import SwiftUI
import LodiKit

/// A line in the Assistant conversation.
struct AssistantMessage: Identifiable, Sendable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    let text: String

    static func user(_ text: String) -> AssistantMessage { .init(role: .user, text: text) }
    static func assistant(_ text: String) -> AssistantMessage { .init(role: .assistant, text: text) }
}

/// Surface 4 — the Assistant (docs/ui-review.md). A chat panel present on every
/// screen that drives the app by text: navigate, run any command, and log a
/// request when it can't. Carries pink and nothing else in the app does.
///
/// v0.1 routing is *local*: the ask is matched against the CommandRegistry with a
/// simple word-overlap score. Haiku intent-routing and Claude for real work land
/// in v0.2 — the seam is `route(_:)`, everything else stays.
struct AssistantPanelView: View {
    @Environment(CommandRegistry.self) private var registry
    @Environment(Navigator.self) private var navigator
    @Environment(RequestsStore.self) private var requests

    @State private var draft = ""
    @State private var messages: [AssistantMessage] = [
        .assistant("I can switch screens, run any command, and log a request when I can’t. Try “open WebPro”.")
    ]
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(LodiPalette.paper.opacity(0.1))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            AssistantBubble(message: message).id(message.id)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            inputBar
        }
        .background(LodiPalette.ink)
        .lodiAssistant()
    }

    private var header: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundStyle(LodiTheme.assistantAccent)
            Text("Assistant")
                .font(.headline)
                .foregroundStyle(LodiTheme.text)
            Spacer()
            Button {
                Task { try? await registry.run("assistant.toggle") }
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(LodiTheme.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask or command…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .foregroundStyle(LodiTheme.text)
                .focused($inputFocused)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(LodiTheme.assistantAccent)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(12)
        .background(LodiPalette.paper.opacity(0.04))
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        messages.append(.user(text))
        route(text)
    }

    private func route(_ text: String) {
        if let best = bestCommand(for: text) {
            messages.append(.assistant("Running “\(best.title)”."))
            Task { try? await registry.run(best.id) }
        } else {
            requests.log(text, tool: navigator.destination.tool, screen: navigator.destination.screenName)
            messages.append(.assistant("I can’t do that yet — logged it to Requests so it becomes a spec."))
        }
    }

    /// Word-overlap over each available command's title, subtitle and keywords.
    /// Unlike ⌘K's prefix search this tolerates a natural phrasing like
    /// "open WebPro" or "turn on the assistant".
    private func bestCommand(for text: String) -> Command? {
        let words = text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        guard !words.isEmpty else { return nil }

        func score(_ command: Command) -> Int {
            let hay = ([command.title, command.subtitle] + command.keywords)
                .joined(separator: " ")
                .lowercased()
            return words.reduce(0) { $0 + (hay.contains($1) ? 1 : 0) }
        }

        return registry.available
            .map { ($0, score($0)) }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }?
            .0
    }
}

private struct AssistantBubble: View {
    let message: AssistantMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 24) }
            Text(message.text)
                .foregroundStyle(LodiTheme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bubbleStyle, in: RoundedRectangle(cornerRadius: 12))
            if message.role == .assistant { Spacer(minLength: 24) }
        }
    }

    private var bubbleStyle: AnyShapeStyle {
        switch message.role {
        case .user:      AnyShapeStyle(LodiTheme.assistantAccent.opacity(0.25))
        case .assistant: AnyShapeStyle(LodiPalette.paper.opacity(0.06))
        }
    }
}
