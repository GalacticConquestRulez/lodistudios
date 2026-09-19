import Testing
import Foundation
@testable import LodiKit

struct RemoteFileTests {
    @Test func permissionStringForCommonModes() {
        #expect(RemoteFile.permissionString(0o040755) == "drwxr-xr-x")   // directory
        #expect(RemoteFile.permissionString(0o100644) == "-rw-r--r--")   // file
        #expect(RemoteFile.permissionString(0o120777) == "lrwxrwxrwx")   // symlink
        #expect(RemoteFile.permissionString(0o100600) == "-rw-------")   // private file
    }

    @Test func humanSizeScales() {
        #expect(RemoteFile.humanSize(0) == "0 B")
        #expect(RemoteFile.humanSize(512) == "512 B")
        #expect(RemoteFile.humanSize(1024) == "1.0 KB")
        #expect(RemoteFile.humanSize(1536) == "1.5 KB")
        #expect(RemoteFile.humanSize(1_048_576) == "1.0 MB")
        #expect(RemoteFile.humanSize(3_221_225_472) == "3.0 GB")
    }

    @Test func typeFlagsFromMode() {
        let dir = RemoteFile(name: "etc", path: "/etc", size: 0, modified: Date(timeIntervalSince1970: 0), mode: 0o040755)
        #expect(dir.isDirectory)
        #expect(!dir.isRegularFile)

        let file = RemoteFile(name: "f", path: "/f", size: 10, modified: Date(timeIntervalSince1970: 0), mode: 0o100644)
        #expect(file.isRegularFile)
        #expect(!file.isDirectory)
        #expect(file.displaySize == "10 B")

        let link = RemoteFile(name: "l", path: "/l", size: 0, modified: Date(timeIntervalSince1970: 0), mode: 0o120777)
        #expect(link.isSymlink)
    }
}
