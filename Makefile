# Combined build targets for Rust and Swift projects

.PHONY: build-rust build-swift build-all test-rust test-swift test-all clean

build-rust:
	cargo build --manifest-path rust-app/Cargo.toml

build-swift:
	swift build --package-path swift-app

build-all: build-rust build-swift

test-rust:
	cargo test --manifest-path rust-app/Cargo.toml

test-swift:
	swift test --package-path swift-app

test-all: test-rust test-swift

clean:
	cargo clean --manifest-path rust-app/Cargo.toml
	swift package reset --package-path swift-app >/dev/null 2>&1 || true
