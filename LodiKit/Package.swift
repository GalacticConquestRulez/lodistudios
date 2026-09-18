// swift-tools-version: 6.0
import PackageDescription

// LodiKit is the shared core of LodiStudios: design system, command registry,
// host inventory, terminal seams and the SSH transport protocol. Everything the
// docs say lives "in LodiKit" belongs here so it is testable with `swift test`
// on both macOS and iOS without an app around it.
let package = Package(
    name: "LodiKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "LodiKit", targets: ["LodiKit"]),
    ],
    targets: [
        // The vendored libssh2 (mbedTLS crypto backend) static-library
        // xcframework. Built by scripts/build-libssh2.sh and committed under
        // Vendor/ so a fresh clone builds without running the script. The path is
        // relative to this package directory (LodiKit/), so it climbs one level to
        // the repo root's Vendor/.
        .binaryTarget(name: "libssh2", path: "../Vendor/libssh2.xcframework"),

        // Swift cannot `import` a static-library binary target directly, so this C
        // shim re-exports the libssh2 public headers as an importable `CLibSSH2`
        // module (see Sources/CLibSSH2/include/module.modulemap). It depends on the
        // libssh2 binary target for the actual symbols and header search path, and
        // links the system libraries libssh2's mbedTLS backend needs.
        .target(
            name: "CLibSSH2",
            dependencies: ["libssh2"],
            linkerSettings: [
                .linkedLibrary("z"),
            ]
        ),

        .target(
            name: "LodiKit",
            dependencies: ["CLibSSH2"]
        ),
        .testTarget(name: "LodiKitTests", dependencies: ["LodiKit"]),
    ]
)
