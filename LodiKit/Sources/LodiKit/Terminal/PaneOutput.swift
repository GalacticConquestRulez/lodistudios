import Foundation

/// Identifies a pane. In tmux control mode this wraps the `%N` pane id; before
/// control mode (v0.1 plain attach) it is the tab/session identity.
public struct PaneID: Hashable, Sendable {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }
}

/// A chunk of raw bytes produced by a pane. Raw on purpose — an LLM sink gets a
/// separate, escape-stripped stream; only the terminal view wants VT100.
public struct PaneChunk: Sendable, Equatable {
    public let pane: PaneID
    public let bytes: [UInt8]
    public init(pane: PaneID, bytes: [UInt8]) {
        self.pane = pane
        self.bytes = bytes
    }
}

/// Anything that consumes pane output. The transport broadcasts to a fan of these
/// rather than calling the terminal view directly (docs/plan.md, week-one
/// `PaneOutputSink`): the terminal is one sink, an AI observer is another, a
/// transcript recorder is another. Adding an agent to a live session is then zero
/// changes to the transport.
public protocol PaneOutputSink: AnyObject {
    func receive(_ chunk: PaneChunk)
}

/// Fans pane output out to every registered sink. Sinks are held weakly so a
/// closed terminal view detaches itself. Confine one broadcaster to a single
/// actor/queue — the transport that owns it drives it serially.
public final class PaneOutputBroadcaster {
    private struct WeakSink {
        weak var sink: (any PaneOutputSink)?
    }

    private var sinks: [WeakSink] = []

    public init() {}

    public func add(_ sink: any PaneOutputSink) {
        compact()
        guard !sinks.contains(where: { $0.sink === sink }) else { return }
        sinks.append(WeakSink(sink: sink))
    }

    public func remove(_ sink: any PaneOutputSink) {
        sinks.removeAll { $0.sink === sink || $0.sink == nil }
    }

    public func broadcast(_ chunk: PaneChunk) {
        compact()
        for entry in sinks {
            entry.sink?.receive(chunk)
        }
    }

    /// Number of live sinks; primarily for tests and diagnostics.
    public var sinkCount: Int {
        sinks.reduce(0) { $0 + ($1.sink == nil ? 0 : 1) }
    }

    private func compact() {
        sinks.removeAll { $0.sink == nil }
    }
}
