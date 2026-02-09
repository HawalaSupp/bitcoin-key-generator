import SwiftUI
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
    @State private var statusMessage: String?
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
    @StateObject private var sparklineCache = SparklineCache.shared
    @StateObject private var assetCache = AssetCache.shared
    private let transactionHistoryService = TransactionHistoryService.shared
    @StateObject private var navigationVM = NavigationViewModel()
    @StateObject private var securityVM = SecurityViewModel()
    @StateObject private var walletVM = WalletViewModel()
    @StateObject private var balanceService = BalanceService.shared
    @StateObject private var priceService = PriceService.shared
    private let backupService = BackupService.shared
    private let wcSigningService = WalletConnectSigningService.shared
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
    @State private var walletSearchText: String = ""
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

    
    // MARK: - NavigationSplitView sidebar selection (ROADMAP-03 E8)
    @State private var sidebarSelection: SidebarItem? = .portfolio

    enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
        case portfolio = "Portfolio"
        case activity  = "Activity"
        case discover  = "Discover"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .portfolio: return "chart.pie.fill"
            case .activity:  return "clock.arrow.circlepath"
            case .discover:  return "sparkles"
            }
        }
    }

    private var mainAppStage: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            // Sidebar (ROADMAP-03 E8: macOS NavigationSplitView)
            List(SidebarItem.allCases, selection: $sidebarSelection) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationTitle("Hawala")
            .frame(minWidth: 160, idealWidth: 180)
        } detail: {
            mainDetailContent
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        .background(HawalaTheme.Colors.background)
        .preferredColorScheme(.dark)
        // All sheet modifiers extracted to SheetCoordinator
        .sheetCoordinator(
            navigationVM: navigationVM,
            securityVM: securityVM,
            backupService: backupService,
            wcSigningService: wcSigningService,
            priceService: priceService,
            keys: $keys,
            isUnlocked: $isUnlocked,
            hasAcknowledgedSecurityNotice: $hasAcknowledgedSecurityNotice,
            storedPasscodeHash: $storedPasscodeHash,
            storedFiatCurrency: $storedFiatCurrency,
            biometricUnlockEnabled: $biometricUnlockEnabled,
            biometricForSends: $biometricForSends,
            biometricForKeyReveal: $biometricForKeyReveal,
            storedAutoLockInterval: $storedAutoLockInterval,
            onShowStatus: { msg, tone, auto in showStatus(msg, tone: tone, autoClear: auto) },
            onCopyToClipboard: copyToClipboard,
            onCopySensitiveToClipboard: copySensitiveToClipboard,
            onRevealPrivateKeys: { await revealPrivateKeysWithBiometric() },
            onHandleTransactionSuccess: handleTransactionSuccess,
            onRefreshPendingTransactions: { await refreshPendingTransactions() },
            onPresentQueuedSend: presentQueuedSendIfNeeded,
            onFinalizeEncryptedImport: { password in finalizeEncryptedImport(with: password) },
            onImportPrivateKey: { key, chain in await importPrivateKey(key, for: chain) },
            onStartFXRatesFetch: { priceService.startFXRatesFetch() },
            onFetchPrices: { Task { _ = await priceService.fetchAndStorePrices() } },
            onSetupKeyboardShortcutCallbacks: setupKeyboardShortcutCallbacks
        )
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
        // Sync sidebar selection → HawalaMainView tab
        .onChange(of: sidebarSelection) { newValue in
            if let item = newValue {
                navigationVM.sidebarTab = item.rawValue
            }
        }
    }

    private var mainDetailContent: some View {
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
                    historyError: $historyError,
                    sidebarTab: navigationVM.sidebarTab
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
                        
                        // Token / chain search bar
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14))
                                .foregroundColor(HawalaTheme.Colors.textTertiary)
                            
                            TextField("Search chains...", text: $walletSearchText)
                                .textFieldStyle(.plain)
                                .font(HawalaTheme.Typography.body)
                                .foregroundColor(HawalaTheme.Colors.textPrimary)
                                .accessibilityLabel("Search wallets")
                                .accessibilityIdentifier("wallet_search_field")
                            
                            if !walletSearchText.isEmpty {
                                Button {
                                    walletSearchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, HawalaTheme.Spacing.md)
                        .padding(.vertical, HawalaTheme.Spacing.sm)
                        .background(HawalaTheme.Colors.backgroundTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
                        
                        LazyVGrid(columns: gridColumns(for: navigationVM.viewportWidth), spacing: 14) {
                            ForEach(filteredChainInfos(keys.chainInfos)) { chain in
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

                    transactionHistoryPanel
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

    // MARK: - Dashboard Header (extracted to DashboardHeaderView)
    
    private var dashboardHeader: DashboardHeaderView {
        DashboardHeaderView(
            totalBalanceDisplay: totalBalanceDisplay,
            priceStatusLine: priceStatusLine,
            viewportWidth: navigationVM.viewportWidth,
            keys: keys,
            isGenerating: isGenerating,
            canAccessSensitiveData: canAccessSensitiveData,
            onRefreshBalances: { refreshAllBalances() },
            onSend: {
                if keys == nil {
                    Task {
                        await runGenerator()
                        await MainActor.run { openSendSheet() }
                    }
                } else {
                    openSendSheet()
                }
            },
            onReceive: {
                guard keys != nil else {
                    showStatus("Generate keys before receiving.", tone: .info)
                    return
                }
                navigationVM.showReceiveSheet = true
            },
            onViewKeys: {
                guard canAccessSensitiveData else {
                    navigationVM.showUnlockSheet = true
                    return
                }
                if keys != nil {
                    Task { await revealPrivateKeysWithBiometric() }
                } else {
                    showStatus("Generate keys before viewing private material.", tone: .info)
                }
            },
            onExport: {
                guard keys != nil else {
                    showStatus("Generate keys before exporting.", tone: .info)
                    return
                }
                navigationVM.showExportPasswordPrompt = true
            },
            onSeedPhrase: { navigationVM.showSeedPhraseSheet = true },
            onHistory: { navigationVM.showTransactionHistorySheet = true }
        )
    }
    
    private var portfolioHeader: some View {
        dashboardHeader
    }
    
    private var actionButtonsRow: some View {
        dashboardHeader.actionButtonsRow
    }

    private var totalBalanceDisplay: String {
        let result = priceService.calculatePortfolioTotal(keys: keys, balanceStates: balanceStates, balanceService: balanceService)
        guard let total = result.total, result.hasData else {
            return "—"
        }
        return priceService.formatFiatAmountInSelectedCurrency(total, storedFiatCurrency: storedFiatCurrency)
    }

    private var priceStatusLine: String {
        priceService.priceStatusLine(storedFiatCurrency: storedFiatCurrency)
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
    // MARK: - Transaction History (extracted to TransactionHistoryPanelView)

    private var transactionHistoryPanel: some View {
        TransactionHistoryPanelView(
            pendingTransactions: pendingTransactions,
            historyEntries: historyEntries,
            historyError: historyError,
            isHistoryLoading: isHistoryLoading,
            cardBackgroundColor: cardBackgroundColor,
            historySearchText: $historySearchText,
            historyFilterChain: $historyFilterChain,
            historyFilterType: $historyFilterType,
            onRefresh: { refreshTransactionHistory(force: true) },
            onSpeedUp: { navigationVM.speedUpTransaction = $0 },
            onCancel: { navigationVM.cancelTransaction = $0 },
            onSelectTransaction: { navigationVM.selectedTransactionForDetail = $0 },
            onExportCSV: {
                if let result = transactionHistoryService.exportHistoryAsCSV(entries: filteredHistoryEntries) {
                    showStatus(result.message, tone: result.tone, autoClear: result.autoClear)
                }
            }
        )
    }
    
    // MARK: - History Filtering Logic
    private var hasActiveHistoryFilters: Bool {
        !historySearchText.isEmpty || historyFilterChain != nil || historyFilterType != nil
    }
    
    private var uniqueHistoryChains: [String] {
        TransactionHistoryService.uniqueChains(from: historyEntries)
    }
    
    private var filteredHistoryEntries: [HawalaTransactionEntry] {
        TransactionHistoryService.filteredEntries(
            historyEntries,
            chain: historyFilterChain,
            type: historyFilterType,
            searchText: historySearchText
        )
    }
    
    private func showStatus(_ message: String, tone: StatusTone, autoClear: Bool = true) {
        statusTask?.cancel()
        statusTask = nil
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
                
                balanceService.startBalanceFetch(for: result)
                priceService.startPriceUpdatesIfNeeded(sparklineCache: sparklineCache)
                refreshTransactionHistory(force: true)
            }
        } catch {
            await MainActor.run {
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
    
    // MARK: - Portfolio Search
    
    /// Filters chain list based on the wallet search text
    private func filteredChainInfos(_ chains: [ChainInfo]) -> [ChainInfo] {
        guard !walletSearchText.isEmpty else { return chains }
        let query = walletSearchText.lowercased().trimmingCharacters(in: .whitespaces)
        return chains.filter { chain in
            chain.title.lowercased().contains(query) ||
            chain.subtitle.lowercased().contains(query) ||
            chain.id.lowercased().contains(query)
        }
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

    /// Reveal private keys with biometric + password authentication
    @MainActor
    private func revealPrivateKeysWithBiometric() async {
        // Step 1: Check biometric authentication if enabled
        if BiometricAuthHelper.shouldRequireBiometric(settingEnabled: biometricForKeyReveal) {
            let result = await BiometricAuthHelper.authenticate(reason: "Authenticate to view private keys")
            switch result {
            case .success:
                break // Continue to password step
            case .cancelled:
                return // User cancelled
            case .failed(let message):
                showStatus("Authentication failed: \(message)", tone: .error)
                return
            case .notAvailable:
                break // Biometric not available, continue with password only
            }
        }
        
        // Step 2: Show password prompt
        navigationVM.showPrivateKeyPasswordPrompt = true
    }

}

// BitcoinUTXO, BitcoinFeeEstimates, EthGasSpeed, EthGasEstimates, and BitcoinSendError
// are defined in Models/FeeModels.swift

// Preview disabled - use Xcode previews instead
// #Preview {
//     ContentView()
// }
