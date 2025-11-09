#!/usr/bin/env bash
set -euo pipefail

# Build Rust project
echo "Building Rust project..."
cargo build --manifest-path "$(dirname "$0")/../rust-app/Cargo.toml"

# Build Swift project
echo "Building Swift project..."
swift build --package-path "$(dirname "$0")/../swift-app"

echo "Build completed successfully."
