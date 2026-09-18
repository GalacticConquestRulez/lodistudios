import Foundation

public enum SSHTransportState: Sendable, Equatable {
    case idle
    case connecting
    case connected
    case disconnected(reason: String?)
}

/// The transport seam. The v1 implementation is embedded libssh2 with the app as
/// its own agent (docs/plan.md); everything above it — tabs, the Board, WebPro,
/// Infrastructure Pro — codes against this protocol so the C core can be built and
/// swapped in behind it. v0.1 opens a shell that runs `tmux new -A -s <name>`, so
/// the persistent session lives on the droplet and the transport is disposable.
public protocol SSHTransport: AnyObject {
    var state: SSHTransportState { get }

    func connect(to host: Host) async throws
    func disconnect() async

    /// Opens an interactive terminal, optionally running a command (the tmux
    /// attach). Returns the pane whose output the broadcaster will carry.
    func openTerminal(command: String?) async throws -> PaneID
}

/// An in-memory transport for previews and tests, so UI and command flows can be
/// exercised before the libssh2 core exists.
public final class FakeSSHTransport: SSHTransport {
    public private(set) var state: SSHTransportState = .idle
    public private(set) var connectedHost: Host?
    private var paneCounter = 0

    public init() {}

    public func connect(to host: Host) async throws {
        state = .connecting
        connectedHost = host
        state = .connected
    }

    public func disconnect() async {
        connectedHost = nil
        state = .disconnected(reason: nil)
    }

    public func openTerminal(command: String?) async throws -> PaneID {
        guard case .connected = state else {
            throw CommandError.unavailable("transport not connected")
        }
        paneCounter += 1
        return PaneID("fake-\(paneCounter)")
    }
}
