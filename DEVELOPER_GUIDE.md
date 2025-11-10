# Developer Guide

Welcome! This guide helps you understand, modify, and extend the Multi-Chain Key Generator.

## Project Layout

```
888/
├── rust-app/                      # Rust cryptographic backend
│   ├── src/
│   │   └── main.rs               # All chain implementations (1,000+ lines)
│   ├── Cargo.toml                # Rust dependencies
│   ├── Cargo.lock                # Locked versions
│   └── target/                   # Build artifacts (gitignored)
│
├── swift-app/                     # SwiftUI macOS frontend
│   ├── Sources/
│   │   └── ContentView.swift     # GUI & process management
│   ├── Tests/
│   │   └── HawalaAppTests.swift
│   ├── Package.swift
│   └── Package.resolved
│
├── README.md                      # Main documentation
├── QUICKSTART.md                  # 2-minute setup guide
├── ARCHITECTURE.md                # Design deep-dive
├── PROJECT_STATUS.md              # Current roadmap
├── LICENSE                        # License file
└── [this file]                    # Developer guide
```

## Development Environment Setup

### 1. Prerequisites

```bash
# Install Rust (if not already installed)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

# Verify installations
rustc --version     # Rust 1.70+
cargo --version     # Cargo matching rustc
swift --version     # Swift 5.9+ (from Xcode)
```

### 2. Clone and Build

```bash
cd ~/Desktop/888
cargo build --manifest-path rust-app/Cargo.toml
swift build --package-path swift-app
```

### 3. IDE Setup

**For Rust**:
- VS Code: Install `rust-analyzer` extension
- JetBrains: Use IntelliJ IDEA with Rust plugin
- Vim: Use `rust.vim` plugin

**For Swift**:
- Xcode: Recommended (native)
- VS Code: Swift for VS Code extension

## Understanding the Codebase

### Key Entry Points

| File | Purpose | Lines |
|------|---------|-------|
| `rust-app/src/main.rs` | Chain implementations | ~450 |
| `swift-app/Sources/ContentView.swift` | GUI layer | ~200 |
| `rust-app/Cargo.toml` | Rust dependencies | ~15 |
| `swift-app/Package.swift` | Swift metadata | ~25 |

### Critical Functions in `main.rs`

#### Bitcoin Generation

```rust
fn generate_bitcoin_keys(
    secp: &Secp256k1<secp256k1::All>,
    rng: &mut OsRng,
) -> Result<BitcoinKeys, Box<dyn Error>>
```

**Flow**:
1. Generate random 32-byte seed
2. Create secp256k1 secret key
3. Derive compressed public key
4. Hash160 and encode as Bech32 P2WPKH

**Key Variables**:
- `secret_key`: 32 bytes, secp256k1 private key
- `compressed`: 33 bytes, secp256k1 public key
- `address`: Bech32 string (bc1...)

#### Monero Generation

```rust
fn generate_monero_keys(rng: &mut OsRng) -> Result<MoneroKeys, Box<dyn Error>>
```

**Flow**:
1. Generate random spend seed
2. Reduce modulo curve order → spend private key
3. Hash spend key with Keccak-256
4. Reduce hash → view private key
5. Multiply both by base point → public keys
6. Construct address: [0x12 | spend_pub | view_pub | checksum(4)]
7. Encode with custom base58 (8-byte chunks)

**Key Variables**:
- `spend_scalar`: Ed25519 scalar (32 bytes)
- `view_scalar`: Derived from Keccak-256
- `public_spend`, `public_view`: Compressed Edwards points

#### Monero Base58 Encoding

```rust
fn monero_base58_encode(data: &[u8]) -> String
```

**Why Custom Encoding?**

Monero uses block-wise base58 encoding (non-standard):
- Split data into 8-byte chunks
- Encode each chunk independently
- Pad with '1' characters to expected length per chunk

**Chunk Encoding Lengths**:
```
1 byte  → 2 characters
2 bytes → 3 characters
3 bytes → 5 characters
...
8 bytes → 11 characters
```

## Adding a New Cryptocurrency

### Step 1: Define the Key Struct

In `rust-app/src/main.rs`, add:

```rust
struct DogecoinKeys {
    private_hex: String,
    private_wif: String,
    public_compressed_hex: String,
    address: String,
}
```

### Step 2: Implement Generation Function

```rust
fn generate_dogecoin_keys(
    secp: &Secp256k1<secp256k1::All>,
    rng: &mut OsRng,
) -> Result<DogecoinKeys, Box<dyn Error>> {
    let mut secret_bytes = [0u8; 32];
    rng.fill_bytes(&mut secret_bytes);
    let secret_key = SecretKey::from_slice(&secret_bytes)?;
    
    let private_hex = hex::encode(secret_key.secret_bytes());
    let secp_public_key = SecpPublicKey::from_secret_key(secp, &secret_key);
    let public_key = BitcoinPublicKey::from(secp_public_key);
    let compressed = CompressedPublicKey::try_from(public_key.clone())?;
    
    // Dogecoin: WIF prefix 0x9E, Bech32 hrp "doge"
    let private_wif = encode_dogecoin_wif(&secret_key);
    
    // For simplicity, use Bech32 like Litecoin
    // (Real Dogecoin is P2PKH, but we'll use SegWit for consistency)
    let pubkey_hash = hash160::Hash::hash(compressed.to_bytes());
    // ... bech32 encoding with "doge" prefix ...
    
    Ok(DogecoinKeys {
        private_hex,
        private_wif,
        public_compressed_hex: hex::encode(compressed.to_bytes()),
        address, // "doge1..."
    })
}

fn encode_dogecoin_wif(secret_key: &SecretKey) -> String {
    let mut data = Vec::with_capacity(34);
    data.push(0x9E); // Dogecoin mainnet prefix
    data.extend_from_slice(&secret_key.secret_bytes());
    data.push(0x01); // compressed
    
    let checksum = sha256d::Hash::hash(&data);
    let mut payload = data;
    payload.extend_from_slice(&checksum[..4]);
    
    bs58::encode(payload).into_string()
}
```

### Step 3: Call from `main()`

```rust
fn main() -> Result<(), Box<dyn Error>> {
    // ... existing code ...
    
    let dogecoin_keys = generate_dogecoin_keys(&secp, &mut rng)?;
    
    // ... existing print statements ...
    
    println!("=== Dogecoin ===");
    println!("Private key (hex): {}", dogecoin_keys.private_hex);
    println!("Private key (WIF): {}", dogecoin_keys.private_wif);
    println!("Public key (compressed hex): {}", dogecoin_keys.public_compressed_hex);
    println!("Address: {}", dogecoin_keys.address);
    println!();
    
    Ok(())
}
```

### Step 4: Update Swift UI

In `swift-app/Sources/ContentView.swift`:

```swift
Text("Press the button to invoke the Rust tool. Bitcoin, Litecoin, Monero, Solana, Ethereum, and Dogecoin credentials will appear below.")
```

### Step 5: Add Dependencies (if needed)

In `rust-app/Cargo.toml`, if you need a dogecoin-specific crate:

```toml
[dependencies]
dogecoin = "0.1"  # Example (may not exist)
```

Then run:

```bash
cargo build --manifest-path rust-app/Cargo.toml
```

---

## Debugging Tips

### Rust Debugging

```bash
# Verbose build output
RUST_BACKTRACE=1 cargo run --manifest-path rust-app/Cargo.toml --bin rust-app

# Check for compiler warnings
cargo clippy --manifest-path rust-app/Cargo.toml

# Format code
cargo fmt --manifest-path rust-app/Cargo.toml

# Audit dependencies for vulnerabilities
cargo audit --manifest-path rust-app/Cargo.toml
```

### Swift Debugging

```bash
# Build with verbose output
swift build --package-path swift-app -v

# Run with debug output
RUST_LOG=debug swift run --package-path swift-app

# Check for warnings
swift build --package-path swift-app 2>&1 | grep warning
```

### Process Debugging (Swift → Rust)

Add logging to `ContentView.swift`:

```swift
print("Running command: \(process.executableURL?.path ?? "")")
print("Arguments: \(process.arguments ?? [])")
print("Working directory: \(process.currentDirectoryURL?.path ?? "")")
```

Check stderr:

```swift
let errorString = String(data: errorData, encoding: .utf8) ?? ""
print("STDERR: \(errorString)")
```

---

## Testing

### Rust Tests

Create `rust-app/src/lib.rs`:

```rust
pub fn is_valid_bitcoin_address(addr: &str) -> bool {
    addr.starts_with("bc1") && addr.len() == 42
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bitcoin_address_format() {
        assert!(is_valid_bitcoin_address("bc1qjvkdhpem3jn4mkgkw33dyn4pkvjtgwn0fkdcp0"));
        assert!(!is_valid_bitcoin_address("invalid"));
    }
}
```

Run tests:

```bash
cargo test --manifest-path rust-app/Cargo.toml
```

### Swift Tests

In `swift-app/Tests/HawalaAppTests.swift`:

```swift
import XCTest

final class GeneratorTests: XCTestCase {
    func testGeneratorProcessStarts() throws {
        let process = Process()
        // ... setup ...
        try process.run()
        XCTAssertTrue(process.isRunning)
    }
}
```

Run tests:

```bash
swift test --package-path swift-app
```

---

## Performance Profiling

### Rust

```bash
# Release build (optimized)
cargo build --release --manifest-path rust-app/Cargo.toml

# Time execution
time cargo run --release --manifest-path rust-app/Cargo.toml
```

### Swift

Use Xcode's Profiler:
```bash
swift build --package-path swift-app
xcrun xctrace record --template "System Trace" -- swift run --package-path swift-app
```

---

## Code Style & Conventions

### Rust

- **File naming**: `snake_case` (main.rs, lib.rs)
- **Function naming**: `snake_case` (generate_bitcoin_keys)
- **Struct naming**: `PascalCase` (BitcoinKeys)
- **Line length**: 100 characters (soft limit, 120 hard)

```rust
fn generate_bitcoin_keys(
    secp: &Secp256k1<secp256k1::All>,
    rng: &mut OsRng,
) -> Result<BitcoinKeys, Box<dyn Error>> {
    // Implementation
}
```

### Swift

- **File naming**: `PascalCase` (ContentView.swift)
- **Function naming**: `camelCase` (runGenerator)
- **Variable naming**: `camelCase` (isGenerating)
- **Line length**: 100 characters

```swift
private func runGenerator() async {
    isGenerating = true
    // Implementation
}
```

---

## Common Tasks

### Update a Dependency

```bash
# Check for updates
cargo update --manifest-path rust-app/Cargo.toml

# Update specific crate
cargo update --manifest-path rust-app/Cargo.toml -p bitcoin
```

### Clean Build

```bash
# Rust
cargo clean --manifest-path rust-app/Cargo.toml

# Swift
swift package clean --package-path swift-app

# Both
cargo clean --manifest-path rust-app/Cargo.toml && \
swift package clean --package-path swift-app
```

### Run with Different Configuration

```bash
# Debug (default)
cargo run --manifest-path rust-app/Cargo.toml --bin rust-app

# Release (optimized)
cargo run --release --manifest-path rust-app/Cargo.toml

# With specific features
cargo run --manifest-path rust-app/Cargo.toml --bin rust-app --features=no-default-features
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `error: failed to run generator` | Ensure Rust is built: `cargo build --manifest-path rust-app/Cargo.toml` |
| `rustc: command not found` | Run `source $HOME/.cargo/env` or restart terminal |
| `error: unknown field 'feature'` | Check dependency documentation; use valid feature names |
| `Cannot open file` (Swift) | Verify workspace root calculation in `ContentView.swift` |
| Memory usage spikes | Profile with `valgrind` (Linux) or Instruments (macOS) |

---

## Resources

- **Rust Book**: https://doc.rust-lang.org/book/
- **Bitcoin Dev Kit**: https://bitcoindevkit.org/
- **Ed25519 Curve25519 Docs**: https://docs.rs/curve25519-dalek/
- **Monero Docs**: https://monerodocs.org/
- **Solana Docs**: https://docs.solana.com/

---

**Questions?** Check ARCHITECTURE.md or create a GitHub issue.
