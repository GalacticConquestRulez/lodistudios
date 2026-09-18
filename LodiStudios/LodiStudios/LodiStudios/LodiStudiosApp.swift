import SwiftUI
import LodiKit
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Copy a string to the system pasteboard, cross-platform.
@MainActor func lodiCopyToPasteboard(_ string: String) {
    #if canImport(AppKit)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
    #elseif canImport(UIKit)
    UIPasteboard.general.string = string
    #endif
}

/// The app is one app for five tools: same chrome, same sidebar, same command
/// surface (docs/plan.md). Dark only, black ground, white text.
@main
struct LodiStudiosApp: App {
    @State private var registry = CommandRegistry()
    @State private var inventory = HostInventory(hosts: HostInventory.known)
    @State private var navigator = Navigator()
    @State private var requests = RequestsStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(registry)
                .environment(inventory)
                .environment(navigator)
                .environment(requests)
                .preferredColorScheme(.dark)
                .task {
                    registerBaselineCommands()
                    ensureDeviceIdentity()
                }
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
    }

    /// The comment on the device key line, so an authorized_keys entry says which
    /// machine it came from.
    static var keyComment: String { "lodistudios@" + ProcessInfo.processInfo.hostName }

    /// Generate the device SSH key on first launch (kept in the Keychain) and
    /// mirror the public half to Application Support so it can be read and added
    /// to a host's authorized_keys. The private half never leaves the Keychain.
    @MainActor private func ensureDeviceIdentity() {
        guard let line = try? SSHKeyStore().publicKeyOpenSSH(comment: Self.keyComment) else { return }
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )) ?? URL.temporaryDirectory
        let dir = base.appendingPathComponent("LodiStudios", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? Data((line + "\n").utf8).write(
            to: dir.appendingPathComponent("id_ed25519.pub"), options: .atomic
        )
    }

    /// The baseline commands, so the registry is real from day one and the
    /// sidebar, ⌘K and the Assistant all reach navigation through it. Each body
    /// hops to the main actor to touch the `Navigator`.
    @MainActor private func registerBaselineCommands() {
        guard registry.all.isEmpty else { return }
        let navigator = navigator

        registry.register([
            Command(id: "nav.board", title: "Go to Board",
                    subtitle: "The live front page: what is running, broken, waiting",
                    keywords: ["home", "front"]) { _ in
                await MainActor.run { navigator.go(to: .board) }
            },
            Command(id: "palette.open", title: "Open Command Palette",
                    subtitle: "Jump to any tool or run any command",
                    keywords: ["cmdk", "search", "jump", "run"]) { _ in
                await MainActor.run { navigator.openPalette() }
            },
            Command(id: "palette.close", title: "Close Command Palette",
                    keywords: ["dismiss", "escape"]) { _ in
                await MainActor.run { navigator.closePalette() }
            },
            Command(id: "assistant.toggle", title: "Toggle Assistant",
                    subtitle: "The chat panel that drives every command",
                    keywords: ["chat", "ai", "open", "close"]) { _ in
                await MainActor.run { navigator.toggleAssistant() }
            },
            Command(id: "ssh.copyPublicKey", title: "Copy SSH Public Key",
                    subtitle: "The app's device key, to add to a host's authorized_keys",
                    keywords: ["ssh", "key", "authorized", "clipboard", "identity"]) { _ in
                let line = (try? SSHKeyStore().publicKeyOpenSSH(comment: Self.keyComment)) ?? ""
                await MainActor.run { lodiCopyToPasteboard(line) }
            },
        ])

        for tool in LodiTool.allCases {
            registry.register(
                Command(id: "nav.\(tool.rawValue)", title: "Go to \(tool.title)",
                        tool: tool, keywords: ["open", "switch"]) { _ in
                    await MainActor.run { navigator.go(to: .tool(tool)) }
                }
            )
        }
    }
}
