import Testing
@testable import LodiKit

@MainActor
struct HostFactsTests {

    @Test func fakeProviderDescribesKnownHosts() async {
        let provider = FakeHostFactsProvider()
        let sessions = Host(alias: "sessions", hostName: "67.205.136.45")
        let facts = await provider.facts(for: sessions)

        #expect(!facts.isEmpty)
        #expect(facts.contains { $0.id == "swap" && $0.status == .warn })
    }

    @Test func greenflashSurfacesTheForeignDNS() async {
        let provider = FakeHostFactsProvider()
        let gf = Host(alias: "greenflash", hostName: "10.116.0.2")
        let facts = await provider.facts(for: gf)

        #expect(facts.contains { $0.id == "dns" && $0.status == .fail })
    }

    @Test func unknownHostIsUnknownNotEmpty() async {
        let provider = FakeHostFactsProvider()
        let facts = await provider.facts(for: Host(alias: "mystery", hostName: "1.2.3.4"))

        #expect(facts.count == 1)
        #expect(facts.first?.status == .unknown)
    }

    @Test func everyStatusHasADistinctSymbol() {
        let symbols = Set(HostFact.Status.allCases.map(\.symbol))
        #expect(symbols.count == HostFact.Status.allCases.count)
    }
}
