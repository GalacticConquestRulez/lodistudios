import Testing
import Foundation
@testable import LodiKit

/// The Files pane's path arithmetic is pure and drives every navigation and op, so
/// it is unit-tested the way the other parsers are.
@MainActor
struct FilesStoreTests {
    @Test func parentClampsAtRoot() {
        #expect(FilesStore.parent(of: "/") == "/")
        #expect(FilesStore.parent(of: "") == "/")
        #expect(FilesStore.parent(of: "/root") == "/")
        #expect(FilesStore.parent(of: "/root/logs") == "/root")
        #expect(FilesStore.parent(of: "/a/b/c") == "/a/b")
        #expect(FilesStore.parent(of: "/root/") == "/")   // trailing slash tolerated
    }

    @Test func childJoinsWithoutDoubleSlash() {
        #expect(FilesStore.child("/", "x") == "/x")
        #expect(FilesStore.child("/root", "x") == "/root/x")
        #expect(FilesStore.child("/root/", "x") == "/root/x")
        #expect(FilesStore.child("/a/b", "file name.txt") == "/a/b/file name.txt")
    }

    @Test func parentThenChildRoundTrips() {
        let path = "/root/project/main.swift"
        let parent = FilesStore.parent(of: path)
        #expect(FilesStore.child(parent, "main.swift") == path)
    }
}
