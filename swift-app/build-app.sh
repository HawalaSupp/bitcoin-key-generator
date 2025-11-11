#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building Hawala Wallet..."
swift build -c release

echo "Creating app bundle..."
APP_NAME="HawalaWallet"
BUNDLE_DIR="$PWD/.build/release/$APP_NAME.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Clean old bundle
rm -rf "$BUNDLE_DIR"

# Create directory structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
cp ".build/release/swift-app" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

# Copy Info.plist
cp "Info.plist" "$CONTENTS_DIR/"

echo "App bundle created at: $BUNDLE_DIR"
echo "Launching..."

open "$BUNDLE_DIR"
