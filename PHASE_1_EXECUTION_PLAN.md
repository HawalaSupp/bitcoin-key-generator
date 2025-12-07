# Phase 1 Execution Plan: Transaction Infrastructure
**Status:** In Progress  
**Goal:** Move from "Read-Only" to "Read-Write" capability for all supported chains.

This document details the technical implementation steps for Phase 1 of the Hawala 2.0 Roadmap.

---

## 1. Rust Backend: Signing Logic Completion

### 1.1 XRP (Ripple) Implementation
**Current Status:** Mock implementation returning dummy hex.
**Objective:** Implement real offline transaction serialization and signing.

*   **Step 1: Dependency Verification**
    *   Verify `xrpl-rust` crate capabilities. Does it support `Payment` transaction serialization?
    *   *Fallback:* If `xrpl-rust` is immature, implement minimal serialization for `Payment` type manually (RC4 serialization).
*   **Step 2: Implementation (`rust-app/src/xrp_wallet.rs`)**
    *   Define `XrpTransaction` struct.
    *   Implement `serialize()` to produce canonical binary format.
    *   Implement `sign()` using `secp256k1` (already in dependencies).
*   **Step 3: Testing**
    *   Add official XRPL test vectors to `tests/`.
    *   Verify output against `rippled` sign command.

### 1.2 Monero (XMR) Strategy
**Current Status:** Address validation only.
**Objective:** Enable spending capability.
**Challenge:** Monero requires "Ring Signatures" which need decoy outputs (mixins) fetched from the blockchain. It is not purely stateless like BTC/ETH.

*   **Step 1: Feasibility Study**
    *   Can we fetch mixins via Swift (API) and pass them to Rust?
    *   *Investigation:* Check `monero-rs` crate for `Transaction` builder support.
*   **Step 2: Implementation Path (Select One)**
    *   *Path A (Preferred):* **Light Wallet Mode.** Swift fetches unspent outputs + decoys from a remote node. Rust constructs the RingCT transaction.
    *   *Path B (Fallback):* **RPC Bridge.** Bundle `monero-wallet-rpc` binary and orchestrate it via Swift. (Easier dev, larger app size).
*   **Step 3: Execution**
    *   Implement `generate_key_image` in Rust (needed to check if funds are spent).
    *   Implement `create_transaction` accepting `inputs`, `mixins`, and `outputs`.

---

## 2. Swift Frontend: Broadcasting Layer

**Objective:** Send the signed hex strings to the respective blockchain networks.

### 2.1 Network Service Architecture
Create a unified protocol for transaction broadcasting.

```swift
protocol TransactionBroadcaster {
    func broadcast(hex: String, for chain: Chain) async throws -> String // Returns TxHash
}
```

### 2.2 Chain-Specific Implementations

#### **Bitcoin (BTC)**
*   **API:** Blockstream API (`https://blockstream.info/api/tx`) or Mempool.space.
*   **Method:** POST raw hex.
*   **Task:** Create `BitcoinService.swift`.

#### **Ethereum (ETH)**
*   **API:** Alchemy (Existing integration).
*   **Method:** JSON-RPC `eth_sendRawTransaction`.
*   **Task:** Extend `AlchemyService.swift`.

#### **Solana (SOL)**
*   **API:** Solana JSON RPC.
*   **Method:** `sendTransaction` (Base64 encoded).
*   **Task:** Create `SolanaService.swift`.

#### **XRP (Ripple)**
*   **API:** XRPL JSON-RPC (Public nodes like `s1.ripple.com`).
*   **Method:** `submit` command.
*   **Task:** Create `XRPService.swift`.

---

## 3. Integration & UI

### 3.1 The "Send" Flow
*   **Step 1:** User enters Address & Amount.
*   **Step 2:** Swift calls Rust `prepare_transaction` -> gets `SignedHex`.
*   **Step 3:** Swift calls `TransactionBroadcaster.broadcast(hex)`.
*   **Step 4:** UI shows "Transaction Submitted" with Explorer Link.

### 3.2 Transaction Monitoring
*   Implement a polling mechanism to check status of `TxHash`.
*   Update local balance once confirmed.

---

## 4. Immediate Next Actions (Checklist)

- [ ] **Rust:** Implement `sign-xrp` with real serialization.
- [ ] **Swift:** Create `TransactionBroadcaster` protocol.
- [ ] **Swift:** Implement `BitcoinService` broadcast method.
- [ ] **Swift:** Implement `EthereumService` broadcast method.
- [ ] **Test:** End-to-end test on Testnets (Sepolia, BTC Testnet).
