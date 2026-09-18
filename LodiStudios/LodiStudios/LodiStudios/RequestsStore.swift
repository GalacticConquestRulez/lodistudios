import Foundation
import Observation
import LodiKit

/// A logged feature request: the ask verbatim, where the owner was, and when.
/// The Assistant writes one whenever it's asked for something no Command can do
/// (docs/ui-review.md, "Feature requests").
struct LoggedRequest: Identifiable, Codable, Sendable {
    let id: UUID
    let text: String
    let tool: LodiTool?
    let screen: String
    let date: Date

    init(text: String, tool: LodiTool?, screen: String, date: Date) {
        self.id = UUID()
        self.text = text
        self.tool = tool
        self.screen = screen
        self.date = date
    }
}

/// The request log. Persisted to JSON under Application Support on every change —
/// a log that evaporates on quit is not a log (docs/reviews/2026-09-18-v0.1-shell.md,
/// item 1 of the f7ec8ed review). Markdown export to docs/requests.md waits for
/// LodiAdmin; not losing the ask does not.
@MainActor
@Observable
final class RequestsStore {
    private(set) var requests: [LoggedRequest] = []

    private let fileURL: URL

    init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )) ?? URL.temporaryDirectory
        fileURL = base.appendingPathComponent("LodiStudios/requests.json")
        load()
    }

    /// Newest first, so a Board badge and the Requests list read top-down.
    func log(_ text: String, tool: LodiTool?, screen: String) {
        requests.insert(
            LoggedRequest(text: text, tool: tool, screen: screen, date: Date()),
            at: 0
        )
        save()
    }

    var count: Int { requests.count }

    // MARK: - Persistence (best-effort; a failed write never breaks logging)

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([LoggedRequest].self, from: data) {
            requests = decoded
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(requests).write(to: fileURL, options: .atomic)
        } catch {
            // Intentionally ignored: persistence is a backup of the in-memory log.
        }
    }
}
