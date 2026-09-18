import Foundation

/// One operational truth about a host, as the Board shows it: a label, a value,
/// and a status. Deliberately pure data — no SwiftUI — so the same fact renders
/// on the Board, in a widget, or in a notification (docs/ui-review.md, gaps 1 & 5).
///
/// Status is carried as shape + word first (● ok, ▲ warn, ✕ fail, ○ unknown);
/// colour only reinforces it, and only from LodiTheme's status trio — never a tool
/// accent (gap 4).
public struct HostFact: Identifiable, Sendable, Equatable {
    public enum Status: String, Sendable, CaseIterable {
        case ok
        case warn
        case fail
        case unknown

        /// The glyph that carries meaning without colour.
        public var symbol: String {
            switch self {
            case .ok:      "●"
            case .warn:    "▲"
            case .fail:    "✕"
            case .unknown: "○"
            }
        }
    }

    /// Stable per-host key, e.g. "disk" — also the id within a host's fact list.
    public let id: String
    public let label: String
    public let value: String
    public let status: Status

    public init(id: String, label: String, value: String, status: Status) {
        self.id = id
        self.label = label
        self.value = value
        self.status = status
    }
}

/// Where the Board's facts come from. v0.1 has a fake provider so the Board is
/// worth opening before the transport exists; the SSH-backed provider that runs
/// `git status`, `systemctl list-timers`, `free`, `dig`, `certbot certificates`
/// over the milestone-3 channel slots in behind this same seam without touching
/// the Board (docs/ui-review.md, gap 1: "the Board's data is nearly free").
public protocol HostFactsProvider: Sendable {
    func facts(for host: Host) async -> [HostFact]
}

/// Representative facts so the Board renders realistically now — including the
/// three the UI review said it would have caught this week: unpushed commits, a
/// domain resolving to a foreign IP, a droplet deep into swap.
public struct FakeHostFactsProvider: HostFactsProvider {
    public init() {}

    public func facts(for host: Host) async -> [HostFact] {
        switch host.alias {
        case "sessions":
            return [
                HostFact(id: "disk",   label: "Disk",   value: "38% of 80 GB",           status: .ok),
                HostFact(id: "swap",   label: "Swap",   value: "1.9 GB in swap",         status: .warn),
                HostFact(id: "timers", label: "Timers", value: "cc-sessions-save · last ok", status: .ok),
                HostFact(id: "claude", label: "Claude", value: "1 run active",           status: .ok),
            ]
        case "greenflash":
            return [
                HostFact(id: "git",  label: "Repo", value: "21 commits unpushed",              status: .warn),
                HostFact(id: "dns",  label: "DNS",  value: "hewanorra.com → foreign IP",       status: .fail),
                HostFact(id: "cert", label: "Cert", value: "3 sites expire in < 14 days",      status: .warn),
                HostFact(id: "http", label: "HTTP", value: "17 sites · 200 OK",                status: .ok),
            ]
        default:
            return [HostFact(id: "reach", label: "Reachability", value: "unknown", status: .unknown)]
        }
    }
}
