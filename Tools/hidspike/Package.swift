// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "hidspike",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "hidspike", path: "Sources/hidspike"),
    ]
)
