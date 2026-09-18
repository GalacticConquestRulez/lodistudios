import Foundation
import Security

/// The app's own SSH identity: a device-held ECDSA P-256 key used to authenticate
/// to hosts (docs/specs/transport-v0.1.md, milestone 1). Generated on first use as
/// a non-extractable `SecKey` in the Keychain and signed with `SecKeyCreateSignature`
/// — the app is its own agent, so no key file ever exists and the private key is
/// never readable by Swift, only signed with.
///
/// P-256 (`ecdsa-sha2-nistp256`) because libssh2's mbedTLS backend has
/// `LIBSSH2_ED25519 0` (ECDSA/RSA only) and because it is the only type the Secure
/// Enclave signs — so M1 through M5 use one key type. M5 is then just adding
/// `kSecAttrTokenID: kSecAttrTokenIDSecureEnclave` to `createKey`'s attributes.
public struct SSHKeyStore: Sendable {
    public enum KeyError: Error, Sendable {
        case keychain(OSStatus)
        case generate(String)
        case noPublicKey
        case sign(String)
        case badSignature
    }

    private let tag: Data

    public init(tag: String = "com.lodistudios.ssh.device-p256") {
        self.tag = Data(tag.utf8)
    }

    // MARK: - Key lifecycle

    public func loadOrCreate() throws -> SecKey {
        if let existing = try loadKey() { return existing }
        return try createKey()
    }

    private func loadKey() throws -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag as String: tag,
            kSecReturnRef as String: true,
        ]
        var ref: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &ref)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let ref else { throw KeyError.keychain(status) }
        return (ref as! SecKey)
    }

    private func createKey() throws -> SecKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ],
            // M5: kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw KeyError.generate(String(describing: error?.takeRetainedValue()))
        }
        return key
    }

    // MARK: - Public key

    /// The raw EC point `0x04 || X || Y` (65 bytes).
    private func publicPoint(_ key: SecKey) throws -> Data {
        guard let pub = SecKeyCopyPublicKey(key) else { throw KeyError.noPublicKey }
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(pub, &error) as Data? else {
            throw KeyError.generate(String(describing: error?.takeRetainedValue()))
        }
        return data
    }

    /// The SSH public-key blob libssh2 wants as `pubkeydata`:
    /// `string("ecdsa-sha2-nistp256") string("nistp256") string(Q)`.
    public func publicKeyBlob() throws -> Data {
        Self.ecdsaBlob(point: try publicPoint(try loadOrCreate()))
    }

    /// The public key in OpenSSH `authorized_keys` form.
    public func publicKeyOpenSSH(comment: String) throws -> String {
        Self.openSSHLine(point: try publicPoint(try loadOrCreate()), comment: comment)
    }

    // MARK: - Signing

    /// Sign `data` for the libssh2 publickey callback, returning the SSH ecdsa
    /// signature blob `mpint(r) || mpint(s)` — exactly what libssh2's internal
    /// signer returns; libssh2 then wraps it as `string(method) + string(blob)`.
    public func sign(_ data: Data) throws -> Data {
        let key = try loadOrCreate()
        var error: Unmanaged<CFError>?
        guard let der = SecKeyCreateSignature(
            key, .ecdsaSignatureMessageX962SHA256, data as CFData, &error
        ) as Data? else {
            throw KeyError.sign(String(describing: error?.takeRetainedValue()))
        }
        return try Self.sshSignatureBlob(fromDER: der)
    }

    /// The full SSH signature for the agent protocol's SIGN_RESPONSE:
    /// `string("ecdsa-sha2-nistp256") + string(mpint(r)||mpint(s))`. (libssh2's
    /// publickey callback wants only the inner blob; the agent wire wants this.)
    public func agentSignature(_ data: Data) throws -> Data {
        var signature = Data()
        signature.append(Self.sshString(Data("ecdsa-sha2-nistp256".utf8)))
        signature.append(Self.sshString(try sign(data)))
        return signature
    }

    // MARK: - Pure SSH encodings (static so they are testable without the Keychain)

    /// An SSH `string`: 4-byte big-endian length, then the bytes.
    static func sshString(_ bytes: Data) -> Data {
        var out = Data()
        var length = UInt32(bytes.count).bigEndian
        withUnsafeBytes(of: &length) { out.append(contentsOf: $0) }
        out.append(bytes)
        return out
    }

    /// An SSH `mpint`: minimal big-endian magnitude, a leading 0x00 when the top
    /// bit is set so it reads as positive, length-prefixed as a string.
    static func sshMPInt(_ magnitude: Data) -> Data {
        var bytes = Data(magnitude.drop { $0 == 0 })
        if bytes.isEmpty { return sshString(Data()) }
        if bytes[bytes.startIndex] & 0x80 != 0 { bytes = Data([0]) + bytes }
        return sshString(bytes)
    }

    static func ecdsaBlob(point: Data) -> Data {
        var blob = Data()
        blob.append(sshString(Data("ecdsa-sha2-nistp256".utf8)))
        blob.append(sshString(Data("nistp256".utf8)))
        blob.append(sshString(point))
        return blob
    }

    static func openSSHLine(point: Data, comment: String) -> String {
        "ecdsa-sha2-nistp256 \(ecdsaBlob(point: point).base64EncodedString()) \(comment)"
    }

    /// Parse a DER `SEQUENCE { INTEGER r, INTEGER s }` and re-encode as the SSH
    /// ecdsa signature blob. P-256 signatures are always DER short-form.
    static func sshSignatureBlob(fromDER der: Data) throws -> Data {
        let (r, s) = try parseECDSADER(der)
        var out = Data()
        out.append(sshMPInt(r))
        out.append(sshMPInt(s))
        return out
    }

    static func parseECDSADER(_ der: Data) throws -> (Data, Data) {
        let bytes = [UInt8](der)
        var i = 0
        func need(_ n: Int) throws { if i + n > bytes.count { throw KeyError.badSignature } }
        func take(_ n: Int) throws -> [UInt8] { try need(n); defer { i += n }; return Array(bytes[i..<i+n]) }
        func byte() throws -> UInt8 { try need(1); defer { i += 1 }; return bytes[i] }
        func length() throws -> Int {
            let first = try byte()
            if first < 0x80 { return Int(first) }        // short form only (P-256)
            throw KeyError.badSignature
        }
        func integer() throws -> Data {
            guard try byte() == 0x02 else { throw KeyError.badSignature }
            let len = try length()
            return Data(try take(len))
        }
        guard try byte() == 0x30 else { throw KeyError.badSignature }
        _ = try length()
        let r = try integer()
        let s = try integer()
        return (r, s)
    }
}
