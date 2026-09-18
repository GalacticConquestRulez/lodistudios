import Foundation

/// The seam in front of the emulator. SwiftTerm is the v1 renderer on both
/// platforms, but the rest of the app codes against this so libghostty (still
/// alpha) can slot in later without touching callers (docs/plan.md).
///
/// A concrete surface is typically also a `PaneOutputSink` that forwards received
/// bytes into `feed`, closing the loop transport → broadcaster → surface.
public protocol TerminalSurface: AnyObject {
    /// Remote output to draw.
    func feed(_ bytes: [UInt8])
    /// Resize the emulator's grid.
    func resize(cols: Int, rows: Int)
    /// User keystrokes leaving the surface, headed for the `PaneWriter`.
    var onInput: (([UInt8]) -> Void)? { get set }
}
