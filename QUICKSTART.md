# Quick Start Guide

Get up and running with the Multi-Chain Key Generator in 2 minutes.

## Prerequisites

- macOS 12.0 or later
- Xcode 14.0+ (includes Swift)
- Rust 1.70+ (install via `rustup`)

## One-Command Setup

```bash
# Build everything
cargo build --manifest-path rust-app/Cargo.toml && swift build --package-path swift-app
```

## Run the GUI

```bash
swift run --package-path swift-app
```

A macOS window will appear with three buttons:
- **Generate Keys**: Creates fresh keys for all five cryptocurrencies
- **Copy**: Copies the output to your clipboard
- **Clear**: Resets the interface

## Run the CLI (Terminal Output)

```bash
cargo run --manifest-path rust-app/Cargo.toml --bin rust-app
```

You'll see formatted key output for:
- Bitcoin
- Litecoin
- Monero
- Solana
- Ethereum

## Example Workflow

```bash
# Terminal 1: Generate keys
$ cargo run --manifest-path rust-app/Cargo.toml --bin rust-app

# Output will show all chains with private/public keys and addresses

# Terminal 2: Launch the GUI
$ swift run --package-path swift-app

# Click "Generate Keys" button to create new keys in the GUI
# Click "Copy" to copy output to macOS clipboard
```

## Common Commands

| Task | Command |
|------|---------|
| Build Rust only | `cargo build --manifest-path rust-app/Cargo.toml` |
| Build Swift only | `swift build --package-path swift-app` |
| Run CLI | `cargo run --manifest-path rust-app/Cargo.toml --bin rust-app` |
| Run GUI | `swift run --package-path swift-app` |
| Test Rust | `cargo test --manifest-path rust-app/Cargo.toml` |
| Test Swift | `swift test --package-path swift-app` |
| Clean build | `cargo clean --manifest-path rust-app/Cargo.toml && swift package clean --package-path swift-app` |

## First-Time Issues

### "Command not found: cargo"
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

### "Failed to run generator"
Ensure Rust has been built at least once:
```bash
cargo build --manifest-path rust-app/Cargo.toml
```

Then try the Swift app again:
```bash
swift run --package-path swift-app
```

## Next Steps

- See `README.md` for detailed documentation
- Review `rust-app/src/main.rs` to understand the cryptographic implementation
- Explore `swift-app/Sources/ContentView.swift` for the GUI code
- Check `ARCHITECTURE.md` for design patterns and extensibility

## Security Reminder

⚠️ These are demonstration keys. **Never use generated keys for real funds without proper security audits.**

---

**Questions?** See README.md for references and additional details.
