import SwiftUI
import LodiKit

/// The app is one app for five tools: same chrome, same sidebar, same command
/// surface (docs/plan.md). Dark only, black ground, white text.
@main
struct LodiStudiosApp: App {
    @State private var registry = CommandRegistry()
    @State private var inventory = HostInventory(hosts: HostInventory.known)

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(registry)
                .environment(inventory)
                .preferredColorScheme(.dark)
                .task { registerBaselineCommands() }
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
    }

    /// The first few commands, so the registry is real from day one. Views will
    /// grow to invoke these instead of holding bare actions.
    @MainActor private func registerBaselineCommands() {
        guard registry.all.isEmpty else { return }
        registry.register([
            Command(id: "nav.board", title: "Go to Board",
                    subtitle: "The live front page: what is running, broken, waiting",
                    keywords: ["home", "front"]) { _ in },
            Command(id: "assistant.toggle", title: "Toggle Assistant",
                    subtitle: "The chat panel that drives every command",
                    keywords: ["chat", "ai"]) { _ in },
        ])
        for tool in LodiTool.allCases {
            registry.register(
                Command(id: "nav.\(tool.rawValue)", title: "Go to \(tool.title)",
                        tool: tool, keywords: ["open", "switch"]) { _ in }
            )
        }
    }
}
