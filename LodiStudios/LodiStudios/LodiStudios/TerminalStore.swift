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
    private var sessions: [String: SSHTerminalSession] = [:]
    private var agents: [String: SSHAgent] = [:]
    /// Observable per-host connection state, driving the reconnect banner.
    private(set) var states: [String: SSHTerminalSession.State] = [:]

    /// The session for a host, created and started on first request, reused after.
    func session(for host: LodiKit.Host) -> SSHTerminalSession {
        if let existing = sessions[host.alias] { return existing }

        let keyStore = SSHKeyStore()
        let agent = SSHAgent(keyStore: keyStore, comment: LodiStudiosApp.keyComment)
        try? agent.start()
        agents[host.alias] = agent
        states[host.alias] = .connecting

        let alias = host.alias
        let session = SSHTerminalSession(
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

    func state(for host: LodiKit.Host) -> SSHTerminalSession.State {
        states[host.alias] ?? .connecting
    }
}
