// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MediaLibrary",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "MediaLibrary", targets: ["MediaLibrary"]),
    ],
    targets: [
        .target(name: "MediaLibrary"),
    ]
)
