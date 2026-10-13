// swift-tools-version: 6.2
import PackageDescription

// MediaLibrary: sources, scanning, the SwiftData model and artwork.
// Tag reading lives in MetadataProviders; PlaybackCore supplies the item
// type the library hands to the player.
let package = Package(
    name: "MediaLibrary",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "MediaLibrary", targets: ["MediaLibrary"]),
    ],
    dependencies: [
        .package(path: "../MetadataProviders"),
        .package(path: "../PlaybackEngine"),
    ],
    targets: [
        .target(
            name: "MediaLibrary",
            dependencies: [
                "MetadataProviders",
                .product(name: "PlaybackCore", package: "PlaybackEngine"),
            ]
        ),
        .testTarget(
            name: "MediaLibraryTests",
            dependencies: ["MediaLibrary", "MetadataProviders"]
        ),
    ]
)
