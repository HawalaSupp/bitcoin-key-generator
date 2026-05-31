# Hawala Build And Release Runbook

**Created:** May 31, 2026  
**Status:** Phase 1 release-foundation runbook.

---

## Build Requirements

- macOS 14 or newer for release packaging.
- Xcode 15 or newer.
- Swift 6.1-compatible toolchain.
- Rust stable toolchain.
- Apple Developer ID Application certificate for distribution builds.

---

## Local Verification

From the repository root:

```bash
swift build --package-path swift-app
cargo test --manifest-path rust-app/Cargo.toml --no-run
scripts/check_production_guards.sh
```

Full local build:

```bash
scripts/build_all.sh
```

Full local test:

```bash
scripts/test_all.sh
```

Notes:

- `cargo clippy --manifest-path rust-app/Cargo.toml --all-targets` currently passes with warnings.
- `cargo fmt --manifest-path rust-app/Cargo.toml -- --check` currently reports broad pre-existing formatting drift. Do not fix this opportunistically inside feature work; schedule a dedicated formatting-only commit.

---

## Release Bundle

Create an unsigned/ad-hoc signed local release bundle:

```bash
BUILD_CONFIGURATION=release swift-app/build-app.sh
```

Output:

- `swift-app/.build/release/HawalaWallet.app`
- `swift-app/.build/release/HawalaWallet.zip`
- `swift-app/.build/release/HawalaWallet.zip.sha256`

The script:

1. Builds the Rust release FFI library.
2. Runs production guard checks.
3. Builds the Swift release executable.
4. Creates a macOS `.app` bundle.
5. Copies `librust_app.dylib` into `Contents/Frameworks`.
6. Signs the app.
7. Verifies the signature.
8. Creates a zip archive and SHA-256 checksum.

---

## Signed Distribution Build

Set the signing identity:

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
BUILD_CONFIGURATION=release \
swift-app/build-app.sh
```

The signing identity must exist in the current keychain:

```bash
security find-identity -v -p codesigning
```

---

## Notarized Distribution Build

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
APPLE_ID="you@example.com" \
APPLE_TEAM_ID="TEAMID" \
APPLE_APP_PASSWORD="app-specific-password" \
NOTARIZE=1 \
BUILD_CONFIGURATION=release \
swift-app/build-app.sh
```

The script submits the archive with `xcrun notarytool`, waits for completion, and staples the notarization ticket to the app bundle.

---

## CI Coverage

GitHub Actions currently includes:

- Rust build and tests.
- Rust clippy visibility check.
- Rust dependency audit visibility check.
- Wallet validator flow.
- Swift build and tests.
- Production guard check.
- Release bundle smoke test.

The workflows run on:

- `main`
- `mvvm-refactor-phase-1`
- pull requests targeting either branch

---

## Production Guardrails

`scripts/check_production_guards.sh` fails when launch-scope source areas contain mock execution paths or obvious sensitive `print` statements.

Known internal/deferred modules are excluded because Phase 0 hides those product surfaces. Before any excluded feature becomes public, remove its exclusion and replace the mock path with a real implementation.

---

## Remaining Phase 1 Follow-Ups

- Add real crash reporting provider credentials once a provider is chosen.
- Decide whether Rust formatting should be normalized in a dedicated repo-wide commit.
- Convert dependency audit warnings into hard failures after current advisories are remediated or formally risk-accepted.
- Add notarization secrets to GitHub Actions when Apple Developer credentials are available.
