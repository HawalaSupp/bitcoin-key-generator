# Multi-Chain Cryptocurrency Key Generator

A Rust CLI tool with a SwiftUI macOS interface that generates cryptographically secure keys and addresses for Bitcoin, Litecoin, Monero, Solana, and Ethereum.

## Overview

This workspace combines Rust cryptographic primitives with a native SwiftUI front-end to provide a user-friendly multi-chain key generation experience. The Rust backend handles all cryptographic operations, while the Swift layer provides a macOS GUI with copy-to-clipboard functionality.

## Features

### Supported Cryptocurrencies

1. **Bitcoin (P2WPKH)**
   - Private key (hex and WIF formats)
   - Compressed public key
   - Bech32 SegWit address (bc1...)

2. **Litecoin (P2WPKH)**
   - Private key (hex and Litecoin WIF)
   - Compressed public key
   - Bech32 SegWit address (ltc1...)

3. **Monero**
   - Private spend and view keys (ed25519 scalars)
   - Public spend and view keys
   - Primary address (custom base58 encoding per Monero specs)
   - Address checksum validation

4. **Solana**
   - Ed25519 seed and keypair
   - Private key (base58-encoded keypair)
   - Public key / address (base58-encoded)

5. **Ethereum**
   - Private key (256-bit hex)
   - Uncompressed public key (Keccak-256 derived)
   - EIP-55 checksummed address

### Key Features

- **Cryptographically Secure**: Uses OS-level RNG (`OsRng`) for entropy
- **Copy to Clipboard**: SwiftUI button instantly copies all output to macOS clipboard
- **Clear Output**: One-click clearing of generated keys
- **Error Handling**: Graceful error messages if generation fails

## Project Structure

```
.
├── rust-app/
│   ├── src/
│   │   └── main.rs         # Multi-chain key generator logic
│   ├── Cargo.toml          # Rust dependencies
│   └── Cargo.lock          # Locked dependency versions
│
├── swift-app/
│   ├── Sources/
│   │   └── ContentView.swift # SwiftUI GUI
│   ├── Package.swift
│   └── Tests/
│
├── README.md               # This file
└── docs/                   # Additional documentation
```

## Dependencies

### Rust (`Cargo.toml`)

- **bitcoin** (0.32): Bitcoin cryptography and address encoding
- **bs58** (0.4): Base58 encoding (Monero, Solana)
- **bech32** (0.9): Bech32 encoding (Bitcoin/Litecoin)
- **ed25519-dalek** (2.0): Ed25519 signing (Solana, Monero)
- **curve25519-dalek** (4.1): Curve25519 elliptic curve (Monero)
- **tiny-keccak** (2.0): Keccak-256 hashing (Ethereum, Monero)
- **hex** (0.4): Hexadecimal encoding
- **rand** (0.8): Cryptographic randomness

### Swift

- SwiftUI (macOS 12.0+)
- Foundation (Process management)

## Build Commands

```bash
# Build only Rust
cargo build --manifest-path rust-app/Cargo.toml

# Build only Swift
swift build --package-path swift-app

# Build both (sequential)
cargo build --manifest-path rust-app/Cargo.toml && \
swift build --package-path swift-app
```

## Running the Applications

### Rust CLI (Direct)

```bash
cargo run --manifest-path rust-app/Cargo.toml --bin rust-app
```

**Sample Output:**

```
=== Bitcoin (P2WPKH) ===
Private key (hex): 199de1c9e4e8f956b9e86cee3db535b454c4cde23e8383df593822a5e1a49343
Private key (WIF): Kx5WKxAJzhcLURwRmGWnJd5ZULtxH5H6wgBrydn6c8hpMtaKgVcw
Public key (compressed hex): 02f8946397c7a300f9fca1b330fbe8245b9689807b9d1304e15b5c57aa1d115fee
Bech32 address (P2WPKH): bc1qjvkdhpem3jn4mkgkw33dyn4pkvjtgwn0fkdcp0

=== Litecoin (P2WPKH) ===
Private key (hex): a9019e155008668cbdd2ce55a5897974db124e4093c70238a77313777391cb71
Private key (WIF): T8iW9Y1D14CWXt2GKguKUeuD9rjXNA5A9ryVoSf6P6cA7jTuD3CH
Public key (compressed hex): 03e0d2111bb267f90fb97a36ba18498ac02eaac27f283cd7d5bc362c47c6164205
Bech32 address (P2WPKH): ltc1qaxk6ufcra7zqtwjr4pr735qyqpt7ze0qsdhl2l

=== Monero ===
Private spend key (hex): f95df22597a1a57e53f01ebcc99e3bf960bf385a6336275fe00f3f0586dd120f
Private view key (hex): 9a60e85975eee493d02bb9a4510140b10e8b3034173e46fa04a8ddb780408c09
Public spend key (hex): 11965f4aa9f70a25b8f03c63866cce6022efa2a776821315d1506c0ed4c30146
Public view key (hex): 0ca8ea93d2382fd5eae436efa73d2be3a0f06142929b13cd3cf5b803709cb64c
Primary address: 2qQ58Yj8DehbXa6giABS3n4GGXpWPEfWo1J86KCb31yN8u7WRekjknh8EVSY8pxo1v4HDiaYg1pWeXYZGGvh8JeG11d8

=== Solana ===
Private seed (hex): 4d183c5feead109bbca0b8b9cfd2daa6ebe35d6fda3e52aba7913a2ef1ea196a
Private key (base58): 2YQAfkg5CKzRfosHwyyawSSWjSvZDXXmoHUixchJswAZB5ycqTcRwWRCWu9Q3Dt83gBoNzSkTCS6QFrY1dTtenU
Public key / address (base58): 69nuU4m1QEb9VtERKxqty2ZShWK83wzocUn1BbCrCFpA

=== Ethereum ===
Private key (hex): e1d53f00d25ea0557b353829a85bb256973ea5d89c7b49f5346c27b49abfddaa
Public key (uncompressed hex): 6fbfdce9eea7d83511bd133c456bb10952e371bf34c13db3ded45c95bef5a0e6b4ed7164c56bdb
Checksummed address: 0x7160a854BA41D4F3099C6a366bA0201f7756E719
```

### SwiftUI Application (GUI)

```bash
swift run --package-path swift-app
```

**Usage:**

1. Click **"Generate Keys"** to invoke the Rust binary and display credentials for all five chains
2. Click **"Copy"** to copy the entire output to macOS clipboard (with visual confirmation)
3. Click **"Clear"** to remove the output and reset the interface
4. All operations run asynchronously; the UI remains responsive

## Testing

```bash
# Test Rust
cargo test --manifest-path rust-app/Cargo.toml

# Test Swift
swift test --package-path swift-app
```

## Cryptographic Notes

### Bitcoin & Litecoin

- Uses secp256k1 elliptic curve (via `bitcoin` crate)
- P2WPKH (Pay-to-Witness-Public-Key-Hash) format for SegWit addresses
- WIF (Wallet Import Format) for private key export
- Litecoin WIF prefix: `0xB0` (instead of Bitcoin's `0x80`)

### Monero

- Ed25519 elliptic curve for spend/view key generation
- View key derived from spend key via Keccak-256 hash
- Primary address: version byte (0x12) + public spend + public view + 4-byte checksum
- Custom base58 alphabet and block-wise encoding per Monero specification

### Solana

- Ed25519 keypair generation
- Private key stored as 64-byte keypair (seed + public key)
- Base58 encoding for key serialization

### Ethereum

- secp256k1 elliptic curve (same as Bitcoin)
- Uncompressed public key (without 0x04 prefix) hashed with Keccak-256
- Last 20 bytes of hash become the address
- EIP-55 checksummed format for human-readable addresses

## Security Considerations

⚠️ **Warning**: This is a demonstration tool. For production use:

- **Never share your private keys** with anyone
- **Back up private keys securely** (hardware wallet, encrypted storage)
- **Validate addresses** on-chain before sending funds
- **Use hardware wallets** for high-value holdings
- **Test with small amounts** before moving large sums
- **Audit cryptographic code** before production deployment

## Development

### Adding a New Cryptocurrency

To add support for another chain:

1. Create a new `generate_<chain>_keys()` function in `rust-app/src/main.rs`
2. Add the corresponding struct and printing logic in `main()`
3. Update `swift-app/Sources/ContentView.swift` description
4. Add dependencies to `Cargo.toml` as needed
5. Update this README with the new chain details

### macOS Build Requirements

- Xcode 14.0+
- Swift 5.9+
- Rust 1.70+ (toolchain via `rustup`)

## License

See `LICENSE` file for details.

## References

- [Bitcoin BIP32](https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki)
- [Monero Address Format](https://monerodocs.org/)
- [Solana Documentation](https://docs.solana.com/)
- [Ethereum Yellow Paper](https://ethereum.org/en/developers/docs/evm/)

---

**Last Updated**: November 2025  
**Maintenance**: This workspace is actively maintained. Issues and PRs welcome.
