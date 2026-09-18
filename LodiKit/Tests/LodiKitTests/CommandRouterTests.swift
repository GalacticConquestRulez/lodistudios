import Testing
@testable import LodiKit

/// The Assistant's v0.1 local router. The trap the review flagged: the keyword
/// "open" is on every nav command *and* on the Assistant toggle, so a naive match
/// on "open the assistant" would pick a nav command. Overlap must disambiguate.
@MainActor
struct CommandRouterTests {
    private func baseline() -> CommandRegistry {
        let registry = CommandRegistry()
        registry.register(
            Command(id: "assistant.toggle", title: "Toggle Assistant",
                    subtitle: "The chat panel that drives every command",
                    keywords: ["chat", "ai", "open", "close"]) { _ in }
        )
        for tool in LodiTool.allCases {
            registry.register(
                Command(id: "nav.\(tool.rawValue)", title: "Go to \(tool.title)",
                        tool: tool, keywords: ["open", "switch"]) { _ in }
            )
        }
        return registry
    }

    @Test func openTheAssistantPicksTheToggleNotANavCommand() {
        let registry = baseline()
        #expect(registry.bestMatch(for: "open the assistant")?.id == "assistant.toggle")
    }

    @Test func openWebProPicksTheWebProNav() {
        let registry = baseline()
        #expect(registry.bestMatch(for: "open WebPro")?.id == "nav.webPro")
    }

    @Test func nothingOverlappingReturnsNil() {
        let registry = baseline()
        #expect(registry.bestMatch(for: "zxqw") == nil)
    }

    @Test func emptyTextReturnsNil() {
        let registry = baseline()
        #expect(registry.bestMatch(for: "   ") == nil)
    }
}
