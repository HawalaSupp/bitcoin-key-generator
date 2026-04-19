# Milestone 3: Chain Expansion (SOL + XRP + LTC + Multi-EVM)

## Overview
**Goal:** Broaden chain set without compromising UX/security. Implement unified ChainAdapter pattern.

**Timeline:** 4-10 weeks  
**Status:** 🚧 In Progress  
**Started:** December 2024

---

## Definition of Done (DoD)

- [ ] Each chain: send + receive + history with correct chain-specific warnings
- [ ] Testnet support works and is visually separated
- [ ] ChainAdapter protocol fully implemented for all target chains
- [ ] Unit tests for each chain's transaction building
- [ ] No chain-specific bugs in fee calculation or transaction signing

---

## Target Chains (Priority Order)

| Priority | Chain | Status | Notes |
|----------|-------|--------|-------|
| 1 | Litecoin (LTC) | ✅ Complete | Full send/receive in SendView |
| 2 | Solana (SOL) | ✅ Complete | Ed25519, blockhash, fixed fee display |
| 3 | XRP (Ripple) | ✅ Complete | Destination tags, sequence numbers |
| 4 | Polygon (MATIC) | ⏳ Partial | EVM, already have infrastructure |
| 5 | BNB Chain (BSC) | ⏳ Partial | EVM, already have infrastructure |
| 6 | Cosmos (ATOM) | 📋 Planned | Memo, gas model |
| 7 | Cardano (ADA) | 📋 Planned | eUTXO model |

---

## Existing Infrastructure Audit

### ✅ Already Implemented
| Component | File | Status |
|-----------|------|--------|
| Litecoin Keys | `LitecoinKeys` in ContentView | ✅ Derivation works |
| Litecoin Fee Estimation | `FeeEstimationService.fetchLitecoinFees()` | ✅ Blockchair API |
| Litecoin Transaction Builder | `litecoin_wallet.rs` (Rust) | ✅ Complete |
| Litecoin Broadcaster | `TransactionBroadcaster.broadcastLitecoin()` | ✅ Blockchair/Blockcypher |
| Litecoin SendView | `SendView.swift` case `.litecoin` | ✅ Complete |
| Solana Keys | `SolanaKeys` in ContentView | ✅ Ed25519 derivation |
| Solana Broadcaster | `SolanaNetworkService` | ⏳ Needs verification |
| XRP Keys | `XrpKeys` in ContentView | ✅ secp256k1 derivation |
| XRP Broadcaster | `XRPNetworkService` | ⏳ Needs verification |
| EVM Transaction Builder | `EthereumTransaction.swift` | ✅ Complete |
| Polygon/BSC Support | Chain IDs configured | ⏳ Partial |

### 🔧 Needs Work
| Component | Issue | Priority |
|-----------|-------|----------|
| ~~Litecoin Transaction Builder~~ | ~~Create `LitecoinTransaction.swift`~~ | ✅ DONE |
| ~~Litecoin UTXO Store~~ | ~~Extend UTXOStore for LTC~~ | ✅ DONE (Rust handles) |
| Solana Transaction Builder | Verify `SolanaTransaction.swift` signing | HIGH |
| XRP Transaction Builder | Complete `XRPTransaction.swift` | HIGH |
| ChainAdapter Protocol | Unified interface | HIGH |
| Multi-EVM Chain Switcher | UI for Polygon/BSC selection | MEDIUM |

---

## Detailed Task Breakdown

### M3.1 — Litecoin Sending Complete ✅ (Days 1-7)
**Goal:** Full send/receive with UTXO management like Bitcoin
**Status:** ✅ COMPLETE

#### M3.1.1 — Litecoin Transaction Builder ✅
- [x] **M3.1.1.1** Create `litecoin_wallet.rs` (Rust)
  - Adapted Bitcoin transaction building for LTC specifics
  - P2WPKH (native SegWit) transactions
  - Correct version bytes and WIF prefix (0xB0)
  
- [x] **M3.1.1.2** Litecoin UTXO Integration
  - Rust module fetches UTXOs via Blockchair API
  - UTXO selection in Rust code
  - Standard dust threshold handling

- [x] **M3.1.1.3** Litecoin Fee Estimation
  - ✅ Already have `fetchLitecoinFees()` in FeeEstimationService
  - ✅ Wired up to SendView for LTC selection
  - ✅ Shows sat/vB estimates (same as Bitcoin UI)

#### M3.1.2 — Litecoin Send UI ✅
- [x] **M3.1.2.1** Enable LTC in SendView
  - ✅ Added `.litecoin` case to Chain enum
  - ✅ Address validation (ltc1 bech32 + L/M prefixes)
  
- [x] **M3.1.2.2** Litecoin Broadcaster
  - ✅ `TransactionBroadcaster.broadcastLitecoin()` implemented
  - ✅ Uses Blockchair primary, Blockcypher fallback
  - ✅ Explorer link to litecoinspace.org

#### M3.1.3 — Litecoin Receive ✅
- [x] **M3.1.3.1** QR Code generation for LTC addresses (already existed)
- [x] **M3.1.3.2** Litecoin-specific payment URI (litecoin:address?amount=...)

---

### M3.2 — Solana Sending Polish ✅ (Days 8-14)
**Goal:** Reliable SOL transfers with proper slot/blockhash handling
**Status:** ✅ COMPLETE (basic flow verified)

#### M3.2.1 — Solana Transaction Verification ✅
- [x] **M3.2.1.1** Verify Ed25519 signing
  - ✅ Using solana-sdk Rust crate for signing
  - ✅ Keypair from base58 private key
  
- [x] **M3.2.1.2** Recent Blockhash Management
  - ✅ Fetch latest blockhash before signing (`getSolanaBlockhash`)
  - ✅ Using "finalized" commitment level
  - Transaction expires if blockhash too old (~60-90 slots)

#### M3.2.2 — Solana Fee Estimation ✅
- [x] **M3.2.2.1** Fixed Fee Display
  - ✅ Added `fixedFeeInfoSection` for Solana/XRP
  - ✅ Shows ~0.000005 SOL fixed fee
  - ✅ Shows ~1 min confirmation time

- [ ] **M3.2.2.2** Compute Budget Integration (FUTURE)
  - Set appropriate compute limits for complex txs
  - Priority fee support for congestion

#### M3.2.3 — Solana Transaction Status ✅
- [x] **M3.2.3.1** Confirmation Tracking
  - ✅ `TransactionConfirmationTracker` supports Solana
  - ✅ Explorer link to explorer.solana.com

---

### M3.3 — XRP Sending Polish ✅ (Days 15-21)
**Goal:** Complete XRP transfers with destination tags and proper sequence handling
**Status:** ✅ COMPLETE

#### M3.3.1 — XRP Transaction Verification ✅
- [x] **M3.3.1.1** Verify secp256k1 Signing
  - ✅ Using xrpl Rust crate for signing
  - ✅ Canonical signature format via `sign()` function
  
- [x] **M3.3.1.2** Sequence Number Management
  - ✅ Fetch current sequence from `account_info` RPC
  - ✅ `getXRPSequence()` in TransactionBroadcaster

#### M3.3.2 — Destination Tag Support ✅
- [x] **M3.3.2.1** UI for Destination Tags
  - ✅ `xrpOptionsSection` in SendView
  - ✅ Optional destination tag field
  - ✅ "Some exchanges require a destination tag" hint

- [x] **M3.3.2.2** Tag Integration
  - ✅ Rust `prepare_xrp_transaction` accepts `destination_tag: Option<u32>`
  - ✅ Swift passes tag via `--destination-tag` CLI arg
  - ✅ Tag embedded in signed transaction

#### M3.3.3 — XRP Fee Model ✅
- [x] **M3.3.3.1** Fee Display
  - ✅ Fixed 12 drops fee in transaction
  - ✅ `fixedFeeInfoSection` shows ~0.00001 XRP
  - ✅ ~4 sec confirmation time displayed

---

### M3.4 — Multi-EVM Chain Support (Days 22-28)
**Goal:** Polygon and BSC parity with Ethereum

#### M3.4.1 — Chain Registry
- [ ] **M3.4.1.1** EVM Chain Configuration
  - Define chain configs: chainId, RPC URLs, explorers
  - Native token symbols (ETH, MATIC, BNB)
  - Gas token decimals

- [ ] **M3.4.1.2** Chain Switcher UI
  - Add Polygon/BSC to chain selector in SendView
  - Clear visual distinction between chains
  - Remember last used chain

#### M3.4.2 — Multi-Chain Gas Estimation
- [ ] **M3.4.2.1** Chain-Specific Gas APIs
  - Polygon: polygonscan.com gas oracle
  - BSC: bscscan.com gas oracle
  - Fallback to RPC eth_gasPrice

- [ ] **M3.4.2.2** Gas Price Warnings
  - Warn if gas unusually high for chain
  - Show USD equivalent

#### M3.4.3 — EVM Token Support Prep
- [ ] **M3.4.3.1** ERC-20 Balance Display
  - Parse token balances from API
  - Show in wallet overview
  
- [ ] **M3.4.3.2** Token Send Preparation
  - Token selector in SendView
  - Gas limit estimation for token transfers

---

### M3.5 — ChainAdapter Protocol (Days 29-35)
**Goal:** Unified interface for all chain operations

#### M3.5.1 — Protocol Definition
- [ ] **M3.5.1.1** Create `ChainAdapter` Protocol
  ```swift
  protocol ChainAdapter {
      var chainId: String { get }
      var displayName: String { get }
      var nativeSymbol: String { get }
      
      func deriveAddress(from publicKey: Data) -> String
      func validateAddress(_ address: String) -> Bool
      func fetchBalance(for address: String) async throws -> Decimal
      func fetchTransactionHistory(for address: String) async throws -> [Transaction]
      func estimateFee(for transaction: TransactionRequest) async throws -> FeeEstimate
      func buildTransaction(_ request: TransactionRequest) async throws -> SignableTransaction
      func signTransaction(_ tx: SignableTransaction, with privateKey: Data) async throws -> SignedTransaction
      func broadcastTransaction(_ signedTx: SignedTransaction) async throws -> String
  }
  ```

- [ ] **M3.5.1.2** Implement Adapters
  - `BitcoinChainAdapter`
  - `LitecoinChainAdapter`
  - `EthereumChainAdapter` (shared for all EVM)
  - `SolanaChainAdapter`
  - `XRPChainAdapter`

#### M3.5.2 — Chain Registry Service
- [ ] **M3.5.2.1** ChainRegistry Singleton
  - Register all available adapters
  - Lookup by chainId
  - Enable/disable chains dynamically

---

### M3.6 — Testing & Validation (Days 36-42)
**Goal:** Comprehensive test coverage for all chains

#### M3.6.1 — Unit Tests
- [ ] **M3.6.1.1** Litecoin Transaction Tests
  - Address validation
  - UTXO selection
  - Fee calculation
  - Transaction building

- [ ] **M3.6.1.2** Solana Transaction Tests
  - Ed25519 signature verification
  - Blockhash handling
  - Compute budget

- [ ] **M3.6.1.3** XRP Transaction Tests
  - Sequence number logic
  - Destination tag handling
  - Fee calculation

- [ ] **M3.6.1.4** Multi-EVM Tests
  - Chain-specific gas estimation
  - ChainId verification

#### M3.6.2 — Integration Tests
- [ ] **M3.6.2.1** Testnet Sends
  - LTC testnet transaction
  - SOL devnet transaction
  - XRP testnet transaction
  - Polygon Mumbai transaction
  - BSC testnet transaction

---

## File Structure (New Files)

```
Sources/
├── HawalaCore/
│   ├── ChainAdapters/
│   │   ├── ChainAdapter.swift           # Protocol definition
│   │   ├── ChainRegistry.swift          # Registry service
│   │   ├── BitcoinChainAdapter.swift
│   │   ├── LitecoinChainAdapter.swift
│   │   ├── EthereumChainAdapter.swift   # Shared for EVM chains
│   │   ├── SolanaChainAdapter.swift
│   │   └── XRPChainAdapter.swift
│   └── Transactions/
│       └── LitecoinTransaction.swift
└── HawalaApp/
    └── Services/
        └── LitecoinNetworkService.swift

Tests/
└── swift-appTests/
    ├── LitecoinTransactionTests.swift
    ├── SolanaTransactionTests.swift
    └── XRPTransactionTests.swift
```

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Solana blockhash expiry | Retry logic with fresh blockhash |
| XRP sequence conflicts | Lock sequence during pending tx |
| EVM chain confusion | Clear visual indicators, chain name in tx confirmation |
| Fee estimation inaccuracy | Multiple API sources, fallback defaults |

---

## Progress Tracking

| Section | Status | % Complete |
|---------|--------|------------|
| M3.1 Litecoin | 🚧 Starting | 0% |
| M3.2 Solana | ⏳ Pending | 0% |
| M3.3 XRP | ⏳ Pending | 0% |
| M3.4 Multi-EVM | ⏳ Pending | 0% |
| M3.5 ChainAdapter | ⏳ Pending | 0% |
| M3.6 Testing | ⏳ Pending | 0% |

**Overall M3 Progress:** 0%
