import Foundation
import Observation
import LodiKit

/// A logged feature request: the ask verbatim, where the owner was, and when.
/// The Assistant writes one whenever it's asked for something no Command can do
/// (docs/ui-review.md, "Feature requests"). v0.1 keeps them in memory; the
/// Admin → Requests screen and persistence land with that tool.
struct LoggedRequest: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let tool: LodiTool?
    let screen: String
    let date: Date
}

@MainActor
@Observable
final class RequestsStore {
    private(set) var requests: [LoggedRequest] = []

    /// Newest first, so a Board badge and the Requests list read top-down.
    func log(_ text: String, tool: LodiTool?, screen: String) {
        requests.insert(
            LoggedRequest(text: text, tool: tool, screen: screen, date: Date()),
            at: 0
        )
    }

    var count: Int { requests.count }
}
