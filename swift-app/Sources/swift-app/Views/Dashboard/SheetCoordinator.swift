import SwiftUI

// MARK: - Sheet Coordinator
// Groups all ~30 sheet modifiers that were previously chained inline on ContentView's mainAppStage.
// This reduces ContentView.swift by ~280 lines.

struct SheetCoordinator: ViewModifier {
    // MARK: - State bindings
    @ObservedObject var navigationVM: NavigationViewModel
    @ObservedObject var securityVM: SecurityViewModel
    @ObservedObject var backupService: BackupService
    @ObservedObject var wcSigningService: WalletConnectSigningService
    @ObservedObject var priceService: PriceService

    @Binding var keys: AllKeys?
    @Binding var isUnlocked: Bool
    @Binding var hasAcknowledgedSecurityNotice: Bool
    @Binding var storedPasscodeHash: String?
    @Binding var storedFiatCurrency: String
    @Binding var biometricUnlockEnabled: Bool
    @Binding var biometricForSends: Bool
    @Binding var biometricForKeyReveal: Bool
    @Binding var storedAutoLockInterval: Double

    // MARK: - Callbacks
    var onShowStatus: (String, StatusTone, Bool) -> Void = { _, _, _ in }
    var onCopyToClipboard: (String) -> Void = { _ in }
    var onCopySensitiveToClipboard: (String) -> Void = { _ in }
    var onRevealPrivateKeys: () async -> Void = {}
    var onHandleTransactionSuccess: (TransactionBroadcastResult) -> Void = { _ in }
    var onRefreshPendingTransactions: () async -> Void = {}
    var onPresentQueuedSend: () -> Void = {}
    var onFinalizeEncryptedImport: (String) -> Void = { _ in }
    var onImportPrivateKey: (String, String) async -> Void = { _, _ in }
    var onStartFXRatesFetch: () -> Void = {}
    var onFetchPrices: () -> Void = {}
    var onSetupKeyboardShortcutCallbacks: () -> Void = {}

    // MARK: - Computed helpers
    private var canAccessSensitiveData: Bool {
        storedPasscodeHash == nil || isUnlocked
    }

    private var biometricToggleBinding: Binding<Bool> {
        Binding(
            get: { biometricUnlockEnabled },
            set: { biometricUnlockEnabled = $0 }
        )
    }

    private var autoLockSelectionBinding: Binding<AutoLockIntervalOption> {
        Binding(
            get: { AutoLockIntervalOption(rawValue: storedAutoLockInterval) ?? .fiveMinutes },
            set: { storedAutoLockInterval = $0.rawValue }
        )
    }

    private var biometricDisplayInfo: (label: String, icon: String) {
        switch securityVM.biometricState {
        case .available(.faceID): return ("Face ID", "faceid")
        case .available(.touchID): return ("Touch ID", "touchid")
        default: return ("Biometrics", "lock.shield")
        }
    }

    // MARK: - Body
    func body(content: Content) -> some View {
        content
            // Keyboard shortcuts help
            .sheet(isPresented: $navigationVM.showKeyboardShortcutsHelp) {
                KeyboardShortcutsHelpView()
                    .hawalaModal(allowSwipeDismiss: true)
            }
            .onAppear {
                onSetupKeyboardShortcutCallbacks()
            }
            // All private keys
            .sheet(isPresented: $navigationVM.showAllPrivateKeysSheet) {
                if let keys {
                    AllPrivateKeysSheet(chains: keys.chainInfos, onCopy: onCopySensitiveToClipboard)
                        .hawalaModal()
                } else {
                    NoKeysPlaceholderView()
                }
            }
            // Private key password gate
            .sheet(isPresented: $navigationVM.showPrivateKeyPasswordPrompt) {
                PasswordPromptView(
                    mode: .privateKeyExport,
                    onConfirm: { password in
                        // Verify against stored passcode
                        if let expected = storedPasscodeHash {
                            let hashed = securityVM.hashPasscode(password)
                            guard hashed == expected else {
                                // Wrong password — don't reveal keys
                                return
                            }
                        }
                        // Password verified (or no passcode set) — show keys
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            navigationVM.showAllPrivateKeysSheet = true
                        }
                    },
                    onCancel: {}
                )
                .hawalaModal()
            }
            // Receive
            .sheet(isPresented: $navigationVM.showReceiveSheet) {
                if let keys {
                    ReceiveViewModern(chains: keys.chainInfos, onCopy: onCopyToClipboard)
                        .frame(minWidth: 500, minHeight: 650)
                        .hawalaModal(allowSwipeDismiss: true)
                } else {
                    NoKeysPlaceholderView()
                }
            }
            // Send (from chain context)
            .sheet(item: $navigationVM.sendChainContext, onDismiss: { navigationVM.sendChainContext = nil }) { chain in
                if let keys {
                    SendView(keys: keys, initialChain: SendFlowHelper.mapToChain(chain.id), onSuccess: { result in
                        onHandleTransactionSuccess(result)
                    })
                    .hawalaModal()
                } else {
                    Text("Keys not available")
                }
            }
            // Send picker
            .sheet(isPresented: $navigationVM.showSendPicker, onDismiss: onPresentQueuedSend) {
                if let keys {
                    SendAssetPickerSheet(
                        chains: SendFlowHelper.sendEligibleChains(from: keys),
                        onSelect: { chain in
                            navigationVM.pendingSendChain = chain
                            navigationVM.showSendPicker = false
                        },
                        onBatchSend: {
                            navigationVM.showSendPicker = false
                            navigationVM.showBatchTransactionSheet = true
                        },
                        onDismiss: {
                            navigationVM.showSendPicker = false
                        }
                    )
                }
            }
            // Seed phrase (view saved or generate new)
            .sheet(isPresented: $navigationVM.showSeedPhraseSheet) {
                Group {
                    if SecureSeedStorage.hasSeedPhrase(),
                       let savedWords = try? SecureSeedStorage.loadSeedPhrase() {
                        SeedPhraseSheet(savedPhrase: savedWords, onCopy: { value in
                            onCopyToClipboard(value)
                        })
                    } else {
                        SeedPhraseSheet(onCopy: { value in
                            onCopyToClipboard(value)
                        })
                    }
                }
                .hawalaModal()
            }
            // Transaction history
            .sheet(isPresented: $navigationVM.showTransactionHistorySheet) {
                TransactionHistoryView()
                    .frame(minWidth: 500, minHeight: 600)
                    .hawalaModal(allowSwipeDismiss: true)
            }
            // Transaction detail
            .sheet(item: $navigationVM.selectedTransactionForDetail) { transaction in
                TransactionDetailSheet(transaction: transaction)
                    .hawalaModal(allowSwipeDismiss: true)
            }
            // Speed up
            .sheet(item: $navigationVM.speedUpTransaction) { tx in
                if let keys {
                    TransactionCancellationSheet(
                        pendingTx: tx,
                        keys: keys,
                        initialMode: .speedUp,
                        onDismiss: {
                            navigationVM.speedUpTransaction = nil
                        },
                        onSuccess: { newTxid in
                            navigationVM.speedUpTransaction = nil
                            onShowStatus("Transaction sped up: \(newTxid.prefix(16))...", .success, true)
                            Task { await onRefreshPendingTransactions() }
                        }
                    )
                    .hawalaModal()
                }
            }
            // Cancel transaction
            .sheet(item: $navigationVM.cancelTransaction) { tx in
                if let keys {
                    TransactionCancellationSheet(
                        pendingTx: tx,
                        keys: keys,
                        initialMode: .cancel,
                        onDismiss: {
                            navigationVM.cancelTransaction = nil
                        },
                        onSuccess: { newTxid in
                            navigationVM.cancelTransaction = nil
                            onShowStatus("Transaction cancelled: \(newTxid.prefix(16))...", .success, true)
                            Task { await onRefreshPendingTransactions() }
                        }
                    )
                    .hawalaModal()
                }
            }
            // Simple feature sheets
            .sheet(isPresented: $navigationVM.showContactsSheet) { ContactsView() }
            .sheet(isPresented: $navigationVM.showStakingSheet) { StakingView() }
            .sheet(isPresented: $navigationVM.showNotificationsSheet) { NotificationsView() }
            .sheet(isPresented: $navigationVM.showMultisigSheet) { MultisigView() }
            .sheet(isPresented: $navigationVM.showHardwareWalletSheet) { HardwareWalletView() }
            .sheet(isPresented: $navigationVM.showWatchOnlySheet) { WatchOnlyView() }
            // WalletConnect
            .sheet(isPresented: $navigationVM.showWalletConnectSheet) {
                WalletConnectView(
                    availableAccounts: keys.map { wcSigningService.evmAccounts(from: $0) } ?? [],
                    onSign: { request in
                        guard let keys = self.keys else { throw WCError.userRejected }
                        return try await wcSigningService.handleSign(request, keys: keys)
                    }
                )
            }
            // Phase 3 feature sheets
            .sheet(isPresented: $navigationVM.showL2AggregatorSheet) {
                let ethAddress = keys?.chainInfos.first(where: { $0.id == "ethereum" })?.receiveAddress ?? ""
                L2BalanceAggregatorView(address: ethAddress)
            }
            .sheet(isPresented: $navigationVM.showPaymentLinksSheet) { PaymentLinksView() }
            .sheet(isPresented: $navigationVM.showTransactionNotesSheet) { TransactionNotesView() }
            .sheet(isPresented: $navigationVM.showSellCryptoSheet) { SellCryptoView() }
            .sheet(isPresented: $navigationVM.showPriceAlertsSheet) { PriceAlertsView() }
            // Phase 4: Account Abstraction
            .sheet(isPresented: $navigationVM.showSmartAccountSheet) { SmartAccountView() }
            .sheet(isPresented: $navigationVM.showGasAccountSheet) { GasAccountView() }
            .sheet(isPresented: $navigationVM.showPasskeyAuthSheet) { PasskeyAuthView() }
            .sheet(isPresented: $navigationVM.showGaslessTxSheet) { GaslessTxView() }
            .sheet(isPresented: $navigationVM.showBatchTransactionSheet) { BatchTransactionView() }
            // Settings
            .sheet(isPresented: $navigationVM.showSettingsPanel) {
                SettingsPanelView(
                    hasKeys: keys != nil,
                    onShowKeys: {
                        if keys != nil {
                            Task { await onRevealPrivateKeys() }
                        } else {
                            onShowStatus("Generate keys before viewing private material.", .info, true)
                        }
                    },
                    onOpenSecurity: {
                        DispatchQueue.main.async {
                            navigationVM.showSecuritySettings = true
                        }
                    },
                    selectedCurrency: $storedFiatCurrency,
                    onCurrencyChanged: {
                        onStartFXRatesFetch()
                        onFetchPrices()
                    }
                )
            }
            // Security
            .sheet(isPresented: $navigationVM.showSecurityNotice) {
                SecurityNoticeView {
                    hasAcknowledgedSecurityNotice = true
                    navigationVM.showSecurityNotice = false
                }
            }
            .sheet(isPresented: $navigationVM.showSecuritySettings) {
                SecuritySettingsView(
                    hasPasscode: storedPasscodeHash != nil,
                    onSetPasscode: { passcode in
                        storedPasscodeHash = securityVM.hashPasscode(passcode)
                        securityVM.lock()
                        navigationVM.showSecuritySettings = false
                    },
                    onRemovePasscode: {
                        storedPasscodeHash = nil
                        isUnlocked = true
                        navigationVM.showSecuritySettings = false
                    },
                    biometricState: securityVM.biometricState,
                    biometricEnabled: biometricToggleBinding,
                    biometricForSends: $biometricForSends,
                    biometricForKeyReveal: $biometricForKeyReveal,
                    autoLockSelection: autoLockSelectionBinding,
                    onBiometricRequest: {
                        securityVM.attemptBiometricUnlock(reason: "Unlock Hawala")
                    }
                )
            }
            // Unlock
            .sheet(isPresented: $navigationVM.showUnlockSheet) {
                UnlockView(
                    supportsBiometrics: biometricUnlockEnabled && securityVM.biometricState.supportsUnlock && storedPasscodeHash != nil,
                    biometricButtonLabel: biometricDisplayInfo.label,
                    biometricButtonIcon: biometricDisplayInfo.icon,
                    onBiometricRequest: {
                        securityVM.attemptBiometricUnlock(reason: "Unlock Hawala")
                    },
                    onSubmit: { candidate in
                        guard let expected = storedPasscodeHash else { return nil }
                        let hashed = securityVM.hashPasscode(candidate)
                        if hashed == expected {
                            isUnlocked = true
                            navigationVM.showUnlockSheet = false
                            securityVM.recordActivity()
                            return nil
                        }
                        return "Incorrect passcode. Try again."
                    },
                    onCancel: {
                        navigationVM.showUnlockSheet = false
                    }
                )
            }
            // Export / Import
            .sheet(isPresented: $navigationVM.showExportPasswordPrompt) {
                PasswordPromptView(
                    mode: .export,
                    onConfirm: { password in
                        navigationVM.showExportPasswordPrompt = false
                        backupService.performEncryptedExport(keys: keys, password: password)
                    },
                    onCancel: {
                        navigationVM.showExportPasswordPrompt = false
                    }
                )
            }
            .sheet(isPresented: $navigationVM.showImportPasswordPrompt) {
                PasswordPromptView(
                    mode: .import,
                    onConfirm: { password in
                        navigationVM.showImportPasswordPrompt = false
                        onFinalizeEncryptedImport(password)
                    },
                    onCancel: {
                        navigationVM.showImportPasswordPrompt = false
                        navigationVM.pendingImportData = nil
                    }
                )
            }
            .sheet(isPresented: $navigationVM.showImportPrivateKeySheet) {
                ImportPrivateKeySheet(
                    onImport: { privateKey, chainType in
                        navigationVM.showImportPrivateKeySheet = false
                        Task { await onImportPrivateKey(privateKey, chainType) }
                    },
                    onCancel: {
                        navigationVM.showImportPrivateKeySheet = false
                    }
                )
            }
    }
}

// MARK: - View Extension
extension View {
    func sheetCoordinator(
        navigationVM: NavigationViewModel,
        securityVM: SecurityViewModel,
        backupService: BackupService,
        wcSigningService: WalletConnectSigningService,
        priceService: PriceService,
        keys: Binding<AllKeys?>,
        isUnlocked: Binding<Bool>,
        hasAcknowledgedSecurityNotice: Binding<Bool>,
        storedPasscodeHash: Binding<String?>,
        storedFiatCurrency: Binding<String>,
        biometricUnlockEnabled: Binding<Bool>,
        biometricForSends: Binding<Bool>,
        biometricForKeyReveal: Binding<Bool>,
        storedAutoLockInterval: Binding<Double>,
        onShowStatus: @escaping (String, StatusTone, Bool) -> Void,
        onCopyToClipboard: @escaping (String) -> Void,
        onCopySensitiveToClipboard: @escaping (String) -> Void,
        onRevealPrivateKeys: @escaping () async -> Void,
        onHandleTransactionSuccess: @escaping (TransactionBroadcastResult) -> Void,
        onRefreshPendingTransactions: @escaping () async -> Void,
        onPresentQueuedSend: @escaping () -> Void,
        onFinalizeEncryptedImport: @escaping (String) -> Void,
        onImportPrivateKey: @escaping (String, String) async -> Void,
        onStartFXRatesFetch: @escaping () -> Void,
        onFetchPrices: @escaping () -> Void,
        onSetupKeyboardShortcutCallbacks: @escaping () -> Void
    ) -> some View {
        self.modifier(SheetCoordinator(
            navigationVM: navigationVM,
            securityVM: securityVM,
            backupService: backupService,
            wcSigningService: wcSigningService,
            priceService: priceService,
            keys: keys,
            isUnlocked: isUnlocked,
            hasAcknowledgedSecurityNotice: hasAcknowledgedSecurityNotice,
            storedPasscodeHash: storedPasscodeHash,
            storedFiatCurrency: storedFiatCurrency,
            biometricUnlockEnabled: biometricUnlockEnabled,
            biometricForSends: biometricForSends,
            biometricForKeyReveal: biometricForKeyReveal,
            storedAutoLockInterval: storedAutoLockInterval,
            onShowStatus: onShowStatus,
            onCopyToClipboard: onCopyToClipboard,
            onCopySensitiveToClipboard: onCopySensitiveToClipboard,
            onRevealPrivateKeys: onRevealPrivateKeys,
            onHandleTransactionSuccess: onHandleTransactionSuccess,
            onRefreshPendingTransactions: onRefreshPendingTransactions,
            onPresentQueuedSend: onPresentQueuedSend,
            onFinalizeEncryptedImport: onFinalizeEncryptedImport,
            onImportPrivateKey: onImportPrivateKey,
            onStartFXRatesFetch: onStartFXRatesFetch,
            onFetchPrices: onFetchPrices,
            onSetupKeyboardShortcutCallbacks: onSetupKeyboardShortcutCallbacks
        ))
    }
}
