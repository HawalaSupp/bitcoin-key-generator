# ROADMAP-01 — Rust Architecture Unification

**Theme:** Architecture / Security  
**Priority:** P0 (Emergency)  
**Target Outcome:** Signing works reliably on any machine; no hardcoded paths; sandbox-safe

---

## 1) What This Fixes (Mapped to MASTER REVIEW)

- **[Critical] Dual Rust Integration Paths** (Section 3.15) — RustService (FFI) AND RustCLIBridge (Process execution) both exist
- **[Critical] Hardcoded Absolute Paths** (Section 3.15) — RustCLIBridge uses `/Users/x/Desktop/888/rust-app/target/...`
- **[High] Swift/Rust Responsibility Blur** (Section 3.15) — Logic scattered; unclear who owns what
- **Top 10 Failures #2** — Rust CLI Bridge (`Process()` calls)
- **Phase 0 P0-1** — Remove Rust CLI Bridge
- **Phase 0 P0-2** — Fix hardcoded paths
- **Master Changelog** — [Architecture] Dual Rust integration → Remove CLI path, unify on FFI
- **Master Changelog** — [Architecture] Hardcoded absolute paths → Remove or use Bundle.main
- **Edge Case #31** — Rust FFI returns invalid JSON
- **Edge Case #32** — Rust FFI returns null
- **Edge Case #58** — App update breaks binary

---

## 2) User Impact

**Before:**
- App crashes on any machine except developer's
- Signing fails silently with cryptic errors
- Security risk from external process execution
- App Store rejection guaranteed

**After:**
- App works on any Mac
- Signing is fast, reliable, and sandboxed
- Distributable via App Store or notarized DMG
- Clear error messages when crypto operations fail

---

## 3) Scope

**Included:**
- Audit all `RustCLIBridge` call sites
- Migrate all functionality to FFI-based `RustService`
- Delete `RustCLIBridge.swift`
- Update build pipeline to embed Rust as static library
- Add FFI error handling with user-facing messages
- Document Swift/Rust boundary contracts

**Not Included:**
- Adding new Rust features
- Changing signing algorithms
- Multi-wallet architecture (separate roadmap)

---

## 4) Step-by-Step Tasks

### Design Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| D1: Error message mapping | Create user-facing copy for all Rust error codes | Users see "Signing failed. Please try again." not "FFI returned null" | Work with copy team |
| D2: Loading states for Rust ops | Design skeleton/spinner for signing operations | Consistent with app design system | 1-2s max expected |

### Engineering Tasks (Swift)

| Task | Description | Expected Behavior | Implementation Notes |
|:---|:---|:---|:---|
| E1: Audit RustCLIBridge usage | Find all call sites in codebase | List of functions to migrate | `grep -r "RustCLIBridge"` |
| E2: Create FFI equivalents | For each CLI function, ensure RustService has FFI version | All signing/validation via FFI | Coordinate with Rust tasks |
| E3: Migrate call sites | Replace RustCLIBridge calls with RustService | Zero behavior change; tests pass | One call site at a time |
| E4: Add error handling | Wrap FFI calls with proper Result/throws | Graceful degradation; retry options | Use Swift error types |
| E5: Delete RustCLIBridge.swift | Remove file after migration complete | Clean compile; no dead code | Final step |
| E6: Update RustService documentation | Document all FFI function signatures | Clear API contract | Inline + README |

### Engineering Tasks (Rust)

| Task | Description | Expected Behavior | Implementation Notes |
|:---|:---|:---|:---|
| R1: Expose missing FFI functions | Any CLI-only function needs FFI equivalent | All functionality available via FFI | `#[no_mangle] pub extern "C"` |
| R2: Standardize error codes | Create enum of all possible errors | Consistent error handling | Map to Swift errors |
| R3: Add JSON validation | Validate input JSON before processing | Reject malformed input gracefully | serde_json validation |
| R4: Update build script | Build as static library for embedding | `cargo build --release` produces `.a` | Update Makefile |
| R5: Add health check function | `rust_health_check()` returns version/status | Swift can verify Rust is working | Called on app launch |

### QA Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| Q1: Test on fresh Mac | Install on machine without dev tools | App launches; signing works | Use VM or second Mac |
| Q2: Test sandbox mode | Run with App Sandbox enabled | No permission errors | Xcode entitlements |
| Q3: Stress test signing | Sign 100 transactions rapidly | No memory leaks; no crashes | Instruments profiling |
| Q4: Error injection testing | Force Rust errors; verify Swift handling | User sees friendly errors | Mock FFI responses |

---

## 5) Acceptance Criteria

- [ ] `RustCLIBridge.swift` is deleted from codebase
- [ ] Zero references to `Process()` for Rust calls
- [ ] App builds and runs on clean Mac without Rust toolchain
- [ ] All existing tests pass
- [ ] App Sandbox entitlement enabled without errors
- [ ] Signing latency < 100ms for simple transactions
- [ ] Error messages are user-friendly (no "FFI", "null", technical jargon)
- [ ] `rust_health_check()` called on app launch; failure shows alert

---

## 6) Edge Cases & Failure States

| Scenario | Detection | UX Response |
|:---|:---|:---|
| Rust FFI returns null | Guard check in Swift | "Signing engine error. Please restart Hawala." + restart button |
| Rust FFI returns invalid JSON | JSON decode failure | "Unexpected response. Please try again." + retry |
| Rust library missing | Health check fails | "Hawala is corrupted. Please reinstall." |
| Rust version mismatch | Version check on launch | "Update available" or block if critical |
| Memory pressure during signing | Catch allocation failure | "System memory low. Close other apps." |

---

## 7) Analytics / Telemetry

| Event Name | Properties | Success/Failure |
|:---|:---|:---|
| `rust_health_check` | `version`, `status`, `latency_ms` | Success if status=ok |
| `rust_sign_transaction` | `chain`, `tx_type`, `latency_ms`, `error_code` | Success if error_code=none |
| `rust_ffi_error` | `function`, `error_code`, `error_message` | Always failure |
| `rust_recovery_attempted` | `action` (restart/retry) | Success if user continues |

---

## 8) QA Checklist

**Manual Tests:**
- [ ] Fresh install on Mac without Xcode
- [ ] Sign ETH transaction
- [ ] Sign BTC transaction (UTXO)
- [ ] Sign Solana transaction
- [ ] Sign with Touch ID
- [ ] Sign with passcode fallback
- [ ] Force quit during signing; relaunch
- [ ] Verify no hardcoded paths in binary (`strings` check)

**Automated Tests:**
- [ ] Unit tests for RustService wrapper
- [ ] Integration test: generate key → sign tx → verify signature
- [ ] Error handling tests with mock FFI
- [ ] Memory leak test (Instruments)

---

## 9) Effort & Dependencies

**Effort:** L (3-5 days)

**Dependencies:**
- Rust toolchain for development
- Build pipeline update
- No external APIs

**Risks:**
- Some CLI-only functions may be complex to port
- Build pipeline changes may break CI

**Rollout Plan:**
1. Implement FFI equivalents (Day 1-2)
2. Migrate Swift call sites (Day 2-3)
3. Test on clean machine (Day 3-4)
4. Delete RustCLIBridge; final QA (Day 4-5)

---

## 10) Definition of Done

- [ ] RustCLIBridge.swift deleted
- [ ] No `Process()` calls for Rust
- [ ] App runs on clean Mac
- [ ] App Sandbox passes
- [ ] All signing operations work
- [ ] Error messages are user-friendly
- [ ] Documentation updated
- [ ] PR reviewed and merged
