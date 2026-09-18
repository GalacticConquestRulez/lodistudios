import Testing
import CLibSSH2

/// Milestone 0 smoke test: proves the vendored libssh2 xcframework's headers and
/// static library are visible and linkable from Swift on macOS. It exercises the
/// real C entry points — init, version, exit — rather than any LodiKit code.
struct LibSSH2LinkageTests {

    @Test func libssh2InitializesAndReportsExpectedVersion() {
        // libssh2_init must return 0 on success.
        #expect(libssh2_init(0) == 0)

        // libssh2_version(required) returns the library version string, or NULL if
        // the running library is older than `required` (0 => any).
        guard let cVersion = libssh2_version(0) else {
            Issue.record("libssh2_version(0) returned NULL")
            libssh2_exit()
            return
        }
        let version = String(cString: cVersion)

        // We vendor libssh2 1.11.x; the linkage test pins the major/minor line so a
        // wrong or stale binary is caught here rather than at runtime on a droplet.
        #expect(version.hasPrefix("1.11"), "unexpected libssh2 version: \(version)")

        libssh2_exit()
    }
}
