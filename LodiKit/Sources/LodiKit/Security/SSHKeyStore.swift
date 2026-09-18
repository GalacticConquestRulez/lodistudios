import Foundation
import CryptoKit
import Security

/// The app's own SSH identity: a device-held ed25519 key used to authenticate to
/// hosts (docs/specs/transport-v0.1.md, milestone 1). Generated on first use and
/// kept in the Keychain; the app is its own agent, so no key file ever exists.
///
/// Deviation from the spec's literal wording, worth the owner knowing: the spec
/// says "SecKeyCreateSignature on a Keychain-held ed25519 key", but SecKey/Keychain
/// do not support ed25519 for signing on Apple platforms — only Secure Enclave EC
/// (P-256) at milestone 5. So milestone 1 uses a CryptoKit Curve25519 key whose raw
/// representation is stored in the Keychain and loaded to sign. The "private key is
/// never readable by Swift" guarantee arrives with the Secure Enclave at M5; here
/// the software key is loaded to sign, which the spec anticipates for M1.
public struct SSHKeyStore: Sendable {
    public enum KeyError: Error, Sendable {
        case keychain(OSStatus)
    }

    private let service: String
    private let account: String

    public init(service: String = "com.lodistudios.ssh", account: String = "device-ed25519") {
        self.service = service
        self.account = account
    }

    // MARK: - Key lifecycle

    /// The device key, generated and persisted on first call, returned as-is after.
    public func loadOrCreate() throws -> Curve25519.Signing.PrivateKey {
        if let existing = try load() { return existing }
        let key = Curve25519.Signing.PrivateKey()
        try store(key)
        return key
    }

    /// Sign `data` with the device key — the sign primitive the libssh2 publickey
    /// callback and the in-app agent both call (milestones 1 and 2).
    public func sign(_ data: Data) throws -> Data {
        try loadOrCreate().signature(for: data)
    }

    /// The public key in OpenSSH `authorized_keys` form: `ssh-ed25519 <base64> <comment>`.
    public func publicKeyOpenSSH(comment: String) throws -> String {
        Self.openSSHEd25519(try loadOrCreate().publicKey, comment: comment)
    }

    // MARK: - OpenSSH wire format

    /// Encodes an ed25519 public key as OpenSSH does: two length-prefixed strings
    /// ("ssh-ed25519" then the 32 raw bytes), base64'd, with the algorithm name and
    /// a trailing comment.
    static func openSSHEd25519(_ publicKey: Curve25519.Signing.PublicKey, comment: String) -> String {
        func sshString(_ bytes: Data) -> Data {
            var out = Data()
            var length = UInt32(bytes.count).bigEndian
            withUnsafeBytes(of: &length) { out.append(contentsOf: $0) }
            out.append(bytes)
            return out
        }
        var blob = Data()
        blob.append(sshString(Data("ssh-ed25519".utf8)))
        blob.append(sshString(publicKey.rawRepresentation))
        return "ssh-ed25519 \(blob.base64EncodedString()) \(comment)"
    }

    // MARK: - Keychain

    private func load() throws -> Curve25519.Signing.PrivateKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeyError.keychain(status)
        }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
    }

    private func store(_ key: Curve25519.Signing.PrivateKey) throws {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: key.rawRepresentation,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeyError.keychain(status) }
    }
}
