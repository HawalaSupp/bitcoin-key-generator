# Hawala Production-Ready Master Roadmap

**Created:** May 31, 2026  
**Purpose:** Single engineering source of truth for making Hawala production-ready, secure, and world-class.  
**Principle:** No feature is public until it is real, tested end to end, observable, recoverable, and secure.

---

## 1. Product Definition

Hawala is a native macOS multi-chain cryptocurrency wallet with:

- a Rust wallet core for cryptography, signing, transaction construction, chain logic, security checks, and FFI;
- a SwiftUI app for onboarding, portfolio, send/receive, swaps, bridges, settings, backup, security, and user workflows;
- a JSON-based C FFI bridge between Swift and Rust;
- a long-term ambition to compete with the best self-custody wallets in security, chain coverage, and advanced wallet technology.

The production version must be treated as a financial-security product, not a demo. Every public feature must protect real user funds.

---

## 2. Non-Negotiable Launch Rules

1. **Security over feature count.** If a feature can lose funds, leak keys, mislead users, or produce unrecoverable states, it stays hidden.
2. **No mock-backed production flows.** Mock quote, mock transaction, mock status, and placeholder signing paths are allowed only in tests, previews, or explicitly labeled development mode.
3. **Capability-gated UI.** The app must expose chains and features only through a code-owned capability matrix.
4. **Rust owns signing and transaction correctness.** Swift should orchestrate UX and call hardened Rust APIs for cryptographic operations.
5. **Every transaction has a review model.** Users must see source, destination, chain, amount, fees, allowances, risk, simulation result, and failure modes before signing.
6. **Every network action has recovery behavior.** Failed quote, stuck transaction, dropped broadcast, provider outage, expired session, and partial bridge states need user-visible recovery.
7. **No broad marketing claims until verified.** “40+ chains,” “staking,” “hardware wallet,” “bridge,” “swap,” or “account abstraction” are not public claims until they pass the gates below.

---

## 3. Definition Of Done

For any chain or feature to be production-ready:

- **Implementation:** real provider or protocol path, no mocks, no placeholder transaction data.
- **Security:** threat model reviewed, key material protected, logs redacted, dependency audit clean or risk-accepted.
- **Correctness:** deterministic unit tests, integration tests, failure-path tests, and at least one live testnet or mainnet dry-run where applicable.
- **UX:** clear review screen, clear errors, no hidden irreversible behavior, no misleading copy.
- **Observability:** structured non-sensitive telemetry, provider status, failure categories, crash reporting, and local debug bundles.
- **Release gating:** controlled by capability registry, feature flags, and launch matrix.
- **Documentation:** user-facing help, engineering runbook, known limitations, and support playbook.

---

## 4. Current Reality Summary

The codebase is substantial and promising, but it is pre-production. Rust test targets compile, but the Swift build was inconclusive during inspection because Swift Package Manager stalled inside a dependency checkout. Existing docs disagree with source comments and audits in several areas.

Key realities:

- Rust backend has broad modules and strong foundations.
- Swift app has many real workflows but is large and still mid-refactor.
- DEX, bridge, Lightning, Ordinals, THORChain, IBC, staking, hardware wallet, and some advanced features still contain mock, placeholder, or partial paths.
- The launch claim should be narrower than the repository ambition.
- Security must become a formal release gate, not a best-effort checklist.

---

## 5. Target Launch Scope

### Launch-Ready Candidate Chains

These are the only chains that should be considered for first public release unless later gates prove otherwise:

| Chain | Public Launch Goal | Required Capabilities |
|---|---|---|
| Bitcoin | Yes | generate, restore, receive, balance, history, send, fee estimate, RBF speed-up/cancel, coin control |
| Litecoin | Yes | generate, restore, receive, balance, history, send, fee estimate |
| Ethereum Mainnet | Yes | generate, restore, receive, balance, history, EIP-1559 send, ERC-20, approvals, WalletConnect |
| Solana | Yes, conservative | generate, restore, receive, balance, history, send, SPL tokens |
| XRP | Yes, conservative | generate, restore, receive, balance, history, send, destination tag handling |

### Internal/Test Scope

Polygon, Arbitrum, Optimism, Base, Avalanche, BNB, Cosmos chains, bridges, swaps, staking, ERC-4337, EIP-7702, hardware wallets, Lightning, Ordinals, and cross-chain flows stay internal until their gates are met.

---

## 6. Phase 0: Stabilize The Truth

**Goal:** Stop roadmap drift and make the codebase tell the truth.

Tasks:

- [ ] Create a code-owned `CapabilityRegistry` shared by Swift UI and Rust/FFI responses.
- [ ] Encode launch status per chain: `launch`, `internal`, `testnet`, `hidden`, `deferred`.
- [ ] Encode feature support per chain: receive, send, token balances, history, swap, bridge, stake, WalletConnect, hardware signing, alerts.
- [ ] Hide any UI flow that depends on mocks or placeholders in production builds.
- [ ] Add a build-time `HAWALA_DEVELOPMENT_FEATURES` flag for demo/internal-only features.
- [ ] Update README claims to match the capability registry.
- [ ] Mark existing roadmap documents as historical or superseded by this roadmap.
- [ ] Create an implementation dashboard that lists each feature, owner, status, gate, test status, and risk.

Acceptance criteria:

- The app cannot accidentally show incomplete production flows.
- Marketing copy and README match actual shipped capabilities.
- Each feature has one status, not conflicting statuses across documents.

---

## 7. Phase 1: Build And Release Foundations

**Goal:** Make the project build, test, sign, notarize, and ship repeatably.

Tasks:

- [ ] Fix Swift Package Manager dependency stall around `swift-secp256k1`.
- [ ] Ensure `swift build --package-path swift-app` completes from a clean checkout.
- [ ] Ensure `swift test --package-path swift-app` completes from a clean checkout.
- [ ] Ensure `cargo test --manifest-path rust-app/Cargo.toml` completes cleanly.
- [ ] Add CI jobs for Rust build/test/clippy/fmt/audit.
- [ ] Add CI jobs for Swift build/test/lint where practical.
- [ ] Add a release build script that builds Rust release library, links Swift, signs the app, notarizes it, and creates a distributable artifact.
- [ ] Add reproducible build notes and environment versions.
- [ ] Add crash reporting and non-sensitive diagnostics.
- [ ] Add automated checks that fail production builds if mock-only symbols are used in live flows.

Acceptance criteria:

- A clean machine can build, test, sign, notarize, install, and open Hawala.
- CI is required before merge.
- Release artifacts are traceable to git commits and dependency lockfiles.

---

## 8. Phase 2: Security Hardening Baseline

**Goal:** Make Hawala safe enough to hold real funds in a closed beta.

Tasks:

- [ ] Run `cargo audit`, `cargo deny`, and dependency license checks.
- [ ] Remove, update, or risk-accept vulnerable dependencies with explicit rationale.
- [ ] Run Rust `clippy` with security-relevant lints and fix production panics.
- [ ] Replace production `.unwrap()`, `.expect()`, `fatalError`, and force unwraps where user data, network data, or FFI data is involved.
- [ ] Audit all Swift `print`, Rust logging, and debug output for key, seed, mnemonic, transaction payload, address linkage, and API-token leakage.
- [ ] Verify private keys, mnemonics, seeds, passcodes, and decrypted backup data never enter logs, analytics, crash reports, or screenshots.
- [ ] Add a secrets scanner for commits and CI.
- [ ] Review FFI memory ownership, null handling, malformed JSON handling, and panic boundaries.
- [ ] Wrap Rust FFI entry points with panic guards so Rust panics never unwind across FFI.
- [ ] Add fuzz/property tests for address validation, JSON FFI inputs, transaction decoders, QR decoders, and ABI parsing.
- [ ] Document key lifecycle from entropy to storage to signing to zeroization.
- [ ] Require local authentication before revealing keys, exporting backups, or signing transactions.
- [ ] Add tamper-aware release checks: hardened runtime, entitlements review, app sandbox, notarization, update signature verification.

Acceptance criteria:

- No known high/critical unactioned dependency vulnerabilities.
- No sensitive data in production logs or analytics.
- Malformed FFI input returns safe errors, not crashes.
- Security sign-off is required for beta.

---

## 9. Phase 3: Core Wallet Correctness

**Goal:** Make the basic wallet flows boring, reliable, and recoverable.

Tasks:

- [ ] Finalize BIP-39 wallet creation, restore, optional passphrase, and test vectors.
- [ ] Implement clear backup verification: user must prove recovery phrase before funds are encouraged.
- [ ] Support encrypted local backup export/import with authenticated encryption and versioned format.
- [ ] Support factory wipe and recovery from backup.
- [ ] Make Keychain storage migration-safe across app updates.
- [ ] Add multi-wallet persistence, active wallet switching, labels, and deletion rules.
- [ ] Add watch-only wallet support only if no signing paths are exposed for watch-only accounts.
- [ ] Add private-key import only for chains with proven derivation and address validation.
- [ ] Add deterministic tests for every derivation path and address format in launch scope.
- [ ] Add address validation and normalization per launch chain.
- [ ] Add QR receive and payment request parsing with chain mismatch warnings.

Acceptance criteria:

- A user can create, back up, wipe, restore, and verify the same wallet.
- Imported and generated accounts are clearly distinguished.
- Invalid addresses, wrong chains, and malformed payment requests fail safely.

---

## 10. Phase 4: Launch Chain Completion

**Goal:** Ship a small number of chains fully instead of many chains partially.

### Bitcoin

- [ ] Live balance provider with fallback and cache.
- [ ] Transaction history with confirmations and pending state.
- [ ] UTXO selection, coin control, privacy labels, frozen UTXOs.
- [ ] Fee estimation using mempool data.
- [ ] P2WPKH send and Taproot support only if fully tested.
- [ ] RBF speed-up and cancel for eligible transactions.
- [ ] Dust, change, insufficient funds, replacement fee, and double-spend warnings.

### Litecoin

- [ ] Live balance and history provider.
- [ ] Bech32 receive and send validation.
- [ ] Fee estimation and UTXO selection.
- [ ] Clear limitation handling for RBF if not fully supported.

### Ethereum

- [ ] EIP-1559 transaction construction and signing through Rust.
- [ ] ERC-20 balance and metadata support.
- [ ] ERC-20 transfer support with decimals and contract validation.
- [ ] Token approval review and revoke flow.
- [ ] Nonce tracking, pending tx replacement, cancel, and speed-up.
- [ ] Gas estimation for native, ERC-20, and contract interactions.
- [ ] Block explorer reconciliation after broadcast.

### Solana

- [ ] SOL transfer with blockhash handling.
- [ ] SPL token balances and sends.
- [ ] Rent and account-existence handling.
- [ ] Confirmation tracking and dropped transaction recovery.

### XRP

- [ ] XRP send with destination tag support.
- [ ] Reserve awareness.
- [ ] Trustline visibility if tokens are shown.
- [ ] Clear handling for no-destination-tag exchange warnings.

Acceptance criteria:

- Each launch chain supports create, restore, receive, balance, history, send, fee estimate, broadcast, pending status, and failure recovery.
- Each launch chain has live-provider integration tests or documented manual test scripts.

---

## 11. Phase 5: Transaction Safety Layer

**Goal:** Make signing safe, understandable, and hard to abuse.

Tasks:

- [ ] Build a unified `TransactionReview` model for every send/swap/bridge/dApp request.
- [ ] Show human-readable changes: assets leaving, assets entering, network fees, contract approvals, recipient labels, chain, and account.
- [ ] Add transaction simulation for EVM through a production provider, with fallback states clearly labeled.
- [ ] Decode ERC-20, ERC-721, ERC-1155, Permit, Permit2, Uniswap, bridge, and approval transactions.
- [ ] Add malicious approval warnings for unlimited approvals and unknown spenders.
- [ ] Add address intelligence: contacts, previous interaction, ENS/reverse resolution, blacklist, sanctions/provider warnings where legally appropriate.
- [ ] Add clipboard spoofing detection and chain/address mismatch warnings.
- [ ] Add phishing-domain and WalletConnect origin risk review.
- [ ] Add spending limits, velocity checks, cooldowns, and optional require-passcode-for-large-send.
- [ ] Add duress mode only after a careful abuse and safety review.

Acceptance criteria:

- Users understand what a transaction can do before signing.
- Unknown contracts and unlimited approvals are visually hard to miss.
- High-risk transactions require stronger confirmation.

---

## 12. Phase 6: Swaps And Bridges, Production Only

**Goal:** Ship swaps and bridges only when they are real, quote-backed, signed, tracked, and recoverable.

### Swap Tasks

- [ ] Remove all mock quote fallback from production swap code.
- [ ] Integrate real providers: 0x, 1inch, LI.FI, Socket, or equivalent.
- [ ] Validate token address, decimals, chain, allowance, slippage, price impact, route, and recipient.
- [ ] Add allowance flow and revoke guidance.
- [ ] Add quote expiry, refresh, provider status, and error normalization.
- [ ] Add execution tracking from approval to swap transaction to final settlement.
- [ ] Add MEV/slippage warnings for risky routes.
- [ ] Add minimum received and exact spender address to review.

### Bridge Tasks

- [ ] Remove all mock bridge fallback from production bridge code.
- [ ] Integrate real providers: LI.FI, Socket, Stargate, Wormhole, or equivalent.
- [ ] Validate source chain, destination chain, asset mapping, recipient, route, fees, ETA, and refund behavior.
- [ ] Add stuck-transfer tracking, provider status, explorer links, and support bundle generation.
- [ ] Add bridge risk disclosures per route.
- [ ] Add testnet route tests before mainnet exposure.

Acceptance criteria:

- Swaps and bridges can be completed end to end on supported networks.
- Users can see exactly who receives approval and what route is being used.
- Failed or stuck routes have recovery and support instructions.

---

## 13. Phase 7: WalletConnect And DApp Security

**Goal:** Make dApp interactions safer than competing wallets.

Tasks:

- [ ] Use production WalletConnect project configuration.
- [ ] Persist sessions securely with scoped permissions.
- [ ] Show dApp origin, verified domain, requested chains, requested methods, accounts exposed, and expiry.
- [ ] Add per-session permissions: view address, request signature, request transaction, switch chain.
- [ ] Add one-click disconnect and per-dApp activity history.
- [ ] Decode `personal_sign`, EIP-712, Permit, Permit2, session auth, and transaction requests.
- [ ] Require stronger auth for signing and transaction requests.
- [ ] Add phishing and impersonation warnings for known malicious origins.
- [ ] Add test suite with malicious, malformed, oversized, and ambiguous requests.

Acceptance criteria:

- A malicious dApp cannot trick users with unreadable prompts.
- Users can audit and revoke dApp access.
- WalletConnect failures do not leave broken sessions.

---

## 14. Phase 8: Advanced Security And Recovery

**Goal:** Differentiate Hawala through serious self-custody safety.

Tasks:

- [ ] Social recovery or Shamir backup flow with clear threshold education.
- [ ] Hardware-backed local encryption where available.
- [ ] Optional passphrase wallets with clear warnings.
- [ ] Emergency lockdown: disable dApps, hide balances, block sends, require recovery phrase check.
- [ ] Suspicious activity alerts: new approval, large outgoing transaction, high-risk dApp.
- [ ] Address book with verified labels, anti-poisoning warnings, and first/last-used metadata.
- [ ] Secure export format with versioning, KDF parameters, checksum, and migration plan.
- [ ] Local-only privacy mode: hide fiat values, hide balances, disable analytics.
- [ ] Privacy-preserving analytics defaults and explicit consent.

Acceptance criteria:

- Users have multiple safe recovery options.
- Sensitive actions are authenticated and auditable.
- Privacy-sensitive users can run the app with minimal telemetry.

---

## 15. Phase 9: Cutting-Edge Wallet Capabilities

**Goal:** Become world-class by adding advanced features only after the core is safe.

Candidates:

- [ ] ERC-4337 smart accounts: gas sponsorship, session keys, spending policies, social recovery.
- [ ] EIP-7702 delegated account flows with high-clarity risk review.
- [ ] Passkey-secured smart wallet mode.
- [ ] MPC account option for users who prefer cloud-assisted recovery.
- [ ] Intent-based swaps and cross-chain actions with route simulation.
- [ ] Chain abstraction: one gas account, cross-chain fee payment, safe route planner.
- [ ] Account-level risk score and transaction firewall.
- [ ] AI-assisted transaction explanation that never sees private keys.
- [ ] Hardware wallet deep support: Ledger, Trezor, Keystone/QR, and air-gapped signing.
- [ ] Bitcoin advanced: PSBT workflow, multisig coordinator, descriptors, Miniscript, Lightning only after real node/provider integration.
- [ ] Privacy tools: coin control, address reuse warnings, stealth-address support where practical, Tor only if distribution constraints are solved.

Gating rule:

Each cutting-edge feature must have a threat model, adversarial test cases, feature flags, and a rollback path before public release.

---

## 16. Phase 10: External Audits And Beta

**Goal:** Validate the wallet with people outside the build team before public launch.

Tasks:

- [ ] Internal red-team review.
- [ ] Independent Rust crypto/signing audit.
- [ ] Independent Swift app security review.
- [ ] FFI boundary audit.
- [ ] WalletConnect/dApp phishing review.
- [ ] Dependency and supply-chain audit.
- [ ] Closed beta with test funds first.
- [ ] Closed beta with capped real-fund usage after audit fixes.
- [ ] Bug bounty or responsible disclosure program.
- [ ] Public security page with PGP/contact, scope, and disclosure policy.

Acceptance criteria:

- Critical and high audit findings resolved.
- Medium findings resolved or explicitly accepted.
- Beta users can complete launch-scope flows without support intervention.

---

## 17. Release Gates

### Alpha Gate

- Builds locally.
- Launch chains visible behind internal flags.
- Wallet create/restore/send works on testnets.
- No production-sensitive logging.

### Closed Beta Gate

- Signed and notarized app.
- Launch chains complete.
- Core transaction review complete.
- Dependency audit reviewed.
- Crash reporting and support bundle ready.

### Public Launch Gate

- External audit complete.
- No critical/high security findings open.
- No mock-backed production flow reachable.
- Marketing claims match capability registry.
- Support, docs, incident response, and update system live.

### World-Class Gate

- Smart accounts, passkeys, hardware wallets, swaps, bridges, WalletConnect, recovery, and transaction firewall are all production-grade.
- The app can explain and defend high-risk transactions better than mainstream wallets.
- Reliability metrics prove users can use the wallet without developer assistance.

---

## 18. Immediate Next Sprint

Start here before adding new features:

1. Fix Swift build reproducibility.
2. Implement capability registry and hide incomplete flows.
3. Remove production mock fallbacks or put them behind development flags.
4. Run full Rust and Swift tests from clean checkout.
5. Run dependency/security audits.
6. Create transaction review model.
7. Make launch chain matrix code-owned.
8. Update README to stop overclaiming.

