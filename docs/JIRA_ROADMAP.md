# HAWALA WALLET — JIRA-READY ROADMAP

**Generated:** January 30, 2026  
**Status:** Pre-Production Remediation Plan  
**Estimated Total Effort:** 8 weeks

---

## 0) RELEASE STAGES + DEFINITION OF DONE

### Internal Dev DoD
- [ ] All P0 tickets closed
- [ ] No `print()` statements leak sensitive data
- [ ] All `.unwrap()` in production code replaced
- [ ] EIP-1559 transactions pass signing test vectors
- [ ] Biometric required before tx broadcast
- [ ] Incomplete features hidden from UI
- [ ] 80%+ Rust test coverage on crypto modules
- [ ] Zero crash in 30-minute smoke test

### Beta DoD (TestFlight/Limited Distribution)
- [ ] All P0 + P1 tickets closed
- [ ] Code signing configured and passing Gatekeeper
- [ ] ContentView.swift split into <500 line components
- [ ] FFI schema versioned with migration support
- [ ] Keys never cross FFI boundary as raw strings
- [ ] TLS pinning enabled for all RPC endpoints
- [ ] Balance/fee caching implemented
- [ ] 10+ beta testers complete full tx flows without crash

### Public Release DoD
- [ ] All P0 + P1 + P2 tickets closed
- [ ] Notarization passes Apple review
- [ ] External security audit completed (or scheduled)
- [ ] All 30+ chains pass address generation test vectors
- [ ] Transaction signing passes known-good vectors for BTC/ETH/SOL
- [ ] App runs 8 hours without memory leak
- [ ] Error messages are user-actionable
- [ ] Documentation complete (README, API docs, troubleshooting)

---

## 1) EPICS

| Epic ID | Name | Description | Owner |
|---------|------|-------------|-------|
| EPIC-SEC | Security Hardening | Fix all security vulnerabilities, key handling, auth | Rust + Swift |
| EPIC-CORRECT | Correctness & Reliability | Fix broken tx encoding, crash risks, edge cases | Rust |
| EPIC-FFI | FFI Bridge Reliability | Schema versioning, validation, error handling | Both |
| EPIC-SWIFT | SwiftUI Refactor | Break up massive files, improve architecture | Swift |
| EPIC-PERF | Performance & Caching | Async HTTP, caching, backoff | Rust + Swift |
| EPIC-TEST | Testing & Verification | Crypto vectors, integration tests, Swift UI tests | Both |
| EPIC-RELEASE | Release Engineering | Code signing, notarization, CI/CD | DevOps |
| EPIC-UX | User Experience | Error messages, hidden features, polish | Swift |

---

## 2) STORIES & TASKS

---

# EPIC-SEC: SECURITY HARDENING

---

## [STORY] SEC-001: Eliminate Debug Logging of Sensitive Data

```
Priority: P0
Severity: Critical
Effort: S
Owner: Both (Swift + Rust)

Description:
Multiple print(), eprintln!(), and debug statements throughout the codebase 
may log private keys, seed phrases, or transaction data to console/crash logs.

Impact/Risk:
- Private keys exposed in crash reports sent to Apple
- Keys visible in Console.app during debugging
- Analytics services may capture stdout

Root Cause:
Development convenience prints left in production code paths.

Proposed Fix (Step-by-step):
1) In Swift: Search for all `print(` statements
   - Add `#if DEBUG` guards around ALL print statements
   - Or replace with os.log with .private redaction

2) In Rust: Search for all `eprintln!`, `println!`, `dbg!`
   - Remove from production code OR wrap in #[cfg(debug_assertions)]
   - Replace with proper logging crate with level filtering

3) Add CI check to prevent new unguarded prints

Files/Modules to inspect/edit:
- swift-app/Sources/swift-app/Views/SendView.swift (lines 1283, 1313, 1636, 1789, etc.)
- swift-app/Sources/swift-app/Services/RustCLIBridge.swift (lines 40-76)
- swift-app/Sources/swift-app/Services/TransactionScheduler.swift
- rust-app/src/bitcoin_wallet.rs (lines 58, 67, 115, 119, 124, 138, 145, 154, 216, 252)
- rust-app/src/litecoin_wallet.rs (lines 40, 68, 104, 127, 135, 194, 228)
- rust-app/src/tx/broadcaster.rs (line 214)
- rust-app/src/main.rs (all println! calls)

Dependencies: None

Acceptance Criteria:
[ ] Zero print/println/eprintln in release builds that contain key/seed/private data
[ ] `grep -r "print(" swift-app/Sources | wc -l` returns 0 outside #if DEBUG
[ ] `grep -rE "println!|eprintln!|dbg!" rust-app/src --include="*.rs" | grep -v test | grep -v "#\[cfg(debug"` returns 0
[ ] Release build console output is empty during normal operation

Verification Steps:
[ ] Build release: `swift build -c release`
[ ] Run app, create wallet, send tx
[ ] Check Console.app for any key material
[ ] Run `log stream --predicate 'subsystem == "com.hawala"'` during tx

Tests to Add/Update:
[ ] CI job: lint-no-debug-prints.sh

Notes / Pitfalls:
- Some prints may be in preview/test code - those are OK
- os.log with .private still logs in debug but redacts in release
```

---

## [TASK] SEC-001-A: Guard Swift Print Statements

```
Priority: P0
Severity: Critical
Effort: S
Owner: Swift

Description:
Wrap all Swift print() statements with #if DEBUG or replace with os.log

Proposed Fix (Step-by-step):
1) Run: grep -rn "print(" swift-app/Sources --include="*.swift" > prints.txt
2) For each line, wrap with:
   #if DEBUG
   print("...")
   #endif
3) For security-sensitive prints, delete entirely
4) For permanent logging, use:
   import os
   private let logger = Logger(subsystem: "com.hawala", category: "SendView")
   logger.debug("Message with \(value, privacy: .private)")

Files/Modules:
- SendView.swift: ~30 print statements
- TransactionSecurityCheckView.swift: 4 prints
- RustCLIBridge.swift: 4 prints
- TransactionScheduler.swift: 7 prints
- TransactionIntentDecoder.swift: 4 prints

Acceptance Criteria:
[ ] All print() wrapped or replaced
[ ] Release build produces no console output

Verification Steps:
[ ] grep -r "print(" swift-app/Sources | grep -v "#if DEBUG" | grep -v "Preview" returns empty
```

---

## [TASK] SEC-001-B: Guard Rust Debug Output

```
Priority: P0
Severity: Critical
Effort: S
Owner: Rust

Description:
Remove or guard all eprintln!/println!/dbg! in non-test Rust code

Proposed Fix (Step-by-step):
1) Search: grep -rn "eprintln!\|println!\|dbg!" rust-app/src --include="*.rs"
2) For each occurrence:
   a) If in test: leave as-is
   b) If debugging only: wrap with #[cfg(debug_assertions)]
   c) If actually needed: use tracing crate with level filtering
3) Add to lib.rs:
   #[cfg(not(debug_assertions))]
   macro_rules! debug_println { ($($arg:tt)*) => {} }
   #[cfg(debug_assertions)]
   macro_rules! debug_println { ($($arg:tt)*) => { eprintln!($($arg)*) } }

Files/Modules:
- bitcoin_wallet.rs: 12 eprintln!
- litecoin_wallet.rs: 8 eprintln!
- tx/broadcaster.rs: 1 eprintln!
- main.rs: 20+ println! (CLI output - OK for CLI, not for lib)

Acceptance Criteria:
[ ] cargo build --release produces no debug output during operation
[ ] All eprintln! outside tests are guarded

Verification Steps:
[ ] Build release, run FFI wallet generation, check stderr is empty
```

---

## [STORY] SEC-002: Add Biometric Confirmation Before Transaction Broadcast

```
Priority: P0
Severity: Critical
Effort: S
Owner: Swift

Description:
Currently, once a user enters amount and taps "Send", the transaction broadcasts
without requiring biometric (Face ID/Touch ID) or passcode confirmation.
This allows anyone with physical access to drain the wallet.

Impact/Risk:
- Stolen/borrowed device = total loss of funds
- Shoulder surfing attacks become fund-draining attacks
- No audit trail of who authorized transaction

Root Cause:
sendTransaction() in SendView.swift directly broadcasts without auth check.

Proposed Fix (Step-by-step):
1) Create BiometricAuthService if not exists
2) Before broadcast in sendTransaction():
   let context = LAContext()
   let reason = "Confirm transaction of \(amount) \(chain) to \(recipient)"
   try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
3) On failure/cancel, abort transaction
4) Make biometric configurable in Settings (but default ON)
5) For Watch-only wallets, skip (they can't sign anyway)

Files/Modules to inspect/edit:
- swift-app/Sources/swift-app/Views/SendView.swift: sendTransaction() ~line 1746
- swift-app/Sources/swift-app/Services/PasscodeManager.swift (if exists)
- Create: BiometricAuthService.swift

Dependencies: None

Acceptance Criteria:
[ ] Every sendTransaction() call is preceded by successful biometric/passcode
[ ] Cancel in biometric prompt aborts transaction
[ ] Setting exists to require biometric (default: ON)
[ ] Fallback to device passcode if biometric unavailable

Verification Steps:
[ ] Initiate send, cancel Face ID → tx does NOT broadcast
[ ] Initiate send, authenticate → tx broadcasts
[ ] Disable Face ID in System Prefs → passcode prompt appears
[ ] With biometric disabled in Settings → still works (user choice)

Tests to Add/Update:
[ ] Unit test: BiometricAuthServiceTests.swift
[ ] UI test: SendFlowUITests - test cancel aborts

Notes / Pitfalls:
- LAContext must be created fresh each time (can't reuse)
- evaluatePolicy is async in iOS 15+
- Don't show biometric for $0 or test transactions
```

---

## [STORY] SEC-003: Keep Private Keys in Rust Only

```
Priority: P1
Severity: High
Effort: L
Owner: Both

Description:
Private keys currently pass through Swift String when crossing FFI boundary.
Swift Strings are immutable, reference-counted, and may persist in memory
indefinitely. Keys should never leave Rust as raw data.

Impact/Risk:
- Keys may remain in Swift heap after use
- Memory dumps could expose keys
- No zeroization control on Swift side

Root Cause:
FFI returns JSON with private_hex, private_wif fields as strings.

Proposed Fix (Step-by-step):
1) Design new FFI architecture:
   - Rust holds keys in SecureBuffer
   - Swift only receives: addresses, public keys, key_handle (opaque ID)
   - Signing operations take key_handle, return signature
   
2) Implement key storage in Rust:
   static KEYS: Lazy<RwLock<HashMap<String, SecureKeyStore>>> = ...
   
3) Modify hawala_generate_wallet():
   - Store keys internally
   - Return only public data + handle
   
4) Modify hawala_sign_transaction():
   - Accept key_handle instead of private_hex
   - Look up key, sign, return signature
   
5) Implement hawala_clear_keys(handle) for logout

6) Update Swift HawalaBridge:
   - Remove all private key fields from response structs
   - Store only handles
   - Pass handle to sign operations

Files/Modules to inspect/edit:
- rust-app/src/ffi.rs: All wallet functions
- rust-app/src/wallet/keygen.rs: Key generation
- NEW: rust-app/src/wallet/keystore.rs: Secure key storage
- swift-app/Sources/swift-app/Services/HawalaBridge.swift: All key types

Dependencies:
- SEC-001 (debug prints) should be done first
- May require FFI-002 (schema versioning) for backwards compat

Acceptance Criteria:
[ ] No struct in Swift contains private_hex or private_wif fields
[ ] grep -r "privateHex\|privateWif\|private_hex\|private_wif" swift-app returns 0
[ ] Keys exist only in Rust RwLock<HashMap>
[ ] Logout clears all keys from Rust store
[ ] Keys zeroized on drop via SecureBuffer

Verification Steps:
[ ] Memory dump Swift process, search for known test private key → not found
[ ] Generate wallet, sign tx, logout → key handle invalid after logout
[ ] Restart app → must restore from Keychain, not memory

Tests to Add/Update:
[ ] Rust: test_key_store_zeroization()
[ ] Rust: test_key_handle_invalid_after_clear()
[ ] Swift: KeyHandleTests.swift

Notes / Pitfalls:
- Major architectural change - do in dedicated sprint
- Need migration path for existing wallets
- Keychain still stores encrypted seed - that's OK
```

---

## [STORY] SEC-004: Implement TLS Certificate Pinning

```
Priority: P1
Severity: High
Effort: M
Owner: Both

Description:
RPC endpoints (mempool.space, blockstream, Alchemy, etc.) are not certificate-pinned.
MITM attacks could intercept balance queries or inject malicious RPC responses.

Impact/Risk:
- Attacker on same network could show fake balances
- Could inject malicious transaction data
- RPC provider compromise goes undetected

Root Cause:
Using default HTTP clients without pinning configuration.

Proposed Fix (Step-by-step):
1) Identify all RPC endpoints used:
   - mempool.space (Bitcoin)
   - blockstream.info (Bitcoin)
   - Alchemy/Infura (Ethereum)
   - Others per chain

2) For Rust (reqwest):
   let cert = Certificate::from_pem(MEMPOOL_CERT)?;
   let client = Client::builder()
       .add_root_certificate(cert)
       .build()?;

3) For Swift (URLSession):
   class PinningDelegate: NSObject, URLSessionDelegate {
       func urlSession(_ session: URLSession, 
                       didReceive challenge: URLAuthenticationChallenge,
                       completionHandler: ...) {
           // Validate against pinned certificate
       }
   }

4) Store certificate hashes in config file
5) Implement fallback: if pinning fails, warn user but allow (with setting)
6) Add certificate rotation mechanism

Files/Modules to inspect/edit:
- rust-app/src/api/providers.rs: HTTP client creation
- rust-app/src/bitcoin_wallet.rs: fetch_utxos client
- swift-app/Sources/swift-app/Services/UnifiedBlockchainProvider.swift
- NEW: rust-app/src/utils/tls_pinning.rs
- NEW: swift-app/Sources/swift-app/Security/CertificatePinning.swift

Dependencies: None

Acceptance Criteria:
[ ] All RPC requests use pinned connections
[ ] MITM proxy (Charles/mitmproxy) causes connection failure
[ ] Invalid certificate → request fails with clear error
[ ] Setting to disable pinning for debugging (OFF by default)

Verification Steps:
[ ] Configure Charles Proxy, try balance fetch → fails
[ ] Remove pinning check, try again → succeeds (proves pinning was active)
[ ] Test each RPC endpoint individually

Tests to Add/Update:
[ ] Integration: test_pinning_rejects_mitm()
[ ] Unit: test_certificate_validation()

Notes / Pitfalls:
- Certificates expire! Need rotation plan
- Some RPC providers use CDN with rotating certs - may need to pin CA instead
- Don't pin Let's Encrypt certs directly (they rotate frequently)
```

---

## [STORY] SEC-005: Persist Security State Across Restarts

```
Priority: P1
Severity: Medium
Effort: M
Owner: Rust

Description:
ThreatDetector blacklist/whitelist and TransactionPolicyEngine limits are in-memory
only. App restart clears all security configuration.

Impact/Risk:
- Blacklisted scam addresses forgotten on restart
- Spending limits reset
- Security posture degrades over time

Root Cause:
Security modules use in-memory HashMap/HashSet with no persistence.

Proposed Fix (Step-by-step):
1) Add persistence layer for security state:
   - Use SQLite via rusqlite
   - Or JSON file in app data directory

2) Modify ThreatDetector:
   pub fn load_state(path: &Path) -> Result<Self>
   pub fn save_state(&self, path: &Path) -> Result<()>
   
3) Modify TransactionPolicyEngine similarly

4) Add FFI functions:
   hawala_load_security_state(path)
   hawala_save_security_state(path)
   
5) Call load on app startup, save on changes

6) Encrypt at rest with app-specific key

Files/Modules to inspect/edit:
- rust-app/src/security/threat_detection.rs: Add persistence
- rust-app/src/security/tx_policy.rs: Add persistence
- rust-app/src/ffi.rs: Add load/save FFI
- swift-app/Sources/swift-app/Services/HawalaBridge.swift: Call on startup

Dependencies:
- Add rusqlite or serde_json to Cargo.toml

Acceptance Criteria:
[ ] Blacklist address, restart app → address still blacklisted
[ ] Set spending limit, restart → limit still enforced
[ ] State file is encrypted at rest
[ ] Corrupted state file → graceful fallback to defaults

Verification Steps:
[ ] Add address to blacklist via FFI
[ ] Force quit app
[ ] Relaunch, query blacklist → address present
[ ] Delete state file, relaunch → empty blacklist (fresh start)

Tests to Add/Update:
[ ] test_security_state_persistence()
[ ] test_corrupted_state_recovery()

Notes / Pitfalls:
- Don't block app launch if state load fails
- Consider state file migration for future versions
```

---

## [STORY] SEC-006: Clear Clipboard After Copy

```
Priority: P2
Severity: Low
Effort: S
Owner: Swift

Description:
When user copies address or seed phrase, it remains in clipboard indefinitely.
Other apps can read clipboard contents.

Impact/Risk:
- Malicious apps can steal copied seed phrases
- Copied addresses may be pasted into wrong context later

Root Cause:
No clipboard clearing mechanism implemented.

Proposed Fix (Step-by-step):
1) Create ClipboardManager service:
   class ClipboardManager {
       static func copyWithExpiry(_ string: String, expiresIn: TimeInterval = 60) {
           NSPasteboard.general.clearContents()
           NSPasteboard.general.setString(string, forType: .string)
           
           DispatchQueue.main.asyncAfter(deadline: .now() + expiresIn) {
               if NSPasteboard.general.string(forType: .string) == string {
                   NSPasteboard.general.clearContents()
               }
           }
       }
   }

2) Replace all NSPasteboard.general.setString calls with ClipboardManager.copyWithExpiry

3) For seed phrases, use shorter expiry (30s) or immediate clear after paste

4) Show toast: "Copied - will clear in 60s"

Files/Modules to inspect/edit:
- NEW: swift-app/Sources/swift-app/Services/ClipboardManager.swift
- swift-app/Sources/swift-app/Views/SeedPhraseViews.swift: Copy button
- swift-app/Sources/swift-app/Views/ReceiveViewModern.swift: Address copy

Dependencies: None

Acceptance Criteria:
[ ] Copied text cleared from clipboard after 60s (configurable)
[ ] Seed phrases cleared after 30s
[ ] User sees notification of auto-clear
[ ] Manual paste within window works

Verification Steps:
[ ] Copy address, wait 60s, paste → empty or different content
[ ] Copy address, paste within 30s → works

Tests to Add/Update:
[ ] ClipboardManagerTests.swift

Notes / Pitfalls:
- Can't guarantee clear if user copies something else first (that's OK)
- macOS clipboard is shared across spaces
```

---

# EPIC-CORRECT: CORRECTNESS & RELIABILITY

---

## [STORY] CORRECT-001: Complete EIP-1559 RLP Encoding

```
Priority: P0
Severity: Critical
Effort: M
Owner: Rust + Swift

Description:
EIP-1559 (Type-2) transaction encoding is incomplete. The Swift code has a TODO
that just concatenates r+s+v, which is NOT valid RLP and will be rejected by nodes.

Impact/Risk:
- ALL Ethereum mainnet transactions may fail
- Users will see "transaction rejected" with no explanation
- Loss of user trust

Root Cause:
EthereumTransaction.swift:178 has TODO instead of proper RLP encoding.

Proposed Fix (Step-by-step):
1) Fix in Rust (preferred - keep crypto in Rust):
   The rust-app/src/ethereum_wallet.rs already uses ethers-core which handles RLP.
   Verify the Rust path is being used, not Swift.

2) If Swift signing is needed, implement proper RLP:
   func encodeEIP1559Transaction() -> Data {
       var encoded = Data([0x02])
       let fields: [RLPEncodable] = [
           chainId, nonce, maxPriorityFeePerGas, maxFeePerGas,
           gasLimit, to, value, data, [], v, r, s
       ]
       encoded.append(RLP.encode(fields))
       return encoded
   }

3) Add RLP encoding utility (or use swift-rlp library)

4) Test against known vectors:
   - EIP-1559 signing vector from eth-tests repo
   - Broadcast to Sepolia testnet

Files/Modules to inspect/edit:
- swift-app/Sources/swift-app/EthereumTransaction.swift: line 178
- rust-app/src/ethereum_wallet.rs: Verify ethers-core usage
- rust-app/src/tx/signer.rs: EVM signing

Dependencies:
- Decide: Swift signing or Rust signing? (Recommend Rust)

Acceptance Criteria:
[ ] EIP-1559 tx broadcasts successfully to Sepolia
[ ] EIP-1559 tx broadcasts successfully to Ethereum mainnet
[ ] Transaction appears in block explorer with correct type (0x2)
[ ] Signing passes test vector

Verification Steps:
[ ] Create Type-2 tx on Sepolia, broadcast → accepted
[ ] View on etherscan → shows as EIP-1559
[ ] Compare raw tx bytes to expected encoding
[ ] Run against ethereum/tests signing vectors

Tests to Add/Update:
[ ] Rust: test_eip1559_signing_vector()
[ ] Rust: test_eip1559_broadcast_sepolia()
[ ] Swift: EthereumTransactionTests.swift

Notes / Pitfalls:
- accessList must be empty array [], not omitted
- v is 0 or 1 for EIP-1559, not 27/28
- chainId must match network
```

---

## [STORY] CORRECT-002: Replace All .unwrap() Calls with Proper Error Handling

```
Priority: P0
Severity: High
Effort: L
Owner: Rust

Description:
50+ .unwrap() calls in production Rust code will panic on unexpected input,
crashing the app and potentially leaving transactions in inconsistent state.

Impact/Risk:
- App crash during transaction = possible fund loss
- Panic in FFI = Swift app terminates
- Poor user experience

Root Cause:
Rapid development prioritized speed over robustness.

Proposed Fix (Step-by-step):
1) Inventory all .unwrap() calls:
   grep -rn "\.unwrap()" rust-app/src --include="*.rs" | grep -v test > unwraps.txt

2) Categorize by risk:
   a) In FFI path: CRITICAL - must fix
   b) In crypto path: CRITICAL - must fix
   c) In RwLock: HIGH - lock poisoning
   d) In tests: OK - leave as-is
   e) Truly infallible: document with expect("reason")

3) For each production .unwrap():
   Replace with:
   - .ok_or(HawalaError::...)? for Option
   - .map_err(|e| HawalaError::...)? for Result
   - .unwrap_or_default() for non-critical with safe default
   - .expect("specific reason why this can't fail") for truly infallible

4) For RwLock .unwrap():
   Replace:
   self.data.read().unwrap()
   With:
   self.data.read().map_err(|_| HawalaError::internal("Lock poisoned"))?

Files/Modules to inspect/edit (50+ locations):
- rust-app/src/api/providers.rs:296 - hex parsing
- rust-app/src/security/threat_detection.rs:250,260,266,272,278,287,296,326,350,375
- rust-app/src/security/tx_policy.rs:172,215,371,406,421,429,435,446,452,458,472,481,495,510,525,540
- rust-app/src/security/key_rotation.rs:166,197,210,222,249,266,272,281,282,346,367,380,412,424,434,454
- rust-app/src/utils/audit.rs:186,187,279,322,331,340,349,358,368,376,381,384
- rust-app/src/utils/security_config.rs:259,264,269,287,295,301,306,311,316,321

Dependencies: None

Acceptance Criteria:
[ ] Zero .unwrap() in production code paths (outside tests)
[ ] All errors propagate with meaningful context
[ ] App doesn't crash on malformed API responses
[ ] Lock poisoning is handled gracefully

Verification Steps:
[ ] grep -rn "\.unwrap()" rust-app/src --include="*.rs" | grep -v test | grep -v expect → 0 results
[ ] Send malformed JSON to FFI → returns error JSON, doesn't crash
[ ] Force lock poison (in test), call function → returns error

Tests to Add/Update:
[ ] test_malformed_input_no_crash()
[ ] test_poisoned_lock_recovery()

Notes / Pitfalls:
- .expect("reason") is OK for truly infallible cases
- Don't just change to .unwrap_or_default() blindly - may hide real errors
- RwLock poisoning means previous holder panicked - state may be corrupt
```

---

## [STORY] CORRECT-003: Enforce Bitcoin Dust Threshold

```
Priority: P1
Severity: Medium
Effort: S
Owner: Rust

Description:
Bitcoin change outputs under 546 satoshis are considered "dust" and will be
rejected by nodes. Current code doesn't enforce this.

Impact/Risk:
- Transactions with tiny change may fail silently
- Nodes may reject "dust" transactions
- User confusion

Root Cause:
No dust check in change output creation.

Proposed Fix (Step-by-step):
1) Define dust constant:
   const DUST_THRESHOLD_SATS: u64 = 546; // P2WPKH dust limit

2) In prepare_transaction() after calculating change:
   let change_amount = total_input_value - target_value - fee;
   if change_amount > 0 && change_amount < DUST_THRESHOLD_SATS {
       fee += change_amount;
       change_amount = 0;
   }

3) Update fee estimation to account for potential dust absorption

4) Document behavior: "Change under 546 sats added to miner fee"

Files/Modules to inspect/edit:
- rust-app/src/bitcoin_wallet.rs: prepare_transaction ~line 175
- rust-app/src/tx/builder.rs: build_bitcoin_transaction
- rust-app/src/litecoin_wallet.rs: Similar change

Dependencies: None

Acceptance Criteria:
[ ] No transaction creates output < 546 sats
[ ] Change < 546 sats absorbed into fee
[ ] Transaction still succeeds when this happens
[ ] User informed if change was absorbed

Verification Steps:
[ ] Send amount that leaves 545 sats change → no change output, higher fee
[ ] Send amount that leaves 547 sats change → change output exists

Tests to Add/Update:
[ ] test_dust_absorbed_into_fee()
[ ] test_above_dust_has_change()

Notes / Pitfalls:
- Dust threshold varies by output type
- Litecoin dust threshold is different
```

---

# EPIC-FFI: FFI BRIDGE RELIABILITY

---

## [STORY] FFI-001: Add FFI Schema Versioning

```
Priority: P1
Severity: High
Effort: M
Owner: Both

Description:
FFI JSON schema has no version field. Breaking changes will crash old Swift
code against new Rust library.

Impact/Risk:
- App updates may break wallet access
- No migration path for schema changes
- Silent data corruption if schemas mismatch

Root Cause:
No versioning strategy implemented.

Proposed Fix (Step-by-step):
1) Add version to all FFI responses:
   {
       "schema_version": "1.0.0",
       "success": true,
       "data": {...}
   }

2) Define schema version constants:
   // Rust
   pub const FFI_SCHEMA_VERSION: &str = "1.0.0";
   
   // Swift
   let FFI_SCHEMA_VERSION = "1.0.0"

3) Swift validates version on every response:
   guard response.schemaVersion.hasPrefix("1.") else {
       throw HawalaError.incompatibleSchema(got: response.schemaVersion, expected: "1.x")
   }

4) Document schema changelog in SCHEMA_CHANGELOG.md

5) Add FFI function: hawala_get_schema_version() -> &str

Files/Modules to inspect/edit:
- rust-app/src/ffi.rs: Add version to all responses
- rust-app/src/types.rs: ApiResponse struct
- swift-app/Sources/swift-app/Services/HawalaBridge.swift: Validate version
- NEW: docs/SCHEMA_CHANGELOG.md

Dependencies: None

Acceptance Criteria:
[ ] All FFI responses include schema_version field
[ ] Swift validates version and shows error for incompatible
[ ] Version mismatch gives clear user message
[ ] Changelog documents all schema changes

Verification Steps:
[ ] Modify schema_version to "2.0.0" in Rust → Swift shows incompatibility error
[ ] Check all FFI responses in debug → all have version

Tests to Add/Update:
[ ] test_schema_version_present()
[ ] test_schema_version_compatibility_check()

Notes / Pitfalls:
- Minor versions (1.1, 1.2) should be backward compatible
- Major version = breaking change
```

---

## [STORY] FFI-002: Add JSON Validation at FFI Boundary

```
Priority: P1
Severity: High
Effort: M
Owner: Both

Description:
FFI layer accepts any JSON without validation. Malformed input can cause
crashes or undefined behavior.

Impact/Risk:
- Malformed JSON → crash
- Missing fields → panic
- Type mismatches → undefined behavior

Root Cause:
serde_json::from_str used without validation.

Proposed Fix (Step-by-step):
1) Add input validation wrapper:
   fn validate_and_parse<T: DeserializeOwned + Validate>(json: &str) -> Result<T, HawalaError> {
       let value: T = serde_json::from_str(json)?;
       value.validate()?;
       Ok(value)
   }

2) Add Validate trait with domain checks:
   trait Validate {
       fn validate(&self) -> Result<(), HawalaError>;
   }
   
   impl Validate for TransactionRequest {
       fn validate(&self) -> Result<(), HawalaError> {
           if self.amount.is_empty() { return Err(...) }
           if self.recipient.is_empty() { return Err(...) }
       }
   }

3) On Swift side, validate before sending to FFI

Files/Modules to inspect/edit:
- rust-app/src/ffi.rs: All FFI entry points
- NEW: rust-app/src/validation.rs: Validate trait and impls
- swift-app/Sources/swift-app/Services/HawalaBridge.swift: Pre-validation

Dependencies: None

Acceptance Criteria:
[ ] Empty JSON returns descriptive error, not crash
[ ] Missing required fields return error with field name
[ ] Invalid types return error with expected type
[ ] All FFI functions protected by validation

Verification Steps:
[ ] Send {} to hawala_prepare_transaction → error "missing field: recipient"
[ ] Send {recipient: ""} → error "recipient cannot be empty"
[ ] Send {amount: "abc"} → error "amount must be numeric"

Tests to Add/Update:
[ ] test_ffi_empty_input()
[ ] test_ffi_missing_fields()
[ ] test_ffi_invalid_types()

Notes / Pitfalls:
- Validation should be fast (no network calls)
- Error messages should not leak sensitive data
```

---

# EPIC-SWIFT: SWIFTUI REFACTOR

---

## [STORY] SWIFT-001: Split ContentView.swift into Components

```
Priority: P1
Severity: High
Effort: L
Owner: Swift

Description:
ContentView.swift is ~13,000 lines. This is unmaintainable, causes slow builds,
makes git merges painful, and SwiftUI previews unusable.

Impact/Risk:
- Any change risks breaking unrelated features
- New developers cannot navigate codebase
- SwiftUI previews time out
- Build times excessive

Root Cause:
Organic growth without refactoring.

Proposed Fix (Step-by-step):
1) Identify logical components (estimate 25-30 new files):
   - WalletDashboardView.swift (~500 lines)
   - WalletListView.swift
   - AssetRowView.swift
   - BalanceSummaryView.swift
   - SendView.swift (already exists but pull more into it)
   - ReceiveView.swift
   - TransactionListView.swift
   - TransactionRowView.swift
   - SettingsView.swift
   - SecuritySettingsView.swift
   - NetworkSettingsView.swift
   - AboutView.swift
   - OnboardingView.swift
   - WalletCreationFlow/
     - WelcomeStepView.swift
     - SecurityStepView.swift
     - PasscodeStepView.swift
     - ReadyStepView.swift
   - Components/
     - CryptoAmountField.swift
     - AddressField.swift
     - ChainPicker.swift
     - LoadingOverlay.swift

2) Create folder structure:
   Views/
     Dashboard/
     Send/
     Receive/
     Transactions/
     Settings/
     Onboarding/
     Components/

3) Move code incrementally:
   - Extract one component at a time
   - Run tests after each extraction
   - Keep ContentView as thin coordinator

4) Use @EnvironmentObject or @Observable for shared state

5) Target: ContentView.swift < 300 lines (just routing)

Files/Modules to inspect/edit:
- swift-app/Sources/swift-app/ContentView.swift: Split into 25+ files
- Create new folder structure under Views/

Dependencies:
- Do after SEC-001 (debug prints) to avoid merge conflicts

Acceptance Criteria:
[ ] ContentView.swift < 300 lines
[ ] Each new file < 500 lines
[ ] All previews load in < 5 seconds
[ ] No functionality regression
[ ] Build time reduced by 30%+

Verification Steps:
[ ] wc -l ContentView.swift → < 300
[ ] All existing UI tests pass
[ ] Manual test all screens
[ ] Check SwiftUI previews work

Tests to Add/Update:
[ ] Ensure existing tests still pass
[ ] Add snapshot tests for new components

Notes / Pitfalls:
- Extract state management carefully
- Use @Binding for child → parent communication
- Consider using a coordinator pattern
- Do in small PRs, not one massive change
```

---

# EPIC-PERF: PERFORMANCE & CACHING

---

## [STORY] PERF-001: Implement Async HTTP in FFI Layer

```
Priority: P1
Severity: High
Effort: M
Owner: Rust

Description:
HTTP calls in FFI use reqwest::blocking, which blocks the FFI thread.
This freezes the Swift UI during network operations.

Impact/Risk:
- UI unresponsive during balance fetch
- User thinks app is frozen
- Watchdog may kill app if blocked too long

Root Cause:
Using blocking HTTP client in synchronous FFI functions.

Proposed Fix (Step-by-step):
1) Option A: Make FFI async-aware (callbacks)
2) Option B: Return immediately with request ID (polling)
3) Option C: Use static tokio runtime with spawn

4) Recommended: Option B with polling
   - Simpler callback handling
   - Swift can show loading state
   - Can cancel pending requests

Files/Modules to inspect/edit:
- rust-app/src/lib.rs: prepare_ethereum_transaction_ffi
- rust-app/src/bitcoin_wallet.rs: fetch_utxos (blocking)
- rust-app/src/api/providers.rs: All HTTP calls
- NEW: rust-app/src/async_ffi.rs: Async request management

Dependencies: None

Acceptance Criteria:
[ ] No UI freeze during network operations
[ ] Balance fetch happens in background
[ ] User sees loading indicator
[ ] Can cancel pending requests on view dismiss

Verification Steps:
[ ] Throttle network to 56k → UI remains responsive
[ ] Start balance fetch, navigate away → no crash
[ ] Time UI responsiveness during fetch → never blocked > 100ms

Tests to Add/Update:
[ ] test_async_fetch_completes()
[ ] test_async_fetch_cancellation()

Notes / Pitfalls:
- Don't create new Runtime per call (expensive)
- Use global static runtime with lazy_static
- Handle task cancellation properly
```

---

## [STORY] PERF-002: Add Balance and Fee Caching

```
Priority: P2
Severity: Medium
Effort: M
Owner: Rust + Swift

Description:
Every balance/fee request hits external APIs. This is slow, uses bandwidth,
and may hit rate limits.

Impact/Risk:
- Slow UI on every view
- Rate limited by RPC providers
- Unnecessary network usage

Root Cause:
No caching layer implemented.

Proposed Fix (Step-by-step):
1) Implement cache in Rust:
   struct CachedValue<T> {
       value: T,
       fetched_at: Instant,
       ttl: Duration,
   }

2) TTL configuration:
   - Balances: 30 seconds
   - Fees: 15 seconds
   - History: 60 seconds

3) Add cache-control to FFI:
   hawala_fetch_balance(input, force_refresh: bool)
   
4) Swift shows cached value immediately, refreshes in background

5) Cache invalidation after sending transaction

Files/Modules to inspect/edit:
- NEW: rust-app/src/cache.rs: Caching logic
- rust-app/src/balances.rs: Use cache
- rust-app/src/fees/estimator.rs: Use cache

Dependencies: None

Acceptance Criteria:
[ ] Second balance fetch within 30s is instant (cached)
[ ] Force refresh bypasses cache
[ ] Cache cleared after send transaction
[ ] Memory usage bounded (LRU or max entries)

Verification Steps:
[ ] Fetch balance → 500ms
[ ] Fetch again → < 5ms (cached)
[ ] Wait 30s, fetch → 500ms (expired)
[ ] Send tx, fetch → 500ms (invalidated)

Tests to Add/Update:
[ ] test_cache_hit()
[ ] test_cache_expiry()
[ ] test_cache_invalidation_after_send()

Notes / Pitfalls:
- Different TTL per chain may be needed
- Don't cache errors
```

---

## [STORY] PERF-003: Implement RPC Retry with Exponential Backoff

```
Priority: P2
Severity: Medium
Effort: M
Owner: Rust

Description:
RPC failures currently fail immediately. No retry logic, no backoff for rate limits,
no circuit breaker for sustained outages.

Impact/Risk:
- Transient failures cause user-visible errors
- Rate limiting causes cascade of failures
- Overloaded provider gets hammered

Root Cause:
No resilience patterns implemented.

Proposed Fix (Step-by-step):
1) Add retry policy:
   struct RetryPolicy {
       max_attempts: u32,
       initial_delay: Duration,
       max_delay: Duration,
       exponential_base: f64,
   }

2) Implement retry logic with exponential backoff

3) Add circuit breaker for sustained failures

4) Mark retryable errors:
   - Network timeout: YES
   - Rate limited (429): YES
   - Server error (5xx): YES
   - Invalid request (4xx): NO
   - Parse error: NO

Files/Modules to inspect/edit:
- NEW: rust-app/src/utils/retry.rs
- NEW: rust-app/src/utils/circuit_breaker.rs
- rust-app/src/api/providers.rs: Use retry wrapper
- rust-app/src/bitcoin_wallet.rs: Use retry for UTXO fetch

Dependencies: None

Acceptance Criteria:
[ ] Transient failure retried up to 3 times
[ ] Backoff doubles each attempt (500ms → 1s → 2s)
[ ] Rate limit (429) backs off longer
[ ] Circuit opens after 5 consecutive failures
[ ] Circuit resets after 30s

Verification Steps:
[ ] Mock RPC to fail once then succeed → succeeds after retry
[ ] Mock RPC to return 429 → backs off appropriately
[ ] Mock RPC to fail 10x → circuit opens, fails fast

Tests to Add/Update:
[ ] test_retry_on_transient_error()
[ ] test_exponential_backoff()
[ ] test_circuit_breaker_opens()
[ ] test_circuit_breaker_resets()

Notes / Pitfalls:
- Don't retry if request already sent and state changed
- Circuit breaker per endpoint, not global
- Log retry attempts for debugging
```

---

# EPIC-TEST: TESTING & VERIFICATION

---

## [STORY] TEST-001: Add Cryptographic Test Vectors

```
Priority: P0
Severity: Critical
Effort: M
Owner: Rust

Description:
No test vectors verify key derivation or transaction signing against known-good
values. Could have subtle bugs in crypto implementations.

Impact/Risk:
- Wrong addresses = funds sent to void
- Wrong signatures = transactions rejected or stolen
- Undetected regression in crypto code

Root Cause:
Tests exist but don't use official test vectors.

Proposed Fix (Step-by-step):
1) Add BIP-39 test vectors
2) Add BIP-32 derivation vectors
3) Add BIP-44 Ethereum derivation vector
4) Add transaction signing vectors
5) Add for all supported chains

Files/Modules to inspect/edit:
- rust-app/tests/crypto_vectors.rs (NEW)
- rust-app/src/wallet/keygen.rs: Ensure deterministic
- Test vectors from official BIP repos

Dependencies: None

Acceptance Criteria:
[ ] BIP-39 mnemonic → seed matches official vectors
[ ] BIP-32 derivation matches official vectors
[ ] Bitcoin address matches for test mnemonic
[ ] Ethereum address matches for test mnemonic
[ ] Solana address matches for test mnemonic
[ ] Transaction signing matches known vectors

Verification Steps:
[ ] cargo test crypto_vectors → all pass
[ ] Compare outputs to other wallet implementations (Electrum, MEW)

Tests to Add/Update:
[ ] rust-app/tests/crypto_vectors.rs: 30+ test cases

Notes / Pitfalls:
- Mnemonic passphrase affects seed - test both empty and non-empty
- Use test vectors from official BIP repos, not made up
```

---

## [STORY] TEST-002: Add Swift UI Tests for Critical Flows

```
Priority: P1
Severity: High
Effort: L
Owner: Swift

Description:
Swift test coverage is minimal. Critical flows (send, receive, backup) have no
automated UI testing.

Impact/Risk:
- Regressions go undetected
- Manual testing required for every release
- User-facing bugs ship

Root Cause:
Focus on Rust testing, Swift tests deprioritized.

Proposed Fix (Step-by-step):
1) Set up XCUITest infrastructure
2) Implement test flows:
   a) Wallet Creation Flow
   b) Send Flow
   c) Receive Flow
   d) Backup/Restore Flow
   e) Settings Flow
3) Use mock FFI responses for deterministic tests
4) Add to CI pipeline

Files/Modules to inspect/edit:
- swift-app/Tests/swift-appTests/: Existing test files
- NEW: swift-app/Tests/swift-appUITests/: UI test target
- NEW: WalletCreationUITests.swift
- NEW: SendFlowUITests.swift
- NEW: ReceiveFlowUITests.swift
- NEW: SettingsUITests.swift

Dependencies:
- Mock FFI layer needed for deterministic tests

Acceptance Criteria:
[ ] 5 critical flow UI tests passing
[ ] Tests run in CI on every PR
[ ] Tests complete in < 5 minutes
[ ] No flaky tests

Verification Steps:
[ ] Run full UI test suite → all pass
[ ] Introduce regression → test fails
[ ] Check CI → tests run on PR

Tests to Add/Update:
[ ] WalletCreationUITests: 10 tests
[ ] SendFlowUITests: 15 tests
[ ] ReceiveFlowUITests: 5 tests
[ ] SettingsUITests: 10 tests

Notes / Pitfalls:
- UI tests are slow - prioritize critical paths
- Use accessibility identifiers for reliable element finding
- Mock network to avoid flakiness
```

---

# EPIC-RELEASE: RELEASE ENGINEERING

---

## [STORY] RELEASE-001: Configure macOS Code Signing

```
Priority: P0
Severity: Critical
Effort: M
Owner: DevOps

Description:
No code signing configured. macOS Gatekeeper will block app installation for
all users.

Impact/Risk:
- App won't launch on any Mac
- Users must disable security (dangerous)
- App Store submission impossible

Root Cause:
No Apple Developer account or signing configuration.

Proposed Fix (Step-by-step):
1) Obtain Apple Developer ID ($99/year)
2) Create Developer ID Application certificate
3) Configure Xcode signing or command-line builds
4) Add to build script
5) Verify signing

Files/Modules to inspect/edit:
- swift-app/build-app.sh: Add signing
- NEW: swift-app/signing-config.sh (for CI)
- .github/workflows/build.yml: Add signing in CI

Dependencies:
- Apple Developer account

Acceptance Criteria:
[ ] App is signed with Developer ID
[ ] spctl --assess returns "accepted"
[ ] App launches on fresh Mac without security warnings
[ ] Keychain access works (entitlements correct)

Verification Steps:
[ ] Build signed app
[ ] Copy to fresh Mac
[ ] Double-click → launches without warning
[ ] Keychain operations work

Tests to Add/Update:
[ ] CI: verify-signature.sh

Notes / Pitfalls:
- Hardened runtime required for notarization
- Entitlements must match app capabilities
- Keep signing identity secure (not in repo)
```

---

## [STORY] RELEASE-002: Configure macOS Notarization

```
Priority: P0 (after signing)
Severity: Critical
Effort: M
Owner: DevOps

Description:
Even signed apps need notarization for macOS 10.15+. Without it, Gatekeeper
shows warning dialog.

Impact/Risk:
- Warning dialog scares users
- Some users can't override warning
- App Store requirement

Root Cause:
Notarization not configured.

Proposed Fix (Step-by-step):
1) Create app-specific password for notarization
2) Create notarization script
3) Verify with stapler
4) Add to CI release workflow

Files/Modules to inspect/edit:
- NEW: scripts/notarize.sh
- .github/workflows/release.yml: Add notarization step

Dependencies:
- RELEASE-001 (code signing) must be complete

Acceptance Criteria:
[ ] App passes notarization
[ ] Ticket stapled to app
[ ] Gatekeeper shows no warnings on fresh Mac

Verification Steps:
[ ] Run notarize.sh → succeeds
[ ] Download on fresh Mac → launches clean
[ ] spctl --assess → "accepted source=Notarized Developer ID"

Tests to Add/Update:
[ ] CI: verify-notarization.sh

Notes / Pitfalls:
- Notarization can take 5-15 minutes
- Failed notarization provides log URL - check it!
- All executables and libraries must be signed
```

---

# EPIC-UX: USER EXPERIENCE

---

## [STORY] UX-001: Hide Incomplete Features from UI

```
Priority: P0
Severity: High
Effort: S
Owner: Swift

Description:
DEX, Bridge, IBC, Lightning, and Ordinals tabs are visible but lead to
placeholder implementations. This destroys user trust.

Impact/Risk:
- Users try feature, it fails
- Support burden for "why doesn't this work"
- Unprofessional appearance

Root Cause:
Features started but not completed, never hidden.

Proposed Fix (Step-by-step):
1) Add feature flags:
   struct FeatureFlags {
       static let dexEnabled = false
       static let bridgeEnabled = false
       static let ibcEnabled = false
       static let lightningEnabled = false
       static let ordinalsEnabled = false
   }

2) Conditionally show tabs/buttons
3) Add internal setting to enable for testing

Files/Modules to inspect/edit:
- swift-app/Sources/swift-app/ContentView.swift: Tab/navigation setup
- NEW: swift-app/Sources/swift-app/Config/FeatureFlags.swift

Dependencies: None

Acceptance Criteria:
[ ] No incomplete features visible in release build
[ ] #if DEBUG allows enabling for testing
[ ] No "dead end" navigation paths

Verification Steps:
[ ] Build release, launch → no Swap/Bridge/Lightning tabs
[ ] All visible features functional

Tests to Add/Update:
[ ] UI test: verify only enabled features visible

Notes / Pitfalls:
- Don't delete the code, just hide it
- Make sure to hide any deep links too
```

---

## [STORY] UX-002: Improve Error Messages

```
Priority: P2
Severity: Medium
Effort: M
Owner: Swift + Rust

Description:
Error messages are generic ("Transaction failed"). Users can't understand what
went wrong or how to fix it.

Impact/Risk:
- User frustration
- Support burden
- Users give up and switch wallets

Root Cause:
Errors not mapped to user-friendly messages.

Proposed Fix (Step-by-step):
1) Create error message catalog
2) Map Rust errors to user messages
3) Add error help button that opens documentation
4) For technical users, show "Details" expandable

Files/Modules to inspect/edit:
- swift-app/Sources/swift-app/Services/HawalaBridge.swift: Error mapping
- NEW: swift-app/Sources/swift-app/Utilities/UserFacingError.swift
- rust-app/src/error.rs: Ensure codes are consistent

Dependencies: None

Acceptance Criteria:
[ ] All common errors have user-friendly messages
[ ] Messages include actionable suggestions
[ ] Technical details available for debugging
[ ] No "unknown error" for known error codes

Verification Steps:
[ ] Trigger insufficient_funds → see friendly message
[ ] Trigger network_error → see retry suggestion
[ ] Trigger unknown error → see fallback message + details

Tests to Add/Update:
[ ] test_error_message_mapping()
[ ] UI test: error states show correct messages

Notes / Pitfalls:
- Don't expose internal details in user messages
- Translate error messages if localizing
```

---

## 3) MASTER DEPENDENCY GRAPH (Critical Path)

```
PHASE 1 (P0 - MUST DO FIRST):
┌─────────────────────────────────────────────────────────────┐
│ SEC-001 (Debug Prints)                                      │
│     ↓                                                       │
│ CORRECT-002 (.unwrap removal) ─────────────────────────────→│
│     ↓                                                       │
│ SEC-002 (Biometric)                                         │
│     ↓                                                       │
│ CORRECT-001 (EIP-1559) ←──── TEST-001 (Crypto Vectors)      │
│     ↓                                                       │
│ UX-001 (Hide Features) ─────────────────────────────────────│
│     ↓                                                       │
│ RELEASE-001 (Code Signing) → RELEASE-002 (Notarization)     │
└─────────────────────────────────────────────────────────────┘

PHASE 2 (P1 - REQUIRED FOR BETA):
┌─────────────────────────────────────────────────────────────┐
│ SWIFT-001 (ContentView Split)                               │
│     ↓                                                       │
│ FFI-001 (Schema Versioning) → FFI-002 (Validation)          │
│     ↓                                                       │
│ SEC-003 (Keys in Rust) ←── FFI changes required             │
│     ↓                                                       │
│ SEC-004 (TLS Pinning)                                       │
│     ↓                                                       │
│ PERF-001 (Async FFI)                                        │
│     ↓                                                       │
│ TEST-002 (Swift UI Tests)                                   │
│     ↓                                                       │
│ SEC-005 (Persist Security State)                            │
└─────────────────────────────────────────────────────────────┘

PHASE 3 (P2 - BEFORE PUBLIC LAUNCH):
┌─────────────────────────────────────────────────────────────┐
│ PERF-002 (Caching)                                          │
│     ↓                                                       │
│ PERF-003 (Retry/Backoff)                                    │
│     ↓                                                       │
│ UX-002 (Error Messages)                                     │
│     ↓                                                       │
│ SEC-006 (Clipboard Clear)                                   │
│     ↓                                                       │
│ CORRECT-003 (Dust Threshold)                                │
└─────────────────────────────────────────────────────────────┘
```

---

## 4) SUGGESTED SPRINT PLAN

### Sprint 1: P0 Critical Fixes (Week 1)

| Day | Focus | Tickets |
|-----|-------|---------|
| 1 | Security Basics | SEC-001-A, SEC-001-B (debug prints) |
| 2 | Crash Prevention | CORRECT-002-A (RwLock), Start CORRECT-002 |
| 3 | Crash Prevention | Finish CORRECT-002 (.unwrap) |
| 4 | Core Correctness | CORRECT-001 (EIP-1559), TEST-001 |
| 5 | Auth & UX | SEC-002 (biometric), UX-001 (hide features) |

**Sprint 1 Goal:** App doesn't crash, doesn't leak keys, core tx works.

### Sprint 2: P1 Beta Quality (Week 2)

| Day | Focus | Tickets |
|-----|-------|---------|
| 1-2 | Architecture | SWIFT-001 (ContentView split) |
| 3 | FFI | FFI-001 (versioning), FFI-002 (validation) |
| 4 | Security | SEC-003 (keys in Rust), SEC-004 (TLS) |
| 5 | Performance | PERF-001 (async FFI) |

**Sprint 2 Goal:** Maintainable codebase, reliable FFI, keys protected.

### Sprint 3: Release Engineering (Week 3)

| Day | Focus | Tickets |
|-----|-------|---------|
| 1 | Signing | RELEASE-001 (code signing) |
| 2 | Notarization | RELEASE-002 (notarization) |
| 3 | Testing | TEST-002 (Swift UI tests) |
| 4 | Persistence | SEC-005 (security state) |
| 5 | Polish | UX-002 (error messages) |

**Sprint 3 Goal:** Distributable, tested, professional.

### Sprint 4: Hardening (Week 4)

| Day | Focus | Tickets |
|-----|-------|---------|
| 1 | Performance | PERF-002 (caching) |
| 2 | Resilience | PERF-003 (retry/backoff) |
| 3 | Edge Cases | CORRECT-003 (dust), SEC-006 (clipboard) |
| 4-5 | QA | Full manual QA, bug fixes |

**Sprint 4 Goal:** Production-ready.

---

## 5) FINAL "TOP 10 MUST-DO FIXES"

1. **SEC-001: Guard all debug prints** - 4 hours, prevents key leaks
2. **CORRECT-001: Fix EIP-1559 encoding** - 2 days, Ethereum is broken without this
3. **CORRECT-002: Replace .unwrap()** - 2 days, prevents crashes
4. **SEC-002: Add biometric before tx** - 4 hours, major security gap
5. **UX-001: Hide incomplete features** - 2 hours, professional appearance
6. **RELEASE-001 + 002: Code signing** - 1 day, required to distribute
7. **SWIFT-001: Split ContentView** - 3 days, maintainability
8. **SEC-003: Keys stay in Rust** - 1 week, defense in depth
9. **TEST-001: Crypto test vectors** - 1 day, proves correctness
10. **FFI-001: Schema versioning** - 1 day, future-proofing

---

*Roadmap generated January 30, 2026. Review and adjust priorities based on team capacity.*
