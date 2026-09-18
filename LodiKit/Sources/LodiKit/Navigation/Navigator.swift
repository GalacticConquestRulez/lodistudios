import Foundation
import Observation

/// Where the app is pointed. `board` is the live front page; every other screen
/// is a tool. Kept in LodiKit so navigation is testable without an app and so the
/// nav Commands, ⌘K and the Assistant all speak one destination type.
public enum Destination: Hashable, Sendable {
    case board
    case tool(LodiTool)

    /// Human name for the current screen — used when logging a request's origin.
    public var screenName: String {
        switch self {
        case .board:          "Board"
        case .tool(let tool): tool.title
        }
    }

    /// The tool we're in, or nil on the Board.
    public var tool: LodiTool? {
        if case .tool(let tool) = self { return tool }
        return nil
    }
}

/// The single source of truth for the current destination and which of the
/// always-present surfaces are open (docs/reviews/2026-09-18-v0.1-shell.md, item
/// 2). Navigation Commands call `go(to:)`; the sidebar binds to `destination`
/// through the same door. Nothing in a view flips these fields on its own.
@MainActor
@Observable
public final class Navigator {
    public private(set) var destination: Destination = .board
    /// The docked Assistant panel (pink, present on every screen).
    public var isAssistantVisible = false
    /// The ⌘K command palette overlay.
    public var isPaletteVisible = false

    public init() {}

    /// Change screens. Closes the palette — you asked to be somewhere, so the
    /// jump surface gets out of the way.
    public func go(to destination: Destination) {
        self.destination = destination
        isPaletteVisible = false
    }

    public func openPalette()  { isPaletteVisible = true }
    public func closePalette() { isPaletteVisible = false }
    public func toggleAssistant() { isAssistantVisible.toggle() }
}
