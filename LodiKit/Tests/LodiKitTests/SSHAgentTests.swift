import Testing
import Foundation
@testable import LodiKit

struct SSHAgentTests {
    private let blob = Data("test-key-blob".utf8)

    private func responder() -> SSHAgentResponder {
        SSHAgentResponder(publicKeyBlob: blob, comment: "lodi@test") { data in
            Data("SIGNED:".utf8) + data   // deterministic fake signature
        }
    }

    private func sshString(_ d: Data) -> Data {
        var out = Data()
        var len = UInt32(d.count).bigEndian
        withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
        out.append(d)
        return out
    }

    /// `handle` takes an unframed message body and returns a framed reply, so the
    /// reply's first 4 bytes are the outer length.
    private func replyBody(_ response: Data) -> SSHWireReader {
        SSHWireReader(Data(response.dropFirst(4)))
    }

    @Test func requestIdentitiesReturnsTheKey() {
        var agent = responder()
        var reader = replyBody(agent.handle(Data([11])))   // REQUEST_IDENTITIES
        #expect(reader.byte() == 12)                        // IDENTITIES_ANSWER
        #expect(reader.uint32() == 1)                       // one key
        #expect(reader.string() == blob)
        #expect(reader.string() == Data("lodi@test".utf8))
    }

    @Test func signRequestForOurKeySigns() {
        var agent = responder()
        let data = Data("challenge".utf8)
        var request = Data([13])                            // SIGN_REQUEST
        request += sshString(blob)
        request += sshString(data)
        request += Data([0, 0, 0, 0])                       // flags
        var reader = replyBody(agent.handle(request))
        #expect(reader.byte() == 14)                        // SIGN_RESPONSE
        #expect(reader.string() == Data("SIGNED:".utf8) + data)
    }

    @Test func signRequestForUnknownKeyFails() {
        var agent = responder()
        var request = Data([13])
        request += sshString(Data("someone-elses-key".utf8))
        request += sshString(Data("challenge".utf8))
        request += Data([0, 0, 0, 0])
        #expect(Array(agent.handle(request).dropFirst(4)) == [5])  // FAILURE
    }

    @Test func sessionBindIsRecordedAndAcknowledged() {
        var agent = responder()
        let sessionID = Data([0xAB, 0xCD])
        var request = Data([27])                            // EXTENSION
        request += sshString(Data("session-bind@openssh.com".utf8))
        request += sshString(sessionID)
        request += sshString(Data("hostkey-sig".utf8))
        request += Data([0])                                // is_forwarding
        #expect(Array(agent.handle(request).dropFirst(4)) == [6])  // SUCCESS
        #expect(agent.boundSessions == [sessionID])
    }

    @Test func unknownMessageFails() {
        var agent = responder()
        #expect(Array(agent.handle(Data([99])).dropFirst(4)) == [5])  // FAILURE
    }
}
