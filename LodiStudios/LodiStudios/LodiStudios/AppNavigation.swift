import Foundation
import Observation
import LodiKit

/// Where the app is pointed and which of the always-present surfaces are open.
/// This is the one source of truth navigation commands mutate; the sidebar binds
/// to it too, so there is exactly one place "we are on screen X" is written.
enum NavTarget: Hashable, Sendable {
    case board
    case tool(LodiTool)

    /// Human name for the current screen — used when logging a request's origin.
    var screenName: String {
        switch self {
        case .board:            "Board"
        case .tool(let tool):   tool.title
        }
    }

    /// The tool we're in, or nil on the Board.
    var tool: LodiTool? {
        if case .tool(let tool) = self { return tool }
        return nil
    }
}

/// App-wide navigation and surface state. Deliberately holds no bare actions of
/// its own beyond mutating state — the *reasons* to change it are Commands in the
/// registry (docs/ui-review.md, "everything is a Command").
@MainActor
@Observable
final class AppNavigation {
    var target: NavTarget = .board
    /// The docked Assistant panel (pink, present on every screen).
    var isAssistantVisible = false
    /// The ⌘K command palette overlay.
    var isPaletteVisible = false

    func select(_ target: NavTarget) {
        self.target = target
        isPaletteVisible = false
    }

    func openPalette()  { isPaletteVisible = true }
    func closePalette() { isPaletteVisible = false }
    func toggleAssistant() { isAssistantVisible.toggle() }
}
