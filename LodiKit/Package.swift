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
        .target(name: "LodiKit"),
        .testTarget(name: "LodiKitTests", dependencies: ["LodiKit"]),
    ]
)
