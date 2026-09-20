import SwiftUI
import Observation
import LodiKit

/// App-level owner of terminal sessions and their agents, keyed by host, so a
/// session outlives the view that shows it (docs/reviews/2026-09-18-transport-m3.md,
/// UI item 3; and M4 "disconnect is not an event"). Views attach and detach
/// *sinks* — they never start or stop the session. Injected like the registry.
@MainActor
@Observable
final class TerminalStore {
    private var sessions: [String: HostConnection] = [:]
    private var agents: [String: SSHAgent] = [:]
    private var queues: [String: TransferQueue] = [:]
    /// Observable per-host connection state, driving the reconnect banner.
    private(set) var states: [String: HostConnection.State] = [:]

    /// The session for a host, created and started on first request, reused after.
    func session(for host: LodiKit.Host) -> HostConnection {
        if let existing = sessions[host.alias] { return existing }

        let keyStore = SSHKeyStore()
        let agent = SSHAgent(keyStore: keyStore, comment: LodiStudiosApp.keyComment)
        try? agent.start()
        agents[host.alias] = agent
        states[host.alias] = .connecting

        let alias = host.alias
        let session = HostConnection(
            host: host,
            keyStore: keyStore,
            agentSocketPath: agent.socketPath,
            agentComment: LodiStudiosApp.keyComment,
            onState: { [weak self] state in
                Task { @MainActor in self?.states[alias] = state }
            }
        )
        sessions[alias] = session
        session.start()
        return session
    }

    func state(for host: LodiKit.Host) -> HostConnection.State {
        states[host.alias] ?? .connecting
    }

    /// The transfer queue for a host, created on first request and reused. It moves
    /// bytes over its own lazy bulk connection (never the PTY link); it shares the
    /// host's agent socket so it authenticates with the same Enclave key.
    func transferQueue(for host: LodiKit.Host) -> TransferQueue {
        if let existing = queues[host.alias] { return existing }
        _ = session(for: host)   // ensure the host's agent is started
        let queue = TransferQueue(host: host, keyStore: SSHKeyStore(),
                                  agentSocketPath: agents[host.alias]?.socketPath)
        queues[host.alias] = queue
        return queue
    }
}
