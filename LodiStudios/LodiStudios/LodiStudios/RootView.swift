import SwiftUI
import LodiKit

/// The shared chrome: one sidebar, one detail area, the docked Assistant and the
/// ⌘K overlay. What changes between tools is the working area and the accent, not
/// the furniture (docs/ui-review.md, "The shell").
struct RootView: View {
    @Environment(HostInventory.self) private var inventory
    @Environment(CommandRegistry.self) private var registry
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        NavigationSplitView {
            // The sidebar writes navigation.target directly — the same state the
            // nav Commands mutate — so there is one source of truth, not a bare
            // action competing with the registry.
            List(selection: Binding<NavTarget?>(
                get: { navigation.target },
                set: { if let target = $0 { navigation.select(target) } }
            )) {
                Label("Board", systemImage: "square.grid.2x2")
                    .tag(NavTarget.board)

                Section("Tools") {
                    ForEach(LodiTool.allCases) { tool in
                        Label(tool.title, systemImage: tool.systemImage)
                            .tag(NavTarget.tool(tool))
                    }
                }
            }
            .navigationTitle("LodiStudios")
        } detail: {
            HStack(spacing: 0) {
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LodiTheme.ground)

                if navigation.isAssistantVisible {
                    Divider()
                    AssistantPanelView()
                        .frame(width: 320)
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    Button { run("palette.open") } label: {
                        Label("Command Palette", systemImage: "magnifyingglass")
                    }
                    .keyboardShortcut("k", modifiers: .command)

                    Button { run("assistant.toggle") } label: {
                        Label("Assistant", systemImage: "sparkles")
                    }
                    .keyboardShortcut("j", modifiers: .command)
                }
            }
        }
        .overlay {
            if navigation.isPaletteVisible {
                CommandPaletteView()
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch navigation.target {
        case .board:
            BoardView(hosts: inventory.hosts)
        case .tool(let tool):
            ToolPlaceholderView(tool: tool)
                .lodiTool(tool)
        }
    }

    /// Every chrome control invokes a Command rather than acting directly, so the
    /// palette, the Assistant and a shortcut all reach the app the same way.
    private func run(_ id: String) {
        Task { try? await registry.run(id) }
    }
}

/// A stand-in for a tool's working area, coloured by that tool's accent so the
/// wayfinding rule is visible before the real surfaces exist.
struct ToolPlaceholderView: View {
    let tool: LodiTool
    @Environment(\.lodiAccent) private var accent

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: tool.systemImage)
                .font(.system(size: 48))
                .foregroundStyle(accent)
            Text(tool.title)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(LodiTheme.text)
            Text("Coming in Phase build order — see docs/plan.md")
                .foregroundStyle(LodiTheme.secondaryText)
        }
    }
}
