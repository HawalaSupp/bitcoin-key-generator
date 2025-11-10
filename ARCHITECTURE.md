# Architecture & Design

## System Overview

The Multi-Chain Key Generator follows a **layered architecture** separating cryptographic logic from user interface:

```
┌─────────────────────────────────────────────────────────────┐
│                  SwiftUI Frontend (macOS)                   │
│              ContentView.swift (Event Handlers)             │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      │ Process invocation & IPC
                      │ (cargo run --manifest-path ...)
                      ↓
┌─────────────────────────────────────────────────────────────┐
│                     Rust Backend                            │
│              main.rs (Cryptographic Core)                   │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Bitcoin       │ Litecoin     │ Monero                 │ │
│  │ (secp256k1)   │ (secp256k1)  │ (ed25519 + curve25519) │ │
│  ├────────────────────────────────────────────────────────┤ │
│  │ Solana        │ Ethereum                              │ │
│  │ (ed25519)     │ (secp256k1 + Keccak-256)             │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  Dependencies:                                               │
│  • bitcoin (secp256k1 operations)                           │
│  • ed25519-dalek & curve25519-dalek (EdDSA)               │
│  • tiny-keccak (Ethereum hashing)                          │
│  • bs58, bech32 (encoding)                                 │
└──────────────────────────────────────────────────────────────┘
```

## Module Breakdown

### `rust-app/src/main.rs`

**Purpose**: Generates cryptographically secure keys for all supported chains.

**Key Functions**:

| Function | Purpose | Algorithm |
|----------|---------|-----------|
| `generate_bitcoin_keys()` | BTC key generation | secp256k1 + P2WPKH |
| `generate_litecoin_keys()` | LTC key generation | secp256k1 + Bech32 P2WPKH |
| `generate_monero_keys()` | XMR key generation | Ed25519 + Keccak-256 + custom base58 |
| `generate_solana_keys()` | SOL key generation | Ed25519 + base58 encoding |
| `generate_ethereum_keys()` | ETH key generation | secp256k1 + Keccak-256 + EIP-55 |
| `keccak256()` | Hash utility | Keccak-256 (used by Monero & Ethereum) |
| `monero_base58_encode()` | Custom encoding | Monero-specific base58 (8-byte chunks) |
| `encode_monero_block()` | Block encoding | Base58 digit conversion per Monero spec |

### `swift-app/Sources/ContentView.swift`

**Purpose**: Provides a user-friendly macOS GUI for key generation.

**Key Components**:

- **UI Layout**: VStack with buttons (Generate, Clear, Copy) and a scrollable output area
- **State Management**: `@State` properties for output, generation status, error/success messages
- **Process Management**: Uses `Process` API to invoke `cargo run` and capture stdout/stderr
- **Clipboard Integration**: Platform-conditional code for NSPasteboard (macOS) / UIPasteboard (iOS)
- **Async Handling**: `withCheckedThrowingContinuation` for non-blocking key generation
- **User Feedback**: Visual indicators for copy success, generation progress, and errors

## Cryptographic Details

### Bitcoin & Litecoin

**Key Derivation**:
```
random seed (32 bytes)
    ↓
secp256k1 secret key
    ↓
public key (compressed)
    ↓
hash160(pubkey) [RIPEMD-160(SHA-256)]
    ↓
Bech32 encoding → P2WPKH address (bc1.../ltc1...)
```

**Address Format**:
- Bitcoin: `bc1` (Bech32)
- Litecoin: `ltc1` (Bech32)
- Both use SegWit v0 (P2WPKH)

### Monero

**Key Derivation** (Custom ed25519):
```
random seed (32 bytes)
    ↓
Scalar reduction → spend private key
    ↓
Keccak-256(spend_private)
    ↓
Scalar reduction → view private key
    ↓
EdwardsPoint::mul_base() for both → public keys
    ↓
[0x12 | public_spend | public_view | checksum(4 bytes)]
    ↓
Custom base58 encoding (8-byte chunks) → address
```

**Notable Features**:
- View key derived deterministically from spend key
- Primary address includes both public keys for complete transaction scanning
- Custom base58 alphabet: `123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz` (no 0, I, O, l)
- Block-wise encoding: 8-byte chunks encoded separately, padded with '1' prefix

### Solana

**Key Derivation**:
```
random seed (32 bytes)
    ↓
Ed25519 signing key (private)
    ↓
Ed25519 verifying key (public)
    ↓
Keypair: [seed || public_key] (64 bytes)
    ↓
Base58 encoding → address
```

**Key Format**:
- Entire keypair (64 bytes) base58-encoded for import/export
- Public key alone is the address

### Ethereum

**Key Derivation**:
```
random seed (32 bytes)
    ↓
secp256k1 secret key
    ↓
public key (uncompressed, 64 bytes, drop 0x04 prefix)
    ↓
Keccak-256(public_key) → 32-byte hash
    ↓
last 20 bytes → raw address
    ↓
EIP-55 checksumming (mixed-case hex) → checksummed address
```

**EIP-55 Checksumming**:
```
lowercase_hex = hex(address[10:])
hash = Keccak-256(lowercase_hex)

for each character in lowercase_hex:
    if numeric: keep as-is
    else:
        if corresponding hash nibble ≥ 8: uppercase
        else: lowercase
```

## Data Flow Example

**User Action**: Click "Generate Keys" in Swift GUI

1. **Swift Layer**:
   - Disable buttons, show "Generating..." progress
   - Construct Process with args: `["cargo", "run", "--manifest-path", "rust-app/Cargo.toml", "--quiet"]`
   - Set stdout/stderr pipes

2. **Process Execution**:
   - Cargo compiles (if needed) and runs Rust binary
   - Binary generates 5 key sets in parallel (via separate function calls)
   - Outputs formatted text to stdout

3. **Swift Capture**:
   - Waits for process termination
   - Reads all data from stdout pipe
   - Decodes as UTF-8 string

4. **UI Update**:
   - Trim whitespace from output
   - Set `@State` property `output`
   - SwiftUI re-renders with results
   - Enable buttons again

5. **User Action**: Click "Copy"
   - Access NSPasteboard (macOS)
   - Set string type to `output`
   - Show green "Copied to clipboard" message for 1.5 seconds

## Extensibility Points

### Adding a New Cryptocurrency

To support Chain X, follow this pattern:

**In `main.rs`**:

```rust
struct ChainXKeys {
    private_key: String,
    public_key: String,
    address: String,
}

fn generate_chainx_keys(rng: &mut OsRng) -> Result<ChainXKeys, Box<dyn Error>> {
    // Generate keys using cryptographic primitives
    let private_key = /* ... */;
    let public_key = /* ... */;
    let address = /* ... */;
    
    Ok(ChainXKeys {
        private_key,
        public_key,
        address,
    })
}
```

**In `main()` function**:

```rust
let chainx_keys = generate_chainx_keys(&mut rng)?;
println!("=== Chain X ===");
println!("Private key: {}", chainx_keys.private_key);
println!("Public key: {}", chainx_keys.public_key);
println!("Address: {}", chainx_keys.address);
```

**In `ContentView.swift`**:

Update the description text to mention Chain X.

**In `Cargo.toml`**:

Add dependencies as needed (e.g., chain-specific crates).

### UI Enhancements

Potential improvements:

1. **Chain Selection**: Toggle which chains to generate (reduce output clutter)
2. **Export Formats**: Support JSON, CSV, or hardware wallet imports
3. **QR Codes**: Display addresses as scannable QR codes
4. **Testnet Support**: Generate testnet keys for Bitcoin/Litecoin/Ethereum
5. **Mnemonic Phrases**: BIP39 seed phrases for deterministic wallets
6. **Key Verification**: UI to verify a given address belongs to a private key

### Performance Optimization

Current bottlenecks:

1. **Cargo compilation overhead**: Process startup ~2–5 seconds for debug builds
   - *Solution*: Pre-build release binary, cache compilation
2. **Keccak-256 hashing**: Used by Monero and Ethereum
   - *Solution*: Already using fast `tiny-keccak`; minimal overhead
3. **Ed25519 point multiplication**: Used by Monero and Solana
   - *Solution*: `curve25519-dalek` is highly optimized; negligible cost

## Error Handling

**Rust Layer**:
- Uses `Result<T, Box<dyn Error>>` for error propagation
- Each function returns errors that bubble up to `main()`
- Process exit code signals success (0) or failure (non-zero)

**Swift Layer**:
- Captures stderr if exit code ≠ 0
- Displays error message in red text
- Maintains UI responsiveness even on error

## Testing Strategy

**Rust Tests** (`cargo test`):
- Unit tests for encoding functions (Bech32, base58)
- Validation of key format consistency
- Address checksum verification

**Swift Tests** (`swift test`):
- Integration tests for Process invocation
- UI state management tests
- Clipboard functionality tests

**Manual Testing**:
- Validate generated addresses on-chain (use testnet)
- Verify private keys import to standard wallets
- Compare output against known test vectors

## Security Considerations

1. **Entropy Source**: Uses `OsRng` (cryptographically secure)
2. **Key Handling**: All keys ephemeral (not persisted by the generator)
3. **Process Isolation**: Swift → Rust via IPC (keys never cross process boundary in plaintext)
4. **No Networking**: Generator is completely offline
5. **Dependency Audits**: Use `cargo audit` to check for known vulnerabilities

---

**Design Philosophy**: Keep cryptographic logic in Rust (correctness, performance), UI logic in Swift (native feel, accessibility).
