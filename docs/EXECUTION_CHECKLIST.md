# HAWALA WALLET — EXECUTION CHECKLIST

**Purpose:** Rapid daily reference for development team  
**Last Updated:** January 30, 2026  
**Status:** Pre-Production  

---

## STOP-SHIP GATES 🚫

Before ANY distribution, ALL of these must be complete:

| Gate | Status | Owner | Verified By |
|------|--------|-------|-------------|
| Zero debug prints leak keys | ⬜ | Both | Security |
| All .unwrap() replaced | ⬜ | Rust | Lead |
| EIP-1559 passes test vector | ⬜ | Rust | Lead |
| Biometric required before tx | ⬜ | Swift | Security |
| Incomplete features hidden | ⬜ | Swift | QA |
| Code signing passes Gatekeeper | ⬜ | DevOps | QA |
| App notarized | ⬜ | DevOps | QA |
| 1 hour smoke test no crashes | ⬜ | QA | Lead |

---

## P0 CHECKLIST (Week 1)

### 🔒 Security: Debug Print Removal

**SEC-001-A: Swift Debug Prints**

- [ ] Run: `grep -rn "print(" swift-app/Sources --include="*.swift" | wc -l`
- [ ] Current count: ____
- [ ] Wrap each with `#if DEBUG ... #endif`
- [ ] Priority files:
  - [ ] SendView.swift (~30 prints)
  - [ ] TransactionSecurityCheckView.swift (4 prints)
  - [ ] RustCLIBridge.swift (4 prints)
  - [ ] TransactionScheduler.swift (7 prints)
- [ ] Final check: `grep -r "print(" swift-app/Sources | grep -v "#if DEBUG" | wc -l` = 0
- [ ] Build release, run, check Console.app = empty

**SEC-001-B: Rust Debug Output**

- [ ] Run: `grep -rn "eprintln!\|println!\|dbg!" rust-app/src --include="*.rs" | grep -v test | wc -l`
- [ ] Current count: ____
- [ ] Priority files:
  - [ ] bitcoin_wallet.rs (12 eprintln!)
  - [ ] litecoin_wallet.rs (8 eprintln!)
  - [ ] tx/broadcaster.rs (1 eprintln!)
- [ ] Wrap with `#[cfg(debug_assertions)]` or delete
- [ ] Final check: same grep = 0
- [ ] `cargo build --release`, run FFI, check stderr = empty

---

### 💥 Reliability: Crash Prevention

**CORRECT-002: Replace .unwrap() Calls**

- [ ] Run: `grep -rn "\.unwrap()" rust-app/src --include="*.rs" | grep -v test | wc -l`
- [ ] Current count: ____
- [ ] **RwLock unwraps (Critical):**
  - [ ] threat_detection.rs: lines 250, 260, 266, 272, 278, 287, 296, 326, 350, 375
  - [ ] tx_policy.rs: lines 172, 215, 371, 406, 421, 429, 435, 446, 452, 458, 472, 481, 495, 510, 525, 540
  - [ ] key_rotation.rs: lines 166, 197, 210, 222, 249, 266, 272, 281, 282, 346, 367, 380, 412, 424, 434, 454
  - [ ] audit.rs: lines 186, 187, 279, 322, 331, 340, 349, 358, 368, 376, 381, 384
  - [ ] security_config.rs: lines 259, 264, 269, 287, 295, 301, 306, 311, 316, 321
- [ ] Replace pattern:
  ```rust
  // Before:
  self.data.read().unwrap()
  // After:
  self.data.read().map_err(|_| HawalaError::internal("Lock poisoned"))?
  ```
- [ ] **Hex parsing unwraps:**
  - [ ] providers.rs:296
- [ ] Final check: same grep = 0
- [ ] Test: send malformed JSON to FFI → returns error JSON, no crash

---

### ⚡ Correctness: EIP-1559 Transaction Encoding

**CORRECT-001: Fix EIP-1559**

- [ ] Review: `swift-app/Sources/swift-app/EthereumTransaction.swift:178`
- [ ] Current code has TODO - must implement proper RLP encoding
- [ ] **Decision:** Use Rust signing path or fix Swift?
  - [ ] Option A: Route all ETH signing through Rust (recommended)
  - [ ] Option B: Implement RLP in Swift
- [ ] Add test vector from ethereum/tests repo
- [ ] Test on Sepolia testnet:
  - [ ] Create Type-2 tx
  - [ ] Broadcast
  - [ ] Verify on Sepolia Etherscan shows type=0x2
- [ ] Test on mainnet with small amount ($1)

---

### 🔐 Security: Biometric Authentication

**SEC-002: Biometric Before Transaction**

- [ ] Locate: `swift-app/Sources/swift-app/Views/SendView.swift` → `sendTransaction()`
- [ ] Add before broadcast:
  ```swift
  let context = LAContext()
  let reason = "Confirm transaction of \(amount) \(chain)"
  try await context.evaluatePolicy(
      .deviceOwnerAuthentication, 
      localizedReason: reason
  )
  ```
- [ ] Handle cancel → abort tx
- [ ] Add Setting: "Require authentication for transactions" (default: ON)
- [ ] Test:
  - [ ] Initiate send → Face ID prompt appears
  - [ ] Cancel Face ID → tx NOT broadcast
  - [ ] Authenticate → tx broadcasts
  - [ ] Disable Face ID in System Prefs → passcode prompt appears

---

### 🎭 UX: Hide Incomplete Features

**UX-001: Feature Flags**

- [ ] Create: `swift-app/Sources/swift-app/Config/FeatureFlags.swift`
  ```swift
  struct FeatureFlags {
      static let dexEnabled = false
      static let bridgeEnabled = false
      static let ibcEnabled = false
      static let lightningEnabled = false
      static let ordinalsEnabled = false
  }
  ```
- [ ] Find all tab/navigation items for these features in ContentView.swift
- [ ] Wrap with: `if FeatureFlags.dexEnabled { ... }`
- [ ] Test: Build release → no Swap/Bridge/Lightning visible
- [ ] Verify: All visible features are functional

---

## P1 CHECKLIST (Week 2)

### 📦 Release: Code Signing

**RELEASE-001: macOS Code Signing**

- [ ] Apple Developer account ($99/year) obtained
- [ ] Developer ID Application certificate created
- [ ] Keychain access configured on build machine
- [ ] Update `swift-app/build-app.sh`:
  ```bash
  codesign --deep --force --verify --verbose \
    --sign "Developer ID Application: YOUR NAME (TEAM_ID)" \
    --options runtime \
    --entitlements Hawala.entitlements \
    .build/release/Hawala.app
  ```
- [ ] Test: `spctl --assess --verbose .build/release/Hawala.app` → "accepted"
- [ ] Test: Copy to fresh Mac → launches without warning

**RELEASE-002: macOS Notarization**

- [ ] App-specific password created at appleid.apple.com
- [ ] Create `scripts/notarize.sh`:
  ```bash
  xcrun notarytool submit Hawala.zip \
    --apple-id "$APPLE_ID" \
    --password "$APP_PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait
  xcrun stapler staple Hawala.app
  ```
- [ ] Run notarization → succeeds
- [ ] Verify: `stapler validate Hawala.app`
- [ ] Test: Download on fresh Mac → no Gatekeeper warning

---

### 🏗️ Architecture: Swift Refactor

**SWIFT-001: Split ContentView.swift**

- [ ] Current line count: `wc -l swift-app/Sources/swift-app/ContentView.swift` = ____
- [ ] Target: < 300 lines
- [ ] Create folder structure:
  ```
  Views/
    Dashboard/
      WalletDashboardView.swift
      WalletListView.swift
      AssetRowView.swift
    Send/
      (existing SendView.swift)
    Receive/
      ReceiveView.swift
    Transactions/
      TransactionListView.swift
      TransactionRowView.swift
    Settings/
      SettingsView.swift
      SecuritySettingsView.swift
    Components/
      CryptoAmountField.swift
      AddressField.swift
  ```
- [ ] Extract incrementally (test after each):
  - [ ] WalletDashboardView.swift
  - [ ] WalletListView.swift
  - [ ] AssetRowView.swift
  - [ ] SettingsView.swift
  - [ ] ... continue until ContentView < 300 lines
- [ ] Final: All existing tests pass
- [ ] SwiftUI previews load in < 5 seconds

---

### 🔌 FFI: Schema & Validation

**FFI-001: Schema Versioning**

- [ ] Add to all FFI responses in `rust-app/src/ffi.rs`:
  ```rust
  "schema_version": "1.0.0"
  ```
- [ ] Add constant: `pub const FFI_SCHEMA_VERSION: &str = "1.0.0";`
- [ ] Update `swift-app/Sources/swift-app/Services/HawalaBridge.swift`:
  - [ ] Parse schema_version from all responses
  - [ ] Validate: `version.hasPrefix("1.")` else show error
- [ ] Create: `docs/SCHEMA_CHANGELOG.md`
- [ ] Test: Change version to "2.0.0" → Swift shows incompatibility error

**FFI-002: Input Validation**

- [ ] Create: `rust-app/src/validation.rs`
- [ ] Add Validate trait with domain checks
- [ ] Wrap all FFI entry points with validation
- [ ] Test:
  - [ ] Send `{}` to hawala_prepare_transaction → error "missing field: recipient"
  - [ ] Send `{recipient: ""}` → error "recipient cannot be empty"
  - [ ] No crashes on malformed input

---

### 🔐 Security: Keys in Rust

**SEC-003: Private Keys Stay in Rust**

- [ ] Design: Key handle approach (opaque ID, never raw key)
- [ ] Create: `rust-app/src/wallet/keystore.rs`
  ```rust
  static KEYS: Lazy<RwLock<HashMap<String, SecureKeyStore>>> = ...;
  ```
- [ ] Modify `hawala_generate_wallet()`:
  - [ ] Store keys internally
  - [ ] Return only: address, public_key, key_handle
- [ ] Modify `hawala_sign_transaction()`:
  - [ ] Accept key_handle, not private_hex
  - [ ] Look up key, sign, return signature
- [ ] Add `hawala_clear_keys(handle)` for logout
- [ ] Update Swift HawalaBridge:
  - [ ] Remove all private_hex fields
  - [ ] Store only handles
- [ ] Test: `grep -r "privateHex\|private_hex" swift-app` = 0
- [ ] Test: Memory dump → no raw private keys found

---

### 🔐 Security: TLS Pinning

**SEC-004: Certificate Pinning**

- [ ] Identify RPC endpoints:
  - [ ] mempool.space (Bitcoin)
  - [ ] blockstream.info (Bitcoin)
  - [ ] Alchemy/Infura (Ethereum)
  - [ ] ... others per chain
- [ ] Rust (reqwest):
  ```rust
  let cert = Certificate::from_pem(include_bytes!("certs/mempool.pem"))?;
  let client = Client::builder()
      .add_root_certificate(cert)
      .build()?;
  ```
- [ ] Swift (URLSession): Implement URLSessionDelegate with pinning
- [ ] Create: `rust-app/src/utils/tls_pinning.rs`
- [ ] Create: `swift-app/Sources/swift-app/Security/CertificatePinning.swift`
- [ ] Test: Configure Charles Proxy → connections fail
- [ ] Add setting: "Disable certificate pinning" (DEBUG only)

---

### ⚡ Performance: Async FFI

**PERF-001: Non-blocking HTTP**

- [ ] Choose approach:
  - [ ] Option A: Callbacks
  - [ ] Option B: Polling (recommended)
  - [ ] Option C: Static tokio runtime
- [ ] Implement async request management
- [ ] Update Swift to show loading state during fetch
- [ ] Test: Throttle network to 56k → UI remains responsive
- [ ] Test: Balance fetch in background → can navigate

---

## P2 CHECKLIST (Week 3-4)

### 🔐 Security: State Persistence

**SEC-005: Persist Security State**

- [ ] Add persistence layer (SQLite or JSON file)
- [ ] Modify ThreatDetector: `load_state()`, `save_state()`
- [ ] Modify TransactionPolicyEngine similarly
- [ ] Add FFI: `hawala_load_security_state(path)`
- [ ] Call load on app startup, save on changes
- [ ] Test: Blacklist address → restart → still blacklisted

---

### ⚡ Performance: Caching & Resilience

**PERF-002: Balance/Fee Caching**

- [ ] Create: `rust-app/src/cache.rs`
- [ ] TTL configuration:
  - [ ] Balances: 30 seconds
  - [ ] Fees: 15 seconds
  - [ ] History: 60 seconds
- [ ] Add cache-control to FFI: `force_refresh: bool`
- [ ] Invalidate cache after send transaction
- [ ] Test: Second balance fetch within 30s = instant

**PERF-003: Retry with Backoff**

- [ ] Create: `rust-app/src/utils/retry.rs`
- [ ] Create: `rust-app/src/utils/circuit_breaker.rs`
- [ ] Implement exponential backoff (500ms → 1s → 2s)
- [ ] Circuit opens after 5 consecutive failures
- [ ] Test: Mock RPC fail once → succeeds after retry

---

### 🧪 Testing

**TEST-001: Crypto Test Vectors**

- [ ] Create: `rust-app/tests/crypto_vectors.rs`
- [ ] Add BIP-39 mnemonic → seed vectors
- [ ] Add BIP-32 derivation vectors
- [ ] Add Bitcoin address derivation vector
- [ ] Add Ethereum address derivation vector
- [ ] Add Solana address derivation vector
- [ ] `cargo test crypto_vectors` → all pass

**TEST-002: Swift UI Tests**

- [ ] Create: `swift-app/Tests/swift-appUITests/`
- [ ] Add tests:
  - [ ] WalletCreationUITests.swift
  - [ ] SendFlowUITests.swift
  - [ ] ReceiveFlowUITests.swift
  - [ ] SettingsUITests.swift
- [ ] All tests pass in CI
- [ ] Tests complete in < 5 minutes

---

### 🎭 UX: Error Messages

**UX-002: User-Friendly Errors**

- [ ] Create: `swift-app/Sources/swift-app/Utilities/UserFacingError.swift`
- [ ] Map Rust error codes to friendly messages
- [ ] Add "Details" expandable for technical info
- [ ] Test:
  - [ ] insufficient_funds → "Not enough funds..."
  - [ ] network_error → "Network issue. Check connection..."

---

### 🔒 Security: Clipboard

**SEC-006: Clear Clipboard After Copy**

- [ ] Create: `swift-app/Sources/swift-app/Services/ClipboardManager.swift`
- [ ] Implement: `copyWithExpiry(_ string: String, expiresIn: TimeInterval = 60)`
- [ ] Replace all `NSPasteboard.general.setString` calls
- [ ] Seed phrases: 30s expiry
- [ ] Addresses: 60s expiry
- [ ] Test: Copy address → wait 60s → paste empty

---

### ⚡ Correctness: Edge Cases

**CORRECT-003: Bitcoin Dust Threshold**

- [ ] Define: `const DUST_THRESHOLD_SATS: u64 = 546;`
- [ ] In `prepare_transaction()`:
  ```rust
  if change_amount > 0 && change_amount < DUST_THRESHOLD_SATS {
      fee += change_amount;
      change_amount = 0;
  }
  ```
- [ ] Test: Send amount leaving 545 sats change → no change output

---

## FINAL RELEASE CHECKLIST 🚀

### Pre-Release

- [ ] All P0 tickets closed
- [ ] All P1 tickets closed
- [ ] All P2 tickets closed (or documented as known issues)
- [ ] Full regression test passed
- [ ] Security self-audit completed
- [ ] Performance benchmarks met

### Build & Sign

- [ ] Clean build: `swift build -c release`
- [ ] Code signed: `codesign --verify` passes
- [ ] Notarized: `stapler validate` passes
- [ ] DMG/ZIP packaged
- [ ] Checksums generated (SHA256)

### Distribution

- [ ] Website download page updated
- [ ] GitHub release created
- [ ] Release notes written
- [ ] Changelog updated
- [ ] Social announcement drafted

### Post-Release

- [ ] Monitor crash reports (24 hours)
- [ ] Check support channels
- [ ] Hotfix process ready if needed

---

## QUICK REFERENCE COMMANDS

### Grep Commands

```bash
# Count debug prints (Swift)
grep -rn "print(" swift-app/Sources --include="*.swift" | grep -v "#if DEBUG" | wc -l

# Count debug prints (Rust)
grep -rn "eprintln!\|println!\|dbg!" rust-app/src --include="*.rs" | grep -v test | wc -l

# Count .unwrap() calls
grep -rn "\.unwrap()" rust-app/src --include="*.rs" | grep -v test | wc -l

# Find private key references in Swift
grep -rn "privateHex\|privateWif\|private_hex\|private_wif" swift-app/Sources

# Line count of ContentView
wc -l swift-app/Sources/swift-app/ContentView.swift
```

### Build Commands

```bash
# Build Rust release
cargo build --manifest-path rust-app/Cargo.toml --release

# Build Swift release
cd swift-app && swift build -c release

# Run Rust tests
cargo test --manifest-path rust-app/Cargo.toml

# Run Swift tests
cd swift-app && swift test

# Run all tests
make test-all
```

### Code Signing

```bash
# Verify signature
spctl --assess --verbose .build/release/Hawala.app

# Check code signature details
codesign -dv --verbose=4 .build/release/Hawala.app

# Verify notarization
xcrun stapler validate Hawala.app
```

### Launch App (Correct Way)

```bash
# ALWAYS use this to launch the app:
cd /Users/x/Desktop/888/swift-app && swift run swift-app

# NEVER use:
# open Hawala.app (loads cached version)
```

---

*Checklist generated January 30, 2026. Check items as completed. Review daily in standup.*
