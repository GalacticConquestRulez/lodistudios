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

/// Write a small file under the app's Application Support/LodiStudios directory.
/// Used to mirror the public key and the M1 probe result where they can be read.
func lodiWriteAppSupport(_ name: String, _ text: String) {
    let base = (try? FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask,
        appropriateFor: nil, create: true
    )) ?? URL.temporaryDirectory
    let dir = base.appendingPathComponent("LodiStudios", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? Data(text.utf8).write(to: dir.appendingPathComponent(name), options: .atomic)
}

/// The app is one app for five tools: same chrome, same sidebar, same command
/// surface (docs/plan.md). Dark only, black ground, white text.
@main
struct LodiStudiosApp: App {
    @State private var registry = CommandRegistry()
    @State private var inventory = HostInventory(hosts: HostInventory.known)
    @State private var navigator = Navigator()
    @State private var requests = RequestsStore()
    @State private var terminals = TerminalStore()
    /// The Board's own agent, so its periodic fact-gathering signs independently
    /// of the terminal sessions.
    @State private var boardAgent = SSHAgent(keyStore: SSHKeyStore(), comment: "lodistudios")

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(registry)
                .environment(inventory)
                .environment(navigator)
                .environment(requests)
                .environment(terminals)
                .environment(\.hostFacts, SSHHostFactsProvider(agentSocketPath: boardAgent.socketPath))
                .preferredColorScheme(.dark)
                .task {
                    registerBaselineCommands()
                    ensureDeviceIdentity()
                    try? boardAgent.start()
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
        lodiWriteAppSupport("id_ecdsa.pub", line + "\n")
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
            Command(id: "net.sessionsUname", title: "Connect to Sessions, run uname",
                    subtitle: "Transport proof — SSH to the session droplet via the in-app agent",
                    keywords: ["ssh", "connect", "sessions", "uname", "probe", "agent"]) { _ in
                guard let sessions = HostInventory.known.first(where: { $0.alias == "sessions" }) else { return }
                let agent = SSHAgent(keyStore: SSHKeyStore(), comment: Self.keyComment)
                do {
                    try agent.start()
                    defer { agent.stop() }
                    let session = SSHSession(host: sessions, agentSocketPath: agent.socketPath, agentComment: Self.keyComment)
                    // M2b: authenticate through the agent.
                    let uname = try await session.run("uname -a")
                    lodiWriteAppSupport("m2-uname.txt", "OK exit=\(uname.exitStatus)\n\(uname.stdout)")
                    // M2c: forward the agent and prove a remote shell sees the key.
                    let forwarded = try await session.run(
                        "echo AUTH_SOCK=$SSH_AUTH_SOCK; ssh-add -l 2>&1; echo rc=$?",
                        forwardAgent: true
                    )
                    lodiWriteAppSupport("m2-agent.txt", "exit=\(forwarded.exitStatus)\n\(forwarded.stdout)")
                } catch {
                    lodiWriteAppSupport("m2-uname.txt", "ERR \(error)\n")
                }
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
