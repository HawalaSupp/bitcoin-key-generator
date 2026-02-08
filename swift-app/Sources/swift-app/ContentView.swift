import SwiftUI
import Security
import LocalAuthentication
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// Types are defined in Models/AppTypes.swift and Models/ChainKeys.swift

struct ContentView: View {
    @State private var keys: AllKeys?
    @State private var rawJSON: String = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var statusColor: Color = .green
    @State private var statusTask: Task<Void, Never>?
    @AppStorage("hawala.securityAcknowledged") private var hasAcknowledgedSecurityNotice = false
    @AppStorage("hawala.passcodeHash") private var storedPasscodeHash: String?
    @AppStorage("hawala.onboardingCompleted") private var onboardingCompleted = false
    @AppStorage("hawala.appearanceMode") private var storedAppearanceMode = AppearanceMode.system.rawValue
    @AppStorage("hawala.biometricUnlockEnabled") private var biometricUnlockEnabled = false
    @AppStorage("hawala.biometricForSends") private var biometricForSends = true
    @AppStorage("hawala.biometricForKeyReveal") private var biometricForKeyReveal = true
    @AppStorage("hawala.autoLockInterval") private var storedAutoLockInterval: Double = AutoLockIntervalOption.fiveMinutes.rawValue
    @AppStorage("hawala.selectedFiatCurrency") private var storedFiatCurrency = FiatCurrency.usd.rawValue
    @State private var isUnlocked = false
    @State private var hasResetOnboardingState = false
    @State private var balanceStates: [String: ChainBalanceState] = [:]
    @State private var cachedBalances: [String: CachedBalance] = [:]
    @State private var balanceBackoff: [String: BackoffTracker] = [:]
    @State private var balanceFetchTasks: [String: Task<Void, Never>] = [:]
    @StateObject private var sparklineCache = SparklineCache.shared
    @StateObject private var assetCache = AssetCache.shared
    @StateObject private var transactionHistoryService = TransactionHistoryService.shared
    @StateObject private var navigationVM = NavigationViewModel()
    @StateObject private var securityVM = SecurityViewModel()
    @StateObject private var walletVM = WalletViewModel()
    @StateObject private var balanceService = BalanceService.shared
    @StateObject private var priceService = PriceService.shared
    @StateObject private var backupService = BackupService.shared
    @StateObject private var wcSigningService = WalletConnectSigningService.shared
    // Phase 3 Feature Sheets
    // Phase 4 Feature Sheets (ERC-4337 Account Abstraction)
    @State private var historyEntries: [HawalaTransactionEntry] = []
    @State private var historyError: String?
    @State private var isHistoryLoading = false
    @State private var historyFetchTask: Task<Void, Never>?
    // History filtering
    @State private var historySearchText: String = ""
    @State private var historyFilterChain: String? = nil
    @State private var historyFilterType: String? = nil
    @State private var pendingTransactions: [PendingTransactionManager.PendingTransaction] = []
    @State private var pendingTxRefreshTask: Task<Void, Never>?
    // Debug: Show FPS performance overlay in DEBUG builds
    #if DEBUG
    @State private var showPerformanceOverlay = false  // Disabled for screenshot
    #endif
    private let moneroBalancePlaceholder = "View-only · Open Monero GUI wallet for full access"

    private let minimumBalanceRetryDelay: TimeInterval = 0.5
    private static let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var canAccessSensitiveData: Bool {
        storedPasscodeHash == nil || isUnlocked
    }

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: storedAppearanceMode) ?? .system
    }

    private var appearanceSelectionBinding: Binding<AppearanceMode> {
        Binding(
            get: { appearanceMode },
            set: { newValue in updateAppearanceMode(newValue) }
        )
    }

    private var autoLockSelectionBinding: Binding<AutoLockIntervalOption> {
        Binding(
            get: { AutoLockIntervalOption(rawValue: storedAutoLockInterval) ?? .fiveMinutes },
            set: { newValue in
                storedAutoLockInterval = newValue.rawValue
                Task { @MainActor in
                    securityVM.recordActivity()
                }
            }
        )
    }

    private var biometricToggleBinding: Binding<Bool> {
        Binding(
            get: { biometricUnlockEnabled && storedPasscodeHash != nil },
            set: { newValue in
                guard storedPasscodeHash != nil else {
                    biometricUnlockEnabled = false
                    return
                }
                biometricUnlockEnabled = newValue
                if newValue {
                    securityVM.attemptBiometricUnlock(reason: "Unlock Hawala")
                }
            }
        )
    }

    private var biometricDisplayInfo: (label: String, icon: String) {
        if case .available(let kind) = securityVM.biometricState {
            return (kind.displayName, kind.iconName)
        }
        return ("Biometrics", "lock.circle")
    }

    var body: some View {
        ZStack {
            // Splash screen overlay
            if navigationVM.showSplashScreen {
                HawalaSplashView(isShowingSplash: $navigationVM.showSplashScreen)
                    .zIndex(100)
                    .transition(.opacity)
            }
            
            ZStack(alignment: .topTrailing) {
                Group {
                    if onboardingCompleted {
                        mainAppStage
                    } else {
                        onboardingFlow
                    }
                }

                // newestBuildBadge - hidden for screenshot
                //     .padding(.top, 12)
                //     .padding(.trailing, 12)
                //     .allowsHitTesting(false)
                
                // DEBUG: Performance overlay (tap badge to toggle, or start with environment variable)
                #if DEBUG
                if showPerformanceOverlay {
                    PerformanceOverlay()
                        .padding(.top, 50)
                        .padding(.trailing, 12)
                        .zIndex(200)
                        .onTapGesture(count: 2) {
                            showPerformanceOverlay = false
                        }
                }
                #endif
            }
            .opacity(navigationVM.showSplashScreen ? 0 : 1)
        }
        #if DEBUG
        .onAppear {
            // Enable with environment variable: HAWALA_PERF_OVERLAY=1
            if ProcessInfo.processInfo.environment["HAWALA_PERF_OVERLAY"] == "1" {
                showPerformanceOverlay = true
            }
        }
        #endif
        .animation(.easeInOut(duration: 0.3), value: navigationVM.showSplashScreen)
        .animation(.easeInOut(duration: 0.3), value: onboardingCompleted)
        .animation(.easeInOut(duration: 0.3), value: navigationVM.onboardingStep)
        .preferredColorScheme(appearanceMode.colorScheme)
        .onAppear {
            guard !hasResetOnboardingState else { return }
            onboardingCompleted = false
            navigationVM.onboardingStep = .welcome
            navigationVM.shouldAutoGenerateAfterOnboarding = false
            balanceStates.removeAll()
            priceService.resetState()
            cachedBalances.removeAll()
            balanceBackoff.removeAll()
            hasResetOnboardingState = true
            
            // Load cached asset data for instant display
            loadCachedAssetData()
            
            // Try to load existing keys from Keychain
            loadKeysFromKeychain()
            
            // Start pending transaction monitoring
            startPendingTransactionRefresh()
        }
        .onChange(of: onboardingCompleted) { completed in
            if completed && keys == nil {
                // Load keys when onboarding completes if not already loaded
                loadKeysFromKeychain()
            }
        }
    }

    
    private var mainAppStage: some View {
        ZStack {
            // New modern UI
            if navigationVM.selectedChain == nil {
                HawalaMainView(
                    keys: $keys,
                    selectedChain: $navigationVM.selectedChain,
                    balanceStates: $balanceStates,
                    priceStates: $priceService.priceStates,
                    sparklineCache: sparklineCache,
                    showSendPicker: $navigationVM.showSendPicker,
                    showReceiveSheet: $navigationVM.showReceiveSheet,
                    showSettingsPanel: $navigationVM.showSettingsPanel,
                    showStakingSheet: $navigationVM.showStakingSheet,
                    showNotificationsSheet: $navigationVM.showNotificationsSheet,
                    showContactsSheet: $navigationVM.showContactsSheet,
                    showWalletConnectSheet: $navigationVM.showWalletConnectSheet,
                    showL2AggregatorSheet: $navigationVM.showL2AggregatorSheet,
                    showPaymentLinksSheet: $navigationVM.showPaymentLinksSheet,
                    showTransactionNotesSheet: $navigationVM.showTransactionNotesSheet,
                    showSellCryptoSheet: $navigationVM.showSellCryptoSheet,
                    showPriceAlertsSheet: $navigationVM.showPriceAlertsSheet,
                    // Phase 4: Account Abstraction
                    showSmartAccountSheet: $navigationVM.showSmartAccountSheet,
                    showGasAccountSheet: $navigationVM.showGasAccountSheet,
                    showPasskeyAuthSheet: $navigationVM.showPasskeyAuthSheet,
                    showGaslessTxSheet: $navigationVM.showGaslessTxSheet,
                    onGenerateKeys: {
                        // Auto-acknowledge security notice for streamlined UX
                        if !hasAcknowledgedSecurityNotice {
                            hasAcknowledgedSecurityNotice = true
                        }
                        guard canAccessSensitiveData else {
                            navigationVM.showUnlockSheet = true
                            return
                        }
                        Task { await runGenerator() }
                    },
                    onRefreshBalances: {
                        if let keys = keys {
                            balanceService.startBalanceFetch(for: keys)
                        }
                    },
                    onRefreshHistory: {
                        refreshTransactionHistory(force: true)
                    },
                    selectedFiatSymbol: selectedFiatCurrency.symbol,
                    fxRates: priceService.fxRates,
                    selectedFiatCurrency: storedFiatCurrency,
                    isGenerating: isGenerating,
                    historyEntries: $historyEntries,
                    isHistoryLoading: $isHistoryLoading,
                    historyError: $historyError
                )
            } else if let chain = navigationVM.selectedChain {
                HawalaAssetDetailView(
                    chain: chain,
                    balanceState: Binding(
                        get: { balanceStates[chain.id] },
                        set: { balanceStates[chain.id] = $0 ?? .idle }
                    ),
                    priceState: Binding(
                        get: { priceService.priceStates[chain.id] },
                        set: { priceService.priceStates[chain.id] = $0 ?? .idle }
                    ),
                    sparklineData: sparklineCache.sparklines[chain.id] ?? [],
                    onSend: {
                        navigationVM.pendingSendChain = chain
                        navigationVM.selectedChain = nil
                    },
                    onReceive: {
                        navigationVM.showReceiveSheet = true
                    },
                    onClose: {
                        withAnimation(HawalaTheme.Animation.fast) {
                            navigationVM.selectedChain = nil
                        }
                    },
                    selectedFiatSymbol: selectedFiatCurrency.symbol,
                    fxMultiplier: priceService.fxRates[storedFiatCurrency] ?? 1.0
                )
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(HawalaTheme.Colors.background)
        .preferredColorScheme(.dark)
        // ROADMAP-03: Keyboard shortcuts help sheet
        .sheet(isPresented: $navigationVM.showKeyboardShortcutsHelp) {
            KeyboardShortcutsHelpView()
                .hawalaModal(allowSwipeDismiss: true) // OK to swipe-dismiss help
        }
        // ROADMAP-03: Setup keyboard shortcut callbacks
        .onAppear {
            setupKeyboardShortcutCallbacks()
        }
        .sheet(isPresented: $navigationVM.showAllPrivateKeysSheet) {
            if let keys {
                AllPrivateKeysSheet(chains: keys.chainInfos, onCopy: copySensitiveToClipboard)
                    .hawalaModal() // Prevent accidental dismiss of sensitive info
            } else {
                NoKeysPlaceholderView()
            }
        }
        .sheet(isPresented: $navigationVM.showReceiveSheet) {
            if let keys {
                ReceiveViewModern(chains: keys.chainInfos, onCopy: copyToClipboard)
                    .frame(minWidth: 500, minHeight: 650)
                    .hawalaModal(allowSwipeDismiss: true) // OK to swipe-dismiss receive
            } else {
                NoKeysPlaceholderView()
            }
        }
        .sheet(item: $navigationVM.sendChainContext, onDismiss: { navigationVM.sendChainContext = nil }) { chain in
            if let keys {
                SendView(keys: keys, initialChain: SendFlowHelper.mapToChain(chain.id), onSuccess: { result in
                    handleTransactionSuccess(result)
                })
                .hawalaModal() // CRITICAL: Prevent accidental dismiss during transaction
            } else {
                Text("Keys not available")
            }
        }

        .sheet(isPresented: $navigationVM.showSendPicker, onDismiss: presentQueuedSendIfNeeded) {
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
        .sheet(isPresented: $navigationVM.showSeedPhraseSheet) {
            SeedPhraseSheet(onCopy: { value in
                copyToClipboard(value)
            })
            .hawalaModal() // CRITICAL: Prevent accidental dismiss of seed phrase
        }
        .sheet(isPresented: $navigationVM.showTransactionHistorySheet) {
            TransactionHistoryView()
                .frame(minWidth: 500, minHeight: 600)
                .hawalaModal(allowSwipeDismiss: true) // OK to swipe-dismiss history
        }
        .sheet(item: $navigationVM.selectedTransactionForDetail) { transaction in
            TransactionDetailSheet(transaction: transaction)
                .hawalaModal(allowSwipeDismiss: true) // OK to swipe-dismiss detail
        }
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
                        showStatus("Transaction sped up: \(newTxid.prefix(16))...", tone: .success)
                        Task { await refreshPendingTransactions() }
                    }
                )
                .hawalaModal() // CRITICAL: Prevent accidental dismiss during speed-up
            }
        }
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
                        showStatus("Transaction cancelled: \(newTxid.prefix(16))...", tone: .success)
                        Task { await refreshPendingTransactions() }
                    }
                )
                .hawalaModal() // CRITICAL: Prevent accidental dismiss during cancel
            }
        }
        .sheet(isPresented: $navigationVM.showContactsSheet) {
            ContactsView()
        }
        .sheet(isPresented: $navigationVM.showStakingSheet) {
            StakingView()
        }
        .sheet(isPresented: $navigationVM.showNotificationsSheet) {
            NotificationsView()
        }
        .sheet(isPresented: $navigationVM.showMultisigSheet) {
            MultisigView()
        }
        .sheet(isPresented: $navigationVM.showHardwareWalletSheet) {
            HardwareWalletView()
        }
        .sheet(isPresented: $navigationVM.showWatchOnlySheet) {
            WatchOnlyView()
        }
        .sheet(isPresented: $navigationVM.showWalletConnectSheet) {
            WalletConnectView(
                availableAccounts: keys.map { wcSigningService.evmAccounts(from: $0) } ?? [],
                onSign: { [self] request in
                    guard let keys = self.keys else { throw WCError.userRejected }
                    return try await wcSigningService.handleSign(request, keys: keys)
                }
            )
        }
        // Phase 3 Feature Sheets
        .sheet(isPresented: $navigationVM.showL2AggregatorSheet) {
            if let ethAddress = keys?.chainInfos.first(where: { $0.id == "ethereum" })?.receiveAddress {
                L2BalanceAggregatorView(address: ethAddress)
            } else {
                L2BalanceAggregatorView(address: "")
            }
        }
        .sheet(isPresented: $navigationVM.showPaymentLinksSheet) {
            PaymentLinksView()
        }
        .sheet(isPresented: $navigationVM.showTransactionNotesSheet) {
            TransactionNotesView()
        }
        .sheet(isPresented: $navigationVM.showSellCryptoSheet) {
            SellCryptoView()
        }
        .sheet(isPresented: $navigationVM.showPriceAlertsSheet) {
            PriceAlertsView()
        }
        // Phase 4: ERC-4337 Account Abstraction Sheets
        .sheet(isPresented: $navigationVM.showSmartAccountSheet) {
            SmartAccountView()
        }
        .sheet(isPresented: $navigationVM.showGasAccountSheet) {
            GasAccountView()
        }
        .sheet(isPresented: $navigationVM.showPasskeyAuthSheet) {
            PasskeyAuthView()
        }
        .sheet(isPresented: $navigationVM.showGaslessTxSheet) {
            GaslessTxView()
        }
        .sheet(isPresented: $navigationVM.showBatchTransactionSheet) {
            BatchTransactionView()
        }
        .sheet(isPresented: $navigationVM.showSettingsPanel) {
            SettingsPanelView(
                hasKeys: keys != nil,
                onShowKeys: {
                    if keys != nil {
                        Task { await revealPrivateKeysWithBiometric() }
                    } else {
                        showStatus("Generate keys before viewing private material.", tone: .info)
                    }
                },
                onOpenSecurity: {
                    DispatchQueue.main.async {
                        navigationVM.showSecuritySettings = true
                    }
                },
                selectedCurrency: $storedFiatCurrency,
                onCurrencyChanged: {
                    // Refresh FX rates and prices when currency changes
                    priceService.startFXRatesFetch()
                    Task {
                        _ = await priceService.fetchAndStorePrices()
                    }
                }
            )
        }
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
                    finalizeEncryptedImport(with: password)
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
                    Task {
                        await importPrivateKey(privateKey, for: chainType)
                    }
                },
                onCancel: {
                    navigationVM.showImportPrivateKeySheet = false
                }
            )
        }
        .overlay {
            // Privacy blur overlay when app goes to background/inactive
            if securityVM.showPrivacyBlur {
                PrivacyBlurOverlay()
                    .transition(.opacity)
            }
        }
        .onAppear {
            prepareSecurityState()
            triggerAutoGenerationIfNeeded()
            priceService.startPriceUpdatesIfNeeded(sparklineCache: sparklineCache)
            securityVM.refreshBiometricAvailability()
            securityVM.startActivityMonitoringIfNeeded()
            securityVM.recordActivity()
            backupService.onStatus = { [self] message, tone, autoClear in
                showStatus(message, tone: tone, autoClear: autoClear)
            }
        }
        .onChange(of: storedPasscodeHash) { _ in
            securityVM.handlePasscodeChange()
        }
        .onChange(of: scenePhase) { phase in
            handleScenePhase(phase)
        }
        .onChange(of: navigationVM.shouldAutoGenerateAfterOnboarding) { newValue in
            if newValue {
                triggerAutoGenerationIfNeeded()
            }
        }
        .onChange(of: onboardingCompleted) { completed in
            if completed {
                priceService.startPriceUpdatesIfNeeded(sparklineCache: sparklineCache)
            } else {
                priceService.stopPriceUpdates()
            }
        }
    }

    private var onboardingFlow: some View {
        NewOnboardingFlowView { result in
            Task {
                await handleOnboardingComplete(result)
            }
        }
    }
    
    private func importPrivateKey(_ privateKey: String, for chainType: String) async {
        showStatus("Importing private key for \(chainType)...", tone: .info)

        // For now, show a message that the import functionality requires generating
        // keys from the Rust backend with custom seeds
        showStatus("""
            ⚠️ Private key import requires integration with the Rust key generator.

            Current implementation generates all keys from a single seed.
            To import individual private keys, you would need to:

            1. Modify the Rust backend to accept custom private keys
            2. Derive public addresses from the imported private key
            3. Merge with existing key set

            For now, you can:
            • Use the imported private key directly in the Bitcoin send flow
            • Export current keys and manually edit the JSON to include imported keys

            Imported key saved to clipboard for manual use.
            """, tone: .info, autoClear: false)

        // Copy to clipboard for user to use manually
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(privateKey, forType: .string)
    }

    @MainActor
    private func handleOnboardingComplete(_ result: WalletCreationResult) async {
        // Set all the necessary flags
        hasAcknowledgedSecurityNotice = true
        isUnlocked = true
        navigationVM.shouldAutoGenerateAfterOnboarding = false
        navigationVM.completedOnboardingThisSession = true
        
        // Generate or import wallet based on method
        switch result.method {
        case .create, .importSeed:
            // Use the Rust backend to generate keys
            await runGenerator()
            
        case .ledger, .trezor, .keystone:
            // Hardware wallet - just mark complete, actual connection handled separately
            break
            
        case .watchOnly:
            // Watch-only mode - no keys to generate
            break
        }
        
        // Enable biometrics if user opted in
        if result.hasBiometrics {
            // Store biometric preference
            UserDefaults.standard.set(true, forKey: "hawala.biometricsEnabled")
        }
        
        // Mark onboarding as complete
        onboardingCompleted = true
    }

    // MARK: - Privacy Blur Overlay
    private struct PrivacyBlurOverlay: View {
        var body: some View {
            ZStack {
                // Blur background
                #if canImport(AppKit)
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                #else
                Rectangle()
                    .fill(.ultraThinMaterial)
                #endif
                
                // Hawala branding
                VStack(spacing: 16) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                    
                    Text("Hawala")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Wallet protected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .ignoresSafeArea()
        }
    }
    
    #if canImport(AppKit)
    private struct VisualEffectBlur: NSViewRepresentable {
        let material: NSVisualEffectView.Material
        let blendingMode: NSVisualEffectView.BlendingMode
        
        func makeNSView(context: Context) -> NSVisualEffectView {
            let view = NSVisualEffectView()
            view.material = material
            view.blendingMode = blendingMode
            view.state = .active
            return view
        }
        
        func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
            nsView.material = material
            nsView.blendingMode = blendingMode
        }
    }
    #endif

    @ViewBuilder
    private var contentArea: some View {
        if !hasAcknowledgedSecurityNotice {
            SecurityPromptView {
                navigationVM.showSecurityNotice = true
            }
        } else if !canAccessSensitiveData {
            LockedStateView {
                navigationVM.showUnlockSheet = true
            }
        } else if let keys {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    portfolioHeader
                    
                    actionButtonsRow

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Your Wallets")
                                    .font(.headline)
                                Text("\(keys.chainInfos.count) chains")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        
                        LazyVGrid(columns: gridColumns(for: navigationVM.viewportWidth), spacing: 14) {
                            ForEach(keys.chainInfos) { chain in
                                Button {
                                    guard canAccessSensitiveData else {
                                        navigationVM.showUnlockSheet = true
                                        return
                                    }
                                    navigationVM.selectedChain = chain
                                } label: {
                                    let balance = balanceStates[chain.id] ?? balanceService.defaultBalanceState(for: chain.id)
                                    let price = priceService.priceStates[chain.id] ?? priceService.defaultPriceState(for: chain.id)
                                    let sparkline = sparklineCache.sparklines[chain.id] ?? []
                                    ChainCard(
                                        chain: chain,
                                        balanceState: balance,
                                        priceState: price,
                                        sparklineData: sparkline
                                    )
                                }
                                .buttonStyle(.plain)
                                .transition(cardTransition)
                            }
                        }
                        // Only animate viewport changes, not data changes
                        // This prevents full grid re-renders during scroll
                        .animation(cardAnimation, value: navigationVM.viewportWidth)
                        // Removed: .animation(cardAnimation, value: balanceAnimationToken)
                        // Removed: .animation(cardAnimation, value: priceAnimationToken)
                        // These caused jank during scroll as any balance/price update triggered full grid animation
                    }

                    pendingTransactionsSection
                    transactionHistorySection
                }
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: ViewWidthPreferenceKey.self, value: proxy.size.width)
                }
            )
            .onPreferenceChange(ViewWidthPreferenceKey.self) { width in
                navigationVM.viewportWidth = width
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "rectangle.and.text.magnifyingglass")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No key material yet")
                    .font(.headline)
                Text("Generate a fresh set of keys to review per-chain details and copy them securely.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var cardBackgroundColor: Color {
        #if canImport(AppKit)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(UIColor.secondarySystemBackground)
        #endif
    }

    private func gridColumns(for width: CGFloat) -> [GridItem] {
        let effectiveWidth = (width.isFinite && width > 0) ? width : 900
        if effectiveWidth < 520 {
            return [GridItem(.flexible(), spacing: 12, alignment: .top)]
        } else if effectiveWidth < 900 {
            return [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 14, alignment: .top)]
        } else {
            return [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 16, alignment: .top)]
        }
    }

    private var balanceAnimationToken: Int {
        balanceStates.reduce(0) { partial, entry in
            var hasher = Hasher()
            hasher.combine(entry.key)
            hasher.combine(String(describing: entry.value))
            return partial ^ hasher.finalize()
        }
    }

    private var priceAnimationToken: Int {
        priceService.priceStates.reduce(0) { partial, entry in
            var hasher = Hasher()
            hasher.combine(entry.key)
            hasher.combine(String(describing: entry.value))
            return partial ^ hasher.finalize()
        }
    }

    private var cardAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.45, dampingFraction: 0.82, blendDuration: 0.3)
    }

    private var cardTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity)
    }

    private var appearanceMenu: some View {
        Menu {
            Picker("Appearance", selection: appearanceSelectionBinding) {
                ForEach(AppearanceMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.menuIconName)
                        .tag(mode)
                }
            }
        } label: {
            Image(systemName: appearanceMode.menuIconName)
                .font(.title2)
                .padding(6)
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Appearance")
        .help("Switch between system, light, or dark appearance")
    }

    private func updateAppearanceMode(_ mode: AppearanceMode) {
        guard appearanceMode != mode else { return }
        storedAppearanceMode = mode.rawValue
        showStatus("\(mode.displayName) enabled", tone: .info)
    }

    private var portfolioHeader: some View {
        VStack(spacing: 12) {
            Text("Total Portfolio Value")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            Text(totalBalanceDisplay)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.blue, Color.purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            
            Text(priceStatusLine)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button {
                refreshAllBalances()
            } label: {
                Label("Refresh Balances", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.blue)
        }
        .frame(maxWidth: headerMaxWidth(for: navigationVM.viewportWidth))
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func headerMaxWidth(for width: CGFloat) -> CGFloat? {
        guard width.isFinite else { return nil }
        if width < 560 {
            return width - 16
        }
        return min(width - 120, 780)
    }

    private var totalBalanceDisplay: String {
        let result = calculatePortfolioTotal()
        guard let total = result.total, result.hasData else {
            return "—"
        }
        return priceService.formatFiatAmountInSelectedCurrency(total, storedFiatCurrency: storedFiatCurrency)
    }

    private var priceStatusLine: String {
        if priceService.priceStates.isEmpty {
            return "Fetching live prices…"
        }

        if priceService.priceStates.values.contains(where: { state in
            if case .loading = state { return true }
            return false
        }) {
            return "Fetching live prices…"
        }
        if priceService.priceStates.values.contains(where: { state in
            if case .refreshing = state { return true }
            return false
        }) {
            return "Refreshing live prices…"
        }

        if priceService.priceStates.values.contains(where: { state in
            if case .stale = state { return true }
            return false
        }) {
            if let latest = latestPriceUpdate, let relative = relativeTimeDescription(from: latest) {
                return "Showing cached prices • updated \(relative)"
            }
            return "Showing cached prices"
        }

        if let latest = latestPriceUpdate, let relative = relativeTimeDescription(from: latest) {
            return "Live estimate • updated \(relative)"
        }

        return "Live estimate"
    }

    private var latestPriceUpdate: Date? {
        priceService.priceStates.values.compactMap { state in
            switch state {
            case .loaded(_, let timestamp):
                return timestamp
            case .refreshing(_, let timestamp):
                return timestamp
            case .stale(_, let timestamp, _):
                return timestamp
            default:
                return nil
            }
        }.max()
    }

    private func calculatePortfolioTotal() -> (total: Double?, hasData: Bool) {
        guard let keys else { return (nil, false) }
        var accumulator: Double = 0
        var hasValue = false

        for chain in keys.chainInfos {
            let balanceState = balanceStates[chain.id] ?? balanceService.defaultBalanceState(for: chain.id)
            let priceState = priceService.priceStates[chain.id] ?? priceService.defaultPriceState(for: chain.id)

            guard
                let balance = balanceService.extractNumericAmount(from: balanceState),
                let price = extractFiatPrice(from: priceState)
            else { continue }

            hasValue = true
            accumulator += balance * price
        }

        return hasValue ? (accumulator, true) : (nil, false)
    }

    @ViewBuilder
    private var actionButtonsRow: some View {
        if navigationVM.viewportWidth < 620 {
            VStack(spacing: 10) {
                actionButtonsContent
            }
        } else {
            HStack(spacing: 10) {
                actionButtonsContent
            }
        }
    }

    @ViewBuilder
    private var actionButtonsContent: some View {
        walletActionButton(
            title: "Send",
            systemImage: "paperplane.fill",
            color: .orange
        ) {
            if keys == nil {
                Task {
                    await runGenerator()
                    await MainActor.run {
                        openSendSheet()
                    }
                }
            } else {
                openSendSheet()
            }
        }
        .disabled(keys == nil && isGenerating)

        walletActionButton(
            title: "Receive",
            systemImage: "arrow.down.left.and.arrow.up.right",
            color: .green
        ) {
            guard keys != nil else {
                showStatus("Generate keys before receiving.", tone: .info)
                return
            }
            navigationVM.showReceiveSheet = true
        }
        .disabled(keys == nil)

        walletActionButton(
            title: "View Keys",
            systemImage: "doc.richtext",
            color: .blue
        ) {
            guard canAccessSensitiveData else {
                navigationVM.showUnlockSheet = true
                return
            }
            if keys != nil {
                Task { await revealPrivateKeysWithBiometric() }
            } else {
                showStatus("Generate keys before viewing private material.", tone: .info)
            }
        }
        .disabled(!canAccessSensitiveData)

        walletActionButton(
            title: "Export",
            systemImage: "tray.and.arrow.up",
            color: .purple
        ) {
            guard keys != nil else {
                showStatus("Generate keys before exporting.", tone: .info)
                return
            }
            navigationVM.showExportPasswordPrompt = true
        }
        .disabled(keys == nil)

        walletActionButton(
            title: "Seed Phrase",
            systemImage: "list.number.rtl",
            color: .purple
        ) {
            navigationVM.showSeedPhraseSheet = true
        }
        
        walletActionButton(
            title: "History",
            systemImage: "clock.arrow.circlepath",
            color: .cyan
        ) {
            navigationVM.showTransactionHistorySheet = true
        }
    }


    @MainActor
    private func refreshAllBalances() {
        guard let keys else {
            showStatus("Generate keys to refresh balances.", tone: .info)
            return
        }

        balanceService.startBalanceFetch(for: keys)
        refreshTransactionHistory(force: true)
        showStatus("Refreshing balances…", tone: .info)
    }


    private func extractFiatPrice(from state: ChainPriceState) -> Double? {
        let value: String
        switch state {
        case .loaded(let string, _), .refreshing(let string, _), .stale(let string, _, _):
            value = string
        default:
            return nil
        }

        let filtered = value.filter { "0123456789.,-".contains($0) }
        guard !filtered.isEmpty else { return nil }
        let normalized = filtered.replacingOccurrences(of: ",", with: "")
        return Double(normalized)
    }

    @ViewBuilder
    private func walletActionButton(
        title: String,
        systemImage: String,
        color: Color,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title2)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .tint(prominent ? color : .secondary)
        .controlSize(.large)
    }

    private var newestBuildBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.caption)
            Text(AppVersion.displayVersion)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.green.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.green.opacity(0.45), lineWidth: 1)
        )
        .foregroundStyle(Color.green)
        .accessibilityLabel("\(AppVersion.displayVersion) indicator")
    }

    /// Shows pending (unconfirmed) transactions with live status updates
    @ViewBuilder
    private var pendingTransactionsSection: some View {
        let pending = pendingTransactions.filter { $0.status == .pending }
        if !pending.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Pending Transactions", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                    Spacer()
                    Text("\(pending.count)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
                
                VStack(spacing: 0) {
                    ForEach(pending) { tx in
                        PendingTransactionRow(
                            transaction: tx,
                            onSpeedUp: {
                                navigationVM.speedUpTransaction = tx
                            },
                            onCancel: {
                                navigationVM.cancelTransaction = tx
                            }
                        )
                        if tx.id != pending.last?.id {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(cardBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
        }
    }

    private var transactionHistorySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent Activity")
                        .font(.headline)
                    Text("Transaction history and events")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    if isHistoryLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                    
                    // Export button
                    if !historyEntries.isEmpty {
                        Menu {
                            Button {
                                let service = self.transactionHistoryService
                                if let result = service.exportHistoryAsCSV(entries: filteredHistoryEntries) {
                                    showStatus(result.message, tone: result.tone, autoClear: result.autoClear)
                                }
                            } label: {
                                Label("Export as CSV", systemImage: "tablecells")
                            }
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                                .labelStyle(.titleAndIcon)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .buttonStyle(.link)
                    }
                    
                    Button {
                        refreshTransactionHistory(force: true)
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.link)
                    .disabled(isHistoryLoading)
                }
            }
            
            // Search and Filter Controls
            historyFilterBar

            if let historyError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange.opacity(0.6))
                    Text("Unable to load history")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(historyError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        refreshTransactionHistory(force: true)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else if isHistoryLoading && historyEntries.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Fetching your latest transactions…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else if historyEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("No transactions yet")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Your activity will appear here once funds move.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                let filtered = filteredHistoryEntries
                if filtered.isEmpty && !historyEntries.isEmpty {
                    // No results match the filter
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary.opacity(0.5))
                        Text("No matching transactions")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Try adjusting your search or filters")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Clear Filters") {
                            historySearchText = ""
                            historyFilterChain = nil
                            historyFilterType = nil
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    VStack(spacing: 0) {
                        ForEach(filtered) { entry in
                            Button {
                                navigationVM.selectedTransactionForDetail = entry
                            } label: {
                                TransactionHistoryRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                            
                            if entry.id != filtered.last?.id {
                                Divider()
                                    .padding(.leading, 48)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    // MARK: - History Filter Bar
    private var historyFilterBar: some View {
        VStack(spacing: 8) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search transactions…", text: $historySearchText)
                    .textFieldStyle(.plain)
                if !historySearchText.isEmpty {
                    Button {
                        historySearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(8)
            
            // Filter chips
            HStack(spacing: 8) {
                // Chain filter
                Menu {
                    Button("All Chains") {
                        historyFilterChain = nil
                    }
                    Divider()
                    ForEach(uniqueHistoryChains, id: \.self) { chain in
                        Button(self.transactionHistoryService.chainDisplayName(chain)) {
                            historyFilterChain = chain
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                        Text(historyFilterChain.map { self.transactionHistoryService.chainDisplayName($0) } ?? "All Chains")
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(historyFilterChain != nil ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
                    .foregroundStyle(historyFilterChain != nil ? Color.accentColor : .primary)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                // Type filter
                Menu {
                    Button("All Types") {
                        historyFilterType = nil
                    }
                    Divider()
                    Button("Received") {
                        historyFilterType = "Received"
                    }
                    Button("Sent") {
                        historyFilterType = "Sent"
                    }
                    Button("Contract") {
                        historyFilterType = "Contract"
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right")
                        Text(historyFilterType ?? "All Types")
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(historyFilterType != nil ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
                    .foregroundStyle(historyFilterType != nil ? Color.accentColor : .primary)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Active filter count
                if hasActiveHistoryFilters {
                    Button {
                        historySearchText = ""
                        historyFilterChain = nil
                        historyFilterType = nil
                    } label: {
                        HStack(spacing: 4) {
                            Text("Clear")
                            Image(systemName: "xmark")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - History Filtering Logic
    private var hasActiveHistoryFilters: Bool {
        !historySearchText.isEmpty || historyFilterChain != nil || historyFilterType != nil
    }
    
    private var uniqueHistoryChains: [String] {
        let chains = Set(historyEntries.compactMap { $0.chainId })
        return chains.sorted()
    }
    
    private var filteredHistoryEntries: [HawalaTransactionEntry] {
        var entries = historyEntries
        
        // Filter by chain
        if let chain = historyFilterChain {
            entries = entries.filter { $0.chainId == chain }
        }
        
        // Filter by type
        if let type = historyFilterType {
            entries = entries.filter { $0.type == type }
        }
        
        // Filter by search text
        if !historySearchText.isEmpty {
            let searchLower = historySearchText.lowercased()
            entries = entries.filter { entry in
                entry.asset.lowercased().contains(searchLower) ||
                entry.amountDisplay.lowercased().contains(searchLower) ||
                (entry.txHash?.lowercased().contains(searchLower) ?? false) ||
                entry.timestamp.lowercased().contains(searchLower)
            }
        }
        
        return entries
    }
    
    private func showStatus(_ message: String, tone: StatusTone, autoClear: Bool = true) {
        statusTask?.cancel()
        statusTask = nil
        statusColor = tone.color
        statusMessage = message

        guard autoClear else { return }

        statusTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                statusMessage = nil
                statusTask = nil
            }
        }
    }

    /// Track a new pending transaction after broadcast
    private func trackPendingTransaction(
        txid: String,
        chainId: String,
        chainName: String,
        amount: String,
        recipient: String,
        isRBFEnabled: Bool = true, // Bitcoin txs have RBF enabled by default in Hawala
        feeRate: Int? = nil,
        nonce: Int? = nil
    ) {
        Task {
            await PendingTransactionManager.shared.add(
                txid: txid,
                chainId: chainId,
                chainName: chainName,
                amount: amount,
                recipient: recipient,
                isRBFEnabled: isRBFEnabled,
                feeRate: feeRate,
                nonce: nonce
            )
            await refreshPendingTransactions()
        }
    }

    /// Refresh pending transactions list from manager
    private func refreshPendingTransactions() async {
        let pending = await PendingTransactionManager.shared.getAll()
        await MainActor.run {
            pendingTransactions = pending
        }
    }

    /// Start periodic refresh of pending transactions
    private func startPendingTransactionRefresh() {
        pendingTxRefreshTask?.cancel()
        pendingTxRefreshTask = Task {
            while !Task.isCancelled {
                await refreshPendingTransactions()
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            }
        }
    }

    /// Handle a successful transaction broadcast
    private func handleTransactionSuccess(_ result: TransactionBroadcastResult) {
        navigationVM.sendChainContext = nil
        showStatus("Transaction broadcast: \(result.txid.prefix(16))...", tone: .success)
        trackPendingTransaction(
            txid: result.txid,
            chainId: result.chainId,
            chainName: result.chainName,
            amount: result.amount,
            recipient: result.recipient,
            isRBFEnabled: result.isRBFEnabled,
            feeRate: result.feeRate,
            nonce: result.nonce
        )
    }

    private func refreshTransactionHistory(force: Bool = false) {
        guard let keys else {
            historyEntries = []
            historyError = nil
            isHistoryLoading = false
            return
        }

        if isHistoryLoading && !force {
            return
        }

        historyFetchTask?.cancel()
        historyError = nil
        isHistoryLoading = true

        let targets = transactionHistoryService.historyTargets(from: keys)
        
        #if DEBUG
        print("📜 History targets: \(targets.map { "\($0.chainId): \($0.address.prefix(10))..." })")
        #endif
        
        if targets.isEmpty {
            isHistoryLoading = false
            historyEntries = []
            return
        }

        historyFetchTask = Task {
            let entries = await transactionHistoryService.fetchAllHistoryAsHawala(targets: targets, force: force)
            
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.historyEntries = entries
                self.isHistoryLoading = false
                self.historyError = transactionHistoryService.error
                self.historyFetchTask = nil
                #if DEBUG
                print("📜 History fetch complete: \(entries.count) total transactions")
                #endif
            }
        }
    }

    private func openSendSheet() {
        guard let keys else {
            showStatus("Generate keys before sending.", tone: .info)
            return
        }
        let available = SendFlowHelper.sendEligibleChains(from: keys)
        guard !available.isEmpty else {
            showStatus("No send-ready chains available yet.", tone: .info)
            return
        }
        navigationVM.pendingSendChain = nil
        navigationVM.sendChainContext = nil
        navigationVM.showSendPicker = true
    }
    
    private func openSendSheet(for chain: ChainInfo) {
        navigationVM.pendingSendChain = nil
        navigationVM.sendChainContext = chain
    }

    private func presentQueuedSendIfNeeded() {
        guard let chain = navigationVM.pendingSendChain else { return }
        navigationVM.pendingSendChain = nil
        navigationVM.sendChainContext = chain
    }



    private func loadKeysFromKeychain() {
        // Don't overwrite existing keys
        guard keys == nil else {
            #if DEBUG
            print("ℹ️ Keys already loaded, skipping Keychain load")
            #endif
            return
        }
        
        // Run Keychain access on a background thread to avoid blocking UI
        Task.detached(priority: .userInitiated) {
            do {
                let keychainResult = try KeychainHelper.loadKeys()
                
                await MainActor.run {
                    if let loadedKeys = keychainResult {
                        self.keys = loadedKeys
                        // Safely encode keys with error handling
                        if let encoded = try? JSONEncoder().encode(loadedKeys) {
                            self.rawJSON = self.backupService.prettyPrintedJSON(from: encoded)
                        }
                        self.priceService.primeStateCaches(for: loadedKeys, balanceService: self.balanceService, storedFiatCurrency: self.storedFiatCurrency)
                        #if DEBUG
                        print("✅ Loaded keys from Keychain")
                        print("🔑 Bitcoin Testnet Address: \(loadedKeys.bitcoinTestnet.address)")
                        #endif
                        
                        // Mark onboarding as completed since user has existing keys
                        if !self.onboardingCompleted {
                            self.onboardingCompleted = true
                            #if DEBUG
                            print("✅ Marking onboarding as completed (keys found in Keychain)")
                            #endif
                        }
                        
                        self.balanceService.startBalanceFetch(for: loadedKeys)
                        self.priceService.startPriceUpdatesIfNeeded(sparklineCache: self.sparklineCache)
                        self.refreshTransactionHistory(force: true)
                    } else {
                        #if DEBUG
                        print("ℹ️ No keys found in Keychain")
                        #endif
                    }
                }
            } catch {
                await MainActor.run {
                    #if DEBUG
                    print("⚠️ Failed to load keys from Keychain: \(error)")
                    #endif
                }
            }
        }
    }
    
    /// Load cached balances and prices for instant display on app startup
    private func loadCachedAssetData() {
        // Load from persistent cache
        for (chainId, cached) in assetCache.cachedBalances {
            // Use stale state if cache is old, otherwise show as loaded
            let age = Date().timeIntervalSince(cached.lastUpdated)
            if age < 300 { // 5 minutes
                cachedBalances[chainId] = CachedBalance(value: cached.balance, lastUpdated: cached.lastUpdated)
                balanceStates[chainId] = .loaded(value: cached.balance, lastUpdated: cached.lastUpdated)
            } else {
                cachedBalances[chainId] = CachedBalance(value: cached.balance, lastUpdated: cached.lastUpdated)
                balanceStates[chainId] = .stale(value: cached.balance, lastUpdated: cached.lastUpdated, message: "Updating...")
            }
        }
        
        for (chainId, cached) in assetCache.cachedPrices {
            let age = Date().timeIntervalSince(cached.lastUpdated)
            if age < 300 {
                priceService.cachedPrices[chainId] = CachedPrice(value: cached.price, lastUpdated: cached.lastUpdated)
                priceService.priceStates[chainId] = .loaded(value: cached.price, lastUpdated: cached.lastUpdated)
            } else {
                priceService.cachedPrices[chainId] = CachedPrice(value: cached.price, lastUpdated: cached.lastUpdated)
                priceService.priceStates[chainId] = .stale(value: cached.price, lastUpdated: cached.lastUpdated, message: "Updating...")
            }
        }
        
        #if DEBUG
        if !assetCache.cachedBalances.isEmpty {
            print("📦 Loaded \(assetCache.cachedBalances.count) cached balances, \(assetCache.cachedPrices.count) cached prices")
        }
        #endif
    }
    
    private func runGenerator() async {
        guard canAccessSensitiveData else { return }
        isGenerating = true
        errorMessage = nil
        statusTask?.cancel()
        statusTask = nil
        statusMessage = nil

        do {
            let (result, jsonString) = try await runRustKeyGenerator()
            await MainActor.run {
                // Prime states BEFORE setting keys to avoid race condition
                priceService.primeStateCaches(for: result, balanceService: balanceService, storedFiatCurrency: storedFiatCurrency)
                keys = result
                rawJSON = jsonString
                isGenerating = false
                
                #if DEBUG
                // Debug addresses (only in development)
                print("🔑 Generated Bitcoin Testnet Address: \(result.bitcoinTestnet.address)")
                print("🔑 Generated Bitcoin Mainnet Address: \(result.bitcoin.address)")
                #endif
                
                // Save to Keychain
                do {
                    try KeychainHelper.saveKeys(result)
                    #if DEBUG
                    print("✅ Keys saved to Keychain")
                    #endif
                } catch {
                    #if DEBUG
                    print("⚠️ Failed to save keys to Keychain: \(error)")
                    #endif
                }
                
                // Status message
                let cardCount = result.chainInfos.count
                let hasTestnet = result.bitcoinTestnet.address.starts(with: "tb1")
                let hasSepolia = result.ethereumSepolia.address.starts(with: "0x")
                let summary = "Generated \(cardCount) chains • Bitcoin testnet available: \(hasTestnet ? "yes" : "no") • Ethereum Sepolia available: \(hasSepolia ? "yes" : "no")"
                statusMessage = summary
                statusColor = .green
                
                balanceService.startBalanceFetch(for: result)
                priceService.startPriceUpdatesIfNeeded(sparklineCache: sparklineCache)
                refreshTransactionHistory(force: true)
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isGenerating = false
                // Show user-visible error toast
                showStatus("Failed to generate wallet: \(error.localizedDescription)", tone: .error, autoClear: false)
            }
        }
    }

    private func copyOutput() {
        guard !rawJSON.isEmpty, canAccessSensitiveData else { return }
        copySensitiveToClipboard(rawJSON)
    }

    private func copyToClipboard(_ text: String) {
        ClipboardHelper.copy(text)
        showStatus("Copied to clipboard.", tone: .success)
    }

    /// Copies sensitive data to clipboard with auto-clear after 60 seconds
    private func copySensitiveToClipboard(_ text: String) {
        ClipboardHelper.copySensitive(text, timeout: 60) {
            // Note: onClear callback fires after 60 seconds
            // The status message is shown immediately below
        }
        showStatus("Copied to clipboard. Will auto-clear in 60s.", tone: .success)
    }

    private func beginEncryptedImport() {
        guard hasAcknowledgedSecurityNotice else {
            navigationVM.showSecurityNotice = true
            return
        }

        guard canAccessSensitiveData else {
            navigationVM.showUnlockSheet = true
            return
        }

        backupService.beginEncryptedImport { [self] data in
            if let data {
                navigationVM.pendingImportData = data
                navigationVM.showImportPasswordPrompt = true
            }
        }
    }

    @MainActor
    private func finalizeEncryptedImport(with password: String) {
        guard let archiveData = navigationVM.pendingImportData else {
            showStatus("No backup selected.", tone: .error)
            return
        }

        #if DEBUG
        print("🔄 Starting encrypted import...")
        print("📦 Archive size: \(archiveData.count) bytes")
        #endif
        
        do {
            let importedKeys = try backupService.decryptAndDecode(archiveData: archiveData, password: password)
            let jsonString = try backupService.decryptToJSON(archiveData: archiveData, password: password)
            #if DEBUG
            print("✅ Keys decoded successfully")
            #endif
            
            keys = importedKeys
            rawJSON = jsonString
            
            #if DEBUG
            print("🔑 Imported Bitcoin Testnet Address: \(importedKeys.bitcoinTestnet.address)")
            print("🔑 Imported Bitcoin Mainnet Address: \(importedKeys.bitcoin.address)")
            #endif
            
            // Save to Keychain
            do {
                try KeychainHelper.saveKeys(importedKeys)
                #if DEBUG
                print("✅ Imported keys saved to Keychain")
                #endif
            } catch {
                #if DEBUG
                print("⚠️ Failed to save imported keys to Keychain: \(error)")
                #endif
            }
            
            priceService.primeStateCaches(for: importedKeys, balanceService: balanceService, storedFiatCurrency: storedFiatCurrency)
            balanceService.startBalanceFetch(for: importedKeys)
            priceService.startPriceUpdatesIfNeeded(sparklineCache: sparklineCache)
            refreshTransactionHistory(force: true)
            navigationVM.pendingImportData = nil
            showStatus("Encrypted backup imported successfully. Keys loaded.", tone: .success)
            #if DEBUG
            print("✅ Import complete - UI should now show keys")
            #endif
        } catch let DecodingError.keyNotFound(key, context) {
            #if DEBUG
            print("❌ Missing key: \(key.stringValue)")
            print("❌ Context: \(context.debugDescription)")
            print("❌ Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            #endif
            showStatus("Import failed: Missing required field '\(key.stringValue)'", tone: .error, autoClear: false)
        } catch let DecodingError.typeMismatch(type, context) {
            #if DEBUG
            print("❌ Type mismatch for type: \(type)")
            print("❌ Context: \(context.debugDescription)")
            print("❌ Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            #endif
            showStatus("Import failed: Invalid data format", tone: .error, autoClear: false)
        } catch {
            #if DEBUG
            print("❌ Import failed: \(error)")
            #endif
            showStatus("Import failed: \(error.localizedDescription)", tone: .error, autoClear: false)
        }
    }

    // Note: Cargo-related helper functions (resolveCargoExecutable, candidateCargoPaths, 
    // locateCargoWithWhich, mergedEnvironment) have been removed as key generation now
    // uses FFI instead of spawning cargo processes.

    private func runRustKeyGenerator() async throws -> (AllKeys, String) {
        // Use FFI-based key generation instead of spawning cargo process
        // This is more reliable, faster, and doesn't require cargo to be installed
        return try await Task.detached {
            let jsonString = RustService.shared.generateKeys()
            
            guard let jsonData = jsonString.data(using: .utf8) else {
                throw KeyGeneratorError.executionFailed("Invalid UTF-8 output from generator")
            }
            
            // Check for API response format
            if let apiResponse = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let success = apiResponse["success"] as? Bool {
                if !success {
                    if let error = apiResponse["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        throw KeyGeneratorError.executionFailed(message)
                    }
                    throw KeyGeneratorError.executionFailed("Key generation failed")
                }
                // Extract data from API response
                if let dataObj = apiResponse["data"],
                   let dataJson = try? JSONSerialization.data(withJSONObject: dataObj) {
                    let decoder = JSONDecoder()
                    let response = try decoder.decode(WalletResponse.self, from: dataJson)
                    let formattedJson = String(data: dataJson, encoding: .utf8) ?? jsonString
                    return (response.keys, formattedJson)
                }
            }
            
            // Try direct WalletResponse format (legacy)
            let decoder = JSONDecoder()
            let response = try decoder.decode(WalletResponse.self, from: jsonData)
            return (response.keys, jsonString)
        }.value
    }

    @MainActor
    private func clearSensitiveData() {
        keys = nil
        rawJSON = ""
        navigationVM.selectedChain = nil
        navigationVM.sendChainContext = nil
        statusTask?.cancel()
        statusTask = nil
        statusMessage = nil
        errorMessage = nil
        navigationVM.pendingImportData = nil
    navigationVM.pendingSendChain = nil
        navigationVM.showSendPicker = false
        navigationVM.showReceiveSheet = false
        navigationVM.showAllPrivateKeysSheet = false
        navigationVM.showImportPrivateKeySheet = false
    historyFetchTask?.cancel()
    historyFetchTask = nil
    historyEntries = []
    historyError = nil
    isHistoryLoading = false
        balanceService.cancelBalanceFetchTasks()
        balanceStates.removeAll()
        cachedBalances.removeAll()
        balanceBackoff.removeAll()
        priceService.resetState()
        priceService.stopPriceUpdates()

        do {
            try KeychainHelper.deleteKeys()
            #if DEBUG
            print("✅ Keys deleted from Keychain")
            #endif
        } catch {
            #if DEBUG
            print("⚠️ Failed to delete keys from Keychain: \(error)")
            #endif
        }
    }

    @MainActor
    private func prepareSecurityState() {
        if !hasAcknowledgedSecurityNotice {
            navigationVM.showSecurityNotice = true
        }

        guard storedPasscodeHash != nil else {
            isUnlocked = true
            return
        }

        if navigationVM.completedOnboardingThisSession {
            isUnlocked = true
            navigationVM.showUnlockSheet = false
            navigationVM.completedOnboardingThisSession = false
        } else if !isUnlocked {
            navigationVM.showUnlockSheet = true
        }
    }
    
    // MARK: - Keyboard Shortcuts Setup (ROADMAP-03)
    
    @MainActor
    private func setupKeyboardShortcutCallbacks() {
        let commands = NavigationCommandsManager.shared
        
        // ⌘, - Open Settings
        commands.onOpenSettings = { [self] in
            navigationVM.showSettingsPanel = true
        }
        
        // ⌘R - Refresh data
        commands.onRefresh = { [self] in
            if let keys = keys {
                balanceService.startBalanceFetch(for: keys)
                refreshTransactionHistory(force: true)
                sparklineCache.fetchAllSparklines()
            }
        }
        
        // ⌘N - New transaction (Send)
        commands.onNewTransaction = { [self] in
            if keys != nil {
                navigationVM.showSendPicker = true
            }
        }
        
        // ⌘? - Show help/shortcuts
        commands.onShowHelp = { [self] in
            navigationVM.showKeyboardShortcutsHelp = true
        }
        
        // ⌘⇧R - Receive
        commands.onReceive = { [self] in
            if keys != nil {
                navigationVM.showReceiveSheet = true
            }
        }
        
        // ⌘H - Toggle history
        commands.onToggleHistory = { [self] in
            navigationVM.showTransactionHistorySheet.toggle()
        }
    }

    @MainActor
    private func triggerAutoGenerationIfNeeded() {
        guard navigationVM.shouldAutoGenerateAfterOnboarding else { return }
        guard hasAcknowledgedSecurityNotice else { return }
        guard canAccessSensitiveData else { return }
        guard !isGenerating else { return }

        navigationVM.shouldAutoGenerateAfterOnboarding = false

        Task {
            await runGenerator()
        }
    }

    private var selectedFiatCurrency: FiatCurrency {
        FiatCurrency(rawValue: storedFiatCurrency) ?? .usd
    }

    @MainActor
    private func handleScenePhase(_ phase: ScenePhase) {
        // Delegate security handling to ViewModel
        securityVM.handleScenePhase(phase)
        
        // App-specific phase handling
        switch phase {
        case .active:
            priceService.startPriceUpdatesIfNeeded(sparklineCache: sparklineCache)
            if storedPasscodeHash != nil && !isUnlocked {
                navigationVM.showUnlockSheet = true
            }
        case .inactive:
            break
        case .background:
            priceService.stopPriceUpdates()
            clearSensitiveData()
            if storedPasscodeHash != nil {
                isUnlocked = false
            }
        @unknown default:
            break
        }
    }








    
    /// Reveal private keys with optional biometric authentication
    @MainActor
    private func revealPrivateKeysWithBiometric() async {
        // Check biometric authentication if enabled
        if BiometricAuthHelper.shouldRequireBiometric(settingEnabled: biometricForKeyReveal) {
            let result = await BiometricAuthHelper.authenticate(reason: "Authenticate to view private keys")
            switch result {
            case .success:
                break // Continue to show keys
            case .cancelled:
                return // User cancelled
            case .failed(let message):
                showStatus("Authentication failed: \(message)", tone: .error)
                return
            case .notAvailable:
                break // Biometric not available, continue anyway
            }
        }
        
        navigationVM.showAllPrivateKeysSheet = true
    }

}

// BitcoinUTXO, BitcoinFeeEstimates, EthGasSpeed, EthGasEstimates, and BitcoinSendError
// are defined in Models/FeeModels.swift

// Preview disabled - use Xcode previews instead
// #Preview {
//     ContentView()
// }
