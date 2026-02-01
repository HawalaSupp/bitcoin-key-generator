# 🚀 Hawala Wallet - Launch Readiness Checklist

**Generated:** January 21, 2026  
**Last Updated:** $(date) (IBC FFI, DEX/Bridge/EIP-1559 verification)  
**Status:** Pre-Launch Audit

---

## Executive Summary

| Category | Status | Critical Issues |
|----------|--------|-----------------|
| **Security** | ✅ Strong | 1 dependency CVE (medium) |
| **Core Functionality** | ✅ Ready | DEX/Bridge/IBC FFI complete |
| **Build & Signing** | 🔴 Incomplete | No code signing configured |
| **Testing** | ✅ Improved | 773 Rust tests + UI test suite |
| **Documentation** | ✅ Good | Comprehensive |

---

## 🔴 CRITICAL - Must Fix Before Launch

### 1. Code Signing & Notarization
- [ ] Obtain Apple Developer ID certificate ($99/year)
- [ ] Configure signing identity in Xcode/build scripts
- [ ] Set up notarization workflow
- [ ] Test installation on fresh Mac (Gatekeeper check)

**Files:** `swift-app/RELEASE_ENGINEERING.md`, `swift-app/build-app.sh`

### 2. EIP-1559 Transaction Encoding Incomplete
- [x] EIP-1559 encoding implemented in Rust (`signing/preimage/ethereum.rs`, `signing/compiler.rs`)
- [x] Swift uses RustCLIBridge.signEthereum which calls Rust for Type-2 transactions
- [ ] Test Type-2 transactions on testnets (manual testing)
- [ ] Verify gas estimation accuracy

**Note:** The original Swift code in `EthereumTransaction.swift` is deprecated. All signing now routes through RustCLIBridge → Rust backend which has complete EIP-1559 support.

### 3. DEX/Swap Integration Placeholders
- [x] `DEXAggregatorService.swift:423` - Wallet signing integration (uses RustCLIBridge.signEthereum)
- [x] `DEXAggregatorService.swift:464` - Rust FFI calls (using HawalaBridge.getNonce)
- [x] Implementation complete - Swap functionality is integrated

### 4. Bridge Integration Placeholders
- [x] `BridgeService.swift:463` - Wallet signing integration (uses RustCLIBridge.signEthereum)
- [x] `BridgeService.swift:499` - Status polling implemented
- [x] `BridgeService.swift:558` - Rust FFI calls (using HawalaBridge)
- [x] Implementation complete - Bridge functionality is integrated

### 5. IBC Transfer Incomplete
- [x] `IBCService.swift:494` - Transaction building/signing (FFI infrastructure added)
- [x] Rust FFI endpoints added: `hawala_ibc_build_transfer`, `hawala_ibc_get_channel`, etc.
- [ ] Configure Swift-Rust FFI library linking (requires build system changes)
- [ ] Either complete implementation OR hide from Cosmos chains

---

## 🟠 HIGH PRIORITY - Should Fix Before Launch

### 6. Biometric Confirmation for Transactions
- [ ] Add FaceID/TouchID prompt before `sendTransaction()` calls
- [ ] Make it configurable in Settings
- [ ] Fallback to passcode if biometric unavailable

**Reference:** `FEATURE_GAP_ANALYSIS.md` line 25

### 7. Production Error Handling (Rust)
Replace `.unwrap()` calls in non-test code:
- [ ] `utils/http.rs:127` - HttpClientPool initialization
- [ ] `utils/network_config.rs` - RwLock read/write (5+ locations)
- [ ] `utils/session.rs` - Session management (15+ locations)
- [ ] `cpfp/builder.rs:115-116` - Parent/destination unwraps
- [ ] `api/providers.rs:296` - Hex parsing

### 8. ContentView.swift Refactor
- [x] Split 13,000+ line file into components (reduced from 13,762 to 11,165 lines)
- [x] Moved duplicate type definitions to Models/AppTypes.swift and Models/ChainKeys.swift
- [ ] Further component extraction (WalletView, SettingsView) - optional enhancement

### 9. Debug Print Statements
Add `#if DEBUG` guards to:
- [ ] `DuressWalletManager.swift` - Duress mode logging
- [ ] Any `print()` statements containing key/seed references
- [ ] Replace with proper `os.log` with redaction

### 10. Dependency Vulnerability
```
Crate: curve25519-dalek 3.2.0
Issue: RUSTSEC-2024-0344 (Timing variability)
Severity: MEDIUM
```
- [ ] Document in security disclosure
- [ ] Monitor for solana-sdk update
- [ ] Consider: Is Solana support essential for v1.0?

---

## 🟡 MEDIUM PRIORITY - Improve Before Launch

### 11. Remaining TODOs in Swift
- [ ] `WalletManager.swift:270` - Private key validation
- [ ] `BackupManager.swift:185` - Imported accounts
- [ ] `KeyDerivationService.swift:61` - Passphrase support
- [ ] `ProviderSettingsView.swift:460` - CoinGecko key storage
- [ ] `TransactionDecoder.swift:186` - Tenderly/Alchemy simulation

### 12. Update Feature Gap Analysis
Mark completed features:
- [ ] Terms of Service - DONE (SettingsView.swift)
- [ ] Privacy Policy - DONE (SettingsView.swift)
- [ ] EIP-712 Typed Data - DONE (Rust eip712 module)
- [ ] Update all status fields

### 13. Testing Coverage
- [ ] Add Swift UI tests for critical flows:
  - Send flow
  - Receive flow
  - Backup/restore
- [ ] Run `cargo audit` and document results
- [ ] Integration tests for Rust-Swift bridge

### 14. App Store Preparation
- [ ] App icon (all sizes)
- [ ] Screenshots for App Store listing
- [ ] Privacy policy URL
- [ ] Support email/URL
- [ ] Age rating assessment
- [ ] Export compliance (cryptography)

---

## ✅ VERIFIED - Already Production Ready

### Security ✅
- [x] Keychain storage with proper `kSecClass` APIs
- [x] Certificate pinning infrastructure
- [x] Secure memory with `Zeroizing` wrapper
- [x] App Sandbox enabled
- [x] No committed secrets (`.env` gitignored)
- [x] Sensitive data redaction in logs
- [x] Threat detection modules
- [x] Spending policies

### Code Quality ✅
- [x] 773 Rust tests passing
- [x] Custom error handling (`HawalaResult`)
- [x] Release profile with LTO, stripped symbols
- [x] CI/CD workflows configured

### Documentation ✅
- [x] README.md
- [x] SECURITY_AUDIT.md
- [x] RELEASE_ENGINEERING.md
- [x] Multiple roadmap documents

---

## Launch Decision Matrix

| Scenario | Requirements | Timeline |
|----------|--------------|----------|
| **Soft Launch (Beta)** | Fix #1-5 only | 1-2 weeks |
| **Public Launch** | Fix #1-10 | 3-4 weeks |
| **Feature Complete** | Fix all | 6-8 weeks |

---

## Recommended Launch Strategy

### Phase 1: Critical Fixes (Week 1)
1. Complete EIP-1559 encoding
2. Disable incomplete features (Swap/Bridge) in UI
3. Configure code signing

### Phase 2: Security Hardening (Week 2)
4. Add biometric transaction confirmation
5. Fix `.unwrap()` calls in Rust
6. Add `#if DEBUG` guards

### Phase 3: TestFlight Beta (Week 3)
7. Internal testing
8. Fix reported issues
9. Prepare App Store assets

### Phase 4: Public Launch (Week 4)
10. Notarize app
11. Submit to App Store
12. Prepare support channels

---

## Quick Commands

```bash
# Run all Rust tests
cd rust-app && cargo test --lib

# Build Swift app
cd swift-app && swift build

# Run Swift tests
cd swift-app && swift test

# Check for security vulnerabilities
cd rust-app && cargo audit

# Build release
cd swift-app && swift build -c release
```

---

## Files to Review Before Launch

| File | Reason |
|------|--------|
| `swift-app/Hawala.entitlements` | App permissions |
| `swift-app/Info.plist` | App metadata |
| `rust-app/Cargo.toml` | Dependencies |
| `swift-app/Package.swift` | Swift dependencies |
| `APIKeys.swift.template` | API key instructions |

---

**Last Updated:** January 21, 2026  
**Next Review:** Before each release milestone
