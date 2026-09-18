import SwiftUI
import LodiKit

/// LodiTerminal (v0.1): a live tmux session on the Sessions droplet, rendered by
/// SwiftTerm over the embedded libssh2 transport. Owns the in-app agent and the
/// session for the lifetime of the screen.
struct LodiTerminalView: View {
    @State private var model = TerminalModel()

    var body: some View {
        TerminalPaneView(session: model.session)
            .background(LodiTheme.ground)
            .onDisappear { model.shutdown() }
    }
}

/// Holds the agent and the terminal session so they live as long as the screen.
@MainActor
final class TerminalModel {
    let agent: SSHAgent
    let session: SSHTerminalSession

    init() {
        let keyStore = SSHKeyStore()
        agent = SSHAgent(keyStore: keyStore, comment: LodiStudiosApp.keyComment)
        try? agent.start()
        let sessions = HostInventory.known.first { $0.alias == "sessions" }
            ?? Host(alias: "sessions", hostName: "67.205.136.45")
        session = SSHTerminalSession(
            host: sessions, keyStore: keyStore, agentSocketPath: agent.socketPath
        )
    }

    func shutdown() {
        session.stop()
        agent.stop()
    }
}
