import SwiftUI
import LodiKit

/// ⌘K — the primary navigation (docs/ui-review.md, gap 3). A search field over
/// the CommandRegistry: type, and the ranked matches are what you can run. Every
/// row is a real Command, so anything the app can do is reachable here the day it
/// is registered.
struct CommandPaletteView: View {
    @Environment(CommandRegistry.self) private var registry
    @Environment(Navigator.self) private var navigator

    @State private var query = ""
    @FocusState private var fieldFocused: Bool

    private var results: [Command] { registry.search(query) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { navigator.closePalette() }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(LodiTheme.secondaryText)
                    TextField("Jump to a tool or run a command…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .foregroundStyle(LodiTheme.text)
                        .focused($fieldFocused)
                        .onSubmit(runFirst)
                }
                .padding(16)

                Divider().overlay(LodiPalette.paper.opacity(0.1))

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(results) { command in
                            Button { run(command) } label: {
                                CommandRow(command: command)
                            }
                            .buttonStyle(.plain)
                        }
                        if results.isEmpty {
                            Text("No commands match “\(query)”")
                                .foregroundStyle(LodiTheme.secondaryText)
                                .padding(16)
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
            .frame(width: 560)
            .background(LodiPalette.ink)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(LodiPalette.paper.opacity(0.12))
            )
            .shadow(radius: 30)
        }
        .onAppear { fieldFocused = true }
        #if os(macOS)
        .onExitCommand { navigator.closePalette() }
        #endif
    }

    private func runFirst() {
        if let first = results.first { run(first) }
    }

    private func run(_ command: Command) {
        navigator.closePalette()
        Task { try? await registry.run(command.id) }
    }
}

/// One command in the palette. The tool's primary tints only the leading glyph —
/// wayfinding, not decoration; status colours never appear here.
private struct CommandRow: View {
    let command: Command

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: command.tool?.systemImage ?? "command")
                .frame(width: 20)
                .foregroundStyle(command.tool?.accent ?? LodiTheme.secondaryText)
            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .foregroundStyle(LodiTheme.text)
                if !command.subtitle.isEmpty {
                    Text(command.subtitle)
                        .font(.caption)
                        .foregroundStyle(LodiTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            if command.isDestructive {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(LodiTheme.statusWarn)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
