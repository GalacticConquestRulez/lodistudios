import Foundation
import Darwin
import CryptoKit
import CLibSSH2

/// libssh2's global init, exactly once per process. Never `libssh2_exit`: tearing
/// down global state under other live sessions (a second tab, a probe) would crash
/// them (docs/reviews/2026-09-18-transport-m3.md).
enum LibSSH2 {
    private static let ready: Int32 = libssh2_init(0)
    static func ensure() { _ = ready }
}

/// A context handed to the C sign callback through libssh2's `abstract` pointer,
/// since a `@convention(c)` function can capture nothing.
private final class SignContext {
    let keyStore: SSHKeyStore
    var error: Error?
    init(_ keyStore: SSHKeyStore) { self.keyStore = keyStore }
}

/// libssh2 publickey sign callback: sign `data` with the Keychain key and return
/// `mpint(r) || mpint(s)`, malloc'd so libssh2 can free it.
private func lodiSignCallback(
    _ session: OpaquePointer?,
    _ sig: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
    _ sigLen: UnsafeMutablePointer<Int>?,
    _ data: UnsafePointer<UInt8>?,
    _ dataLen: Int,
    _ abstract: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> Int32 {
    guard let sig, let sigLen, let data, let ctxPtr = abstract?.pointee else { return -1 }
    let context = Unmanaged<SignContext>.fromOpaque(ctxPtr).takeUnretainedValue()
    do {
        let blob = try context.keyStore.sign(Data(bytes: data, count: dataLen))
        let out = malloc(blob.count)!.assumingMemoryBound(to: UInt8.self)
        blob.copyBytes(to: out, count: blob.count)
        sig.pointee = out
        sigLen.pointee = blob.count
        return 0
    } catch {
        context.error = error
        return -1
    }
}

/// One SSH connection to a host, over embedded libssh2 with the app as its own
/// signer (docs/specs/transport-v0.1.md, milestone 1). The session is non-blocking
/// from the first call and driven with a socket wait. v0.1 proves connect + auth +
/// one command; the terminal channel (M3) builds on the same session.
///
/// The libssh2 flow is `nonisolated static` — self-contained synchronous work over
/// immutable, Sendable inputs — so it stays clear of Swift's actor-isolation data-
/// race checks around the C `abstract` pointer. The actor serializes calls; when a
/// long-lived session with mutable state arrives at M3 that state becomes isolated.
public actor SSHSession {
    public struct Output: Sendable {
        public let stdout: String
        public let exitStatus: Int32
    }

    public enum Failure: Error, Sendable, CustomStringConvertible {
        case socket(String)
        case handshake(String)
        case hostKeyUnavailable
        case hostKeyMismatch(expected: String, got: String)
        case authFailed(String)
        case channel(String)

        public var description: String {
            switch self {
            case .socket(let m):        "socket: \(m)"
            case .handshake(let m):     "handshake: \(m)"
            case .hostKeyUnavailable:   "host key unavailable"
            case .hostKeyMismatch(let e, let g): "host key mismatch — pinned \(e), got \(g)"
            case .authFailed(let m):    "auth failed: \(m)"
            case .channel(let m):       "channel: \(m)"
            }
        }
    }

    private let host: Host
    private let keyStore: SSHKeyStore
    /// When set, authenticate through the in-app agent at this Unix-socket path
    /// (milestone 2) instead of the direct sign callback (milestone 1).
    private let agentSocketPath: String?
    /// The comment reported for forwarded-agent identities (what `ssh-add -l` shows).
    private let agentComment: String

    public init(
        host: Host,
        keyStore: SSHKeyStore = SSHKeyStore(),
        agentSocketPath: String? = nil,
        agentComment: String = "lodistudios"
    ) {
        self.host = host
        self.keyStore = keyStore
        self.agentSocketPath = agentSocketPath
        self.agentComment = agentComment
    }

    /// Connect, verify the host key, authenticate, run `command`, return its stdout.
    /// `forwardAgent` requests agent forwarding on the channel so a remote shell
    /// can reach this app's agent.
    public func run(_ command: String, forwardAgent: Bool = false) throws -> Output {
        try Self.execute(
            command, host: host, keyStore: keyStore,
            agentSocketPath: agentSocketPath, agentComment: agentComment,
            forwardAgent: forwardAgent
        )
    }

    // MARK: - The blocking libssh2 flow

    private nonisolated static func execute(
        _ command: String, host: Host, keyStore: SSHKeyStore,
        agentSocketPath: String?, agentComment: String, forwardAgent: Bool
    ) throws -> Output {
        LibSSH2.ensure()

        let sock = try openSocket(host: host.hostName, port: host.port)
        defer { close(sock) }

        // For forwarding, a context (reached via the session abstract) collects the
        // forwarded auth-agent channels and answers them with the same responder.
        let context: AuthAgentContext? = forwardAgent
            ? AuthAgentContext(responder: SSHAgentResponder(
                publicKeyBlob: try keyStore.publicKeyBlob(),
                comment: agentComment,
                sign: { try keyStore.agentSignature($0) }))
            : nil
        let abstract = context.map { Unmanaged.passUnretained($0).toOpaque() }

        guard let session = libssh2_session_init_ex(nil, nil, nil, abstract) else {
            throw Failure.handshake("session init failed")
        }
        defer {
            libssh2_session_disconnect_ex(session, SSH_DISCONNECT_BY_APPLICATION, "bye", "")
            libssh2_session_free(session)
        }
        libssh2_session_set_blocking(session, 0)

        if forwardAgent {
            AuthAgentForwarding.registerCallback(on: session)
        }

        let rc = retry(session, sock) { libssh2_session_handshake(session, sock) }
        guard rc == 0 else { throw Failure.handshake(lastError(session)) }

        try verifyHostKey(session, host: host)
        if let agentSocketPath {
            try authenticateViaAgent(session, sock, socketPath: agentSocketPath, user: host.user)
        } else {
            try authenticate(session, sock, host: host, keyStore: keyStore)
        }

        let output = try runExec(
            command, session: session, sock: sock,
            forwardAgent: forwardAgent, context: context
        )
        withExtendedLifetime(context) {}
        return output
    }

    private nonisolated static func runExec(
        _ command: String, session: OpaquePointer, sock: Int32,
        forwardAgent: Bool, context: AuthAgentContext?
    ) throws -> Output {
        var channel: OpaquePointer?
        repeat {
            // LIBSSH2_CHANNEL_WINDOW_DEFAULT / _PACKET_DEFAULT — the arithmetic
            // macros don't import into Swift, so their literal values are inlined.
            channel = libssh2_channel_open_ex(session, "session", 7, 2 * 1024 * 1024, 32_768, nil, 0)
            if channel == nil {
                let err = libssh2_session_last_errno(session)
                if err == LIBSSH2_ERROR_EAGAIN { waitSocket(sock, session); continue }
                throw Failure.channel(lastError(session))
            }
        } while channel == nil
        defer {
            libssh2_channel_close(channel)
            libssh2_channel_free(channel)
        }

        // Request agent forwarding for this channel so a remote shell can reach
        // our agent. Best-effort: if the server declines we still run the command.
        if forwardAgent {
            _ = retry(session, sock) { libssh2_channel_request_auth_agent(channel) }
        }

        let rc = retry(session, sock) {
            libssh2_channel_process_startup(channel, "exec", 4, command, UInt32(command.utf8.count))
        }
        guard rc == 0 else { throw Failure.channel("exec: \(lastError(session))") }

        var stdout = Data()
        var buffer = [Int8](repeating: 0, count: 32_768)
        while true {
            var progressed = false

            let n = libssh2_channel_read_ex(channel, 0, &buffer, buffer.count)
            if n > 0 {
                buffer.withUnsafeBytes {
                    stdout.append($0.bindMemory(to: UInt8.self).baseAddress!, count: n)
                }
                progressed = true
            } else if n < 0 && n != LIBSSH2_ERROR_EAGAIN {
                break   // real read error
            }

            // Service any forwarded auth-agent channels so a remote ssh-add can
            // reach our key while its exec command is still blocked.
            if let context, AuthAgentForwarding.service(context) { progressed = true }

            if libssh2_channel_eof(channel) == 1 && !progressed { break }
            if !progressed { waitSocket(sock, session) }
        }

        _ = retry(session, sock) { libssh2_channel_close(channel) }
        let exitStatus = libssh2_channel_get_exit_status(channel)
        return Output(stdout: String(decoding: stdout, as: UTF8.self), exitStatus: exitStatus)
    }

    // MARK: - Host key

    nonisolated static func verifyHostKey(_ session: OpaquePointer, host: Host) throws {
        var len = 0
        var type: Int32 = 0
        guard let hk = libssh2_session_hostkey(session, &len, &type) else {
            throw Failure.hostKeyUnavailable
        }
        let raw = Data(bytes: hk, count: len)
        let fingerprint = "SHA256:" + Data(SHA256.hash(data: raw))
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")

        // Pinned host: refuse on mismatch. Unpinned: trust on first use (v0.1).
        if let expected = host.hostKeyFingerprintSHA256, expected != fingerprint {
            throw Failure.hostKeyMismatch(expected: expected, got: fingerprint)
        }
    }

    // MARK: - Auth

    private nonisolated static func authenticate(
        _ session: OpaquePointer, _ sock: Int32, host: Host, keyStore: SSHKeyStore
    ) throws {
        let blob = try keyStore.publicKeyBlob()
        let context = SignContext(keyStore)
        let opaque = Unmanaged.passUnretained(context).toOpaque()
        var rc: Int32 = 0

        blob.withUnsafeBytes { blobPtr in
            let base = blobPtr.bindMemory(to: UInt8.self).baseAddress!
            host.user.withCString { userPtr in
                var abstract: UnsafeMutableRawPointer? = opaque
                repeat {
                    rc = libssh2_userauth_publickey(
                        session, userPtr, base, blob.count, lodiSignCallback, &abstract
                    )
                    if rc == LIBSSH2_ERROR_EAGAIN { waitSocket(sock, session) }
                } while rc == LIBSSH2_ERROR_EAGAIN
            }
        }
        withExtendedLifetime(context) {}

        if rc != 0 {
            if let signError = context.error { throw Failure.authFailed("sign: \(signError)") }
            throw Failure.authFailed(lastError(session))
        }
    }

    /// Authenticate through the in-app agent: libssh2 connects to our Unix socket
    /// as an agent client, lists identities, and signs the challenge via the agent
    /// (milestone 2) — the private key stays behind the agent, never in libssh2.
    nonisolated static func authenticateViaAgent(
        _ session: OpaquePointer, _ sock: Int32, socketPath: String, user: String
    ) throws {
        guard let agent = libssh2_agent_init(session) else {
            throw Failure.authFailed("agent init failed")
        }
        defer { libssh2_agent_free(agent) }

        socketPath.withCString { libssh2_agent_set_identity_path(agent, $0) }
        guard retry(session, sock, { libssh2_agent_connect(agent) }) == 0 else {
            throw Failure.authFailed("agent connect: \(lastError(session))")
        }
        defer { libssh2_agent_disconnect(agent) }

        guard retry(session, sock, { libssh2_agent_list_identities(agent) }) == 0 else {
            throw Failure.authFailed("agent list: \(lastError(session))")
        }

        var identity: UnsafeMutablePointer<libssh2_agent_publickey>?
        var authenticated = false
        while true {
            let getResult = libssh2_agent_get_identity(agent, &identity, identity)
            if getResult == 1 { break }              // no more identities
            if getResult < 0 { throw Failure.authFailed("agent get identity") }
            guard let id = identity else { break }
            if retry(session, sock, { libssh2_agent_userauth(agent, user, id) }) == 0 {
                authenticated = true
                break
            }
        }
        guard authenticated else { throw Failure.authFailed("agent userauth: \(lastError(session))") }
    }

    // MARK: - Socket + poll

    nonisolated static func openSocket(host: String, port: Int) throws -> Int32 {
        var hints = addrinfo(
            ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil
        )
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &info) == 0, let list = info else {
            throw Failure.socket("cannot resolve \(host)")
        }
        defer { freeaddrinfo(info) }

        var node: UnsafeMutablePointer<addrinfo>? = list
        while let current = node {
            let fd = socket(current.pointee.ai_family, current.pointee.ai_socktype, current.pointee.ai_protocol)
            if fd >= 0 {
                if connect(fd, current.pointee.ai_addr, current.pointee.ai_addrlen) == 0 {
                    _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK)
                    return fd
                }
                close(fd)
            }
            node = current.pointee.ai_next
        }
        throw Failure.socket("cannot connect to \(host):\(port)")
    }

    nonisolated static func waitSocket(_ sock: Int32, _ session: OpaquePointer) {
        var pfd = pollfd(fd: sock, events: 0, revents: 0)
        let directions = libssh2_session_block_directions(session)
        if directions & LIBSSH2_SESSION_BLOCK_INBOUND != 0 { pfd.events |= Int16(POLLIN) }
        if directions & LIBSSH2_SESSION_BLOCK_OUTBOUND != 0 { pfd.events |= Int16(POLLOUT) }
        if pfd.events == 0 { pfd.events = Int16(POLLIN) }
        _ = poll(&pfd, 1, 5_000)
    }

    nonisolated static func retry(
        _ session: OpaquePointer, _ sock: Int32, _ op: () -> Int32
    ) -> Int32 {
        var rc = op()
        while rc == LIBSSH2_ERROR_EAGAIN {
            waitSocket(sock, session)
            rc = op()
        }
        return rc
    }

    nonisolated static func lastError(_ session: OpaquePointer) -> String {
        var message: UnsafeMutablePointer<CChar>?
        var length: Int32 = 0
        let code = libssh2_session_last_error(session, &message, &length, 0)
        let text = message.map { String(cString: $0) } ?? ""
        return "\(code) \(text)"
    }
}
