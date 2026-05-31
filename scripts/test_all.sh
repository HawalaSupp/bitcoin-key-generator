#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Test Rust project
echo "Running Rust tests..."
cargo test --manifest-path "$ROOT_DIR/rust-app/Cargo.toml"

# Test Swift project
echo "Running Swift tests..."
swift test --package-path "$ROOT_DIR/swift-app"

echo "Checking production guardrails..."
"$ROOT_DIR/scripts/check_production_guards.sh"

echo "Running security audit..."
"$ROOT_DIR/scripts/security_audit.sh"

echo "Tests finished successfully."
