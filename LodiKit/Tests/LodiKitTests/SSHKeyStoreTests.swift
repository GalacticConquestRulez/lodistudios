import Testing
import Foundation
import CryptoKit
@testable import LodiKit

struct SSHKeyStoreTests {

    /// The OpenSSH encoding is testable without the Keychain: check structure
    /// against a fixed public key rather than a magic base64 constant.
    @Test func opensshEncodingIsWellFormed() throws {
        let key = Curve25519.Signing.PrivateKey()
        let line = SSHKeyStore.openSSHEd25519(key.publicKey, comment: "lodi@test")

        let parts = line.split(separator: " ")
        #expect(parts.count == 3)
        #expect(parts[0] == "ssh-ed25519")
        #expect(parts[2] == "lodi@test")

        let blob = try #require(Data(base64Encoded: String(parts[1])))
        // string("ssh-ed25519") = 4 + 11 = 15 bytes; string(32-byte key) = 4 + 32 = 36; total 51.
        #expect(blob.count == 51)

        // First length-prefixed field is exactly "ssh-ed25519".
        let nameLen = blob.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        #expect(nameLen == 11)
        let name = String(decoding: blob[4..<4 + nameLen], as: UTF8.self)
        #expect(name == "ssh-ed25519")

        // Second field carries the exact 32 raw public-key bytes.
        let keyBytes = blob.suffix(32)
        #expect(Data(keyBytes) == key.publicKey.rawRepresentation)
    }
}
