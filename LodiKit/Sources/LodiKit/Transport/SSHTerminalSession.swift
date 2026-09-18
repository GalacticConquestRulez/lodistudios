import Foundation
import Darwin
import CLibSSH2

/// A live, interactive SSH session: a PTY channel running tmux, its output fanned
/// through a `PaneOutputBroadcaster` and its input taken behind `PaneBackend`
/// (docs/specs/transport-v0.1.md, milestone 3). Reuses SSHSession's proven
/// connect / host-key / agent-auth path.
///
/// libssh2 is single-threaded per session, so one dedicated thread owns the
/// channel: it polls for output and drains queued input and resizes. Input arrives
/// from any thread through a lock; output is broadcast from the loop thread and
/// sinks (e.g. the terminal view) hop to the main thread themselves.
public final class SSHTerminalSession: @unchecked Sendable, PaneBackend {
    /// Fan-out of remote output. Add the terminal view as a sink before `start()`.
    public let broadcaster = PaneOutputBroadcaster()
    public let pane: PaneID

    private let host: Host
    private let keyStore: SSHKeyStore
    private let agentSocketPath: String?
    private let initialCols: Int32
    private let initialRows: Int32
    private let onClosed: @Sendable (String?) -> Void

    private let lock = NSLock()
    private var inputQueue: [UInt8] = []
    private var pendingSize: (Int32, Int32)?
    private var running = true

    public init(
        host: Host,
        keyStore: SSHKeyStore = SSHKeyStore(),
        agentSocketPath: String? = nil,
        cols: Int32 = 80,
        rows: Int32 = 24,
        onClosed: @escaping @Sendable (String?) -> Void = { _ in }
    ) {
        self.host = host
        self.keyStore = keyStore
        self.agentSocketPath = agentSocketPath
        self.initialCols = cols
        self.initialRows = rows
        self.onClosed = onClosed
        self.pane = PaneID(host.alias)
    }

    public func start() {
        let thread = Thread { [weak self] in self?.loop() }
        thread.name = "ssh-terminal"
        thread.stackSize = 2 << 20
        thread.start()
    }

    public func stop() {
        lock.lock(); running = false; lock.unlock()
    }

    /// Raw bytes to the remote (keystrokes). Thread-safe.
    public func sendBytes(_ bytes: [UInt8]) {
        lock.lock(); inputQueue.append(contentsOf: bytes); lock.unlock()
    }

    public func resize(cols: Int32, rows: Int32) {
        lock.lock(); pendingSize = (cols, rows); lock.unlock()
    }

    // PaneBackend seam — so a PaneWriter policy can gate input later.
    public func send(_ input: PaneInput, to pane: PaneID) {
        switch input {
        case .text(let text): sendBytes(Array(text.utf8))
        case .keys(let keys): sendBytes(Array(keys.utf8))
        }
    }

    // MARK: - The single-threaded libssh2 loop

    private func loop() {
        _ = libssh2_init(0)
        defer { libssh2_exit() }
        do {
            let sock = try SSHSession.openSocket(host: host.hostName, port: host.port)
            defer { close(sock) }

            guard let session = libssh2_session_init_ex(nil, nil, nil, nil) else {
                throw SSHSession.Failure.handshake("session init failed")
            }
            defer {
                libssh2_session_disconnect_ex(session, SSH_DISCONNECT_BY_APPLICATION, "bye", "")
                libssh2_session_free(session)
            }
            libssh2_session_set_blocking(session, 0)

            guard SSHSession.retry(session, sock, { libssh2_session_handshake(session, sock) }) == 0 else {
                throw SSHSession.Failure.handshake(SSHSession.lastError(session))
            }
            try SSHSession.verifyHostKey(session, host: host)
            if let agentSocketPath {
                try SSHSession.authenticateViaAgent(session, sock, socketPath: agentSocketPath, user: host.user)
            } else {
                throw SSHSession.Failure.authFailed("terminal session requires the agent")
            }

            var channel: OpaquePointer?
            repeat {
                channel = libssh2_channel_open_ex(session, "session", 7, 2 * 1024 * 1024, 32_768, nil, 0)
                if channel == nil {
                    if libssh2_session_last_errno(session) == LIBSSH2_ERROR_EAGAIN {
                        SSHSession.waitSocket(sock, session); continue
                    }
                    throw SSHSession.Failure.channel(SSHSession.lastError(session))
                }
            } while channel == nil
            defer {
                libssh2_channel_close(channel)
                libssh2_channel_free(channel)
            }

            let ptyResult = "xterm-256color".withCString { term in
                SSHSession.retry(session, sock) {
                    libssh2_channel_request_pty_ex(channel, term, 14, nil, 0, initialCols, initialRows, 0, 0)
                }
            }
            guard ptyResult == 0 else { throw SSHSession.Failure.channel("pty: \(SSHSession.lastError(session))") }

            let command = "tmux new -A -s lodi"
            guard SSHSession.retry(session, sock, {
                libssh2_channel_process_startup(channel, "exec", 4, command, UInt32(command.utf8.count))
            }) == 0 else {
                throw SSHSession.Failure.channel("exec: \(SSHSession.lastError(session))")
            }

            try eventLoop(channel: channel!, session: session, sock: sock)
            onClosed(nil)
        } catch {
            onClosed("\(error)")
        }
    }

    private func eventLoop(channel: OpaquePointer, session: OpaquePointer, sock: Int32) throws {
        var buffer = [Int8](repeating: 0, count: 32_768)
        while true {
            lock.lock()
            let shouldStop = !running
            let input = inputQueue; inputQueue = []
            let size = pendingSize; pendingSize = nil
            lock.unlock()
            if shouldStop { break }

            var progressed = false
            if let size {
                _ = libssh2_channel_request_pty_size_ex(channel, size.0, size.1, 0, 0)
                progressed = true
            }
            if !input.isEmpty {
                writeAll(channel, input)
                progressed = true
            }

            let n = libssh2_channel_read_ex(channel, 0, &buffer, buffer.count)
            if n > 0 {
                let bytes = buffer.prefix(n).map { UInt8(bitPattern: $0) }
                broadcaster.broadcast(PaneChunk(pane: pane, bytes: bytes))
                progressed = true
            } else if n < 0 && n != LIBSSH2_ERROR_EAGAIN {
                break
            }

            if libssh2_channel_eof(channel) == 1 { break }
            if !progressed { SSHSession.waitSocket(sock, session) }
        }
    }

    private func writeAll(_ channel: OpaquePointer, _ bytes: [UInt8]) {
        bytes.withUnsafeBytes { raw in
            let base = raw.bindMemory(to: UInt8.self).baseAddress!
            var sent = 0
            while sent < raw.count {
                let n = libssh2_channel_write_ex(channel, 0, base + sent, raw.count - sent)
                if n == LIBSSH2_ERROR_EAGAIN { continue }
                if n <= 0 { break }
                sent += Int(n)
            }
        }
    }
}
