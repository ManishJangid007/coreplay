// swift-tools-version: 6.2
import PackageDescription

// Coreplay's design language: brand assets, system colours and type, artwork
// views, artwork-derived backgrounds, transport controls and motion. SwiftUI
// only, no knowledge of engines or the library.
let package = Package(
    name: "DesignSystem",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    targets: [
        .target(
            name: "DesignSystem",
            resources: [.process("Resources")]
        ),
    ]
)
