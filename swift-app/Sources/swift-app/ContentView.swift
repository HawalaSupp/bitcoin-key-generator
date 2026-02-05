import SwiftUI
import CryptoKit
import UniformTypeIdentifiers
import Security
import LocalAuthentication
import P256K
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// Types are defined in Models/AppTypes.swift and Models/ChainKeys.swift

struct ContentView: View {
    @State private var showSplashScreen = true
    @State private var keys: AllKeys?
    @State private var rawJSON: String = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var statusColor: Color = .green
    @State private var statusTask: Task<Void, Never>?
    @State private var selectedChain: ChainInfo?
    @AppStorage("hawala.securityAcknowledged") private var hasAcknowledgedSecurityNotice = false
    @AppStorage("hawala.passcodeHash") private var storedPasscodeHash: String?
    @AppStorage("hawala.onboardingCompleted") private var onboardingCompleted = false
    @AppStorage("hawala.appearanceMode") private var storedAppearanceMode = AppearanceMode.system.rawValue
    @AppStorage("hawala.biometricUnlockEnabled") private var biometricUnlockEnabled = false
    @AppStorage("hawala.biometricForSends") private var biometricForSends = true
    @AppStorage("hawala.biometricForKeyReveal") private var biometricForKeyReveal = true
    @AppStorage("hawala.autoLockInterval") private var storedAutoLockInterval: Double = AutoLockIntervalOption.fiveMinutes.rawValue
    @AppStorage("hawala.selectedFiatCurrency") private var storedFiatCurrency = FiatCurrency.usd.rawValue
    @State private var fxRates: [String: Double] = [:] // Currency code -> rate (relative to USD)
    @State private var fxRatesFetchTask: Task<Void, Never>?
    @State private var isUnlocked = false
    @State private var showSecurityNotice = false
    @State private var showSecuritySettings = false
    @State private var showUnlockSheet = false
    @State private var showExportPasswordPrompt = false
    @State private var showImportPasswordPrompt = false
    @State private var pendingImportData: Data?
    @State private var showImportPrivateKeySheet = false
    @State private var onboardingStep: OnboardingStep = .welcome
    @State private var completedOnboardingThisSession = false
    @State private var shouldAutoGenerateAfterOnboarding = false
    @State private var hasResetOnboardingState = false
    @State private var balanceStates: [String: ChainBalanceState] = [:]
    @State private var priceStates: [String: ChainPriceState] = [:]
    @State private var cachedBalances: [String: CachedBalance] = [:]
    @State private var balanceBackoff: [String: BackoffTracker] = [:]
    @State private var balanceFetchTasks: [String: Task<Void, Never>] = [:]
    @State private var cachedPrices: [String: CachedPrice] = [:]
    @State private var priceBackoffTracker = BackoffTracker()
    @State private var priceUpdateTask: Task<Void, Never>?
    @StateObject private var sparklineCache = SparklineCache.shared
    @StateObject private var assetCache = AssetCache.shared
    @StateObject private var transactionHistoryService = TransactionHistoryService.shared
    @State private var showAllPrivateKeysSheet = false
    @State private var showSettingsPanel = false
    @State private var showContactsSheet = false
    @State private var showStakingSheet = false
    @State private var showNotificationsSheet = false
    @State private var showMultisigSheet = false
    @State private var showHardwareWalletSheet = false
    @State private var showWatchOnlySheet = false
    @State private var showWalletConnectSheet = false
    @State private var showReceiveSheet = false
    @State private var showSendPicker = false
    @State private var showBatchTransactionSheet = false
    // Phase 3 Feature Sheets
    @State private var showL2AggregatorSheet = false
    @State private var showPaymentLinksSheet = false
    @State private var showTransactionNotesSheet = false
    @State private var showSellCryptoSheet = false
    @State private var showPriceAlertsSheet = false
    // Phase 4 Feature Sheets (ERC-4337 Account Abstraction)
    @State private var showSmartAccountSheet = false
    @State private var showGasAccountSheet = false
    @State private var showPasskeyAuthSheet = false
    @State private var showGaslessTxSheet = false
    @State private var sendChainContext: ChainInfo?
    @State private var pendingSendChain: ChainInfo?
    @State private var showSeedPhraseSheet = false
    @State private var showTransactionHistorySheet = false
    @State private var historyEntries: [HawalaTransactionEntry] = []
    @State private var historyError: String?
    @State private var isHistoryLoading = false
    @State private var historyFetchTask: Task<Void, Never>?
    // History filtering
    @State private var historySearchText: String = ""
    @State private var historyFilterChain: String? = nil
    @State private var historyFilterType: String? = nil
    @State private var selectedTransactionForDetail: HawalaTransactionEntry?
    @State private var pendingTransactions: [PendingTransactionManager.PendingTransaction] = []
    @State private var pendingTxRefreshTask: Task<Void, Never>?
    @State private var speedUpTransaction: PendingTransactionManager.PendingTransaction?
    @State private var cancelTransaction: PendingTransactionManager.PendingTransaction?
    @State private var viewportWidth: CGFloat = 900
    @State private var biometricState: BiometricState = .unknown
    @State private var lastActivityTimestamp = Date()
    @State private var autoLockTask: Task<Void, Never>?
    @State private var showPrivacyBlur = false
    // Debug: Show FPS performance overlay in DEBUG builds
    #if DEBUG
    @State private var showPerformanceOverlay = false  // Disabled for screenshot
    #endif
    #if canImport(AppKit)
    @State private var activityMonitor: UserActivityMonitor?
    #endif
    private let moneroBalancePlaceholder = "View-only · Open Monero GUI wallet for full access"
    private let trackedPriceChainIDs = [
        "bitcoin", "bitcoin-testnet", "ethereum", "ethereum-sepolia", "litecoin", "monero",
        "solana", "xrp", "bnb", "usdt-erc20", "usdc-erc20", "dai-erc20"
    ]
    private let sendEnabledChainIDs: Set<String> = [
        "bitcoin", "bitcoin-testnet", "litecoin", "ethereum", "ethereum-sepolia", "bnb", "solana"
    ]
    // CoinGecko free API: ~10-30 calls/min without key, ~30 calls/min with demo key
    // We poll prices every 2 minutes to stay well under limits
    private let pricePollingInterval: TimeInterval = 120
    // Optional: Set your CoinGecko Demo API key here for higher rate limits
    // Get a free key at: https://www.coingecko.com/en/api/pricing (Demo tier is free)
    private let coingeckoAPIKey: String? = nil // e.g. "CG-xxxxxxxxxxxxxxxxxxxx"
    private let minimumBalanceRetryDelay: TimeInterval = 0.5
    private static var cachedWorkspaceRoot: URL?
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
                    recordActivity()
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
                    attemptBiometricUnlock(reason: "Unlock Hawala")
                }
            }
        )
    }

    private var biometricDisplayInfo: (label: String, icon: String) {
        if case .available(let kind) = biometricState {
            return (kind.displayName, kind.iconName)
        }
        return ("Biometrics", "lock.circle")
    }

    var body: some View {
        ZStack {
            // Splash screen overlay
            if showSplashScreen {
                HawalaSplashView(isShowingSplash: $showSplashScreen)
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
            .opacity(showSplashScreen ? 0 : 1)
        }
        #if DEBUG
        .onAppear {
            // Enable with environment variable: HAWALA_PERF_OVERLAY=1
            if ProcessInfo.processInfo.environment["HAWALA_PERF_OVERLAY"] == "1" {
                showPerformanceOverlay = true
            }
        }
        #endif
        .animation(.easeInOut(duration: 0.3), value: showSplashScreen)
        .animation(.easeInOut(duration: 0.3), value: onboardingCompleted)
        .animation(.easeInOut(duration: 0.3), value: onboardingStep)
        .preferredColorScheme(appearanceMode.colorScheme)
        .onAppear {
            guard !hasResetOnboardingState else { return }
            onboardingCompleted = false
            onboardingStep = .welcome
            shouldAutoGenerateAfterOnboarding = false
            balanceStates.removeAll()
            priceStates.removeAll()
            cachedBalances.removeAll()
            cachedPrices.removeAll()
            balanceBackoff.removeAll()
            priceBackoffTracker = BackoffTracker()
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

    @State private var showKeyboardShortcutsHelp = false  // ROADMAP-03: Keyboard shortcuts help sheet
    
    private var mainAppStage: some View {
        ZStack {
            // New modern UI
            if selectedChain == nil {
                HawalaMainView(
                    keys: $keys,
                    selectedChain: $selectedChain,
                    balanceStates: $balanceStates,
                    priceStates: $priceStates,
                    sparklineCache: sparklineCache,
                    showSendPicker: $showSendPicker,
                    showReceiveSheet: $showReceiveSheet,
                    showSettingsPanel: $showSettingsPanel,
                    showStakingSheet: $showStakingSheet,
                    showNotificationsSheet: $showNotificationsSheet,
                    showContactsSheet: $showContactsSheet,
                    showWalletConnectSheet: $showWalletConnectSheet,
                    showL2AggregatorSheet: $showL2AggregatorSheet,
                    showPaymentLinksSheet: $showPaymentLinksSheet,
                    showTransactionNotesSheet: $showTransactionNotesSheet,
                    showSellCryptoSheet: $showSellCryptoSheet,
                    showPriceAlertsSheet: $showPriceAlertsSheet,
                    // Phase 4: Account Abstraction
                    showSmartAccountSheet: $showSmartAccountSheet,
                    showGasAccountSheet: $showGasAccountSheet,
                    showPasskeyAuthSheet: $showPasskeyAuthSheet,
                    showGaslessTxSheet: $showGaslessTxSheet,
                    onGenerateKeys: {
                        // Auto-acknowledge security notice for streamlined UX
                        if !hasAcknowledgedSecurityNotice {
                            hasAcknowledgedSecurityNotice = true
                        }
                        guard canAccessSensitiveData else {
                            showUnlockSheet = true
                            return
                        }
                        Task { await runGenerator() }
                    },
                    onRefreshBalances: {
                        if let keys = keys {
                            startBalanceFetch(for: keys)
                        }
                    },
                    onRefreshHistory: {
                        refreshTransactionHistory(force: true)
                    },
                    selectedFiatSymbol: selectedFiatCurrency.symbol,
                    fxRates: fxRates,
                    selectedFiatCurrency: storedFiatCurrency,
                    isGenerating: isGenerating,
                    historyEntries: $historyEntries,
                    isHistoryLoading: $isHistoryLoading,
                    historyError: $historyError
                )
            } else if let chain = selectedChain {
                HawalaAssetDetailView(
                    chain: chain,
                    balanceState: Binding(
                        get: { balanceStates[chain.id] },
                        set: { balanceStates[chain.id] = $0 ?? .idle }
                    ),
                    priceState: Binding(
                        get: { priceStates[chain.id] },
                        set: { priceStates[chain.id] = $0 ?? .idle }
                    ),
                    sparklineData: sparklineCache.sparklines[chain.id] ?? [],
                    onSend: {
                        pendingSendChain = chain
                        selectedChain = nil
                    },
                    onReceive: {
                        showReceiveSheet = true
                    },
                    onClose: {
                        withAnimation(HawalaTheme.Animation.fast) {
                            selectedChain = nil
                        }
                    },
                    selectedFiatSymbol: selectedFiatCurrency.symbol,
                    fxMultiplier: fxRates[storedFiatCurrency] ?? 1.0
                )
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(HawalaTheme.Colors.background)
        .preferredColorScheme(.dark)
        // ROADMAP-03: Keyboard shortcuts help sheet
        .sheet(isPresented: $showKeyboardShortcutsHelp) {
            KeyboardShortcutsHelpView()
                .hawalaModal(allowSwipeDismiss: true) // OK to swipe-dismiss help
        }
        // ROADMAP-03: Setup keyboard shortcut callbacks
        .onAppear {
            setupKeyboardShortcutCallbacks()
        }
        .sheet(isPresented: $showAllPrivateKeysSheet) {
            if let keys {
                AllPrivateKeysSheet(chains: keys.chainInfos, onCopy: copySensitiveToClipboard)
                    .hawalaModal() // Prevent accidental dismiss of sensitive info
            } else {
                NoKeysPlaceholderView()
            }
        }
        .sheet(isPresented: $showReceiveSheet) {
            if let keys {
                ReceiveViewModern(chains: keys.chainInfos, onCopy: copyToClipboard)
                    .frame(minWidth: 500, minHeight: 650)
                    .hawalaModal(allowSwipeDismiss: true) // OK to swipe-dismiss receive
            } else {
                NoKeysPlaceholderView()
            }
        }
        .sheet(item: $sendChainContext, onDismiss: { sendChainContext = nil }) { chain in
            if let keys {
                SendView(keys: keys, initialChain: mapToChain(chain.id), onSuccess: { result in
                    handleTransactionSuccess(result)
                })
                .hawalaModal() // CRITICAL: Prevent accidental dismiss during transaction
            } else {
                Text("Keys not available")
            }
        }

        .sheet(isPresented: $showSendPicker, onDismiss: presentQueuedSendIfNeeded) {
            if let keys {
                SendAssetPickerSheet(
                    chains: sendEligibleChains(from: keys),
                    onSelect: { chain in
                        pendingSendChain = chain
                        showSendPicker = false
                    },
                    onBatchSend: {
                        showSendPicker = false
                        showBatchTransactionSheet = true
                    },
                    onDismiss: {
                        showSendPicker = false
                    }
                )
            }
        }
        .sheet(isPresented: $showSeedPhraseSheet) {
            SeedPhraseSheet(onCopy: { value in
                copyToClipboard(value)
            })
            .hawalaModal() // CRITICAL: Prevent accidental dismiss of seed phrase
        }
        .sheet(isPresented: $showTransactionHistorySheet) {
            TransactionHistoryView()
                .frame(minWidth: 500, minHeight: 600)
                .hawalaModal(allowSwipeDismiss: true) // OK to swipe-dismiss history
        }
        .sheet(item: $selectedTransactionForDetail) { transaction in
            TransactionDetailSheet(transaction: transaction)
                .hawalaModal(allowSwipeDismiss: true) // OK to swipe-dismiss detail
        }
        .sheet(item: $speedUpTransaction) { tx in
            if let keys {
                TransactionCancellationSheet(
                    pendingTx: tx,
                    keys: keys,
                    initialMode: .speedUp,
                    onDismiss: {
                        speedUpTransaction = nil
                    },
                    onSuccess: { newTxid in
                        speedUpTransaction = nil
                        showStatus("Transaction sped up: \(newTxid.prefix(16))...", tone: .success)
                        Task { await refreshPendingTransactions() }
                    }
                )
                .hawalaModal() // CRITICAL: Prevent accidental dismiss during speed-up
            }
        }
        .sheet(item: $cancelTransaction) { tx in
            if let keys {
                TransactionCancellationSheet(
                    pendingTx: tx,
                    keys: keys,
                    initialMode: .cancel,
                    onDismiss: {
                        cancelTransaction = nil
                    },
                    onSuccess: { newTxid in
                        cancelTransaction = nil
                        showStatus("Transaction cancelled: \(newTxid.prefix(16))...", tone: .success)
                        Task { await refreshPendingTransactions() }
                    }
                )
                .hawalaModal() // CRITICAL: Prevent accidental dismiss during cancel
            }
        }
        .sheet(isPresented: $showContactsSheet) {
            ContactsView()
        }
        .sheet(isPresented: $showStakingSheet) {
            StakingView()
        }
        .sheet(isPresented: $showNotificationsSheet) {
            NotificationsView()
        }
        .sheet(isPresented: $showMultisigSheet) {
            MultisigView()
        }
        .sheet(isPresented: $showHardwareWalletSheet) {
            HardwareWalletView()
        }
        .sheet(isPresented: $showWatchOnlySheet) {
            WatchOnlyView()
        }
        .sheet(isPresented: $showWalletConnectSheet) {
            WalletConnectView(
                availableAccounts: getEvmAccounts(),
                onSign: { request in
                    try await handleWalletConnectSign(request)
                }
            )
        }
        // Phase 3 Feature Sheets
        .sheet(isPresented: $showL2AggregatorSheet) {
            if let ethAddress = keys?.chainInfos.first(where: { $0.id == "ethereum" })?.receiveAddress {
                L2BalanceAggregatorView(address: ethAddress)
            } else {
                L2BalanceAggregatorView(address: "")
            }
        }
        .sheet(isPresented: $showPaymentLinksSheet) {
            PaymentLinksView()
        }
        .sheet(isPresented: $showTransactionNotesSheet) {
            TransactionNotesView()
        }
        .sheet(isPresented: $showSellCryptoSheet) {
            SellCryptoView()
        }
        .sheet(isPresented: $showPriceAlertsSheet) {
            PriceAlertsView()
        }
        // Phase 4: ERC-4337 Account Abstraction Sheets
        .sheet(isPresented: $showSmartAccountSheet) {
            SmartAccountView()
        }
        .sheet(isPresented: $showGasAccountSheet) {
            GasAccountView()
        }
        .sheet(isPresented: $showPasskeyAuthSheet) {
            PasskeyAuthView()
        }
        .sheet(isPresented: $showGaslessTxSheet) {
            GaslessTxView()
        }
        .sheet(isPresented: $showBatchTransactionSheet) {
            BatchTransactionView()
        }
        .sheet(isPresented: $showSettingsPanel) {
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
                        showSecuritySettings = true
                    }
                },
                selectedCurrency: $storedFiatCurrency,
                onCurrencyChanged: {
                    // Refresh FX rates and prices when currency changes
                    startFXRatesFetch()
                    Task {
                        await fetchAndStorePrices()
                    }
                }
            )
        }
        .sheet(isPresented: $showSecurityNotice) {
            SecurityNoticeView {
                hasAcknowledgedSecurityNotice = true
                showSecurityNotice = false
            }
        }
        .sheet(isPresented: $showSecuritySettings) {
            SecuritySettingsView(
                hasPasscode: storedPasscodeHash != nil,
                onSetPasscode: { passcode in
                    storedPasscodeHash = hashPasscode(passcode)
                    lock()
                    showSecuritySettings = false
                },
                onRemovePasscode: {
                    storedPasscodeHash = nil
                    isUnlocked = true
                    showSecuritySettings = false
                },
                biometricState: biometricState,
                biometricEnabled: biometricToggleBinding,
                biometricForSends: $biometricForSends,
                biometricForKeyReveal: $biometricForKeyReveal,
                autoLockSelection: autoLockSelectionBinding,
                onBiometricRequest: {
                    attemptBiometricUnlock(reason: "Unlock Hawala")
                }
            )
        }
        .sheet(isPresented: $showUnlockSheet) {
            UnlockView(
                supportsBiometrics: biometricUnlockEnabled && biometricState.supportsUnlock && storedPasscodeHash != nil,
                biometricButtonLabel: biometricDisplayInfo.label,
                biometricButtonIcon: biometricDisplayInfo.icon,
                onBiometricRequest: {
                    attemptBiometricUnlock(reason: "Unlock Hawala")
                },
                onSubmit: { candidate in
                    guard let expected = storedPasscodeHash else { return nil }
                    let hashed = hashPasscode(candidate)
                    if hashed == expected {
                        isUnlocked = true
                        showUnlockSheet = false
                        recordActivity()
                        return nil
                    }
                    return "Incorrect passcode. Try again."
                },
                onCancel: {
                    showUnlockSheet = false
                }
            )
        }
        .sheet(isPresented: $showExportPasswordPrompt) {
            PasswordPromptView(
                mode: .export,
                onConfirm: { password in
                    showExportPasswordPrompt = false
                    performEncryptedExport(with: password)
                },
                onCancel: {
                    showExportPasswordPrompt = false
                }
            )
        }
        .sheet(isPresented: $showImportPasswordPrompt) {
            PasswordPromptView(
                mode: .import,
                onConfirm: { password in
                    showImportPasswordPrompt = false
                    finalizeEncryptedImport(with: password)
                },
                onCancel: {
                    showImportPasswordPrompt = false
                    pendingImportData = nil
                }
            )
        }
        .sheet(isPresented: $showImportPrivateKeySheet) {
            ImportPrivateKeySheet(
                onImport: { privateKey, chainType in
                    showImportPrivateKeySheet = false
                    Task {
                        await importPrivateKey(privateKey, for: chainType)
                    }
                },
                onCancel: {
                    showImportPrivateKeySheet = false
                }
            )
        }
        .overlay {
            // Privacy blur overlay when app goes to background/inactive
            if showPrivacyBlur {
                PrivacyBlurOverlay()
                    .transition(.opacity)
            }
        }
        .onAppear {
            prepareSecurityState()
            triggerAutoGenerationIfNeeded()
            startPriceUpdatesIfNeeded()
            refreshBiometricAvailability()
            startActivityMonitoringIfNeeded()
            recordActivity()
        }
        .onChange(of: storedPasscodeHash) { _ in
            handlePasscodeChange()
        }
        .onChange(of: scenePhase) { phase in
            handleScenePhase(phase)
        }
        .onChange(of: shouldAutoGenerateAfterOnboarding) { newValue in
            if newValue {
                triggerAutoGenerationIfNeeded()
            }
        }
        .onChange(of: onboardingCompleted) { completed in
            if completed {
                startPriceUpdatesIfNeeded()
            } else {
                stopPriceUpdates()
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
    
    @MainActor
    private func handleOnboardingComplete(_ result: WalletCreationResult) async {
        // Set all the necessary flags
        hasAcknowledgedSecurityNotice = true
        isUnlocked = true
        shouldAutoGenerateAfterOnboarding = false
        completedOnboardingThisSession = true
        
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
                showSecurityNotice = true
            }
        } else if !canAccessSensitiveData {
            LockedStateView {
                showUnlockSheet = true
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
                        
                        LazyVGrid(columns: gridColumns(for: viewportWidth), spacing: 14) {
                            ForEach(keys.chainInfos) { chain in
                                Button {
                                    guard canAccessSensitiveData else {
                                        showUnlockSheet = true
                                        return
                                    }
                                    selectedChain = chain
                                } label: {
                                    let balance = balanceStates[chain.id] ?? defaultBalanceState(for: chain.id)
                                    let price = priceStates[chain.id] ?? defaultPriceState(for: chain.id)
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
                        .animation(cardAnimation, value: viewportWidth)
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
                viewportWidth = width
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
        priceStates.reduce(0) { partial, entry in
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
        .frame(maxWidth: headerMaxWidth(for: viewportWidth))
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
        return formatFiatAmountInSelectedCurrency(total)
    }

    private var priceStatusLine: String {
        if priceStates.isEmpty {
            return "Fetching live prices…"
        }

        if priceStates.values.contains(where: { state in
            if case .loading = state { return true }
            return false
        }) {
            return "Fetching live prices…"
        }
        if priceStates.values.contains(where: { state in
            if case .refreshing = state { return true }
            return false
        }) {
            return "Refreshing live prices…"
        }

        if priceStates.values.contains(where: { state in
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
        priceStates.values.compactMap { state in
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
            let balanceState = balanceStates[chain.id] ?? defaultBalanceState(for: chain.id)
            let priceState = priceStates[chain.id] ?? defaultPriceState(for: chain.id)

            guard
                let balance = extractNumericAmount(from: balanceState),
                let price = extractFiatPrice(from: priceState)
            else { continue }

            hasValue = true
            accumulator += balance * price
        }

        return hasValue ? (accumulator, true) : (nil, false)
    }

    @ViewBuilder
    private var actionButtonsRow: some View {
        if viewportWidth < 620 {
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
            showReceiveSheet = true
        }
        .disabled(keys == nil)

        walletActionButton(
            title: "View Keys",
            systemImage: "doc.richtext",
            color: .blue
        ) {
            guard canAccessSensitiveData else {
                showUnlockSheet = true
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
            showExportPasswordPrompt = true
        }
        .disabled(keys == nil)

        walletActionButton(
            title: "Seed Phrase",
            systemImage: "list.number.rtl",
            color: .purple
        ) {
            showSeedPhraseSheet = true
        }
        
        walletActionButton(
            title: "History",
            systemImage: "clock.arrow.circlepath",
            color: .cyan
        ) {
            showTransactionHistorySheet = true
        }
    }


    @MainActor
    private func refreshAllBalances() {
        guard let keys else {
            showStatus("Generate keys to refresh balances.", tone: .info)
            return
        }

        startBalanceFetch(for: keys)
        refreshTransactionHistory(force: true)
        showStatus("Refreshing balances…", tone: .info)
    }

    private func extractNumericAmount(from state: ChainBalanceState) -> Double? {
        let value: String
        switch state {
        case .loaded(let loadedValue, _), .refreshing(let loadedValue, _), .stale(let loadedValue, _, _):
            value = loadedValue
        default:
            return nil
        }

        let raw = value.split(separator: " ").first.map(String.init) ?? value
        let cleaned = raw.replacingOccurrences(of: ",", with: "")
        return Double(cleaned)
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
                                speedUpTransaction = tx
                            },
                            onCancel: {
                                cancelTransaction = tx
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
                                exportHistoryAsCSV()
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
                                selectedTransactionForDetail = entry
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
                        Button(chainDisplayName(chain)) {
                            historyFilterChain = chain
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                        Text(historyFilterChain.map { chainDisplayName($0) } ?? "All Chains")
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
    
    private func chainDisplayName(_ chainId: String) -> String {
        switch chainId {
        case "bitcoin": return "Bitcoin"
        case "bitcoin-testnet": return "Bitcoin Testnet"
        case "litecoin": return "Litecoin"
        case "ethereum": return "Ethereum"
        case "ethereum-sepolia": return "Ethereum Sepolia"
        case "bnb": return "BNB Chain"
        case "solana": return "Solana"
        case "solana-devnet": return "Solana Devnet"
        case "xrp": return "XRP"
        case "xrp-testnet": return "XRP Testnet"
        case "monero": return "Monero"
        default: return chainId.capitalized
        }
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
    
    // MARK: - Export Transaction History
    private func exportHistoryAsCSV() {
        let entries = filteredHistoryEntries
        guard !entries.isEmpty else { return }
        
        // Build CSV content
        var csv = "Date,Type,Asset,Amount,Status,Fee,Confirmations,TX Hash,Chain\n"
        
        for entry in entries {
            let date = entry.timestamp.replacingOccurrences(of: ",", with: ";")
            let type = entry.type
            let asset = entry.asset
            let amount = entry.amountDisplay.replacingOccurrences(of: ",", with: "")
            let status = entry.status
            let fee = entry.fee ?? ""
            let confirmations = entry.confirmations.map { String($0) } ?? ""
            let txHash = entry.txHash ?? ""
            let chain = entry.chainId ?? ""
            
            csv += "\"\(date)\",\"\(type)\",\"\(asset)\",\"\(amount)\",\"\(status)\",\"\(fee)\",\"\(confirmations)\",\"\(txHash)\",\"\(chain)\"\n"
        }
        
        #if canImport(AppKit)
        let savePanel = NSSavePanel()
        savePanel.title = "Export Transaction History"
        savePanel.message = "Save your transaction history as a CSV file"
        savePanel.nameFieldStringValue = "hawala_transactions_\(formattedExportDate()).csv"
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.canCreateDirectories = true
        
        let response = savePanel.runModal()
        if response == .OK, let url = savePanel.url {
            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
                showStatus("Exported \(entries.count) transactions to \(url.lastPathComponent)", tone: .success)
            } catch {
                showStatus("Export failed: \(error.localizedDescription)", tone: .error)
            }
        }
        #endif
    }
    
    private func formattedExportDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    // Using shared HawalaTransactionEntry from Models/TransactionModels.swift

    private struct TransactionHistoryRow: View {
        let entry: HawalaTransactionEntry
        @State private var isHovered = false
        @State private var isExpanded = false
        @State private var noteText: String = ""
        @State private var isEditingNote = false

        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: iconForType(entry.type))
                        .font(.title3)
                        .foregroundStyle(colorForType(entry.type))
                        .frame(width: 36, height: 36)
                        .background(colorForType(entry.type).opacity(0.15))
                        .clipShape(Circle())
                    
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(entry.asset)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            if hasNote {
                                Image(systemName: "note.text")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        HStack(spacing: 4) {
                            Text(entry.timestamp)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let confs = entry.confirmationsDisplay {
                                Text("•")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(confs)
                                    .font(.caption)
                                    .foregroundStyle(confirmationsColor)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(entry.amountDisplay)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(amountColor)
                        HStack(spacing: 4) {
                            if let fee = entry.fee {
                                Text("Fee: \(fee)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.status)
                                .font(.caption)
                                .foregroundStyle(statusColor)
                            if hasDetails {
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHovered = hovering
                }
                .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
                .cornerRadius(6)
                .onTapGesture {
                    if hasDetails {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    }
                }
                
                // Expandable details section
                if isExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        Divider()
                            .padding(.leading, 48)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                if let hash = entry.txHash {
                                    HStack(spacing: 4) {
                                        Text("TX Hash:")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(String(hash.prefix(16)) + "..." + String(hash.suffix(8)))
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.primary)
                                        Button {
                                            #if canImport(AppKit)
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(hash, forType: .string)
                                            #endif
                                        } label: {
                                            Image(systemName: "doc.on.doc")
                                                .font(.caption2)
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                                
                                if let block = entry.blockNumber {
                                    HStack(spacing: 4) {
                                        Text("Block:")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text("#\(block)")
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.primary)
                                    }
                                }
                                
                                if let fee = entry.fee {
                                    HStack(spacing: 4) {
                                        Text("Network Fee:")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(fee)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.primary)
                                    }
                                }
                                
                                // Note/Label section
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 4) {
                                        Text("Note:")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        if !isEditingNote {
                                            Button {
                                                isEditingNote = true
                                            } label: {
                                                Image(systemName: "pencil")
                                                    .font(.caption2)
                                            }
                                            .buttonStyle(.plain)
                                            .foregroundStyle(.secondary)
                                        }
                                    }
                                    
                                    if isEditingNote {
                                        HStack {
                                            TextField("Add a note...", text: $noteText)
                                                .textFieldStyle(.roundedBorder)
                                                .font(.caption)
                                                .frame(maxWidth: 200)
                                            
                                            Button("Save") {
                                                if let hash = entry.txHash {
                                                    TransactionNotesManager.shared.setNote(noteText, for: hash)
                                                }
                                                isEditingNote = false
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .controlSize(.small)
                                            
                                            Button("Cancel") {
                                                noteText = entry.txHash.flatMap { TransactionNotesManager.shared.getNote(for: $0) } ?? ""
                                                isEditingNote = false
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                    } else if let hash = entry.txHash, let note = TransactionNotesManager.shared.getNote(for: hash), !note.isEmpty {
                                        Text(note)
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                            .italic()
                                    } else {
                                        Text("No note")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary.opacity(0.5))
                                    }
                                }
                                .padding(.top, 4)
                            }
                            
                            Spacer()
                            
                            if let url = entry.explorerURL {
                                Button {
                                    #if canImport(AppKit)
                                    NSWorkspace.shared.open(url)
                                    #elseif canImport(UIKit)
                                    UIApplication.shared.open(url)
                                    #endif
                                } label: {
                                    Label("View in Explorer", systemImage: "arrow.up.right.square")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(.leading, 48)
                        .padding(.vertical, 8)
                    }
                }
            }
            .onAppear {
                if let hash = entry.txHash {
                    noteText = TransactionNotesManager.shared.getNote(for: hash) ?? ""
                }
            }
        }
        
        private var hasNote: Bool {
            guard let hash = entry.txHash else { return false }
            return TransactionNotesManager.shared.getNote(for: hash) != nil
        }
        
        private var hasDetails: Bool {
            entry.txHash != nil || entry.fee != nil || entry.blockNumber != nil
        }
        
        private var confirmationsColor: Color {
            guard let confs = entry.confirmations else { return .secondary }
            if confs >= 6 {
                return .green
            } else if confs >= 3 {
                return .orange
            } else {
                return .yellow
            }
        }
        
        private var statusColor: Color {
            switch entry.status.lowercased() {
            case "confirmed", "success": return .green
            case "pending": return .orange
            case "failed": return .red
            default: return .secondary
            }
        }
        
        private func iconForType(_ type: String) -> String {
            switch type {
            case "Receive": return "arrow.down.circle.fill"
            case "Send": return "paperplane.fill"
            case "Swap": return "arrow.left.arrow.right.circle.fill"
            case "Stake": return "chart.bar.fill"
            case "Transaction": return "arrow.left.arrow.right"
            default: return "circle.fill"
            }
        }
        
        private func colorForType(_ type: String) -> Color {
            switch type {
            case "Receive": return .green
            case "Send": return .orange
            case "Swap": return .blue
            case "Stake": return .purple
            case "Transaction": return .gray
            default: return .gray
            }
        }
        
        private var amountColor: Color {
            if entry.amountDisplay.hasPrefix("+") {
                return .green
            } else if entry.amountDisplay.hasPrefix("-") {
                return .red
            }
            return .primary
        }
    }

    /// Row view for pending transactions with explorer link and speed-up option
    private struct PendingTransactionRow: View {
        let transaction: PendingTransactionManager.PendingTransaction
        let onSpeedUp: (() -> Void)?
        let onCancel: (() -> Void)?
        
        init(transaction: PendingTransactionManager.PendingTransaction, onSpeedUp: (() -> Void)? = nil, onCancel: (() -> Void)? = nil) {
            self.transaction = transaction
            self.onSpeedUp = onSpeedUp
            self.onCancel = onCancel
        }
        
        private var timeAgo: String {
            let interval = Date().timeIntervalSince(transaction.timestamp)
            if interval < 60 {
                return "Just now"
            } else if interval < 3600 {
                let mins = Int(interval / 60)
                return "\(mins)m ago"
            } else {
                let hours = Int(interval / 3600)
                return "\(hours)h ago"
            }
        }
        
        var body: some View {
            HStack(spacing: 12) {
                // Animated pending indicator
                ZStack {
                    Circle()
                        .stroke(Color.orange.opacity(0.3), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.orange)
                )
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(transaction.chainName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("To: \(String(transaction.recipient.prefix(8)))...\(String(transaction.recipient.suffix(6)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 3) {
                    Text("-\(transaction.amount)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.orange)
                    
                    HStack(spacing: 6) {
                        // Cancel button if available
                        if transaction.canSpeedUp, let cancel = onCancel {
                            Button {
                                cancel()
                            } label: {
                                Label("Cancel", systemImage: "xmark.circle.fill")
                                    .font(.caption2)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .tint(.red)
                        }
                        
                        // Speed Up button if available
                        if transaction.canSpeedUp, let speedUp = onSpeedUp {
                            Button {
                                speedUp()
                            } label: {
                                Label("Speed Up", systemImage: "bolt.fill")
                                    .font(.caption2)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .tint(.orange)
                        }
                        
                        Text(transaction.displayStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if let url = transaction.explorerURL {
                            Link(destination: url) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 10)
        }
    }

    private struct BitcoinHistoryItem: Decodable {
        let txid: String
        let amountSats: Int64
        let confirmed: Bool
        let timestamp: UInt64?
        let height: UInt64?
        let feeSats: UInt64?
    }

    private struct HistoryChainTarget {
        let id: String
        let address: String
        let displayName: String
        let symbol: String
    }

    private enum StatusTone {
        case success
        case info
        case error

        var color: Color {
            switch self {
            case .success: return .green
            case .info: return .blue
            case .error: return .red
            }
        }
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
        sendChainContext = nil
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

        // Convert to service's HistoryTarget format
        let targets = historyTargets(from: keys).map { target in
            HistoryTarget(
                chainId: target.id,
                address: target.address,
                displayName: target.displayName,
                symbol: target.symbol
            )
        }
        
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

    private func historyTargets(from keys: AllKeys) -> [HistoryChainTarget] {
        var targets: [HistoryChainTarget] = []

        func appendTarget(id: String, address: String, displayName: String, symbol: String) {
            guard !address.isEmpty else { return }
            // Don't dedupe by address - each chain has its own history even if address is same
            targets.append(HistoryChainTarget(id: id, address: address, displayName: displayName, symbol: symbol))
        }

        appendTarget(id: "bitcoin", address: keys.bitcoin.address, displayName: "Bitcoin", symbol: "BTC")
        appendTarget(id: "bitcoin-testnet", address: keys.bitcoinTestnet.address, displayName: "Bitcoin Testnet", symbol: "tBTC")
        appendTarget(id: "litecoin", address: keys.litecoin.address, displayName: "Litecoin", symbol: "LTC")
        // For EVM chains, use ethereum address (same key works on all EVM networks)
        let evmAddress = keys.ethereum.address.isEmpty ? keys.ethereumSepolia.address : keys.ethereum.address
        appendTarget(id: "ethereum", address: evmAddress, displayName: "Ethereum", symbol: "ETH")
        appendTarget(id: "ethereum-sepolia", address: evmAddress, displayName: "Ethereum Sepolia", symbol: "ETH")
        appendTarget(id: "bnb", address: keys.bnb.address.isEmpty ? evmAddress : keys.bnb.address, displayName: "BNB Chain", symbol: "BNB")
        // Use same address for both mainnet and devnet Solana
        appendTarget(id: "solana", address: keys.solana.publicKeyBase58, displayName: "Solana", symbol: "SOL")
        appendTarget(id: "solana-devnet", address: keys.solana.publicKeyBase58, displayName: "Solana Devnet", symbol: "SOL")
        // Use same address for both mainnet and testnet XRP
        appendTarget(id: "xrp", address: keys.xrp.classicAddress, displayName: "XRP Ledger", symbol: "XRP")
        appendTarget(id: "xrp-testnet", address: keys.xrp.classicAddress, displayName: "XRP Testnet", symbol: "XRP")

        return targets
    }
    
    // MARK: - WalletConnect Helpers
    
    /// Get all EVM-compatible addresses for WalletConnect
    private func getEvmAccounts() -> [String] {
        guard let keys = keys else { return [] }
        
        var accounts: [String] = []
        
        // Ethereum mainnet
        if !keys.ethereum.address.isEmpty {
            accounts.append("eip155:1:\(keys.ethereum.address)")
        }
        
        // Ethereum Sepolia testnet
        if !keys.ethereumSepolia.address.isEmpty {
            accounts.append("eip155:11155111:\(keys.ethereumSepolia.address)")
        }
        
        // BSC (BNB Chain)
        if !keys.bnb.address.isEmpty {
            accounts.append("eip155:56:\(keys.bnb.address)")
        }
        
        // Add more EVM chains as needed - they typically share the same address
        let evmAddress = keys.ethereum.address.isEmpty ? keys.ethereumSepolia.address : keys.ethereum.address
        if !evmAddress.isEmpty {
            accounts.append("eip155:137:\(evmAddress)")   // Polygon
            accounts.append("eip155:42161:\(evmAddress)") // Arbitrum
            accounts.append("eip155:10:\(evmAddress)")    // Optimism
            accounts.append("eip155:43114:\(evmAddress)") // Avalanche
        }
        
        return accounts
    }
    
    /// Handle WalletConnect signing requests
    private func handleWalletConnectSign(_ request: WCSessionRequest) async throws -> String {
        // Extract the method and params
        let method = request.method
        
        // For now, we'll return a placeholder - full implementation would
        // use the wallet's private keys to sign the message/transaction
        switch method {
        case "personal_sign", "eth_sign":
            // Sign a message
            return try await signPersonalMessage(request)
            
        case "eth_signTypedData", "eth_signTypedData_v3", "eth_signTypedData_v4":
            // Sign typed data (EIP-712)
            return try await signTypedData(request)
            
        case "eth_sendTransaction", "eth_signTransaction":
            // Sign/send a transaction
            return try await signTransaction(request)
            
        default:
            throw WCError.userRejected
        }
    }
    
    /// Sign a personal message (eth_sign, personal_sign)
    private func signPersonalMessage(_ request: WCSessionRequest) async throws -> String {
        // Extract message from params
        guard let params = request.params as? [Any],
              params.count >= 2,
              let message = params[1] as? String else {
            throw WCError.requestTimeout
        }
        
        // Get the Ethereum private key
        guard let keys = self.keys else {
            throw WCError.userRejected
        }
        
        let privateKeyHex = keys.ethereum.privateHex.isEmpty ? keys.ethereumSepolia.privateHex : keys.ethereum.privateHex
        guard !privateKeyHex.isEmpty else {
            throw WCError.userRejected
        }
        
        #if DEBUG
        print("📝 WalletConnect: Personal sign request for message: \(message)")
        #endif
        
        // Decode message (could be hex or plain text)
        let messageBytes: Data
        if message.hasPrefix("0x") {
            // Hex-encoded message - proper hex decoding
            let hexString = String(message.dropFirst(2))
            var data = Data()
            var index = hexString.startIndex
            while index < hexString.endIndex {
                let nextIndex = hexString.index(index, offsetBy: 2, limitedBy: hexString.endIndex) ?? hexString.endIndex
                if let byte = UInt8(hexString[index..<nextIndex], radix: 16) {
                    data.append(byte)
                }
                index = nextIndex
            }
            messageBytes = data
        } else {
            messageBytes = Data(message.utf8)
        }
        
        // Create Ethereum signed message hash: keccak256("\x19Ethereum Signed Message:\n" + len(message) + message)
        let prefix = "\u{19}Ethereum Signed Message:\n\(messageBytes.count)"
        var prefixedMessage = Data(prefix.utf8)
        prefixedMessage.append(messageBytes)
        
        // Use keccak256
        let messageHash = Keccak256.hash(data: prefixedMessage)
        
        // Sign with secp256k1
        return try signWithSecp256k1(hash: messageHash, privateKeyHex: privateKeyHex)
    }
    
    /// Sign typed data (EIP-712)
    private func signTypedData(_ request: WCSessionRequest) async throws -> String {
        guard let params = request.params as? [Any],
              params.count >= 2 else {
            throw WCError.requestTimeout
        }
        
        // Get the Ethereum private key
        guard let keys = self.keys else {
            throw WCError.userRejected
        }
        
        let privateKeyHex = keys.ethereum.privateHex.isEmpty ? keys.ethereumSepolia.privateHex : keys.ethereum.privateHex
        guard !privateKeyHex.isEmpty else {
            throw WCError.userRejected
        }
        
        #if DEBUG
        print("📝 WalletConnect: Typed data sign request")
        #endif
        
        // Extract typed data JSON
        let typedDataJSON: String
        if let jsonStr = params[1] as? String {
            typedDataJSON = jsonStr
        } else if let jsonDict = params[1] as? [String: Any],
                  let jsonData = try? JSONSerialization.data(withJSONObject: jsonDict),
                  let str = String(data: jsonData, encoding: .utf8) {
            typedDataJSON = str
        } else {
            throw WCError.requestTimeout
        }
        
        // For EIP-712, we need to compute the struct hash
        // This is a simplified implementation - full EIP-712 requires domain separator + struct hash
        let hash = Keccak256.hash(data: Data(typedDataJSON.utf8))
        
        return try signWithSecp256k1(hash: hash, privateKeyHex: privateKeyHex)
    }
    
    /// Sign or send a transaction
    private func signTransaction(_ request: WCSessionRequest) async throws -> String {
        guard let params = request.params as? [[String: Any]],
              let txParams = params.first else {
            throw WCError.requestTimeout
        }
        
        #if DEBUG
        print("📝 WalletConnect: Transaction sign request")
        print("   From: \(txParams["from"] ?? "unknown")")
        print("   To: \(txParams["to"] ?? "unknown")")
        print("   Value: \(txParams["value"] ?? "0")")
        print("   Data: \(txParams["data"] ?? "0x")")
        #endif
        
        // For transaction signing, we should use the SendView flow
        // For now, return error to indicate user should use app's send UI
        throw WCError.userRejected
    }
    
    /// Sign a hash using secp256k1 and return Ethereum-compatible signature
    private func signWithSecp256k1(hash: Data, privateKeyHex: String) throws -> String {
        // Parse private key
        let cleanHex = privateKeyHex.hasPrefix("0x") ? String(privateKeyHex.dropFirst(2)) : privateKeyHex
        var privKeyData = Data()
        var index = cleanHex.startIndex
        while index < cleanHex.endIndex {
            let nextIndex = cleanHex.index(index, offsetBy: 2, limitedBy: cleanHex.endIndex) ?? cleanHex.endIndex
            if let byte = UInt8(cleanHex[index..<nextIndex], radix: 16) {
                privKeyData.append(byte)
            }
            index = nextIndex
        }
        
        guard privKeyData.count == 32 else {
            throw WCError.userRejected
        }
        
        // Sign using P256K (secp256k1)
        let privKey = try P256K.Signing.PrivateKey(dataRepresentation: privKeyData)
        
        // Use P256K's HashDigest for pre-hashed data
        let digest = HashDigest(Array(hash))
        let signature = try privKey.signature(for: digest)
        
        // Get DER encoded signature and extract r,s components
        let derSig = try signature.derRepresentation
        
        // Parse DER signature to extract r and s values
        // DER format: 0x30 [total-length] 0x02 [r-length] [r] 0x02 [s-length] [s]
        guard derSig.count >= 8,
              derSig[0] == 0x30,
              derSig[2] == 0x02 else {
            throw WCError.userRejected
        }
        
        let rLength = Int(derSig[3])
        let rStart = 4
        var rData = Data(derSig[rStart..<(rStart + rLength)])
        
        // Skip the 0x02 marker and s length
        let sLengthIndex = rStart + rLength + 1
        guard derSig.count > sLengthIndex else {
            throw WCError.userRejected
        }
        let sLength = Int(derSig[sLengthIndex])
        let sStart = sLengthIndex + 1
        var sData = Data(derSig[sStart..<(sStart + sLength)])
        
        // Remove leading zero padding if present (DER uses it for positive numbers starting with high bit)
        if rData.count == 33 && rData[0] == 0x00 {
            rData = Data(rData.dropFirst())
        }
        if sData.count == 33 && sData[0] == 0x00 {
            sData = Data(sData.dropFirst())
        }
        
        // Pad to 32 bytes if shorter
        while rData.count < 32 { rData.insert(0x00, at: 0) }
        while sData.count < 32 { sData.insert(0x00, at: 0) }
        
        // Recovery ID (v) - typically 27 or 28 for Ethereum
        let v: UInt8 = 27
        
        // Format: 0x + r (32 bytes) + s (32 bytes) + v (1 byte)
        return "0x" + rData.map { String(format: "%02x", $0) }.joined() +
               sData.map { String(format: "%02x", $0) }.joined() +
               String(format: "%02x", v)
    }
    
    private func openSendSheet() {
        guard let keys else {
            showStatus("Generate keys before sending.", tone: .info)
            return
        }
        let available = sendEligibleChains(from: keys)
        guard !available.isEmpty else {
            showStatus("No send-ready chains available yet.", tone: .info)
            return
        }
        pendingSendChain = nil
        sendChainContext = nil
        showSendPicker = true
    }
    
    private func openSendSheet(for chain: ChainInfo) {
        pendingSendChain = nil
        sendChainContext = chain
    }

    private func presentQueuedSendIfNeeded() {
        guard let chain = pendingSendChain else { return }
        pendingSendChain = nil
        sendChainContext = chain
    }

    private func mapToChain(_ chainId: String) -> Chain {
        if chainId == "bitcoin-testnet" { return .bitcoinTestnet }
        if chainId == "bitcoin" || chainId == "bitcoin-mainnet" { return .bitcoinMainnet }
        if chainId == "ethereum-sepolia" { return .ethereumSepolia }
        if chainId == "ethereum" || chainId == "ethereum-mainnet" { return .ethereumMainnet }
        if chainId == "polygon" { return .polygon }
        if chainId == "bnb" { return .bnb }
        if chainId == "solana-devnet" { return .solanaDevnet }
        if chainId == "solana" || chainId == "solana-mainnet" { return .solanaMainnet }
        if chainId == "xrp-testnet" { return .xrpTestnet }
        if chainId == "xrp" || chainId == "xrp-mainnet" { return .xrpMainnet }
        if chainId == "monero" { return .monero }
        return .bitcoinTestnet
    }

    private func sendEligibleChains(from keys: AllKeys) -> [ChainInfo] {
        keys.chainInfos.filter { chain in
            isSendSupported(chainID: chain.id)
        }
    }

    private func isSendSupported(chainID: String) -> Bool {
        if sendEnabledChainIDs.contains(chainID) { return true }
        if chainID.contains("erc20") { return true }
        return false
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
                            self.rawJSON = self.prettyPrintedJSON(from: encoded)
                        }
                        self.primeStateCaches(for: loadedKeys)
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
                        
                        self.startBalanceFetch(for: loadedKeys)
                        self.startPriceUpdatesIfNeeded()
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
                cachedPrices[chainId] = CachedPrice(value: cached.price, lastUpdated: cached.lastUpdated)
                priceStates[chainId] = .loaded(value: cached.price, lastUpdated: cached.lastUpdated)
            } else {
                cachedPrices[chainId] = CachedPrice(value: cached.price, lastUpdated: cached.lastUpdated)
                priceStates[chainId] = .stale(value: cached.price, lastUpdated: cached.lastUpdated, message: "Updating...")
            }
        }
        
        #if DEBUG
        if !assetCache.cachedBalances.isEmpty {
            print("📦 Loaded \(assetCache.cachedBalances.count) cached balances, \(assetCache.cachedPrices.count) cached prices")
        }
        #endif
    }
    
    /// Save balance to persistent cache
    private func saveBalanceToCache(chainId: String, balance: String) {
        // Extract numeric value from balance string (e.g., "0.001 BTC" -> 0.001)
        let numericValue = extractNumericValue(from: balance)
        assetCache.cacheBalance(chainId: chainId, balance: balance, numericValue: numericValue)
    }
    
    /// Save price to persistent cache
    private func savePriceToCache(chainId: String, price: String, numericValue: Double, change24h: Double? = nil) {
        assetCache.cachePrice(chainId: chainId, price: price, numericValue: numericValue, change24h: change24h)
    }
    
    /// Extract numeric value from a formatted balance string
    private func extractNumericValue(from balance: String) -> Double {
        // Remove currency symbols and extract number
        let cleaned = balance.components(separatedBy: CharacterSet.decimalDigits.inverted.subtracting(CharacterSet(charactersIn: ".")))
            .joined()
        return Double(cleaned) ?? 0
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
                primeStateCaches(for: result)
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
                
                startBalanceFetch(for: result)
                startPriceUpdatesIfNeeded()
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

    private func performEncryptedExport(with password: String) {
        guard let keys else {
            showStatus("Nothing to export yet.", tone: .info)
            return
        }

        do {
            let archive = try buildEncryptedArchive(from: keys, password: password)
#if canImport(AppKit)
            DispatchQueue.main.async {
                let panel = NSSavePanel()
                var contentTypes: [UTType] = [.json]
                let customTypes = ["hawala", "hawbackup"].compactMap { UTType(filenameExtension: $0) }
                contentTypes.append(contentsOf: customTypes)
                panel.allowedContentTypes = contentTypes
                panel.nameFieldStringValue = defaultExportFileName()
                panel.title = "Save Encrypted Hawala Backup"
                panel.canCreateDirectories = true

                panel.begin { response in
                    if response == .OK, let url = panel.url {
                        do {
                            try archive.write(to: url)
                            self.showStatus("Encrypted backup saved to \(url.lastPathComponent)", tone: .success)
                        } catch {
                            self.showStatus("Failed to write file: \(error.localizedDescription)", tone: .error, autoClear: false)
                        }
                    }
                }
            }
#else
            showStatus("Encrypted export is only supported on macOS.", tone: .error, autoClear: false)
#endif
        } catch {
            showStatus("Export failed: \(error.localizedDescription)", tone: .error, autoClear: false)
        }
    }

    private func beginEncryptedImport() {
        guard hasAcknowledgedSecurityNotice else {
            showSecurityNotice = true
            return
        }

        guard canAccessSensitiveData else {
            showUnlockSheet = true
            return
        }

#if canImport(AppKit)
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            var contentTypes: [UTType] = [.json]
            let customTypes = ["hawala", "hawbackup"].compactMap { UTType(filenameExtension: $0) }
            contentTypes.append(contentsOf: customTypes)
            panel.allowedContentTypes = contentTypes
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.title = "Open Encrypted Hawala Backup"

            panel.begin { response in
                if response == .OK, let url = panel.url {
                    do {
                        let data = try Data(contentsOf: url)
                        self.pendingImportData = data
                        self.showImportPasswordPrompt = true
                    } catch {
                        self.showStatus("Failed to read file: \(error.localizedDescription)", tone: .error, autoClear: false)
                    }
                }
            }
        }
#else
        showStatus("Encrypted import is only supported on macOS.", tone: .error, autoClear: false)
#endif
    }

    @MainActor
    private func finalizeEncryptedImport(with password: String) {
        guard let archiveData = pendingImportData else {
            showStatus("No backup selected.", tone: .error)
            return
        }

        #if DEBUG
        print("🔄 Starting encrypted import...")
        print("📦 Archive size: \(archiveData.count) bytes")
        #endif
        
        do {
            let plaintext = try decryptArchive(archiveData, password: password)
            #if DEBUG
            print("✅ Decryption successful, plaintext size: \(plaintext.count) bytes")
            
            // Debug: print first 200 characters of JSON (only in development)
            if let jsonString = String(data: plaintext, encoding: .utf8) {
                print("📄 JSON preview: \(String(jsonString.prefix(200)))...")
            }
            #endif
            
            let decoder = JSONDecoder()
            // Don't use convertFromSnakeCase because AllKeys already has custom CodingKeys
            let importedKeys = try decoder.decode(AllKeys.self, from: plaintext)
            #if DEBUG
            print("✅ Keys decoded successfully")
            #endif
            
            keys = importedKeys
            rawJSON = prettyPrintedJSON(from: plaintext)
            
            #if DEBUG
            // Debug imported addresses (only in development)
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
            
            primeStateCaches(for: importedKeys)
            startBalanceFetch(for: importedKeys)
            startPriceUpdatesIfNeeded()
            refreshTransactionHistory(force: true)
            pendingImportData = nil
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

    private func buildEncryptedArchive(from keys: AllKeys, password: String) throws -> Data {
        let encoder = JSONEncoder()
        // Don't use convertToSnakeCase because AllKeys already has custom CodingKeys
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let plaintext = try encoder.encode(keys)
        let envelope = try encryptPayload(plaintext, password: password)
        let archiveEncoder = JSONEncoder()
        archiveEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        archiveEncoder.dateEncodingStrategy = .iso8601
        return try archiveEncoder.encode(envelope)
    }

    private func decryptArchive(_ data: Data, password: String) throws -> Data {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(EncryptedPackage.self, from: data)
        return try decryptPayload(envelope, password: password)
    }

    private func encryptPayload(_ plaintext: Data, password: String) throws -> EncryptedPackage {
        let salt = randomData(count: 16)
        let key = deriveSymmetricKey(password: password, salt: salt)
        let nonce = try AES.GCM.Nonce(data: randomData(count: 12))
        let sealedBox = try AES.GCM.seal(plaintext, using: key, nonce: nonce)

        return EncryptedPackage(
            formatVersion: 1,
            createdAt: Date(),
            salt: salt.base64EncodedString(),
            nonce: Data(nonce).base64EncodedString(),
            ciphertext: sealedBox.ciphertext.base64EncodedString(),
            tag: sealedBox.tag.base64EncodedString()
        )
    }

    private func decryptPayload(_ envelope: EncryptedPackage, password: String) throws -> Data {
        guard
            let salt = Data(base64Encoded: envelope.salt),
            let nonceData = Data(base64Encoded: envelope.nonce),
            let ciphertext = Data(base64Encoded: envelope.ciphertext),
            let tag = Data(base64Encoded: envelope.tag)
        else {
            throw SecureArchiveError.invalidEnvelope
        }

        let key = deriveSymmetricKey(password: password, salt: salt)
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        return try AES.GCM.open(sealedBox, using: key)
    }

    private func deriveSymmetricKey(password: String, salt: Data) -> SymmetricKey {
        let passwordKey = SymmetricKey(data: Data(password.utf8))
        return HKDF<CryptoKit.SHA256>.deriveKey(
            inputKeyMaterial: passwordKey,
            salt: salt,
            info: Data("hawala-key-backup".utf8),
            outputByteCount: 32
        )
    }

    private func randomData(count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: 0...255) })
    }
    
    @MainActor
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

    private func defaultExportFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "hawala-backup-\(formatter.string(from: Date())).hawala"
    }

    private func prettyPrintedJSON(from data: Data) -> String {
        guard
            let jsonObject = try? JSONSerialization.jsonObject(with: data),
            let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
            let prettyString = String(data: prettyData, encoding: .utf8)
        else {
            return String(data: data, encoding: .utf8) ?? ""
        }

        return prettyString
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
        selectedChain = nil
        sendChainContext = nil
        statusTask?.cancel()
        statusTask = nil
        statusMessage = nil
        errorMessage = nil
        pendingImportData = nil
    pendingSendChain = nil
        showSendPicker = false
        showReceiveSheet = false
        showAllPrivateKeysSheet = false
        showImportPrivateKeySheet = false
    historyFetchTask?.cancel()
    historyFetchTask = nil
    historyEntries = []
    historyError = nil
    isHistoryLoading = false
        cancelBalanceFetchTasks()
        balanceStates.removeAll()
        cachedBalances.removeAll()
        balanceBackoff.removeAll()
        cachedPrices.removeAll()
        priceStates.removeAll()
        priceBackoffTracker = BackoffTracker()
        stopPriceUpdates()

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
            showSecurityNotice = true
        }

        guard storedPasscodeHash != nil else {
            isUnlocked = true
            return
        }

        if completedOnboardingThisSession {
            isUnlocked = true
            showUnlockSheet = false
            completedOnboardingThisSession = false
        } else if !isUnlocked {
            showUnlockSheet = true
        }
    }
    
    // MARK: - Keyboard Shortcuts Setup (ROADMAP-03)
    
    @MainActor
    private func setupKeyboardShortcutCallbacks() {
        let commands = NavigationCommandsManager.shared
        
        // ⌘, - Open Settings
        commands.onOpenSettings = { [self] in
            showSettingsPanel = true
        }
        
        // ⌘R - Refresh data
        commands.onRefresh = { [self] in
            if let keys = keys {
                startBalanceFetch(for: keys)
                refreshTransactionHistory(force: true)
                sparklineCache.fetchAllSparklines()
            }
        }
        
        // ⌘N - New transaction (Send)
        commands.onNewTransaction = { [self] in
            if keys != nil {
                showSendPicker = true
            }
        }
        
        // ⌘? - Show help/shortcuts
        commands.onShowHelp = { [self] in
            showKeyboardShortcutsHelp = true
        }
        
        // ⌘⇧R - Receive
        commands.onReceive = { [self] in
            if keys != nil {
                showReceiveSheet = true
            }
        }
        
        // ⌘H - Toggle history
        commands.onToggleHistory = { [self] in
            showTransactionHistorySheet.toggle()
        }
    }

    @MainActor
    private func triggerAutoGenerationIfNeeded() {
        guard shouldAutoGenerateAfterOnboarding else { return }
        guard hasAcknowledgedSecurityNotice else { return }
        guard canAccessSensitiveData else { return }
        guard !isGenerating else { return }

        shouldAutoGenerateAfterOnboarding = false

        Task {
            await runGenerator()
        }
    }

    @MainActor
    private func startPriceUpdatesIfNeeded() {
        guard onboardingCompleted else { return }
        ensurePriceStateEntries()
        // Also fetch FX rates and sparklines when starting price updates
        startFXRatesFetch()
        sparklineCache.apiKey = coingeckoAPIKey
        sparklineCache.fetchAllSparklines()
        if priceUpdateTask == nil {
            markPriceStatesLoading()
            priceUpdateTask = Task {
                await priceUpdateLoop()
            }
        } else {
            Task {
                await fetchAndStorePrices()
            }
        }
    }

    @MainActor
    private func stopPriceUpdates() {
        priceUpdateTask?.cancel()
        priceUpdateTask = nil
        priceBackoffTracker = BackoffTracker()
    }

    @MainActor
    private func markPriceStatesLoading() {
        for id in trackedPriceChainIDs {
            applyPriceLoadingState(for: id)
        }
    }

    private func priceUpdateLoop() async {
        while !Task.isCancelled {
            let (succeeded, wasRateLimited) = await fetchAndStorePrices()
            let delay = await MainActor.run { () -> TimeInterval in
                if succeeded {
                    priceBackoffTracker.registerSuccess()
                    return pricePollingInterval
                } else if wasRateLimited {
                    // On rate limit, wait longer (minimum 3 minutes)
                    let backoff = priceBackoffTracker.registerFailure()
                    return max(180, backoff)
                } else {
                    return priceBackoffTracker.registerFailure()
                }
            }

            let clampedDelay = max(30, delay) // Minimum 30 seconds between retries
            let nanos = UInt64(clampedDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
        }
    }

    private func fetchAndStorePrices() async -> (success: Bool, rateLimited: Bool) {
        do {
            let snapshot = try await fetchPriceSnapshot()
            let now = Date()
            await MainActor.run {
                updatePriceStates(with: snapshot, timestamp: now)
            }
            return (true, false)
        } catch BalanceFetchError.rateLimited {
            // On rate limit, keep cached prices but mark as stale
            await MainActor.run {
                applyPriceStaleState(message: "Rate limited - retrying soon")
            }
            return (false, true)
        } catch {
            await MainActor.run {
                applyPriceFailureState(message: error.localizedDescription)
            }
            return (false, false)
        }
    }

    @MainActor
    private func applyPriceStaleState(message: String) {
        for chainId in trackedPriceChainIDs {
            if let cache = cachedPrices[chainId] {
                priceStates[chainId] = .stale(value: cache.value, lastUpdated: cache.lastUpdated, message: message)
            }
        }
    }

    @MainActor
    private func updatePriceStates(with snapshot: [String: Double], timestamp: Date) {
        for chainId in trackedPriceChainIDs {
            if let staticDisplay = staticPriceDisplay(for: chainId) {
                cachedPrices[chainId] = CachedPrice(value: staticDisplay, lastUpdated: timestamp)
                priceStates[chainId] = .loaded(value: staticDisplay, lastUpdated: timestamp)
                // Save static prices to persistent cache
                savePriceToCache(chainId: chainId, price: staticDisplay, numericValue: 0)
                continue
            }

            guard let identifiers = priceIdentifiers(for: chainId) else { continue }
            guard let priceValue = identifiers.compactMap({ snapshot[$0] }).first else {
                if let cache = cachedPrices[chainId] {
                    priceStates[chainId] = .stale(value: cache.value, lastUpdated: cache.lastUpdated, message: "Price unavailable.")
                } else {
                    priceStates[chainId] = .failed("Price unavailable.")
                }
                continue
            }

            let display = formatFiatAmountInSelectedCurrency(priceValue)
            cachedPrices[chainId] = CachedPrice(value: display, lastUpdated: timestamp)
            priceStates[chainId] = .loaded(value: display, lastUpdated: timestamp)
            // Save to persistent cache
            savePriceToCache(chainId: chainId, price: display, numericValue: priceValue)
        }
    }

    private func priceIdentifiers(for chainId: String) -> [String]? {
        switch chainId {
        case "bitcoin":
            return ["bitcoin"]
        case "ethereum":
            return ["ethereum"]
        case "litecoin":
            return ["litecoin"]
        case "monero":
            return ["monero"]
        case "solana":
            return ["solana"]
        case "xrp":
            return ["ripple", "xrp"]
        case "bnb":
            return ["binancecoin", "bnb"]
        case "bitcoin-testnet", "ethereum-sepolia", "usdt-erc20", "usdc-erc20", "dai-erc20":
            return nil
        default:
            return nil
        }
    }

    private func fetchPriceSnapshot() async throws -> [String: Double] {
        // Use MultiProviderAPI with automatic fallbacks (CoinCap -> CryptoCompare -> CoinGecko)
        do {
            return try await MultiProviderAPI.shared.fetchPrices()
        } catch {
            // If all providers fail, throw rate limited error to trigger retry
            throw BalanceFetchError.rateLimited
        }
    }

    /// Fetches FX rates relative to USD from CoinGecko Exchange Rates API
    private func fetchFXRates() async throws -> [String: Double] {
        // CoinGecko provides exchange rates for many currencies relative to BTC
        // We use USD as base (rate = 1.0) and calculate other rates
        let baseURL: String
        if let apiKey = coingeckoAPIKey, !apiKey.isEmpty {
            baseURL = "https://pro-api.coingecko.com/api/v3/exchange_rates?x_cg_pro_api_key=\(apiKey)"
        } else {
            baseURL = "https://api.coingecko.com/api/v3/exchange_rates"
        }
        
        guard let url = URL(string: baseURL) else {
            throw BalanceFetchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/\(AppVersion.displayVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }
        
        // Handle rate limiting
        if httpResponse.statusCode == 429 {
            throw BalanceFetchError.rateLimited
        }
        
        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidResponse
        }

        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = object as? [String: Any],
              let rates = dictionary["rates"] as? [String: Any] else {
            throw BalanceFetchError.invalidPayload
        }

        // Get USD value (base)
        guard let usdInfo = rates["usd"] as? [String: Any],
              let usdValue = usdInfo["value"] as? Double else {
            return ["USD": 1.0]
        }

        var fxRates: [String: Double] = ["USD": 1.0]
        
        // Calculate rates relative to USD
        let currencyCodes = ["EUR": "eur", "GBP": "gbp", "JPY": "jpy", "CAD": "cad", 
                            "AUD": "aud", "CHF": "chf", "CNY": "cny", "INR": "inr", "PLN": "pln"]
        
        for (code, apiKey) in currencyCodes {
            if let info = rates[apiKey] as? [String: Any],
               let value = info["value"] as? Double {
                // Rate relative to USD: how many units of currency per 1 USD
                fxRates[code] = value / usdValue
            }
        }

        return fxRates
    }

    @MainActor
    private func startFXRatesFetch() {
        fxRatesFetchTask?.cancel()
        fxRatesFetchTask = Task {
            do {
                let rates = try await fetchFXRates()
                self.fxRates = rates
            } catch {
                #if DEBUG
                print("Failed to fetch FX rates: \(error)")
                #endif
                // Keep existing rates if fetch fails
            }
        }
    }

    // MARK: - Sparkline data now handled by SparklineCache service

    @MainActor
    private func startBalanceFetch(for keys: AllKeys) {
        cancelBalanceFetchTasks()
        balanceBackoff.removeAll()
        
        // Group 1: BlockCypher (Rate limited, must be spaced out)
        scheduleBalanceFetch(for: "bitcoin") {
            try await fetchBitcoinBalance(address: keys.bitcoin.address)
        }

        scheduleBalanceFetch(for: "bitcoin-testnet", delay: 0.5) {
            try await fetchBitcoinBalance(address: keys.bitcoinTestnet.address, isTestnet: true)
        }

        scheduleBalanceFetch(for: "litecoin", delay: 1.0) {
            try await fetchLitecoinBalance(address: keys.litecoin.address)
        }

        // Group 2: Independent APIs (Can run in parallel immediately)
        scheduleBalanceFetch(for: "solana") {
            try await fetchSolanaBalance(address: keys.solana.publicKeyBase58)
        }

        scheduleBalanceFetch(for: "xrp") {
            try await fetchXrpBalance(address: keys.xrp.classicAddress)
        }

        scheduleBalanceFetch(for: "bnb") {
            try await fetchBnbBalance(address: keys.bnb.address)
        }

        startEthereumAndTokenBalanceFetch(address: keys.ethereum.address)
    }

    @MainActor
    private func startEthereumAndTokenBalanceFetch(address: String) {
        scheduleBalanceFetch(for: "ethereum") {
            try await fetchEthereumBalanceViaInfura(address: address)
        }

        scheduleBalanceFetch(for: "ethereum-sepolia", delay: 0.3) {
            try await fetchEthereumSepoliaBalance(address: address)
        }

        scheduleBalanceFetch(for: "usdt-erc20", delay: 0.7) {
            try await fetchERC20Balance(
                address: address,
                contractAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
                decimals: 6,
                symbol: "USDT"
            )
        }

        scheduleBalanceFetch(for: "usdc-erc20", delay: 1.4) {
            try await fetchERC20Balance(
                address: address,
                contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
                decimals: 6,
                symbol: "USDC"
            )
        }

        scheduleBalanceFetch(for: "dai-erc20", delay: 2.1) {
            try await fetchERC20Balance(
                address: address,
                contractAddress: "0x6B175474E89094C44Da98b954EedeAC495271d0F",
                decimals: 18,
                symbol: "DAI"
            )
        }
    }

    @MainActor
    private func ensurePriceStateEntries() {
        for id in trackedPriceChainIDs where priceStates[id] == nil {
            applyPriceLoadingState(for: id)
        }
    }

    @MainActor
    private func primeStateCaches(for keys: AllKeys) {
        let chains = keys.chainInfos
        for chain in chains {
            let balanceDefault = defaultBalanceState(for: chain.id)
            let priceDefault = defaultPriceState(for: chain.id)
            balanceStates[chain.id] = balanceDefault
            priceStates[chain.id] = priceDefault
        }
    }

    @MainActor
    private func defaultBalanceState(for chainID: String) -> ChainBalanceState {
        switch chainID {
        case "bitcoin-testnet":
            return .loading
        case "ethereum-sepolia":
            return .loaded(value: "Use Sepolia faucet for funds", lastUpdated: Date())
        case "monero":
            return .loaded(value: moneroBalancePlaceholder, lastUpdated: Date())
        default:
            return .loading
        }
    }

    @MainActor
    private func defaultPriceState(for chainID: String) -> ChainPriceState {
        if let staticDisplay = staticPriceDisplay(for: chainID) {
            return .loaded(value: staticDisplay, lastUpdated: Date())
        }
        return .loading
    }

    private func staticPriceDisplay(for chainID: String) -> String? {
        switch chainID {
        case "usdt-erc20", "usdc-erc20", "dai-erc20":
            return formatFiatAmountInSelectedCurrency(1.0)
        case "bitcoin-testnet", "ethereum-sepolia":
            return "Testnet asset"
        default:
            return nil
        }
    }

    @MainActor
    private func applyPriceLoadingState(for chainId: String) {
        let now = Date()
        let state = PriceStateReducer.loadingState(
            cache: cachedPrices[chainId],
            staticDisplay: staticPriceDisplay(for: chainId),
            now: now
        )
        if case .loaded(let value, let timestamp) = state {
            cachedPrices[chainId] = CachedPrice(value: value, lastUpdated: timestamp)
        }
        priceStates[chainId] = state
    }

    @MainActor
    private func applyPriceFailureState(message: String) {
        let now = Date()
        for id in trackedPriceChainIDs {
            let state = PriceStateReducer.failureState(
                cache: cachedPrices[id],
                staticDisplay: staticPriceDisplay(for: id),
                message: message,
                now: now
            )
            if case .loaded(let value, let timestamp) = state {
                cachedPrices[id] = CachedPrice(value: value, lastUpdated: timestamp)
            }
            priceStates[id] = state
        }
    }

    @MainActor
    private func scheduleBalanceFetch(for chainId: String, delay: TimeInterval = 0, fetcher: @escaping () async throws -> String) {
        applyLoadingState(for: chainId)
        launchBalanceFetchTask(for: chainId, after: delay, fetcher: fetcher)
    }

    @MainActor
    private func cancelBalanceFetchTasks() {
        for task in balanceFetchTasks.values {
            task.cancel()
        }
        balanceFetchTasks.removeAll()
    }

    @MainActor
    private func launchBalanceFetchTask(for chainId: String, after delay: TimeInterval, fetcher: @escaping () async throws -> String) {
        balanceFetchTasks[chainId]?.cancel()
        let task = Task {
            if delay > 0 {
                let nanos = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }
            await runBalanceFetchLoop(chainId: chainId, fetcher: fetcher)
        }
        balanceFetchTasks[chainId] = task
    }

    private func runBalanceFetchLoop(chainId: String, fetcher: @escaping () async throws -> String) async {
        while !Task.isCancelled {
            let succeeded = await performBalanceFetch(chainId: chainId, fetcher: fetcher)
            if succeeded || Task.isCancelled {
                return
            }

            let pendingDelay = await MainActor.run {
                balanceBackoff[chainId]?.remainingBackoff ?? minimumBalanceRetryDelay
            }
            let clampedDelay = max(pendingDelay, minimumBalanceRetryDelay)
            let nanos = UInt64(clampedDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
        }
    }

    @MainActor
    private func applyLoadingState(for chainId: String) {
        if let cache = cachedBalances[chainId] {
            balanceStates[chainId] = .refreshing(previous: cache.value, lastUpdated: cache.lastUpdated)
        } else {
            balanceStates[chainId] = .loading
        }
    }

    private func performBalanceFetch(chainId: String, fetcher: @escaping () async throws -> String) async -> Bool {
        if Task.isCancelled { return false }

        var pendingDelay: TimeInterval = 0
        await MainActor.run {
            if let tracker = balanceBackoff[chainId], tracker.isInBackoff {
                pendingDelay = tracker.remainingBackoff
            }
        }

        if pendingDelay > 0 {
            let nanos = UInt64(pendingDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            if Task.isCancelled { return false }
        }

        do {
            let displayValue = try await fetcher()
            await MainActor.run {
                let now = Date()
                cachedBalances[chainId] = CachedBalance(value: displayValue, lastUpdated: now)
                balanceStates[chainId] = .loaded(value: displayValue, lastUpdated: now)
                balanceBackoff[chainId] = nil
                // Save to persistent cache
                saveBalanceToCache(chainId: chainId, balance: displayValue)
            }
            return true
        } catch {
            let friendlyMessage: String = await MainActor.run {
                var tracker = balanceBackoff[chainId] ?? BackoffTracker()
                let retryDelay = tracker.registerFailure()
                balanceBackoff[chainId] = tracker
                let message = friendlyBackoffMessage(for: error, retryDelay: retryDelay)
                if let cache = cachedBalances[chainId] {
                    balanceStates[chainId] = .stale(value: cache.value, lastUpdated: cache.lastUpdated, message: message)
                } else {
                    balanceStates[chainId] = .failed(message)
                }
                return message
            }
            let nextDelay = await MainActor.run {
                balanceBackoff[chainId]?.remainingBackoff ?? minimumBalanceRetryDelay
            }
            let addressHint = chainId == "xrp" ? " (XRP address retry pending)" : ""
            let formattedDelay = String(format: "%.1fs", max(nextDelay, minimumBalanceRetryDelay))
            #if DEBUG
            print("⚠️ Balance fetch error for \(chainId): \(friendlyMessage) – \(error.localizedDescription). Next retry in \(formattedDelay)\(addressHint)")
            #endif
            return false
        }
    }

    private func friendlyBackoffMessage(for error: Error, retryDelay: TimeInterval) -> String {
        var base: String
        if let balanceError = error as? BalanceFetchError {
            switch balanceError {
            case .invalidStatus(let code) where code == 429:
                base = "Temporarily rate limited"
            case .invalidStatus(let code):
                base = "Service returned status \(code)"
            case .invalidRequest:
                base = "Invalid request"
            case .invalidResponse:
                base = "Unexpected response"
            case .invalidPayload:
                base = "Unreadable data"
            case .rateLimited:
                base = "Rate limited - prices updating soon"
            }
        } else {
            base = error.localizedDescription
        }

        if retryDelay > 0.1 {
            return "\(base). Retrying in \(formatRetryDuration(retryDelay))…"
        }
        return base
    }

    private func formatRetryDuration(_ delay: TimeInterval) -> String {
        if delay >= 10 {
            return "\(Int(delay))s"
        } else {
            return String(format: "%.1fs", delay)
        }
    }

    private func fetchBitcoinBalance(address: String, isTestnet: Bool = false) async throws -> String {
        let symbol = isTestnet ? "tBTC" : "BTC"
        
        // Use MultiProviderAPI with automatic fallbacks
        do {
            let btc = try await MultiProviderAPI.shared.fetchBitcoinBalance(address: address, isTestnet: isTestnet)
            return formatCryptoAmount(btc, symbol: symbol, maxFractionDigits: 8)
        } catch {
            #if DEBUG
            print("⚠️ All Bitcoin balance providers failed: \(error.localizedDescription)")
            #endif
            throw error
        }
    }

    private func fetchLitecoinBalance(address: String) async throws -> String {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://litecoinspace.org/api/address/\(encodedAddress)") else {
            throw BalanceFetchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            return "0.00000000 LTC"
        }

        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = jsonObject as? [String: Any],
              let chainStats = dictionary["chain_stats"] as? [String: Any] else {
            throw BalanceFetchError.invalidPayload
        }

        let funded = (chainStats["funded_txo_sum"] as? NSNumber)?.doubleValue ?? 0
        let spent = (chainStats["spent_txo_sum"] as? NSNumber)?.doubleValue ?? 0
        let balanceInLitoshis = max(0, funded - spent)
        let ltc = balanceInLitoshis / 100_000_000.0
        return formatCryptoAmount(ltc, symbol: "LTC", maxFractionDigits: 8)
    }

    private func fetchSolanaBalance(address: String) async throws -> String {
        // Try Alchemy FIRST if configured (most reliable)
        if APIConfig.isAlchemyConfigured() {
            do {
                #if DEBUG
                print("📡 Trying Alchemy for SOL balance...")
                #endif
                let sol = try await MultiProviderAPI.shared.fetchSolanaBalanceViaAlchemy(address: address)
                return formatCryptoAmount(sol, symbol: "SOL", maxFractionDigits: 6)
            } catch {
                #if DEBUG
                print("⚠️ Alchemy SOL failed: \(error.localizedDescription)")
                #endif
            }
        }
        
        // Use MultiProviderAPI with automatic fallbacks across multiple RPC endpoints
        do {
            let sol = try await MultiProviderAPI.shared.fetchSolanaBalance(address: address)
            return formatCryptoAmount(sol, symbol: "SOL", maxFractionDigits: 6)
        } catch {
            #if DEBUG
            print("⚠️ All Solana balance providers failed: \(error.localizedDescription)")
            #endif
            throw error
        }
    }

    private func fetchXrpBalanceViaRippleDataAPI(address: String) async throws -> String {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://data.ripple.com/v2/accounts/\(encodedAddress)/balances") else {
            throw BalanceFetchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            return formatCryptoAmount(0, symbol: "XRP", maxFractionDigits: 6)
        }

        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let payload = try decoder.decode(RippleDataAccountBalanceResponse.self, from: data)

        if payload.isAccountMissing {
            return formatCryptoAmount(0, symbol: "XRP", maxFractionDigits: 6)
        }

        if let balanceDecimal = payload.xrpBalanceValue {
            let xrp = NSDecimalNumber(decimal: balanceDecimal).doubleValue
            return formatCryptoAmount(xrp, symbol: "XRP", maxFractionDigits: 6)
        }

        return formatCryptoAmount(0, symbol: "XRP", maxFractionDigits: 6)
    }

    private func fetchXrpBalance(address: String) async throws -> String {
        let shortened = address.prefix(8)

        do {
            return try await fetchXrpBalanceViaRippleDataAPI(address: address)
        } catch {
            #if DEBUG
            print("⚠️ Ripple Data API lookup failed for \(shortened)…: \(error.localizedDescription). Trying XRPSCAN next.")
            #endif
        }

        do {
            return try await fetchXrpBalanceViaXrpScan(address: address)
        } catch {
            #if DEBUG
            print("⚠️ XRPSCAN lookup failed for \(shortened)…: \(error.localizedDescription). Falling back to XRPL RPC endpoints.")
            #endif
        }

        return try await fetchXrpBalanceViaRippleRPC(address: address)
    }

    private func fetchXrpBalanceViaRippleRPC(address: String) async throws -> String {
        var lastError: Error?
        let shortened = address.prefix(8)

        for endpoint in APIConfig.xrplEndpoints {
            do {
                return try await requestXrpBalance(address: address, endpoint: endpoint)
            } catch {
                #if DEBUG
                print("⚠️ XRPL RPC \(endpoint) failed for \(shortened)…: \(error.localizedDescription)")
                #endif
                lastError = error
                continue
            }
        }

        #if DEBUG
        print("❌ All XRPL RPC endpoints exhausted for \(shortened)…")
        #endif
        throw lastError ?? BalanceFetchError.invalidResponse
    }

    private func requestXrpBalance(address: String, endpoint: String) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw BalanceFetchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try xrplAccountInfoPayload(address: address)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            return formatCryptoAmount(0, symbol: "XRP", maxFractionDigits: 6)
        }

        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }

        do {
            let xrpDecimal = try BalanceResponseParser.parseXRPLBalance(from: data)
            let xrp = NSDecimalNumber(decimal: xrpDecimal).doubleValue
            return formatCryptoAmount(xrp, symbol: "XRP", maxFractionDigits: 6)
        } catch {
            if xrplResponseIndicatesUnfundedAccount(data) {
                return formatCryptoAmount(0, symbol: "XRP", maxFractionDigits: 6)
            }
            throw error
        }
    }

    private func fetchXrpBalanceViaXrpScan(address: String) async throws -> String {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.xrpscan.com/api/v1/account/\(encodedAddress)") else {
            throw BalanceFetchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            return formatCryptoAmount(0, symbol: "XRP", maxFractionDigits: 6)
        }

        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let payload = try decoder.decode(XrpScanAccountResponse.self, from: data)

        if let balanceString = payload.xrpBalance ?? payload.balance,
           let balanceDecimal = Decimal(string: balanceString) {
            let xrp = NSDecimalNumber(decimal: balanceDecimal).doubleValue
            return formatCryptoAmount(xrp, symbol: "XRP", maxFractionDigits: 6)
        }

        return formatCryptoAmount(0, symbol: "XRP", maxFractionDigits: 6)
    }

    private func xrplAccountInfoPayload(address: String) throws -> Data {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "account_info",
            "id": 1,
            "params": [
                [
                    "account": address,
                    "ledger_index": "validated",
                    "queue": true
                ]
            ]
        ]

        return try JSONSerialization.data(withJSONObject: payload, options: [])
    }

    private func xrplResponseIndicatesUnfundedAccount(_ data: Data) -> Bool {
        guard
            let json = try? JSONSerialization.jsonObject(with: data, options: []),
            let dictionary = json as? [String: Any],
            let result = dictionary["result"] as? [String: Any]
        else { return false }

        if let errorCode = result["error"] as? String {
            return errorCode == "actNotFound"
        }

        if let status = result["status"] as? String, status == "error",
           let errorMessage = result["error_message"] as? String {
            return errorMessage.lowercased().contains("not found")
        }

        return false
    }

    private func fetchBnbBalance(address: String) async throws -> String {
        guard let url = URL(string: "https://bsc-dataseed.binance.org/") else {
            throw BalanceFetchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "eth_getBalance",
            "params": [address, "latest"]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = jsonObject as? [String: Any],
              let result = dictionary["result"] as? String else {
            throw BalanceFetchError.invalidPayload
        }

        let weiDecimal = decimalFromHex(result)
        let divisor = Decimal(string: "1000000000000000000") ?? Decimal(1_000_000_000_000_000_000)
        let bnbDecimal = weiDecimal / divisor
        let bnb = NSDecimalNumber(decimal: bnbDecimal).doubleValue
        return formatCryptoAmount(bnb, symbol: "BNB", maxFractionDigits: 6)
    }

    private func fetchEthereumBalanceViaInfura(address: String) async throws -> String {
        // Try Alchemy FIRST if configured (most reliable)
        if APIConfig.isAlchemyConfigured() {
            do {
                #if DEBUG
                print("📡 Trying Alchemy for ETH balance...")
                #endif
                return try await fetchEthereumBalanceViaAlchemy(address: address)
            } catch {
                #if DEBUG
                print("⚠️ Alchemy ETH failed: \(error.localizedDescription)")
                #endif
            }
        }
        
        // Use MultiProviderAPI with automatic fallbacks across multiple RPC endpoints
        do {
            let eth = try await MultiProviderAPI.shared.fetchEthereumBalance(address: address)
            return formatCryptoAmount(eth, symbol: "ETH", maxFractionDigits: 6)
        } catch {
            // If all providers fail, try Blockchair as last resort
            return try await fetchEthereumBalanceViaBlockchair(address: address)
        }
    }
    
    private func fetchEthereumBalanceViaAlchemy(address: String) async throws -> String {
        guard let url = URL(string: APIConfig.alchemyMainnetURL) else {
            throw BalanceFetchError.invalidRequest
        }
        
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getBalance",
            "params": [address, "latest"],
            "id": 1
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }
        
                let ethDecimal = try BalanceResponseParser.parseAlchemyETHBalance(from: responseData)
                let eth = NSDecimalNumber(decimal: ethDecimal).doubleValue
        return formatCryptoAmount(eth, symbol: "ETH", maxFractionDigits: 6)
    }
    
    private func fetchEthereumBalanceViaBlockchair(address: String) async throws -> String {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.blockchair.com/ethereum/dashboards/address/\(encodedAddress)") else {
            throw BalanceFetchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }
        
        if httpResponse.statusCode == 404 {
            return "0.00 ETH"
        }
        
        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }

        do {
            let ethDecimal = try BalanceResponseParser.parseBlockchairETHBalance(from: data, address: address)
            let eth = NSDecimalNumber(decimal: ethDecimal).doubleValue
            return formatCryptoAmount(eth, symbol: "ETH", maxFractionDigits: 6)
        } catch {
            return "0.00 ETH"
        }
    }

    private func fetchERC20Balance(address: String, contractAddress: String, decimals: Int, symbol: String) async throws -> String {
        // Use Alchemy if configured, otherwise fallback to Blockchair
        if APIConfig.isAlchemyConfigured() {
            return try await fetchERC20BalanceViaAlchemy(address: address, contractAddress: contractAddress, decimals: decimals, symbol: symbol)
        } else {
            return try await fetchERC20BalanceViaBlockchair(address: address, contractAddress: contractAddress, decimals: decimals, symbol: symbol)
        }
    }
    
    private func fetchERC20BalanceViaAlchemy(address: String, contractAddress: String, decimals: Int, symbol: String) async throws -> String {
        guard let url = URL(string: APIConfig.alchemyMainnetURL) else {
            throw BalanceFetchError.invalidRequest
        }
        
        // balanceOf(address) function signature
        let functionSelector = "0x70a08231"
        let paddedAddress = String(address.dropFirst(2)).padding(toLength: 64, withPad: "0", startingAt: 0)
        let data = functionSelector + paddedAddress
        
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_call",
            "params": [
                [
                    "to": contractAddress,
                    "data": data
                ],
                "latest"
            ],
            "id": 1
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            return "0 \(symbol)"
        }
        
        do {
            let tokenAmountDecimal = try BalanceResponseParser.parseAlchemyERC20Balance(from: responseData, decimals: decimals)
            let amount = NSDecimalNumber(decimal: tokenAmountDecimal).doubleValue
            return formatCryptoAmount(amount, symbol: symbol, maxFractionDigits: decimals >= 6 ? 6 : decimals)
        } catch {
            return "0 \(symbol)"
        }
    }
    
    private func fetchERC20BalanceViaBlockchair(address: String, contractAddress: String, decimals: Int, symbol: String) async throws -> String {
        // Use Blockchair API for ERC-20 tokens - better rate limits
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.blockchair.com/ethereum/dashboards/address/\(encodedAddress)?erc_20=true") else {
            throw BalanceFetchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            return "0 \(symbol)"
        }

        let amountDecimal = try BalanceResponseParser.parseBlockchairERC20Balance(from: data, address: address, contractAddress: contractAddress, decimals: decimals)
        let amount = NSDecimalNumber(decimal: amountDecimal).doubleValue
        return formatCryptoAmount(amount, symbol: symbol, maxFractionDigits: decimals >= 6 ? 6 : decimals)
    }

    private func fetchEthplorerAccount(address: String) async throws -> EthplorerAddressResponse {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.ethplorer.io/getAddressInfo/\(encodedAddress)?apiKey=freekey") else {
            throw BalanceFetchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            return EthplorerAddressResponse(eth: .init(balance: 0), tokens: [])
        }

        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(EthplorerAddressResponse.self, from: data)
    }

    private func tokenBalance(for symbol: String, decimalsHint: Int, in tokens: [EthplorerAddressResponse.TokenBalance]?) -> Double {
        guard let tokens else { return 0 }
        let match = tokens.first { entry in
            guard let tokenSymbol = entry.tokenInfo?.symbol else { return false }
            return tokenSymbol.caseInsensitiveCompare(symbol) == .orderedSame
        }

        if let balance = match?.balance {
            return balance
        }

        if let rawBalance = match?.rawBalance,
           let rawDecimal = Decimal(string: rawBalance) {
            let decimals = match?.tokenInfo?.decimals.flatMap(Int.init) ?? decimalsHint
            let adjusted = decimalDividingByPowerOfTen(rawDecimal, exponent: decimals)
            return NSDecimalNumber(decimal: adjusted).doubleValue
        }

        return 0
    }

    private func decimalFromHex(_ hexString: String) -> Decimal {
        let sanitized = hexString.lowercased().hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
        guard !sanitized.isEmpty else { return Decimal.zero }

        var result = Decimal.zero
        for character in sanitized {
            result *= 16
            if let digit = Int(String(character), radix: 16) {
                result += Decimal(digit)
            } else {
                return Decimal.zero
            }
        }
        return result
    }

    private func decimalDividingByPowerOfTen(_ value: Decimal, exponent: Int) -> Decimal {
        var input = value
        var result = Decimal()
        let clampedExponent = Int16(clamping: exponent)
        NSDecimalMultiplyByPowerOf10(&result, &input, -clampedExponent, .plain)
        return result
    }

    private func normalizeAddressForCall(_ address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") ? String(trimmed.dropFirst(2)) : trimmed
        let lowercased = stripped.lowercased()
        let filtered = lowercased.filter { "0123456789abcdef".contains($0) }
        let limited = filtered.count > 64 ? String(filtered.suffix(64)) : filtered
        guard limited.count < 64 else { return limited }
        return String(repeating: "0", count: 64 - limited.count) + limited
    }

    private func fetchEthereumBalance(address: String) async throws -> String {
        let payload = try await fetchEthplorerAccount(address: address)
        let balance = payload.eth.balance
        return formatCryptoAmount(balance, symbol: "ETH", maxFractionDigits: 6)
    }

    private func fetchEthereumSepoliaBalance(address: String) async throws -> String {
        guard let url = URL(string: APIConfig.alchemySepoliaURL) else {
            throw BalanceFetchError.invalidRequest
        }
        
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getBalance",
            "params": [address, "latest"],
            "id": 1
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }
        
        let ethDecimal = try BalanceResponseParser.parseAlchemyETHBalance(from: responseData)
        let eth = NSDecimalNumber(decimal: ethDecimal).doubleValue
        return formatCryptoAmount(eth, symbol: "ETH", maxFractionDigits: 6)
    }

    private func formatCryptoAmount(_ amount: Double, symbol: String, maxFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxFractionDigits
        let formatted = formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.\(maxFractionDigits)f", amount)
        return "\(formatted) \(symbol)"
    }

    private var selectedFiatCurrency: FiatCurrency {
        FiatCurrency(rawValue: storedFiatCurrency) ?? .usd
    }

    /// Formats amount in the user's selected fiat currency
    /// - Parameters:
    ///   - amountInUSD: The amount in USD (as provided by CoinGecko)
    ///   - useSelectedCurrency: If true, converts to user's selected currency. If false, formats as USD.
    private func formatFiatAmountInSelectedCurrency(_ amountInUSD: Double, useSelectedCurrency: Bool = true) -> String {
        let currency = useSelectedCurrency ? selectedFiatCurrency : .usd
        let rate = fxRates[currency.rawValue] ?? 1.0
        let convertedAmount = amountInUSD * rate
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.rawValue
        
        // Use appropriate locale for currency formatting
        switch currency {
        case .eur: formatter.locale = Locale(identifier: "de_DE")
        case .gbp: formatter.locale = Locale(identifier: "en_GB")
        case .jpy: formatter.locale = Locale(identifier: "ja_JP")
        case .cad: formatter.locale = Locale(identifier: "en_CA")
        case .aud: formatter.locale = Locale(identifier: "en_AU")
        case .chf: formatter.locale = Locale(identifier: "de_CH")
        case .cny: formatter.locale = Locale(identifier: "zh_CN")
        case .inr: formatter.locale = Locale(identifier: "en_IN")
        case .pln: formatter.locale = Locale(identifier: "pl_PL")
        case .usd: formatter.locale = Locale(identifier: "en_US")
        }
        
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        
        return formatter.string(from: NSNumber(value: convertedAmount)) ?? "\(currency.symbol)\(String(format: "%.2f", convertedAmount))"
    }

    private func formatFiatAmount(_ amount: Double, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = Locale(identifier: "en_US")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }

    private func handlePasscodeChange() {
        if storedPasscodeHash != nil {
            lock()
        } else {
            isUnlocked = true
            biometricUnlockEnabled = false
            autoLockTask?.cancel()
        }
    }

    @MainActor
    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            // Remove privacy blur when app becomes active
            withAnimation(.easeOut(duration: 0.2)) {
                showPrivacyBlur = false
            }
            startPriceUpdatesIfNeeded()
            refreshBiometricAvailability()
            startActivityMonitoringIfNeeded()
            recordActivity()
            if storedPasscodeHash != nil && !isUnlocked {
                if biometricUnlockEnabled {
                    attemptBiometricUnlock(reason: "Unlock Hawala")
                }
                showUnlockSheet = true
            }
        case .inactive:
            // Show privacy blur when app goes inactive (e.g., app switcher)
            withAnimation(.easeIn(duration: 0.1)) {
                showPrivacyBlur = true
            }
        case .background:
            showPrivacyBlur = true
            stopPriceUpdates()
            clearSensitiveData()
            if storedPasscodeHash != nil {
                isUnlocked = false
            }
            autoLockTask?.cancel()
            stopActivityMonitoring()
        @unknown default:
            break
        }
    }

    private func lock() {
        clearSensitiveData()
        isUnlocked = false
        showUnlockSheet = true
        autoLockTask?.cancel()
        if biometricUnlockEnabled {
            attemptBiometricUnlock(reason: "Unlock Hawala")
        }
    }

    @MainActor
    private func recordActivity() {
        lastActivityTimestamp = Date()
        scheduleAutoLockCountdown()
    }

    @MainActor
    private func scheduleAutoLockCountdown() {
        autoLockTask?.cancel()
        guard storedPasscodeHash != nil else { return }
        guard let interval = (AutoLockIntervalOption(rawValue: storedAutoLockInterval) ?? .fiveMinutes).duration,
              interval > 0 else { return }
        let deadline = lastActivityTimestamp.addingTimeInterval(interval)
        autoLockTask = Task { [deadline] in
            let delay = max(0, deadline.timeIntervalSinceNow)
            let nanos = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if Date() >= deadline && storedPasscodeHash != nil {
                    lock()
                }
            }
        }
    }

    @MainActor
    private func startActivityMonitoringIfNeeded() {
        #if canImport(AppKit)
        guard activityMonitor == nil else { return }
        activityMonitor = UserActivityMonitor {
            Task { @MainActor in
                recordActivity()
            }
        }
        #endif
    }

    @MainActor
    private func stopActivityMonitoring() {
        #if canImport(AppKit)
        activityMonitor?.stop()
        activityMonitor = nil
        #endif
    }

    @MainActor
    private func refreshBiometricAvailability() {
        #if canImport(LocalAuthentication)
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            if #available(macOS 11.0, iOS 11.0, *) {
                switch context.biometryType {
                case .touchID:
                    biometricState = .available(.touchID)
                case .faceID:
                    biometricState = .available(.faceID)
                default:
                    biometricState = .available(.generic)
                }
            } else {
                biometricState = .available(.generic)
            }
        } else {
            let reason = error?.localizedDescription ?? "Biometrics are not available on this device."
            biometricState = .unavailable(reason)
            biometricUnlockEnabled = false
        }
        #else
        biometricState = .unavailable("Biometrics are not supported on this platform.")
        biometricUnlockEnabled = false
        #endif
    }

    private func attemptBiometricUnlock(reason: String) {
        #if canImport(LocalAuthentication)
        guard biometricUnlockEnabled else { return }
        let context = LAContext()
        context.localizedFallbackTitle = "Enter Passcode"
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, evalError in
                guard success else {
                    if let evalError = evalError as? LAError, evalError.code == .biometryNotAvailable {
                        Task { @MainActor in
                            biometricUnlockEnabled = false
                            biometricState = .unavailable(evalError.localizedDescription)
                        }
                    }
                    return
                }
                Task { @MainActor in
                    isUnlocked = true
                    showUnlockSheet = false
                    recordActivity()
                }
            }
        } else {
            biometricUnlockEnabled = false
            biometricState = .unavailable(error?.localizedDescription ?? "Biometrics are unavailable.")
        }
        #else
        _ = reason
        #endif
    }

    private func hashPasscode(_ passcode: String) -> String {
        let data = Data(passcode.utf8)
        let digest = CryptoKit.SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
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
        
        showAllPrivateKeysSheet = true
    }

    private var workspaceRoot: URL {
        if let cached = ContentView.cachedWorkspaceRoot {
            return cached
        }

        let resolved = resolveWorkspaceRoot()
        ContentView.cachedWorkspaceRoot = resolved
        return resolved
    }

    private var manifestPath: String {
        workspaceRoot
            .appendingPathComponent("rust-app")
            .appendingPathComponent("Cargo.toml")
            .path
    }

    private func resolveWorkspaceRoot() -> URL {
        let fm = FileManager.default

        let candidateDirectories: [URL] = [
            URL(fileURLWithPath: fm.currentDirectoryPath),
            URL(fileURLWithPath: Bundle.main.executablePath ?? "").deletingLastPathComponent(),
            Bundle.main.bundleURL,
            Bundle.main.bundleURL.deletingLastPathComponent()
        ]

        for candidate in candidateDirectories {
            if let root = findWorkspaceRoot(startingAt: candidate) {
                return root
            }
        }

        // Fallback to current directory if nothing else works
        return URL(fileURLWithPath: fm.currentDirectoryPath)
    }

    private func findWorkspaceRoot(startingAt initialURL: URL) -> URL? {
        let fm = FileManager.default
        var current = initialURL
            .resolvingSymlinksInPath()

        let maxDepth = 12
        for _ in 0..<maxDepth {
            let rustManifest = current
                .appendingPathComponent("rust-app")
                .appendingPathComponent("Cargo.toml")
            let swiftPackage = current
                .appendingPathComponent("swift-app")
                .appendingPathComponent("Package.swift")

            if fm.fileExists(atPath: rustManifest.path), fm.fileExists(atPath: swiftPackage.path) {
                return current
            }

            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                break
            }
            current = parent
        }

        return nil
    }
}

// BitcoinUTXO, BitcoinFeeEstimates, EthGasSpeed, EthGasEstimates, and BitcoinSendError
// are defined in Models/FeeModels.swift

// MARK: - Send Picker & Seed Phrase

private struct SendAssetPickerSheet: View {
    let chains: [ChainInfo]
    let onSelect: (ChainInfo) -> Void
    let onBatchSend: () -> Void
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredChains: [ChainInfo] {
        let sorted = chains.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        if searchText.isEmpty { return sorted }
        return sorted.filter { $0.title.localizedCaseInsensitiveContains(searchText) || $0.id.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search assets", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.body)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding()

                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Batch Send option
                        Button {
                            dismiss()
                            onBatchSend()
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "square.stack.3d.up.fill")
                                    .font(.title2)
                                    .foregroundStyle(HawalaTheme.Colors.accent)
                                    .frame(width: 44, height: 44)
                                    .background(HawalaTheme.Colors.accent.opacity(0.1))
                                    .clipShape(Circle())
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Batch Send")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("Send to multiple addresses at once")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .background(LinearGradient(
                                colors: [HawalaTheme.Colors.accent.opacity(0.08), HawalaTheme.Colors.accent.opacity(0.02)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(HawalaTheme.Colors.accent.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        
                        // Divider
                        HStack {
                            VStack { Divider() }
                            Text("or select an asset")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            VStack { Divider() }
                        }
                        .padding(.vertical, 4)
                        
                        ForEach(filteredChains) { chain in
                            Button {
                                dismiss()
                                onSelect(chain)
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: chain.iconName)
                                        .font(.title2)
                                        .foregroundStyle(chain.accentColor)
                                        .frame(width: 44, height: 44)
                                        .background(chain.accentColor.opacity(0.1))
                                        .clipShape(Circle())
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(chain.title)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text(chain.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(Color.gray.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Send Funds")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                        onDismiss()
                    }
                }
            }
        }
        .frame(width: 450, height: 550)
    }
}

private struct SeedPhraseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCount: MnemonicGenerator.WordCount = .twelve
    @State private var words: [String] = MnemonicGenerator.generate(wordCount: .twelve)
    let onCopy: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Picker("Length", selection: $selectedCount) {
                    ForEach(MnemonicGenerator.WordCount.allCases) { count in
                        Text(count.title).tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedCount) { newValue in
                    regenerate(using: newValue)
                }

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                        ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                            HStack {
                                Text(String(format: "%02d", index + 1))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(word)
                                    .font(.headline)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.horizontal)
                }

                HStack(spacing: 12) {
                    Button {
                        regenerate(using: selectedCount)
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        let phrase = words.joined(separator: " ")
                        onCopy(phrase)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)

                Text("Back up this phrase securely. Anyone with access can control your wallets.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer(minLength: 0)
            }
            .padding(.top, 20)
            .navigationTitle("Seed Phrase")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 550, height: 600)
    }

    private func regenerate(using count: MnemonicGenerator.WordCount) {
        words = MnemonicGenerator.generate(wordCount: count)
    }
}

// ChainCard for displaying chain balance/price info in the main grid
private struct ChainCard: View {
    let chain: ChainInfo
    let balanceState: ChainBalanceState
    let priceState: ChainPriceState
    var sparklineData: [Double] = []

    @State private var skeletonPhase: CGFloat = -0.8

    private var pricePrimary: String {
        switch priceState {
        case .idle:
            return "—"
        case .loading:
            return "Loading…"
        case .refreshing(let value, _), .loaded(let value, _), .stale(let value, _, _):
            return value
        case .failed:
            return "Unavailable"
        }
    }

    private var isBalanceLoading: Bool {
        if case .loading = balanceState { return true }
        return false
    }

    private var isPriceLoading: Bool {
        if case .loading = priceState { return true }
        return false
    }

    private var priceDetail: (text: String, color: Color)? {
        switch priceState {
        case .refreshing(_, let timestamp):
            let detail = relativeTimeDescription(from: timestamp).map { "Refreshing… • updated \($0)" } ?? "Refreshing…"
            return (detail, .secondary)
        case .loaded(_, let timestamp):
            if let relative = relativeTimeDescription(from: timestamp) {
                return ("Updated \(relative)", .secondary)
            }
            return nil
        case .stale(_, let timestamp, let message):
            var detail = message
            if let relative = relativeTimeDescription(from: timestamp) {
                detail += " • updated \(relative)"
            }
            return (detail, .orange)
        case .failed(let message):
            return (message, .red)
        default:
            return nil
        }
    }

    private var balancePrimary: String {
        switch balanceState {
        case .idle:
            return "—"
        case .loading:
            return "Loading…"
        case .refreshing(let value, _), .loaded(let value, _), .stale(let value, _, _):
            return value
        case .failed:
            return "Unavailable"
        }
    }

    private var balanceDetail: (text: String, color: Color)? {
        switch balanceState {
        case .refreshing(_, let timestamp):
            if let relative = relativeTimeDescription(from: timestamp) {
                return ("Refreshing… • updated \(relative)", .secondary)
            }
            return ("Refreshing…", .secondary)
        case .loaded(_, let timestamp):
            if let relative = relativeTimeDescription(from: timestamp) {
                return ("Updated \(relative)", .secondary)
            }
            return nil
        case .stale(_, let timestamp, let message):
            var detail = message
            if let relative = relativeTimeDescription(from: timestamp) {
                detail += " • updated \(relative)"
            }
            return (detail, .orange)
        case .failed(let message):
            return (message, .red)
        default:
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: chain.iconName)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(chain.accentColor)
                    .frame(width: 40, height: 40)
                    .background(chain.accentColor.opacity(0.15))
                    .clipShape(Circle())
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(chain.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text(chain.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer(minLength: 8)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Balance")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Spacer()
                        if isBalanceLoading {
                            SkeletonLine()
                        } else {
                            Text(balancePrimary)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                    if isBalanceLoading {
                        SkeletonLine(width: 110, height: 8)
                            .padding(.top, 2)
                    } else if let detail = balanceDetail {
                        Text(detail.text)
                            .font(.caption2)
                            .foregroundStyle(detail.color)
                    }
                    
                    HStack {
                        Text("Price")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Spacer()
                        if isPriceLoading {
                            SkeletonLine(width: 70)
                        } else {
                            HStack(spacing: 8) {
                                Text(pricePrimary)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                if !sparklineData.isEmpty {
                                    SparklineView(dataPoints: sparklineData, lineColor: chain.accentColor)
                                }
                            }
                        }
                    }
                    if isPriceLoading {
                        SkeletonLine(width: 90, height: 8)
                            .padding(.top, 2)
                    } else if let detail = priceDetail {
                        Text(detail.text)
                            .font(.caption2)
                            .foregroundStyle(detail.color)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(chain.accentColor.opacity(0.15), lineWidth: 1)
        )
        // GPU-accelerated compositing for smooth scrolling
        .drawingGroup(opaque: false)
    }
}

private struct SettingsPanelView: View {
    let hasKeys: Bool
    let onShowKeys: () -> Void
    let onOpenSecurity: () -> Void
    @Binding var selectedCurrency: String
    let onCurrencyChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var localization = LocalizationManager.shared
    @ObservedObject private var feedbackManager = FeedbackManager.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    languageSection
                    
                    Divider()
                    
                    currencySection
                    
                    Divider()
                    
                    feedbackSection
                    
                    Divider()

                    keysButton
                    securityButton
                    privacyButton

                    Spacer()
                }
                .padding()
            }
            .frame(width: 380, height: 520)
            .navigationTitle("settings.title".localized)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close".localized) { dismiss() }
                }
            }
        }
    }
    
    @State private var selectedLanguage: LocalizationManager.Language = .english
    
    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Feedback")
                .font(.headline)
            
            Toggle(isOn: Binding(
                get: { feedbackManager.isSoundEnabled },
                set: { feedbackManager.isSoundEnabled = $0 }
            )) {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sound Effects")
                            .font(.body)
                        Text("Play sounds for actions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .toggleStyle(.switch)
            
            Toggle(isOn: Binding(
                get: { feedbackManager.isHapticEnabled },
                set: { feedbackManager.isHapticEnabled = $0 }
            )) {
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap.fill")
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Haptic Feedback")
                            .font(.body)
                        Text("Trackpad haptics for actions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .toggleStyle(.switch)
        }
        .padding(.bottom, 8)
    }
    
    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("settings.language".localized)
                .font(.headline)
            Picker("Language", selection: $selectedLanguage) {
                ForEach(LocalizationManager.Language.allCases) { language in
                    HStack(spacing: 8) {
                        Text(language.flag)
                        Text(language.displayName)
                    }
                    .tag(language)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: selectedLanguage) { newLang in
                localization.setLanguage(newLang)
            }
            .onAppear {
                selectedLanguage = localization.currentLanguage
            }
            
            Text("settings.language.description".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }

    private var currencySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("settings.currency".localized)
                .font(.headline)
            Picker("Currency", selection: $selectedCurrency) {
                ForEach(FiatCurrency.allCases) { currency in
                    Text("\(currency.symbol) \(currency.displayName)")
                        .tag(currency.rawValue)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: selectedCurrency) { _ in
                onCurrencyChanged()
            }
        }
        .padding(.bottom, 8)
    }

    private var keysButton: some View {
        Button {
            dismiss()
            onShowKeys()
        } label: {
            Label("settings.show_keys".localized, systemImage: "doc.text.magnifyingglass")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!hasKeys)
    }

    private var securityButton: some View {
        Button {
            dismiss()
            onOpenSecurity()
        } label: {
            Label("settings.security".localized, systemImage: "lock.shield")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
    }
    
    @State private var showPrivacySettings = false
    @ObservedObject private var privacyManager = PrivacyManager.shared
    
    private var privacyButton: some View {
        Button {
            showPrivacySettings = true
        } label: {
            HStack {
                Label("Privacy", systemImage: privacyManager.isPrivacyModeEnabled ? "eye.slash.fill" : "eye.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                if privacyManager.isPrivacyModeEnabled {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .buttonStyle(.bordered)
        .sheet(isPresented: $showPrivacySettings) {
            NavigationStack {
                PrivacySettingsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showPrivacySettings = false }
                        }
                    }
            }
            .frame(width: 450, height: 550)
        }
    }
}

private struct AllPrivateKeysSheet: View {
    let chains: [ChainInfo]
    let onCopy: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private var sections: [(chain: ChainInfo, items: [KeyDetail])] {
        chains.compactMap { chain in
            let privateItems = chain.details.filter { $0.label.localizedCaseInsensitiveContains("private") }
            guard !privateItems.isEmpty else { return nil }
            return (chain, privateItems)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if sections.isEmpty {
                        Text("No private key fields are available to display.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    } else {
                        ForEach(sections, id: \.chain.id) { section in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(section.chain.title)
                                    .font(.headline)
                                ForEach(section.items) { item in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(item.label)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        HStack(alignment: .top, spacing: 8) {
                                            Text(item.value)
                                                .font(.system(.body, design: .monospaced))
                                                .textSelection(.enabled)
                                            Spacer(minLength: 0)
                                            Button {
                                                onCopy(item.value)
                                            } label: {
                                                Image(systemName: "doc.on.doc")
                                                    .padding(6)
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                    }
                                    .padding(12)
                                    .background(Color.gray.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("All Private Keys")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(width: 600, height: 700)
    }
}

private struct ChainDetailSheet: View {
    let chain: ChainInfo
    let balanceState: ChainBalanceState
    let priceState: ChainPriceState
    let keys: AllKeys?
    let onCopy: (String) -> Void
    let onSendRequested: (ChainInfo) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showReceiveInfo = false
    @State private var showReceiveQR = false
    @State private var copyFeedbackMessage: String?
    @State private var copyFeedbackTask: Task<Void, Never>?
    
    private var isBitcoinChain: Bool {
        chain.id.starts(with: "bitcoin")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isBitcoinChain {
                        quickActionsSection
                    }
                    
                    if let receiveAddress = chain.receiveAddress {
                        receiveSection(address: receiveAddress)
                    }
                    balanceSummary
                    priceSummary
                }
                .padding()
            }
            .navigationTitle(chain.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(width: 480, height: 600)
        .overlay(alignment: .bottom) {
            if let message = copyFeedbackMessage {
                CopyFeedbackBanner(message: message)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    
    @ViewBuilder
    private var quickActionsSection: some View {
        HStack(spacing: 12) {
            Button {
                onSendRequested(chain)
            } label: {
                Label("Send", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(keys == nil)
            
            Button {
                withAnimation { showReceiveInfo = true }
            } label: {
                Label("Receive", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func receiveSection(address: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.to.line.compact")
                    .font(.title3)
                    .foregroundStyle(chain.accentColor)
                Text("Receive")
                    .font(.headline)
                Spacer()
                Button(showReceiveInfo ? "Hide" : "Show") {
                    withAnimation { showReceiveInfo.toggle() }
                }
                .buttonStyle(.bordered)
            }

            if showReceiveInfo {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Share this address to receive funds:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    // QR Code (toggleable)
                    if showReceiveQR {
                        HStack {
                            Spacer()
                            QRCodeView(content: address, size: 160)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Address display
                    Text(address)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    // Action buttons
                    HStack(spacing: 10) {
                        Button {
                            copyWithFeedback(value: address, label: "Receive address")
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(chain.accentColor)
                        
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showReceiveQR.toggle()
                            }
                        } label: {
                            Label(
                                showReceiveQR ? "Hide QR" : "Show QR",
                                systemImage: showReceiveQR ? "qrcode" : "qrcode.viewfinder"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        
                        #if canImport(AppKit)
                        Button {
                            shareReceiveAddress(address)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        #endif
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(chain.accentColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    #if canImport(AppKit)
    private func shareReceiveAddress(_ address: String) {
        let sharingText = "My \(chain.title) address: \(address)"
        let picker = NSSharingServicePicker(items: [sharingText])
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            let rect = CGRect(x: contentView.bounds.midX, y: contentView.bounds.midY, width: 1, height: 1)
            picker.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
        }
    }
    #endif

    @ViewBuilder
    private var balanceSummary: some View {
        HStack(alignment: .center, spacing: 12) {
            Label("Balance", systemImage: "creditcard.fill")
                .font(.headline)
            Spacer()
            switch balanceState {
            case .idle:
                Text("—")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .loading:
                ProgressView()
                    .controlSize(.small)
            case .refreshing(let value, let timestamp):
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value)
                        .font(.headline)
                        .foregroundStyle(chain.accentColor)
                    Text(relativeTimeDescription(from: timestamp).map { "Refreshing… • updated \($0)" } ?? "Refreshing…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .loaded(let value, let timestamp):
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value)
                        .font(.headline)
                        .foregroundStyle(chain.accentColor)
                    if let relative = relativeTimeDescription(from: timestamp) {
                        Text("Updated \(relative)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            case .stale(let value, let timestamp, let message):
                let detail: String = {
                    if let relative = relativeTimeDescription(from: timestamp) {
                        return "\(message) • updated \(relative)"
                    }
                    return message
                }()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value)
                        .font(.headline)
                        .foregroundStyle(chain.accentColor)
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            case .failed(let message):
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Unavailable")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            if let copyValue = balanceCopyValue {
                Button {
                    copyWithFeedback(value: copyValue, label: "\(chain.title) balance")
                } label: {
                    Label("Copy Balance", systemImage: "doc.on.doc")
                }
            }
        }
    }

    @ViewBuilder
    private var priceSummary: some View {
        HStack(alignment: .center, spacing: 12) {
            Label("Price", systemImage: "dollarsign.circle.fill")
                .font(.headline)
            Spacer()
            switch priceState {
            case .idle:
                Text("—")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .loading:
                ProgressView()
                    .controlSize(.small)
            case .refreshing(let value, let timestamp):
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value)
                        .font(.headline)
                        .foregroundStyle(chain.accentColor)
                    Text(relativeTimeDescription(from: timestamp).map { "Refreshing… • updated \($0)" } ?? "Refreshing…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .loaded(let value, let timestamp):
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value)
                        .font(.headline)
                        .foregroundStyle(chain.accentColor)
                    if let relative = relativeTimeDescription(from: timestamp) {
                        Text("Updated \(relative)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            case .stale(let value, let timestamp, let message):
                let detail: String = {
                    if let relative = relativeTimeDescription(from: timestamp) {
                        return "\(message) • updated \(relative)"
                    }
                    return message
                }()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value)
                        .font(.headline)
                        .foregroundStyle(chain.accentColor)
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            case .failed(let message):
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Unavailable")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            if let copyValue = priceCopyValue {
                Button {
                    copyWithFeedback(value: copyValue, label: "\(chain.title) price")
                } label: {
                    Label("Copy Price", systemImage: "dollarsign.circle")
                }
            }
        }
    }

    private var balanceCopyValue: String? {
        switch balanceState {
        case .refreshing(let value, _), .loaded(let value, _), .stale(let value, _, _):
            return value
        default:
            return nil
        }
    }

    private var priceCopyValue: String? {
        switch priceState {
        case .refreshing(let value, _), .loaded(let value, _), .stale(let value, _, _):
            return value
        default:
            return nil
        }
    }

    private func copyWithFeedback(value: String, label: String) {
        onCopy(value)
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task { @MainActor in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                copyFeedbackMessage = "\(label) copied"
            }
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation(.easeInOut(duration: 0.25)) {
                copyFeedbackMessage = nil
            }
        }
    }
}

private struct SecurityPromptView: View {
    let onReview: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Sensitive material locked")
                .font(.title3)
                .bold()
            Text("Review and acknowledge the security notice before generating wallet credentials. This helps ensure you understand the handling requirements for the generated keys.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Review Security Notice", action: onReview)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LockedStateView: View {
    let onUnlock: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.primary)
            Text("Session locked")
                .font(.title3)
                .bold()
            Text("Unlock with your passcode to view or copy any key material. Keys are automatically cleared when the app locks itself.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Unlock", action: onUnlock)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NoKeysPlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No key material available")
                .font(.title3)
                .bold()
            Text("Generate a fresh set of keys to review private values.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }
}

private struct SecurityNoticeView: View {
    let onAcknowledge: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Handle generated keys securely", systemImage: "lock.shield")
                        .font(.title2)
                        .bold()

                    Text("This tool produces private keys, recovery secrets, and wallet addresses. Treat everything shown in the app as confidential. Anyone with access to these keys can spend the associated funds.")

                    Text("Best practices")
                        .font(.headline)

                    bulletPoint("Never screenshot or share keys in plain text.")
                    bulletPoint("Store backups encrypted and offline whenever possible.")
                    bulletPoint("Clear key material before stepping away from the device.")
                    bulletPoint("Consider using hardware wallets for long-term storage.")

                    Divider()

                    Text("By tapping 'I Understand', you acknowledge the security implications and accept responsibility for safeguarding any generated keys.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Security Notice")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("I Understand") {
                        onAcknowledge()
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 500, height: 600)
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.callout)
            Text(text)
        }
        .font(.body)
    }
}

private struct SecuritySettingsView: View {
    let hasPasscode: Bool
    let onSetPasscode: (String) -> Void
    let onRemovePasscode: () -> Void
    let biometricState: BiometricState
    @Binding var biometricEnabled: Bool
    @Binding var biometricForSends: Bool
    @Binding var biometricForKeyReveal: Bool
    @Binding var autoLockSelection: AutoLockIntervalOption
    let onBiometricRequest: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var passcode = ""
    @State private var confirmPasscode = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Session Lock")) {
                    if hasPasscode {
                        Text("A passcode is currently required to unlock key material. You can remove it below or set a new one.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            onRemovePasscode()
                            dismiss()
                        } label: {
                            Label("Remove Passcode", systemImage: "lock.open")
                        }
                    } else {
                        Text("Add a passcode to require unlocking before any key data is shown. This clears keys when the app goes to the background.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(header: Text("Set New Passcode")) {
                    SecureField("New passcode", text: $passcode)
                        .textContentType(.password)
                    SecureField("Confirm passcode", text: $confirmPasscode)
                        .textContentType(.password)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button {
                        validateAndSave()
                    } label: {
                        Label("Save Passcode", systemImage: "lock")
                    }
                    .disabled(passcode.isEmpty || confirmPasscode.isEmpty)
                }

                Section(header: Text("Biometric Unlock")) {
                    Text(biometricState.statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if biometricState.supportsUnlock {
                        Toggle(isOn: $biometricEnabled) {
                            Label("Enable \(biometricLabel)", systemImage: biometricIcon)
                        }
                        .disabled(!hasPasscode)

                        if !hasPasscode {
                            Text("Set a passcode to turn on biometrics.")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        } else if biometricEnabled {
                            Button {
                                onBiometricRequest()
                            } label: {
                                Label("Test \(biometricLabel)", systemImage: "hand.raised.fill")
                            }
                        }
                    }
                }
                
                if BiometricAuthHelper.isBiometricAvailable {
                    Section(header: Text("Biometric Protection")) {
                        Toggle(isOn: $biometricForSends) {
                            Label("Require for Sends", systemImage: "paperplane.fill")
                        }
                        
                        Toggle(isOn: $biometricForKeyReveal) {
                            Label("Require for Key Reveal", systemImage: "key.fill")
                        }
                        
                        Text("When enabled, \(biometricLabel) will be required before sending funds or viewing private keys.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(header: Text("Auto-Lock Timer")) {
                    Picker("Auto-lock after", selection: $autoLockSelection) {
                        ForEach(AutoLockIntervalOption.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .disabled(!hasPasscode)

                    Text(autoLockSelection.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if !hasPasscode {
                        Text("Auto-lock requires a passcode so there’s something to lock to.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                
                // Duress Protection Section
                Section(header: Text("Duress Protection")) {
                    DuressProtectionRow(hasPasscode: hasPasscode)
                }
                
                // Inheritance Protocol Section
                Section(header: Text("Inheritance Protocol")) {
                    InheritanceProtocolRow()
                }
                
                // Geographic Security Section
                Section(header: Text("Location Security")) {
                    GeographicSecurityRow()
                }
                
                // Social Recovery Section
                Section(header: Text("Social Recovery")) {
                    SocialRecoveryRow()
                }
            }
            .navigationTitle("Security Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(width: 420, height: 750)
    }

    private func validateAndSave() {
        let trimmed = passcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else {
            errorMessage = "Choose at least 6 characters."
            return
        }
        guard trimmed == confirmPasscode.trimmingCharacters(in: .whitespacesAndNewlines) else {
            errorMessage = "Passcodes do not match."
            return
        }
        errorMessage = nil
        onSetPasscode(trimmed)
        dismiss()
    }

    private var biometricLabel: String {
        if case .available(let kind) = biometricState {
            return kind.displayName
        }
        return "Biometrics"
    }

    private var biometricIcon: String {
        if case .available(let kind) = biometricState {
            return kind.iconName
        }
        return "lock.circle"
    }
}

// MARK: - Duress Protection Row

private struct DuressProtectionRow: View {
    let hasPasscode: Bool
    @StateObject private var duressManager = DuressWalletManager.shared
    @State private var showDuressSetup = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: duressManager.isConfigured ? "shield.checkered" : "exclamationmark.shield")
                    .foregroundColor(duressManager.isConfigured ? .green : .orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Duress PIN")
                        .font(.body)
                    
                    Text(duressManager.isConfigured ? "Protected with decoy wallet" : "Not configured")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(duressManager.isConfigured ? "Manage" : "Set Up") {
                    showDuressSetup = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasPasscode)
            }
            
            if !hasPasscode {
                Text("Set a passcode first to enable duress protection.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else {
                Text("Create a secondary PIN that opens a decoy wallet with minimal funds. Use in coercion scenarios for plausible deniability.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            
            // Show duress mode indicator (only visible in real mode)
            if duressManager.isInDuressMode {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("Currently in duress mode")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(.top, 4)
            }
        }
        .sheet(isPresented: $showDuressSetup) {
            DuressSetupView()
        }
    }
}

// MARK: - Inheritance Protocol Row

private struct InheritanceProtocolRow: View {
    @StateObject private var manager = DeadMansSwitchManager.shared
    @State private var showInheritanceSetup = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: manager.isConfigured ? "person.2.badge.gearshape.fill" : "person.2.badge.gearshape")
                    .foregroundColor(manager.isConfigured ? .green : .blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dead Man's Switch")
                        .font(.body)
                    
                    if manager.isConfigured {
                        Text("\(manager.daysUntilTrigger ?? 0) days until trigger")
                            .font(.caption)
                            .foregroundColor(manager.warningLevel == .critical ? .red : 
                                           manager.warningLevel == .warning ? .orange : .secondary)
                    } else {
                        Text("Not configured")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if manager.isConfigured && manager.warningLevel != .none {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(manager.warningLevel == .critical ? .red : .orange)
                }
                
                Button(manager.isConfigured ? "Manage" : "Set Up") {
                    showInheritanceSetup = true
                }
                .buttonStyle(.borderedProminent)
            }
            
            Text("Automatically transfer funds to designated heirs after a period of inactivity. Trustless inheritance using blockchain timelocks.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showInheritanceSetup) {
            DeadMansSwitchView()
        }
    }
}

// MARK: - Geographic Security Row

private struct GeographicSecurityRow: View {
    @StateObject private var manager = GeographicSecurityManager.shared
    @State private var showGeoSecurity = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: manager.isEnabled ? "location.shield.fill" : "location.slash")
                    .font(.title2)
                    .foregroundStyle(manager.isEnabled ? .blue : .secondary)
                
                VStack(alignment: .leading) {
                    Text("Geographic Security")
                        .font(.headline)
                    
                    if manager.travelModeActive {
                        Text("Travel Mode Active")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if manager.isEnabled {
                        Text("\(manager.trustedZones.count) trusted zone(s)")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Text("Location protection disabled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Button(manager.isEnabled ? "Manage" : "Enable") {
                    showGeoSecurity = true
                }
                .buttonStyle(.borderedProminent)
            }
            
            Text("Restrict wallet access based on geographic location. Set trusted zones, enable travel mode, and add location-based transaction limits.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showGeoSecurity) {
            GeographicSecurityView()
        }
    }
}

// MARK: - Social Recovery Row

private struct SocialRecoveryRow: View {
    @StateObject private var multisigManager = MultisigManager.shared
    @State private var showSocialRecovery = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.3.fill")
                    .font(.title2)
                    .foregroundStyle(.purple)
                
                VStack(alignment: .leading) {
                    Text("Social Recovery")
                        .font(.headline)
                    
                    if !multisigManager.wallets.isEmpty {
                        Text("\(multisigManager.wallets.count) multisig wallet(s)")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Text("No multisig wallets configured")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Button("Configure") {
                    showSocialRecovery = true
                }
                .buttonStyle(.borderedProminent)
            }
            
            Text("Use trusted guardians to help recover your wallet if you lose access. Add friends, family, or hardware keys as recovery partners.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showSocialRecovery) {
            SocialRecoveryView()
        }
    }
}

private struct UnlockView: View {
    let supportsBiometrics: Bool
    let biometricButtonLabel: String
    let biometricButtonIcon: String
    let onBiometricRequest: () -> Void
    let onSubmit: (String) -> String?
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var passcode = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Unlock Session")
                    .font(.title3)
                    .bold()
                Text("Enter the passcode you set in Security Settings to reveal the generated key material.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                SecureField("Passcode", text: $passcode)
                    .textContentType(.password)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if supportsBiometrics {
                    Button {
                        onBiometricRequest()
                    } label: {
                        Label("Unlock with \(biometricButtonLabel)", systemImage: biometricButtonIcon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }

                HStack {
                    Button("Cancel", role: .cancel) {
                        onCancel()
                        dismiss()
                    }
                    Spacer()
                    Button("Unlock") {
                        let message = onSubmit(passcode)
                        if let message {
                            errorMessage = message
                            passcode = ""
                        } else {
                            errorMessage = nil
                            passcode = ""
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(minWidth: 360, minHeight: 220)
    }
}

private struct PasswordPromptView: View {
    enum Mode {
        case export
        case `import`

        var title: String {
            switch self {
            case .export: return "Encrypt Backup"
            case .import: return "Unlock Backup"
            }
        }

        var actionTitle: String {
            switch self {
            case .export: return "Export"
            case .import: return "Import"
            }
        }

        var description: String {
            switch self {
            case .export:
                return "Choose a strong passphrase. You will need it to restore this backup later."
            case .import:
                return "Enter the passphrase that was used when this backup was created."
            }
        }
    }

    let mode: Mode
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(mode.title)) {
                    Text(mode.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    SecureField("Passphrase", text: $password)
                        .textContentType(.password)

                    if mode == .export {
                        SecureField("Confirm passphrase", text: $confirmation)
                            .textContentType(.password)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.actionTitle) {
                        confirmAction()
                    }
                    .disabled(password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 360, minHeight: mode == .export ? 280 : 240)
    }

    private func confirmAction() {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else {
            errorMessage = "Use at least 8 characters."
            return
        }

        if mode == .export {
            let confirmTrimmed = confirmation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed == confirmTrimmed else {
                errorMessage = "Passphrases do not match."
                return
            }
        }

        errorMessage = nil
        onConfirm(trimmed)
        dismiss()
    }
}

private struct ImportPrivateKeySheet: View {
    let onImport: (String, String) -> Void
    let onCancel: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var privateKeyInput = ""
    @State private var selectedChain = "bitcoin"
    @State private var errorMessage: String?
    
    private let supportedChains = [
        ("bitcoin", "Bitcoin (WIF)", "bc1..."),
        ("bitcoin-testnet", "Bitcoin Testnet (WIF)", "tb1..."),
        ("ethereum", "Ethereum (Hex)", "0x..."),
        ("litecoin", "Litecoin (WIF)", "ltc1..."),
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Import Private Key")) {
                    Text("⚠️ Only import private keys you trust. Never share your private keys with anyone.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    
                    Picker("Chain", selection: $selectedChain) {
                        ForEach(supportedChains, id: \.0) { chain in
                            Text(chain.1).tag(chain.0)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Private Key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if let format = supportedChains.first(where: { $0.0 == selectedChain })?.2 {
                            Text("Format: \(format)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        
                        TextEditor(text: $privateKeyInput)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 100)
                            .border(Color.secondary.opacity(0.3))
                    }
                    
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                
                Section {
                    Text("Supported formats:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("• Bitcoin/Litecoin: WIF format (starts with K, L, or 5)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    
                    Text("• Ethereum: 64 hex characters (with or without 0x)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .navigationTitle("Import Private Key")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        importAction()
                    }
                    .disabled(privateKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 420)
    }
    
    private func importAction() {
        let trimmed = privateKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            errorMessage = "Private key cannot be empty"
            return
        }
        
        // Basic validation
        if selectedChain == "bitcoin" || selectedChain == "bitcoin-testnet" || selectedChain == "litecoin" {
            // WIF format validation
            guard trimmed.count >= 51 && trimmed.count <= 52 else {
                errorMessage = "Invalid WIF format. Should be 51-52 characters."
                return
            }
            let firstChar = trimmed.prefix(1)
            guard firstChar == "K" || firstChar == "L" || firstChar == "5" else {
                errorMessage = "Invalid WIF format. Should start with K, L, or 5."
                return
            }
        } else if selectedChain == "ethereum" {
            var hexString = trimmed
            if hexString.hasPrefix("0x") {
                hexString = String(hexString.dropFirst(2))
            }
            guard hexString.count == 64 else {
                errorMessage = "Invalid Ethereum private key. Should be 64 hex characters."
                return
            }
            guard hexString.allSatisfy({ $0.isHexDigit }) else {
                errorMessage = "Invalid hex characters in private key."
                return
            }
        }
        
        errorMessage = nil
        onImport(trimmed, selectedChain)
        dismiss()
    }
}

#if canImport(AppKit)
private final class UserActivityMonitor {
    private var tokens: [Any] = []

    init(handler: @escaping () -> Void) {
        let mask: NSEvent.EventTypeMask = [
            .keyDown,
            .flagsChanged,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .mouseMoved,
            .scrollWheel
        ]

        if let localToken = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            handler()
            return event
        }) {
            tokens.append(localToken)
        }

        if let globalToken = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { _ in
            handler()
        }) {
            tokens.append(globalToken)
        }
    }

    func stop() {
        for token in tokens {
            NSEvent.removeMonitor(token)
        }
        tokens.removeAll()
    }

    deinit {
        stop()
    }
}
#else
private final class UserActivityMonitor {
    init(handler: @escaping () -> Void) {}
    func stop() {}
}
#endif


// Preview disabled - use Xcode previews instead
// #Preview {
//     ContentView()
// }
