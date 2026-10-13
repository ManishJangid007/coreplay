// swift-tools-version: 6.2
import PackageDescription

// One module per top-level feature. Features talk to playback only through
// PlaybackSession / PlaybackController and never import VLCKit.
let package = Package(
    name: "Features",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "HomeFeature", targets: ["HomeFeature"]),
        .library(name: "LibraryFeature", targets: ["LibraryFeature"]),
        .library(name: "SearchFeature", targets: ["SearchFeature"]),
        .library(name: "PlayerFeature", targets: ["PlayerFeature"]),
        .library(name: "SettingsFeature", targets: ["SettingsFeature"]),
    ],
    dependencies: [
        .package(path: "../DesignSystem"),
        .package(path: "../PlaybackEngine"),
        .package(path: "../NowPlaying"),
    ],
    targets: [
        .target(
            name: "HomeFeature",
            dependencies: [
                "DesignSystem",
                .product(name: "PlaybackCore", package: "PlaybackEngine"),
                .product(name: "PlaybackEngine", package: "PlaybackEngine"),
                "NowPlaying",
            ]
        ),
        .target(
            name: "LibraryFeature",
            dependencies: ["DesignSystem"]
        ),
        .target(
            name: "SearchFeature",
            dependencies: ["DesignSystem"]
        ),
        .target(
            name: "PlayerFeature",
            dependencies: [
                "DesignSystem",
                .product(name: "PlaybackCore", package: "PlaybackEngine"),
                .product(name: "PlaybackEngine", package: "PlaybackEngine"),
                "NowPlaying",
            ]
        ),
        .target(
            name: "SettingsFeature",
            dependencies: [
                "DesignSystem",
                .product(name: "PlaybackCore", package: "PlaybackEngine"),
                .product(name: "PlaybackEngine", package: "PlaybackEngine"),
                "NowPlaying",
            ],
            resources: [.process("Resources")]
        ),
    ]
)
