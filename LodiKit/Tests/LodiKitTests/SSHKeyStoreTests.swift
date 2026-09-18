import Testing
import Foundation
@testable import LodiKit

struct SSHKeyStoreTests {

    /// The OpenSSH line is a well-formed ecdsa-sha2-nistp256 entry built from a
    /// fixed EC point — no Keychain needed.
    @Test func opensshLineIsWellFormed() throws {
        // 0x04 || X || Y, 65 bytes (contents arbitrary for an encoding test).
        let point = Data([0x04] + Array(1...64).map { UInt8($0) })
        let line = SSHKeyStore.openSSHLine(point: point, comment: "lodi@test")

        let parts = line.split(separator: " ")
        #expect(parts.count == 3)
        #expect(parts[0] == "ecdsa-sha2-nistp256")
        #expect(parts[2] == "lodi@test")

        let blob = try #require(Data(base64Encoded: String(parts[1])))
        // string("ecdsa-sha2-nistp256")=4+19, string("nistp256")=4+8, string(point)=4+65.
        #expect(blob.count == (4 + 19) + (4 + 8) + (4 + 65))
    }

    /// An mpint whose top bit is set gets a leading zero; a small one does not.
    @Test func mpintPadsWhenHighBitSet() {
        let high = SSHKeyStore.sshMPInt(Data([0xFF, 0x01]))
        #expect(Array(high) == [0, 0, 0, 3, 0x00, 0xFF, 0x01])

        let low = SSHKeyStore.sshMPInt(Data([0x7F]))
        #expect(Array(low) == [0, 0, 0, 1, 0x7F])
    }

    /// A DER SEQUENCE{INTEGER r, INTEGER s} parses and re-encodes as mpint(r)||mpint(s).
    @Test func parsesDERAndReencodes() throws {
        // SEQUENCE(6) { INTEGER(1)=0x01, INTEGER(1)=0x02 }
        let der = Data([0x30, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x02])
        let (r, s) = try SSHKeyStore.parseECDSADER(der)
        #expect(Array(r) == [0x01])
        #expect(Array(s) == [0x02])

        let blob = try SSHKeyStore.sshSignatureBlob(fromDER: der)
        #expect(Array(blob) == [0, 0, 0, 1, 0x01, 0, 0, 0, 1, 0x02])
    }

    @Test func rejectsNonSequenceDER() {
        #expect(throws: SSHKeyStore.KeyError.self) {
            _ = try SSHKeyStore.parseECDSADER(Data([0x02, 0x01, 0x01]))
        }
    }
}
