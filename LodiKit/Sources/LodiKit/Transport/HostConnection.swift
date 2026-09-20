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

    /// What this connection is for. `.interactive` opens the PTY channel and runs
    /// tmux (the terminal). `.bulk` skips the PTY entirely and serves only SFTP and
    /// transfers, so a saturating upload never contends with keystroke echo on the
    /// terminal's TCP connection (docs/specs/transport-v0.1.md, v0.2 note: bulk
    /// transfers measured +18 ms echo when multiplexed onto the PTY link). It is a
    /// second *instance* of this class — same handshake, auth, keepalive and
    /// dead-link detection — not a second design.
    public enum Role: Sendable { case interactive, bulk }

    /// Fan-out of remote output. Add a sink (the terminal view) any time.
    public let broadcaster = PaneOutputBroadcaster()
    public let pane: PaneID

    private let host: Host
    private let role: Role
    private let keyStore: SSHKeyStore
    private let agentSocketPath: String?
    private let tmuxSession: String
    private let agentComment: String
    private let onState: @Sendable (State) -> Void

    private let lock = NSLock()
    private var inputQueue: [UInt8] = []
    private var pendingSize: (Int32, Int32)?
    /// SFTP operations to run on the loop thread (the only thread that may touch
    /// the libssh2 session). Each closure gets the SFTP handle (nil if it could not
    /// be opened), the session and the socket, and resumes its own continuation.
    private var sftpQueue: [(OpaquePointer?, OpaquePointer, Int32) -> Void] = []
    /// New transfer requests to start, and ids the caller asked to cancel — both
    /// drained by the loop. One chunk moves per loop iteration so a big transfer
    /// never starves keystroke echo.
    private var transferRequests: [TransferRequest] = []
    private var cancelledTransfers: Set<UUID> = []

    /// Bytes moved per loop iteration. The PTY and SFTP channels share one TCP
    /// connection, so transfer bytes contend with keystroke echo.
    static let transferChunk = 32 * 1024
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
        role: Role = .interactive,
        keyStore: SSHKeyStore = SSHKeyStore(),
        agentSocketPath: String? = nil,
        tmuxSession: String? = nil,
        agentComment: String = "lodistudios",
        cols: Int32 = 80,
        rows: Int32 = 24,
        onState: @escaping @Sendable (State) -> Void = { _ in }
    ) {
        self.host = host
        self.role = role
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
        thread.name = role == .bulk ? "ssh-bulk" : "ssh-terminal"
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

        // Bulk role: no PTY, no tmux — the session carries only SFTP and transfers.
        // Same handshake/auth/keepalive above; the loop drains transfers and its
        // defer fails anything in flight if the link drops (then loop() reconnects).
        if role == .bulk {
            everConnected = true
            onState(.connected)
            try eventLoop(channel: nil, session: session, sock: sock, agentContext: agentContext)
            withExtendedLifetime(agentContext) {}
            return
        }

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
        channel: OpaquePointer?, session: OpaquePointer, sock: Int32, agentContext: AuthAgentContext
    ) throws {
        var buffer = [Int8](repeating: 0, count: 32_768)
        // SFTP subsystem, opened lazily on the first op and torn down here so any
        // still-queued op fails rather than hangs when the connection ends.
        var sftp: OpaquePointer?
        var transfers: [ActiveTransfer] = []
        defer {
            // Fail anything queued or in flight so callers never hang.
            lock.lock()
            let orphanedSFTP = sftpQueue; sftpQueue = []
            let orphanedReqs = transferRequests; transferRequests = []
            lock.unlock()
            for work in orphanedSFTP { work(nil, session, sock) }
            for req in orphanedReqs { req.completion(.failure(SFTPError.unavailable)) }
            for t in transfers {
                t.close()
                t.req.completion(.failure(SFTPError.failed("connection ended mid-transfer")))
            }
            if let sftp { libssh2_sftp_shutdown(sftp) }
        }

        while true {
            lock.lock()
            let shouldStop = !running
            let input = inputQueue; inputQueue = []
            let size = pendingSize; pendingSize = nil
            let sftpWork = sftpQueue; sftpQueue = []
            let newTransfers = transferRequests; transferRequests = []
            let cancels = cancelledTransfers
            lock.unlock()
            if shouldStop { break }

            var progressed = false
            if let channel, let size {
                _ = libssh2_channel_request_pty_size_ex(channel, size.0, size.1, 0, 0)
                progressed = true
            }
            if let channel, !input.isEmpty {
                writeAll(channel, input, session: session, sock: sock)
                progressed = true
            }

            // Drain SFTP work: open the subsystem on first use, then run each op to
            // completion (they are quick; transfers chunk below).
            if !sftpWork.isEmpty {
                if sftp == nil { sftp = Self.openSFTP(session, sock) }
                for work in sftpWork { work(sftp, session, sock) }
                progressed = true
            }

            // Transfers: start new ones, then move ONE chunk per active transfer per
            // iteration — the PTY is serviced between chunks, so echo stays snappy.
            if !newTransfers.isEmpty || !transfers.isEmpty {
                if sftp == nil { sftp = Self.openSFTP(session, sock) }
                if let sftp {
                    for req in newTransfers {
                        if let active = Self.startTransfer(req, sftp: sftp, session: session, sock: sock) {
                            transfers.append(active)
                        }
                    }
                    var stillActive: [ActiveTransfer] = []
                    for t in transfers {
                        if cancels.contains(t.req.id) {
                            Self.cancelTransfer(t, sftp: sftp, session: session, sock: sock)
                            progressed = true
                            continue
                        }
                        switch Self.step(t, session: session, sock: sock) {
                        case .moved:        t.req.progress(t.transferred, t.total); progressed = true; stillActive.append(t)
                        case .again:        stillActive.append(t)
                        case .done:         t.close(); t.req.progress(t.total, t.total); t.req.completion(.success(())); progressed = true
                        case .failed(let e): t.close(); t.req.completion(.failure(e)); progressed = true
                        }
                    }
                    transfers = stillActive
                    if !cancels.isEmpty { lock.lock(); cancelledTransfers.subtract(cancels); lock.unlock() }
                } else {
                    for req in newTransfers { req.completion(.failure(SFTPError.unavailable)) }
                }
            }

            // Service any forwarded auth-agent channels (git push / ssh greenflash
            // inside tmux reaching this app's agent). Only the interactive PTY link
            // forwards the agent; the bulk link opens no such channels.
            if channel != nil,
               AuthAgentForwarding.service(agentContext, session: session, sock: sock) { progressed = true }

            if let channel {
                let n = libssh2_channel_read_ex(channel, 0, &buffer, buffer.count)
                if n > 0 {
                    let bytes = buffer.prefix(n).map { UInt8(bitPattern: $0) }
                    broadcaster.broadcast(PaneChunk(pane: pane, bytes: bytes))
                    progressed = true
                } else if n < 0 && n != LIBSSH2_ERROR_EAGAIN {
                    throw SSHSession.Failure.channel("read \(n)")   // dropped connection → reconnect
                }

                if libssh2_channel_eof(channel) == 1 { break }      // clean detach
            }

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

// MARK: - SFTP (a second client on the same connection)

extension HostConnection {
    public enum SFTPError: Error, Sendable, CustomStringConvertible {
        case unavailable
        case cancelled
        case failed(String)
        public var description: String {
            switch self {
            case .unavailable: "sftp not available (connection down)"
            case .cancelled: "transfer cancelled"
            case .failed(let m): "sftp: \(m)"
            }
        }
    }

    /// List a directory (excludes `.` and `..`), directories first then by name.
    public func list(_ path: String) async throws -> [RemoteFile] {
        try await run { sftp, session, sock in try Self.sftpList(sftp, path: path, session: session, sock: sock) }
    }

    public func stat(_ path: String) async throws -> RemoteFile {
        try await run { sftp, session, sock in try Self.sftpStat(sftp, path: path, session: session, sock: sock) }
    }

    public func makeDirectory(_ path: String) async throws {
        try await run { sftp, session, sock in try Self.sftpMkdir(sftp, path: path, session: session, sock: sock) }
    }

    public func rename(_ from: String, to: String) async throws {
        try await run { sftp, session, sock in try Self.sftpRename(sftp, from: from, to: to, session: session, sock: sock) }
    }

    public func remove(_ path: String, isDirectory: Bool) async throws {
        try await run { sftp, session, sock in try Self.sftpRemove(sftp, path: path, isDirectory: isDirectory, session: session, sock: sock) }
    }

    /// Enqueue SFTP work onto the loop and await its result.
    private func run<T: Sendable>(
        _ body: @escaping @Sendable (OpaquePointer, OpaquePointer, Int32) throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
            lock.lock()
            sftpQueue.append { sftp, session, sock in
                guard let sftp else { cont.resume(throwing: SFTPError.unavailable); return }
                do { cont.resume(returning: try body(sftp, session, sock)) }
                catch { cont.resume(throwing: error) }
            }
            lock.unlock()
            wake()
        }
    }

    // MARK: SFTP primitives (run on the loop thread only)

    /// Open the SFTP subsystem on the session, pumping EAGAIN. nil on failure.
    static func openSFTP(_ session: OpaquePointer, _ sock: Int32) -> OpaquePointer? {
        var handle: OpaquePointer?
        repeat {
            handle = libssh2_sftp_init(session)
            if handle == nil {
                if libssh2_session_last_errno(session) == LIBSSH2_ERROR_EAGAIN { SSHSession.waitSocket(sock, session); continue }
                return nil
            }
        } while handle == nil
        return handle
    }

    static func sftpList(_ sftp: OpaquePointer, path: String, session: OpaquePointer, sock: Int32) throws -> [RemoteFile] {
        var handle: OpaquePointer?
        repeat {
            handle = path.withCString {
                libssh2_sftp_open_ex(sftp, $0, UInt32(path.utf8.count), 0, 0, LIBSSH2_SFTP_OPENDIR)
            }
            if handle == nil {
                if libssh2_session_last_errno(session) == LIBSSH2_ERROR_EAGAIN { SSHSession.waitSocket(sock, session); continue }
                throw SFTPError.failed("opendir \(path)")
            }
        } while handle == nil
        defer { _ = SSHSession.retry(session, sock) { libssh2_sftp_close_handle(handle) } }

        var files: [RemoteFile] = []
        var nameBuffer = [Int8](repeating: 0, count: 1024)
        while true {
            var attrs = LIBSSH2_SFTP_ATTRIBUTES()
            let rc = libssh2_sftp_readdir_ex(handle, &nameBuffer, nameBuffer.count, nil, 0, &attrs)
            if rc == Int(LIBSSH2_ERROR_EAGAIN) { SSHSession.waitSocket(sock, session); continue }
            if rc <= 0 { break }   // 0 = end of directory
            let name = String(decoding: nameBuffer.prefix(Int(rc)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if name == "." || name == ".." { continue }
            let childPath = path.hasSuffix("/") ? path + name : "\(path)/\(name)"
            files.append(RemoteFile(
                name: name,
                path: childPath,
                size: attrs.filesize,
                modified: Date(timeIntervalSince1970: Double(attrs.mtime)),
                mode: UInt32(truncatingIfNeeded: attrs.permissions)
            ))
        }
        files.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.lowercased() < b.name.lowercased()
        }
        return files
    }

    static func sftpStat(_ sftp: OpaquePointer, path: String, session: OpaquePointer, sock: Int32) throws -> RemoteFile {
        var attrs = LIBSSH2_SFTP_ATTRIBUTES()
        let rc = SSHSession.retry(session, sock) {
            path.withCString { libssh2_sftp_stat_ex(sftp, $0, UInt32(path.utf8.count), 0, &attrs) }
        }
        guard rc == 0 else { throw SFTPError.failed("stat \(path) (\(rc))") }
        let name = (path as NSString).lastPathComponent
        return RemoteFile(
            name: name, path: path, size: attrs.filesize,
            modified: Date(timeIntervalSince1970: Double(attrs.mtime)),
            mode: UInt32(truncatingIfNeeded: attrs.permissions)
        )
    }

    static func sftpMkdir(_ sftp: OpaquePointer, path: String, session: OpaquePointer, sock: Int32) throws {
        let rc = SSHSession.retry(session, sock) {
            path.withCString { libssh2_sftp_mkdir_ex(sftp, $0, UInt32(path.utf8.count), 0o755) }
        }
        guard rc == 0 else { throw SFTPError.failed("mkdir \(path) (\(rc))") }
    }

    static func sftpRename(_ sftp: OpaquePointer, from: String, to: String, session: OpaquePointer, sock: Int32) throws {
        let flags = Int(LIBSSH2_SFTP_RENAME_OVERWRITE | LIBSSH2_SFTP_RENAME_ATOMIC | LIBSSH2_SFTP_RENAME_NATIVE)
        let rc = SSHSession.retry(session, sock) {
            from.withCString { f in
                to.withCString { t in
                    libssh2_sftp_rename_ex(sftp, f, UInt32(from.utf8.count), t, UInt32(to.utf8.count), flags)
                }
            }
        }
        guard rc == 0 else { throw SFTPError.failed("rename \(from) → \(to) (\(rc))") }
    }

    static func sftpRemove(_ sftp: OpaquePointer, path: String, isDirectory: Bool, session: OpaquePointer, sock: Int32) throws {
        let rc = SSHSession.retry(session, sock) {
            path.withCString {
                isDirectory
                    ? libssh2_sftp_rmdir_ex(sftp, $0, UInt32(path.utf8.count))
                    : libssh2_sftp_unlink_ex(sftp, $0, UInt32(path.utf8.count))
            }
        }
        guard rc == 0 else { throw SFTPError.failed("remove \(path) (\(rc))") }
    }
}

// MARK: - Transfers (chunked, one step per loop iteration)

public enum TransferDirection: Sendable { case upload, download }

/// A queued transfer request. The closures are called from the loop thread; the
/// app wraps them to hop to the main actor.
struct TransferRequest {
    let id: UUID
    let direction: TransferDirection
    let local: URL
    let remote: String
    let progress: @Sendable (UInt64, UInt64) -> Void
    let completion: @Sendable (Result<Void, Error>) -> Void
}

/// In-flight transfer state; touched only on the loop thread.
private final class ActiveTransfer {
    let req: TransferRequest
    let handle: OpaquePointer      // sftp file handle
    let file: FileHandle           // local: reading (upload) or writing (download)
    let total: UInt64
    var transferred: UInt64 = 0
    var uploadPending: [UInt8] = []
    var uploadOffset = 0

    init(req: TransferRequest, handle: OpaquePointer, file: FileHandle, total: UInt64) {
        self.req = req; self.handle = handle; self.file = file; self.total = total
    }
    func close() {
        libssh2_sftp_close_handle(handle)
        try? file.close()
    }
}

private enum StepOutcome { case moved, again, done, failed(Error) }

extension HostConnection {
    /// Queue an upload of a local file to a remote path.
    @discardableResult
    public func upload(
        local: URL, to remote: String, id: UUID = UUID(),
        progress: @escaping @Sendable (UInt64, UInt64) -> Void = { _, _ in },
        completion: @escaping @Sendable (Result<Void, Error>) -> Void = { _ in }
    ) -> UUID {
        enqueueTransfer(TransferRequest(id: id, direction: .upload, local: local, remote: remote,
                                        progress: progress, completion: completion))
        return id
    }

    /// Queue a download of a remote path to a local file.
    @discardableResult
    public func download(
        remote: String, to local: URL, id: UUID = UUID(),
        progress: @escaping @Sendable (UInt64, UInt64) -> Void = { _, _ in },
        completion: @escaping @Sendable (Result<Void, Error>) -> Void = { _ in }
    ) -> UUID {
        enqueueTransfer(TransferRequest(id: id, direction: .download, local: local, remote: remote,
                                        progress: progress, completion: completion))
        return id
    }

    public func cancelTransfer(_ id: UUID) {
        lock.lock(); cancelledTransfers.insert(id); lock.unlock()
        wake()
    }

    private func enqueueTransfer(_ req: TransferRequest) {
        lock.lock(); transferRequests.append(req); lock.unlock()
        wake()
    }

    // MARK: primitives (loop thread only)

    static func openFile(_ sftp: OpaquePointer, _ path: String, flags: UInt, mode: Int,
                         session: OpaquePointer, sock: Int32) -> OpaquePointer? {
        var handle: OpaquePointer?
        repeat {
            handle = path.withCString {
                libssh2_sftp_open_ex(sftp, $0, UInt32(path.utf8.count), flags, mode, LIBSSH2_SFTP_OPENFILE)
            }
            if handle == nil {
                if libssh2_session_last_errno(session) == LIBSSH2_ERROR_EAGAIN { SSHSession.waitSocket(sock, session); continue }
                return nil
            }
        } while handle == nil
        return handle
    }

    fileprivate static func startTransfer(_ req: TransferRequest, sftp: OpaquePointer,
                                          session: OpaquePointer, sock: Int32) -> ActiveTransfer? {
        switch req.direction {
        case .upload:
            guard let file = try? FileHandle(forReadingFrom: req.local) else {
                req.completion(.failure(SFTPError.failed("open local \(req.local.path)"))); return nil
            }
            let total = ((try? FileManager.default.attributesOfItem(atPath: req.local.path))?[.size] as? NSNumber)?.uint64Value ?? 0
            let flags = UInt(LIBSSH2_FXF_WRITE | LIBSSH2_FXF_CREAT | LIBSSH2_FXF_TRUNC)
            guard let handle = openFile(sftp, req.remote, flags: flags, mode: 0o644, session: session, sock: sock) else {
                try? file.close(); req.completion(.failure(SFTPError.failed("open remote \(req.remote)"))); return nil
            }
            return ActiveTransfer(req: req, handle: handle, file: file, total: total)
        case .download:
            let total = (try? sftpStat(sftp, path: req.remote, session: session, sock: sock).size) ?? 0
            guard let handle = openFile(sftp, req.remote, flags: UInt(LIBSSH2_FXF_READ), mode: 0, session: session, sock: sock) else {
                req.completion(.failure(SFTPError.failed("open remote \(req.remote)"))); return nil
            }
            FileManager.default.createFile(atPath: req.local.path, contents: nil)
            guard let file = try? FileHandle(forWritingTo: req.local) else {
                libssh2_sftp_close_handle(handle); req.completion(.failure(SFTPError.failed("open local \(req.local.path)"))); return nil
            }
            return ActiveTransfer(req: req, handle: handle, file: file, total: total)
        }
    }

    fileprivate static func step(_ t: ActiveTransfer, session: OpaquePointer, sock: Int32) -> StepOutcome {
        switch t.req.direction {
        case .download:
            var buffer = [Int8](repeating: 0, count: transferChunk)
            let n = libssh2_sftp_read(t.handle, &buffer, buffer.count)
            if n == Int(LIBSSH2_ERROR_EAGAIN) { return .again }
            if n == 0 { return .done }
            if n < 0 { return .failed(SFTPError.failed("read \(n)")) }
            do { try t.file.write(contentsOf: Data(bytes: buffer, count: n)) }
            catch { return .failed(SFTPError.failed("local write")) }
            t.transferred += UInt64(n)
            return .moved
        case .upload:
            if t.uploadPending.isEmpty {
                let data = t.file.readData(ofLength: transferChunk)
                if data.isEmpty { return .done }
                t.uploadPending = [UInt8](data); t.uploadOffset = 0
            }
            let remaining = t.uploadPending.count - t.uploadOffset
            let n = t.uploadPending.withUnsafeBytes { raw -> Int in
                let base = raw.bindMemory(to: Int8.self).baseAddress! + t.uploadOffset
                return libssh2_sftp_write(t.handle, base, remaining)
            }
            if n == Int(LIBSSH2_ERROR_EAGAIN) { return .again }
            if n < 0 { return .failed(SFTPError.failed("write \(n)")) }
            t.uploadOffset += n
            t.transferred += UInt64(n)
            if t.uploadOffset >= t.uploadPending.count { t.uploadPending = []; t.uploadOffset = 0 }
            return n > 0 ? .moved : .again
        }
    }

    fileprivate static func cancelTransfer(_ t: ActiveTransfer, sftp: OpaquePointer,
                                           session: OpaquePointer, sock: Int32) {
        t.close()
        switch t.req.direction {
        case .download:
            // Keep the partial bytes but mark them clearly.
            let partial = t.req.local.appendingPathExtension("partial")
            try? FileManager.default.removeItem(at: partial)
            try? FileManager.default.moveItem(at: t.req.local, to: partial)
        case .upload:
            // Leave the partial remote file clearly marked, never a truncated real name.
            try? sftpRename(sftp, from: t.req.remote, to: t.req.remote + ".partial", session: session, sock: sock)
        }
        t.req.completion(.failure(SFTPError.cancelled))
    }
}
