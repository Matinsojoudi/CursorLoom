// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InputBridge",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "InputBridge", targets: ["InputBridge"]),
        .executable(name: "InputBridgeApp", targets: ["InputBridgeApp"])
    ],
    targets: [
        .target(name: "InputBridge"),
        .executableTarget(name: "InputBridgeApp", dependencies: ["InputBridge"]),
        .testTarget(name: "InputBridgeTests", dependencies: ["InputBridge"])
    ]
)
