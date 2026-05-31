#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Build Rust project
echo "Building Rust project..."
cargo build --manifest-path "$ROOT_DIR/rust-app/Cargo.toml"

# Build Rust release library so Swift can link the FFI target deterministically.
echo "Building Rust release FFI library..."
cargo build --release --manifest-path "$ROOT_DIR/rust-app/Cargo.toml"

# Build Swift project
echo "Building Swift project..."
swift build --package-path "$ROOT_DIR/swift-app"

echo "Checking production guardrails..."
"$ROOT_DIR/scripts/check_production_guards.sh"

echo "Build completed successfully."
