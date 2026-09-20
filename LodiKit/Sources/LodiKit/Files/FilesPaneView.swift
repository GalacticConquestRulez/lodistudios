import SwiftUI
import UniformTypeIdentifiers

/// The Files pane for a host: a remote directory listing with drag-in upload,
/// drag-out download, and rename / mkdir / delete — every one of them a registered
/// `Command` invoked through the `CommandRegistry`, never a bare action. Delete and
/// overwrite are gated behind a confirm sheet (`FilesStore.pendingConfirmation`);
/// transfers show the `TransferQueue`'s progress and cancel, not a second copy.
///
/// Lives in LodiKit so it is one implementation for Mac and iPhone. Drag uses the
/// cross-platform SwiftUI `.dropDestination` / `.draggable` seams.
public struct FilesPaneView: View {
    @Environment(FilesStore.self) private var store
    @Environment(CommandRegistry.self) private var registry
    @Environment(\.lodiAccent) private var accent

    @FocusState private var mkdirFocused: Bool
    @FocusState private var renameFocused: Bool

    public init() {}

    public var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            header
            Divider().overlay(LodiPalette.paper.opacity(0.12))
            listing
            if !(store.queue?.transfers.isEmpty ?? true) {
                Divider().overlay(LodiPalette.paper.opacity(0.12))
                transfers
            }
            if let error = store.errorText {
                Text(error)
                    .font(.caption).foregroundStyle(LodiTheme.statusFail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 6)
            }
        }
        .frame(minWidth: 480, minHeight: 420)
        .background(LodiTheme.ground)
        .task { await store.refresh() }
        .sheet(isPresented: Binding(
            get: { store.pendingConfirmation != nil },
            set: { if !$0 { store.cancelPending() } }
        )) {
            if let pending = store.pendingConfirmation {
                ConfirmSheet(confirmation: pending,
                             onConfirm: { run("files.confirm") },
                             onCancel: { store.cancelPending() })
            }
        }
    }

    // MARK: - Header (all operations are Commands)

    private var header: some View {
        HStack(spacing: 10) {
            Button { run("files.up") } label: { Image(systemName: "chevron.up") }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .help("Enclosing folder (⌘↑)")

            Text(store.path)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(LodiTheme.text)
                .lineLimit(1).truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button { run("files.refresh") } label: { Image(systemName: "arrow.clockwise") }
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh (⌘R)")
            Button { run("files.mkdir.begin") } label: { Image(systemName: "folder.badge.plus") }
                .keyboardShortcut("n", modifiers: .command)
                .help("New Folder (⌘N)")
            Button { run("files.rename.begin") } label: { Image(systemName: "pencil") }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(store.selectedFile == nil)
                .help("Rename (⌘⇧R)")
            Button { run("files.download") } label: { Image(systemName: "arrow.down.circle") }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(store.selectedFile?.isDirectory ?? true)
                .help("Download to Downloads (⌘D)")
            Button(role: .destructive) { run("files.delete") } label: { Image(systemName: "trash") }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(store.selectedFile == nil)
                .help("Delete (⌘⌫)")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .tint(accent)
    }

    // MARK: - Listing

    private var listing: some View {
        @Bindable var store = store
        return List(selection: $store.selection) {
            if store.makingDirectory {
                mkdirRow
            }
            ForEach(store.entries) { file in
                row(for: file)
                    .tag(file.id)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(LodiTheme.ground)
        // Drag files in from Finder → upload into the current directory.
        .dropDestination(for: URL.self) { urls, _ in
            store.stageUploads(urls)
            run("files.upload")
            return true
        }
        .overlay {
            if store.isLoading {
                ProgressView().controlSize(.small)
            } else if store.entries.isEmpty && !store.makingDirectory {
                Text("Empty").foregroundStyle(LodiTheme.secondaryText)
            }
        }
    }

    @ViewBuilder private func row(for file: RemoteFile) -> some View {
        if renameFocusedTarget(file) {
            renameRow(file)
        } else {
            HStack(spacing: 10) {
                Image(systemName: icon(for: file))
                    .foregroundStyle(file.isDirectory ? accent : LodiTheme.secondaryText)
                    .frame(width: 18)
                Text(file.name)
                    .foregroundStyle(LodiTheme.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(file.isDirectory ? "—" : file.displaySize)
                    .font(.caption.monospacedDigit()).foregroundStyle(LodiTheme.secondaryText)
                    .frame(width: 70, alignment: .trailing)
                Text(file.permissionString)
                    .font(.caption.monospaced()).foregroundStyle(LodiTheme.secondaryText)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { store.selection = file.id; run("files.open") }
            .draggable(RemoteFileExport(store: store, file: file))
            .contextMenu {
                if file.isDirectory {
                    Button("Open") { store.selection = file.id; run("files.open") }
                } else {
                    Button("Download") { store.selection = file.id; run("files.download") }
                }
                Button("Rename…") { store.selection = file.id; run("files.rename.begin") }
                Divider()
                Button("Delete…", role: .destructive) { store.selection = file.id; run("files.delete") }
            }
        }
    }

    private func renameFocusedTarget(_ file: RemoteFile) -> Bool {
        store.renameTarget?.id == file.id
    }

    @ViewBuilder private var mkdirRow: some View {
        @Bindable var store = store
        HStack(spacing: 10) {
            Image(systemName: "folder.badge.plus").foregroundStyle(accent).frame(width: 18)
            TextField("New folder name", text: $store.newDirectoryName)
                .textFieldStyle(.plain)
                .foregroundStyle(LodiTheme.text)
                .focused($mkdirFocused)
                .onSubmit { run("files.mkdir") }
                #if os(macOS)
                .onExitCommand { store.makingDirectory = false }
                #endif
        }
        .onAppear { mkdirFocused = true }
    }

    @ViewBuilder private func renameRow(_ file: RemoteFile) -> some View {
        @Bindable var store = store
        HStack(spacing: 10) {
            Image(systemName: icon(for: file)).foregroundStyle(accent).frame(width: 18)
            TextField("Name", text: $store.renameText)
                .textFieldStyle(.plain)
                .foregroundStyle(LodiTheme.text)
                .focused($renameFocused)
                .onSubmit { run("files.rename") }
                #if os(macOS)
                .onExitCommand { store.renameTarget = nil }
                #endif
        }
        .onAppear { renameFocused = true }
    }

    private func icon(for file: RemoteFile) -> String {
        if file.isDirectory { return "folder" }
        if file.isSymlink { return "arrow.up.right" }
        return "doc"
    }

    // MARK: - Transfers (the queue's progress and cancel)

    private var transfers: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Transfers").font(.caption.weight(.semibold)).foregroundStyle(LodiTheme.secondaryText)
                Spacer()
                Button("Clear finished") { store.clearFinishedTransfers() }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(accent)
            }
            ForEach(store.queue?.transfers ?? []) { transfer in
                HStack(spacing: 8) {
                    Image(systemName: transfer.direction == .upload ? "arrow.up" : "arrow.down")
                        .font(.caption).foregroundStyle(LodiTheme.secondaryText)
                    Text(transfer.name).font(.caption).foregroundStyle(LodiTheme.text).lineLimit(1)
                    ProgressView(value: transfer.fraction)
                        .frame(width: 120)
                    Text(statusText(transfer)).font(.caption2).foregroundStyle(statusColor(transfer))
                    Spacer()
                    if transfer.status == .active {
                        Button { store.cancelTransfer(transfer.id) } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain).foregroundStyle(LodiTheme.statusWarn)
                        .help("Cancel")
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func statusText(_ t: TransferQueue.Transfer) -> String {
        switch t.status {
        case .active:    "\(Int(t.fraction * 100))%"
        case .completed: "done"
        case .cancelled: "cancelled"
        case .failed:    "failed"
        }
    }

    private func statusColor(_ t: TransferQueue.Transfer) -> Color {
        switch t.status {
        case .active:    LodiTheme.secondaryText
        case .completed: LodiTheme.statusOk
        case .cancelled: LodiTheme.statusWarn
        case .failed:    LodiTheme.statusFail
        }
    }

    private func run(_ id: String) {
        Task { try? await registry.run(id) }
    }
}

/// The destructive confirm shown before a delete or an overwrite touches the remote.
private struct ConfirmSheet: View {
    let confirmation: FilesConfirmation
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(confirmation.title).font(.headline).foregroundStyle(LodiTheme.text)
            Text(confirmation.message).font(.callout).foregroundStyle(LodiTheme.secondaryText)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(confirmation.confirmLabel, role: .destructive, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .background(LodiTheme.ground)
    }
}

/// A remote file exported for a Finder drag-out: it downloads on demand through the
/// same `TransferQueue`/bulk link and hands the receiver a real local file.
struct RemoteFileExport: Transferable {
    let store: FilesStore
    let file: RemoteFile

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .data) { export in
            guard let url = await export.store.downloadToTemp(export.file) else {
                throw CocoaError(.fileNoSuchFile)
            }
            return SentTransferredFile(url)
        }
    }
}
