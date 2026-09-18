import Testing
@testable import LodiKit

@MainActor
struct HostInventoryTests {

    @Test func upsertInsertsThenReplaces() {
        let inventory = HostInventory()
        inventory.upsert(Host(alias: "sessions", hostName: "1.1.1.1"))
        #expect(inventory.hosts.count == 1)

        inventory.upsert(Host(alias: "sessions", hostName: "2.2.2.2"))
        #expect(inventory.hosts.count == 1)
        #expect(inventory.host(alias: "sessions")?.hostName == "2.2.2.2")
    }

    @Test func removeByAlias() {
        let inventory = HostInventory(hosts: HostInventory.known)
        inventory.remove(alias: "greenflash")
        #expect(inventory.host(alias: "greenflash") == nil)
        #expect(inventory.host(alias: "sessions") != nil)
    }

    @Test func knownInventoryMatchesDocs() {
        let known = HostInventory.known
        let sessions = known.first { $0.alias == "sessions" }
        let greenflash = known.first { $0.alias == "greenflash" }

        // Only the entry host carries the agent; greenflash is reached through it
        // over the private VPC address and never holds a key.
        #expect(sessions?.forwardAgent == true)
        #expect(greenflash?.forwardAgent == false)
        #expect(greenflash?.proxyJump == "sessions")
        #expect(greenflash?.hostName == "10.116.0.2")

        // Host keys are pinned from docs/hosts.md; the transport refuses a mismatch.
        #expect(sessions?.hostKeyFingerprintSHA256 == "SHA256:QSNdYT45PqF23pHNBeg92CL/Qj0XDfpYm9hZc/4CfJU")
        #expect(greenflash?.hostKeyFingerprintSHA256 == "SHA256:O01ThyuNFaUU+3eGESaMK5hF4q1a6pkIyWtSGF9UtM4")
    }
}
