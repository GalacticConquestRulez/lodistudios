import Testing
@testable import LodiKit

struct SSHHostFactsTests {
    /// Representative output of the provider's script from a real droplet.
    private let sample = """
    ###disk
    Filesystem     1024-blocks     Used Available Capacity Mounted on
    /dev/vda1         81120644 31237120  45719044      41% /
    ###mem
                   total        used        free      shared  buff/cache   available
    Mem:            3928        1893         210          12        1824        1740
    Swap:           4095        1946        2149
    ###load
     15:04:12 up 3 days,  2:11,  1 user,  load average: 0.42, 0.31, 0.28
    """

    @Test func parsesDiskMemSwapLoad() {
        let facts = SSHHostFactsProvider.parse(sample)
        let byID = Dictionary(uniqueKeysWithValues: facts.map { ($0.id, $0) })

        #expect(byID["disk"]?.value == "41% of 77 GB")
        #expect(byID["disk"]?.status == .ok)
        #expect(byID["mem"]?.value == "1893 of 3928 MB")
        #expect(byID["swap"]?.value == "1946 of 4095 MB")
        #expect(byID["swap"]?.status == .warn)          // ~48% in swap
        #expect(byID["load"]?.value == "0.42")
    }

    @Test func diskCapacityDrivesStatus() {
        let warn = SSHHostFactsProvider.diskFact(["/dev/vda1 100 80 20 85% /"])
        #expect(warn?.status == .warn)
        let fail = SSHHostFactsProvider.diskFact(["/dev/vda1 100 95 5 95% /"])
        #expect(fail?.status == .fail)
    }

    @Test func idleSwapIsOkAndReadsNone() {
        let facts = SSHHostFactsProvider.memFacts(["Mem: 3928 500 3000", "Swap: 4095 0 4095"])
        let swap = facts.first { $0.id == "swap" }
        #expect(swap?.value == "none")
        #expect(swap?.status == .ok)
    }

    @Test func emptyOutputParsesToNothing() {
        #expect(SSHHostFactsProvider.parse("").isEmpty)
    }
}
