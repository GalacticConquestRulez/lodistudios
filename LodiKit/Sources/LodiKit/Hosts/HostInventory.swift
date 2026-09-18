import Foundation
import Observation

/// The live host inventory. LodiTerminal builds it first because Infrastructure
/// Pro, WebPro and the agent's destination constraints all reuse it.
@MainActor
@Observable
public final class HostInventory {
    public private(set) var hosts: [Host]

    public init(hosts: [Host] = []) {
        self.hosts = hosts
    }

    public func host(alias: String) -> Host? {
        hosts.first { $0.alias == alias }
    }

    /// Insert or replace by alias, preserving order for existing entries.
    public func upsert(_ host: Host) {
        if let index = hosts.firstIndex(where: { $0.alias == host.alias }) {
            hosts[index] = host
        } else {
            hosts.append(host)
        }
    }

    public func remove(alias: String) {
        hosts.removeAll { $0.alias == alias }
    }

    /// The two hosts that exist today (docs/hosts.md), used to bootstrap v0.1.
    /// The Mac reaches `sessions` (agent forwarded), and `greenflash` is reached
    /// *through* it over the private VPC address — never holding a key itself.
    public static var known: [Host] {
        [
            Host(
                alias: "sessions",
                hostName: "67.205.136.45",
                role: "LodiStudios session droplet — tmux, Claude runs, push relay",
                forwardAgent: true,
                hostKeyFingerprintSHA256: "SHA256:QSNdYT45PqF23pHNBeg92CL/Qj0XDfpYm9hZc/4CfJU"
            ),
            Host(
                alias: "greenflash",
                hostName: "10.116.0.2",
                role: "client-facing: 17 sites, Green Flash Studio",
                proxyJump: "sessions",
                hostKeyFingerprintSHA256: "SHA256:O01ThyuNFaUU+3eGESaMK5hF4q1a6pkIyWtSGF9UtM4"
            ),
        ]
    }
}
