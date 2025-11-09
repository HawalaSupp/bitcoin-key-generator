#!/usr/bin/env bash
set -euo pipefail

# Test Rust project
echo "Running Rust tests..."
cargo test --manifest-path "$(dirname "$0")/../rust-app/Cargo.toml"

# Test Swift project
echo "Running Swift tests..."
swift test --package-path "$(dirname "$0")/../swift-app"

echo "Tests finished successfully."
