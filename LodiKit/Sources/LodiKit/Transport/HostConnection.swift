import Foundation
import Darwin
import CLibSSH2

/// A per-host connection: one libssh2 session, its event loop, keepalives,
/// reconnect and the forwarded agent (docs/specs/transport-v0.1.md, milestones
/// 3–6). Its first client is the interactive PTY channel running tmux, whose
/// output is fanned through a `PaneOutputBroadcaster` and whose input arrives
/// behind `PaneBackend`; the SFTP subsystem joins as a second client on the same
/// loop (v0.2), so Files and the terminal share one login.
///
/// The dedicated loop reconnects on its own: when the channel ends (a tmux detach,
/// a dropped network), it reports `.disconnected` and retries with backoff, then
/// re-runs `tmux new -A -s <name>` so scrollback comes back from the droplet, never
/// from the app's memory. Keepalives make a *dead* link surface within ~30 s
/// instead of only when a write fails. A self-pipe keeps keystrokes lag-free.
///
/// Note: because any disconnect reattaches, a deliberate tmux detach (Ctrl-b d)
/// reattaches within a second — leaving the session is done by closing the tab,
/// not by detaching from inside it.
public final class HostConnection: @unchecked Sendable, PaneBackend {
    public enum State: Sendable, Equatable {
        case connecting
        case connected
        case disconnected(reason: String?)
    }

    /// Fan-out of remote output. Add a sink (the terminal view) any time.
    public let broadcaster = PaneOutputBroadcaster()
    public let pane: PaneID

    private let host: Host
    private let keyStore: SSHKeyStore
    private let agentSocketPath: String?
    private let tmuxSession: String
    private let agentComment: String
    private let onState: @Sendable (State) -> Void

    private let lock = NSLock()
    private var inputQueue: [UInt8] = []
    private var pendingSize: (Int32, Int32)?
    private var cols: Int32
    private var rows: Int32
    private var running = true
    private var started = false
    /// True once we've connected at least once — so a missing tmux session on a
    /// later attach can be reported as "gone" rather than a normal first attach.
    private var everConnected = false

    /// Self-pipe: [read, write]. Writing a byte wakes the poll in the loop.
    private var wakePipe: [Int32] = [-1, -1]

    public init(
        host: Host,
        keyStore: SSHKeyStore = SSHKeyStore(),
        agentSocketPath: String? = nil,
        tmuxSession: String? = nil,
        agentComment: String = "lodistudios",
        cols: Int32 = 80,
        rows: Int32 = 24,
        onState: @escaping @Sendable (State) -> Void = { _ in }
    ) {
        self.host = host
        self.keyStore = keyStore
        self.agentSocketPath = agentSocketPath
        self.tmuxSession = tmuxSession ?? "lodi-\(host.alias)"
        self.agentComment = agentComment
        self.cols = cols
        self.rows = rows
        self.onState = onState
        self.pane = PaneID(host.alias)

        if pipe(&wakePipe) == 0 {
            _ = fcntl(wakePipe[0], F_SETFL, fcntl(wakePipe[0], F_GETFL, 0) | O_NONBLOCK)
        }
    }

    /// Start the reconnecting loop once. Safe to call repeatedly.
    public func start() {
        lock.lock()
        guard !started else { lock.unlock(); return }
        started = true
        lock.unlock()

        let thread = Thread { [weak self] in self?.loop() }
        thread.name = "ssh-terminal"
        thread.stackSize = 2 << 20
        thread.start()
    }

    public func stop() {
        lock.lock(); running = false; lock.unlock()
        wake()
    }

    /// Raw bytes to the remote (keystrokes). Thread-safe; wakes the loop at once.
    public func sendBytes(_ bytes: [UInt8]) {
        lock.lock(); inputQueue.append(contentsOf: bytes); lock.unlock()
        wake()
    }

    public func resize(cols: Int32, rows: Int32) {
        lock.lock(); self.cols = cols; self.rows = rows; pendingSize = (cols, rows); lock.unlock()
        wake()
    }

    // PaneBackend seam — so a PaneWriter policy can gate input.
    public func send(_ input: PaneInput, to pane: PaneID) {
        switch input {
        case .text(let text):  sendBytes(Array(text.utf8))
        case .keys(let keys):  sendBytes(Array(keys.utf8))
        case .bytes(let bytes): sendBytes(bytes)
        }
    }

    private func wake() {
        guard wakePipe[1] >= 0 else { return }
        var byte: UInt8 = 1
        _ = write(wakePipe[1], &byte, 1)
    }

    private func isRunning() -> Bool {
        lock.lock(); defer { lock.unlock() }; return running
    }

    // MARK: - Reconnecting loop

    private func loop() {
        LibSSH2.ensure()
        defer {
            if wakePipe[0] >= 0 { close(wakePipe[0]) }
            if wakePipe[1] >= 0 { close(wakePipe[1]) }
        }

        var backoff: Int32 = 0
        while isRunning() {
            onState(.connecting)
            do {
                try connectAndServe()          // reports .connected; returns on detach/EOF
                onState(.disconnected(reason: nil))
            } catch {
                onState(.disconnected(reason: "\(error)"))
            }
            guard isRunning() else { break }
            backoff = min(max(1, backoff * 2), 5)   // 1, 2, 4, 5, 5…
            interruptibleSleep(seconds: backoff)
        }
    }

    private func connectAndServe() throws {
        let sock = try SSHSession.openSocket(host: host.hostName, port: host.port)
        defer { close(sock) }

        // The agent is forwarded into the tmux shell so `git push` / `ssh greenflash`
        // inside the session reach this app's agent (M6). The context is reached
        // from the auth-agent callback via the session abstract.
        let agentContext = AuthAgentContext(responder: SSHAgentResponder(
            publicKeyBlob: try keyStore.publicKeyBlob(),
            comment: agentComment,
            sign: { try self.keyStore.agentSignature($0) }
        ))
        let abstract = Unmanaged.passUnretained(agentContext).toOpaque()

        guard let session = libssh2_session_init_ex(nil, nil, nil, abstract) else {
            throw SSHSession.Failure.handshake("session init failed")
        }
        defer {
            libssh2_session_disconnect_ex(session, SSH_DISCONNECT_BY_APPLICATION, "bye", "")
            libssh2_session_free(session)
        }
        libssh2_session_set_blocking(session, 0)
        AuthAgentForwarding.registerCallback(on: session)

        guard SSHSession.retry(session, sock, { libssh2_session_handshake(session, sock) }) == 0 else {
            throw SSHSession.Failure.handshake(SSHSession.lastError(session))
        }
        // Ask the server for a keepalive every 15s (want_reply), so a dead link
        // errors a send within ~30s rather than hanging until the next write.
        libssh2_keepalive_config(session, 1, 15)

        try SSHSession.verifyHostKey(session, host: host)
        guard let agentSocketPath else {
            throw SSHSession.Failure.authFailed("terminal session requires the agent")
        }
        try SSHSession.authenticateViaAgent(session, sock, socketPath: agentSocketPath, user: host.user)

        // On a reconnect, if the tmux session is gone the server restarted; say so
        // once rather than silently showing a fresh empty pane (spec + M4 review).
        if everConnected, !hasSession(named: tmuxSession, session: session, sock: sock) {
            onState(.disconnected(reason: "tmux session '\(tmuxSession)' is gone — previous output not available"))
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

        // Forward the agent for this channel so the remote shell can reach it.
        _ = SSHSession.retry(session, sock) { libssh2_channel_request_auth_agent(channel) }

        lock.lock(); let startCols = cols; let startRows = rows; lock.unlock()
        let ptyResult = "xterm-256color".withCString { term in
            SSHSession.retry(session, sock) {
                libssh2_channel_request_pty_ex(channel, term, 14, nil, 0, startCols, startRows, 0, 0)
            }
        }
        guard ptyResult == 0 else { throw SSHSession.Failure.channel("pty: \(SSHSession.lastError(session))") }

        // -A attaches an existing session or creates one, so a reconnect brings the
        // droplet's scrollback back; the app never replays it from memory.
        let command = "tmux new -A -s \(tmuxSession)"
        guard SSHSession.retry(session, sock, {
            libssh2_channel_process_startup(channel, "exec", 4, command, UInt32(command.utf8.count))
        }) == 0 else {
            throw SSHSession.Failure.channel("exec: \(SSHSession.lastError(session))")
        }

        everConnected = true
        onState(.connected)
        try eventLoop(channel: channel!, session: session, sock: sock, agentContext: agentContext)
        withExtendedLifetime(agentContext) {}
    }

    /// Exec `tmux has-session` on a throwaway channel; true if the session exists.
    /// Errors are treated as "exists" so we never cry wolf about lost scrollback.
    private func hasSession(named name: String, session: OpaquePointer, sock: Int32) -> Bool {
        guard let channel = openChannel(session, sock) else { return true }
        defer {
            libssh2_channel_close(channel)
            libssh2_channel_free(channel)
        }
        let command = "tmux has-session -t \(name) 2>/dev/null"
        guard SSHSession.retry(session, sock, {
            libssh2_channel_process_startup(channel, "exec", 4, command, UInt32(command.utf8.count))
        }) == 0 else { return true }

        var buffer = [Int8](repeating: 0, count: 1024)
        while true {
            let n = libssh2_channel_read_ex(channel, 0, &buffer, buffer.count)
            if n == LIBSSH2_ERROR_EAGAIN { SSHSession.waitSocket(sock, session); continue }
            if n <= 0 { break }
        }
        _ = SSHSession.retry(session, sock) { libssh2_channel_close(channel) }
        return libssh2_channel_get_exit_status(channel) == 0
    }

    private func openChannel(_ session: OpaquePointer, _ sock: Int32) -> OpaquePointer? {
        var channel: OpaquePointer?
        repeat {
            channel = libssh2_channel_open_ex(session, "session", 7, 2 * 1024 * 1024, 32_768, nil, 0)
            if channel == nil {
                if libssh2_session_last_errno(session) == LIBSSH2_ERROR_EAGAIN {
                    SSHSession.waitSocket(sock, session); continue
                }
                return nil
            }
        } while channel == nil
        return channel
    }

    private func eventLoop(
        channel: OpaquePointer, session: OpaquePointer, sock: Int32, agentContext: AuthAgentContext
    ) throws {
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
                writeAll(channel, input, session: session, sock: sock)
                progressed = true
            }

            // Service any forwarded auth-agent channels (git push / ssh greenflash
            // inside tmux reaching this app's agent).
            if AuthAgentForwarding.service(agentContext, session: session, sock: sock) { progressed = true }

            let n = libssh2_channel_read_ex(channel, 0, &buffer, buffer.count)
            if n > 0 {
                let bytes = buffer.prefix(n).map { UInt8(bitPattern: $0) }
                broadcaster.broadcast(PaneChunk(pane: pane, bytes: bytes))
                progressed = true
            } else if n < 0 && n != LIBSSH2_ERROR_EAGAIN {
                throw SSHSession.Failure.channel("read \(n)")   // dropped connection → reconnect
            }

            if libssh2_channel_eof(channel) == 1 { break }      // clean detach

            // Send a keepalive if one is due; a dead link errors here → reconnect.
            // Its "seconds to next" becomes the poll timeout so we wake to send it.
            var secondsToNext: Int32 = 15
            if libssh2_keepalive_send(session, &secondsToNext) != 0 {
                throw SSHSession.Failure.channel("keepalive failed — link dead")
            }
            if !progressed {
                waitForActivity(sock: sock, session: session, timeoutSeconds: max(1, secondsToNext))
            }
        }
    }

    /// Wait on both the ssh socket (per libssh2's block directions) and the wake
    /// pipe, so queued input is written the instant it arrives, not after a timeout.
    private func waitForActivity(sock: Int32, session: OpaquePointer, timeoutSeconds: Int32) {
        var fds = [
            pollfd(fd: sock, events: 0, revents: 0),
            pollfd(fd: wakePipe[0], events: Int16(POLLIN), revents: 0),
        ]
        let directions = libssh2_session_block_directions(session)
        if directions & LIBSSH2_SESSION_BLOCK_INBOUND != 0 { fds[0].events |= Int16(POLLIN) }
        if directions & LIBSSH2_SESSION_BLOCK_OUTBOUND != 0 { fds[0].events |= Int16(POLLOUT) }
        if fds[0].events == 0 { fds[0].events = Int16(POLLIN) }

        _ = poll(&fds, 2, timeoutSeconds * 1_000)
        drainWake(fds[1].revents)
    }

    /// Sleep up to `seconds`, but return early if stop()/send wakes the pipe.
    private func interruptibleSleep(seconds: Int32) {
        var fd = pollfd(fd: wakePipe[0], events: Int16(POLLIN), revents: 0)
        _ = poll(&fd, 1, seconds * 1_000)
        drainWake(fd.revents)
    }

    private func drainWake(_ revents: Int16) {
        guard revents != 0 else { return }
        var scratch = [UInt8](repeating: 0, count: 64)
        while read(wakePipe[0], &scratch, scratch.count) > 0 {}
    }

    private func writeAll(_ channel: OpaquePointer, _ bytes: [UInt8], session: OpaquePointer, sock: Int32) {
        bytes.withUnsafeBytes { raw in
            let base = raw.bindMemory(to: UInt8.self).baseAddress!
            var sent = 0
            while sent < raw.count {
                let n = libssh2_channel_write_ex(channel, 0, base + sent, raw.count - sent)
                if n == LIBSSH2_ERROR_EAGAIN { SSHSession.waitSocket(sock, session); continue }
                if n <= 0 { break }
                sent += Int(n)
            }
        }
    }
}
