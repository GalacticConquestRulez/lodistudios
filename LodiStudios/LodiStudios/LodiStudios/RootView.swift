import SwiftUI
import LodiKit

/// The shared chrome: one sidebar, one detail area. What changes between tools is
/// the working area and the accent, not the furniture.
struct RootView: View {
    @Environment(HostInventory.self) private var inventory
    @State private var selection: SidebarItem = .board

    enum SidebarItem: Hashable {
        case board
        case tool(LodiTool)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Board", systemImage: "square.grid.2x2")
                    .tag(SidebarItem.board)

                Section("Tools") {
                    ForEach(LodiTool.allCases) { tool in
                        Label(tool.title, systemImage: tool.systemImage)
                            .tag(SidebarItem.tool(tool))
                    }
                }
            }
            .navigationTitle("LodiStudios")
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(LodiTheme.ground)
        }
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .board:
            BoardView(hosts: inventory.hosts)
        case .tool(let tool):
            ToolPlaceholderView(tool: tool)
                .lodiTool(tool)
        }
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
