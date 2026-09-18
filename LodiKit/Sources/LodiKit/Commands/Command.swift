import Foundation

/// A parameter a command accepts. The schema is what lets the Assistant, ⌘K and
/// App Intents present and validate arguments without knowing the command.
public struct CommandParameter: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case string
        case integer
        case bool
        case host   // an alias in the host inventory
        case path
    }

    public let name: String
    public let kind: Kind
    public let isRequired: Bool
    public let summary: String

    public init(name: String, kind: Kind, isRequired: Bool = true, summary: String = "") {
        self.name = name
        self.kind = kind
        self.isRequired = isRequired
        self.summary = summary
    }
}

/// A concrete argument value passed to a command's `run`.
public enum CommandValue: Sendable, Hashable {
    case string(String)
    case integer(Int)
    case bool(Bool)
}

/// Every toggle, button, menu item and shortcut in the app is one of these
/// (docs/plan.md, week-one `CommandRegistry`). Views invoke commands and have no
/// bare actions of their own, which is what makes the Assistant, ⌘K, App Intents,
/// the `lodi` CLI and the audit log all read from one place.
public struct Command: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    /// The tool this command belongs to, or `nil` for app-wide commands
    /// (navigation, the Assistant itself).
    public let tool: LodiTool?
    public let parameters: [CommandParameter]
    /// Extra terms ⌘K matches against beyond the title (e.g. "sftp" for "Browse files").
    public let keywords: [String]
    /// Destructive commands are marked so the Assistant and UI can warn or gate.
    public let isDestructive: Bool
    /// Whether the command can run right now (e.g. requires a connected host).
    public let availability: @Sendable () -> Bool
    /// The single implementation. Everything that triggers the command runs this.
    public let run: @Sendable ([String: CommandValue]) async throws -> Void

    public init(
        id: String,
        title: String,
        subtitle: String = "",
        tool: LodiTool? = nil,
        parameters: [CommandParameter] = [],
        keywords: [String] = [],
        isDestructive: Bool = false,
        availability: @escaping @Sendable () -> Bool = { true },
        run: @escaping @Sendable ([String: CommandValue]) async throws -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.tool = tool
        self.parameters = parameters
        self.keywords = keywords
        self.isDestructive = isDestructive
        self.availability = availability
        self.run = run
    }
}

public enum CommandError: Error, Sendable, Equatable {
    case unknown(String)
    case unavailable(String)
    case missingParameter(String)
}
