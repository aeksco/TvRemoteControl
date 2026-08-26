// swift-tools-version: 5.9
import PackageDescription

// Pure, side-effect-free decoding of Siri Remote HID reports and the press / long-press / double-press
// state machine. No IOKit, no timers, no main actor — everything here is testable with `swift test`.
let package = Package(
    name: "RemoteCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RemoteCore", targets: ["RemoteCore"]),
    ],
    targets: [
        .target(name: "RemoteCore"),
        .testTarget(name: "RemoteCoreTests", dependencies: ["RemoteCore"]),
    ]
)
