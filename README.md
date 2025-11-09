# Dual Rust & Swift Workspace

This workspace is pre-configured for cross-language development in Rust and Swift.

## Structure
- `rust-app/`: Cargo binary crate for the Rust component.
- `swift-app/`: Swift Package Manager executable project.
- `docs/`: Documentation placeholders for both stacks.

## Build Commands
- `cargo build --manifest-path rust-app/Cargo.toml`
- `swift build --package-path swift-app`

## Test Commands
- `cargo test --manifest-path rust-app/Cargo.toml`
- `swift test --package-path swift-app`

## Running the Apps
- **Rust key generator**: `cargo run --manifest-path rust-app/Cargo.toml`
- **SwiftUI bridge app** (launches a macOS window that invokes the Rust binary):
	```bash
	swift run --package-path swift-app
	```
	Make sure the Rust project has been built at least once so the Swift app can call it quickly.

## Next Steps
1. Update the documentation in `docs/` with project-specific details.
2. Implement shared build automation (e.g., Makefile or scripts) if desired.
3. Configure CI workflows for both toolchains when ready.
