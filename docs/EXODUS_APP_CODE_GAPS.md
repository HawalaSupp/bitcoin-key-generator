# Exodus vs Hawala: App Code Gaps

This file covers features Exodus offers that Hawala does not yet fully deliver inside the product codebase, or features Hawala has only partially implemented and can finish primarily through engineering work.

Scope rules:
- Include only items that are fundamentally app or service code work.
- Exclude staffing, contracts, support operations, legal, and commercial setup.
- Mark each item as `Missing` or `Partial`.

## 1. Browser Extension / Web3 Wallet Surface

Status: `Missing`

Exodus ships a browser-based web3 wallet surface. In this workspace, Hawala has WalletConnect support but no extension target, no extension packaging, and no dedicated extension product surface.

Code work needed:
- Build a browser extension wallet surface for Chrome and Brave.
- Add extension-safe key handling, session approval, account exposure, chain switching, and signing APIs.
- Implement extension onboarding, lock screen, wallet selector, connection approvals, token approvals, and signature review flows.
- Add dApp-origin permission management shared across desktop, extension, and future mobile surfaces.

## 2. Buy / Sell / Fiat On-Ramp / Off-Ramp Integrations

Status: `Partial`

Hawala has buy/sell UI and provider modeling, but quote generation is still simulated in parts of the service layer rather than fully production-backed.

Code work needed:
- Replace simulated quote paths with live provider API integrations.
- Implement quote refresh, expiry handling, provider-specific validation, and error normalization.
- Support full buy and sell execution states, order polling, redirect handling, and recovery after interrupted sessions.
- Add provider capability rules by country, payment method, asset, and network.
- Add analytics and user-visible status tracking for pending, failed, and completed orders.

## 3. Staking Execution

Status: `Partial`

Hawala has staking UI and some validator/stat data, but execution is incomplete. At least one staking path still explicitly throws not implemented.

Code work needed:
- Implement real stake, unstake, redelegate, and reward-claim transaction creation.
- Add validator filtering, slashing-risk presentation, lockup/unbonding timelines, and transaction review.
- Add staking position refresh, reward history, and failure recovery.
- Add chain-by-chain execution coverage instead of data-only support.

## 4. Hardware Wallet Transaction Signing

Status: `Partial`

Hawala detects Ledger and Trezor devices and has UI/scaffolding, but direct signing and transport are not fully shipped.

Code work needed:
- Implement actual Ledger and Trezor transport and APDU/message exchange.
- Add per-chain address fetch, signing, confirmation prompts, and error handling.
- Support hardware-backed send, swap, bridge, message signing, and transaction review.
- Add account discovery, derivation path selection, and reconnect/retry flows.

## 5. Swap Production Hardening

Status: `Partial`

Hawala has a serious DEX abstraction, but it still falls back to mock quote generation when core paths fail.

Code work needed:
- Remove mock-quote fallback from production paths.
- Replace placeholders with fully validated route payloads and signed transaction intents.
- Add provider health scoring, retry logic, slippage/risk warnings, allowance review, and execution tracking.
- Add per-chain liquidity/routing constraints and better quote provenance.

## 6. Bridge Production Hardening

Status: `Partial`

Hawala has a broad bridge abstraction, but it also falls back to mock quote generation during failures.

Code work needed:
- Replace mock bridge quotes with real provider responses only.
- Add source-chain and destination-chain asset validation.
- Add ETA, fee breakdown, bridge risk warnings, and route-specific disclaimers.
- Add bridge status polling, history, stuck-transfer recovery, and refund guidance.

## 7. Token Management End-to-End Wiring

Status: `Partial`

Hawala has a real custom-token manager, but the primary token-management overlay still uses mock display loading in places.

Code work needed:
- Wire token-management UI to live token state instead of mock data.
- Add hide/show, sort, spam filtering, and custom token management against persisted wallet state.
- Add verified token metadata, logo handling, decimals checks, and token list sync.
- Add better error handling for bad contracts, unsupported formats, and missing metadata.

## 8. Broader Network and Asset Parity in Real User Flows

Status: `Partial`

Hawala has large provider and chain ambitions, but actual send and sync coverage in the live app is narrower than the broader ecosystem claims and narrower than Exodus' production breadth.

Code work needed:
- Expand real send, receive, balance, history, fee, and sync coverage across more production-grade chains.
- Make supported assets consistent across wallet creation, balances, sends, swaps, bridges, alerts, and exports.
- Remove gaps where providers claim broad support but the app experience remains limited.
- Add chain-specific test coverage and reliability checks before enabling more assets in the UI.

## 9. Name Resolution Breadth

Status: `Partial`

Hawala has domain-resolution components, but the unified resolver currently treats only `.eth` and `.sol` as supported end-user input formats.

Code work needed:
- Expand the unified name resolver to support more production name systems where appropriate.
- Unify address validation and resolution behavior across send, contacts, QR imports, and history.
- Add reverse resolution, cache invalidation, fallback rules, and warning states for mismatched chain/name combinations.

## 10. WalletConnect Productionization

Status: `Partial`

WalletConnect is meaningfully implemented, but some production-configuration caveats remain.

Code work needed:
- Replace default project IDs and development assumptions with production configuration.
- Add stronger origin trust UX, session risk surfacing, session-scoped permissions, and better failure recovery.
- Add deeper telemetry for failed approvals, rejected methods, disconnects, and session expiry.

## 11. Portfolio, Alerts, and Performance Depth

Status: `Partial`

Hawala has price alerts and portfolio-related surfaces, but the alert universe and consumer-polish depth appear smaller than Exodus' mature portfolio experience.

Code work needed:
- Expand alert coverage beyond a short fixed symbol list.
- Add richer portfolio performance views, allocation breakdowns, and historical PnL where data quality supports it.
- Add per-wallet and all-wallet aggregation, filters, and exportable insights.

## 12. In-App Help, Recovery Guidance, and User Education

Status: `Partial`

Hawala has security-oriented copy and warnings, but not a fully mature in-app education/help system comparable to a polished consumer wallet experience.

Code work needed:
- Add contextual help flows for send, swap, bridge, staking, backups, passkeys, and hardware wallets.
- Add richer failure explanations and guided recovery steps.
- Add searchable in-app help routing and issue-specific support entry points.

## 13. Cross-Surface State Continuity Inside the Product

Status: `Partial`

Hawala has iCloud-backed recovery/passkey-related pieces, but not a fully unified multi-surface product state model.

Code work needed:
- Define consistent state continuity between macOS, extension, and future mobile apps.
- Build secure account sync rules for non-secret state such as watchlists, hidden tokens, preferences, contacts, alert rules, and recent dApps.
- Keep key material and recovery flows separated from convenience sync state.

## Engineering Priority Order

Recommended order if the goal is to close the highest-visibility Exodus gaps:

1. Productionize buy/sell, swap, and bridge paths.
2. Finish hardware wallet signing.
3. Finish staking execution.
4. Ship token management without mock data.
5. Expand network/asset parity in real flows.
6. Build extension wallet surface.
7. Deepen portfolio and alert features.
