// swift-tools-version: 6.2
import PackageDescription

// MetadataProviders: embedded tags, file-name fallbacks and (later) online
// lookups. Foundation only, so the readers are tested on any platform.
let package = Package(
    name: "MetadataProviders",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "MetadataProviders", targets: ["MetadataProviders"]),
    ],
    targets: [
        .target(name: "MetadataProviders"),
        .testTarget(
            name: "MetadataProvidersTests",
            dependencies: ["MetadataProviders"]
        ),
    ]
)
