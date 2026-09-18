import SwiftUI
import SwiftTerm
import LodiKit
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// Hosts SwiftTerm's `TerminalView` and wires it to an `SSHTerminalSession`:
/// remote output feeds the view (as a `PaneOutputSink`), keystrokes and resizes go
/// back to the session (docs/specs/transport-v0.1.md, milestone 3). One renderer
/// on both platforms; only the chrome around it carries the tool accent.
struct TerminalPaneView {
    let session: SSHTerminalSession

    final class Coordinator: NSObject, TerminalViewDelegate, PaneOutputSink {
        let session: SSHTerminalSession
        weak var terminal: TerminalView?
        private var started = false
        /// The one input door — a human's keys and an agent's send-keys alike go
        /// through the writer's policy gate, never straight to the backend.
        private lazy var writer = PaneWriter(backend: session)

        init(session: SSHTerminalSession) { self.session = session }

        /// Bind the view, register as the output sink, and start the session once.
        func attach(_ terminal: TerminalView) {
            self.terminal = terminal
            terminal.terminalDelegate = self
            guard !started else { return }
            started = true
            session.broadcaster.add(self)
            session.start()
        }

        // PaneOutputSink — remote bytes → the view, on the main thread.
        func receive(_ chunk: PaneChunk) {
            let bytes = chunk.bytes
            DispatchQueue.main.async { [weak self] in
                self?.terminal?.feed(byteArray: bytes[...])
            }
        }

        // TerminalViewDelegate
        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            _ = writer.write(.text(String(decoding: data, as: UTF8.self)), to: session.pane)
        }
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            session.resize(cols: Int32(newCols), rows: Int32(newRows))
        }
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
        func bell(source: TerminalView) {}
        func clipboardCopy(source: TerminalView, content: Data) {}
        func clipboardRead(source: TerminalView) -> Data? { nil }
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}

#if canImport(AppKit)
extension TerminalPaneView: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(session: session) }
    func makeNSView(context: Context) -> TerminalView {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 900, height: 520))
        context.coordinator.attach(view)
        return view
    }
    func updateNSView(_ nsView: TerminalView, context: Context) {}
}
#else
extension TerminalPaneView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(session: session) }
    func makeUIView(context: Context) -> TerminalView {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 900, height: 520))
        context.coordinator.attach(view)
        return view
    }
    func updateUIView(_ uiView: TerminalView, context: Context) {}
}
#endif
