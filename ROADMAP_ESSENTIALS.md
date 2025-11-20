# Hawala Wallet Roadmap: Essentials First

This roadmap captures every feature and polish item required for Hawala to feel complete for an everyday user. It reflects what already works across the Rust backend and Swift UI plus the concrete gaps we still need to close before a public release.

## Current Foundations (✅ already in place)
- Secure, multi-chain key generation via Rust Core (Bitcoin, Ethereum, Litecoin, Solana, XRP, Monero, ERC-20 entry points).
- BIP-39 mnemonic generation/restoration and encrypted key export/import flow.
- Basic onboarding, passcode lock, and manual security notice acknowledgment (`ContentView` + onboarding stack).
- Balance polling infrastructure with cached price display and refresh backoff.
- Initial send flows for Bitcoin, Litecoin, Ethereum, ERC-20, BNB, and Solana plus macOS UI for receive/export/private-key review.

These foundations are working today but still require reliability hardening (retry/backoff, empty-state UX, etc.).

## Essential Feature Matrix (must-have before shipping)
| Area | Current State | Gaps to Close |
| --- | --- | --- |
| **Key Management & Recovery** | Single-session BIP-39 restore, encrypted backups, passcode gate | ✅ Audit derivation paths per chain, add multi-device restore verification, CLI restore tests, confirm Monero/XRP parity |
| **Send & Receive UX** | Send sheets per chain, queued picker logic (latest fix), single-address receive cards | ⚠️ Address validation, error surfaced from backend, pending tx tracking, ability to copy/share multiple receive addresses |
| **Balances & History** | Live balance polling, placeholder history list | ❗ Replace mocks with explorer/RPC history, display confirmations/fees, allow filtering/search |
| **Fee & Gas Controls** | Static estimates inside sheets | ❗ Expose mempool/gas oracles, manual fee sliders, warn on low-fee or stuck tx |
| **Asset/Portfolio Management** | Hardcoded chain list + limited ERC-20 metadata | ⚠️ Automatic token discovery, hide/show per asset, fiat currency toggle, portfolio chart |
| **Security & Privacy** | Passcode, lock/unlock flow, manual clipboard copy | ❗ TouchID/FaceID support, auto-lock timer, clipboard auto-clear, crash-safe sensitive data purge |
| **Reliability & Observability** | Basic logging to `app.log`, manual refresh controls | ⚠️ Structured logging, network health indicators, background balance refresh suspension, crash reporting |
| **Release Readiness** | Makefile + scripts, build/test tasks, documentation stubs | ❗ Signed builds/notarization, onboarding checklist, CI coverage (Rust + Swift), App Store/TestFlight packaging |

## Minimum Lovable Product Backlog
1. **Transaction history & labeling**
   - Hook Bitcoin/Litecoin to Blockstream API, Ethereum/Solana to their RPC providers.
   - Persist per-chain histories, include confirmations and fees, allow user to tap through to explorer.
2. **Robust address & amount validation**
   - Implement checksum + Bech32 validation per chain.
   - Add ENS/SNS lookup stubs for chains that support human-readable names.
3. **Dynamic fees & stuck-transaction tooling**
   - Live mempool fee tiers with recommended choices.
   - Replace-by-fee / speed-up / cancel for BTC & ETH where possible.
4. **Receive-side improvements**
   - Multiple receive addresses per chain, label support, QR codes, share sheets.
   - Unified "copy + share" UX and detection of previously used addresses.
5. **Security polish**
   - TouchID/FaceID gating for sends and private-key reveals.
   - Configurable auto-lock timer and background blur.
   - Clipboard wipe and warning banners for copied secrets.
6. **Portfolio clarity**
   - Fiat currency selector + cached FX rates.
   - Sparkline / chart for total portfolio and per-asset performance.
7. **Reliability fixes**
   - Better offline/slow-network messaging, exponential retry tuning, telemetry for RPC failures.
   - Unit/integration tests for Rust wallet commands (`rust-app/tests/*`) covering edge cases.

## Post-GA Enhancements (future but noted)
- WalletConnect + dApp browser hooks.
- Built-in swaps (1inch/ThorChain) and staking dashboards.
- NFT gallery for ERC-721/1155 and Solana NFTs.
- Notifications center (pending tx mined, price alerts, security reminders).

## Immediate Next Steps
1. Replace mock transaction history with live data and detail panes.
2. Ship universal address validation + QR scanning pipeline.
3. Implement biometric + auto-lock security controls on macOS/iOS targets.
4. Harden send flows with fee customization, stuck-tx detection, and better error surfacing.
