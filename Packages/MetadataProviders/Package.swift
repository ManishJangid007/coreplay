// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MetadataProviders",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "MetadataProviders", targets: ["MetadataProviders"]),
    ],
    targets: [
        .target(name: "MetadataProviders"),
    ]
)
