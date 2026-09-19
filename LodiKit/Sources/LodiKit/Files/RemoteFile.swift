import Foundation

/// One entry in a remote directory, as SFTP reports it (name + POSIX attributes).
/// libssh2's `readdir` gives structured attributes, not an `ls -l` line, so the
/// "listing parser" is really the attribute → display formatting: a permission
/// string, a human size, a type. Those are pure and unit-tested here; the SFTP
/// transport that produces `RemoteFile`s lands with the Files pane.
public struct RemoteFile: Identifiable, Sendable, Equatable {
    public let name: String
    public let path: String
    public let size: UInt64
    public let modified: Date
    /// POSIX mode bits (type + permissions), as `st_mode`.
    public let mode: UInt32

    public var id: String { path }

    public init(name: String, path: String, size: UInt64, modified: Date, mode: UInt32) {
        self.name = name
        self.path = path
        self.size = size
        self.modified = modified
        self.mode = mode
    }

    // MARK: - Type

    private var typeBits: UInt32 { mode & 0o170000 }
    public var isDirectory: Bool { typeBits == 0o040000 }
    public var isSymlink: Bool { typeBits == 0o120000 }
    public var isRegularFile: Bool { typeBits == 0o100000 }

    // MARK: - Display

    /// e.g. `drwxr-xr-x` — type char then owner/group/other rwx triples.
    public var permissionString: String { Self.permissionString(mode) }
    /// e.g. `4.0 KB`, `1.2 MB`.
    public var displaySize: String { Self.humanSize(size) }

    public static func permissionString(_ mode: UInt32) -> String {
        let type: Character
        switch mode & 0o170000 {
        case 0o040000: type = "d"
        case 0o120000: type = "l"
        case 0o100000: type = "-"
        default:       type = "?"
        }
        var result = String(type)
        for shift in [6, 3, 0] as [UInt32] {
            let bits = (mode >> shift) & 0o7
            result.append(bits & 0o4 != 0 ? "r" : "-")
            result.append(bits & 0o2 != 0 ? "w" : "-")
            result.append(bits & 0o1 != 0 ? "x" : "-")
        }
        return result
    }

    public static func humanSize(_ bytes: UInt64) -> String {
        guard bytes >= 1024 else { return "\(bytes) B" }
        let units = ["KB", "MB", "GB", "TB", "PB"]
        var value = Double(bytes) / 1024
        var index = 0
        while value >= 1024 && index < units.count - 1 {
            value /= 1024
            index += 1
        }
        return String(format: "%.1f %@", value, units[index])
    }
}
