// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Library search path for the Rust FFI library.
// Uses relative path from swift-app directory for portability.
// For production builds, the library should be bundled in the app package.
let rustLibSearchPath = "../rust-app/target/release"

let package = Package(
    name: "swift-app",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/21-DOT-DEV/swift-secp256k1.git", from: "0.21.1"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
        // Note: Trust Wallet's wallet-core only supports iOS/Android, not macOS desktop.
        // For macOS support, we either:
        // 1. Build wallet-core from source (see WALLET_CORE_INTEGRATION.md)
        // 2. Use our existing Rust backend with equivalent implementations
    ],
    targets: [
        .target(
            name: "RustBridge",
            dependencies: [],
            path: "Sources/RustBridge",
            linkerSettings: [
                .unsafeFlags(["-L\(rustLibSearchPath)"]),
                .linkedLibrary("rust_app")
            ]
        ),
        .executableTarget(
            name: "swift-app",
            dependencies: [
                .product(name: "P256K", package: "swift-secp256k1"),
                .product(name: "GRDB", package: "GRDB.swift"),
                "RustBridge"
            ],
            exclude: ["APIKeys.swift.template"],
            resources: [
                .copy("Resources/HawalaLogo.png"),
                .copy("Resources/ClashGrotesk-Bold.otf")
            ]
        ),
        .testTarget(
            name: "swift-appTests",
            dependencies: ["swift-app"]
        )
    ]
)
