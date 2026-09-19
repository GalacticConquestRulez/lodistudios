import Foundation

/// The Board's real data: runs a small read-only script over the transport and
/// parses the host's vitals into `HostFact`s (docs/ui-review.md, gap 1 — "the
/// Board's data is nearly free"). It dials the host's directly-reachable address
/// (the public IP when the inventory's hostName is a private/jump address).
///
/// It never invents numbers: a host that can't be probed shows a single honest
/// "Reachability" fact with `.unknown` status, not fabricated vitals. The parsers
/// are pure and unit-tested. `FakeHostFactsProvider` lives only in previews/tests.
public struct SSHHostFactsProvider: HostFactsProvider {
    /// One connection, one exec: cheap vitals with `###` section markers.
    static let script = "echo '###disk'; df -P /; echo '###mem'; free -m; echo '###load'; uptime"

    private let agentSocketPath: String

    public init(agentSocketPath: String) {
        self.agentSocketPath = agentSocketPath
    }

    public func facts(for host: Host) async -> [HostFact] {
        // Dial the directly-reachable address: the public IP if the inventory's
        // hostName is a private/jump address, else hostName itself. A jump-only
        // host can't be probed from here yet — say so, never invent numbers.
        guard let dial = host.directHostName ?? (host.proxyJump == nil ? host.hostName : nil) else {
            return [HostFact(id: "reach", label: "Reachability",
                             value: "via jump — facts not yet available", status: .unknown)]
        }
        var target = host
        target.hostName = dial
        do {
            let output = try await SSHSession(host: target, agentSocketPath: agentSocketPath).run(Self.script)
            let facts = Self.parse(output.stdout)
            return facts.isEmpty
                ? [HostFact(id: "reach", label: "Reachability", value: "connected", status: .ok)]
                : facts
        } catch {
            return [HostFact(id: "reach", label: "Reachability", value: "unreachable", status: .unknown)]
        }
    }

    // MARK: - Parsing (pure, testable)

    static func parse(_ stdout: String) -> [HostFact] {
        var sections: [String: [String]] = [:]
        var current = ""
        for line in stdout.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("###") { current = String(line.dropFirst(3)); sections[current] = []; continue }
            if !current.isEmpty { sections[current, default: []].append(line) }
        }

        var facts: [HostFact] = []
        if let disk = sections["disk"], let fact = diskFact(disk) { facts.append(fact) }
        if let mem = sections["mem"] { facts.append(contentsOf: memFacts(mem)) }
        if let load = sections["load"], let fact = loadFact(load) { facts.append(fact) }
        return facts
    }

    /// `df -P /` → the data line's Capacity (`NN%`) and total size in GB.
    static func diskFact(_ lines: [String]) -> HostFact? {
        guard let line = lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
        let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let capacity = fields.first(where: { $0.hasSuffix("%") }),
              let percent = Int(capacity.dropLast()) else { return nil }
        let sizeGB = fields.count > 1 ? (Int(fields[1]).map { $0 / 1_048_576 } ?? 0) : 0
        let status: HostFact.Status = percent >= 90 ? .fail : (percent >= 80 ? .warn : .ok)
        return HostFact(id: "disk", label: "Disk", value: "\(percent)% of \(sizeGB) GB", status: status)
    }

    /// `free -m` → Memory used/total and Swap in use.
    static func memFacts(_ lines: [String]) -> [HostFact] {
        var facts: [HostFact] = []
        for line in lines {
            let f = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            if line.hasPrefix("Mem:"), f.count >= 3, let total = Int(f[1]), let used = Int(f[2]) {
                let percent = total > 0 ? used * 100 / total : 0
                facts.append(HostFact(id: "mem", label: "Memory",
                                      value: "\(used) of \(total) MB",
                                      status: percent >= 90 ? .warn : .ok))
            }
            if line.hasPrefix("Swap:"), f.count >= 3, let total = Int(f[1]), let used = Int(f[2]) {
                let percent = total > 0 ? used * 100 / total : 0
                facts.append(HostFact(id: "swap", label: "Swap",
                                      value: used == 0 ? "none" : "\(used) of \(total) MB",
                                      status: (used == 0 || percent < 25) ? .ok : .warn))
            }
        }
        return facts
    }

    /// `uptime` → the 1-minute load average.
    static func loadFact(_ lines: [String]) -> HostFact? {
        guard let line = lines.first(where: { $0.contains("load average") }),
              let range = line.range(of: "load average:") else { return nil }
        let after = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
        let first = after.split(separator: ",").first.map {
            String($0).trimmingCharacters(in: .whitespaces)
        } ?? "?"
        return HostFact(id: "load", label: "Load", value: first, status: .ok)
    }
}
