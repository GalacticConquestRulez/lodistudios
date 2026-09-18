import Foundation

/// A host in the inventory. The inventory is the source of truth for connection
/// options *and* for the in-app agent's destination constraints — a key may only
/// sign for a hop path that resolves to a host in here (docs/plan.md, "The
/// security control that matters most").
public struct Host: Identifiable, Sendable, Equatable, Codable {
    /// Short alias, also the config `Host` stanza name and the id. e.g. "sessions".
    public var alias: String
    /// The address to dial: a public IP, a private VPC IP, or a DNS name.
    public var hostName: String
    public var user: String
    public var port: Int
    /// Human-readable role, shown in the Board.
    public var role: String?
    /// Alias of the host to hop through first, if any (OpenSSH `ProxyJump`).
    public var proxyJump: String?
    /// Whether the in-app agent is forwarded to this host. Only the entry host
    /// (the session droplet) should carry the agent; onward hops are reached
    /// through it, so keys never rest on a downstream box.
    public var forwardAgent: Bool
    /// The pinned SSH host-key fingerprint (`SHA256:...`, base64, no padding —
    /// exactly as `ssh-keygen -l` prints). The transport refuses to connect on a
    /// mismatch; nil means "trust on first use, then pin" (docs/hosts.md).
    public var hostKeyFingerprintSHA256: String?

    public var id: String { alias }

    public init(
        alias: String,
        hostName: String,
        user: String = "root",
        port: Int = 22,
        role: String? = nil,
        proxyJump: String? = nil,
        forwardAgent: Bool = false,
        hostKeyFingerprintSHA256: String? = nil
    ) {
        self.alias = alias
        self.hostName = hostName
        self.user = user
        self.port = port
        self.role = role
        self.proxyJump = proxyJump
        self.forwardAgent = forwardAgent
        self.hostKeyFingerprintSHA256 = hostKeyFingerprintSHA256
    }
}
