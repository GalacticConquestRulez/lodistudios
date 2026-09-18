import Foundation
import Observation

/// The one place commands are registered and looked up. Put it in while there are
/// ten commands, not four hundred (docs/plan.md). The Assistant's tool list is
/// generated from `available`, ⌘K uses `search`, and every invocation path funnels
/// through `run` so the audit log has a single choke point.
///
/// Main-actor isolated: the UI, ⌘K and menus all drive it from the main actor,
/// and command bodies hop to their own executors as needed.
@MainActor
@Observable
public final class CommandRegistry {
    private var storage: [String: Command] = [:]
    private var order: [String] = []

    public init() {}

    // MARK: Registration

    /// Registers a command. Ids are unique by construction — a collision is a
    /// programming error, not a runtime condition.
    public func register(_ command: Command) {
        precondition(storage[command.id] == nil, "duplicate command id: \(command.id)")
        storage[command.id] = command
        order.append(command.id)
    }

    public func register(_ commands: [Command]) {
        for command in commands { register(command) }
    }

    // MARK: Lookup

    public func command(id: String) -> Command? {
        storage[id]
    }

    /// All commands in registration order.
    public var all: [Command] {
        order.compactMap { storage[$0] }
    }

    /// Only the commands that can run right now — this is the Assistant's tool list.
    public var available: [Command] {
        all.filter { $0.availability() }
    }

    public func commands(for tool: LodiTool) -> [Command] {
        all.filter { $0.tool == tool }
    }

    /// Ranked matches for ⌘K. Available commands only; title matches beat keyword
    /// matches beat subtitle matches, and prefix beats contains within each.
    public func search(_ query: String) -> [Command] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return available }

        func score(_ c: Command) -> Int? {
            let title = c.title.lowercased()
            if title.hasPrefix(q) { return 0 }
            if title.contains(q) { return 1 }
            if c.keywords.contains(where: { $0.lowercased().contains(q) }) { return 2 }
            if c.subtitle.lowercased().contains(q) { return 3 }
            return nil
        }

        return available
            .compactMap { c in score(c).map { (c, $0) } }
            .sorted { $0.1 < $1.1 }
            .map { $0.0 }
    }

    // MARK: Invocation

    /// The single door every trigger goes through. Throws rather than silently
    /// no-op'ing so callers (and the audit log) see unknown/unavailable clearly.
    public func run(_ id: String, arguments: [String: CommandValue] = [:]) async throws {
        guard let command = storage[id] else { throw CommandError.unknown(id) }
        guard command.availability() else { throw CommandError.unavailable(id) }

        for parameter in command.parameters where parameter.isRequired {
            if arguments[parameter.name] == nil {
                throw CommandError.missingParameter(parameter.name)
            }
        }

        try await command.run(arguments)
    }
}
