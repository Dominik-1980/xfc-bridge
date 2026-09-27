// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "XFCBridge",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "XFCBridge", targets: ["XFCBridge"]),
        .executable(name: "MIDIDump", targets: ["MIDIDump"])
    ],
    targets: [
        .executableTarget(name: "XFCBridge"),
        .executableTarget(name: "MIDIDump"),
        .testTarget(name: "XFCBridgeTests", dependencies: ["XFCBridge"])
    ]
)
