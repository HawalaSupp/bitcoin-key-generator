import SwiftUI
import CryptoKit
import UniformTypeIdentifiers
import Security
import LocalAuthentication
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

private enum OnboardingStep: Int {
    case welcome
    case security
    case passcode
    case ready
}

private enum FiatCurrency: String, CaseIterable, Identifiable {
    case usd = "USD"
    case eur = "EUR"
    case gbp = "GBP"
    case jpy = "JPY"
    case cad = "CAD"
    case aud = "AUD"
    case chf = "CHF"
    case cny = "CNY"
    case inr = "INR"
    case pln = "PLN"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .usd: return "US Dollar"
        case .eur: return "Euro"
        case .gbp: return "British Pound"
        case .jpy: return "Japanese Yen"
        case .cad: return "Canadian Dollar"
        case .aud: return "Australian Dollar"
        case .chf: return "Swiss Franc"
        case .cny: return "Chinese Yuan"
        case .inr: return "Indian Rupee"
        case .pln: return "Polish Złoty"
        }
    }

    var symbol: String {
        switch self {
        case .usd: return "$"
        case .eur: return "€"
        case .gbp: return "£"
        case .jpy: return "¥"
        case .cad: return "CA$"
        case .aud: return "A$"
        case .chf: return "CHF"
        case .cny: return "¥"
        case .inr: return "₹"
        case .pln: return "zł"
        }
    }

    var coingeckoID: String {
        rawValue.lowercased()
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System Default"
        case .light: return "Light Mode"
        case .dark: return "Dark Mode"
        }
    }

    var menuIconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

private enum AutoLockIntervalOption: Double, CaseIterable, Identifiable, Hashable {
    case immediate = 0
    case thirtySeconds = 30
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case never = -1

    var id: Double { rawValue }

    var label: String {
        switch self {
        case .immediate: return "Immediately"
        case .thirtySeconds: return "After 30 seconds"
        case .oneMinute: return "After 1 minute"
        case .fiveMinutes: return "After 5 minutes"
        case .fifteenMinutes: return "After 15 minutes"
        case .never: return "Never"
        }
    }

    var description: String {
        switch self {
        case .immediate:
            return "Lock whenever Hawala leaves the foreground."
        case .thirtySeconds:
            return "Lock after 30 seconds of inactivity."
        case .oneMinute:
            return "Lock after 1 minute of inactivity."
        case .fiveMinutes:
            return "Lock after 5 minutes of inactivity."
        case .fifteenMinutes:
            return "Lock after 15 minutes of inactivity."
        case .never:
            return "Keep sessions unlocked until manually locked or the app backgrounded."
        }
    }

    var duration: TimeInterval? {
        switch self {
        case .immediate:
            return 0
        case .never:
            return nil
        default:
            return rawValue >= 0 ? rawValue : nil
        }
    }
}

private enum BiometricState: Equatable {
    case unknown
    case available(BiometryKind)
    case unavailable(String)

    enum BiometryKind: String {
        case touchID
        case faceID
        case generic

        var displayName: String {
            switch self {
            case .touchID: return "Touch ID"
            case .faceID: return "Face ID"
            case .generic: return "Biometrics"
            }
        }

        var iconName: String {
            switch self {
            case .touchID: return "touchid"
            case .faceID: return "faceid"
            case .generic: return "lock.circle"
            }
        }
    }

    var supportsUnlock: Bool {
        if case .available = self { return true }
        return false
    }

    var statusMessage: String {
        switch self {
        case .unknown:
            return "Checking biometric capabilities…"
        case .available(let kind):
            return "Use \(kind.displayName) to unlock faster."
        case .unavailable(let reason):
            return reason
        }
    }
}

private struct ViewWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 900
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Result info passed back after successful transaction broadcast
struct TransactionBroadcastResult {
    let txid: String
    let chainId: String
    let chainName: String
    let amount: String
    let recipient: String
    let isRBFEnabled: Bool
    let feeRate: Int?
    let nonce: Int?
    
    init(txid: String, chainId: String, chainName: String, amount: String, recipient: String, isRBFEnabled: Bool = true, feeRate: Int? = nil, nonce: Int? = nil) {
        self.txid = txid
        self.chainId = chainId
        self.chainName = chainName
        self.amount = amount
        self.recipient = recipient
        self.isRBFEnabled = isRBFEnabled
        self.feeRate = feeRate
        self.nonce = nonce
    }
}

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
    @State private var showPerformanceOverlay = true  // Enabled for 120fps testing
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

                newestBuildBadge
                    .padding(.top, 12)
                    .padding(.trailing, 12)
                    .allowsHitTesting(false)
                
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
                    onGenerateKeys: {
                        guard hasAcknowledgedSecurityNotice else {
                            showSecurityNotice = true
                            return
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
        .sheet(isPresented: $showAllPrivateKeysSheet) {
            if let keys {
                AllPrivateKeysSheet(chains: keys.chainInfos, onCopy: copySensitiveToClipboard)
            } else {
                NoKeysPlaceholderView()
            }
        }
        .sheet(isPresented: $showReceiveSheet) {
            if let keys {
                ReceiveViewModern(chains: keys.chainInfos, onCopy: copyToClipboard)
                    .frame(minWidth: 500, minHeight: 650)
            } else {
                NoKeysPlaceholderView()
            }
        }
        .sheet(item: $sendChainContext, onDismiss: { sendChainContext = nil }) { chain in
            if let keys {
                SendView(keys: keys, initialChain: mapToChain(chain.id), onSuccess: { result in
                    handleTransactionSuccess(result)
                })
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
        }
        .sheet(isPresented: $showTransactionHistorySheet) {
            TransactionHistoryView()
                .frame(minWidth: 500, minHeight: 600)
        }
        .sheet(item: $selectedTransactionForDetail) { transaction in
            TransactionDetailSheet(transaction: transaction)
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
        OnboardingFlowView(
            step: $onboardingStep,
            onSecurityAcknowledged: {
                hasAcknowledgedSecurityNotice = true
            },
            onSetPasscode: { passcode in
                storedPasscodeHash = hashPasscode(passcode)
                isUnlocked = true
            },
            onSkipPasscode: {
                storedPasscodeHash = nil
                isUnlocked = true
            },
            onFinish: {
                shouldAutoGenerateAfterOnboarding = true
                completedOnboardingThisSession = true
                onboardingCompleted = true
            }
        )
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

    private struct OnboardingFlowView: View {
        @Binding var step: OnboardingStep
        let onSecurityAcknowledged: () -> Void
        let onSetPasscode: (String) -> Void
        let onSkipPasscode: () -> Void
        let onFinish: () -> Void

        @State private var passcode = ""
        @State private var confirmPasscode = ""
        @State private var errorMessage: String?
        @FocusState private var passcodeFieldFocused: Bool

        private var totalSteps: Double { 4 }

        var body: some View {
            VStack(alignment: .leading, spacing: 24) {
                header
                content
                Spacer()
                controls
            }
            .padding(32)
            .frame(minWidth: 560, minHeight: 520)
        }

        private var header: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome to Hawala")
                    .font(.largeTitle)
                    .bold()
                Text(stepSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Step \(step.rawValue + 1) of 4")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: Double(step.rawValue + 1), total: totalSteps)
                        .progressViewStyle(.linear)
                }
            }
        }

        @ViewBuilder
        private var content: some View {
            switch step {
            case .welcome:
                VStack(alignment: .leading, spacing: 16) {
                    Text("Let’s prepare your multi-chain vault with the right safeguards and workflows.")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 12) {
                        onboardingBullet("Generate secure keys across major chains in one flow.")
                        onboardingBullet("Encrypt backups and keep session data locked down.")
                        onboardingBullet("Track balances, history, and advanced features as we grow.")
                    }
                }
            case .security:
                VStack(alignment: .leading, spacing: 16) {
                    Label("Protect confidential material", systemImage: "lock.shield")
                        .font(.title3)
                        .bold()
                    Text("This app surfaces private keys, recovery phrases, and transaction secrets. Please review the essentials below before continuing:")
                        .font(.body)
                    VStack(alignment: .leading, spacing: 10) {
                        onboardingBullet("Never capture screenshots or paste keys into untrusted apps.")
                        onboardingBullet("Store any exports encrypted and keep them offline when possible.")
                        onboardingBullet("Clear the dashboard before leaving your device unattended.")
                        onboardingBullet("Use hardware wallets for long-term storage where practical.")
                    }
                }
            case .passcode:
                VStack(alignment: .leading, spacing: 16) {
                    Label("Secure the session", systemImage: "key.viewfinder")
                        .font(.title3)
                        .bold()
                    Text("Add a passcode to require unlocking before any generated keys are displayed. You can update this later in Security Settings.")
                        .font(.body)
                    VStack(alignment: .leading, spacing: 12) {
                        SecureField("Passcode", text: $passcode)
                            .textContentType(.password)
                            .focused($passcodeFieldFocused)
                        SecureField("Confirm passcode", text: $confirmPasscode)
                            .textContentType(.password)
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }
            case .ready:
                VStack(alignment: .leading, spacing: 16) {
                    Label("All set", systemImage: "checkmark.seal.fill")
                        .font(.title3)
                        .bold()
                    Text("Your security preferences are saved. Next up you can generate fresh keys, review chain-by-chain details, and manage encrypted backups from the dashboard.")
                        .font(.body)
                    onboardingBullet("Generate keys and review details per supported chain.")
                    onboardingBullet("Export encrypted backups for safekeeping.")
                    onboardingBullet("Toggle security settings anytime from the toolbar.")
                }
            }
        }

        @ViewBuilder
        private var controls: some View {
            switch step {
            case .welcome:
                HStack {
                    Spacer()
                    Button("Get Started") {
                        withAnimation { step = .security }
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .security:
                HStack {
                    backButton
                    Spacer()
                    Button("I Understand") {
                        onSecurityAcknowledged()
                        withAnimation { step = .passcode }
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .passcode:
                HStack {
                    backButton
                    Spacer()
                    Button("Skip for now") {
                        passcode = ""
                        confirmPasscode = ""
                        errorMessage = nil
                        onSkipPasscode()
                        withAnimation { step = .ready }
                    }
                    .buttonStyle(.bordered)
                    Button("Save Passcode") {
                        handlePasscodeSave()
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .ready:
                HStack {
                    backButton
                    Spacer()
                    Button("Enter Hawala") {
                        onFinish()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }

        private var backButton: some View {
            Button("Back") {
                withAnimation {
                    switch step {
                    case .welcome:
                        break
                    case .security:
                        step = .welcome
                    case .passcode:
                        step = .security
                    case .ready:
                        step = .passcode
                    }
                }
            }
            .buttonStyle(.bordered)
            .opacity(step == .welcome ? 0 : 1)
            .disabled(step == .welcome)
        }

        private var stepSubtitle: String {
            switch step {
            case .welcome:
                return "Configure your secure workspace before generating keys."
            case .security:
                return "Understand the responsibilities that come with handling private keys."
            case .passcode:
                return "Add session protection to keep key material hidden when idle."
            case .ready:
                return "Everything is in place—let’s launch your dashboard."
            }
        }

        private func onboardingBullet(_ text: String) -> some View {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.callout)
                Text(text)
            }
        }

        private func handlePasscodeSave() {
            let trimmed = passcode.trimmingCharacters(in: .whitespacesAndNewlines)
            let confirmation = confirmPasscode.trimmingCharacters(in: .whitespacesAndNewlines)

            guard trimmed.count >= 6 else {
                errorMessage = "Choose at least 6 characters."
                passcodeFieldFocused = true
                return
            }

            guard trimmed == confirmation else {
                errorMessage = "Passcodes do not match."
                confirmPasscode = ""
                passcodeFieldFocused = true
                return
            }

            errorMessage = nil
            onSetPasscode(trimmed)
            withAnimation { step = .ready }
        }
    }

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
        case "xrp": return "XRP"
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

        let targets = historyTargets(from: keys)
        if targets.isEmpty {
            isHistoryLoading = false
            historyEntries = []
            return
        }

        historyFetchTask = Task {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            var aggregated: [HawalaTransactionEntry] = []
            var successCount = 0
            var failureCount = 0

            for target in targets {
                if Task.isCancelled { return }

                switch target.id {
                case "ethereum", "ethereum-sepolia":
                    let entries = await fetchEthereumHistoryEntries(for: target)
                    if !entries.isEmpty {
                        print("📜 [\(target.id)] Fetched \(entries.count) transactions")
                        successCount += 1
                        aggregated.append(contentsOf: entries)
                    } else {
                        print("📜 [\(target.id)] No transactions found")
                        failureCount += 1
                    }
                case "bnb":
                    let entries = await fetchBNBHistoryEntries(for: target)
                    if !entries.isEmpty {
                        print("📜 [\(target.id)] Fetched \(entries.count) transactions")
                        successCount += 1
                        aggregated.append(contentsOf: entries)
                    } else {
                        print("📜 [\(target.id)] No transactions found")
                        failureCount += 1
                    }
                case "solana":
                    let entries = await fetchSolanaHistoryEntries(for: target)
                    if !entries.isEmpty {
                        print("📜 [\(target.id)] Fetched \(entries.count) transactions")
                        successCount += 1
                        aggregated.append(contentsOf: entries)
                    } else {
                        print("📜 [\(target.id)] No transactions found")
                        failureCount += 1
                    }
                case "xrp":
                    let entries = await fetchXRPHistoryEntries(for: target)
                    if !entries.isEmpty {
                        print("📜 [\(target.id)] Fetched \(entries.count) transactions")
                        successCount += 1
                        aggregated.append(contentsOf: entries)
                    } else {
                        print("📜 [\(target.id)] No transactions found")
                        failureCount += 1
                    }
                default:
                    // Bitcoin/Litecoin via direct API
                    let entries = await fetchBitcoinHistoryEntries(for: target)
                    if !entries.isEmpty {
                        print("📜 [\(target.id)] Fetched \(entries.count) transactions")
                        successCount += 1
                        aggregated.append(contentsOf: entries)
                    } else {
                        print("📜 [\(target.id)] No transactions found")
                        failureCount += 1
                    }
                }
            }

            print("📜 History fetch complete: \(successCount) chains succeeded, \(failureCount) failed, \(aggregated.count) total transactions")
            
            aggregated.sort { ($0.sortTimestamp ?? 0) > ($1.sortTimestamp ?? 0) }

            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.historyEntries = aggregated
                self.isHistoryLoading = false
                self.historyError = successCount == 0 && failureCount > 0 ? "Check your connection and try again." : nil
                self.historyFetchTask = nil
            }
        }
    }

    private func historyTargets(from keys: AllKeys) -> [HistoryChainTarget] {
        var targets: [HistoryChainTarget] = []
        var seenAddresses = Set<String>()

        func appendTarget(id: String, address: String, displayName: String, symbol: String) {
            guard !address.isEmpty, !seenAddresses.contains(address) else { return }
            seenAddresses.insert(address)
            targets.append(HistoryChainTarget(id: id, address: address, displayName: displayName, symbol: symbol))
        }

        appendTarget(id: "bitcoin", address: keys.bitcoin.address, displayName: "Bitcoin", symbol: "BTC")
        appendTarget(id: "bitcoin-testnet", address: keys.bitcoinTestnet.address, displayName: "Bitcoin Testnet", symbol: "tBTC")
        appendTarget(id: "litecoin", address: keys.litecoin.address, displayName: "Litecoin", symbol: "LTC")
        appendTarget(id: "ethereum", address: keys.ethereum.address, displayName: "Ethereum", symbol: "ETH")
        appendTarget(id: "ethereum-sepolia", address: keys.ethereumSepolia.address, displayName: "Ethereum Sepolia", symbol: "ETH")
        appendTarget(id: "bnb", address: keys.bnb.address, displayName: "BNB Chain", symbol: "BNB")
        appendTarget(id: "solana", address: keys.solana.publicKeyBase58, displayName: "Solana", symbol: "SOL")
        appendTarget(id: "xrp", address: keys.xrp.classicAddress, displayName: "XRP Ledger", symbol: "XRP")

        return targets
    }

    private static func makeHistoryEntry(from item: BitcoinHistoryItem, target: HistoryChainTarget) -> HawalaTransactionEntry {
        let isReceive = item.amountSats >= 0
        let direction = isReceive ? "Receive" : "Send"
        let amount = formatBitcoinAmount(abs(item.amountSats), symbol: target.symbol)
        let prefix = isReceive ? "+" : "-"
        let timestamp = timestampString(for: item.timestamp)
        
        // Format fee if available
        let feeString: String? = item.feeSats.map { sats in
            let feeValue = Double(sats) / 100_000_000.0
            return String(format: "%.8f", feeValue).trimmingCharacters(in: ["0"]).trimmingCharacters(in: ["."]) + " \(target.symbol)"
        }

        return HawalaTransactionEntry(
            id: "\(target.id)-\(item.txid)",
            type: direction,
            asset: target.displayName,
            amountDisplay: "\(prefix)\(amount)",
            status: item.confirmed ? "Confirmed" : "Pending",
            timestamp: timestamp,
            sortTimestamp: item.timestamp.map { TimeInterval($0) },
            txHash: item.txid,
            chainId: target.id,
            fee: feeString,
            blockNumber: item.height.map { Int($0) }
        )
    }

    private static func formatBitcoinAmount(_ sats: Int64, symbol: String) -> String {
        let value = Double(sats) / 100_000_000.0
        var string = String(format: "%.8f", value)

        if string.contains(".") {
            while string.last == "0" {
                string.removeLast()
            }
            if string.last == "." {
                string.removeLast()
            }
        }

        if string.isEmpty {
            string = "0"
        }

        return "\(string) \(symbol)"
    }

    private static func timestampString(for epoch: UInt64?) -> String {
        guard let epoch else { return "Pending" }
        let date = Date(timeIntervalSince1970: TimeInterval(epoch))
        return historyDateFormatter.string(from: date)
    }

    // MARK: - Bitcoin/Litecoin History Fetching (Blockstream/Litecoinspace API)
    
    private struct BlockstreamTransaction: Decodable {
        let txid: String
        let status: BlockstreamStatus
        let vin: [BlockstreamInput]
        let vout: [BlockstreamOutput]
        let fee: Int?
    }
    
    private struct BlockstreamStatus: Decodable {
        let confirmed: Bool
        let block_height: Int?
        let block_time: Int?
    }
    
    private struct BlockstreamInput: Decodable {
        let prevout: BlockstreamPrevout?
    }
    
    private struct BlockstreamPrevout: Decodable {
        let scriptpubkey_address: String?
        let value: Int
    }
    
    private struct BlockstreamOutput: Decodable {
        let scriptpubkey_address: String?
        let value: Int
    }
    
    private func fetchBitcoinHistoryEntries(for target: HistoryChainTarget) async -> [HawalaTransactionEntry] {
        let baseURL: String
        switch target.id {
        case "bitcoin-testnet":
            baseURL = "https://blockstream.info/testnet/api/address/\(target.address)/txs"
        case "litecoin":
            baseURL = "https://litecoinspace.org/api/address/\(target.address)/txs"
        default:
            baseURL = "https://blockstream.info/api/address/\(target.address)/txs"
        }
        
        guard let url = URL(string: baseURL) else {
            print("[\(target.id)] Invalid URL: \(baseURL)")
            return []
        }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Check for rate limiting
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 429 {
                    print("[\(target.id)] Rate limited")
                    return []
                }
                if httpResponse.statusCode != 200 {
                    print("[\(target.id)] HTTP error: \(httpResponse.statusCode)")
                    return []
                }
            }
            
            let transactions = try JSONDecoder().decode([BlockstreamTransaction].self, from: data)
            
            return transactions.prefix(50).compactMap { tx -> HawalaTransactionEntry? in
                // Calculate net amount for this address
                var inputSum: Int64 = 0
                var outputSum: Int64 = 0
                
                for vin in tx.vin {
                    if let prevout = vin.prevout, prevout.scriptpubkey_address == target.address {
                        inputSum += Int64(prevout.value)
                    }
                }
                
                for vout in tx.vout {
                    if vout.scriptpubkey_address == target.address {
                        outputSum += Int64(vout.value)
                    }
                }
                
                let netSats = outputSum - inputSum
                let isReceive = netSats > 0
                let direction = isReceive ? "Receive" : "Send"
                let prefix = isReceive ? "+" : "-"
                
                // Format amount
                let amountValue = Double(abs(netSats)) / 100_000_000.0
                let formattedAmount = formatCryptoAmount(amountValue, symbol: target.symbol)
                
                // Timestamp
                let timestamp: String
                let sortTimestamp: TimeInterval?
                if let blockTime = tx.status.block_time {
                    let date = Date(timeIntervalSince1970: TimeInterval(blockTime))
                    timestamp = Self.historyDateFormatter.string(from: date)
                    sortTimestamp = TimeInterval(blockTime)
                } else {
                    timestamp = "Pending"
                    sortTimestamp = Date().timeIntervalSince1970 // Sort pending at top
                }
                
                // Status
                let status = tx.status.confirmed ? "Confirmed" : "Pending"
                
                // Fee
                var feeString: String? = nil
                if let fee = tx.fee {
                    let feeBTC = Double(fee) / 100_000_000.0
                    feeString = String(format: "%.8f \(target.symbol)", feeBTC)
                        .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
                        .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
                }
                
                return HawalaTransactionEntry(
                    id: "\(target.id)-\(tx.txid)",
                    type: direction,
                    asset: target.displayName,
                    amountDisplay: "\(prefix)\(formattedAmount)",
                    status: status,
                    timestamp: timestamp,
                    sortTimestamp: sortTimestamp,
                    txHash: tx.txid,
                    chainId: target.id,
                    fee: feeString,
                    blockNumber: tx.status.block_height
                )
            }
        } catch {
            print("[\(target.id)] History fetch error: \(error.localizedDescription)")
            return []
        }
    }
    
    private func formatCryptoAmount(_ value: Double, symbol: String) -> String {
        var formatted: String
        if value < 0.00001 {
            formatted = String(format: "%.8f", value)
        } else if value < 0.01 {
            formatted = String(format: "%.6f", value)
        } else if value < 1 {
            formatted = String(format: "%.4f", value)
        } else {
            formatted = String(format: "%.2f", value)
        }
        
        // Remove trailing zeros after decimal
        if formatted.contains(".") {
            while formatted.last == "0" {
                formatted.removeLast()
            }
            if formatted.last == "." {
                formatted.removeLast()
            }
        }
        
        return "\(formatted) \(symbol)"
    }

    // MARK: - Ethereum History Fetching

    private struct EtherscanTxListResponse: Decodable {
        let status: String
        let message: String?
        let result: [EtherscanTx]?
        
        enum CodingKeys: String, CodingKey {
            case status, message, result
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            status = try container.decode(String.self, forKey: .status)
            message = try container.decodeIfPresent(String.self, forKey: .message)
            
            // Handle result being either an array or a string (error message)
            if let txArray = try? container.decode([EtherscanTx].self, forKey: .result) {
                result = txArray
            } else {
                // Result is a string (error message) - treat as no results
                result = nil
            }
        }
    }

    private struct EtherscanTx: Decodable {
        let hash: String
        let from: String
        let to: String
        let value: String
        let timeStamp: String
        let confirmations: String
        let isError: String?
        let gasUsed: String?
        let gasPrice: String?
        let blockNumber: String?
    }

    private func fetchEthereumHistoryEntries(for target: HistoryChainTarget) async -> [HawalaTransactionEntry] {
        // Use Blockscout API (no API key required) or Etherscan as fallback
        let entries = await fetchEthereumFromBlockscout(for: target)
        if !entries.isEmpty {
            return entries
        }
        
        // Fallback to Etherscan (works without key but rate limited)
        return await fetchEthereumFromEtherscan(for: target)
    }
    
    private func fetchEthereumFromBlockscout(for target: HistoryChainTarget) async -> [HawalaTransactionEntry] {
        let baseURL: String
        if target.id == "ethereum-sepolia" {
            baseURL = "https://eth-sepolia.blockscout.com/api/v2/addresses/\(target.address)/transactions"
        } else {
            baseURL = "https://eth.blockscout.com/api/v2/addresses/\(target.address)/transactions"
        }
        
        guard let url = URL(string: baseURL) else {
            return []
        }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return []
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else {
                return []
            }
            
            return items.prefix(50).compactMap { tx -> HawalaTransactionEntry? in
                guard let hash = tx["hash"] as? String,
                      let to = tx["to"] as? [String: Any],
                      let toHash = to["hash"] as? String else {
                    return nil
                }
                
                let _ = tx["from"] as? [String: Any]
                
                let isReceive = toHash.lowercased() == target.address.lowercased()
                let direction = isReceive ? "Receive" : "Send"
                let prefix = isReceive ? "+" : "-"
                
                // Parse value (in wei)
                let valueString = tx["value"] as? String ?? "0"
                let weiValue = Decimal(string: valueString) ?? 0
                let ethValue = weiValue / Decimal(string: "1000000000000000000")!
                let amount = NSDecimalNumber(decimal: ethValue).doubleValue
                let formattedAmount = formatCryptoAmount(amount, symbol: target.symbol)
                
                // Parse timestamp
                let timestampStr = tx["timestamp"] as? String ?? ""
                let timestamp: String
                let sortTimestamp: TimeInterval?
                if let date = ISO8601DateFormatter().date(from: timestampStr) {
                    timestamp = Self.historyDateFormatter.string(from: date)
                    sortTimestamp = date.timeIntervalSince1970
                } else {
                    timestamp = "Unknown"
                    sortTimestamp = nil
                }
                
                let status = (tx["status"] as? String) == "ok" ? "Confirmed" : "Pending"
                
                // Fee
                var feeString: String? = nil
                if let fee = tx["fee"] as? [String: Any],
                   let feeValue = fee["value"] as? String {
                    let feeWei = Decimal(string: feeValue) ?? 0
                    let feeEth = feeWei / Decimal(string: "1000000000000000000")!
                    let feeAmount = NSDecimalNumber(decimal: feeEth).doubleValue
                    feeString = String(format: "%.6f ETH", feeAmount)
                }
                
                let blockNum = tx["block"] as? Int
                
                return HawalaTransactionEntry(
                    id: "\(target.id)-\(hash)",
                    type: direction,
                    asset: target.displayName,
                    amountDisplay: "\(prefix)\(formattedAmount)",
                    status: status,
                    timestamp: timestamp,
                    sortTimestamp: sortTimestamp,
                    txHash: hash,
                    chainId: target.id,
                    fee: feeString,
                    blockNumber: blockNum
                )
            }
        } catch {
            print("[\(target.id)] Blockscout fetch error: \(error.localizedDescription)")
            return []
        }
    }
    
    private func fetchEthereumFromEtherscan(for target: HistoryChainTarget) async -> [HawalaTransactionEntry] {
        let baseURL: String
        if target.id == "ethereum-sepolia" {
            baseURL = "https://api-sepolia.etherscan.io/api"
        } else {
            baseURL = "https://api.etherscan.io/api"
        }

        // Note: Works without API key but heavily rate limited
        guard let url = URL(string: "\(baseURL)?module=account&action=txlist&address=\(target.address)&startblock=0&endblock=99999999&sort=desc") else {
            return []
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15

            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(EtherscanTxListResponse.self, from: data)

            guard let txs = response.result, !txs.isEmpty else { return [] }

            return txs.prefix(50).compactMap { tx -> HawalaTransactionEntry? in
                let isReceive = tx.to.lowercased() == target.address.lowercased()
                let direction = isReceive ? "Receive" : "Send"
                let prefix = isReceive ? "+" : "-"

                let weiValue = Decimal(string: tx.value) ?? 0
                let ethValue = weiValue / Decimal(string: "1000000000000000000")!
                let formattedAmount = String(format: "%.6f", NSDecimalNumber(decimal: ethValue).doubleValue)

                let timestamp: String
                if let epochInt = UInt64(tx.timeStamp) {
                    let date = Date(timeIntervalSince1970: TimeInterval(epochInt))
                    timestamp = Self.historyDateFormatter.string(from: date)
                } else {
                    timestamp = "Unknown"
                }

                let confirmations = Int(tx.confirmations) ?? 0
                let status = confirmations > 0 ? "Confirmed" : "Pending"
                
                // Calculate fee: gasUsed * gasPrice in ETH
                var feeString: String? = nil
                if let gasUsed = tx.gasUsed, let gasPrice = tx.gasPrice,
                   let gasUsedDecimal = Decimal(string: gasUsed),
                   let gasPriceDecimal = Decimal(string: gasPrice) {
                    let feeWei = gasUsedDecimal * gasPriceDecimal
                    let feeEth = feeWei / Decimal(string: "1000000000000000000")!
                    let feeValue = NSDecimalNumber(decimal: feeEth).doubleValue
                    feeString = String(format: "%.6f ETH", feeValue)
                }
                
                let blockNum = tx.blockNumber.flatMap { Int($0) }

                return HawalaTransactionEntry(
                    id: "\(target.id)-\(tx.hash)",
                    type: direction,
                    asset: target.displayName,
                    amountDisplay: "\(prefix)\(formattedAmount) \(target.symbol)",
                    status: status,
                    timestamp: timestamp,
                    sortTimestamp: UInt64(tx.timeStamp).map { TimeInterval($0) },
                    txHash: tx.hash,
                    chainId: target.id,
                    confirmations: confirmations,
                    fee: feeString,
                    blockNumber: blockNum
                )
            }
        } catch {
            print("Ethereum history fetch error: \(error)")
            return []
        }
    }

    // MARK: - Solana History Fetching

    private struct SolanaSignaturesResponse: Decodable {
        let result: [SolanaSignatureInfo]?
    }

    private struct SolanaSignatureInfo: Decodable {
        let signature: String
        let blockTime: Int?
        let confirmationStatus: String?
        let err: AnyCodable?
    }

    private struct AnyCodable: Decodable {
        init(from decoder: Decoder) throws {
            _ = try decoder.singleValueContainer()
        }
    }

    private func fetchSolanaHistoryEntries(for target: HistoryChainTarget) async -> [HawalaTransactionEntry] {
        let rpcURL = "https://api.mainnet-beta.solana.com"

        guard let url = URL(string: rpcURL) else { return [] }

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getSignaturesForAddress",
            "params": [target.address, ["limit": 50]]
        ]

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(SolanaSignaturesResponse.self, from: data)

            guard let signatures = response.result, !signatures.isEmpty else { return [] }

            return signatures.compactMap { sig -> HawalaTransactionEntry? in
                let timestamp: String
                if let blockTime = sig.blockTime {
                    let date = Date(timeIntervalSince1970: TimeInterval(blockTime))
                    timestamp = Self.historyDateFormatter.string(from: date)
                } else {
                    timestamp = "Pending"
                }

                let status: String
                if sig.err != nil {
                    status = "Failed"
                } else if sig.confirmationStatus == "finalized" {
                    status = "Confirmed"
                } else {
                    status = sig.confirmationStatus?.capitalized ?? "Pending"
                }

                return HawalaTransactionEntry(
                    id: "\(target.id)-\(sig.signature)",
                    type: "Transaction",
                    asset: target.displayName,
                    amountDisplay: "View details",
                    status: status,
                    timestamp: timestamp,
                    sortTimestamp: sig.blockTime.map { TimeInterval($0) },
                    txHash: sig.signature,
                    chainId: target.id
                )
            }
        } catch {
            print("Solana history fetch error: \(error)")
            return []
        }
    }
    
    // MARK: - BNB (BSC) History Fetching
    
    private struct BscScanTxListResponse: Decodable {
        let status: String
        let message: String?
        let result: [BscScanTx]?
        
        enum CodingKeys: String, CodingKey {
            case status, message, result
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            status = try container.decode(String.self, forKey: .status)
            message = try container.decodeIfPresent(String.self, forKey: .message)
            
            // Handle result being either an array or a string (error message)
            if let txArray = try? container.decode([BscScanTx].self, forKey: .result) {
                result = txArray
            } else {
                result = nil
            }
        }
    }
    
    private struct BscScanTx: Decodable {
        let hash: String
        let from: String
        let to: String
        let value: String
        let timeStamp: String
        let confirmations: String
        let isError: String?
        let gasUsed: String?
        let gasPrice: String?
        let blockNumber: String?
    }
    
    private func fetchBNBHistoryEntries(for target: HistoryChainTarget) async -> [HawalaTransactionEntry] {
        // Try Blockscout for BSC first (no API key required)
        let blockscoutEntries = await fetchBNBFromBlockscout(for: target)
        if !blockscoutEntries.isEmpty {
            return blockscoutEntries
        }
        
        // Fallback to BscScan (works without key but rate limited)
        guard let url = URL(string: "https://api.bscscan.com/api?module=account&action=txlist&address=\(target.address)&startblock=0&endblock=99999999&sort=desc") else {
            return []
        }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(BscScanTxListResponse.self, from: data)
            
            guard let txs = response.result, !txs.isEmpty else { return [] }
            
            return txs.prefix(50).compactMap { tx -> HawalaTransactionEntry? in
                let isReceive = tx.to.lowercased() == target.address.lowercased()
                let direction = isReceive ? "Receive" : "Send"
                let prefix = isReceive ? "+" : "-"
                
                let weiValue = Decimal(string: tx.value) ?? 0
                let bnbValue = weiValue / Decimal(string: "1000000000000000000")!
                let formattedAmount = String(format: "%.6f", NSDecimalNumber(decimal: bnbValue).doubleValue)
                
                let timestamp: String
                if let epochInt = UInt64(tx.timeStamp) {
                    let date = Date(timeIntervalSince1970: TimeInterval(epochInt))
                    timestamp = Self.historyDateFormatter.string(from: date)
                } else {
                    timestamp = "Unknown"
                }
                
                let confirmations = Int(tx.confirmations) ?? 0
                let status = confirmations > 0 ? "Confirmed" : "Pending"
                
                // Calculate fee: gasUsed * gasPrice in BNB
                var feeString: String? = nil
                if let gasUsed = tx.gasUsed, let gasPrice = tx.gasPrice,
                   let gasUsedDecimal = Decimal(string: gasUsed),
                   let gasPriceDecimal = Decimal(string: gasPrice) {
                    let feeWei = gasUsedDecimal * gasPriceDecimal
                    let feeBnb = feeWei / Decimal(string: "1000000000000000000")!
                    let feeValue = NSDecimalNumber(decimal: feeBnb).doubleValue
                    feeString = String(format: "%.6f BNB", feeValue)
                }
                
                let blockNum = tx.blockNumber.flatMap { Int($0) }
                
                return HawalaTransactionEntry(
                    id: "\(target.id)-\(tx.hash)",
                    type: direction,
                    asset: target.displayName,
                    amountDisplay: "\(prefix)\(formattedAmount) \(target.symbol)",
                    status: status,
                    timestamp: timestamp,
                    sortTimestamp: UInt64(tx.timeStamp).map { TimeInterval($0) },
                    txHash: tx.hash,
                    chainId: target.id,
                    confirmations: confirmations,
                    fee: feeString,
                    blockNumber: blockNum
                )
            }
        } catch {
            print("BNB history fetch error: \(error)")
            return []
        }
    }
    
    private func fetchBNBFromBlockscout(for target: HistoryChainTarget) async -> [HawalaTransactionEntry] {
        guard let url = URL(string: "https://bsc.blockscout.com/api/v2/addresses/\(target.address)/transactions") else {
            return []
        }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return []
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else {
                return []
            }
            
            return items.prefix(50).compactMap { tx -> HawalaTransactionEntry? in
                guard let hash = tx["hash"] as? String,
                      let to = tx["to"] as? [String: Any],
                      let toHash = to["hash"] as? String else {
                    return nil
                }
                
                let isReceive = toHash.lowercased() == target.address.lowercased()
                let direction = isReceive ? "Receive" : "Send"
                let prefix = isReceive ? "+" : "-"
                
                let valueString = tx["value"] as? String ?? "0"
                let weiValue = Decimal(string: valueString) ?? 0
                let bnbValue = weiValue / Decimal(string: "1000000000000000000")!
                let amount = NSDecimalNumber(decimal: bnbValue).doubleValue
                let formattedAmount = formatCryptoAmount(amount, symbol: target.symbol)
                
                let timestampStr = tx["timestamp"] as? String ?? ""
                let timestamp: String
                let sortTimestamp: TimeInterval?
                if let date = ISO8601DateFormatter().date(from: timestampStr) {
                    timestamp = Self.historyDateFormatter.string(from: date)
                    sortTimestamp = date.timeIntervalSince1970
                } else {
                    timestamp = "Unknown"
                    sortTimestamp = nil
                }
                
                let status = (tx["status"] as? String) == "ok" ? "Confirmed" : "Pending"
                
                var feeString: String? = nil
                if let fee = tx["fee"] as? [String: Any],
                   let feeValue = fee["value"] as? String {
                    let feeWei = Decimal(string: feeValue) ?? 0
                    let feeBnb = feeWei / Decimal(string: "1000000000000000000")!
                    feeString = String(format: "%.6f BNB", NSDecimalNumber(decimal: feeBnb).doubleValue)
                }
                
                return HawalaTransactionEntry(
                    id: "\(target.id)-\(hash)",
                    type: direction,
                    asset: target.displayName,
                    amountDisplay: "\(prefix)\(formattedAmount)",
                    status: status,
                    timestamp: timestamp,
                    sortTimestamp: sortTimestamp,
                    txHash: hash,
                    chainId: target.id,
                    fee: feeString,
                    blockNumber: tx["block"] as? Int
                )
            }
        } catch {
            print("[BNB Blockscout] Fetch error: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - XRP History Fetching
    
    private struct XRPLAccountTxResponse: Decodable {
        let result: XRPLAccountTxResult?
    }
    
    private struct XRPLAccountTxResult: Decodable {
        let transactions: [XRPLTransactionWrapper]?
    }
    
    private struct XRPLTransactionWrapper: Decodable {
        let tx: XRPLTransaction?
        let meta: XRPLMeta?
        let validated: Bool?
    }
    
    private struct XRPLTransaction: Decodable {
        let hash: String?
        let Account: String?
        let Destination: String?
        let Amount: XRPLAmount?
        let date: Int?
        let TransactionType: String?
        let Fee: String?
        let ledger_index: Int?
    }
    
    private enum XRPLAmount: Decodable {
        case drops(String)
        case token(XRPLTokenAmount)
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let drops = try? container.decode(String.self) {
                self = .drops(drops)
            } else if let token = try? container.decode(XRPLTokenAmount.self) {
                self = .token(token)
            } else {
                self = .drops("0")
            }
        }
        
        var xrpValue: Double {
            switch self {
            case .drops(let drops):
                return (Double(drops) ?? 0) / 1_000_000.0
            case .token:
                return 0 // Token transfers shown differently
            }
        }
    }
    
    private struct XRPLTokenAmount: Decodable {
        let value: String
        let currency: String
        let issuer: String?
    }
    
    private struct XRPLMeta: Decodable {
        let TransactionResult: String?
    }
    
    private func fetchXRPHistoryEntries(for target: HistoryChainTarget) async -> [HawalaTransactionEntry] {
        // XRPL JSON-RPC
        guard let url = URL(string: "https://xrplcluster.com/") else { return [] }
        
        let payload: [String: Any] = [
            "method": "account_tx",
            "params": [[
                "account": target.address,
                "ledger_index_min": -1,
                "ledger_index_max": -1,
                "limit": 50
            ]]
        ]
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(XRPLAccountTxResponse.self, from: data)
            
            guard let transactions = response.result?.transactions, !transactions.isEmpty else { return [] }
            
            return transactions.compactMap { wrapper -> HawalaTransactionEntry? in
                guard let tx = wrapper.tx,
                      let hash = tx.hash,
                      tx.TransactionType == "Payment" else { return nil }
                
                let isReceive = tx.Destination?.lowercased() == target.address.lowercased()
                let direction = isReceive ? "Receive" : "Send"
                let prefix = isReceive ? "+" : "-"
                
                let xrpValue = tx.Amount?.xrpValue ?? 0
                let formattedAmount = String(format: "%.6f", xrpValue)
                
                // XRP ledger epoch starts at 2000-01-01 00:00:00 UTC (946684800 seconds after Unix epoch)
                let timestamp: String
                if let rippleTime = tx.date {
                    let unixTime = TimeInterval(rippleTime) + 946684800
                    let date = Date(timeIntervalSince1970: unixTime)
                    timestamp = Self.historyDateFormatter.string(from: date)
                } else {
                    timestamp = "Unknown"
                }
                
                let status: String
                if let result = wrapper.meta?.TransactionResult, result == "tesSUCCESS" {
                    status = wrapper.validated == true ? "Confirmed" : "Pending"
                } else {
                    status = "Failed"
                }
                
                // XRP fee is in drops (1 XRP = 1,000,000 drops)
                var feeString: String? = nil
                if let feeDrops = tx.Fee, let feeValue = Double(feeDrops) {
                    let feeXRP = feeValue / 1_000_000.0
                    feeString = String(format: "%.6f XRP", feeXRP)
                }
                
                return HawalaTransactionEntry(
                    id: "\(target.id)-\(hash)",
                    type: direction,
                    asset: target.displayName,
                    amountDisplay: "\(prefix)\(formattedAmount) \(target.symbol)",
                    status: status,
                    timestamp: timestamp,
                    sortTimestamp: tx.date.map { TimeInterval($0) + 946684800 },
                    txHash: hash,
                    chainId: target.id,
                    fee: feeString,
                    blockNumber: tx.ledger_index
                )
            }
        } catch {
            print("XRP history fetch error: \(error)")
            return []
        }
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
        
        // For now, return a placeholder signature
        // In production, use the private key to sign the message
        // The message format is: keccak256("\x19Ethereum Signed Message:\n" + len(message) + message)
        
        print("📝 WalletConnect: Personal sign request for message: \(message)")
        
        // TODO: Implement actual message signing with private key
        // This requires importing a crypto library or using the Rust backend
        return "0x" + String(repeating: "0", count: 130) // Placeholder
    }
    
    /// Sign typed data (EIP-712)
    private func signTypedData(_ request: WCSessionRequest) async throws -> String {
        guard let params = request.params as? [Any],
              params.count >= 2 else {
            throw WCError.requestTimeout
        }
        
        print("📝 WalletConnect: Typed data sign request")
        
        // TODO: Implement EIP-712 signing
        return "0x" + String(repeating: "0", count: 130) // Placeholder
    }
    
    /// Sign or send a transaction
    private func signTransaction(_ request: WCSessionRequest) async throws -> String {
        guard let params = request.params as? [[String: Any]],
              let txParams = params.first else {
            throw WCError.requestTimeout
        }
        
        print("📝 WalletConnect: Transaction sign request")
        print("   From: \(txParams["from"] ?? "unknown")")
        print("   To: \(txParams["to"] ?? "unknown")")
        print("   Value: \(txParams["value"] ?? "0")")
        print("   Data: \(txParams["data"] ?? "0x")")
        
        // TODO: Build and sign the transaction using the wallet's private key
        // For now, return a placeholder transaction hash
        return "0x" + String(repeating: "0", count: 64) // Placeholder tx hash
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
        if chainId.starts(with: "ethereum") { return .ethereum }
        if chainId == "solana" { return .solana }
        if chainId == "xrp" { return .xrp }
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
            print("ℹ️ Keys already loaded, skipping Keychain load")
            return
        }
        
        do {
            if let loadedKeys = try KeychainHelper.loadKeys() {
                keys = loadedKeys
                rawJSON = prettyPrintedJSON(from: try JSONEncoder().encode(loadedKeys))
                primeStateCaches(for: loadedKeys)
                print("✅ Loaded keys from Keychain")
                print("🔑 Bitcoin Testnet Address: \(loadedKeys.bitcoinTestnet.address)")
                
                // Mark onboarding as completed since user has existing keys
                if !onboardingCompleted {
                    onboardingCompleted = true
                    print("✅ Marking onboarding as completed (keys found in Keychain)")
                }
                
                startBalanceFetch(for: loadedKeys)
                startPriceUpdatesIfNeeded()
                refreshTransactionHistory(force: true)
            } else {
                print("ℹ️ No keys found in Keychain")
            }
        } catch {
            print("⚠️ Failed to load keys from Keychain: \(error)")
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
        
        if !assetCache.cachedBalances.isEmpty {
            print("📦 Loaded \(assetCache.cachedBalances.count) cached balances, \(assetCache.cachedPrices.count) cached prices")
        }
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
        guard hasAcknowledgedSecurityNotice, canAccessSensitiveData else { return }
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
                
                // Debug addresses
                print("🔑 Generated Bitcoin Testnet Address: \(result.bitcoinTestnet.address)")
                print("🔑 Generated Bitcoin Mainnet Address: \(result.bitcoin.address)")
                
                // Save to Keychain
                do {
                    try KeychainHelper.saveKeys(result)
                    print("✅ Keys saved to Keychain")
                } catch {
                    print("⚠️ Failed to save keys to Keychain: \(error)")
                }
                
                // Debug status
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

        print("🔄 Starting encrypted import...")
        print("📦 Archive size: \(archiveData.count) bytes")
        
        do {
            let plaintext = try decryptArchive(archiveData, password: password)
            print("✅ Decryption successful, plaintext size: \(plaintext.count) bytes")
            
            // Debug: print first 200 characters of JSON
            if let jsonString = String(data: plaintext, encoding: .utf8) {
                print("📄 JSON preview: \(String(jsonString.prefix(200)))...")
            }
            
            let decoder = JSONDecoder()
            // Don't use convertFromSnakeCase because AllKeys already has custom CodingKeys
            let importedKeys = try decoder.decode(AllKeys.self, from: plaintext)
            print("✅ Keys decoded successfully")
            
            keys = importedKeys
            rawJSON = prettyPrintedJSON(from: plaintext)
            
            // Debug imported addresses
            print("🔑 Imported Bitcoin Testnet Address: \(importedKeys.bitcoinTestnet.address)")
            print("🔑 Imported Bitcoin Mainnet Address: \(importedKeys.bitcoin.address)")
            
            // Save to Keychain
            do {
                try KeychainHelper.saveKeys(importedKeys)
                print("✅ Imported keys saved to Keychain")
            } catch {
                print("⚠️ Failed to save imported keys to Keychain: \(error)")
            }
            
            primeStateCaches(for: importedKeys)
            startBalanceFetch(for: importedKeys)
            startPriceUpdatesIfNeeded()
            refreshTransactionHistory(force: true)
            pendingImportData = nil
            showStatus("Encrypted backup imported successfully. Keys loaded.", tone: .success)
            print("✅ Import complete - UI should now show keys")
        } catch let DecodingError.keyNotFound(key, context) {
            print("❌ Missing key: \(key.stringValue)")
            print("❌ Context: \(context.debugDescription)")
            print("❌ Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            showStatus("Import failed: Missing required field '\(key.stringValue)'", tone: .error, autoClear: false)
        } catch let DecodingError.typeMismatch(type, context) {
            print("❌ Type mismatch for type: \(type)")
            print("❌ Context: \(context.debugDescription)")
            print("❌ Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            showStatus("Import failed: Invalid data format", tone: .error, autoClear: false)
        } catch {
            print("❌ Import failed: \(error)")
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
        return HKDF<SHA256>.deriveKey(
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

    private nonisolated static func resolveCargoExecutable() throws -> String {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment

        if let override = environment["CARGO_BIN"], fileManager.isExecutableFile(atPath: override) {
            return override
        }

        for path in candidateCargoPaths() {
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }

        if let whichPath = try locateCargoWithWhich(), fileManager.isExecutableFile(atPath: whichPath) {
            return whichPath
        }

        throw KeyGeneratorError.cargoNotFound
    }

    private nonisolated static func candidateCargoPaths() -> [String] {
        var paths: [String] = []
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        paths.append("\(home)/.cargo/bin/cargo")
        paths.append(contentsOf: [
            "/opt/homebrew/bin/cargo",
            "/usr/local/bin/cargo",
            "/usr/bin/cargo"
        ])
        return paths
    }

    private nonisolated static func locateCargoWithWhich() throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "cargo"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    private nonisolated static func mergedEnvironment(forCargoExecutableAt path: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let cargoDirectory = (path as NSString).deletingLastPathComponent
        var segments = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        if !segments.contains(cargoDirectory) {
            segments.insert(cargoDirectory, at: 0)
        }
        environment["PATH"] = segments.joined(separator: ":")
        environment["CARGO_BIN"] = path
        return environment
    }

    private func runRustKeyGenerator() async throws -> (AllKeys, String) {
        // Run cargo resolution in a detached task to avoid blocking the main thread
        let cargoPath = try await Task.detached {
            try ContentView.resolveCargoExecutable()
        }.value

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "cargo",
                "run",
                "--manifest-path",
                manifestPath,
                "--quiet",
                "--",
                "--json"
            ]
            process.currentDirectoryURL = workspaceRoot
            process.environment = ContentView.mergedEnvironment(forCargoExecutableAt: cargoPath)

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            process.terminationHandler = { proc in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                let outputString = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let errorString = String(data: errorData, encoding: .utf8) ?? ""

                guard proc.terminationStatus == 0 else {
                    let message = errorString.isEmpty ? "Rust generator failed with exit code \(proc.terminationStatus)" : errorString
                    continuation.resume(throwing: KeyGeneratorError.executionFailed(message))
                    return
                }

                guard let jsonData = outputString.data(using: .utf8) else {
                    continuation.resume(throwing: KeyGeneratorError.executionFailed("Invalid UTF-8 output from generator"))
                    return
                }

                do {
                    let decoder = JSONDecoder()
                    // The Rust CLI returns { "mnemonic": "...", "keys": {...} }
                    let response = try decoder.decode(WalletResponse.self, from: jsonData)
                    continuation.resume(returning: (response.keys, outputString))
                } catch {
                    print("Key decode failed: \(error)")
                    print("Raw output: \(outputString)")
                    continuation.resume(throwing: error)
                }
            }

            do {
                try process.run()
            } catch {
                let wrapped = KeyGeneratorError.executionFailed("Failed to launch cargo using \(cargoPath): \(error.localizedDescription)")
                continuation.resume(throwing: wrapped)
            }
        }
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
            print("✅ Keys deleted from Keychain")
        } catch {
            print("⚠️ Failed to delete keys from Keychain: \(error)")
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
                print("Failed to fetch FX rates: \(error)")
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
            print("⚠️ Balance fetch error for \(chainId): \(friendlyMessage) – \(error.localizedDescription). Next retry in \(formattedDelay)\(addressHint)")
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
            print("⚠️ All Bitcoin balance providers failed: \(error.localizedDescription)")
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
                print("📡 Trying Alchemy for SOL balance...")
                let sol = try await MultiProviderAPI.shared.fetchSolanaBalanceViaAlchemy(address: address)
                return formatCryptoAmount(sol, symbol: "SOL", maxFractionDigits: 6)
            } catch {
                print("⚠️ Alchemy SOL failed: \(error.localizedDescription)")
            }
        }
        
        // Use MultiProviderAPI with automatic fallbacks across multiple RPC endpoints
        do {
            let sol = try await MultiProviderAPI.shared.fetchSolanaBalance(address: address)
            return formatCryptoAmount(sol, symbol: "SOL", maxFractionDigits: 6)
        } catch {
            print("⚠️ All Solana balance providers failed: \(error.localizedDescription)")
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
            print("⚠️ Ripple Data API lookup failed for \(shortened)…: \(error.localizedDescription). Trying XRPSCAN next.")
        }

        do {
            return try await fetchXrpBalanceViaXrpScan(address: address)
        } catch {
            print("⚠️ XRPSCAN lookup failed for \(shortened)…: \(error.localizedDescription). Falling back to XRPL RPC endpoints.")
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
                print("⚠️ XRPL RPC \(endpoint) failed for \(shortened)…: \(error.localizedDescription)")
                lastError = error
                continue
            }
        }

        print("❌ All XRPL RPC endpoints exhausted for \(shortened)…")
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
                print("📡 Trying Alchemy for ETH balance...")
                return try await fetchEthereumBalanceViaAlchemy(address: address)
            } catch {
                print("⚠️ Alchemy ETH failed: \(error.localizedDescription)")
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
        let digest = SHA256.hash(data: data)
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

// MARK: - Bitcoin Transaction Types

private struct BitcoinUTXO: Codable {
    let txid: String
    let vout: Int
    let value: Int64
    let scriptpubkey: String
    let status: UTXOStatus
    
    struct UTXOStatus: Codable {
        let confirmed: Bool
        let blockHeight: Int?
        let blockHash: String?
        let blockTime: Int?
        
        enum CodingKeys: String, CodingKey {
            case confirmed
            case blockHeight = "block_height"
            case blockHash = "block_hash"
            case blockTime = "block_time"
        }
    }
}

struct BitcoinFeeEstimates: Codable {
    let fastestFee: Int
    let halfHourFee: Int
    let hourFee: Int
    let economyFee: Int
    let minimumFee: Int
}

enum EthGasSpeed: String, CaseIterable {
    case slow = "Slow"
    case standard = "Standard"
    case fast = "Fast"
    case instant = "Instant"
    
    var multiplier: Double {
        switch self {
        case .slow: return 0.8
        case .standard: return 1.0
        case .fast: return 1.3
        case .instant: return 1.6
        }
    }
    
    var estimatedTime: String {
        switch self {
        case .slow: return "~5 min"
        case .standard: return "~2 min"
        case .fast: return "~30 sec"
        case .instant: return "~15 sec"
        }
    }
    
    var icon: String {
        switch self {
        case .slow: return "tortoise.fill"
        case .standard: return "hare.fill"
        case .fast: return "bolt.fill"
        case .instant: return "bolt.horizontal.fill"
        }
    }
}

struct EthGasEstimates {
    let baseFee: Double // Gwei
    let slowPriorityFee: Double
    let standardPriorityFee: Double
    let fastPriorityFee: Double
    let instantPriorityFee: Double
    
    func gasPriceFor(_ speed: EthGasSpeed) -> Double {
        let priorityFee: Double
        switch speed {
        case .slow: priorityFee = slowPriorityFee
        case .standard: priorityFee = standardPriorityFee
        case .fast: priorityFee = fastPriorityFee
        case .instant: priorityFee = instantPriorityFee
        }
        return baseFee + priorityFee
    }
}

private enum BitcoinSendError: LocalizedError {
    case invalidAddress
    case insufficientFunds
    case amountTooLow
    case networkError(String)
    case signingFailed
    case broadcastFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "Invalid Bitcoin address"
        case .insufficientFunds:
            return "Insufficient balance to cover amount + fees"
        case .amountTooLow:
            return "Amount must be greater than dust limit (546 sats)"
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .signingFailed:
            return "Failed to sign transaction"
        case .broadcastFailed(let msg):
            return "Broadcast failed: \(msg)"
        }
    }
}

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

// MARK: - Bitcoin Send Sheet

private struct BitcoinSendSheet: View {
    let chain: ChainInfo
    let keys: AllKeys
    let requireBiometric: Bool
    let onDismiss: () -> Void
    let onSuccess: (TransactionBroadcastResult) -> Void
    
    var body: some View {
        NavigationStack {
            BitcoinSendView(
                chain: chain,
                keys: keys,
                requireBiometric: requireBiometric,
                onDismiss: onDismiss,
                onSuccess: onSuccess,
                isPushed: false
            )
        }
        .frame(width: 480, height: 650)
    }

    enum FeeRate: String, CaseIterable {
        case fast = "Fast (~10 min)"
        case medium = "Medium (~30 min)"
        case slow = "Slow (~1 hour)"
        case economy = "Economy (~6+ hours)"
        
        var priority: Int {
            switch self {
            case .fast: return 0
            case .medium: return 1
            case .slow: return 2
            case .economy: return 3
            }
        }
    }
}

private struct BitcoinSendView: View {
    let chain: ChainInfo
    let keys: AllKeys
    let requireBiometric: Bool
    let onDismiss: () -> Void
    let onSuccess: (TransactionBroadcastResult) -> Void
    let isPushed: Bool
    
    @Environment(\.dismiss) private var dismiss
    @State private var recipientAddress = ""
    @State private var amountCrypto = ""
    @State private var selectedFeeRate: BitcoinSendSheet.FeeRate = .medium
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var feeEstimates: BitcoinFeeEstimates?
    @State private var availableBalance: Int64 = 0
    @State private var balanceLoaded = false  // Track if balance fetch completed (even if 0)
    @State private var estimatedFee: Int64 = 0
    @State private var showConfirmation = false
    @State private var amountValidation: AmountValidationResult = .empty
    @State private var addressValidation: AddressValidationResult = .empty
    @State private var biometricFailed = false
    @State private var showCameraScanner = false
    @State private var showContactPicker = false
    @State private var pendingConfirmation: TransactionConfirmation?
    
    // Chain detection properties
    private var isLitecoin: Bool {
        chain.id == "litecoin"
    }
    
    private var isTestnet: Bool {
        chain.id == "bitcoin-testnet"
    }
    
    private var baseURL: String {
        if isLitecoin {
            return "https://api.blockchair.com/litecoin"
        }
        return isTestnet ? "https://mempool.space/testnet/api" : "https://mempool.space/api"
    }
    
    private var ticker: String {
        if isLitecoin { return "LTC" }
        return isTestnet ? "tBTC" : "BTC"
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Amount Input (Large)
            VStack(spacing: 8) {
                Text("Amount to send")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    TextField("0", text: $amountCrypto)
                        .font(.system(size: 48, weight: .medium, design: .rounded))
                        .multilineTextAlignment(.center)
                        .frame(minWidth: 100)
                        .fixedSize(horizontal: true, vertical: false)
                        .onChange(of: amountCrypto) { _ in validateAmount() }
                    Text(ticker)
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                
                if availableBalance > 0 {
                    Text("Available: \(formatSatoshis(availableBalance))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .onTapGesture { sendMax() }
                }

                switch amountValidation {
                case .invalid(let reason):
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                case .valid:
                    Text("Amount looks good")
                        .font(.caption)
                        .foregroundStyle(.green)
                case .empty:
                    EmptyView()
                }
            }
            .padding(.top, 20)

            // Recipient Input
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("To")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    
                    Spacer()
                    
                    // QR Scan buttons
                    HStack(spacing: 8) {
                        Button {
                            showContactPicker = true
                        } label: {
                            Label("Contacts", systemImage: "person.crop.rectangle.stack")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                        
                        Button {
                            showCameraScanner = true
                        } label: {
                            Label("Camera", systemImage: "camera")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.orange)
                        
                        Button {
                            scanQRFromClipboard()
                        } label: {
                            Label("Paste QR", systemImage: "doc.on.clipboard")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.orange)
                        
                        Button {
                            scanQRFromFile()
                        } label: {
                            Label("Scan QR", systemImage: "qrcode.viewfinder")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.orange)
                    }
                }
                .padding(.leading, 4)
                
                HStack {
                    Image(systemName: "person.circle.fill")
                        .foregroundStyle(.secondary)
                    TextField("Bitcoin Address", text: $recipientAddress)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                    
                    if !recipientAddress.isEmpty {
                        Button { recipientAddress = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                switch addressValidation {
                case .invalid(let reason):
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.leading)
                        .padding(.leading, 4)
                case .valid:
                    Text("Address looks good")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.leading, 4)
                case .empty:
                    EmptyView()
                }
            }
            .padding(.horizontal)

            // Fee Selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Network Fee")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.leading, 4)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(BitcoinSendSheet.FeeRate.allCases, id: \.self) { rate in
                            FeeRateCard(
                                rate: rate,
                                isSelected: selectedFeeRate == rate,
                                estimates: feeEstimates,
                                onSelect: { selectedFeeRate = rate }
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal)
            
            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Spacer()

            // Send Button - shows confirmation sheet first
            Button {
                prepareConfirmation()
            } label: {
                HStack {
                    if isLoading {
                        ProgressView().tint(.white)
                    }
                    Text(isLoading ? "Sending..." : "Send Bitcoin")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isValidForm ? Color.orange : Color.gray.opacity(0.3))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(isLoading || !isValidForm)
            .padding()
        }
        .sheet(item: $pendingConfirmation) { confirmation in
            TransactionConfirmationSheet(
                confirmation: confirmation,
                onConfirm: {
                    pendingConfirmation = nil
                    Task { await sendTransaction() }
                },
                onCancel: {
                    pendingConfirmation = nil
                }
            )
        }
        .navigationTitle("Send \(chain.title)")
        .toolbar {
            if !isPushed {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onDismiss()
                    }
                }
            }
        }
        .onAppear {
            Task {
                await loadBalanceAndFees()
            }
            validateRecipientAddress()
            validateAmount()
        }
        .onChange(of: recipientAddress) { _ in
            validateRecipientAddress()
        }
        .onChange(of: estimatedFee) { _ in
            validateAmount()
        }
        .sheet(isPresented: $showCameraScanner) {
            QRCameraScannerView(isPresented: $showCameraScanner) { scannedText in
                applyBitcoinPayload(scannedText)
            }
        }
        .sheet(isPresented: $showContactPicker) {
            ContactPickerSheet(
                chain: "bitcoin",
                contacts: ContactsManager.shared.contacts,
                onSelect: { contact in
                    recipientAddress = contact.address
                    validateRecipientAddress()
                    showContactPicker = false
                },
                onCancel: {
                    showContactPicker = false
                }
            )
        }
    }
    
    private var isValidForm: Bool {
        !amountCrypto.isEmpty &&
        Double(amountCrypto) ?? 0 > 0 &&
        feeEstimates != nil &&
        addressValidation == .valid &&
        amountValidation == .valid
    }

    private var bitcoinNetwork: BitcoinAddressNetwork? {
        switch chain.id {
        case "bitcoin": return .bitcoinMainnet
        case "bitcoin-testnet": return .bitcoinTestnet
        case "litecoin": return .litecoinMainnet
        default: return nil
        }
    }
    
    private func feeRateForSelection(_ estimates: BitcoinFeeEstimates) -> Int {
        switch selectedFeeRate {
        case .fast: return estimates.fastestFee
        case .medium: return estimates.halfHourFee
        case .slow: return estimates.hourFee
        case .economy: return max(estimates.economyFee, estimates.minimumFee)
        }
    }
    
    private func formatSatoshis(_ sats: Int64) -> String {
        let btc = Double(sats) / 100_000_000.0
        return String(format: "%.8f \(ticker)", btc)
    }
    
    private func sendMax() {
        // Reserve estimated fee (assume 1 input, 1 output = ~140 vBytes)
        let estimatedTxFee = Int64(feeEstimates.map { feeRateForSelection($0) * 140 } ?? 5000)
        let maxSendable = max(0, availableBalance - estimatedTxFee)
        amountCrypto = String(format: "%.8f", Double(maxSendable) / 100_000_000.0)
        updateFeeEstimate()
        validateAmount()
    }
    
    private func updateFeeEstimate() {
        guard let estimates = feeEstimates else { return }
        // Rough estimate: 1 input (148 vB) + 2 outputs (2x34 vB) = ~216 vB
        let estimatedSize = 216
        let feeRate = feeRateForSelection(estimates)
        estimatedFee = Int64(estimatedSize * feeRate)
        validateAmount()
    }
    
    private func loadBalanceAndFees() async {
        isLoading = true
        errorMessage = nil
        balanceLoaded = false
        
        do {
            // Get address based on chain type
            let address: String
            if isLitecoin {
                address = keys.litecoin.address
            } else if isTestnet {
                address = keys.bitcoinTestnet.address
            } else {
                address = keys.bitcoin.address
            }
            
            // Fetch UTXOs using MultiProviderAPI with fallbacks
            print("📡 Loading balance for \(address.prefix(10))...")
            let utxos = try await MultiProviderAPI.shared.fetchBitcoinUTXOs(
                address: address,
                isTestnet: isTestnet,
                isLitecoin: isLitecoin
            )
            
            // Convert to our internal format and calculate balance
            // Include unconfirmed UTXOs to allow spending change immediately
            let totalBalance = utxos.reduce(0) { $0 + $1.value }
            availableBalance = totalBalance
            balanceLoaded = true  // Mark as loaded even if balance is 0
            print("✅ Loaded \(utxos.count) UTXOs, balance: \(totalBalance) sats (including unconfirmed)")
            validateAmount()
            
            // Fetch fee estimates
            feeEstimates = try await fetchFeeEstimates()
            updateFeeEstimate()
            
            isLoading = false
        } catch {
            print("❌ Failed to load balance: \(error.localizedDescription)")
            errorMessage = "Failed to load balance. Tap to retry."
            balanceLoaded = false
            isLoading = false
        }
    }
    
    private func fetchUTXOs(for address: String) async throws -> [BitcoinUTXO] {
        // Use MultiProviderAPI with automatic fallbacks
        let utxos = try await MultiProviderAPI.shared.fetchBitcoinUTXOs(
            address: address,
            isTestnet: isTestnet,
            isLitecoin: isLitecoin
        )
        
        // Convert to BitcoinUTXO format
        return utxos.map { utxo in
            BitcoinUTXO(
                txid: utxo.txid,
                vout: utxo.vout,
                value: utxo.value,
                scriptpubkey: utxo.scriptPubKey,
                status: BitcoinUTXO.UTXOStatus(
                    confirmed: utxo.confirmed,
                    blockHeight: utxo.blockHeight,
                    blockHash: nil,
                    blockTime: nil
                )
            )
        }
    }
    
    private func fetchLitecoinUTXOs(for address: String) async throws -> [BitcoinUTXO] {
        // Use Blockchair API for Litecoin
        guard let url = URL(string: "https://api.blockchair.com/litecoin/dashboards/address/\(address)?limit=100") else {
            throw BitcoinSendError.networkError("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BitcoinSendError.networkError("Failed to fetch Litecoin UTXOs")
        }
        
        // Parse Blockchair response format
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let addressData = dataDict[address] as? [String: Any],
              let utxosArray = addressData["utxo"] as? [[String: Any]] else {
            return []
        }
        
        // Convert Blockchair format to our BitcoinUTXO format
        return utxosArray.compactMap { utxo -> BitcoinUTXO? in
            guard let txid = utxo["transaction_hash"] as? String,
                  let vout = utxo["index"] as? Int,
                  let value = utxo["value"] as? Int64 else {
                return nil
            }
            
            let scriptPubKey = utxo["script_hex"] as? String ?? ""
            let blockId = utxo["block_id"] as? Int ?? 0
            
            return BitcoinUTXO(
                txid: txid,
                vout: vout,
                value: value,
                scriptpubkey: scriptPubKey,
                status: BitcoinUTXO.UTXOStatus(confirmed: blockId > 0, blockHeight: blockId > 0 ? blockId : nil, blockHash: nil, blockTime: nil)
            )
        }
    }
    
    private func fetchFeeEstimates() async throws -> BitcoinFeeEstimates {
        if isLitecoin {
            // Fetch Litecoin fee estimates from Blockchair
            return try await fetchLitecoinFeeEstimates()
        }
        
        // Use mempool.space for Bitcoin fees
        guard let url = URL(string: "\(baseURL)/v1/fees/recommended") else {
            throw BitcoinSendError.networkError("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BitcoinSendError.networkError("Failed to fetch fees")
        }
        
        let estimates = try JSONDecoder().decode(BitcoinFeeEstimates.self, from: data)
        return estimates
    }
    
    private func fetchLitecoinFeeEstimates() async throws -> BitcoinFeeEstimates {
        // Litecoin fees are much lower than Bitcoin - use defaults
        // In production, you would fetch from an API like Blockchair
        return BitcoinFeeEstimates(
            fastestFee: 20,    // ~10 min
            halfHourFee: 10,   // ~30 min
            hourFee: 5,        // ~1 hour
            economyFee: 2,     // Economy
            minimumFee: 1      // Minimum
        )
    }
    
    private func sendTransaction() async {
        // Check biometric authentication first if required
        if BiometricAuthHelper.shouldRequireBiometric(settingEnabled: requireBiometric) {
            let result = await BiometricAuthHelper.authenticate(reason: "Authenticate to send \(ticker)")
            switch result {
            case .success:
                break // Continue with transaction
            case .cancelled:
                return // User cancelled, don't show error
            case .failed(let message):
                await MainActor.run {
                    errorMessage = "Authentication failed: \(message)"
                    biometricFailed = true
                }
                return
            case .notAvailable:
                break // Biometric not available, continue anyway
            }
        }
        
        isLoading = true
        errorMessage = nil
        biometricFailed = false
        
        do {
            // Validate address
            let recipient = recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !recipient.isEmpty else {
                throw BitcoinSendError.invalidAddress
            }
            guard addressValidation == .valid else {
                throw BitcoinSendError.invalidAddress
            }
            guard amountValidation == .valid else {
                throw BitcoinSendError.amountTooLow
            }
            
            // Parse amount
            guard let cryptoAmount = Double(amountCrypto) else {
                throw BitcoinSendError.amountTooLow
            }
            let satoshis = Int64(cryptoAmount * 100_000_000)
            
            guard satoshis >= 546 else { // Dust limit
                throw BitcoinSendError.amountTooLow
            }
            
            guard satoshis + estimatedFee <= availableBalance else {
                throw BitcoinSendError.insufficientFunds
            }
            
            // Get keys and fetch UTXOs based on chain type
            let address: String
            let privateWIF: String
            
            if isLitecoin {
                address = keys.litecoin.address
                privateWIF = keys.litecoin.privateWif
            } else if isTestnet {
                address = keys.bitcoinTestnet.address
                privateWIF = keys.bitcoinTestnet.privateWif
            } else {
                address = keys.bitcoin.address
                privateWIF = keys.bitcoin.privateWif
            }
            
            let utxos = try await fetchUTXOs(for: address)
            // Use all UTXOs including unconfirmed ones
            let availableUTXOs = utxos
            
            guard !availableUTXOs.isEmpty else {
                throw BitcoinSendError.insufficientFunds
            }
            
            // Select UTXOs using greedy algorithm (largest first)
            // This minimizes the number of inputs needed
            let sortedUTXOs = availableUTXOs.sorted { $0.value > $1.value }
            var selectedUTXOs: [BitcoinUTXO] = []
            var totalInputValue: Int64 = 0
            let targetAmount = satoshis + estimatedFee
            
            for utxo in sortedUTXOs {
                selectedUTXOs.append(utxo)
                totalInputValue += utxo.value
                if totalInputValue >= targetAmount {
                    break
                }
            }
            
            guard totalInputValue >= targetAmount else {
                throw BitcoinSendError.insufficientFunds
            }
            
            // Calculate change (input - output - fee)
            // Use accurate fee based on actual transaction size
            let inputCount = selectedUTXOs.count
            let outputCount = 2 // recipient + change (may adjust later)
            let estimatedVSize = inputCount * 68 + outputCount * 31 + 10 // P2WPKH sizes
            let feeRate = feeEstimates.map { feeRateForSelection($0) } ?? 10
            // Add +2 sat buffer to ensure we always meet minimum relay fee
            let actualFee = Int64(estimatedVSize * feeRate) + 2
            
            let change = totalInputValue - satoshis - actualFee
            let dustLimit: Int64 = 546
            
            // Convert selected UTXOs to Input format
            _ = try selectedUTXOs.map { utxo -> BitcoinTransactionBuilder.Input in
                guard let scriptData = Data(hex: utxo.scriptpubkey) else {
                    throw BitcoinSendError.networkError("Invalid scriptPubKey format")
                }
                return BitcoinTransactionBuilder.Input(
                    txid: utxo.txid,
                    vout: UInt32(utxo.vout),
                    value: Int64(utxo.value),
                    scriptPubKey: scriptData
                )
            }
            
            // Create outputs - recipient first, then change if above dust
            var outputs: [BitcoinTransactionBuilder.Output] = [
                BitcoinTransactionBuilder.Output(
                    address: recipient,
                    value: satoshis
                )
            ]
            
            // Add change output if above dust limit
            if change > dustLimit {
                outputs.append(BitcoinTransactionBuilder.Output(
                    address: address, // Send change back to ourselves
                    value: change
                ))
            }
            // If change is below dust, it goes to miners as extra fee
            
            // Build and sign transaction via Rust CLI
            // Note: Rust CLI handles UTXO fetching and change calculation internally.
            let signedTx = try BitcoinTransactionBuilder.buildAndSignViaRust(
                recipient: recipient,
                amountSats: UInt64(satoshis),
                feeRate: UInt64(feeRate),
                privateKeyWIF: privateWIF,
                isTestnet: isTestnet
            )
            
            let rawTxHex = signedTx.rawHex
            
            // DEBUG: Log the raw transaction
            print("🔴 BITCOIN BROADCAST DEBUG 🔴")
            print("📝 Raw Transaction Hex (\(rawTxHex.count) chars):")
            print(rawTxHex)
            print("🔴 END RAW TX 🔴")
            
            // Broadcast transaction based on chain type
            var txid: String
            
            if isLitecoin {
                // Use TransactionBroadcaster for Litecoin
                txid = try await TransactionBroadcaster.shared.broadcastLitecoin(rawTxHex: rawTxHex)
            } else {
                // Use mempool.space for Bitcoin
                let broadcastURL = isTestnet ? "https://mempool.space/testnet/api" : "https://mempool.space/api"
                let fullURL = "\(broadcastURL)/tx"
                print("📡 Broadcasting to: \(fullURL)")
                
                guard let url = URL(string: fullURL) else {
                    throw BitcoinSendError.networkError("Invalid broadcast URL")
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.httpBody = rawTxHex.data(using: String.Encoding.utf8)
                request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
                
                print("📤 Sending POST request...")
                let (data, response) = try await URLSession.shared.data(for: request)
                print("📥 Received response")
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ Invalid response type")
                    throw BitcoinSendError.networkError("Invalid response")
                }
                
                print("📊 HTTP Status Code: \(httpResponse.statusCode)")
                let responseBody = String(data: data, encoding: .utf8) ?? "Unknown"
                print("📄 Response Body: \(responseBody)")
                
                guard httpResponse.statusCode == 200 else {
                    print("❌ Broadcast failed with status \(httpResponse.statusCode)")
                    throw BitcoinSendError.broadcastFailed(responseBody)
                }
                
                txid = responseBody
                print("✅ Broadcast successful! TXID: \(txid)")
            }
            
            // Success!
            await MainActor.run {
                isLoading = false
                let result = TransactionBroadcastResult(
                    txid: txid,
                    chainId: chain.id,
                    chainName: chain.title,
                    amount: "\(cryptoAmount) \(ticker)",
                    recipient: recipient
                )
                onSuccess(result)
                dismiss()
            }
            
        } catch let error as BitcoinSendError {
            await MainActor.run {
                errorMessage = error.errorDescription
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Error: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    private func prepareConfirmation() {
        // Get the sender address
        let fromAddress: String
        if isLitecoin {
            fromAddress = keys.litecoin.address
        } else if isTestnet {
            fromAddress = keys.bitcoinTestnet.address
        } else {
            fromAddress = keys.bitcoin.address
        }
        
        // Parse amounts
        guard let cryptoAmount = Double(amountCrypto) else { return }
        let feeSats = estimatedFee
        let feeInCrypto = Double(feeSats) / 100_000_000.0
        let totalCrypto = cryptoAmount + feeInCrypto
        
        // Format for display
        let formattedAmount = String(format: "%.8f %@", cryptoAmount, ticker)
        let formattedFee = String(format: "%.8f %@ (%d sats)", feeInCrypto, ticker, feeSats)
        let formattedTotal = String(format: "%.8f %@", totalCrypto, ticker)
        
        // Determine chain type
        let chainType: TransactionConfirmation.ChainType = isLitecoin ? .litecoin : .bitcoin
        
        // Determine network name
        let networkName: String
        if isLitecoin {
            networkName = "Litecoin Mainnet"
        } else if isTestnet {
            networkName = "Bitcoin Testnet"
        } else {
            networkName = "Bitcoin Mainnet"
        }
        
        // Get estimated confirmation time based on fee rate
        let estimatedTime: String
        switch selectedFeeRate {
        case .fast:
            estimatedTime = "~10 minutes"
        case .medium:
            estimatedTime = "~30 minutes"
        case .slow:
            estimatedTime = "~1 hour"
        case .economy:
            estimatedTime = "~2+ hours"
        }
        
        // Create confirmation object
        pendingConfirmation = TransactionConfirmation(
            chainType: chainType,
            fromAddress: fromAddress,
            toAddress: recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: formattedAmount,
            amountFiat: nil, // Could add fiat conversion here
            fee: formattedFee,
            feeFiat: nil,
            total: formattedTotal,
            totalFiat: nil,
            memo: nil,
            contractAddress: nil,
            tokenSymbol: nil,
            nonce: nil,
            gasLimit: nil,
            gasPrice: nil,
            networkName: networkName,
            isTestnet: isTestnet,
            estimatedTime: estimatedTime
        )
    }

    private func validateRecipientAddress() {
        guard let network = bitcoinNetwork else {
            addressValidation = recipientAddress.isEmpty ? .empty : .valid
            return
        }
        addressValidation = AddressValidator.validateBitcoinAddress(recipientAddress, network: network)
    }

    private func validateAmount() {
        amountValidation = AmountValidator.validateBitcoin(
            amountString: amountCrypto,
            availableSats: availableBalance,
            estimatedFeeSats: estimatedFee,
            balanceLoaded: balanceLoaded
        )
    }

    private func scanQRFromFile() {
        guard let payload = QRCodeScanner.scanText() else { return }
        applyBitcoinPayload(payload)
    }
    
    private func scanQRFromClipboard() {
        let result = QRCodeScanner.scanFromClipboard()
        switch result {
        case .success(let payload):
            applyBitcoinPayload(payload)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func scanBitcoinQRCode() {
        guard let payload = QRCodeScanner.scanText() else { return }
        applyBitcoinPayload(payload)
    }

    private func applyBitcoinPayload(_ raw: String) {
        let uri = CryptoURI(raw)
        if let scheme = uri.scheme, ["bitcoin", "litecoin", "btc", "ltc"].contains(scheme) {
            if !uri.target.isEmpty {
                recipientAddress = uri.target
            }
            if let amountValue = uri.queryValue("amount"), !amountValue.isEmpty {
                amountCrypto = amountValue
            }
        } else {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                recipientAddress = trimmed
            }
        }
        validateRecipientAddress()
        validateAmount()
    }
}

private struct FeeRateCard: View {
    let rate: BitcoinSendSheet.FeeRate
    let isSelected: Bool
    let estimates: BitcoinFeeEstimates?
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                Text(rate.rawValue.components(separatedBy: " (").first ?? "")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                if let estimates {
                    let fee = feeRateForSelection(estimates, rate: rate)
                    Text("\(fee) sat/vB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(minWidth: 100, alignment: .leading)
            .background(isSelected ? Color.orange.opacity(0.15) : Color.gray.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.orange : Color.clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
    
    private func feeRateForSelection(_ estimates: BitcoinFeeEstimates, rate: BitcoinSendSheet.FeeRate) -> Int {
        switch rate {
        case .fast: return estimates.fastestFee
        case .medium: return estimates.halfHourFee
        case .slow: return estimates.hourFee
        case .economy: return max(estimates.economyFee, estimates.minimumFee)
        }
    }
}

private struct GasSpeedCard: View {
    let speed: EthGasSpeed
    let isSelected: Bool
    let estimates: EthGasEstimates?
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: speed.icon)
                        .font(.caption)
                        .foregroundStyle(isSelected ? .orange : .secondary)
                    Text(speed.rawValue)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Text(speed.estimatedTime)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                if let estimates {
                    let price = estimates.gasPriceFor(speed)
                    Text(String(format: "%.1f Gwei", price))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(minWidth: 90, alignment: .leading)
            .background(isSelected ? Color.orange.opacity(0.15) : Color.gray.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.orange : Color.clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ethereum Send Sheet

private struct EthereumSendSheet: View {
    let chain: ChainInfo
    let keys: AllKeys
    let requireBiometric: Bool
    let onDismiss: () -> Void
    let onSuccess: (TransactionBroadcastResult) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var recipientAddress = ""
    @State private var amountInput = ""
    @State private var selectedToken: TokenType = .eth
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var gasPrice: String = ""
    @State private var nonce: Int = 0
    @State private var balance: String = "0"
    @State private var estimatedGasFee: String = ""
    @State private var showConfirmation = false
    @State private var amountValidation: AmountValidationResult = .empty
    @State private var addressValidation: AddressValidationResult = .empty
    @State private var resolvedENSName: String? = nil
    @State private var isResolvingENS = false
    @State private var ensResolutionTask: Task<Void, Never>?
    @State private var biometricFailed = false
    @State private var selectedGasSpeed: EthGasSpeed = .standard
    @State private var gasEstimates: EthGasEstimates?
    @State private var showCameraScanner = false
    @State private var showContactPicker = false
    @State private var pendingConfirmation: TransactionConfirmation?
    
    private var isTestnet: Bool {
        chain.id == "ethereum-sepolia"
    }
    
    private var rpcURL: String {
        isTestnet ? APIConfig.alchemySepoliaURL : APIConfig.alchemyMainnetURL
    }
    
    private var chainId: Int {
        isTestnet ? 11155111 : 1
    }
    
    private var availableTokens: [TokenType] {
        if isTestnet {
            return [.eth]
        }
        return TokenType.allCases
    }
    
    private func tokenDisplayName(_ token: TokenType) -> String {
        if isTestnet && token == .eth {
            return "Sepolia ETH"
        }
        return token.rawValue
    }
    
    enum TokenType: String, CaseIterable {
        case eth = "ETH"
        case usdt = "USDT"
        case usdc = "USDC"
        case dai = "DAI"
        
        var contractAddress: String? {
            switch self {
            case .eth: return nil
            case .usdt: return "0xdAC17F958D2ee523a2206206994597C13D831ec7"
            case .usdc: return "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
            case .dai: return "0x6B175474E89094C44Da98b954EedeAC495271d0F"
            }
        }
        
        var decimals: Int {
            switch self {
            case .eth: return 18
            case .usdt: return 6
            case .usdc: return 6
            case .dai: return 18
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Token Selector & Amount
                VStack(spacing: 16) {
                    Picker("Token", selection: $selectedToken) {
                        ForEach(availableTokens, id: \.self) { token in
                            Text(tokenDisplayName(token)).tag(token)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 40)
                    .onChange(of: selectedToken) { _ in
                        Task { await loadBalanceAndGas() }
                        validateAmount()
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        TextField("0", text: $amountInput)
                            .font(.system(size: 48, weight: .medium, design: .rounded))
                            .multilineTextAlignment(.center)
                            .frame(minWidth: 100)
                            .fixedSize(horizontal: true, vertical: false)
                            .onChange(of: amountInput) { _ in
                                updateGasEstimate()
                                validateAmount()
                            }
                        Text(tokenDisplayName(selectedToken))
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("Available: \(balance)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .onTapGesture { sendMax() }

                    switch amountValidation {
                    case .invalid(let reason):
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    case .valid:
                        Text("Amount looks good")
                            .font(.caption)
                            .foregroundStyle(.green)
                    case .empty:
                        EmptyView()
                    }
                }
                .padding(.top, 20)

                // Recipient Input
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("To")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        
                        Spacer()
                        
                        // QR Scan buttons
                        HStack(spacing: 8) {
                            Button {
                                showContactPicker = true
                            } label: {
                                Label("Contacts", systemImage: "person.crop.rectangle.stack")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                            
                            Button {
                                showCameraScanner = true
                            } label: {
                                Label("Camera", systemImage: "camera")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.orange)
                            
                            Button {
                                scanQRFromClipboard()
                            } label: {
                                Label("Paste QR", systemImage: "doc.on.clipboard")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.orange)
                            
                            Button {
                                scanQRFromFile()
                            } label: {
                                Label("Scan QR", systemImage: "qrcode.viewfinder")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.orange)
                        }
                    }
                    .padding(.leading, 4)
                    
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .foregroundStyle(.secondary)
                        TextField("0x... or name.eth", text: $recipientAddress)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                        
                        if isResolvingENS {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else if !recipientAddress.isEmpty {
                            Button { 
                                recipientAddress = "" 
                                resolvedENSName = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // ENS Resolution Status
                    if let ensName = resolvedENSName {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.blue)
                            Text("Resolved from \(recipientAddress)")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                        .padding(.leading, 4)
                        
                        Text(ensName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                    }

                    switch addressValidation {
                    case .invalid(let reason):
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.leading, 4)
                            .multilineTextAlignment(.leading)
                    case .valid:
                        if resolvedENSName == nil {
                            Text("Address looks good")
                                .font(.caption)
                                .foregroundStyle(.green)
                                .padding(.leading, 4)
                        }
                    case .empty:
                        EmptyView()
                    }
                }
                .padding(.horizontal)

                // Gas Speed Selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Network Fee")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.leading, 4)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(EthGasSpeed.allCases, id: \.self) { speed in
                                GasSpeedCard(
                                    speed: speed,
                                    isSelected: selectedGasSpeed == speed,
                                    estimates: gasEstimates,
                                    onSelect: {
                                        selectedGasSpeed = speed
                                        updateGasPriceForSpeed()
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    
                    // Gas Price Details
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Gas Price")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(gasPrice.isEmpty ? "—" : "\(gasPrice) Gwei")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("Estimated Cost")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(estimatedGasFee.isEmpty ? "—" : "\(estimatedGasFee) ETH")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(12)
                    .background(Color.gray.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)

                if let error = errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }

                Spacer()

                // Send Button - shows confirmation sheet first
                Button {
                    prepareEthConfirmation()
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView().tint(.white)
                        }
                        Text(isLoading ? "Sending..." : "Send \(selectedToken.rawValue)")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isValidForm ? Color.orange : Color.gray.opacity(0.3))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(!isValidForm || isLoading)
                .padding()
            }
            .sheet(item: $pendingConfirmation) { confirmation in
                TransactionConfirmationSheet(
                    confirmation: confirmation,
                    onConfirm: {
                        pendingConfirmation = nil
                        Task { await sendTransaction() }
                    },
                    onCancel: {
                        pendingConfirmation = nil
                    }
                )
            }
            .navigationTitle("Send Ethereum")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss(); onDismiss() }
                }
            }
            .task {
                await loadBalanceAndGas()
            }
            .onAppear { validateRecipientAddress() }
            .onChange(of: recipientAddress) { _ in 
                resolvedENSName = nil
                ensResolutionTask?.cancel()
                validateRecipientAddressWithENS()
            }
        }
        .sheet(isPresented: $showCameraScanner) {
            QRCameraScannerView(isPresented: $showCameraScanner) { scannedText in
                applyEthereumPayload(scannedText)
            }
        }
        .sheet(isPresented: $showContactPicker) {
            ContactPickerSheet(
                chain: "ethereum",
                contacts: ContactsManager.shared.contacts,
                onSelect: { contact in
                    recipientAddress = contact.address
                    resolvedENSName = nil
                    validateRecipientAddress()
                    showContactPicker = false
                },
                onCancel: {
                    showContactPicker = false
                }
            )
        }
        .frame(width: 480, height: 650)
    }
    
    private var isValidForm: Bool {
        !amountInput.isEmpty &&
        (Double(amountInput) ?? 0) > 0 &&
        !gasPrice.isEmpty &&
        addressValidation == .valid &&
        amountValidation == .valid &&
        !isResolvingENS
    }
    
    private func sendMax() {
        // For ETH, subtract gas fee. For tokens, use full balance
        let balanceValue = Double(balance.replacingOccurrences(of: " \(selectedToken.rawValue)", with: "")) ?? 0
        
        if selectedToken == .eth {
            let gasFeeETH = Double(estimatedGasFee.replacingOccurrences(of: " ETH", with: "")) ?? 0
            let maxSendable = max(0, balanceValue - gasFeeETH)
            amountInput = String(format: "%.8f", maxSendable)
        } else {
            amountInput = String(format: "%.8f", balanceValue)
        }
        validateAmount()
    }
    
    private func updateGasEstimate() {
        guard !gasPrice.isEmpty else { return }
        let gasPriceGwei = Double(gasPrice) ?? 0
        let gasLimit = selectedToken == .eth ? 21000.0 : 65000.0
        let gasFeeETH = (gasPriceGwei * gasLimit) / 1_000_000_000.0
        estimatedGasFee = String(format: "%.6f", gasFeeETH)
        validateAmount()
    }

    private func validateAmount() {
        let locale = Locale(identifier: "en_US_POSIX")
        let available = decimalValue(from: balance, locale: locale)
        let minUnit = Decimal(string: "0.000001", locale: locale) ?? 0.000001
        if selectedToken == .eth {
            let reserve = decimalValue(from: estimatedGasFee, locale: locale)
            amountValidation = AmountValidator.validateDecimalAsset(
                amountString: amountInput,
                assetName: selectedToken.rawValue,
                available: available,
                precision: selectedToken.decimals,
                minimum: minUnit,
                reserved: reserve
            )
        } else {
            amountValidation = AmountValidator.validateDecimalAsset(
                amountString: amountInput,
                assetName: selectedToken.rawValue,
                available: available,
                precision: selectedToken.decimals,
                minimum: minUnit
            )
        }
    }

    private func decimalValue(from display: String, locale: Locale) -> Decimal {
        let numericPortion = display.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? display
        return Decimal(string: numericPortion, locale: locale) ?? 0
    }

    private func scanEthereumQRCode() {
        guard let payload = QRCodeScanner.scanText() else { return }
        applyEthereumPayload(payload)
    }

    private func applyEthereumPayload(_ raw: String) {
        let uri = CryptoURI(raw)
        if let scheme = uri.scheme, scheme == "ethereum" {
            if !uri.target.isEmpty {
                recipientAddress = normalizeEthereumTarget(uri.target)
            }
            if let value = uri.queryValue("value"), let decimalValue = Decimal(string: value) {
                amountInput = formatEthereumAmount(decimalValue)
            } else if let amount = uri.queryValue("amount"), !amount.isEmpty {
                amountInput = amount
            }
        } else {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                recipientAddress = trimmed
            }
        }
        validateRecipientAddress()
        validateAmount()
    }

    private func normalizeEthereumTarget(_ target: String) -> String {
        var adjusted = target
        if adjusted.hasPrefix("pay-") {
            adjusted.removeFirst(4)
        }
        if let atIndex = adjusted.firstIndex(of: "@") {
            adjusted = String(adjusted[..<atIndex])
        }
        return adjusted
    }

    private func formatEthereumAmount(_ weiValue: Decimal) -> String {
        let divisor = pow(10.0, Double(selectedToken.decimals))
        guard divisor > 0 else { return amountInput }
        let doubleValue = (weiValue as NSDecimalNumber).doubleValue / divisor
        return String(format: "%.8f", doubleValue)
    }
    
    private func loadBalanceAndGas() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let address = isTestnet ? keys.ethereumSepolia.address : keys.ethereum.address
            
            // Fetch nonce
            nonce = try await fetchNonce(address: address)
            
            // Fetch gas estimates (EIP-1559 style with fallback)
            let estimates = try await fetchGasEstimates()
            await MainActor.run {
                gasEstimates = estimates
                updateGasPriceForSpeed()
            }
            
            // Fetch balance
            let bal = try await fetchBalance(address: address)
            await MainActor.run {
                balance = bal
                isLoading = false
                validateAmount()
            }
            
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    private func updateGasPriceForSpeed() {
        guard let estimates = gasEstimates else { return }
        let price = estimates.gasPriceFor(selectedGasSpeed)
        gasPrice = String(format: "%.2f", price)
        updateGasEstimate()
    }
    
    private func fetchGasEstimates() async throws -> EthGasEstimates {
        guard let url = URL(string: rpcURL) else {
            throw EthereumError.invalidAddress
        }
        
        // Try to fetch base fee from latest block
        let blockPayload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getBlockByNumber",
            "params": ["latest", false],
            "id": 1
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: blockPayload)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        var baseFeeGwei: Double = 20.0 // Default fallback
        
        if let result = json?["result"] as? [String: Any],
           let baseFeeHex = result["baseFeePerGas"] as? String {
            let cleaned = baseFeeHex.hasPrefix("0x") ? String(baseFeeHex.dropFirst(2)) : baseFeeHex
            if let baseFeeWei = UInt64(cleaned, radix: 16) {
                baseFeeGwei = Double(baseFeeWei) / 1_000_000_000.0
            }
        }
        
        // Also fetch legacy gas price for comparison
        let legacyPrice = try await fetchGasPrice()
        let legacyGwei = Double(legacyPrice) / 1_000_000_000.0
        
        // If baseFee seems off, use legacy price
        if baseFeeGwei < 1.0 {
            baseFeeGwei = legacyGwei * 0.7 // Estimate base fee as ~70% of legacy price
        }
        
        // Priority fee tiers (typical mainnet values)
        return EthGasEstimates(
            baseFee: baseFeeGwei,
            slowPriorityFee: 0.5,
            standardPriorityFee: 1.5,
            fastPriorityFee: 3.0,
            instantPriorityFee: 5.0
        )
    }
    
    private func fetchNonce(address: String) async throws -> Int {
        guard let url = URL(string: rpcURL) else {
            throw EthereumError.invalidAddress
        }
        
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getTransactionCount",
            "params": [address, "latest"],
            "id": 1
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let resultHex = json?["result"] as? String else {
            throw EthereumError.gasEstimationFailed
        }
        
        let cleaned = resultHex.hasPrefix("0x") ? String(resultHex.dropFirst(2)) : resultHex
        return Int(cleaned, radix: 16) ?? 0
    }
    
    private func fetchGasPrice() async throws -> UInt64 {
        guard let url = URL(string: rpcURL) else {
            throw EthereumError.invalidAddress
        }
        
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_gasPrice",
            "params": [],
            "id": 1
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let resultHex = json?["result"] as? String else {
            throw EthereumError.gasEstimationFailed
        }
        
        let cleaned = resultHex.hasPrefix("0x") ? String(resultHex.dropFirst(2)) : resultHex
        return UInt64(cleaned, radix: 16) ?? 20_000_000_000 // 20 Gwei default
    }
    
    private func fetchBalance(address: String) async throws -> String {
        if selectedToken == .eth {
            // Fetch ETH balance via RPC
            guard let url = URL(string: rpcURL) else {
                throw EthereumError.invalidAddress
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
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            
            let ethValue = try BalanceResponseParser.parseAlchemyETHBalance(from: data)
            
            return String(format: "%.6f ETH", NSDecimalNumber(decimal: ethValue).doubleValue)
        } else {
            // TODO: Fetch ERC-20 token balance
            return "0 \(selectedToken.rawValue)"
        }
    }

    private func validateRecipientAddress() {
        addressValidation = AddressValidator.validateEthereumAddress(recipientAddress)
    }
    
    private func scanQRFromFile() {
        guard let payload = QRCodeScanner.scanText() else { return }
        applyEthereumPayload(payload)
    }
    
    private func scanQRFromClipboard() {
        let result = QRCodeScanner.scanFromClipboard()
        switch result {
        case .success(let payload):
            applyEthereumPayload(payload)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func prepareEthConfirmation() {
        // Parse amount
        guard let amount = Double(amountInput) else { return }
        
        // Get addresses
        let fromAddress = keys.ethereum.address
        let toAddress = effectiveRecipientAddress
        
        // Format amounts
        let formattedAmount = String(format: "%.8f %@", amount, selectedToken.rawValue)
        let formattedFee = estimatedGasFee.isEmpty ? "Calculating..." : "\(estimatedGasFee) ETH"
        let totalAmount = selectedToken == .eth ? amount + (Double(estimatedGasFee) ?? 0) : amount
        let formattedTotal = selectedToken == .eth 
            ? String(format: "%.8f ETH", totalAmount)
            : "\(formattedAmount) + \(formattedFee)"
        
        // Network info
        let networkName = isTestnet ? "Ethereum Sepolia (Testnet)" : "Ethereum Mainnet"
        
        // Estimated time based on gas speed
        let estimatedTime: String
        switch selectedGasSpeed {
        case .instant:
            estimatedTime = "~10 seconds"
        case .fast:
            estimatedTime = "~15 seconds"
        case .standard:
            estimatedTime = "~30 seconds"
        case .slow:
            estimatedTime = "~2 minutes"
        }
        
        // Create confirmation
        pendingConfirmation = TransactionConfirmation(
            chainType: .ethereum,
            fromAddress: fromAddress,
            toAddress: toAddress,
            amount: formattedAmount,
            amountFiat: nil,
            fee: formattedFee,
            feeFiat: nil,
            total: formattedTotal,
            totalFiat: nil,
            memo: nil,
            contractAddress: selectedToken.contractAddress,
            tokenSymbol: selectedToken == .eth ? nil : selectedToken.rawValue,
            nonce: nonce,
            gasLimit: 21000,
            gasPrice: gasPrice.isEmpty ? nil : "\(gasPrice) Gwei",
            networkName: networkName,
            isTestnet: isTestnet,
            estimatedTime: estimatedTime
        )
    }

    private func validateRecipientAddressWithENS() {
        let input = recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if it looks like an ENS name
        if NameResolver.isResolvableName(input) && input.lowercased().hasSuffix(".eth") {
            // It's an ENS name - resolve it
            isResolvingENS = true
            addressValidation = .empty
            
            ensResolutionTask = Task {
                do {
                    let resolved = try await NameResolver.shared.resolveENS(input)
                    await MainActor.run {
                        resolvedENSName = resolved
                        isResolvingENS = false
                        // Validate the resolved address
                        addressValidation = AddressValidator.validateEthereumAddress(resolved)
                    }
                } catch {
                    await MainActor.run {
                        resolvedENSName = nil
                        isResolvingENS = false
                        addressValidation = .invalid(error.localizedDescription)
                    }
                }
            }
        } else {
            // Regular address validation
            resolvedENSName = nil
            validateRecipientAddress()
        }
    }

    /// Returns the actual address to send to (resolved ENS or direct input)
    private var effectiveRecipientAddress: String {
        resolvedENSName ?? recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func sendTransaction() async {
        // Check biometric authentication first if required
        if BiometricAuthHelper.shouldRequireBiometric(settingEnabled: requireBiometric) {
            let result = await BiometricAuthHelper.authenticate(reason: "Authenticate to send \(selectedToken.rawValue)")
            switch result {
            case .success:
                break // Continue with transaction
            case .cancelled:
                return // User cancelled, don't show error
            case .failed(let message):
                await MainActor.run {
                    errorMessage = "Authentication failed: \(message)"
                    biometricFailed = true
                }
                return
            case .notAvailable:
                break // Biometric not available, continue anyway
            }
        }
        
        isLoading = true
        errorMessage = nil
        biometricFailed = false
        
        do {
            let privateKey = isTestnet ? keys.ethereumSepolia.privateHex : keys.ethereum.privateHex
            guard addressValidation == .valid else {
                throw EthereumError.invalidAddress
            }
            
            // Use resolved ENS address if available
            let toAddress = effectiveRecipientAddress
            
            // Convert amount to Wei
            let amountValue = Double(amountInput) ?? 0
            let multiplier = pow(10.0, Double(selectedToken.decimals))
            let smallestUnit = UInt64(amountValue * multiplier)
            
            // Convert gas price to Wei
            let gasPriceGwei = Double(gasPrice) ?? 0
            let gasPriceWei = UInt64(gasPriceGwei * 1_000_000_000)
            
            let signedTx: String
            
            if selectedToken == .eth {
                // Send ETH
                signedTx = try EthereumTransaction.buildAndSign(
                    to: toAddress,
                    value: String(smallestUnit),
                    gasLimit: 21000,
                    gasPrice: String(gasPriceWei),
                    nonce: nonce,
                    chainId: chainId,
                    privateKeyHex: privateKey
                )
            } else {
                // Send ERC-20 token
                guard let contract = selectedToken.contractAddress else {
                    throw EthereumError.invalidAddress
                }
                
                signedTx = try EthereumTransaction.buildAndSignERC20Transfer(
                    tokenContract: contract,
                    to: toAddress,
                    amount: String(smallestUnit),
                    gasLimit: 65000,
                    gasPrice: String(gasPriceWei),
                    nonce: nonce,
                    chainId: chainId,
                    privateKeyHex: privateKey
                )
            }
            
            // Broadcast transaction
            let txid = try await broadcastTransaction(signedTx)
            
            await MainActor.run {
                isLoading = false
                let result = TransactionBroadcastResult(
                    txid: txid,
                    chainId: chain.id,
                    chainName: chain.title,
                    amount: "\(amountInput) \(selectedToken.rawValue)",
                    recipient: recipientAddress
                )
                onSuccess(result)
                dismiss()
            }
            
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    private func broadcastTransaction(_ rawTx: String) async throws -> String {
        guard let url = URL(string: rpcURL) else {
            throw EthereumError.invalidAddress
        }
        
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_sendRawTransaction",
            "params": [rawTx],
            "id": 1
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw EthereumError.broadcastFailed("Network error")
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        if let error = json?["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw EthereumError.broadcastFailed(message)
        }
        
        guard let txid = json?["result"] as? String else {
            throw EthereumError.broadcastFailed("No transaction ID returned")
        }
        
        return txid
    }
}

// MARK: - BNB Send Sheet

private struct BnbSendSheet: View {
    let chain: ChainInfo
    let keys: AllKeys
    let requireBiometric: Bool
    let onDismiss: () -> Void
    let onSuccess: (TransactionBroadcastResult) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var recipientAddress = ""
    @State private var amountInput = ""
    @State private var gasPriceGwei = ""
    @State private var balanceDisplay = "0 BNB"
    @State private var estimatedFee = "—"
    @State private var nonce: Int = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var amountValidation: AmountValidationResult = .empty
    @State private var addressValidation: AddressValidationResult = .empty
    @State private var biometricFailed = false
    @State private var showCameraScanner = false
    @State private var showContactPicker = false
    @State private var pendingConfirmation: TransactionConfirmation?
    
    private let rpcURL = "https://bsc-dataseed.binance.org/"
    private let chainId = 56
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Recipient") {
                    TextField("0x...", text: $recipientAddress)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()

                    switch addressValidation {
                    case .invalid(let reason):
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.red)
                    case .valid:
                        Text("Address looks good")
                            .font(.caption)
                            .foregroundStyle(.green)
                    case .empty:
                        EmptyView()
                    }

                    HStack(spacing: 8) {
                        Button { showContactPicker = true } label: {
                            Label("Contacts", systemImage: "person.crop.rectangle.stack")
                        }
                        .buttonStyle(.bordered)
                        
                        Button { showCameraScanner = true } label: {
                            Label("Camera", systemImage: "camera")
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: scanBnbQRCode) {
                            Label("Scan QR", systemImage: "qrcode.viewfinder")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                Section("Amount") {
                    HStack {
                        TextField("0.0", text: $amountInput)
                            .onChange(of: amountInput) { _ in validateAmount() }
                        Text("BNB")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Available")
                        Spacer()
                        Text(balanceDisplay)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    
                    Button("Send Max") {
                        sendMax()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    switch amountValidation {
                    case .invalid(let reason):
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.red)
                    case .valid:
                        Text("Amount looks good")
                            .font(.caption)
                            .foregroundStyle(.green)
                    case .empty:
                        EmptyView()
                    }
                }
                
                Section("Network Fee") {
                    HStack {
                        Text("Gas Price")
                        Spacer()
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(gasPriceGwei.isEmpty ? "—" : gasPriceGwei + " Gwei")
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    HStack {
                        Text("Estimated Fee")
                        Spacer()
                        Text(estimatedFee)
                            .font(.system(.body, design: .monospaced))
                    }
                }
                
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                
                Section {
                    Button {
                        prepareBnbConfirmation()
                    } label: {
                        HStack {
                            if isLoading { ProgressView().controlSize(.small).tint(.white) }
                            Text(isLoading ? "Sending..." : "Send BNB")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValidForm || isLoading)
                }
            }
            .sheet(item: $pendingConfirmation) { confirmation in
                TransactionConfirmationSheet(
                    confirmation: confirmation,
                    onConfirm: {
                        pendingConfirmation = nil
                        Task { await sendTransaction() }
                    },
                    onCancel: {
                        pendingConfirmation = nil
                    }
                )
            }
            .navigationTitle("Send BNB")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onDismiss()
                    }
                }
            }
            .task { await loadWalletState() }
            .onAppear {
                validateRecipientAddress()
                validateAmount()
            }
            .onChange(of: recipientAddress) { _ in validateRecipientAddress() }
        }
        .sheet(isPresented: $showCameraScanner) {
            QRCameraScannerView(isPresented: $showCameraScanner) { scannedText in
                applyBnbPayload(scannedText)
            }
        }
        .sheet(isPresented: $showContactPicker) {
            ContactPickerSheet(
                chain: "bnb",
                contacts: ContactsManager.shared.contacts,
                onSelect: { contact in
                    recipientAddress = contact.address
                    validateRecipientAddress()
                    showContactPicker = false
                },
                onCancel: {
                    showContactPicker = false
                }
            )
        }
        .frame(width: 500, height: 600)
    }
    
    private var isValidForm: Bool {
        addressValidation == .valid &&
        (Double(amountInput) ?? 0) > 0 && !gasPriceGwei.isEmpty &&
        amountValidation == .valid
    }
    
    private func sendMax() {
        let parts = balanceDisplay.replacingOccurrences(of: " BNB", with: "")
        let amount = Double(parts) ?? 0
        let fee = Double(estimatedFee.replacingOccurrences(of: " BNB", with: "")) ?? 0
        let maxValue = max(0, amount - fee)
        amountInput = String(format: "%.6f", maxValue)
        validateAmount()
    }

    private func validateRecipientAddress() {
        addressValidation = AddressValidator.validateBnbAddress(recipientAddress)
    }
    
    private func loadWalletState() async {
        isLoading = true
        errorMessage = nil
        do {
            let address = keys.bnb.address
            nonce = try await fetchNonce(address: address)
            let gasPriceWei = try await fetchGasPrice()
            let gwei = Double(gasPriceWei) / 1_000_000_000.0
            gasPriceGwei = String(format: "%.2f", gwei)
            updateFeeEstimate()
            balanceDisplay = try await fetchBalance(address: address)
            isLoading = false
            validateAmount()
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    private func updateFeeEstimate() {
        let gasPrice = Double(gasPriceGwei) ?? 0
        let fee = (gasPrice * 21000.0) / 1_000_000_000.0
        estimatedFee = String(format: "%.6f BNB", fee)
        validateAmount()
    }

    private func validateAmount() {
        let locale = Locale(identifier: "en_US_POSIX")
        let available = decimalValue(from: balanceDisplay, locale: locale)
        let reserve = decimalValue(from: estimatedFee, locale: locale)
        let minUnit = Decimal(string: "0.000001", locale: locale) ?? 0.000001
        amountValidation = AmountValidator.validateDecimalAsset(
            amountString: amountInput,
            assetName: "BNB",
            available: available,
            precision: 18,
            minimum: minUnit,
            reserved: reserve
        )
    }

    private func decimalValue(from display: String, locale: Locale) -> Decimal {
        let numericPortion = display.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? display
        return Decimal(string: numericPortion, locale: locale) ?? 0
    }

    private func scanBnbQRCode() {
        guard let payload = QRCodeScanner.scanText() else { return }
        applyBnbPayload(payload)
    }
    
    private func scanBnbQRFromClipboard() {
        let result = QRCodeScanner.scanFromClipboard()
        switch result {
        case .success(let payload):
            applyBnbPayload(payload)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func applyBnbPayload(_ raw: String) {
        let uri = CryptoURI(raw)
        if let scheme = uri.scheme, ["ethereum", "bnb"].contains(scheme) {
            if !uri.target.isEmpty {
                recipientAddress = normalizeEip681Target(uri.target)
            }
            if let value = uri.queryValue("value"), let decimalValue = Decimal(string: value) {
                amountInput = formatBnbAmount(decimalValue)
            } else if let amount = uri.queryValue("amount"), !amount.isEmpty {
                amountInput = amount
            }
        } else {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                recipientAddress = trimmed
            }
        }
        validateRecipientAddress()
        validateAmount()
    }

    private func normalizeEip681Target(_ target: String) -> String {
        var adjusted = target
        if adjusted.hasPrefix("pay-") {
            adjusted.removeFirst(4)
        }
        if let atIndex = adjusted.firstIndex(of: "@") {
            adjusted = String(adjusted[..<atIndex])
        }
        return adjusted
    }

    private func formatBnbAmount(_ weiValue: Decimal) -> String {
        let divisor = pow(10.0, 18.0)
        let doubleValue = (weiValue as NSDecimalNumber).doubleValue / divisor
        return String(format: "%.8f", doubleValue)
    }
    
    private func fetchNonce(address: String) async throws -> Int {
        guard let url = URL(string: rpcURL) else { throw EthereumError.invalidAddress }
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getTransactionCount",
            "params": [address, "latest"],
            "id": 1
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let resultHex = json?["result"] as? String else {
            throw EthereumError.gasEstimationFailed
        }
        let cleaned = resultHex.hasPrefix("0x") ? String(resultHex.dropFirst(2)) : resultHex
        return Int(cleaned, radix: 16) ?? 0
    }
    
    private func fetchGasPrice() async throws -> UInt64 {
        guard let url = URL(string: rpcURL) else { throw EthereumError.invalidAddress }
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_gasPrice",
            "params": [],
            "id": 1
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let resultHex = json?["result"] as? String else {
            throw EthereumError.gasEstimationFailed
        }
        let cleaned = resultHex.hasPrefix("0x") ? String(resultHex.dropFirst(2)) : resultHex
        return UInt64(cleaned, radix: 16) ?? 5_000_000_000
    }
    
    private func fetchBalance(address: String) async throws -> String {
        guard let url = URL(string: rpcURL) else { throw EthereumError.invalidAddress }
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getBalance",
            "params": [address, "latest"],
            "id": 1
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let resultHex = json?["result"] as? String else {
            return "0 BNB"
        }
        let cleaned = resultHex.hasPrefix("0x") ? String(resultHex.dropFirst(2)) : resultHex
        let wei = UInt64(cleaned, radix: 16) ?? 0
        let bnb = Double(wei) / pow(10.0, 18.0)
        return String(format: "%.6f BNB", bnb)
    }
    
    private func prepareBnbConfirmation() {
        // Parse amount
        guard let amount = Double(amountInput) else { return }
        
        // Get addresses
        let fromAddress = keys.bnb.address
        let toAddress = recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Calculate fee (gas limit * gas price)
        let gasLimit: UInt64 = 21000
        let gasPriceWei = (Double(gasPriceGwei) ?? 5) * 1_000_000_000
        let feeWei = Double(gasLimit) * gasPriceWei
        let feeBnb = feeWei / 1_000_000_000_000_000_000.0
        
        // Format amounts
        let formattedAmount = String(format: "%.8f BNB", amount)
        let formattedFee = String(format: "%.8f BNB", feeBnb)
        let formattedTotal = String(format: "%.8f BNB", amount + feeBnb)
        
        // Create confirmation
        pendingConfirmation = TransactionConfirmation(
            chainType: .bnb,
            fromAddress: fromAddress,
            toAddress: toAddress,
            amount: formattedAmount,
            amountFiat: nil,
            fee: formattedFee,
            feeFiat: nil,
            total: formattedTotal,
            totalFiat: nil,
            memo: nil,
            contractAddress: nil,
            tokenSymbol: nil,
            nonce: nonce,
            gasLimit: 21000,
            gasPrice: "\(gasPriceGwei) Gwei",
            networkName: "BNB Smart Chain",
            isTestnet: false,
            estimatedTime: "~3 seconds"
        )
    }
    
    private func sendTransaction() async {
        // Check biometric authentication first if required
        if BiometricAuthHelper.shouldRequireBiometric(settingEnabled: requireBiometric) {
            let result = await BiometricAuthHelper.authenticate(reason: "Authenticate to send BNB")
            switch result {
            case .success:
                break // Continue with transaction
            case .cancelled:
                return // User cancelled, don't show error
            case .failed(let message):
                await MainActor.run {
                    errorMessage = "Authentication failed: \(message)"
                    biometricFailed = true
                }
                return
            case .notAvailable:
                break // Biometric not available, continue anyway
            }
        }
        
        isLoading = true
        errorMessage = nil
        biometricFailed = false
        
        do {
            let privateKey = keys.bnb.privateHex
            guard addressValidation == .valid else {
                throw EthereumError.invalidAddress
            }
            guard amountValidation == .valid else {
                throw EthereumError.invalidAmount
            }
            let amountDecimal = NSDecimalNumber(string: amountInput)
            let multiplier = NSDecimalNumber(mantissa: 1, exponent: 18, isNegative: false)
            let weiAmount = amountDecimal.multiplying(by: multiplier).uint64Value
            guard weiAmount > 0 else { throw EthereumError.invalidAmount }
            let gasPriceWei = UInt64((Double(gasPriceGwei) ?? 5) * 1_000_000_000)
            let signedTx = try EthereumTransaction.buildAndSign(
                to: recipientAddress,
                value: String(weiAmount),
                gasLimit: 21000,
                gasPrice: String(gasPriceWei),
                nonce: nonce,
                chainId: chainId,
                privateKeyHex: privateKey
            )
            let txid = try await broadcastTransaction(signedTx)
            await MainActor.run {
                isLoading = false
                let result = TransactionBroadcastResult(
                    txid: txid,
                    chainId: chain.id,
                    chainName: chain.title,
                    amount: "\(amountInput) BNB",
                    recipient: recipientAddress
                )
                onSuccess(result)
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    private func broadcastTransaction(_ raw: String) async throws -> String {
        guard let url = URL(string: rpcURL) else {
            throw EthereumError.invalidAddress
        }
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_sendRawTransaction",
            "params": [raw],
            "id": 1
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let error = json?["error"] as? [String: Any], let message = error["message"] as? String {
            throw EthereumError.broadcastFailed(message)
        }
        guard let txid = json?["result"] as? String else {
            throw EthereumError.broadcastFailed("No tx hash returned")
        }
        return txid
    }
}

// MARK: - Solana Send Sheet

private struct SolanaSendSheet: View {
    let chain: ChainInfo
    let keys: AllKeys
    let requireBiometric: Bool
    let onDismiss: () -> Void
    let onSuccess: (TransactionBroadcastResult) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var recipientAddress = ""
    @State private var amountSOL = ""
    @State private var balanceDisplay = "0 SOL"
    @State private var recentBlockhash = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var addressValidation: AddressValidationResult = .empty
    @State private var amountValidation: AmountValidationResult = .empty
    @State private var resolvedSNSName: String? = nil
    @State private var isResolvingSNS = false
    @State private var snsResolutionTask: Task<Void, Never>?
    @State private var biometricFailed = false
    @State private var showCameraScanner = false
    @State private var showContactPicker = false
    @State private var pendingConfirmation: TransactionConfirmation?
    
    private let rpcURL = "https://api.mainnet-beta.solana.com"
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Amount Input
                VStack(spacing: 16) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        TextField("0", text: $amountSOL)
                            .font(.system(size: 48, weight: .medium, design: .rounded))
                            .multilineTextAlignment(.center)
                            .frame(minWidth: 100)
                            .fixedSize(horizontal: true, vertical: false)
                            .onChange(of: amountSOL) { _ in validateAmount() }
                        Text("SOL")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("Available: \(balanceDisplay)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .onTapGesture { sendMax() }

                    switch amountValidation {
                    case .invalid(let reason):
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.red)
                    case .valid:
                        Text("Amount looks good")
                            .font(.caption)
                            .foregroundStyle(.green)
                    case .empty:
                        EmptyView()
                    }
                }
                .padding(.top, 20)

                // Recipient Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("To")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.leading, 4)
                    
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .foregroundStyle(.secondary)
                        TextField("Address or name.sol", text: $recipientAddress)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                        
                        if isResolvingSNS {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else if !recipientAddress.isEmpty {
                            Button { 
                                recipientAddress = "" 
                                resolvedSNSName = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // SNS Resolution Status
                    if let snsName = resolvedSNSName {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.purple)
                            Text("Resolved from \(recipientAddress)")
                                .font(.caption)
                                .foregroundStyle(.purple)
                        }
                        .padding(.leading, 4)
                        
                        Text(snsName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                    }

                    switch addressValidation {
                    case .invalid(let reason):
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.leading, 4)
                    case .valid:
                        if resolvedSNSName == nil {
                            Text("Address looks good")
                                .font(.caption)
                                .foregroundStyle(.green)
                                .padding(.leading, 4)
                        }
                    case .empty:
                        EmptyView()
                    }

                    HStack(spacing: 8) {
                        Button { showContactPicker = true } label: {
                            Label("Contacts", systemImage: "person.crop.rectangle.stack")
                        }
                        .buttonStyle(.bordered)
                        
                        Button { showCameraScanner = true } label: {
                            Label("Camera", systemImage: "camera")
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: scanSolanaQRCode) {
                            Label("Scan QR", systemImage: "qrcode.viewfinder")
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                    }
                }
                .padding(.horizontal)

                // Network Fee Info
                VStack(alignment: .leading, spacing: 8) {
                    Text("Network Fee")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.leading, 4)
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Estimated Fee")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("~0.000005 SOL")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.purple)
                        }
                        Spacer()
                        Text("Solana Network")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.1))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }
                    .padding(12)
                    .background(Color.gray.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                // Send Button - shows confirmation sheet first
                Button {
                    prepareSolConfirmation()
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView().tint(.white)
                        }
                        Text(isLoading ? "Sending..." : "Send SOL")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isValidForm ? Color.purple : Color.gray.opacity(0.3))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(!isValidForm || isLoading)
                .padding()
            }
            .sheet(item: $pendingConfirmation) { confirmation in
                TransactionConfirmationSheet(
                    confirmation: confirmation,
                    onConfirm: {
                        pendingConfirmation = nil
                        Task { await sendTransaction() }
                    },
                    onCancel: {
                        pendingConfirmation = nil
                    }
                )
            }
            .navigationTitle("Send Solana")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss(); onDismiss() }
                }
            }
            .task { await loadWalletState() }
            .onAppear {
                validateRecipientAddress()
                validateAmount()
            }
            .onChange(of: recipientAddress) { _ in 
                resolvedSNSName = nil
                snsResolutionTask?.cancel()
                validateRecipientAddressWithSNS()
            }
        }
        .sheet(isPresented: $showCameraScanner) {
            QRCameraScannerView(isPresented: $showCameraScanner) { scannedText in
                applySolanaPayload(scannedText)
            }
        }
        .sheet(isPresented: $showContactPicker) {
            ContactPickerSheet(
                chain: "solana",
                contacts: ContactsManager.shared.contacts,
                onSelect: { contact in
                    recipientAddress = contact.address
                    resolvedSNSName = nil
                    validateRecipientAddress()
                    showContactPicker = false
                },
                onCancel: {
                    showContactPicker = false
                }
            )
        }
        .frame(width: 480, height: 600)
    }
    
    private var isValidForm: Bool {
        addressValidation == .valid && (Double(amountSOL) ?? 0) > 0 && !recentBlockhash.isEmpty && amountValidation == .valid && !isResolvingSNS
    }
    
    private func sendMax() {
        let value = Double(balanceDisplay.replacingOccurrences(of: " SOL", with: "")) ?? 0
        amountSOL = String(format: "%.6f", max(0, value - 0.000005))
        validateAmount()
    }

    private func validateAmount() {
        let locale = Locale(identifier: "en_US_POSIX")
        let available = decimalValue(from: balanceDisplay, locale: locale)
        let minUnit = Decimal(string: "0.000001", locale: locale) ?? 0.000001
        let reserve = Decimal(string: "0.000005", locale: locale) ?? 0.000005
        amountValidation = AmountValidator.validateDecimalAsset(
            amountString: amountSOL,
            assetName: "SOL",
            available: available,
            precision: 9,
            minimum: minUnit,
            reserved: reserve
        )
    }

    private func decimalValue(from display: String, locale: Locale) -> Decimal {
        let numericPortion = display.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? display
        return Decimal(string: numericPortion, locale: locale) ?? 0
    }

    private func scanSolanaQRCode() {
        guard let payload = QRCodeScanner.scanText() else { return }
        applySolanaPayload(payload)
    }
    
    private func scanSolanaQRFromClipboard() {
        let result = QRCodeScanner.scanFromClipboard()
        switch result {
        case .success(let payload):
            applySolanaPayload(payload)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func applySolanaPayload(_ raw: String) {
        let uri = CryptoURI(raw)
        if let scheme = uri.scheme, scheme == "solana" {
            if !uri.target.isEmpty {
                recipientAddress = uri.target
            }
            if let lamportValue = uri.queryValue("value"), let decimal = Decimal(string: lamportValue) {
                amountSOL = formatLamportAmount(decimal)
            } else if let amountValue = uri.queryValue("amount"), !amountValue.isEmpty {
                amountSOL = amountValue
            }
        } else {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                recipientAddress = trimmed
            }
        }
        validateRecipientAddress()
        validateAmount()
    }

    private func formatLamportAmount(_ lamports: Decimal) -> String {
        let divisor = Decimal(string: "1000000000") ?? 1_000_000_000
        guard divisor != 0 else { return amountSOL }
        let solValue = lamports / divisor
        return String(format: "%.6f", NSDecimalNumber(decimal: solValue).doubleValue)
    }

    private func validateRecipientAddress() {
        addressValidation = AddressValidator.validateSolanaAddress(recipientAddress)
    }

    private func validateRecipientAddressWithSNS() {
        let input = recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if it looks like an SNS name
        if NameResolver.isResolvableName(input) && input.lowercased().hasSuffix(".sol") {
            // It's an SNS name - resolve it
            isResolvingSNS = true
            addressValidation = .empty
            
            snsResolutionTask = Task {
                do {
                    let resolved = try await NameResolver.shared.resolveSNS(input)
                    await MainActor.run {
                        resolvedSNSName = resolved
                        isResolvingSNS = false
                        // Validate the resolved address
                        addressValidation = AddressValidator.validateSolanaAddress(resolved)
                    }
                } catch {
                    await MainActor.run {
                        resolvedSNSName = nil
                        isResolvingSNS = false
                        addressValidation = .invalid(error.localizedDescription)
                    }
                }
            }
        } else {
            // Regular address validation
            resolvedSNSName = nil
            validateRecipientAddress()
        }
    }

    /// Returns the actual address to send to (resolved SNS or direct input)
    private var effectiveRecipientAddress: String {
        resolvedSNSName ?? recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func loadWalletState() async {
        isLoading = true
        errorMessage = nil
        do {
            balanceDisplay = try await fetchBalance()
            recentBlockhash = try await fetchRecentBlockhash()
            isLoading = false
            validateAmount()
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    private func fetchBalance() async throws -> String {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getBalance",
            "params": [keys.solana.publicKeyBase58]
        ]
        let result = try await solanaRPCResult(payload: payload)
        if let wrapper = result as? [String: Any], let value = wrapper["value"] as? UInt64 {
            let sol = Double(value) / 1_000_000_000.0
            return String(format: "%.6f SOL", sol)
        }
        return "0 SOL"
    }
    
    private func fetchRecentBlockhash() async throws -> String {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getLatestBlockhash",
            "params": []
        ]
        if let result = try await solanaRPCResult(payload: payload) as? [String: Any],
           let value = result["value"] as? [String: Any],
           let hash = value["blockhash"] as? String {
            return hash
        }
        throw SolanaSendError.networkFailure("Missing blockhash")
    }
    
    private func solanaRPCResult(payload: [String: Any]) async throws -> Any {
        guard let url = URL(string: rpcURL) else {
            throw SolanaSendError.networkFailure("Invalid RPC URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let error = json?["error"] as? [String: Any], let message = error["message"] as? String {
            throw SolanaSendError.networkFailure(message)
        }
        guard let result = json?["result"] else {
            throw SolanaSendError.networkFailure("Malformed RPC response")
        }
        return result
    }
    
    private func prepareSolConfirmation() {
        // Parse amount
        guard let amount = Double(amountSOL) else { return }
        
        // Get addresses - Solana uses publicKeyBase58 as address
        let fromAddress = keys.solana.publicKeyBase58
        let toAddress = resolvedSNSName ?? recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Solana fees are very small (~0.000005 SOL per signature)
        let estimatedFeeSol = 0.000005
        let totalSol = amount + estimatedFeeSol
        
        // Format amounts
        let formattedAmount = String(format: "%.9f SOL", amount)
        let formattedFee = String(format: "%.9f SOL (~0.00001 USD)", estimatedFeeSol)
        let formattedTotal = String(format: "%.9f SOL", totalSol)
        
        // Create confirmation
        pendingConfirmation = TransactionConfirmation(
            chainType: .solana,
            fromAddress: fromAddress,
            toAddress: toAddress,
            amount: formattedAmount,
            amountFiat: nil,
            fee: formattedFee,
            feeFiat: nil,
            total: formattedTotal,
            totalFiat: nil,
            memo: nil,
            contractAddress: nil,
            tokenSymbol: nil,
            nonce: nil,
            gasLimit: nil,
            gasPrice: nil,
            networkName: "Solana Mainnet",
            isTestnet: false,
            estimatedTime: "~400ms"
        )
    }
    
    private func sendTransaction() async {
        // Check biometric authentication first if required
        if BiometricAuthHelper.shouldRequireBiometric(settingEnabled: requireBiometric) {
            let result = await BiometricAuthHelper.authenticate(reason: "Authenticate to send SOL")
            switch result {
            case .success:
                break // Continue with transaction
            case .cancelled:
                return // User cancelled, don't show error
            case .failed(let message):
                await MainActor.run {
                    errorMessage = "Authentication failed: \(message)"
                    biometricFailed = true
                }
                return
            case .notAvailable:
                break // Biometric not available, continue anyway
            }
        }
        
        isLoading = true
        errorMessage = nil
        biometricFailed = false
        
        do {
            guard addressValidation == .valid else {
                throw SolanaSendError.invalidAddress
            }
            guard amountValidation == .valid else {
                throw SolanaSendError.invalidAmount
            }
            
            // Use resolved SNS address if available
            let toAddress = effectiveRecipientAddress
            
            let amountDecimal = NSDecimalNumber(string: amountSOL)
            let lamports = amountDecimal.multiplying(by: NSDecimalNumber(value: 1_000_000_000)).uint64Value
            guard lamports > 0 else { throw SolanaSendError.invalidAmount }
            let signed = try SolanaTransaction.buildAndSign(
                from: keys.solana.publicKeyBase58,
                to: toAddress,
                amount: lamports,
                recentBlockhash: recentBlockhash,
                privateKeyBase58: keys.solana.privateKeyBase58
            )
            guard let txData = Base58.decode(signed) else {
                throw SolanaSendError.signingFailed
            }
            let base64Tx = txData.base64EncodedString()
            let payload: [String: Any] = [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sendTransaction",
                "params": [base64Tx]
            ]
            guard let txid = try await solanaRPCResult(payload: payload) as? String else {
                throw SolanaSendError.networkFailure("No transaction signature returned")
            }
            await MainActor.run {
                isLoading = false
                let result = TransactionBroadcastResult(
                    txid: txid,
                    chainId: chain.id,
                    chainName: chain.title,
                    amount: "\(amountSOL) SOL",
                    recipient: recipientAddress
                )
                onSuccess(result)
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

enum SolanaSendError: LocalizedError {
    case invalidAddress
    case invalidAmount
    case signingFailed
    case networkFailure(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "Enter a valid Solana address."
        case .invalidAmount:
            return "Enter a valid SOL amount."
        case .signingFailed:
            return "Failed to sign transaction."
        case .networkFailure(let message):
            return message
        }
    }
}

private struct ReceiveFundsSheet: View {
    let chains: [ChainInfo]
    let onCopy: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var copiedChainID: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(chains) { chain in
                        ReceiveAddressCard(
                            chain: chain,
                            isCopied: copiedChainID == chain.id,
                            onCopy: {
                                guard let address = chain.receiveAddress else { return }
                                onCopy(address)
                                copiedChainID = chain.id
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    if copiedChainID == chain.id {
                                        copiedChainID = nil
                                    }
                                }
                            }
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Receive Funds")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 550, height: 500)
    }
}

private struct ReceiveAddressCard: View {
    let chain: ChainInfo
    let isCopied: Bool
    let onCopy: () -> Void
    @State private var showingQRCode = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: chain.iconName)
                    .font(.title2)
                    .foregroundStyle(chain.accentColor)
                    .frame(width: 36, height: 36)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(chain.title)
                        .font(.headline)
                    Text(chain.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            Divider()
            
            if let address = chain.receiveAddress, !address.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Receive Address")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    
                    if showingQRCode {
                        HStack {
                            Spacer()
                            QRCodeView(content: address, size: 180)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                    
                    Text(address)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    HStack(spacing: 12) {
                        Button(action: onCopy) {
                            Label(
                                isCopied ? "Copied!" : "Copy",
                                systemImage: isCopied ? "checkmark.circle.fill" : "doc.on.doc"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isCopied ? .green : chain.accentColor)
                        .animation(.easeInOut(duration: 0.2), value: isCopied)
                        
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingQRCode.toggle()
                            }
                        } label: {
                            Label(
                                showingQRCode ? "Hide QR" : "Show QR",
                                systemImage: showingQRCode ? "qrcode" : "qrcode.viewfinder"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        
                        #if canImport(AppKit)
                        Button {
                            shareAddress(address, chainName: chain.title)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        #endif
                    }
                }
            } else {
                Text("Receiving address unavailable for this chain.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(chain.accentColor.opacity(0.2), lineWidth: 1)
        )
    }
    
    #if canImport(AppKit)
    private func shareAddress(_ address: String, chainName: String) {
        let sharingText = "My \(chainName) address: \(address)"
        let picker = NSSharingServicePicker(items: [sharingText])
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            let rect = CGRect(x: contentView.bounds.midX, y: contentView.bounds.midY, width: 1, height: 1)
            picker.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
        }
    }
    #endif
}

/// A high-performance sparkline chart using Canvas and pre-computed values
private struct SparklineView: View {
    let dataPoints: [Double]
    var lineColor: Color = .blue
    var height: CGFloat = 24
    
    // Pre-computed values for performance
    private let normalizedPoints: [CGFloat]
    private let priceChange: Double
    private let trendColor: Color
    
    init(dataPoints: [Double], lineColor: Color = .blue, height: CGFloat = 24) {
        self.dataPoints = dataPoints
        self.lineColor = lineColor
        self.height = height
        
        // Pre-compute all values once at init time
        if dataPoints.isEmpty {
            normalizedPoints = []
            priceChange = 0
            trendColor = .secondary
        } else {
            let minVal = dataPoints.min() ?? 0
            let maxVal = dataPoints.max() ?? 1
            let range = maxVal - minVal
            
            if range > 0 {
                normalizedPoints = dataPoints.map { CGFloat(($0 - minVal) / range) }
            } else {
                normalizedPoints = dataPoints.map { _ in CGFloat(0.5) }
            }
            
            // Pre-compute price change
            if dataPoints.count >= 2,
               let first = dataPoints.first,
               let last = dataPoints.last,
               first > 0 {
                priceChange = ((last - first) / first) * 100
            } else {
                priceChange = 0
            }
            
            // Pre-compute trend color
            if priceChange > 0.1 {
                trendColor = .green
            } else if priceChange < -0.1 {
                trendColor = .red
            } else {
                trendColor = .secondary
            }
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            // Sparkline chart using Canvas for better scroll performance
            Canvas { context, size in
                guard normalizedPoints.count > 1 else { return }
                
                let stepX = size.width / CGFloat(normalizedPoints.count - 1)
                var path = Path()
                
                for (index, value) in normalizedPoints.enumerated() {
                    let x = stepX * CGFloat(index)
                    let y = size.height * (1 - value)
                    
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                
                context.stroke(
                    path,
                    with: .color(trendColor),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
            }
            .frame(width: 50, height: height)

            // Percentage change
            if !dataPoints.isEmpty {
                Text(priceChange >= 0 ? "+\(String(format: "%.1f", priceChange))%" : "\(String(format: "%.1f", priceChange))%")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(trendColor)
            }
        }
    }
}

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

private struct SkeletonLine: View {
    var width: CGFloat? = 80
    var height: CGFloat = 10
    var cornerRadius: CGFloat = 6

    @State private var phase: CGFloat = -0.8
    @State private var isVisible = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .frame(width: width, height: height)
            .overlay(
                Group {
                    if isVisible {
                        GeometryReader { geometry in
                            let gradient = LinearGradient(
                                colors: [
                                    Color.primary.opacity(0.08),
                                    Color.primary.opacity(0.18),
                                    Color.primary.opacity(0.08)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(gradient)
                                .scaleEffect(x: 1.6, y: 1, anchor: .leading)
                                .offset(x: geometry.size.width * phase)
                        }
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onAppear {
                isVisible = true
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                    phase = 0.9
                }
            }
            .onDisappear {
                // Stop animation when off-screen to save GPU cycles
                isVisible = false
                phase = -0.8
            }
    }
}

private struct CopyFeedbackBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(message)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.15), radius: 6, y: 4)
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    languageSection
                    
                    Divider()
                    
                    currencySection
                    
                    Divider()

                    keysButton
                    securityButton
                    privacyButton

                    Spacer()
                }
                .padding()
            }
            .frame(width: 380, height: 450)
            .navigationTitle("settings.title".localized)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close".localized) { dismiss() }
                }
            }
        }
    }
    
    @State private var selectedLanguage: LocalizationManager.Language = .english
    
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

struct ChainInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let iconName: String
    let accentColor: Color
    let details: [KeyDetail]
    let receiveAddress: String?
}

enum BalanceFetchError: LocalizedError {
    case invalidRequest
    case invalidResponse
    case invalidStatus(Int)
    case invalidPayload
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "Failed to build balance request."
        case .invalidResponse:
            return "Remote balance service returned an unexpected response."
        case .invalidStatus(let code):
            return "Balance service returned status code \(code)."
        case .invalidPayload:
            return "Balance service returned unexpected data."
        case .rateLimited:
            return "Rate limited - prices will update shortly."
        }
    }
}

private struct EthplorerAddressResponse: Decodable {
    let eth: Eth
    let tokens: [TokenBalance]?

    struct Eth: Decodable {
        let balance: Double

        enum CodingKeys: String, CodingKey {
            case balance
        }
    }

    struct TokenBalance: Decodable {
        let tokenInfo: TokenInfo?
        let balance: Double?
        let rawBalance: String?
    }

    struct TokenInfo: Decodable {
        let symbol: String?
        let decimals: String?
        let address: String?
    }

    enum CodingKeys: String, CodingKey {
        case eth = "ETH"
        case tokens
    }
}

private struct XrpScanAccountResponse: Decodable {
    let xrpBalance: String?
    let balance: String?

    enum CodingKeys: String, CodingKey {
        case xrpBalance
        case balance = "Balance"
    }
}

private struct RippleDataAccountBalanceResponse: Decodable {
    struct BalanceEntry: Decodable {
        let currency: String
        let value: String
    }

    let result: String?
    let balances: [BalanceEntry]?
    let message: String?

    var xrpBalanceValue: Decimal? {
        guard let entry = balances?.first(where: { $0.currency.uppercased() == "XRP" }) else {
            return nil
        }
        return Decimal(string: entry.value)
    }

    var isAccountMissing: Bool {
        guard let result else { return false }
        if result.lowercased() == "success" { return false }
        if let message = message?.lowercased(), message.contains("not found") {
            return true
        }
        return false
    }
}

struct KeyDetail: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let value: String
}

private struct EncryptedPackage: Codable {
    let formatVersion: Int
    let createdAt: Date
    let salt: String
    let nonce: String
    let ciphertext: String
    let tag: String
}

private enum SecureArchiveError: LocalizedError {
    case invalidEnvelope

    var errorDescription: String? {
        switch self {
        case .invalidEnvelope:
            return "Encrypted backup file is malformed or corrupted."
        }
    }
}

// MARK: - Wallet Response Wrapper (from Rust CLI)
private struct WalletResponse: Codable {
    let mnemonic: String
    let keys: AllKeys
}

struct AllKeys: Codable {
    let bitcoin: BitcoinKeys
    let bitcoinTestnet: BitcoinKeys
    let litecoin: LitecoinKeys
    let monero: MoneroKeys
    let solana: SolanaKeys
    let ethereum: EthereumKeys
    let ethereumSepolia: EthereumKeys
    let bnb: BnbKeys
    let xrp: XrpKeys

    private enum CodingKeys: String, CodingKey {
        case bitcoin
        case bitcoinTestnet = "bitcoin_testnet"
        case litecoin
        case monero
        case solana
        case ethereum
        case ethereumSepolia = "ethereum_sepolia"
        case bnb
        case xrp
    }

    var chainInfos: [ChainInfo] {
        var cards: [ChainInfo] = [
            ChainInfo(
                id: "bitcoin",
                title: "Bitcoin",
                subtitle: "SegWit P2WPKH",
                iconName: "bitcoinsign.circle.fill",
                accentColor: Color.orange,
                details: [
                    KeyDetail(label: "Private Key (hex)", value: bitcoin.privateHex),
                    KeyDetail(label: "Private Key (WIF)", value: bitcoin.privateWif),
                    KeyDetail(label: "Public Key (compressed hex)", value: bitcoin.publicCompressedHex),
                    KeyDetail(label: "Address", value: bitcoin.address)
                ],
                receiveAddress: bitcoin.address
            ),
            ChainInfo(
                id: "bitcoin-testnet",
                title: "Bitcoin Testnet",
                subtitle: "SegWit Testnet",
                iconName: "bitcoinsign.circle",
                accentColor: Color.orange.opacity(0.7),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: bitcoinTestnet.privateHex),
                    KeyDetail(label: "Private Key (WIF)", value: bitcoinTestnet.privateWif),
                    KeyDetail(label: "Public Key (compressed hex)", value: bitcoinTestnet.publicCompressedHex),
                    KeyDetail(label: "Testnet Address", value: bitcoinTestnet.address)
                ],
                receiveAddress: bitcoinTestnet.address
            ),
            ChainInfo(
                id: "litecoin",
                title: "Litecoin",
                subtitle: "Bech32 P2WPKH",
                iconName: "l.circle.fill",
                accentColor: Color.green,
                details: [
                    KeyDetail(label: "Private Key (hex)", value: litecoin.privateHex),
                    KeyDetail(label: "Private Key (WIF)", value: litecoin.privateWif),
                    KeyDetail(label: "Public Key (compressed hex)", value: litecoin.publicCompressedHex),
                    KeyDetail(label: "Address", value: litecoin.address)
                ],
                receiveAddress: litecoin.address
            ),
            ChainInfo(
                id: "monero",
                title: "Monero",
                subtitle: "Primary Account",
                iconName: "m.circle.fill",
                accentColor: Color.purple,
                details: [
                    KeyDetail(label: "Private Spend Key", value: monero.privateSpendHex),
                    KeyDetail(label: "Private View Key", value: monero.privateViewHex),
                    KeyDetail(label: "Public Spend Key", value: monero.publicSpendHex),
                    KeyDetail(label: "Public View Key", value: monero.publicViewHex),
                    KeyDetail(label: "Primary Address", value: monero.address)
                ],
                receiveAddress: monero.address
            ),
            ChainInfo(
                id: "solana",
                title: "Solana",
                subtitle: "Ed25519 Keypair",
                iconName: "s.circle.fill",
                accentColor: Color.blue,
                details: [
                    KeyDetail(label: "Private Seed (hex)", value: solana.privateSeedHex),
                    KeyDetail(label: "Private Key (base58)", value: solana.privateKeyBase58),
                    KeyDetail(label: "Public Key / Address", value: solana.publicKeyBase58)
                ],
                receiveAddress: solana.publicKeyBase58
            ),
            ChainInfo(
                id: "xrp",
                title: "XRP Ledger",
                subtitle: "Classic Address",
                iconName: "xmark.seal.fill",
                accentColor: Color.indigo,
                details: [
                    KeyDetail(label: "Private Key (hex)", value: xrp.privateHex),
                    KeyDetail(label: "Public Key (compressed hex)", value: xrp.publicCompressedHex),
                    KeyDetail(label: "Classic Address", value: xrp.classicAddress)
                ],
                receiveAddress: xrp.classicAddress
            )
        ]

        let ethereumDetails = [
            KeyDetail(label: "Private Key (hex)", value: ethereum.privateHex),
            KeyDetail(label: "Public Key (uncompressed hex)", value: ethereum.publicUncompressedHex),
            KeyDetail(label: "Checksummed Address", value: ethereum.address)
        ]

        cards.append(
            ChainInfo(
                id: "ethereum",
                title: "Ethereum",
                subtitle: "EIP-55 Address",
                iconName: "e.circle.fill",
                accentColor: Color.pink,
                details: ethereumDetails,
                receiveAddress: ethereum.address
            )
        )

        cards.append(
            ChainInfo(
                id: "ethereum-sepolia",
                title: "Ethereum Sepolia",
                subtitle: "Testnet Address",
                iconName: "e.circle",
                accentColor: Color.pink.opacity(0.7),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: ethereumSepolia.privateHex),
                    KeyDetail(label: "Public Key (uncompressed hex)", value: ethereumSepolia.publicUncompressedHex),
                    KeyDetail(label: "Checksummed Address", value: ethereumSepolia.address)
                ],
                receiveAddress: ethereumSepolia.address
            )
        )

        let bnbDetails = [
            KeyDetail(label: "Private Key (hex)", value: bnb.privateHex),
            KeyDetail(label: "Public Key (uncompressed hex)", value: bnb.publicUncompressedHex),
            KeyDetail(label: "Checksummed Address", value: bnb.address)
        ]

        cards.append(
            ChainInfo(
                id: "bnb",
                title: "BNB Smart Chain",
                subtitle: "EVM Compatible",
                iconName: "b.circle.fill",
                accentColor: Color(red: 0.95, green: 0.77, blue: 0.23),
                details: bnbDetails,
                receiveAddress: bnb.address
            )
        )

        let tokenEntries: [(idPrefix: String, title: String, subtitle: String, accent: Color, contract: String)] = [
            ("usdt", "Tether USD (USDT)", "ERC-20 Token", Color(red: 0.0, green: 0.64, blue: 0.54), "0xdAC17F958D2ee523a2206206994597C13D831ec7"),
            ("usdc", "USD Coin (USDC)", "ERC-20 Token", Color.blue, "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"),
            ("dai", "Dai (DAI)", "ERC-20 Token", Color.yellow, "0x6B175474E89094C44Da98b954EedeAC495271d0F")
        ]

        for entry in tokenEntries {
            let tokenDetails: [KeyDetail] = [
                KeyDetail(label: "Ethereum Wallet Address", value: ethereum.address),
                KeyDetail(label: "Token Contract", value: entry.contract)
            ]

            cards.append(
                ChainInfo(
                    id: "\(entry.idPrefix)-erc20",
                    title: entry.title,
                    subtitle: entry.subtitle,
                    iconName: "dollarsign.circle.fill",
                    accentColor: entry.accent,
                    details: tokenDetails,
                    receiveAddress: ethereum.address
                )
            )
        }

        return cards
    }
}

struct BitcoinKeys: Codable {
    let privateHex: String
    let privateWif: String
    let publicCompressedHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case privateWif = "private_wif"
        case publicCompressedHex = "public_compressed_hex"
        case address
    }
}

struct LitecoinKeys: Codable {
    let privateHex: String
    let privateWif: String
    let publicCompressedHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case privateWif = "private_wif"
        case publicCompressedHex = "public_compressed_hex"
        case address
    }
}

struct MoneroKeys: Codable {
    let privateSpendHex: String
    let privateViewHex: String
    let publicSpendHex: String
    let publicViewHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateSpendHex = "private_spend_hex"
        case privateViewHex = "private_view_hex"
        case publicSpendHex = "public_spend_hex"
        case publicViewHex = "public_view_hex"
        case address
    }
}

struct SolanaKeys: Codable {
    let privateSeedHex: String
    let privateKeyBase58: String
    let publicKeyBase58: String

    private enum CodingKeys: String, CodingKey {
        case privateSeedHex = "private_seed_hex"
        case privateKeyBase58 = "private_key_base58"
        case publicKeyBase58 = "public_key_base58"
    }
}

struct EthereumKeys: Codable {
    let privateHex: String
    let publicUncompressedHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicUncompressedHex = "public_uncompressed_hex"
        case address
    }
}

struct BnbKeys: Codable {
    let privateHex: String
    let publicUncompressedHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicUncompressedHex = "public_uncompressed_hex"
        case address
    }
}

struct XrpKeys: Codable {
    let privateHex: String
    let publicCompressedHex: String
    let classicAddress: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicCompressedHex = "public_compressed_hex"
        case classicAddress = "classic_address"
    }
}

// MARK: - Keychain Storage
private struct KeychainHelper {
    static let keysIdentifier = "com.hawala.wallet.keys"
    
    static func saveKeys(_ keys: AllKeys) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(keys)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keysIdentifier,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    static func loadKeys() throws -> AllKeys? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keysIdentifier,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.loadFailed(status)
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(AllKeys.self, from: data)
    }
    
    static func deleteKeys() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keysIdentifier
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save keys to Keychain (status: \(status))"
        case .loadFailed(let status):
            return "Failed to load keys from Keychain (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete keys from Keychain (status: \(status))"
        }
    }
}

enum KeyGeneratorError: LocalizedError {
    case executionFailed(String)
    case cargoNotFound

    var errorDescription: String? {
        switch self {
        case .executionFailed(let message):
            return message
        case .cargoNotFound:
            return "Unable to locate the cargo executable. Install Rust via https://rustup.rs or set the CARGO_BIN environment variable to the cargo path."
        }
    }
}

// MARK: - Monero Send Sheet

private struct MoneroSendSheet: View {
    let chain: ChainInfo
    let keys: AllKeys
    let requireBiometric: Bool
    let onDismiss: () -> Void
    let onSuccess: (TransactionBroadcastResult) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var recipientAddress = ""
    @State private var amountInput = ""
    @State private var balanceDisplay = "0 XMR"
    @State private var estimatedFee = "—"
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var amountValidation: AmountValidationResult = .empty
    @State private var addressValidation: AddressValidationResult = .empty
    @State private var pendingConfirmation: TransactionConfirmation?
    
    // Public Monero node for demo purposes
    private let rpcURL = "https://node.moneroworld.com:18089/json_rpc"
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Recipient") {
                    TextField("4...", text: $recipientAddress)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .onChange(of: recipientAddress) { _ in validateAddress() }

                    switch addressValidation {
                    case .invalid(let reason):
                        Text(reason).font(.caption).foregroundStyle(.red)
                    case .valid:
                        Text("Address looks good").font(.caption).foregroundStyle(.green)
                    case .empty:
                        EmptyView()
                    }
                }
                
                Section("Amount") {
                    HStack {
                        TextField("0.0", text: $amountInput)
                            .onChange(of: amountInput) { _ in validateAmount() }
                        Text("XMR").foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Available")
                        Spacer()
                        Text(balanceDisplay).foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    
                    switch amountValidation {
                    case .invalid(let reason):
                        Text(reason).font(.caption).foregroundStyle(.red)
                    case .valid:
                        Text("Amount looks good").font(.caption).foregroundStyle(.green)
                    case .empty:
                        EmptyView()
                    }
                }
                
                Section("Network Fee") {
                    HStack {
                        Text("Estimated Fee")
                        Spacer()
                        Text(estimatedFee).font(.system(.body, design: .monospaced))
                    }
                }
                
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.caption)
                    }
                }
                
                Section {
                    Button {
                        prepareMoneroConfirmation()
                    } label: {
                        HStack {
                            if isLoading { ProgressView().controlSize(.small).tint(.white) }
                            Text(isLoading ? "Sending..." : "Send XMR")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValidForm || isLoading)
                }
            }
            .navigationTitle("Send \(chain.title)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
            }
            .sheet(item: $pendingConfirmation) { confirmation in
                TransactionConfirmationSheet(
                    confirmation: confirmation,
                    onConfirm: {
                        pendingConfirmation = nil
                        Task { await sendTransaction() }
                    },
                    onCancel: {
                        pendingConfirmation = nil
                    }
                )
            }
            .onAppear {
                fetchBalance()
                estimateFee()
            }
        }
    }
    
    private var isValidForm: Bool {
        if case .valid = addressValidation, case .valid = amountValidation {
            return true
        }
        return false
    }
    
    private func validateAddress() {
        if recipientAddress.isEmpty {
            addressValidation = .empty
            return
        }
        // Basic Monero address validation (starts with 4 or 8, length check)
        if (recipientAddress.hasPrefix("4") || recipientAddress.hasPrefix("8")) && recipientAddress.count > 90 {
            addressValidation = .valid
        } else {
            addressValidation = .invalid("Invalid Monero address format")
        }
    }
    
    private func validateAmount() {
        guard let amount = Double(amountInput), amount > 0 else {
            amountValidation = .invalid("Invalid amount")
            return
        }
        // Simple check against mock balance
        if amount > 1000 { // Mock balance check
            amountValidation = .invalid("Insufficient funds")
        } else {
            amountValidation = .valid
        }
    }
    
    private func fetchBalance() {
        // Mock balance for now
        balanceDisplay = "12.500000000000 XMR"
    }
    
    private func estimateFee() {
        // Mock fee
        estimatedFee = "0.00004000 XMR"
    }
    
    private func prepareMoneroConfirmation() {
        guard let amount = Double(amountInput) else { return }
        
        let confirmation = TransactionConfirmation(
            chainType: .monero,
            fromAddress: keys.monero.address,
            toAddress: recipientAddress,
            amount: amountInput,
            amountFiat: nil,
            fee: estimatedFee,
            feeFiat: nil,
            total: String(format: "%.12f", amount + 0.00004),
            totalFiat: nil,
            memo: nil,
            contractAddress: nil,
            tokenSymbol: "XMR",
            nonce: nil,
            gasLimit: nil,
            gasPrice: nil,
            networkName: "Monero Mainnet",
            isTestnet: false,
            estimatedTime: "20 mins"
        )
        pendingConfirmation = confirmation
    }
    
    private func sendTransaction() async {
        isLoading = true
        errorMessage = nil
        
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
        
        // Mock success
        let txid = "c88ce..." + String(Int.random(in: 1000...9999))
        
        isLoading = false
        onSuccess(TransactionBroadcastResult(
            txid: txid,
            chainId: chain.id,
            chainName: chain.title,
            amount: amountInput,
            recipient: recipientAddress
        ))
    }
}

// MARK: - XRP Send Sheet

private struct XRPSendSheet: View {
    let chain: ChainInfo
    let keys: AllKeys
    let requireBiometric: Bool
    let onDismiss: () -> Void
    let onSuccess: (TransactionBroadcastResult) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var recipientAddress = ""
    @State private var destinationTag = ""
    @State private var amountInput = ""
    @State private var balanceDisplay = "0 XRP"
    @State private var estimatedFee = "—"
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var amountValidation: AmountValidationResult = .empty
    @State private var addressValidation: AddressValidationResult = .empty
    @State private var pendingConfirmation: TransactionConfirmation?
    
    private let rpcURL = "https://s1.ripple.com:51234/"
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Recipient") {
                    TextField("r...", text: $recipientAddress)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .onChange(of: recipientAddress) { _ in validateAddress() }
                    
                    TextField("Destination Tag (Optional)", text: $destinationTag)
                        .textFieldStyle(.roundedBorder)

                    switch addressValidation {
                    case .invalid(let reason):
                        Text(reason).font(.caption).foregroundStyle(.red)
                    case .valid:
                        Text("Address looks good").font(.caption).foregroundStyle(.green)
                    case .empty:
                        EmptyView()
                    }
                }
                
                Section("Amount") {
                    HStack {
                        TextField("0.0", text: $amountInput)
                            .onChange(of: amountInput) { _ in validateAmount() }
                        Text("XRP").foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Available")
                        Spacer()
                        Text(balanceDisplay).foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    
                    switch amountValidation {
                    case .invalid(let reason):
                        Text(reason).font(.caption).foregroundStyle(.red)
                    case .valid:
                        Text("Amount looks good").font(.caption).foregroundStyle(.green)
                    case .empty:
                        EmptyView()
                    }
                }
                
                Section("Network Fee") {
                    HStack {
                        Text("Estimated Fee")
                        Spacer()
                        Text(estimatedFee).font(.system(.body, design: .monospaced))
                    }
                }
                
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.caption)
                    }
                }
                
                Section {
                    Button {
                        prepareXRPConfirmation()
                    } label: {
                        HStack {
                            if isLoading { ProgressView().controlSize(.small).tint(.white) }
                            Text(isLoading ? "Sending..." : "Send XRP")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValidForm || isLoading)
                }
            }
            .navigationTitle("Send \(chain.title)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
            }
            .sheet(item: $pendingConfirmation) { confirmation in
                TransactionConfirmationSheet(
                    confirmation: confirmation,
                    onConfirm: {
                        pendingConfirmation = nil
                        Task { await sendTransaction() }
                    },
                    onCancel: {
                        pendingConfirmation = nil
                    }
                )
            }
            .onAppear {
                fetchBalance()
                estimateFee()
            }
        }
    }
    
    private var isValidForm: Bool {
        if case .valid = addressValidation, case .valid = amountValidation {
            return true
        }
        return false
    }
    
    private func validateAddress() {
        if recipientAddress.isEmpty {
            addressValidation = .empty
            return
        }
        // Basic XRP address validation (starts with r, length check)
        if recipientAddress.hasPrefix("r") && recipientAddress.count >= 25 && recipientAddress.count <= 35 {
            addressValidation = .valid
        } else {
            addressValidation = .invalid("Invalid XRP address format")
        }
    }
    
    private func validateAmount() {
        guard let amount = Double(amountInput), amount > 0 else {
            amountValidation = .invalid("Invalid amount")
            return
        }
        // Simple check against mock balance
        if amount > 1000 { // Mock balance check
            amountValidation = .invalid("Insufficient funds")
        } else {
            amountValidation = .valid
        }
    }
    
    private func fetchBalance() {
        // Mock balance for now
        balanceDisplay = "500.000000 XRP"
    }
    
    private func estimateFee() {
        // Mock fee (12 drops)
        estimatedFee = "0.000012 XRP"
    }
    
    private func prepareXRPConfirmation() {
        guard let amount = Double(amountInput) else { return }
        
        let confirmation = TransactionConfirmation(
            chainType: .xrp,
            fromAddress: keys.xrp.classicAddress,
            toAddress: recipientAddress,
            amount: amountInput,
            amountFiat: nil,
            fee: estimatedFee,
            feeFiat: nil,
            total: String(format: "%.6f", amount + 0.000012),
            totalFiat: nil,
            memo: destinationTag.isEmpty ? nil : "Dest Tag: \(destinationTag)",
            contractAddress: nil,
            tokenSymbol: "XRP",
            nonce: nil,
            gasLimit: nil,
            gasPrice: nil,
            networkName: "XRP Ledger",
            isTestnet: false,
            estimatedTime: "4 sec"
        )
        pendingConfirmation = confirmation
    }
    
    private func sendTransaction() async {
        isLoading = true
        errorMessage = nil
        
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
        
        // Mock success
        let txid = "E8D..." + String(Int.random(in: 1000...9999))
        
        isLoading = false
        onSuccess(TransactionBroadcastResult(
            txid: txid,
            chainId: chain.id,
            chainName: chain.title,
            amount: amountInput,
            recipient: recipientAddress
        ))
    }
}

#Preview {
    ContentView()
}
