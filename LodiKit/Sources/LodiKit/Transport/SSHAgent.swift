import Foundation
import Darwin

/// The app as its own SSH agent (docs/specs/transport-v0.1.md, milestone 2): a
/// Unix-domain socket in the container speaking the OpenSSH agent protocol, backed
/// by the Keychain key. libssh2 connects to it as an agent client for auth, and
/// the same socket answers requests forwarded back from a remote shell.
///
/// The wire handling lives in `SSHAgentResponder` (pure, unit-tested); this class
/// only frames it over the socket.
public enum SSHAgentProtocol {
    // Requests (client → agent)
    static let requestIdentities: UInt8 = 11
    static let signRequest: UInt8 = 13
    static let extensionRequest: UInt8 = 27
    // Replies (agent → client)
    static let failure: UInt8 = 5
    static let success: UInt8 = 6
    static let identitiesAnswer: UInt8 = 12
    static let signResponse: UInt8 = 14
}

/// Reads SSH wire primitives from a byte buffer.
struct SSHWireReader {
    let bytes: [UInt8]
    var offset = 0
    init(_ data: Data) { bytes = [UInt8](data) }

    mutating func byte() -> UInt8? {
        guard offset < bytes.count else { return nil }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func uint32() -> UInt32? {
        guard offset + 4 <= bytes.count else { return nil }
        defer { offset += 4 }
        return bytes[offset...].prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    mutating func string() -> Data? {
        guard let length = uint32(), offset + Int(length) <= bytes.count else { return nil }
        defer { offset += Int(length) }
        return Data(bytes[offset..<offset + Int(length)])
    }
}

/// The pure protocol logic: request payload in, response payload out. No sockets,
/// so it is fully unit-testable with a fake signer.
public struct SSHAgentResponder: Sendable {
    public let publicKeyBlob: Data
    public let comment: String
    public let sign: @Sendable (Data) throws -> Data
    /// Session ids recorded from session-bind@openssh.com (enforcement is v0.4).
    public private(set) var boundSessions: [Data] = []

    public init(
        publicKeyBlob: Data,
        comment: String,
        sign: @escaping @Sendable (Data) throws -> Data
    ) {
        self.publicKeyBlob = publicKeyBlob
        self.comment = comment
        self.sign = sign
    }

    public mutating func handle(_ request: Data) -> Data {
        var reader = SSHWireReader(request)
        guard let type = reader.byte() else { return payload([SSHAgentProtocol.failure]) }

        switch type {
        case SSHAgentProtocol.requestIdentities:
            var body = Data([SSHAgentProtocol.identitiesAnswer])
            body.append(u32(1))
            body.append(SSHKeyStore.sshString(publicKeyBlob))
            body.append(SSHKeyStore.sshString(Data(comment.utf8)))
            return payload(body)

        case SSHAgentProtocol.signRequest:
            guard let keyBlob = reader.string(), let data = reader.string(), reader.uint32() != nil else {
                return payload([SSHAgentProtocol.failure])
            }
            guard keyBlob == publicKeyBlob, let signature = try? sign(data) else {
                return payload([SSHAgentProtocol.failure])
            }
            var body = Data([SSHAgentProtocol.signResponse])
            body.append(SSHKeyStore.sshString(signature))
            return payload(body)

        case SSHAgentProtocol.extensionRequest:
            guard let ext = reader.string() else { return payload([SSHAgentProtocol.failure]) }
            // session-bind@openssh.com carries four fields in this order (OpenSSH
            // PROTOCOL.agent): string hostkey, string session-id, string signature,
            // bool is_forwarding. Record the session id — the second field.
            if String(decoding: ext, as: UTF8.self) == "session-bind@openssh.com",
               reader.string() != nil,                 // hostkey
               let sessionID = reader.string(),         // session identifier
               reader.string() != nil,                  // signature
               reader.byte() != nil {                   // is_forwarding
                boundSessions.append(sessionID)
                return payload([SSHAgentProtocol.success])
            }
            return payload([SSHAgentProtocol.failure])

        default:
            return payload([SSHAgentProtocol.failure])
        }
    }

    // MARK: helpers

    private func u32(_ value: UInt32) -> Data {
        var big = value.bigEndian
        return withUnsafeBytes(of: &big) { Data($0) }
    }

    /// Frame a payload: 4-byte big-endian length, then the bytes.
    private func payload(_ body: [UInt8]) -> Data { payload(Data(body)) }
    private func payload(_ body: Data) -> Data {
        var out = u32(UInt32(body.count))
        out.append(body)
        return out
    }
}

/// The socket server around the responder.
public final class SSHAgent: @unchecked Sendable {
    public enum AgentError: Error { case socket(String) }

    public let socketPath: String
    private let keyStore: SSHKeyStore
    private let comment: String
    private var listenFD: Int32 = -1
    private var worker: Thread?

    public init(keyStore: SSHKeyStore, comment: String, socketPath: String? = nil) {
        self.keyStore = keyStore
        self.comment = comment
        // The container tmp dir keeps the path under AF_UNIX's 104-byte sun_path;
        // a unique suffix lets several agents coexist (e.g. a terminal and a probe).
        self.socketPath = socketPath
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("lodi-agent-\(UUID().uuidString.prefix(8)).sock").path
    }

    public func start() throws {
        let fd = try Self.makeListener(path: socketPath)
        listenFD = fd
        let responder = SSHAgentResponder(
            publicKeyBlob: try keyStore.publicKeyBlob(),
            comment: comment,
            sign: { try self.keyStore.agentSignature($0) }
        )
        let thread = Thread { Self.serve(listenFD: fd, responder: responder) }
        thread.stackSize = 512 * 1024
        thread.start()
        worker = thread
    }

    public func stop() {
        if listenFD >= 0 { close(listenFD); listenFD = -1 }
        unlink(socketPath)
    }

    // MARK: - Socket plumbing

    private static func makeListener(path: String) throws -> Int32 {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AgentError.socket("socket \(errno)") }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd); throw AgentError.socket("path too long")
        }
        withUnsafeMutablePointer(to: &addr.sun_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dst in
                pathBytes.withUnsafeBufferPointer { dst.update(from: $0.baseAddress!, count: pathBytes.count) }
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
        }
        guard bound == 0 else { close(fd); throw AgentError.socket("bind \(errno)") }
        chmod(path, 0o600)   // the socket signs with the device key; keep it private
        guard listen(fd, 8) == 0 else { close(fd); throw AgentError.socket("listen \(errno)") }
        return fd
    }

    private static func serve(listenFD: Int32, responder: SSHAgentResponder) {
        var responder = responder
        while true {
            let client = accept(listenFD, nil, nil)
            if client < 0 { break }   // listener closed → stop
            while let request = readFrame(client) {
                let response = responder.handle(request)
                if !writeAll(client, response) { break }
            }
            close(client)
        }
    }

    /// Read one framed message: 4-byte length then that many bytes.
    private static func readFrame(_ fd: Int32) -> Data? {
        guard let header = readN(fd, 4) else { return nil }
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0, length < 256 * 1024 else { return nil }
        return readN(fd, Int(length))
    }

    private static func readN(_ fd: Int32, _ count: Int) -> Data? {
        var buffer = [UInt8](repeating: 0, count: count)
        var got = 0
        while got < count {
            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress!.advanced(by: got), count - got) }
            if n <= 0 { return nil }
            got += n
        }
        return Data(buffer)
    }

    private static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let n = write(fd, raw.baseAddress!.advanced(by: sent), raw.count - sent)
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
    }
}
