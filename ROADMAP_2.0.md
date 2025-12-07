# Hawala 2.0 – Path to Production Roadmap
**Last Updated:** December 7, 2025
**Current Status:** Alpha - Phase 2 Complete (Data Persistence & State Management)

This roadmap outlines the strategic steps to evolve Hawala from a "Key Generator & Balance Checker" into a fully functional, production-grade multi-chain wallet.

---

## 🚀 Phase 1: Transaction Infrastructure ✅ COMPLETE
**Goal:** Enable real value transfer for all supported chains.

### 1.1 Complete Signing Logic
- [x] **Bitcoin (BTC):** Implemented & Tested.
- [x] **Ethereum (ETH):** Implemented & Tested.
- [x] **Solana (SOL):** Implemented & Tested.
- [x] **XRP (Ripple):** Fully implemented with real xrpl-rust serialization and cryptographic signing.
- [~] **Monero (XMR):** Deferred to Phase 2 - requires RPC bridge integration (client-side RingCT is too complex without chain sync).

### 1.2 Broadcasting Layer
- [x] **Network Managers:** All chain-specific broadcast services implemented.
    - `BitcoinNetworkService`: Push via Mempool.space API.
    - `EthereumNetworkService`: `eth_sendRawTransaction` via Alchemy.
    - `SolanaNetworkService`: `sendTransaction` via RPC.
    - `XRPNetworkService`: `submit` command via JSON-RPC.
- [x] **Transaction Status Tracking:**
    - Polling mechanism for all chains (BTC, ETH, SOL, XRP).
    - Confirmation count tracking.
    - Handle "pending" vs "confirmed" vs "failed" states.

### 1.3 Fee Estimation
- [x] **Bitcoin:** Live fees from mempool.space (Fastest/Fast/Medium/Slow).
- [x] **Ethereum:** EIP-1559 aware (baseFee + priorityFee) via Etherscan.
- [x] **Solana:** Priority fee estimation via RPC.
- [x] **XRP:** Open ledger fee and queue monitoring via rippled.

---

## 💾 Phase 2: Data Persistence & State Management ✅ COMPLETE
**Goal:** Make the app usable offline and responsive.

### 2.1 Local Database
- [x] Integrate **SQLite** (via GRDB.swift) to store:
    - Wallets (Metadata, not keys) - `WalletRecord`
    - Transactions (History) - `TransactionRecord`, `TransactionStore`
    - UTXOs (for Bitcoin/Litecoin) - `UTXORecord`, `UTXOStore`
    - Sync State - `SyncStateRecord`, `SyncStateStore`
    - Balance Cache - `CachedBalanceRecord`, `BalanceCacheStore`
- [x] **Migration Strategy:** Schema versioning via `DatabaseMigrator` with `v1_initial` migration.

### 2.2 Sync Engine
- [x] **Incremental Sync:** `SyncEngine` tracks last block height per chain.
- [~] **Background Fetch:** Deferred - requires app lifecycle integration (BGAppRefreshTask).
- [x] **UTXO Management:** `UTXOCoinSelector` with largest-first coin selection, fee estimation, and integration with `BitcoinTransactionBuilder`.

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
