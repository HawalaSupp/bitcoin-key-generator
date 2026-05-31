# Hawala - Security-First Multi-Chain Cryptocurrency Wallet

Hawala is a pre-production, security-first cryptocurrency wallet with a Rust backend and native SwiftUI macOS interface. The codebase contains broad multi-chain and cutting-edge wallet work, but public product claims must follow the code-owned capability registry and production readiness gates in `docs/HAWALA_PRODUCTION_READY_MASTER_ROADMAP.md`.

Current public launch candidates are intentionally conservative: Bitcoin, Litecoin, Ethereum, Solana, XRP, and selected Ethereum ERC-20 token flows. Additional chains and advanced features remain internal until they are real-provider backed, tested end to end, recoverable, observable, and security-reviewed.

## Overview

Hawala combines Rust cryptographic primitives with a native SwiftUI front-end to provide a secure wallet experience. The Rust backend handles cryptographic operations, transaction signing, chain logic, and FFI-facing wallet services, while the Swift layer provides onboarding, portfolio, transaction, security, backup, and settings workflows.

This repository is being moved toward a production discipline where incomplete features are hidden from normal builds instead of being marketed early.

## Features

### Chain Scope

Production visibility is governed by `swift-app/Sources/swift-app/Utilities/ChainCapabilityRegistry.swift`.

**Launch candidates:**
- Bitcoin
- Litecoin
- Ethereum
- Solana
- XRP
- Selected Ethereum ERC-20 token cards

**Internal or deferred until gated:**
- EVM L2s and alternate L1s
- Cosmos/IBC flows
- Swaps and bridges
- Staking
- Hardware wallet signing
- Lightning and Ordinals
- ERC-4337, EIP-7702, passkeys, and other advanced account features

### Broader Implemented / Experimental Chain Work

**Major Chains:**
- Bitcoin (BTC) - SegWit, Taproot, RBF
- Ethereum (ETH) - EIP-1559, ERC-20
- Solana (SOL) - SPL tokens, staking
- Polygon, Arbitrum, Optimism, Base - L2 support

**EVM Compatible:**
- Avalanche, BNB Chain, Fantom, Harmony, Moonbeam

**Smart Contract Platforms:**
- Cardano, Polkadot, Cosmos, Tezos, Near, Sui, Aptos

**UTXO Chains:**
- Litecoin, Dogecoin, Bitcoin Cash, Dash, Zcash, Ravencoin

**Privacy Coins:**
- Monero, Zcash (shielded)

### Cutting-Edge Features (Phase 4)

- **ERC-4337 Smart Accounts**: Account abstraction with counterfactual addresses
- **Gasless Transactions**: Paymaster integration for sponsored gas
- **Multi-Chain Gas Account**: Single balance pays gas on any chain
- **Passkey Authentication**: WebAuthn/Face ID integration
- **Hardware Wallet Support**: Ledger integration
- **Cross-Chain Bridging**: Wormhole, LayerZero, Stargate

### Key Capabilities

- **1,100+ Tests**: 902 Rust + 213 Swift tests with comprehensive coverage
- **120fps Performance**: Optimized for ProMotion displays
- **Security Hardened**: Constant-time comparisons, memory zeroing
- **Transaction Simulation**: Pre-sign preview of balance changes
- **Phishing Protection**: Blacklist checking, risk warnings

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
Private key (hex): <redacted>
Private key (WIF): <redacted>
Public key (compressed hex): 02f8946397c7a300f9fca1b330fbe8245b9689807b9d1304e15b5c57aa1d115fee
Bech32 address (P2WPKH): bc1qjvkdhpem3jn4mkgkw33dyn4pkvjtgwn0fkdcp0

=== Litecoin (P2WPKH) ===
Private key (hex): <redacted>
Private key (WIF): <redacted>
Public key (compressed hex): 03e0d2111bb267f90fb97a36ba18498ac02eaac27f283cd7d5bc362c47c6164205
Bech32 address (P2WPKH): ltc1qaxk6ufcra7zqtwjr4pr735qyqpt7ze0qsdhl2l

=== Monero ===
Private spend key (hex): <redacted>
Private view key (hex): <redacted>
Public spend key (hex): 11965f4aa9f70a25b8f03c63866cce6022efa2a776821315d1506c0ed4c30146
Public view key (hex): 0ca8ea93d2382fd5eae436efa73d2be3a0f06142929b13cd3cf5b803709cb64c
Primary address: 2qQ58Yj8DehbXa6giABS3n4GGXpWPEfWo1J86KCb31yN8u7WRekjknh8EVSY8pxo1v4HDiaYg1pWeXYZGGvh8JeG11d8

=== Solana ===
Private seed (hex): <redacted>
Private key (base58): <redacted>
Public key / address (base58): 69nuU4m1QEb9VtERKxqty2ZShWK83wzocUn1BbCrCFpA

=== Ethereum ===
Private key (hex): <redacted>
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

## Roadmaps

- `HAWALA_ROADMAP.md` — original broad feature roadmap (2025)
- `FINAL_ROADMAP.md` — **ship plan** based on the full product Q&A (milestones, cut-lines, acceptance criteria)

See `LICENSE` file for details.

## References

- [Bitcoin BIP32](https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki)
- [Monero Address Format](https://monerodocs.org/)
- [Solana Documentation](https://docs.solana.com/)
- [Ethereum Yellow Paper](https://ethereum.org/en/developers/docs/evm/)

---

**Last Updated**: November 2025  
**Maintenance**: This workspace is actively maintained. Issues and PRs welcome.
