# Exodus vs Hawala: Gap-to-Code Map

This file maps the major Exodus parity gaps to the Hawala source files and service areas most likely to require changes.

Reading rules:
- `Primary files` means the first places to inspect and change.
- `Secondary files` means adjacent files likely affected by a complete implementation.
- `New code required` means there is no current obvious implementation surface and new modules or targets will need to be added.

## 1. Fiat Buy / Sell / On-Ramp / Off-Ramp

Gap status: `Partial`

Primary files:
- [OnRampService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/OnRamp/OnRampService.swift#L5)
- [BuySellView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/UI/BuySellView.swift)
- [SellCryptoView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Views/SellCryptoView.swift#L5)

Secondary files:
- [APIKeys.swift.template](/Users/x/Desktop/888/swift-app/APIKeys.swift.template)
- [ProviderSettingsView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Views/ProviderSettingsView.swift)
- [NotificationManager.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/NotificationManager.swift)

Implementation note:
- Replace simulated quotes, expand provider capability rules, and add status recovery after hosted provider redirects.

## 2. Swap Reliability and Production Execution

Gap status: `Partial`

Primary files:
- [DEXAggregatorService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/Swap/DEXAggregatorService.swift#L11)
- [SwapBridgeOverlay.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/UI/SwapBridgeOverlay.swift)

Secondary files:
- [TransactionReviewView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/UI/TransactionReviewView.swift)
- [TokenApprovalManager.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/TokenApprovalManager.swift)
- [SendView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Views/SendView.swift)

Implementation note:
- Remove mock quote fallback and complete the route-to-execution chain with production-safe validation.

## 3. Bridge Reliability and Production Execution

Gap status: `Partial`

Primary files:
- [BridgeService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/Bridge/BridgeService.swift#L11)
- [BridgeView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Views/BridgeView.swift)
- [SwapBridgeOverlay.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/UI/SwapBridgeOverlay.swift)

Secondary files:
- [NotificationManager.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/NotificationManager.swift)
- [TransactionHistoryService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/TransactionHistoryService.swift)

Implementation note:
- Replace mock fallback, add status polling, ETA, route risk, and failed-transfer recovery UX.

## 4. Staking Execution and Position Management

Gap status: `Partial`

Primary files:
- [StakingManager.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/StakingManager.swift#L65)
- [StakingOverlay.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/UI/StakingOverlay.swift)

Secondary files:
- [NotificationManager.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/NotificationManager.swift)
- [ExportService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/ExportService.swift)

Implementation note:
- Build real stake/unstake/claim flows, not just validator and APR data.

## 5. Hardware Wallet Signing

Gap status: `Partial`

Primary files:
- [HardwareWalletManager.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/HardwareWalletManager.swift#L125)
- [HardwareWalletView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Views/HardwareWalletView.swift)
- [HardwareWalletSigningSheet.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Views/HardwareWallet/HardwareWalletSigningSheet.swift)

Secondary files:
- [LedgerWallet.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/HardwareWallet/Ledger/LedgerWallet.swift)
- [TrezorWallet.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/HardwareWallet/Trezor/TrezorWallet.swift)
- [ExternalSigner.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Crypto/ExternalSigner.swift)

Implementation note:
- Finish transport, request framing, signing, account discovery, and chain-specific signing paths.

## 6. Token Management and Asset Curation

Gap status: `Partial`

Primary files:
- [TokensOverlay.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/UI/TokensOverlay.swift#L48)
- [CustomTokenManager.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/CustomTokenManager.swift)

Secondary files:
- [BalanceFetchService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/BalanceFetchService.swift)
- [HawalaAssetDetailView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/UI/HawalaAssetDetailView.swift)

Implementation note:
- Remove mock UI data, wire persisted token state, and complete spam/hide/sort workflows.

## 7. WalletConnect Productionization

Gap status: `Partial`

Primary files:
- [WalletConnectService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/WalletConnectService.swift#L9)
- [WalletConnectView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Views/WalletConnectView.swift)
- [WalletConnectOverlay.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/UI/WalletConnectOverlay.swift)

Secondary files:
- [DAppAccessManager.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/DAppAccessManager.swift)
- [DAppRegistry.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/DAppRegistry.swift)

Implementation note:
- Finish production configuration, permission lifecycle, and stronger trust/risk handling.

## 8. Name Resolution Breadth

Gap status: `Partial`

Primary files:
- [NameResolver.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Utilities/NameResolver.swift#L107)
- [ENSResolver.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/ENSResolver.swift)
- [ChainAddressValidator.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/ChainAddressValidator.swift)

Secondary files:
- [SendView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Views/SendView.swift)
- [ContactsManager.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/ContactsManager.swift)

Implementation note:
- Unify and broaden supported name services across user-facing flows.

## 9. Network / Asset Coverage Expansion

Gap status: `Partial`

Primary files:
- [SendFlowHelper.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Utilities/SendFlowHelper.swift#L1)
- [SyncEngine.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/Sync/SyncEngine.swift#L32)
- [ProviderSettingsView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Views/ProviderSettingsView.swift#L437)

Secondary files:
- [WalletViewModel.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/ViewModels/WalletViewModel.swift)
- [BalanceService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/BalanceService.swift)
- [TransactionHistoryService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/TransactionHistoryService.swift)

Implementation note:
- Expand live chain support consistently instead of exposing uneven support through UI and provider configuration alone.

## 10. Portfolio, Alerts, and Reporting Depth

Gap status: `Partial`

Primary files:
- [PriceAlertsOverlay.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/UI/PriceAlertsOverlay.swift#L9)
- [NotificationManager.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/NotificationManager.swift)
- [ExportService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/ExportService.swift)

Secondary files:
- [NotificationsView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Views/NotificationsView.swift)
- [TransactionHistoryService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/TransactionHistoryService.swift)

Implementation note:
- Expand alert coverage, strengthen reporting, and improve multi-wallet portfolio intelligence.

## 11. Browser Extension Product

Gap status: `Missing`

Current codebase state:
- no obvious browser extension target exists in this workspace

New code required:
- extension target
- extension-safe wallet core
- dApp connection and signing APIs
- approval UI and settings UI

Likely shared logic to extract first:
- [WalletConnectService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/WalletConnectService.swift#L9)
- [DAppAccessManager.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/DAppAccessManager.swift)
- signing services under [swift-app/Sources/swift-app/Crypto](/Users/x/Desktop/888/swift-app/Sources/swift-app/Crypto)

## 12. Mobile Product

Gap status: `Missing`

Primary files to refactor or split:
- [Package.swift](/Users/x/Desktop/888/swift-app/Package.swift#L14)
- [HawalaMainView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/UI/HawalaMainView.swift#L7)
- [ContentView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/ContentView.swift)
- [BackupService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/BackupService.swift#L70)

Desktop-coupled files that will need platform separation:
- [ExportService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/ExportService.swift)
- [ClipboardHelper.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Utilities/ClipboardHelper.swift)
- [QRCodeScanner.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Utilities/QRCodeScanner.swift)
- [OnboardingComponents.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Components/OnboardingComponents.swift)
- [PasskeyAuthView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Views/PasskeyAuthView.swift#L7)
- [PasskeyAuthOverlay.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/UI/PasskeyAuthOverlay.swift#L11)

Likely shared services to preserve:
- [OnRampService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/OnRamp/OnRampService.swift#L5)
- [DEXAggregatorService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/Swap/DEXAggregatorService.swift#L11)
- [BridgeService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/Bridge/BridgeService.swift#L11)
- [StakingManager.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/StakingManager.swift#L65)
- [WalletConnectService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/WalletConnectService.swift#L9)

Implementation note:
- Mobile is not one file change. It requires extracting shared domain logic from macOS-specific UI and AppKit-dependent services.

## 13. In-App Help and Support Guidance

Gap status: `Partial`

Primary files:
- [PersonaManager.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/PersonaManager.swift)
- [UserFriendlyErrors.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Utilities/UserFriendlyErrors.swift)
- [ErrorMessages.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Utilities/ErrorMessages.swift)

Secondary files:
- send, swap, bridge, backup, and onboarding views throughout the app

Implementation note:
- Add contextual help and failure recovery guidance without weakening the self-custody posture.
