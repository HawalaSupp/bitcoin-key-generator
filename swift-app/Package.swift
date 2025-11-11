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
        .executableTarget(
            name: "swift-app",
            dependencies: [
                .product(name: "P256K", package: "swift-secp256k1")
            ]
        ),
        .testTarget(
            name: "swift-appTests",
            dependencies: ["swift-app"]
        )
    ]
)
