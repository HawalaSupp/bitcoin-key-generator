# Exodus vs Hawala: Prioritized Launch Roadmap

This roadmap converts the Exodus comparison into a sequence of work buckets.

Priority definitions:
- `P0`: Must be solved before a serious public launch if you want Hawala to compete credibly with Exodus.
- `P1`: Strong follow-up work that materially improves parity and trust after the launch baseline is solid.
- `P2`: Important expansion work, but not required for the first serious parity milestone.

## P0: Launch-Critical

## 1. Replace Simulated Fiat Flows With Real Integrations

Why this is P0:
- Exodus ships real buy/sell flows.
- Hawala still has simulated quote behavior in parts of its on-ramp stack.
- A polished UI without real provider-backed execution is not competitive.

Outcome required:
- real provider quotes
- real buy/sell state handling
- production credentials and redirect handling
- error recovery and status tracking

Primary areas:
- [OnRampService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/OnRamp/OnRampService.swift#L5)
- [BuySellView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/UI/BuySellView.swift)
- [SellCryptoView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Views/SellCryptoView.swift#L5)

## 2. Remove Mock Quote Fallbacks From Swap and Bridge Core Paths

Why this is P0:
- Hawala already has serious swap and bridge ambition.
- Leaving mock fallback behavior in production-critical flows weakens reliability and trust.

Outcome required:
- real quotes only in production
- deterministic failure handling
- execution tracking and route validation

Primary areas:
- [DEXAggregatorService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/Swap/DEXAggregatorService.swift#L11)
- [BridgeService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/Bridge/BridgeService.swift#L11)
- [SwapBridgeOverlay.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/UI/SwapBridgeOverlay.swift)
- [BridgeView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Views/BridgeView.swift)

## 3. Finish Hardware Wallet Signing

Why this is P0:
- Exodus markets Ledger/Trezor support as a real user-facing capability.
- Hawala currently has discovery and UI, but not fully productized signing transport.

Outcome required:
- successful Ledger/Trezor signing for supported chains
- account discovery
- reconnect and error handling
- review and confirmation UX

Primary areas:
- [HardwareWalletManager.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/HardwareWalletManager.swift#L125)
- [HardwareWalletView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Views/HardwareWalletView.swift)
- [HardwareWalletSigningSheet.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Views/HardwareWallet/HardwareWalletSigningSheet.swift)
- [LedgerWallet.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/HardwareWallet/Ledger/LedgerWallet.swift)
- [TrezorWallet.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/HardwareWallet/Trezor/TrezorWallet.swift)

## 4. Finish Staking Execution, Not Just Staking Data

Why this is P0:
- Exodus markets staking and earning as a complete feature, not just informational UI.
- Hawala still has explicit not-implemented execution paths.

Outcome required:
- stake, unstake, claim, and position management for the launch chains
- validator review and risk surfacing
- transaction creation and post-submit tracking

Primary areas:
- [StakingManager.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/StakingManager.swift#L65)
- [StakingOverlay.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/UI/StakingOverlay.swift)

## 5. Eliminate Mocked Token-Management UX

Why this is P0:
- A wallet competing with Exodus cannot have core asset-management UI backed by mock data.

Outcome required:
- live token state
- persisted hide/show and ordering
- custom token and spam management wired end-to-end

Primary areas:
- [TokensOverlay.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/UI/TokensOverlay.swift#L48)
- [CustomTokenManager.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/CustomTokenManager.swift)

## 6. Tighten Support Scope and Public Claims Before Launch

Why this is P0:
- Exodus competes as a finished consumer product.
- Hawala needs clear scope control so claims only match what is really live.

Outcome required:
- launch matrix for live vs beta vs roadmap
- provider and support setup complete
- public trust pages and help center live

Non-code dependencies:
- provider accounts
- support tooling
- public docs and policy pages

## P1: Strong Parity Builders

## 7. Expand Real Network and Asset Coverage

Why this is P1:
- Hawala has broader provider ambition than its actual live experience.
- Expanding real coverage moves it closer to Exodus breadth.

Outcome required:
- more production-grade chains supported consistently across send, history, sync, fees, and alerts

Primary areas:
- [SendFlowHelper.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Utilities/SendFlowHelper.swift#L1)
- [SyncEngine.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/Sync/SyncEngine.swift#L32)
- [ProviderSettingsView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Views/ProviderSettingsView.swift#L437)

## 8. Deepen Portfolio and Alert Features

Why this is P1:
- Exodus’ portfolio experience is polished and broad.
- Hawala has the building blocks but less depth.

Outcome required:
- broader alert support
- stronger portfolio history and allocation views
- per-wallet and all-wallet reporting

Primary areas:
- [PriceAlertsOverlay.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/UI/PriceAlertsOverlay.swift#L9)
- [NotificationManager.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/NotificationManager.swift)
- [ExportService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/ExportService.swift)

## 9. Expand Name Resolution and Identity UX

Why this is P1:
- Hawala has useful resolution primitives, but the unified experience remains narrow.

Outcome required:
- broader name-service coverage where supported
- consistent resolution across send, receive, contacts, and history

Primary areas:
- [NameResolver.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Utilities/NameResolver.swift#L107)
- [ENSResolver.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/ENSResolver.swift)
- [ChainAddressValidator.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/ChainAddressValidator.swift)

## 10. Productionize WalletConnect Further

Why this is P1:
- Hawala is already solid here, but real consumer polish still matters.

Outcome required:
- stronger project configuration
- better permissions, trust surfacing, and telemetry
- more resilient session lifecycle handling

Primary areas:
- [WalletConnectService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/WalletConnectService.swift#L9)
- [WalletConnectView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Views/WalletConnectView.swift)
- [WalletConnectOverlay.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/UI/WalletConnectOverlay.swift)

## P2: Expansion and Product-Surface Growth

## 11. Build Browser Extension Product

Why this is P2:
- This is one of the biggest parity gaps versus Exodus.
- It is major work, but you can still launch a strong desktop wallet before shipping it.

Outcome required:
- Chrome/Brave extension
- dApp permissions and signing
- extension onboarding, approvals, and session state

Current state:
- no extension target exists in this workspace

## 12. Build Mobile Product

Why this is P2:
- Mobile is strategically critical, but it is effectively a second product program.
- It should not be rushed before core execution reliability is solid.

Outcome required:
- shared architecture extraction
- iPhone-first app
- WalletConnect, alerts, backup, and provider-flow parity

Primary starting points:
- [Package.swift](/Users/x/Desktop/888/swift-app/Package.swift#L14)
- [HawalaMainView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/UI/HawalaMainView.swift#L7)
- [BackupService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/BackupService.swift#L70)

## Recommended Execution Order

1. P0.1 through P0.5 in parallel where feasible.
2. P0.6 before any broad public launch claims.
3. P1.7 through P1.10 once core revenue/security features are real.
4. P2.11 through P2.12 as deliberate product expansion, not launch blockers.
