import SwiftUI
import LodiKit

/// The app is one app for five tools: same chrome, same sidebar, same command
/// surface (docs/plan.md). Dark only, black ground, white text.
@main
struct LodiStudiosApp: App {
    @State private var registry = CommandRegistry()
    @State private var inventory = HostInventory(hosts: HostInventory.known)
    @State private var navigator = Navigator()
    @State private var requests = RequestsStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(registry)
                .environment(inventory)
                .environment(navigator)
                .environment(requests)
                .preferredColorScheme(.dark)
                .task { registerBaselineCommands() }
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
    }

    /// The baseline commands, so the registry is real from day one and the
    /// sidebar, ⌘K and the Assistant all reach navigation through it. Each body
    /// hops to the main actor to touch the `Navigator`.
    @MainActor private func registerBaselineCommands() {
        guard registry.all.isEmpty else { return }
        let navigator = navigator

        registry.register([
            Command(id: "nav.board", title: "Go to Board",
                    subtitle: "The live front page: what is running, broken, waiting",
                    keywords: ["home", "front"]) { _ in
                await MainActor.run { navigator.go(to: .board) }
            },
            Command(id: "palette.open", title: "Open Command Palette",
                    subtitle: "Jump to any tool or run any command",
                    keywords: ["cmdk", "search", "jump", "run"]) { _ in
                await MainActor.run { navigator.openPalette() }
            },
            Command(id: "assistant.toggle", title: "Toggle Assistant",
                    subtitle: "The chat panel that drives every command",
                    keywords: ["chat", "ai", "open", "close"]) { _ in
                await MainActor.run { navigator.toggleAssistant() }
            },
        ])

        for tool in LodiTool.allCases {
            registry.register(
                Command(id: "nav.\(tool.rawValue)", title: "Go to \(tool.title)",
                        tool: tool, keywords: ["open", "switch"]) { _ in
                    await MainActor.run { navigator.go(to: .tool(tool)) }
                }
            )
        }
    }
}
