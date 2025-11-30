// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-app",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/21-DOT-DEV/swift-secp256k1.git", from: "0.21.1")
    ],
    targets: [
        .target(
            name: "RustBridge",
            dependencies: [],
            path: "Sources/RustBridge",
            linkerSettings: [
                .unsafeFlags(["-L/Users/x/Desktop/888/rust-app/target/release", "-lrust_app"])
            ]
        ),
        .executableTarget(
            name: "swift-app",
            dependencies: [
                .product(name: "P256K", package: "swift-secp256k1"),
                "RustBridge"
            ],
            exclude: ["APIKeys.swift.template"],
            resources: [
                .copy("Resources/HawalaLogo.png")
            ]
        ),
        .testTarget(
            name: "swift-appTests",
            dependencies: ["swift-app"]
        )
    ]
)
