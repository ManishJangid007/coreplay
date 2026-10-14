// swift-tools-version: 6.2
import PackageDescription

// Networking: saved servers, logins in the Keychain, recent streams and
// where network videos got to. Browsing, discovery and casting go through
// VLC in PlaybackEngine (the only package that may import VLCKit).
let package = Package(
    name: "Networking",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "Networking", targets: ["Networking"]),
    ],
    dependencies: [
        .package(path: "../PlaybackEngine"),
    ],
    targets: [
        .target(
            name: "Networking",
            dependencies: [.product(name: "PlaybackCore", package: "PlaybackEngine")]
        ),
        .testTarget(
            name: "NetworkingTests",
            dependencies: ["Networking", .product(name: "PlaybackCore", package: "PlaybackEngine")]
        ),
    ]
)
