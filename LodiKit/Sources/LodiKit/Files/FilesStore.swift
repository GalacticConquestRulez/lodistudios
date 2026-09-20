import Foundation
import Observation

/// A pending destructive action, held until the user confirms. Nothing touches the
/// remote while one of these is set — the sheet is shown first, and `cancelPending`
/// clears it without a single SFTP call (proven with a listing before and after).
public enum FilesConfirmation: Identifiable, Equatable, Sendable {
    /// Delete a remote entry.
    case delete(RemoteFile)
    /// Upload a local file whose name already exists on the remote.
    case overwrite(local: URL, remoteName: String)

    public var id: String {
        switch self {
        case .delete(let file):       "delete:\(file.path)"
        case .overwrite(_, let name): "overwrite:\(name)"
        }
    }

    public var title: String {
        switch self {
        case .delete(let file):       "Delete “\(file.name)”?"
        case .overwrite(_, let name): "Replace “\(name)”?"
        }
    }

    public var message: String {
        switch self {
        case .delete(let file):
            file.isDirectory ? "The folder and everything in it is removed on the remote."
                             : "The file is removed on the remote."
        case .overwrite:
            "A file with that name already exists on the remote and will be overwritten."
        }
    }

    public var confirmLabel: String {
        switch self {
        case .delete:    "Delete"
        case .overwrite: "Replace"
        }
    }
}

/// The model behind the Files pane: the current directory listing, the inline
/// rename/mkdir prompts, the pending-confirmation gate, and the transfer queue the
/// progress and cancel bind to. Atomic operations (list/stat/mkdir/rename/remove)
/// run over the host's interactive `HostConnection` — they are quick and were shown
/// not to touch keystroke echo; byte-moving transfers run over the injected
/// `TransferQueue` and its own bulk connection, never the PTY link.
///
/// Every mutating method here is the body of a registered `Command`; the view holds
/// no bare actions. Destructive ones set `pendingConfirmation` and wait.
@MainActor
@Observable
public final class FilesStore {
    public private(set) var host: Host?
    private var connection: HostConnection?
    public private(set) var queue: TransferQueue?

    /// The directory being shown. Absolute; navigation rewrites it.
    public private(set) var path: String = "/"
    public private(set) var entries: [RemoteFile] = []
    public private(set) var isLoading = false
    public var errorText: String?
    /// The selected row's id (its path), so rename/download/delete work by keyboard.
    public var selection: RemoteFile.ID?

    /// Whether the pane is on screen (the `files.browse` command opens it).
    public var isPresented = false

    /// The destructive action awaiting confirmation, or nil.
    public private(set) var pendingConfirmation: FilesConfirmation?

    /// Inline "New Folder" prompt.
    public var makingDirectory = false
    public var newDirectoryName = ""
    /// Inline rename prompt; non-nil means a field is showing for this entry.
    public var renameTarget: RemoteFile?
    public var renameText = ""

    private var stagedUploads: [URL] = []

    public init() {}

    public var isReady: Bool { connection != nil }
    public var selectedFile: RemoteFile? { entries.first { $0.id == selection } }

    /// Point the pane at a host: its interactive connection for atomic ops, its
    /// transfer queue for byte-moving. Called by `files.browse`.
    public func configure(host: Host, connection: HostConnection, queue: TransferQueue, startPath: String) {
        self.host = host
        self.connection = connection
        self.queue = queue
        self.path = startPath
        self.selection = nil
    }

    // MARK: - Navigation / listing

    public func refresh() async {
        guard let connection else { return }
        isLoading = true
        errorText = nil
        do { entries = try await connection.list(path) }
        catch { errorText = "\(error)"; entries = [] }
        isLoading = false
    }

    /// Descend into the selected directory (or a given one). No-op for files.
    public func open(_ file: RemoteFile?) async {
        guard let file = file ?? selectedFile, file.isDirectory else { return }
        path = file.path
        selection = nil
        await refresh()
    }

    public func goUp() async {
        let parent = Self.parent(of: path)
        guard parent != path else { return }
        path = parent
        selection = nil
        await refresh()
    }

    // MARK: - mkdir

    public func beginMakeDirectory() {
        newDirectoryName = ""
        makingDirectory = true
    }

    public func makeDirectory() async {
        makingDirectory = false
        let name = newDirectoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        newDirectoryName = ""
        guard let connection, !name.isEmpty else { return }
        do {
            try await connection.makeDirectory(Self.child(path, name))
            await refresh()
        } catch { errorText = "\(error)" }
    }

    // MARK: - rename

    public func beginRename(_ file: RemoteFile?) {
        guard let file = file ?? selectedFile else { return }
        renameTarget = file
        renameText = file.name
    }

    public func commitRename() async {
        guard let file = renameTarget else { return }
        renameTarget = nil
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let connection, !name.isEmpty, name != file.name else { return }
        do {
            try await connection.rename(file.path, to: Self.child(Self.parent(of: file.path), name))
            await refresh()
        } catch { errorText = "\(error)" }
    }

    // MARK: - delete (destructive → confirm)

    /// Ask to delete the selected entry (or a given one). Shows the sheet; nothing
    /// is removed until `confirmPending`.
    public func requestDelete(_ file: RemoteFile?) {
        guard let file = file ?? selectedFile else { return }
        pendingConfirmation = .delete(file)
    }

    // MARK: - upload / download (through the TransferQueue)

    /// Stage dropped/selected URLs for the next `performUpload` (so a drag-in still
    /// goes through the command, not a bare action).
    public func stageUploads(_ urls: [URL]) { stagedUploads = urls }

    /// Upload staged (or explicitly given) local files into the current directory.
    /// Non-colliding files start immediately; the first name collision raises an
    /// overwrite confirmation and is held until confirmed.
    public func performUpload(_ explicit: [URL]? = nil) async {
        let urls = explicit ?? stagedUploads
        stagedUploads = []
        guard let queue, !urls.isEmpty else { return }
        let existing = Set(entries.map { $0.name })
        var firstCollision: URL?
        for url in urls {
            let name = url.lastPathComponent
            if existing.contains(name) {
                if firstCollision == nil { firstCollision = url }
                continue
            }
            queue.upload(local: url, to: Self.child(path, name))
        }
        if let url = firstCollision {
            pendingConfirmation = .overwrite(local: url, remoteName: url.lastPathComponent)
        }
        await refreshWhenTransfersSettle()
    }

    /// Download the selected entry (or a given one) into a directory.
    public func download(_ file: RemoteFile?, to directory: URL) {
        guard let queue, let file = file ?? selectedFile, !file.isDirectory else { return }
        queue.download(remote: file.path, to: directory.appendingPathComponent(file.name))
    }

    /// Download an entry to a private temp directory and await completion, for a
    /// Finder drag-out. Uses the same queue/bulk link; returns the local URL or nil.
    public func downloadToTemp(_ file: RemoteFile) async -> URL? {
        guard let queue else { return nil }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lodi-drag-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(file.name)
        let id = queue.download(remote: file.path, to: dest)
        while true {
            if let transfer = queue.transfers.first(where: { $0.id == id }) {
                switch transfer.status {
                case .completed:            return dest
                case .failed, .cancelled:   return nil
                case .active:               break
                }
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    public func cancelTransfer(_ id: UUID) { queue?.cancel(id) }
    public func clearFinishedTransfers() { queue?.clearFinished() }

    /// The user's Downloads folder (falls back to temp) — where `files.download`
    /// puts a fetched file.
    public static func downloadsDirectory() -> URL {
        (try? FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask,
                                      appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
    }

    // MARK: - confirmation

    /// Run the pending destructive action. This is the only path that touches the
    /// remote for a delete/overwrite.
    public func confirmPending() async {
        guard let pending = pendingConfirmation else { return }
        pendingConfirmation = nil
        switch pending {
        case .delete(let file):
            guard let connection else { return }
            do {
                try await connection.remove(file.path, isDirectory: file.isDirectory)
                if selection == file.id { selection = nil }
                await refresh()
            } catch { errorText = "\(error)" }
        case .overwrite(let url, let name):
            queue?.upload(local: url, to: Self.child(path, name))
            await refreshWhenTransfersSettle()
        }
    }

    /// Dismiss the sheet without touching the remote.
    public func cancelPending() { pendingConfirmation = nil }

    // MARK: - helpers

    /// Refresh the listing once the active transfers have drained, so uploaded files
    /// appear without the user hitting refresh. Bounded so it never spins forever.
    private func refreshWhenTransfersSettle() async {
        guard let queue else { return }
        for _ in 0..<600 {   // ~30 s ceiling
            if queue.transfers.allSatisfy({ $0.status != .active }) { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        await refresh()
    }

    /// The parent directory path, clamped at root.
    public static func parent(of path: String) -> String {
        if path == "/" || path.isEmpty { return "/" }
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: true)
        if components.count <= 1 { return "/" }
        return "/" + components.dropLast().joined(separator: "/")
    }

    /// Join a directory and a child name into an absolute path.
    public static func child(_ directory: String, _ name: String) -> String {
        if directory == "/" { return "/\(name)" }
        return directory.hasSuffix("/") ? "\(directory)\(name)" : "\(directory)/\(name)"
    }
}
