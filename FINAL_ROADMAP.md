# Hawala — Final Ship Roadmap (macOS v1 → iOS)

Last updated: 2025‑12‑14

This document turns the full Q&A decisions into an execution plan with clear cut-lines, acceptance criteria, and risk controls.

## 🔒 Locked product decisions (inputs)

### Distribution & platforms
- **macOS first**, then iOS (same product model, same seed/backups, same privacy stance).
- **Direct download** distribution is allowed/desirable.
- **Auto‑update: YES** (must be secure, signed, and revocable).

### Wallet model
- **HD wallet only** for primary accounts:
  - Single seed phrase (BIP39) + optional **BIP39 passphrase**.
  - Multiple accounts/derivation paths under that seed.
- **Imported Accounts** are separate:
  - Import private keys allowed, but treated as “Imported Accounts” (not merged into HD keychain).
- **No iCloud** (v1). **No tracking/analytics** (v1). **No NFTs ever**.
- **Backup/restore**:
  - Standard seed phrase backup.
  - Plus encrypted export/import file: **`.hawala`**.

### Chains (target set)
Target chains from you:
- **Bitcoin (BTC)**
- **Ethereum (ETH)**
- **Solana (SOL)**
- **XRP (Ripple)**
- **BNB on BSC** (EVM)
- **Monero (XMR)** (fully implemented desired, but not a v1 blocker)
- **Cardano (ADA)**
- **Litecoin (LTC)**
- **Cosmos (ATOM)**
- **Polygon (POL / MATIC)**

### Transaction features / “killer” flow
- All supported chains: **send + receive**.
- Priority “killer feature”: **stuck transaction tools**
  - **Bitcoin:** RBF + CPFP
  - **Ethereum/EVM:** speed up / cancel (replacement tx)
- **Testnets: YES** (gated and clearly labeled).

### Privacy & safety
- **Global Privacy Mode: YES**.
- **Duress mode: decoy wallet**.

---

## ✅ Success criteria (what “done” means)

A release is “ship‑ready” when:
1. A new user can create a wallet, backup, restore, and send/receive on at least the v1 chain cut-line.
2. High‑risk actions (sending, exporting keys/seed, turning off privacy, disabling security) have clear confirmations.
3. No secrets are logged; networking errors are user-friendly; app remains responsive.
4. Security features are enabled by default with explicit opt‑outs (where appropriate).
5. Auto‑update is secure, signed, and supports rollback/kill-switch.

---

## 🧭 Milestones

### Milestone 0 — “Stabilize & Measure” (1–2 weeks)
**Goal:** stop unknown regressions, make development repeatable.

Deliverables
- Define **build + test** gates in CI (Swift + Rust if applicable).
- Add basic app diagnostics boundaries:
  - remove noisy provider spam from user-visible logs
  - create structured log levels (debug vs release)
- Introduce a **Provider Health** model for price/RPC dependencies:
  - “degraded mode” UI
  - cached last-good values

Acceptance criteria
- CI runs: build + unit tests on every PR.
- App launches with network disconnected without crashing.

Risks
- Provider instability (403/DNS/rate limiting) will otherwise look like “app is broken”.

---

### Milestone 1 — Wallet Core v1 (HD + Imported Accounts + Backups) (2–4 weeks)
**Goal:** real wallet foundations that won’t change later.

Deliverables
- **Wallet data model** (single source of truth):
  - HD Wallet: seed/passphrase, accounts, per-chain derivation metadata.
  - Imported Accounts: private keys scoped by chain.
  - Deterministic IDs for accounts for sync/indexing.
- **Secure storage contract**:
  - encrypt at rest
  - key material never written to logs
  - clear separation of “in memory” vs “persisted”
- **Backups**:
  - Seed phrase display + confirmation flow
  - `.hawala` encrypted export/import (include versioning + migrations)
  - Restore flows: seed+passphrase, and `.hawala`

Acceptance criteria
- Fresh install → create wallet → backup confirmation required.
- Restore from seed reproduces same addresses.
- `.hawala` export/import round-trips and verifies integrity.

Cut-line
- This milestone must be complete before chain expansion; otherwise every chain multiplies debt.

---

### Milestone 2 — Transaction Engine v1 (BTC + EVM first) (3–6 weeks)
**Goal:** shipping-grade send/receive on the highest priority networks with stuck-tx tools.

#### 2A. Bitcoin sending (includes stuck-tx tools)
Deliverables
- UTXO tracking + fee estimation
- RBF flow (opt in + default policy)
- CPFP flow (child spend UI)
- Coin control (advanced) + “simple send” (beginner)

Acceptance criteria
- Can create/send a tx, and later bump fee via RBF.
- If RBF unavailable, user can create CPFP.

#### 2B. Ethereum / EVM sending (ETH mainnet + BSC + Polygon)
Deliverables
- EVM tx builder: nonce management + EIP‑1559 / legacy support
- “Speed up” / “Cancel” by replacement tx
- Gas estimation + warnings for low gas

Acceptance criteria
- Speed-up replaces pending tx (same nonce, higher gas) reliably.
- Cancel sends 0-value self-tx replacement where valid.

Cut-line (v1)
- v1 can ship with **BTC + ETH + one additional EVM chain** (BSC preferred for your list), *if* the rest are clearly marked “coming soon”.

---

### Milestone 3 — Chain Expansion (SOL + XRP + LTC + ATOM + ADA + Polygon/BSC parity) (4–10 weeks)
**Goal:** broaden chain set without compromising UX/security.

Approach
- Implement per-chain “ChainAdapter” contract:
  - address derivation
  - balance fetch
  - tx history
  - build/sign/send
  - fee estimation
  - explorer links

Recommended order (minimize complexity first)
1) **Litecoin** (closest to BTC model)
2) **Solana** (account model; careful nonce/slot concerns)
3) **XRP** (destination tags, fee model)
4) **Cosmos (ATOM)** (memo, fee/gas)
5) **Cardano** (UTXO but different primitives)
6) **Polygon / BSC parity** polish

Acceptance criteria
- Each chain: send + receive + history, with correct chain-specific warnings.
- Testnet support works and is visually separated.

---

### Milestone 4 — Privacy Mode + Duress Mode (2–4 weeks)
**Goal:** user-controlled privacy that’s real, not cosmetic.

Deliverables
- **Global Privacy Mode**
  - hides balances by default
  - disables screenshots (where applicable)
  - redacts sensitive UI fields
  - optionally pauses price fetching
- **Duress / Decoy Wallet**
  - separate decoy database + separate passcode
  - safe UX: no obvious “this is fake” indicators
  - clear recovery story for the user

Acceptance criteria
- Switching modes does not leak real balances in UI snapshots.
- Decoy cannot access real wallets without real passcode.

---

### Milestone 5 — Monero “Full Implementation” (nice-to-have for v1, goal for v1.x) (time-boxed)
**Goal:** do XMR correctly or don’t claim it.

Deliverables
- Proper key + address derivation path strategy
- Tx construction/signing (ring signatures, etc.)
- Sender/receiver UX, fee selection, sync model

Cut-line
- If Monero cannot be completed with high confidence, ship with Monero **view-only or “disabled”** rather than partial send.

---

### Milestone 6 — Release Engineering (Auto-update, Signing, Notarization) (1–3 weeks)
**Goal:** ship like a real product.

Deliverables
- Code signing + notarization
- Auto-update implementation (secure):
  - signed update feed
  - mandatory signature verification
  - staged rollout + rollback
  - kill-switch if compromised

Acceptance criteria
- App verifies update signature offline before install.
- Rollback path documented.

---

## 🔐 Security program (continuous)

### Defaults
- Biometric / passcode gating for:
  - viewing seed
  - exporting `.hawala`
  - sending above threshold
  - toggling advanced security off

### Threats to explicitly cover
- Address poisoning + clipboard hijacking
- Phishing / lookalike domains
- Replay / nonce reuse
- “Provider lies” (RPC returning bad data)

### Audits
- Pre‑v1: internal security checklist + static scanning + dependency review.
- Post‑v1: pay for third-party audit on sending/signing flows.

---

## 🧪 Testing & quality gates

Minimum required
- Unit tests for:
  - key derivation (deterministic vectors)
  - address formatting
  - fee math and nonce logic
  - backup export/import
- Integration tests (where possible):
  - transaction building fixtures (without broadcasting)
  - provider failover / offline mode

Performance
- Regression guardrails for scrolling and list rendering.

---

## 🧯 Known current risks (from runtime behavior)

These must be handled as product UX, not just “console noise”:
- Provider DNS failures / 403s / rate limits (e.g., Alchemy misconfig).
- Chain providers not enabled for some networks.

Deliverable expectation
- A **Provider Settings** screen and a safe default configuration.
- Error copy that doesn’t scare users (e.g., “Market data temporarily unavailable”).

---

## v1 cut-line recommendation (clear + shippable)

If you want a realistic v1 without slipping forever:
- Ship v1 with **BTC + ETH + BSC + Polygon** (EVM set) + **LTC**.
- Ship **SOL + XRP + ATOM + ADA** as v1.1 in rapid follow-up.
- Ship **XMR send** only when it meets a high bar (or keep it disabled until it does).

This matches your “stuck tx tools” priority and keeps the first release coherent.
