# Exodus vs Hawala: Owner Action Checklist

This file turns the non-code gaps into concrete owner actions. These are things you need to decide, buy, negotiate, configure, publish, or operationalize outside the app source code.

Use this as an execution checklist.

## 1. Buy / Sell / Payment Provider Setup

You need to:
- choose which providers Hawala will actually launch with
- create partner accounts and complete onboarding with providers such as MoonPay, Transak, Ramp, and any others you want active
- obtain production API keys, webhook secrets, referral links, redirect URLs, and dashboard access
- define which countries, fiat currencies, and payment methods you will support at launch
- confirm what happens when a user has a failed purchase, pending payout, or KYC issue

Why this matters:
- the code can only finish the flow once real partner credentials, hosted widget links, and provider access are in place

## 2. WalletConnect Production Credentials

You need to:
- register and secure the production WalletConnect project configuration
- decide allowed origins and environments
- define how you will rotate secrets and respond to abuse or spam session traffic

## 3. Blockchain Data / RPC / Infrastructure Contracts

You need to:
- choose production providers for balances, history, pricing, token metadata, name resolution, swaps, and bridging
- secure paid plans where necessary
- define fallback providers and rate-limit strategy
- maintain an owner-controlled inventory of all provider keys and quotas

## 3A. Phase 2: Swap Routing and DEX Execution Setup

You need to:
- choose the exact swap-routing stack Hawala will trust at launch: internal Rust routing only, external aggregators, or a hybrid
- secure production access for every upstream swap source the Rust routing layer depends on, including API keys, IP allowlists, and rate limits where required
- decide which chains and token pairs are allowed in the public swap surface at launch instead of exposing every theoretical route
- define a hard blocklist for unsupported assets, taxed tokens, illiquid pairs, and chains that still have weak quote or execution reliability
- decide whether approvals default to exact-amount only at launch or whether unlimited approvals are allowed anywhere in the UI
- define swap-provider incident handling: what Hawala shows when a routing backend is down, when a provider is degraded, or when a route becomes unsafe mid-session
- set thresholds for disabling public swap routing during abnormal slippage, stale quotes, or upstream outage conditions
- provide explorer URLs, router addresses, and contract-allowlist ownership so the engineering side is not relying on ad hoc values

Why this matters:
- Phase 2 no longer permits fake swap liquidity. If the routing backend or upstream providers are not production-ready, the app will now fail closed instead of inventing quotes.

## 3B. Phase 3: Bridge Provider and Transfer Operations Setup

You need to:
- choose the exact bridge providers Hawala will trust at launch and define which chain-to-chain corridors are public, beta-only, or disabled
- secure production access for every bridge backend the Rust bridge layer depends on, including provider credentials, RPC capacity, allowlists, and outage contacts where applicable
- publish a bridge corridor allowlist covering supported source chains, destination chains, assets, minimum amounts, and any route-specific restrictions
- define route disable rules for high fees, stale quotes, excessive bridge duration, low liquidity, provider incidents, destination outages, and abnormal failure rates
- decide the manual-recovery policy for stuck transfers, including when Hawala tells users to wait, when support intervenes, and what evidence support requires from the user
- maintain the provider-specific explorer links, bridge dashboard links, router or messenger contract inventories, and operational contacts the team needs during incidents
- define how transfer-status incidents are handled when live tracking is degraded so support and product messaging stay aligned with the app's fail-closed behavior

Why this matters:
- Phase 3 now shows only live bridge routes and no longer simulates transfer progress when provider tracking is unavailable. Launching bridge features safely requires explicit corridor ownership, incident rules, and manual recovery playbooks outside the app code.

## 4. Customer Support Operation

You need to:
- decide whether Hawala will offer email support, chat support, or both
- choose a help desk platform
- create support SLAs and escalation rules
- write the initial help-center content
- define support boundaries for self-custody, provider issues, recovery, and scams

## 5. Public Trust and Website Assets

You need to:
- publish a proper marketing website or trust hub
- publish supported-assets and supported-networks pages
- publish a security page, privacy page, terms, and support page
- publish recovery warnings and scam-prevention guidance
- keep launch claims aligned with what the app actually does today

## 6. Hardware Wallet Readiness

You need to:
- decide which hardware wallets truly launch on day one
- verify any entitlement, USB, signing, packaging, or compatibility requirements
- test actual device models and firmware versions
- prepare support documentation for Ledger and Trezor setup and troubleshooting

## 7. Security Assurance

You need to:
- budget for third-party security review
- commission at least one audit before broader launch
- set up a vulnerability disclosure contact
- decide how you will communicate security fixes and emergency releases

## 8. Analytics, Crash Reporting, and Release Operations

You need to:
- choose analytics and crash-reporting tooling consistent with your privacy posture
- decide what telemetry is acceptable for a self-custody wallet
- set up release versioning, rollback procedures, and post-release monitoring

## 9. Token Metadata Provider Decisions

You need to:
- decide which token metadata providers you trust
- choose verified token lists and spam-filter sources
- define content moderation policy for malicious token metadata

## 10. Extension Strategy

You need to:
- decide whether Hawala will ship a browser extension at all
- choose the first browser targets
- create publisher accounts for browser stores
- plan review, compliance, release notes, and extension support operations

## 11. Mobile Launch Ownership

You need to:
- decide whether iPhone is launch priority before Android
- secure Apple Developer and later Google Play operational readiness
- plan mobile QA hardware coverage, store assets, release cadence, and support ownership

## 12. Legal and Policy Work

You need to:
- get legal review for terms, privacy, disclaimers, and provider relationships
- define wording around self-custody, third-party fiat partners, and supported jurisdictions
- define a policy for sanctions, abuse, fraud, and takedown requests where relevant

## 13. Launch Claims Discipline

You need to:
- align public messaging with what is actually production-ready
- avoid claiming support just because a provider or UI stub exists in the repo
- create a launch matrix that distinguishes live, beta, and roadmap features

## Suggested Owner Order

1. Lock launch scope.
2. Secure provider accounts, keys, and links.
3. Stand up support and trust pages.
4. Fund security review.
5. Decide extension and mobile strategy.
6. Only then broaden public claims.
