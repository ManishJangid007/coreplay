// swift-tools-version: 6.2
import PackageDescription

// One module per top-level feature. Features talk to playback only through
// PlaybackSession / PlaybackController, to the library through
// LibraryManager and SwiftData queries, and never import VLCKit.
let package = Package(
    name: "Features",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "HomeFeature", targets: ["HomeFeature"]),
        .library(name: "LibraryFeature", targets: ["LibraryFeature"]),
        .library(name: "MusicFeature", targets: ["MusicFeature"]),
        .library(name: "VideoFeature", targets: ["VideoFeature"]),
        .library(name: "SearchFeature", targets: ["SearchFeature"]),
        .library(name: "PlayerFeature", targets: ["PlayerFeature"]),
        .library(name: "SettingsFeature", targets: ["SettingsFeature"]),
    ],
    dependencies: [
        .package(path: "../DesignSystem"),
        .package(path: "../PlaybackEngine"),
        .package(path: "../NowPlaying"),
        .package(path: "../MediaLibrary"),
    ],
    targets: [
        .target(
            name: "MusicFeature",
            dependencies: [
                "DesignSystem",
                "MediaLibrary",
                "NowPlaying",
                .product(name: "PlaybackCore", package: "PlaybackEngine"),
            ]
        ),
        .target(
            name: "VideoFeature",
            dependencies: [
                "DesignSystem",
                "MediaLibrary",
                "MusicFeature",
                "NowPlaying",
                .product(name: "PlaybackCore", package: "PlaybackEngine"),
            ]
        ),
        .target(
            name: "HomeFeature",
            dependencies: [
                "DesignSystem",
                "MediaLibrary",
                "MusicFeature",
                "VideoFeature",
                .product(name: "PlaybackCore", package: "PlaybackEngine"),
                .product(name: "PlaybackEngine", package: "PlaybackEngine"),
                "NowPlaying",
            ]
        ),
        .target(
            name: "LibraryFeature",
            dependencies: [
                "DesignSystem",
                "MediaLibrary",
                "MusicFeature",
                "VideoFeature",
                "NowPlaying",
                .product(name: "PlaybackCore", package: "PlaybackEngine"),
            ]
        ),
        .target(
            name: "SearchFeature",
            dependencies: [
                "DesignSystem",
                "MediaLibrary",
                "MusicFeature",
                "VideoFeature",
                "NowPlaying",
            ]
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
                "MediaLibrary",
                .product(name: "PlaybackCore", package: "PlaybackEngine"),
                .product(name: "PlaybackEngine", package: "PlaybackEngine"),
                "NowPlaying",
            ],
            resources: [.process("Resources")]
        ),
    ]
)
