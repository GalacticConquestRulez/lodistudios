import Testing
@testable import LodiKit

@MainActor
struct CommandRegistryTests {

    @Test func registersAndLooksUpById() {
        let registry = CommandRegistry()
        registry.register(Command(id: "nav.board", title: "Go to Board") { _ in })
        #expect(registry.command(id: "nav.board")?.title == "Go to Board")
        #expect(registry.all.count == 1)
    }

    @Test func runInvokesTheBody() async throws {
        let registry = CommandRegistry()
        let flag = Flag()
        registry.register(Command(id: "do.thing", title: "Do") { _ in await flag.set() })
        try await registry.run("do.thing")
        #expect(await flag.value)
    }

    @Test func runThrowsOnUnknown() async {
        let registry = CommandRegistry()
        await #expect(throws: CommandError.unknown("missing")) {
            try await registry.run("missing")
        }
    }

    @Test func runThrowsWhenUnavailable() async {
        let registry = CommandRegistry()
        registry.register(Command(id: "x", title: "X", availability: { false }) { _ in })
        await #expect(throws: CommandError.unavailable("x")) {
            try await registry.run("x")
        }
    }

    @Test func runThrowsOnMissingRequiredParameter() async {
        let registry = CommandRegistry()
        registry.register(Command(
            id: "connect",
            title: "Connect",
            parameters: [CommandParameter(name: "host", kind: .host)]
        ) { _ in })
        await #expect(throws: CommandError.missingParameter("host")) {
            try await registry.run("connect")
        }
    }

    @Test func availableFiltersOnAvailability() {
        let registry = CommandRegistry()
        registry.register(Command(id: "on", title: "On") { _ in })
        registry.register(Command(id: "off", title: "Off", availability: { false }) { _ in })
        #expect(registry.available.map(\.id) == ["on"])
    }

    @Test func searchRanksTitlePrefixFirst() {
        let registry = CommandRegistry()
        registry.register(Command(id: "a", title: "Open SFTP browser", subtitle: "connect files") { _ in })
        registry.register(Command(id: "b", title: "Connect to host", keywords: ["ssh"]) { _ in })
        let ids = registry.search("connect").map(\.id)
        // "Connect to host" is a title prefix; the other only matches in subtitle.
        #expect(ids.first == "b")
        #expect(ids.contains("a"))
    }
}

/// A tiny actor for observing side effects from a `@Sendable` command body.
actor Flag {
    private(set) var value = false
    func set() { value = true }
}
