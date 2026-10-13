// swift-tools-version: 6.2
import PackageDescription

// NowPlaying owns everything "currently playing" beyond the engine itself:
// the Up Next queue, MPNowPlayingInfoCenter, remote commands (Lock Screen,
// Control Center, AirPods, media keys) and the iOS audio session.
let package = Package(
    name: "NowPlaying",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "NowPlaying", targets: ["NowPlaying"]),
    ],
    dependencies: [
        .package(path: "../PlaybackEngine"),
    ],
    targets: [
        .target(
            name: "NowPlaying",
            dependencies: [
                .product(name: "PlaybackCore", package: "PlaybackEngine"),
                .product(name: "PlaybackEngine", package: "PlaybackEngine"),
            ]
        ),
        .testTarget(
            name: "NowPlayingTests",
            dependencies: [
                "NowPlaying",
                .product(name: "PlaybackCore", package: "PlaybackEngine"),
            ]
        ),
    ]
)
