# Exodus vs Hawala: App Code Implementation Roadmap

This roadmap is the execution plan derived from [EXODUS_APP_CODE_GAPS.md](/Users/x/Desktop/888/docs/EXODUS_APP_CODE_GAPS.md). It is written as the document to follow when fixing the remaining code-side gaps.

Guiding rules:
- Do not add non-fungible asset support.
- Do not broaden public claims until the implementation and validation items for a phase are complete.
- Finish one vertical slice end-to-end before enabling it broadly in the UI.
- Prefer production-safe failure behavior over feature breadth.

Delivery model:
- `Phase`: major workstream.
- `Goal`: what must be true when the phase ends.
- `Tasks`: concrete engineering tasks.
- `Implementation ideas`: suggested design choices.
- `Definition of done`: the release bar.
- `Validation`: how to verify the work.

## Phase 0: Scope Lock and Cleanup

Goal:
- Freeze the code roadmap around the fungible-asset wallet product.

Tasks:
- Remove all non-fungible-asset roadmap references from Hawala planning docs.
- Review token-management code and UI copy for any user-facing unsupported-asset promises.
- Define the launch asset classes explicitly: coins, fungible tokens, staking assets, bridged assets, WalletConnect-connected assets.
- Create a single source of truth for launch-supported chains and supported features per chain.

Implementation ideas:
- Add a supported-capabilities matrix owned in code and docs.
- Use one table for each chain: send, receive, history, swap, bridge, staking, WalletConnect, alerts, export.

Definition of done:
- No internal roadmap conflicts around unsupported asset classes.
- One agreed capability matrix exists and is referenced by product and engineering.

Validation:
- Search docs for unsupported-asset references and remove any new ones before each milestone.

## Phase 1: Fiat / Buy / Sell Productionization

Goal:
- Turn buy and sell from UI-driven demos into real provider-backed user flows.

Primary files:
- [OnRampService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/OnRamp/OnRampService.swift#L5)
- [BuySellView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/UI/BuySellView.swift)
- [SellCryptoView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Views/SellCryptoView.swift#L5)

Tasks:
- Replace simulated quote methods with provider-specific live API clients.
- Normalize quote models so every provider returns the same app-level fields.
- Add quote timestamps and expiry timestamps.
- Add country, fiat, asset, and payment-method eligibility checks before request submission.
- Add a provider failure taxonomy: network, KYC required, blocked country, unsupported asset, expired quote, redirect cancelled, payout pending.
- Add persistent order state so the app can recover after relaunch.
- Add user-visible order history for buy/sell attempts.
- Add webhook or polling reconciliation entry points if providers support them.

Implementation ideas:
- Introduce a provider adapter protocol with `fetchQuote`, `buildCheckoutURL`, `parseCallbackState`, and `refreshOrderStatus`.
- Use a normalized `FiatOrder` model persisted locally with provider ID, status, asset, chain, amount, quote ID, created time, and last refresh time.
- Build a provider capability cache refreshed daily so the UI does not offer unsupported combinations.

Definition of done:
- At least one buy provider and one sell-capable provider work end-to-end in production mode.
- Interrupted sessions recover cleanly after app restart.
- Errors are actionable and provider-specific.

Validation:
- Run happy-path tests for buy and sell.
- Simulate provider timeout, expired quote, cancelled redirect, and pending payout.
- Verify unsupported countries and unsupported asset combinations are blocked before checkout.

## Phase 2: Swap Reliability and Execution Hardening

Goal:
- Make swap execution trustworthy and remove mock behavior from core paths.

Primary files:
- [DEXAggregatorService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/Swap/DEXAggregatorService.swift#L11)
- [SwapBridgeOverlay.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/UI/SwapBridgeOverlay.swift)
- [TransactionReviewView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/UI/TransactionReviewView.swift)
- [TokenApprovalManager.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/TokenApprovalManager.swift)

Tasks:
- Remove mock quote fallback from production builds.
- Separate quote discovery from execution intent building.
- Validate every route for chain, token decimals, minimum amount, slippage, allowance requirements, and deadline.
- Add approval review that clearly shows spender, approval amount, and revocation advice.
- Add route provenance fields so the UI can show which provider and path produced the result.
- Persist in-flight swap attempts and final outcomes.
- Add failure classification: approval failed, slippage exceeded, route expired, RPC failed, nonce issue, broadcast failed, receipt failed.

Implementation ideas:
- Create a `SwapExecutionPlan` model generated only after quote validation passes.
- Make UI consume `quote confidence`, `route source`, `expected output`, `minimum output`, `approval needed`, and `risk notes`.
- Gate provider fallback behind explicit provider health logic rather than silent fake data.

Definition of done:
- No mock quotes are shown in the shipped app.
- A user can approve and execute a swap with clear preflight and post-submit state.
- Failed swaps leave a traceable record with a user-readable reason.

Validation:
- Test exact-in and max-slippage edge cases.
- Test allowance-required and allowance-not-required paths.
- Test route expiry and replacement quote prompts.

## Phase 3: Bridge Reliability and Transfer Tracking

Goal:
- Make bridge flows production-safe with clear status and failure recovery.

Primary files:
- [BridgeService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/Bridge/BridgeService.swift#L11)
- [BridgeView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Views/BridgeView.swift)
- [SwapBridgeOverlay.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/UI/SwapBridgeOverlay.swift)

Tasks:
- Remove mock bridge quote fallback from production paths.
- Validate source chain, destination chain, token compatibility, recipient rules, fees, and ETA before execution.
- Add a bridge transaction state model with source tx hash, provider transfer ID, destination completion status, and failure reason.
- Add stuck-transfer handling and manual refresh.
- Add provider-specific warnings for finality time, bridge trust assumptions, and refund limitations.
- Add bridge history and receipt detail views.

Implementation ideas:
- Create a `BridgeTransferRecord` persisted locally with lifecycle stages.
- Add a background status refresh loop for active bridge transfers.
- Keep bridge review stricter than swap review because there are two chains and longer settlement uncertainty.

Definition of done:
- Users see real quotes, real status, and a clear path from initiation to completion.
- Stuck bridges are visible and diagnosable.

Validation:
- Test source success plus delayed destination settlement.
- Test destination failure or timeout states.
- Test invalid source/destination combinations in UI and service layer.

## Phase 4: Hardware Wallet Signing Completion

Goal:
- Make Ledger and Trezor support real and usable.

Primary files:
- [HardwareWalletManager.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/HardwareWalletManager.swift#L125)
- [LedgerWallet.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/HardwareWallet/Ledger/LedgerWallet.swift)
- [TrezorWallet.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/HardwareWallet/Trezor/TrezorWallet.swift)
- [HardwareWalletSigningSheet.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Views/HardwareWallet/HardwareWalletSigningSheet.swift)

Tasks:
- Implement the actual transport for device communication.
- Add per-chain address retrieval and verification on device.
- Add account discovery across supported derivation paths.
- Implement signing for launch chains only, not theoretical all-chain support.
- Add explicit mismatch detection when the device app, chain, or derivation path is wrong.
- Add reconnect, timeout, and user-cancel handling.

Implementation ideas:
- Build one transport layer, then one chain adapter per supported signing family.
- Start with a small support matrix: EVM, Bitcoin-like, Solana, XRP only if device and code paths are reliable.
- Expose a `HardwareSigningCapability` check before presenting hardware actions in the UI.

Definition of done:
- Device connection, address verification, and signing work end-to-end for the launch chains.
- Errors are explicit and do not strand the user in half-finished flows.

Validation:
- Test unplug/replug during signing.
- Test wrong app open on the hardware wallet.
- Test derivation path mismatch and address mismatch.

## Phase 5: Staking Execution Completion

Goal:
- Turn staking from data display into actual transaction-capable functionality.

Primary files:
- [StakingManager.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/StakingManager.swift#L65)
- [StakingOverlay.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/UI/StakingOverlay.swift)

Tasks:
- Implement real stake transaction builders for the selected launch chains.
- Add unstake and reward-claim flows.
- Track staking positions, reward accrual, lockup periods, and unbonding windows.
- Add validator details: commission, uptime, warning flags, and selection criteria.
- Add staking transaction review and post-submit state tracking.

Implementation ideas:
- Launch with one fully reliable staking chain first, then expand.
- Reuse the existing transaction review safety pattern for staking confirmation.

Definition of done:
- A user can stake, view the stake, and later unstake or claim rewards on at least one chain without leaving Hawala.

Validation:
- Test amount validation, validator selection, reward updates, and cooldown handling.
- Test partial failures where the data fetch works but the transaction builder fails.

## Phase 6: Token Management End-to-End Wiring

Goal:
- Replace mock token-management behavior with real persisted wallet state.

Primary files:
- [TokensOverlay.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/UI/TokensOverlay.swift#L48)
- [CustomTokenManager.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/CustomTokenManager.swift)
- [BalanceFetchService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/BalanceFetchService.swift)

Tasks:
- Remove `loadMockData()` from the token-management path.
- Persist hide/show state, order, and custom token additions per wallet.
- Add verified metadata and contract validation before accepting custom tokens.
- Add safer spam filtering for fungible tokens.
- Add reconciliation between fetched balances and user-hidden assets.

Implementation ideas:
- Introduce a wallet-scoped token preference store.
- Keep token metadata separate from token balances so metadata can be refreshed without mutating balance state.
- Treat unsupported contracts as rejected, not partially added.

Definition of done:
- The overlay reflects real wallet data and user actions persist correctly.
- No mock token records appear in the live flow.

Validation:
- Test add custom token, hide token, unhide token, reorder token, and bad contract entry.
- Test behavior across multiple wallets.

## Phase 7: Broader Network and Asset Coverage

Goal:
- Close the gap between broad provider claims and the actual in-app supported experience.

Primary files:
- [SendFlowHelper.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Utilities/SendFlowHelper.swift#L1)
- [SyncEngine.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/Sync/SyncEngine.swift#L32)
- [ProviderSettingsView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Views/ProviderSettingsView.swift#L437)
- [WalletViewModel.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/ViewModels/WalletViewModel.swift)

Tasks:
- Define the exact launch set of chains with all supported capabilities.
- For each new chain, implement balance, history, fee, send, receive, sync, and export support before marking it as generally supported.
- Remove or relabel chains that appear in config but are not fully usable.
- Add per-chain test cases and service health checks.

Implementation ideas:
- Maintain a single `ChainCapabilityRegistry` consumed by UI and services.
- Use capability-driven UI gating instead of static string checks spread across the codebase.

Definition of done:
- Every visible supported chain has a consistent, working minimum feature set.

Validation:
- Regression test each chain across wallet creation/import, send, receive, history, and fees.

## Phase 8: Name Resolution Expansion and Unification

Goal:
- Make name resolution more consistent and more broadly useful across flows.

Primary files:
- [NameResolver.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Utilities/NameResolver.swift#L107)
- [ENSResolver.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/ENSResolver.swift)
- [ChainAddressValidator.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/ChainAddressValidator.swift)
- [SendView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Views/SendView.swift)

Tasks:
- Unify the entry point used by send, contacts, and validation flows.
- Expand supported resolution only where the resolution is trustworthy and matches supported chains.
- Add mismatch warnings when a resolved name points to an address incompatible with the chosen chain.
- Add cache strategy and retry rules.

Implementation ideas:
- One resolver service should own supported suffixes, chain compatibility, and normalization.
- Avoid duplicate chain/name rules across UI and validation layers.

Definition of done:
- A resolved name behaves the same in send, contact save, and transaction review.

Validation:
- Test positive resolution, negative resolution, timeout, and mismatched-chain warnings.

## Phase 9: WalletConnect Productionization

Goal:
- Turn an already strong WalletConnect base into a production-grade consumer feature.

Primary files:
- [WalletConnectService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/WalletConnectService.swift#L9)
- [WalletConnectView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Views/WalletConnectView.swift)
- [WalletConnectOverlay.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/UI/WalletConnectOverlay.swift)
- [DAppAccessManager.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/DAppAccessManager.swift)

Tasks:
- Replace development configuration with production credentials and environment handling.
- Add stronger permission granularity by dApp, chain, method, and session lifetime.
- Improve suspicious-origin messaging and risky-request review.
- Add durable session restore, expiry handling, and better disconnect cleanup.

Implementation ideas:
- Persist approvals and revocations as first-class records, not only session memory.
- Track high-risk request types separately in analytics and local history.

Definition of done:
- WalletConnect survives relaunch, exposes clear permissions, and handles bad or stale sessions gracefully.

Validation:
- Test connect, sign, switch chain, expire session, reconnect, and revoke access.

## Phase 10: Portfolio, Alerts, and Reporting Depth

Goal:
- Strengthen the wallet’s day-to-day utility and portfolio visibility.

Primary files:
- [PriceAlertsOverlay.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/UI/PriceAlertsOverlay.swift#L9)
- [NotificationManager.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/NotificationManager.swift)
- [ExportService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/ExportService.swift)

Tasks:
- Expand supported price-alert assets beyond the current short list.
- Add alert persistence and per-wallet configuration.
- Improve portfolio performance summaries and historical views where data is reliable.
- Improve export scope so users can export per wallet, all wallets, filtered assets, and date ranges.

Implementation ideas:
- Use one normalized portfolio snapshot model for views, alerts, and exports.
- Keep unreliable PnL or tax-like numbers out of the UI unless data quality is strong enough.

Definition of done:
- Alerts cover the actual launch asset set.
- Users can understand positions and export useful data without confusion.

Validation:
- Test alert creation, update, trigger, deduplication, and deletion.
- Test export correctness for multiple wallets and date filters.

## Phase 11: In-App Help and Recovery Guidance

Goal:
- Reduce avoidable user error without weakening the self-custody posture.

Primary files:
- [PersonaManager.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/PersonaManager.swift)
- [UserFriendlyErrors.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Utilities/UserFriendlyErrors.swift)
- [ErrorMessages.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Utilities/ErrorMessages.swift)

Tasks:
- Add contextual help blocks in send, swap, bridge, backup, staking, and hardware-wallet flows.
- Standardize failure messages so they explain the problem and the next action.
- Add recovery suggestions for interrupted provider flows, stuck bridge transfers, missing WalletConnect sessions, and hardware-wallet misconfiguration.

Implementation ideas:
- Create a small `HelpTopic` registry keyed by feature and error state.
- Keep messages short, operational, and specific.

Definition of done:
- Users can recover from common failures without guessing.

Validation:
- Review the top 20 likely failure states and confirm each has a user-readable message and next step.

## Phase 12: Cross-Surface State Continuity

Goal:
- Prepare Hawala for extension and mobile without mixing secret sync and convenience sync.

Primary files:
- [BackupService.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/BackupService.swift#L70)
- [SecureSeedStorage.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Services/SecureSeedStorage.swift)
- [PasskeyAuthView.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/Views/PasskeyAuthView.swift#L7)
- [PasskeyAuthOverlay.swift](/Users/x/Desktop/888/swift-app/Sources/swift-app/UI/PasskeyAuthOverlay.swift#L11)

Tasks:
- Define which user state can sync safely: contacts, hidden tokens, alert rules, preferences, recent dApps.
- Keep recovery phrase handling and secure secrets outside convenience-sync design.
- Create migration rules for future desktop-to-mobile or desktop-to-extension continuity.

Implementation ideas:
- Separate `SecretState` from `ConvenienceState` at the model layer.
- Build sync later on top of that split instead of improvising sync rules feature by feature.

Definition of done:
- The codebase has a clean state separation model ready for extension and mobile work.

Validation:
- Review every candidate synced field and classify it explicitly as `sync allowed`, `local only`, or `derived only`.

## Phase 13: Browser Extension Foundation

Goal:
- Create the foundation for a future web3 extension without disrupting the desktop app.

Tasks:
- Extract reusable wallet core logic away from macOS-only UI assumptions.
- Identify signing, permission, and session logic that can be shared with an extension.
- Design the extension capability matrix before writing extension UI.

Implementation ideas:
- Do not start with UI. Start by extracting shareable service boundaries and a capability registry.

Definition of done:
- Shared non-UI core is clearer and extension-specific work can start without duplicating business logic.

Validation:
- Confirm the future extension does not need to import AppKit-bound services.

## Phase 14: Mobile Foundation

Goal:
- Prepare the app for a future iPhone build by separating macOS-only assumptions from shareable wallet logic.

Tasks:
- Identify AppKit-dependent services and isolate them behind platform-specific adapters.
- Split monolithic desktop views into reusable domain logic and platform-specific presentation.
- Make backup, QR, clipboard, and export flows platform-aware.

Implementation ideas:
- Start with service extraction, not screen cloning.
- Favor reusable state/view models and service protocols that can later power iOS screens.

Definition of done:
- The codebase has a realistic path to iPhone without rewriting core wallet behavior from scratch.

Validation:
- Review every service touched by AppKit and tag it as `shared`, `desktop adapter`, or `needs redesign`.

## Release Discipline

Rules to follow during execution:
- Do not enable a feature just because one service path works.
- Do not expose chains in the UI before send, sync, and history are reliable for that chain.
- Do not keep mock fallbacks in production-critical code.
- Do not ship partial hardware wallet support presented as complete support.

## Recommended Build Order

1. Phase 0
2. Phase 1
3. Phase 2
4. Phase 3
5. Phase 4
6. Phase 5
7. Phase 6
8. Phase 7
9. Phase 8
10. Phase 9
11. Phase 10
12. Phase 11
13. Phase 12
14. Phase 13
15. Phase 14

## First Practical Sprint

If work starts immediately, the first sprint should do only this:
- remove simulated on-ramp quote paths from the active design
- remove mock fallback dependency from swap and bridge planning
- map hardware-wallet signing support by launch chain
- remove token-management mock loading
- create the chain capability matrix

That first sprint will clarify what is truly launch-ready versus still architectural.