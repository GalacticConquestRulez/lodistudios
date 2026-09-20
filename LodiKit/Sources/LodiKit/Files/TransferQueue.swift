import Foundation

/// The single owner of transfer progress and cancellation (owner's rule, v0.2
/// SFTP: "Transfers through one TransferQueue with progress and cancel, so the
/// terminal stays responsive"). It holds the observable list the Files pane binds
/// to and moves bytes over a *separate* bulk `HostConnection` — never the terminal's
/// PTY link — because a saturating 50 MB transfer multiplexed onto the PTY
/// connection cost +18 ms of keystroke echo (over the ~10 ms budget). The bulk link
/// opens lazily on the first transfer and closes itself after ~60 s idle; it reuses
/// HostConnection's handshake, agent auth, keepalive and dead-link detection
/// unchanged (it is a second instance, not a second design).
///
/// Progress and completion closures fire on the bulk connection's loop thread; this
/// type hops them to the main actor so the UI mutates state on one actor only.
@MainActor
@Observable
public final class TransferQueue {
    public enum Direction: Sendable { case upload, download }

    public enum Status: Sendable, Equatable {
        case active
        case completed
        case cancelled
        case failed(String)
    }

    public struct Transfer: Identifiable, Sendable {
        public let id: UUID
        public let name: String
        public let direction: Direction
        public var transferred: UInt64
        public var total: UInt64
        public var status: Status

        /// 0…1; 0 until the total is known (download stats the remote first).
        public var fraction: Double { total == 0 ? 0 : min(1, Double(transferred) / Double(total)) }
    }

    private let host: Host
    private let keyStore: SSHKeyStore
    private let agentSocketPath: String?

    /// The lazily-opened bulk link and the timer that closes it once idle.
    private var bulk: HostConnection?
    private var idleCloseTask: Task<Void, Never>?
    /// How long the bulk link lingers with no active transfer before closing.
    private let idleCloseSeconds: UInt64 = 60

    public private(set) var transfers: [Transfer] = []

    public init(host: Host, keyStore: SSHKeyStore = SSHKeyStore(), agentSocketPath: String?) {
        self.host = host
        self.keyStore = keyStore
        self.agentSocketPath = agentSocketPath
    }

    /// Queue an upload; returns the id so a Command can later cancel it.
    @discardableResult
    public func upload(local: URL, to remote: String) -> UUID {
        let id = UUID()
        transfers.append(Transfer(id: id, name: local.lastPathComponent, direction: .upload,
                                  transferred: 0, total: 0, status: .active))
        connection().upload(local: local, to: remote, id: id,
                            progress: { [weak self] done, total in
                                Task { @MainActor in self?.update(id, done: done, total: total) }
                            },
                            completion: { [weak self] result in
                                Task { @MainActor in self?.finish(id, result: result) }
                            })
        return id
    }

    /// Queue a download; returns the id so a Command can later cancel it.
    @discardableResult
    public func download(remote: String, to local: URL) -> UUID {
        let id = UUID()
        let name = (remote as NSString).lastPathComponent
        transfers.append(Transfer(id: id, name: name, direction: .download,
                                  transferred: 0, total: 0, status: .active))
        connection().download(remote: remote, to: local, id: id,
                             progress: { [weak self] done, total in
                                 Task { @MainActor in self?.update(id, done: done, total: total) }
                             },
                             completion: { [weak self] result in
                                 Task { @MainActor in self?.finish(id, result: result) }
                             })
        return id
    }

    /// Cancel an in-flight transfer. The stream stops, the queue entry is marked
    /// `.cancelled`, and the connection removes/marks the partial on the far side.
    public func cancel(_ id: UUID) {
        bulk?.cancelTransfer(id)
    }

    /// Drop finished entries from the list (completed, cancelled or failed).
    public func clearFinished() {
        transfers.removeAll { $0.status != .active }
    }

    // MARK: - Bulk link lifecycle

    /// The bulk connection, opened on first use. Any pending idle-close is cancelled
    /// because a fresh transfer is about to run.
    private func connection() -> HostConnection {
        idleCloseTask?.cancel()
        idleCloseTask = nil
        if let bulk { return bulk }
        let conn = HostConnection(host: host, role: .bulk,
                                  keyStore: keyStore, agentSocketPath: agentSocketPath)
        conn.start()
        bulk = conn
        return conn
    }

    /// Once no transfer is active, close the bulk link after the idle window unless
    /// a new transfer arrives first (which cancels this task via `connection()`).
    private func scheduleIdleClose() {
        guard transfers.allSatisfy({ $0.status != .active }) else { return }
        idleCloseTask?.cancel()
        let seconds = idleCloseSeconds
        idleCloseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            if self.transfers.allSatisfy({ $0.status != .active }) {
                self.bulk?.stop()
                self.bulk = nil
            }
        }
    }

    private func update(_ id: UUID, done: UInt64, total: UInt64) {
        guard let i = transfers.firstIndex(where: { $0.id == id }) else { return }
        transfers[i].transferred = done
        transfers[i].total = total
    }

    private func finish(_ id: UUID, result: Result<Void, Error>) {
        guard let i = transfers.firstIndex(where: { $0.id == id }) else { return }
        switch result {
        case .success:
            transfers[i].status = .completed
        case .failure(let error):
            if case HostConnection.SFTPError.cancelled = error {
                transfers[i].status = .cancelled
            } else {
                transfers[i].status = .failed("\(error)")
            }
        }
        scheduleIdleClose()
    }
}
