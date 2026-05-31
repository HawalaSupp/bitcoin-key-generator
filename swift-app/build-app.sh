#!/usr/bin/env bash
set -euo pipefail

SWIFT_APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SWIFT_APP_DIR/.." && pwd)"
APP_NAME="${APP_NAME:-HawalaWallet}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
NOTARIZE="${NOTARIZE:-0}"
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_APP_PASSWORD="${APPLE_APP_PASSWORD:-}"

cd "$ROOT_DIR"

echo "Building Rust release FFI library..."
cargo build --release --manifest-path rust-app/Cargo.toml

echo "Checking production guardrails..."
scripts/check_production_guards.sh

echo "Building Swift package ($BUILD_CONFIGURATION)..."
if [[ "$BUILD_CONFIGURATION" == "release" ]]; then
  swift build -c release --package-path swift-app
  SWIFT_BUILD_DIR="$SWIFT_APP_DIR/.build/release"
else
  swift build --package-path swift-app
  SWIFT_BUILD_DIR="$SWIFT_APP_DIR/.build/debug"
fi

BUNDLE_DIR="$SWIFT_BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"

echo "Creating app bundle at $BUNDLE_DIR..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

cp "$SWIFT_BUILD_DIR/swift-app" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
cp "$SWIFT_APP_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$SWIFT_APP_DIR/Hawala.entitlements" "$CONTENTS_DIR/Hawala.entitlements"

if [[ -f "$ROOT_DIR/rust-app/target/release/librust_app.dylib" ]]; then
  cp "$ROOT_DIR/rust-app/target/release/librust_app.dylib" "$FRAMEWORKS_DIR/"
  install_name_tool -change librust_app.dylib "@executable_path/../Frameworks/librust_app.dylib" "$MACOS_DIR/$APP_NAME" || true
fi

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$BUNDLE_DIR"
  xattr -d com.apple.FinderInfo "$BUNDLE_DIR" 2>/dev/null || true
  xattr -d 'com.apple.fileprovider.fpfs#P' "$BUNDLE_DIR" 2>/dev/null || true
fi

sign_app() {
  if [[ -n "$SIGNING_IDENTITY" ]]; then
    codesign --force --options runtime --timestamp --deep \
      --sign "$SIGNING_IDENTITY" \
      --entitlements "$SWIFT_APP_DIR/Hawala.entitlements" \
      "$BUNDLE_DIR"
  else
    codesign --force --deep --sign - --entitlements "$SWIFT_APP_DIR/Hawala.entitlements" "$BUNDLE_DIR"
  fi
}

if [[ -n "$SIGNING_IDENTITY" ]]; then
  echo "Signing app with identity: $SIGNING_IDENTITY"
else
  echo "No SIGNING_IDENTITY provided. Applying ad-hoc signature for local validation."
fi

sign_app || true

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$BUNDLE_DIR"
  xattr -d com.apple.FinderInfo "$BUNDLE_DIR" 2>/dev/null || true
  xattr -d 'com.apple.fileprovider.fpfs#P' "$BUNDLE_DIR" 2>/dev/null || true
fi

if ! sign_app; then
  sign_app
fi

codesign --verify --deep --strict --verbose=2 "$BUNDLE_DIR"

ARCHIVE_PATH="$SWIFT_BUILD_DIR/$APP_NAME.zip"
echo "Creating archive $ARCHIVE_PATH..."
ditto -c -k --keepParent "$BUNDLE_DIR" "$ARCHIVE_PATH"
shasum -a 256 "$ARCHIVE_PATH" > "$ARCHIVE_PATH.sha256"

if [[ "$NOTARIZE" == "1" ]]; then
  if [[ -z "$APPLE_ID" || -z "$APPLE_TEAM_ID" || -z "$APPLE_APP_PASSWORD" || -z "$SIGNING_IDENTITY" ]]; then
    echo "NOTARIZE=1 requires APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD, and SIGNING_IDENTITY." >&2
    exit 1
  fi

  echo "Submitting archive for notarization..."
  xcrun notarytool submit "$ARCHIVE_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --wait

  xcrun stapler staple "$BUNDLE_DIR"
fi

echo "Build artifact:"
echo "  App:     $BUNDLE_DIR"
echo "  Archive: $ARCHIVE_PATH"
echo "  SHA256:  $ARCHIVE_PATH.sha256"
