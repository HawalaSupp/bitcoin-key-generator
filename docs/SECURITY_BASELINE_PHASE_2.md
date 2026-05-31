# Hawala Phase 2 Security Baseline

This document is the Phase 2 security sign-off ledger for closed beta readiness. A feature is not beta-ready unless it passes these gates or has an explicit, dated risk acceptance here.

## Security Gates

- `scripts/security_audit.sh` must pass before merge.
- `scripts/check_production_guards.sh` must pass for every production build.
- `cargo audit` is the blocking RustSec advisory gate; `cargo-deny` enforces license, duplicate dependency, and source policy.
- Rust release builds must keep `panic = "abort"` so panics cannot unwind across the C FFI boundary.
- No production logs, analytics, crash reports, or screenshots may contain private keys, mnemonics, seeds, passcodes, decrypted backups, API tokens, or full transaction payloads.
- Any new RustSec advisory fails the audit unless it is patched or added to this file with a clear owner and removal condition.
- Transitive yanked or unmaintained advisories are warning-only until the owning upstream crate exposes a safe upgrade path; they must be reviewed during dependency refreshes.

## Dependency Audit Results

Initial Phase 2 audit found 13 RustSec vulnerabilities. The patchable findings were reduced by:

- updating `bytes` to `1.11.1`;
- updating `rkyv` and `rkyv_derive` to `0.7.46`;
- updating `time` to `0.3.47`;
- updating the Rustls webpki path through `reqwest` `0.12.x`.

Remaining accepted advisories:

| Advisory | Source | Status | Risk Decision |
|---|---|---|---|
| `RUSTSEC-2022-0093` | Solana SDK transitive `ed25519-dalek` `1.x` | Accepted for Phase 2 only | Direct Hawala Ed25519 dependency uses `2.x`; Solana launch remains conservative and must be re-audited before public beta. |
| `RUSTSEC-2024-0344` | Solana SDK transitive `curve25519-dalek` `3.x` | Accepted for Phase 2 only | Tied to Solana transitive stack; remove by upgrading Solana dependencies or isolating Solana signing before beta. |
| `RUSTSEC-2024-0398` | Direct `sharks` dependency | Accepted for internal-only use | Shamir/social recovery must stay non-launch/internal until the dependency is replaced or cryptographically reviewed. |

No high/critical advisory may be accepted silently. A security owner must review these before closed beta.

## Logging And Diagnostics Policy

- Use redacted, structured diagnostics only.
- Use DEBUG-only logs for local investigation.
- Never log secrets or recovery material, even at debug level.
- Never include raw transaction payloads when they can link accounts, recipients, amounts, or dApp origins.
- Crash reporting must strip Swift `Error.localizedDescription` values if they may include request bodies, provider responses, or user-entered data.

## FFI Boundary Policy

- Public FFI functions return JSON with `success: false` on null input, invalid UTF-8, malformed JSON, and unsupported requests.
- Rust release profile uses `panic = "abort"` to prevent undefined behavior from unwinding across C ABI.
- `rust-app/tests/ffi_safety.rs` covers null and malformed JSON behavior for launch-scope FFI entry points.
- New FFI exports must add malformed-input tests before becoming launch-visible.

## Tamper And Release Checks

- `swift-app/build-app.sh` performs release build, embeds the Rust dylib, signs the app, verifies the signature, and emits a zip plus SHA-256.
- Production notarization requires Developer ID credentials and hardened runtime signing.
- Entitlements must be reviewed before beta. Any new entitlement must include a short purpose and security implication in the release PR.

## Key Lifecycle Reference

See [KEY_LIFECYCLE.md](KEY_LIFECYCLE.md).
