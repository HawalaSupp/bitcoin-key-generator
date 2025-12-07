# Hawala 2.0 – Path to Production Roadmap
**Last Updated:** December 7, 2025
**Current Status:** Alpha - Core Signing Infrastructure Implemented

This roadmap outlines the strategic steps to evolve Hawala from a "Key Generator & Balance Checker" into a fully functional, production-grade multi-chain wallet.

---

## 🚀 Phase 1: Transaction Infrastructure (Immediate Priority)
**Goal:** Enable real value transfer for all supported chains.

### 1.1 Complete Signing Logic
- [x] **Bitcoin (BTC):** Implemented & Tested.
- [x] **Ethereum (ETH):** Implemented & Tested.
- [x] **Solana (SOL):** Implemented & Tested.
- [ ] **XRP (Ripple):** 
    - Replace mock implementation in `rust-app/src/xrp_wallet.rs` with real `xrpl-rust` serialization.
    - Verify canonical serialization against `rippled` test vectors.
- [ ] **Monero (XMR):**
    - Evaluate feasibility of client-side RingCT signing vs. `monero-wallet-rpc`.
    - If client-side is too heavy, implement a secure bridge to a local/remote node for signing.
    - **Decision Point:** Pure Rust implementation vs. FFI bindings to C++ Monero libraries.

### 1.2 Broadcasting Layer
- [ ] **Network Managers:** Create Swift services to broadcast signed hexes.
    - `BitcoinNetworkService`: Push via Blockstream/Mempool API.
    - `EthereumNetworkService`: `eth_sendRawTransaction` via Alchemy/Infura.
    - `SolanaNetworkService`: `sendTransaction` via RPC.
    - `XRPNetworkService`: `submit` command via WebSocket/JSON-RPC.
- [ ] **Transaction Status Tracking:**
    - Polling mechanism to check if tx is confirmed.
    - Handle "dropped" or "stuck" transactions (RBF for Bitcoin, Nonce replacement for ETH).

---

## 💾 Phase 2: Data Persistence & State Management
**Goal:** Make the app usable offline and responsive.

### 2.1 Local Database
- [ ] Integrate **SQLite** (via GRDB.swift or CoreData) to store:
    - Wallets (Metadata, not keys).
    - Transactions (History).
    - UTXOs (for Bitcoin/Litecoin).
- [ ] **Migration Strategy:** Ensure schema versioning from day one.

### 2.2 Sync Engine
- [ ] **Incremental Sync:** Only fetch new transactions since last block height.
- [ ] **Background Fetch:** Utilize `BGAppRefreshTask` to keep balances up to date.
- [ ] **UTXO Management:** For BTC, we must track unspent outputs locally to construct transactions without re-scanning the whole chain every time.

---

## 🎨 Phase 3: User Experience (UX) Overhaul
**Goal:** A beautiful, intuitive interface that hides complexity.

### 3.1 "Send" Flow
- [ ] **Input Validation:** Address checksums, ENS resolution, Unstoppable Domains support.
- [ ] **Fee Estimation:**
    - Dynamic fee sliders (Slow/Average/Fast).
    - EIP-1559 gas estimation for ETH.
- [ ] **Review Screen:** Clear breakdown of "You Send", "Network Fee", "Total".

### 3.2 "Receive" Flow
- [ ] **QR Codes:** Generate QR codes for addresses.
- [ ] **Unified Payment Links:** BIP-21 (Bitcoin), EIP-681 (Ethereum).
- [ ] **Privacy Features:** (Optional) Single-use addresses for Bitcoin.

### 3.3 Transaction History
- [ ] **Rich Metadata:** Parse transaction data to show "Swap", "Approve", "Send", "Receive" instead of just raw methods.
- [ ] **Fiat Value at Time of Transaction:** Historical price lookup.

---

## 🔒 Phase 4: Security Hardening
**Goal:** Bank-grade security.

### 4.1 Key Storage
- [ ] **Keychain Access:** Ensure all private keys are stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- [ ] **Biometric Auth:** Require TouchID/FaceID to sign transactions or reveal keys.
- [ ] **Memory Hygiene:** Zeroize sensitive memory in Rust (`zeroize` crate) and Swift after use.

### 4.2 Audit & Compliance
- [ ] **Dependency Audit:** `cargo audit` and `npm audit` (if applicable).
- [ ] **Reproducible Builds:** Ensure the binary can be verified against the source.

---

## 📦 Phase 5: Distribution & Release
**Goal:** Get it in users' hands.

### 5.1 Packaging
- [ ] **App Sandbox:** Configure entitlements for Mac App Store (Network Client, Hardware access if needed).
- [ ] **Notarization:** Set up automated signing pipeline with Apple Developer ID.

### 5.2 CI/CD
- [ ] **GitHub Actions:**
    - Build Rust binary.
    - Build Swift app.
    - Run Integration Tests.
    - Create Release Artifacts (DMG/Zip).

---

## 🛠 Technical Debt & Cleanup
- [ ] **Refactor Rust Bridge:** Move from `Process` spawning to **FFI (Foreign Function Interface)** for performance and security. Spawning a binary is okay for MVP, but FFI is cleaner.
- [ ] **Error Handling:** Standardize error codes between Rust and Swift.
