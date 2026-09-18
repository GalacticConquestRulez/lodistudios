import Foundation

/// Input bound for a pane. Keyboard input and an agent's `send-keys` are the same
/// kind of thing and go through one door.
public enum PaneInput: Sendable, Equatable {
    /// Literal characters typed by the user.
    case text(String)
    /// A tmux `send-keys` token, e.g. "Enter", "C-c".
    case keys(String)
    /// Raw bytes — keystrokes from a terminal view, which are not always valid
    /// UTF-8 (control sequences, paste) and must not round-trip through String.
    case bytes([UInt8])
}

public enum PaneWriteDecision: Sendable, Equatable {
    case allow
    case confirm(reason: String)
    case deny(reason: String)
}

/// The policy in front of the write door: rate limit, confirm-before-execute,
/// read-only. Put it in while there is exactly one caller and the policy is
/// trivially "allow" (docs/plan.md, week-one `PaneWriter`).
public protocol PaneWritePolicy: Sendable {
    func evaluate(_ input: PaneInput, to pane: PaneID) -> PaneWriteDecision
}

/// v0.1 policy: one human caller, everything allowed.
public struct AllowAllPolicy: PaneWritePolicy {
    public init() {}
    public func evaluate(_ input: PaneInput, to pane: PaneID) -> PaneWriteDecision { .allow }
}

/// An observer that may watch but never type — the read-only end of the range
/// Infrastructure Pro will need.
public struct ReadOnlyPolicy: PaneWritePolicy {
    public init() {}
    public func evaluate(_ input: PaneInput, to pane: PaneID) -> PaneWriteDecision {
        .deny(reason: "read-only session")
    }
}

/// The thing that actually puts bytes on the transport. The terminal transport
/// implements this; `PaneWriter` is the policy gate in front of it.
public protocol PaneBackend: AnyObject {
    func send(_ input: PaneInput, to pane: PaneID)
}

/// The single write door. Every keystroke and every agent `send-keys` goes
/// through `write`; only an `.allow` reaches the backend. A caller that has
/// obtained user confirmation for a `.confirm` uses `forceWrite`.
public final class PaneWriter {
    private let backend: any PaneBackend
    private var policy: any PaneWritePolicy

    public init(backend: any PaneBackend, policy: any PaneWritePolicy = AllowAllPolicy()) {
        self.backend = backend
        self.policy = policy
    }

    public func setPolicy(_ policy: any PaneWritePolicy) {
        self.policy = policy
    }

    /// Evaluates policy and forwards on `.allow`. Returns the decision so the
    /// caller can surface a confirmation prompt or a denial.
    @discardableResult
    public func write(_ input: PaneInput, to pane: PaneID) -> PaneWriteDecision {
        let decision = policy.evaluate(input, to: pane)
        if case .allow = decision {
            backend.send(input, to: pane)
        }
        return decision
    }

    /// Bypasses policy for input the user has explicitly confirmed. Never call
    /// this from a non-interactive path.
    public func forceWrite(_ input: PaneInput, to pane: PaneID) {
        backend.send(input, to: pane)
    }
}
