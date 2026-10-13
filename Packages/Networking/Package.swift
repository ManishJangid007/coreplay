// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Networking",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "Networking", targets: ["Networking"]),
    ],
    targets: [
        .target(name: "Networking"),
    ]
)
