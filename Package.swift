// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "InputBridge",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "InputBridge", targets: ["InputBridge"])
    ],
    targets: [
        .executableTarget(
            name: "InputBridge",
            path: "Sources/InputBridge"
        ),
        .testTarget(
            name: "InputBridgeTests",
            dependencies: ["InputBridge"],
            path: "Tests/InputBridgeTests"
        )
    ]
)
