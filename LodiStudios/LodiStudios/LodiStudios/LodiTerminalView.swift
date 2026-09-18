import SwiftUI
import LodiKit

/// LodiTerminal (v0.1): a live tmux session on the Sessions droplet, rendered by
/// SwiftTerm. The session lives in the TerminalStore, not here, so switching away
/// and back does not disconnect — this view only attaches its sink and shows the
/// reconnect banner when the connection is not up (M4).
struct LodiTerminalView: View {
    @Environment(TerminalStore.self) private var store
    @State private var session: SSHTerminalSession?

    private var host: LodiKit.Host {
        HostInventory.known.first { $0.alias == "sessions" }
            ?? LodiKit.Host(alias: "sessions", hostName: "67.205.136.45")
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let session {
                TerminalPaneView(session: session)
                    .background(LodiTheme.ground)
            } else {
                LodiTheme.ground
            }
            banner
        }
        .task { session = store.session(for: host) }
    }

    /// A reconnect banner that says why — status carried by shape + word + the
    /// status trio, never a tool accent (docs/ui-review.md, gap 4).
    @ViewBuilder private var banner: some View {
        switch store.state(for: host) {
        case .connected:
            EmptyView()
        case .connecting:
            ReconnectBanner(symbol: "●", text: "Connecting to \(host.alias)…", tint: LodiTheme.statusWarn)
        case .disconnected(let reason):
            ReconnectBanner(
                symbol: "▲",
                text: "Disconnected — reconnecting…" + (reason.map { " (\($0))" } ?? ""),
                tint: LodiTheme.statusWarn
            )
        }
    }
}

private struct ReconnectBanner: View {
    let symbol: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(symbol).foregroundStyle(tint)
            Text(text)
                .font(.callout)
                .foregroundStyle(LodiTheme.text)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(LodiPalette.paper.opacity(0.08))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
