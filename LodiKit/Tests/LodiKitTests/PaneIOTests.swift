import Testing
@testable import LodiKit

struct PaneIOTests {

    final class CollectingSink: PaneOutputSink {
        var chunks: [PaneChunk] = []
        func receive(_ chunk: PaneChunk) { chunks.append(chunk) }
    }

    final class RecordingBackend: PaneBackend {
        var sent: [(PaneInput, PaneID)] = []
        func send(_ input: PaneInput, to pane: PaneID) { sent.append((input, pane)) }
    }

    @Test func broadcastReachesEverySink() {
        let broadcaster = PaneOutputBroadcaster()
        let a = CollectingSink()
        let b = CollectingSink()
        broadcaster.add(a)
        broadcaster.add(b)

        let chunk = PaneChunk(pane: PaneID("%1"), bytes: [0x68, 0x69])
        broadcaster.broadcast(chunk)

        #expect(a.chunks == [chunk])
        #expect(b.chunks == [chunk])
    }

    @Test func addingSameSinkTwiceIsIdempotent() {
        let broadcaster = PaneOutputBroadcaster()
        let sink = CollectingSink()
        broadcaster.add(sink)
        broadcaster.add(sink)
        broadcaster.broadcast(PaneChunk(pane: PaneID("%1"), bytes: [0x2a]))
        #expect(sink.chunks.count == 1)
    }

    @Test func droppedSinkStopsReceiving() {
        let broadcaster = PaneOutputBroadcaster()
        var sink: CollectingSink? = CollectingSink()
        broadcaster.add(sink!)
        #expect(broadcaster.sinkCount == 1)
        sink = nil
        #expect(broadcaster.sinkCount == 0)
    }

    @Test func allowPolicyForwardsToBackend() {
        let backend = RecordingBackend()
        let writer = PaneWriter(backend: backend)
        let decision = writer.write(.text("ls\n"), to: PaneID("%1"))
        #expect(decision == .allow)
        #expect(backend.sent.count == 1)
    }

    @Test func readOnlyPolicyDeniesAndDoesNotForward() {
        let backend = RecordingBackend()
        let writer = PaneWriter(backend: backend, policy: ReadOnlyPolicy())
        let decision = writer.write(.keys("C-c"), to: PaneID("%1"))
        #expect(decision == .deny(reason: "read-only session"))
        #expect(backend.sent.isEmpty)
    }

    @Test func forceWriteBypassesPolicy() {
        let backend = RecordingBackend()
        let writer = PaneWriter(backend: backend, policy: ReadOnlyPolicy())
        writer.forceWrite(.text("y\n"), to: PaneID("%1"))
        #expect(backend.sent.count == 1)
    }
}
