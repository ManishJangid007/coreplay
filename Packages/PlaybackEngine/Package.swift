// swift-tools-version: 6.2
import PackageDescription

// PlaybackEngine is the only package allowed to import VLCKit.
//
// - PlaybackCore: engine-agnostic types (protocol, events, tracks, router logic).
//   Foundation only, so it builds and tests on any platform.
// - PlaybackEngine: VLCKitEngine, AVPlayerEngine, the media prober, the
//   PlaybackController that routes and hands off between engines, and the
//   video surface views.
let package = Package(
    name: "PlaybackEngine",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "PlaybackCore", targets: ["PlaybackCore"]),
        .library(name: "PlaybackEngine", targets: ["PlaybackEngine"]),
    ],
    targets: [
        // Official VideoLAN binary for VLCKit 4.0.0a25 (built 2026-09-29).
        // URL and checksum are copied verbatim from VLCKit's own Package.swift
        // (https://code.videolan.org/videolan/VLCKit/-/blob/master/Package.swift).
        // VLCKit 4 is a dynamic framework, which keeps us LGPL-compliant.
        .binaryTarget(
            name: "VLCKit",
            url: "https://download.videolan.org/cocoapods/unstable/VLCKit-4.0-20260929-1631.zip",
            checksum: "f37c8dbdd4427d1a3f5d75dc4b8bd1ae863cef4426f9a405a2fd1c5c9012f1fb"
        ),
        .target(name: "PlaybackCore"),
        .target(
            name: "PlaybackEngine",
            dependencies: ["PlaybackCore", "VLCKit"]
        ),
        .testTarget(
            name: "PlaybackCoreTests",
            dependencies: ["PlaybackCore"]
        ),
        // Plays a generated movie through both engines on the Mac (needs a
        // window server, so it doesn't run in the Linux harness).
        .testTarget(
            name: "PlaybackEngineTests",
            dependencies: ["PlaybackEngine", "PlaybackCore", "VLCKit"]
        ),
    ]
)
