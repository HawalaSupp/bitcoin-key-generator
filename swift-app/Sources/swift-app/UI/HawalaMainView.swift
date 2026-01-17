import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Main App Shell (Modern Glass Design)
struct HawalaMainView: View {
    @Binding var keys: AllKeys?
    @Binding var selectedChain: ChainInfo?
    @Binding var balanceStates: [String: ChainBalanceState]
    @Binding var priceStates: [String: ChainPriceState]
    @StateObject var sparklineCache: SparklineCache
    
    // Privacy
    @ObservedObject private var privacyManager = PrivacyManager.shared
    
    // Settings
    @AppStorage("showBalances") private var showBalances = true
    @AppStorage("showTestnets") private var showTestnets = false
    @AppStorage("selectedBackgroundType") private var selectedBackgroundType = "none"
    
    // Computed property for hiding balances (respects both settings and privacy mode)
    private var shouldHideBalances: Bool {
        !showBalances || privacyManager.shouldHideBalances
    }
    
    // Navigation
    @State private var selectedTab: NavigationTab = .portfolio
    @State private var previousTab: NavigationTab = .portfolio
    @State private var searchText: String = ""
    @State private var isNavBarHovered: Bool = false
    @State private var hoveredTab: NavigationTab? = nil
    
    // FAB state
    @State private var isFABExpanded: Bool = false
    @State private var isRefreshing: Bool = false
    
    // Drag and drop reordering
    @State private var assetOrder: [String] = []
    @State private var draggedAsset: String?
    
    // Sheets
    @Binding var showSendPicker: Bool
    @Binding var showReceiveSheet: Bool
    @Binding var showSettingsPanel: Bool
    @Binding var showStakingSheet: Bool
    @Binding var showNotificationsSheet: Bool
    @Binding var showContactsSheet: Bool
    @Binding var showWalletConnectSheet: Bool
    
    // Actions
    var onGenerateKeys: () -> Void
    var onRefreshBalances: () -> Void
    var onRefreshHistory: () -> Void
    var selectedFiatSymbol: String
    var fxRates: [String: Double]
    var selectedFiatCurrency: String
    var isGenerating: Bool = false
    
    // Transaction history
    @Binding var historyEntries: [HawalaTransactionEntry]
    @Binding var isHistoryLoading: Bool
    @Binding var historyError: String?
    
    // Transaction detail sheet
    @State private var selectedTransaction: HawalaTransactionEntry?
    
    // Asset detail popup
    @State private var selectedAssetForDetail: AssetDetailInfo? = nil
    @State private var showAssetDetailPopup: Bool = false
    
    // Chains that support sending
    private let sendEnabledChainIDs: Set<String> = [
        "bitcoin", "bitcoin-testnet", "litecoin", "ethereum", "ethereum-sepolia", "bnb", "solana"
    ]
    
    // Computed property for background type
    private var backgroundType: AnimatedBackgroundType {
        AnimatedBackgroundType(rawValue: selectedBackgroundType) ?? .none
    }
    
    enum NavigationTab: String, CaseIterable, Comparable {
        case portfolio = "Portfolio"
        case activity = "Activity"
        case discover = "Discover"
        
        var icon: String {
            switch self {
            case .portfolio: return "chart.pie.fill"
            case .activity: return "clock.arrow.circlepath"
            case .discover: return "sparkles"
            }
        }
        
        // Whether to show text label (activity is icon-only)
        var showLabel: Bool {
            switch self {
            case .activity: return false
            default: return true
            }
        }
        
        var index: Int {
            switch self {
            case .portfolio: return 0
            case .activity: return 1
            case .discover: return 2
            }
        }
        
        static func < (lhs: NavigationTab, rhs: NavigationTab) -> Bool {
            lhs.index < rhs.index
        }
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // Background - Animated or Simple Gradient
            backgroundView
            
            // Main content (full width now)
            mainContentView
                .padding(.top, 46) // Space for floating nav bar
            
            // Traffic light buttons (close, minimize, zoom) integrated into app - positioned at very top left
            TrafficLightButtons()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 8)
                .padding(.leading, 8)
            
            // Floating liquid glass navigation bar
            liquidGlassNavBar
                .padding(.top, 12)
            
            // Hidden keyboard shortcut buttons
            keyboardShortcutHandlers
            
            // Toast notifications overlay
            ToastContainer()
            
            // Asset Detail Popup Overlay
            if showAssetDetailPopup, let assetInfo = selectedAssetForDetail {
                AssetDetailPopup(
                    assetInfo: assetInfo,
                    isPresented: $showAssetDetailPopup,
                    onSend: {
                        showAssetDetailPopup = false
                        // Find the chain and trigger send
                        if let chain = keys?.chainInfos.first(where: { $0.id == assetInfo.chain.id }) {
                            selectedChain = chain
                            showSendPicker = true
                        }
                    },
                    onReceive: {
                        showAssetDetailPopup = false
                        showReceiveSheet = true
                    }
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                    removal: .opacity.combined(with: .scale(scale: 0.98))
                ))
                .zIndex(100)
            }
        }
        .ignoresSafeArea() // Ignore safe area to push content to very top
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettingsPanel) {
            SettingsView()
                .frame(minWidth: 500, minHeight: 700)
        }
        .sheet(item: $selectedTransaction) { transaction in
            TransactionDetailSheet(transaction: transaction)
        }
    }
    
    // MARK: - Background View
    @ViewBuilder
    private var backgroundView: some View {
        ZStack {
            // Base background color
            HawalaTheme.Colors.background
            
            // Animated background based on selection
            switch backgroundType {
            case .none:
                // Simple static gradient background (optimized - no animations)
                LinearGradient(
                    colors: [
                        HawalaTheme.Colors.background,
                        HawalaTheme.Colors.backgroundSecondary.opacity(0.3),
                        HawalaTheme.Colors.background
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .aurora:
                // Exact ReactBits Aurora background
                AuroraBackground(
                    colorStops: ["#00D4FF", "#7C3AED", "#00D4FF"],
                    amplitude: 1.0,
                    blend: 0.5,
                    speed: 1.0
                )
            case .silk:
                // ReactBits Silk flowing fabric effect
                SilkBackground(
                    speed: 5.0,
                    scale: 1.0,
                    color: "#7B7481",
                    noiseIntensity: 1.5,
                    rotation: 0.0
                )
            }
        }
    }
    
    // MARK: - Keyboard Shortcut Handlers
    private var keyboardShortcutHandlers: some View {
        Group {
            // Tab navigation: Cmd+1, Cmd+2, Cmd+3
            Button("") {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    selectedTab = .portfolio
                }
            }
            .keyboardShortcut("1", modifiers: .command)
            .opacity(0)
            
            Button("") {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    selectedTab = .activity
                }
            }
            .keyboardShortcut("2", modifiers: .command)
            .opacity(0)
            
            Button("") {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    selectedTab = .discover
                }
            }
            .keyboardShortcut("3", modifiers: .command)
            .opacity(0)
            
            // Refresh: Cmd+R
            Button("") {
                triggerRefresh()
            }
            .keyboardShortcut("r", modifiers: .command)
            .opacity(0)
            
            // Settings: Cmd+,
            Button("") {
                showSettingsPanel = true
            }
            .keyboardShortcut(",", modifiers: .command)
            .opacity(0)
            
            // Send: Cmd+S (with shift to not conflict)
            Button("") {
                showSendPicker = true
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .opacity(0)
            
            // Receive: Cmd+Shift+R
            Button("") {
                showReceiveSheet = true
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .opacity(0)
        }
        .frame(width: 0, height: 0)
    }
    
    private func triggerRefresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        onRefreshBalances()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isRefreshing = false
        }
    }
    
    // MARK: - Liquid Glass Navigation Bar
    private var liquidGlassNavBar: some View {
        HStack(spacing: 8) {
            // HAWALA text branding
            Text("HAWALA")
                .font(.clashGroteskBold(size: 14))
                .foregroundColor(HawalaTheme.Colors.textPrimary)
            
            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1, height: 18)
            
            // Navigation tabs (Portfolio, Discover)
            HStack(spacing: 4) {
                ForEach(NavigationTab.allCases.filter { $0 != .activity }, id: \.self) { tab in
                    liquidGlassTab(tab)
                }
            }
            
            // Divider before right section
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1, height: 18)
            
            // Right side actions with Activity icon (no spacer - compact)
            HStack(spacing: 6) {
                // Activity tab (icon only)
                liquidGlassTab(.activity)
                
                GlassIconButton(icon: "arrow.up.arrow.down", tooltip: "Send & Receive") {
                    showSendPicker = true
                }
                
                GlassIconButton(icon: "qrcode", tooltip: "Receive Funds") {
                    showReceiveSheet = true
                }
                
                GlassIconButton(icon: "gearshape", tooltip: "Settings") {
                    showSettingsPanel = true
                }
                
                GlassIconButton(icon: "bell", badge: NotificationManager.shared.unreadCount, tooltip: "Notifications") {
                    showNotificationsSheet = true
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .fixedSize(horizontal: true, vertical: false) // Prevents stretching
        .background(
            ZStack {
                // Glassmorphism effect
                if #available(macOS 12.0, *) {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                } else {
                    Capsule()
                        .fill(Color(white: 0.15, opacity: 0.85))
                }
                
                // Simple border with gradient
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.2), .white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 6) // Single optimized shadow
    }
    
    // MARK: - Liquid Glass Tab
    private func liquidGlassTab(_ tab: NavigationTab) -> some View {
        let isSelected = selectedTab == tab
        let isHovered = hoveredTab == tab
        
        return Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                selectedTab = tab
            }
        }) {
            HStack(spacing: tab.showLabel ? 4 : 0) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11, weight: .medium))
                
                if tab.showLabel {
                    Text(tab.rawValue)
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundColor(isSelected ? HawalaTheme.Colors.textPrimary : HawalaTheme.Colors.textSecondary)
            .padding(.horizontal, tab.showLabel ? 8 : 6)
            .padding(.vertical, 4)
            .background(
                Group {
                    if isSelected {
                        Capsule()
                            .fill(Color.white.opacity(0.10))
                    } else if isHovered {
                        Capsule()
                            .fill(Color.white.opacity(0.05))
                    }
                }
            )
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(OptimizedAnimations.snappySpring, value: isHovered) // 120fps optimized
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(OptimizedAnimations.quick) { // 120fps optimized
                hoveredTab = hovering ? tab : nil
            }
        }
    }
    
    // MARK: - Glass Icon Button
    struct GlassIconButton: View {
        let icon: String
        var badge: Int? = nil
        var tooltip: String? = nil
        let action: () -> Void
        
        @State private var isHovered = false
        
        var body: some View {
            Button(action: action) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(isHovered ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
                        )
                        .scaleEffect(isHovered ? 1.1 : 1.0)
                    
                    if let badge = badge, badge > 0 {
                        Circle()
                            .fill(HawalaTheme.Colors.accent)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Text("\(min(badge, 9))")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white)
                            )
                            .offset(x: 4, y: -4)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(tooltip ?? "")
            .onHover { hovering in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isHovered = hovering
                }
            }
        }
    }
    
    // MARK: - Main Content (with Liquid Glass Transitions)
    private var mainContentView: some View {
        VStack(spacing: 0) {
            // Content based on selected tab with smooth scrolling
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    Group {
                        switch selectedTab {
                        case .portfolio:
                            portfolioView
                        case .activity:
                            activityView
                        case .discover:
                            discoverView
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity.combined(with: .move(edge: .leading))
                    ))
                    .id(selectedTab) // Force view recreation for animation
                }
                .animation(OptimizedAnimations.page, value: selectedTab) // 120fps page transition
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await refreshData()
            }
        }
    }
    
    // Async refresh handler for pull-to-refresh
    private func refreshData() async {
        // Trigger haptic feedback
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #endif
        
        // Refresh balances
        onRefreshBalances()
        
        // Wait a short time for visual feedback
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
    }
    
    // MARK: - Portfolio View (Redesigned with Bento Grid)
    private var portfolioView: some View {
        VStack(alignment: .center, spacing: HawalaTheme.Spacing.xxl) {
            // Minimalist centered balance
            minimalistBalanceDisplay
            
            // Bento grid assets
            bentoAssetsGrid
        }
        .padding(.top, HawalaTheme.Spacing.xl)
        .padding(.bottom, HawalaTheme.Spacing.xxl)
    }
    
    // MARK: - Minimalist Balance Display (No background, centered, modern font)
    private var minimalistBalanceDisplay: some View {
        VStack(alignment: .center, spacing: HawalaTheme.Spacing.sm) {
            if let keys = keys {
                let isLoading = areAllBalancesLoading(chains: keys.chainInfos)
                
                if isLoading {
                    // Simple loading state - no shimmer animation
                    Text("$0.00")
                        .font(.clashGroteskBold(size: 56))
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                        .opacity(0.5)
                } else {
                    let total = calculateTotalBalance()
                    
                    // Main balance - Clash Grotesk Bold
                    if showBalances {
                        Text(selectedFiatSymbol + formatLargeNumber(total))
                            .font(.clashGroteskBold(size: 56))
                            .monospacedDigit()
                            .foregroundColor(.white)
                    } else {
                        Text("••••••")
                            .font(.clashGroteskBold(size: 56))
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                    }
                }
            } else {
                // No keys state - minimal
                VStack(spacing: HawalaTheme.Spacing.lg) {
                    Text("$0.00")
                        .font(.clashGroteskBold(size: 56))
                        .foregroundColor(HawalaTheme.Colors.textTertiary.opacity(0.5))
                    
                    HawalaPrimaryButton("Generate Wallet", icon: "key.fill", action: onGenerateKeys)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, HawalaTheme.Spacing.xl)
    }
    
    // MARK: - Bento Assets Grid
    private var bentoAssetsGrid: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            // Section header
            HStack {
                Text("Assets")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .textCase(.uppercase)
                    .tracking(1.2)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isRefreshing = true
                    }
                    onRefreshBalances()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { isRefreshing = false }
                    }
                }) {
                    HStack(spacing: 4) {
                        if isRefreshing {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)
            }
            .padding(.horizontal, HawalaTheme.Spacing.xl)
            
            if let keys = keys {
                let chains = getOrderedChains(keys.chainInfos)
                
                // Bento grid layout
                LazyVGrid(columns: bentGridColumns, spacing: HawalaTheme.Spacing.md) {
                    ForEach(Array(chains.enumerated()), id: \.element.id) { index, chain in
                        BentoAssetCard(
                            chain: chain,
                            chainSymbol: chainSymbol(for: chain.id),
                            chainColor: HawalaTheme.Colors.forChain(chain.id),
                            balance: formatBalance(for: chain.id),
                            fiatValue: formatFiatValue(for: chain.id),
                            sparklineData: sparklineCache.sparklines[chain.id] ?? [],
                            hideBalance: shouldHideBalances,
                            onTap: {
                                // Get the current price from priceStates
                                let currentPrice: Double = {
                                    if let priceState = priceStates[chain.id] {
                                        switch priceState {
                                        case .loaded(let priceStr, _):
                                            // Remove currency symbols and commas for parsing
                                            let cleanedPrice = priceStr
                                                .replacingOccurrences(of: "$", with: "")
                                                .replacingOccurrences(of: ",", with: "")
                                                .trimmingCharacters(in: .whitespaces)
                                            print("💰 [Card Tap] Chain: \(chain.id), raw: \(priceStr), cleaned: \(cleanedPrice)")
                                            return Double(cleanedPrice) ?? 0
                                        case .refreshing(let previous, _), .stale(let previous, _, _):
                                            let cleanedPrice = previous
                                                .replacingOccurrences(of: "$", with: "")
                                                .replacingOccurrences(of: ",", with: "")
                                                .trimmingCharacters(in: .whitespaces)
                                            return Double(cleanedPrice) ?? 0
                                        default:
                                            return 0
                                        }
                                    }
                                    print("💰 [Card Tap] Chain: \(chain.id), NO priceState found!")
                                    return 0
                                }()
                                
                                // Create asset detail info
                                selectedAssetForDetail = AssetDetailInfo(
                                    chain: chain,
                                    chainSymbol: chainSymbol(for: chain.id),
                                    balance: formatBalance(for: chain.id),
                                    rawBalance: getRawBalance(for: chain.id),
                                    fiatValue: formatFiatValue(for: chain.id),
                                    currentPrice: currentPrice,
                                    sparklineData: sparklineCache.sparklines[chain.id] ?? [],
                                    canSend: sendEnabledChainIDs.contains(chain.id)
                                )
                                
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                    showAssetDetailPopup = true
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, HawalaTheme.Spacing.xl)
            } else {
                BentoEmptyState(onGenerate: onGenerateKeys, isLoading: isGenerating)
                    .padding(.horizontal, HawalaTheme.Spacing.xl)
            }
        }
    }
    
    // Bento grid columns - adaptive based on content
    private var bentGridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: HawalaTheme.Spacing.md),
            GridItem(.flexible(), spacing: HawalaTheme.Spacing.md)
        ]
    }
    
    // MARK: - Total Balance Card (Legacy - kept for reference)
    private var totalBalanceCard: some View {
        VStack(alignment: .center, spacing: HawalaTheme.Spacing.md) {
            Text("Total Balance")
                .font(HawalaTheme.Typography.bodySmall)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
            
            if let keys = keys {
                let isLoading = areAllBalancesLoading(chains: keys.chainInfos)
                
                if isLoading {
                    // Skeleton loading for balance
                    SkeletonShape(width: 200, height: 48, cornerRadius: 8)
                    SkeletonShape(width: 100, height: 20, cornerRadius: 4)
                } else {
                    let total = calculateTotalBalance()
                    
                    // Animated balance counter
                    AnimatedCounter(value: total, prefix: selectedFiatSymbol, duration: 1.0, hideBalance: shouldHideBalances)
                    
                    // P&L indicator (simulated for now - would need purchase history)
                    if !shouldHideBalances {
                        ProfitLossIndicator(
                            currentValue: total,
                            purchaseValue: total * 0.95, // Simulated 5% gain
                            currencySymbol: selectedFiatSymbol,
                            size: .medium
                        )
                    }
                }
            } else {
                // No keys state
                VStack(alignment: .center, spacing: HawalaTheme.Spacing.md) {
                    Text("--")
                        .font(HawalaTheme.Typography.display(48))
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                    
                    Text("Generate keys to get started")
                        .font(HawalaTheme.Typography.body)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                    
                    HawalaPrimaryButton(isGenerating ? "Generating..." : "Generate Wallet", icon: isGenerating ? nil : "key.fill", isLoading: isGenerating, action: onGenerateKeys)
                        .padding(.top, HawalaTheme.Spacing.sm)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(HawalaTheme.Spacing.xl)
        .glassCard(cornerRadius: HawalaTheme.Radius.xl, opacity: 0.1, blurRadius: 25)
    }
    
    // MARK: - Quick Stats Row
    private var quickStatsRow: some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            HawalaStatCard(
                title: "24h Volume",
                value: "$12.4K",
                change: "+5.2%",
                isPositive: true,
                icon: "chart.bar.fill"
            )
            
            HawalaStatCard(
                title: "Assets",
                value: keys != nil ? "\(keys!.chainInfos.count)" : "0",
                change: nil,
                isPositive: nil,
                icon: "bitcoinsign.circle"
            )
            
            HawalaStatCard(
                title: "Transactions",
                value: "24",
                change: nil,
                isPositive: nil,
                icon: "arrow.left.arrow.right"
            )
        }
    }
    
    // MARK: - Assets Section
    private var assetsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header with animated refresh
            HStack {
                Text("Assets")
                    .font(HawalaTheme.Typography.h3)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                // Drag hint
                Text("• Drag to reorder")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                
                Spacer()
                
                // Refresh button with indicator
                Button(action: {
                    withAnimation {
                        isRefreshing = true
                    }
                    onRefreshBalances()
                    ToastManager.shared.info("Refreshing", message: "Fetching latest balances...")
                    // Simulate refresh completion
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            isRefreshing = false
                        }
                        ToastManager.shared.success("Updated", message: "Balances refreshed")
                    }
                }) {
                    HStack(spacing: 4) {
                        RefreshIndicator(isRefreshing: $isRefreshing)
                        
                        Text(isRefreshing ? "Refreshing..." : "Refresh")
                            .font(HawalaTheme.Typography.caption)
                    }
                    .foregroundColor(HawalaTheme.Colors.accent)
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)
            }
            .padding(.horizontal, HawalaTheme.Spacing.xl)
            .padding(.bottom, HawalaTheme.Spacing.md)
            
            if let keys = keys {
                let chains = getOrderedChains(keys.chainInfos)
                let isInitialLoading = areAllBalancesLoading(chains: chains)
                
                if isInitialLoading {
                    // Show skeleton loading state
                    VStack(spacing: 0) {
                        SkeletonAssetList(count: min(chains.count, 5))
                    }
                    .hawalaCard(padding: 0)
                    .padding(.horizontal, HawalaTheme.Spacing.xl)
                } else {
                    VStack(spacing: 0) {
                        ForEach(chains) { chain in
                            let balanceState = balanceStates[chain.id]
                            let isLoading = isBalanceLoading(balanceState)
                            
                            if isLoading && !isRefreshing {
                                // Individual row skeleton
                                SkeletonAssetRow()
                            } else {
                                DraggableAssetRow(
                                    chain: chain,
                                    chainSymbol: chainSymbol(for: chain.id),
                                    chainColor: HawalaTheme.Colors.forChain(chain.id),
                                    balance: formatBalance(for: chain.id),
                                    fiatValue: formatFiatValue(for: chain.id),
                                    sparklineData: sparklineCache.sparklines[chain.id] ?? [],
                                    isSelected: selectedChain?.id == chain.id,
                                    isDragging: draggedAsset == chain.id,
                                    hideBalance: shouldHideBalances,
                                    onSelect: {
                                        withAnimation(HawalaTheme.Animation.fast) {
                                            selectedChain = chain
                                        }
                                    },
                                    onDragStarted: {
                                        draggedAsset = chain.id
                                    },
                                    onDragEnded: {
                                        draggedAsset = nil
                                    },
                                    onDropTarget: { targetId in
                                        reorderAsset(draggedId: chain.id, targetId: targetId)
                                    }
                                )
                            }
                            
                            if chain.id != chains.last?.id {
                                Divider()
                                    .background(HawalaTheme.Colors.divider)
                                    .padding(.horizontal, HawalaTheme.Spacing.lg)
                            }
                        }
                    }
                    .hawalaCard(padding: 0)
                    .padding(.horizontal, HawalaTheme.Spacing.xl)
                }
            } else {
                HawalaEmptyState(
                    icon: "wallet.pass",
                    title: "No Wallet",
                    message: "Generate a new wallet to view your assets and start transacting.",
                    actionTitle: isGenerating ? "Generating..." : "Generate Wallet",
                    isLoading: isGenerating,
                    action: onGenerateKeys
                )
                .frame(maxWidth: .infinity)
                .hawalaCard()
                .padding(.horizontal, HawalaTheme.Spacing.xl)
            }
        }
        .onAppear {
            if let keys = keys {
                initializeAssetOrder(from: keys.chainInfos)
            }
        }
    }
    
    // Helper to check if balance is loading
    private func isBalanceLoading(_ state: ChainBalanceState?) -> Bool {
        guard let state = state else { return true }
        switch state {
        case .idle, .loading:
            return true
        default:
            return false
        }
    }
    
    // Helper to check if all balances are still in initial loading
    private func areAllBalancesLoading(chains: [ChainInfo]) -> Bool {
        let loadedCount = chains.filter { chain in
            if let state = balanceStates[chain.id] {
                switch state {
                case .loaded, .stale, .failed, .refreshing:
                    return true
                default:
                    return false
                }
            }
            return false
        }.count
        return loadedCount == 0 && !chains.isEmpty
    }
    
    // MARK: - Asset Ordering Helpers
    private func initializeAssetOrder(from chains: [ChainInfo]) {
        if assetOrder.isEmpty {
            assetOrder = chains.map { $0.id }
        }
    }
    
    private func getOrderedChains(_ chains: [ChainInfo]) -> [ChainInfo] {
        let filtered = filterChains(chains)
        if assetOrder.isEmpty {
            return filtered
        }
        return filtered.sorted { chain1, chain2 in
            let index1 = assetOrder.firstIndex(of: chain1.id) ?? Int.max
            let index2 = assetOrder.firstIndex(of: chain2.id) ?? Int.max
            return index1 < index2
        }
    }
    
    private func reorderAsset(draggedId: String, targetId: String) {
        guard draggedId != targetId,
              let fromIndex = assetOrder.firstIndex(of: draggedId),
              let toIndex = assetOrder.firstIndex(of: targetId) else { return }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            assetOrder.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }
    
    // MARK: - Accounts View
    private var accountsView: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.xl) {
            Text("Accounts")
                .font(HawalaTheme.Typography.h2)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
                .padding(.horizontal, HawalaTheme.Spacing.xl)
            
            if let keys = keys {
                // Account cards for each chain
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: HawalaTheme.Spacing.md),
                    GridItem(.flexible(), spacing: HawalaTheme.Spacing.md)
                ], spacing: HawalaTheme.Spacing.md) {
                    ForEach(keys.chainInfos) { chain in
                        AccountCard(
                            chain: chain,
                            balance: formatBalance(for: chain.id),
                            fiatValue: formatFiatValue(for: chain.id),
                            isSelected: selectedChain?.id == chain.id,
                            hideBalance: shouldHideBalances
                        ) {
                            selectedChain = chain
                        }
                    }
                }
                .padding(.horizontal, HawalaTheme.Spacing.xl)
            } else {
                HawalaEmptyState(
                    icon: "creditcard",
                    title: "No Accounts",
                    message: "Generate a wallet to create accounts for multiple chains.",
                    actionTitle: "Get Started",
                    action: onGenerateKeys
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal, HawalaTheme.Spacing.xl)
            }
        }
        .padding(.vertical, HawalaTheme.Spacing.lg)
    }
    
    // MARK: - Activity View
    private var activityView: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.xl) {
            HStack {
                Text("Recent Activity")
                    .font(HawalaTheme.Typography.h2)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Spacer()
                
                if isHistoryLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                
                Button {
                    onRefreshHistory()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.body)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(isHistoryLoading)
            }
            .padding(.horizontal, HawalaTheme.Spacing.xl)
            
            // Transaction list or empty/error state
            VStack(spacing: 0) {
                if let error = historyError {
                    // Error state
                    VStack(spacing: HawalaTheme.Spacing.md) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundColor(HawalaTheme.Colors.warning)
                        
                        Text("Unable to load transactions")
                            .font(HawalaTheme.Typography.body)
                            .foregroundColor(HawalaTheme.Colors.textPrimary)
                        
                        Text(error)
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                        
                        Button("Try Again") {
                            onRefreshHistory()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, HawalaTheme.Spacing.xxl)
                } else if isHistoryLoading && historyEntries.isEmpty {
                    // Loading state
                    VStack(spacing: HawalaTheme.Spacing.md) {
                        ProgressView()
                            .controlSize(.large)
                        
                        Text("Loading transactions...")
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, HawalaTheme.Spacing.xxl)
                } else if historyEntries.isEmpty {
                    // Empty state with illustration
                    EmptyStateIllustration(
                        icon: "clock.arrow.circlepath",
                        title: "No transactions yet",
                        subtitle: "Your activity will appear here once you make your first transaction.",
                        actionTitle: "Send Crypto",
                        action: { showSendPicker = true }
                    )
                    .padding(.vertical, HawalaTheme.Spacing.xxl)
                } else {
                    // Real transaction list with fixed heights for performance
                    ForEach(historyEntries.prefix(10)) { entry in
                        Button {
                            selectedTransaction = entry
                        } label: {
                            HawalaTransactionRow(
                                type: transactionType(from: entry.type),
                                amount: formatAmountOnly(entry.amountDisplay),
                                symbol: symbolFromAsset(entry.asset),
                                fiatValue: "", // Fiat value not available from API
                                date: entry.timestamp,
                                status: transactionStatus(from: entry.status),
                                counterparty: entry.counterparty ?? shortenHash(entry.txHash)
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(height: 56) // Fixed height for cell reuse optimization
                        
                        if entry.id != historyEntries.prefix(10).last?.id {
                            Divider()
                                .background(HawalaTheme.Colors.divider)
                                .padding(.horizontal, HawalaTheme.Spacing.md)
                        }
                    }
                }
            }
            .padding(HawalaTheme.Spacing.sm)
            .frostedGlass(cornerRadius: HawalaTheme.Radius.lg, intensity: 0.2)
            .padding(.horizontal, HawalaTheme.Spacing.xl)
        }
        .padding(.vertical, HawalaTheme.Spacing.lg)
    }
    
    // MARK: - Transaction Helpers
    
    private func transactionType(from typeString: String) -> HawalaTransactionRow.TransactionType {
        switch typeString.lowercased() {
        case "receive": return .receive
        case "send": return .send
        case "swap": return .swap
        default: return .receive
        }
    }
    
    private func transactionStatus(from statusString: String) -> HawalaTransactionRow.TxStatus {
        switch statusString.lowercased() {
        case "confirmed": return .confirmed
        case "pending": return .pending
        case "processing": return .processing
        case "failed": return .failed
        default: return .pending
        }
    }
    
    private func formatAmountOnly(_ display: String) -> String {
        // Remove +/- prefix and symbol to get just the number
        var result = display
        if result.hasPrefix("+") || result.hasPrefix("-") {
            result = String(result.dropFirst())
        }
        // Remove trailing symbol (BTC, ETH, etc.)
        let parts = result.split(separator: " ")
        if let firstPart = parts.first {
            return String(firstPart)
        }
        return result
    }
    
    private func symbolFromAsset(_ asset: String) -> String {
        switch asset.lowercased() {
        case "bitcoin": return "BTC"
        case "bitcoin testnet": return "tBTC"
        case "litecoin": return "LTC"
        case "ethereum": return "ETH"
        case "ethereum sepolia": return "ETH"
        case "bnb chain", "bnb": return "BNB"
        case "solana": return "SOL"
        case "xrp ledger", "xrp": return "XRP"
        default: return asset
        }
    }
    
    private func shortenHash(_ hash: String?) -> String? {
        guard let hash = hash, hash.count > 12 else { return hash }
        return "\(hash.prefix(6))...\(hash.suffix(4))"
    }
    
    // MARK: - Discover View
    private var discoverView: some View {
        VStack(spacing: HawalaTheme.Spacing.xl) {
            Text("Discover")
                .font(HawalaTheme.Typography.h2)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, HawalaTheme.Spacing.xl)
            
            // Feature cards
            VStack(spacing: HawalaTheme.Spacing.md) {
                DiscoverCard(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Staking",
                    description: "Earn rewards by staking your assets",
                    color: HawalaTheme.Colors.accent
                ) {
                    showStakingSheet = true
                }
                
                DiscoverCard(
                    icon: "person.3.fill",
                    title: "Multisig Wallets",
                    description: "Enhanced security with multi-signature",
                    color: HawalaTheme.Colors.info
                ) {
                    // showMultisigSheet = true
                }
                
                DiscoverCard(
                    icon: "cpu",
                    title: "Hardware Wallet",
                    description: "Connect Ledger or Trezor devices",
                    color: HawalaTheme.Colors.success
                ) {
                    // showHardwareWalletSheet = true
                }
                
                DiscoverCard(
                    icon: "link.circle.fill",
                    title: "WalletConnect",
                    description: "Connect to dApps securely",
                    color: HawalaTheme.Colors.info
                ) {
                    showWalletConnectSheet = true
                }
            }
            .padding(.horizontal, HawalaTheme.Spacing.xl)
            
            Spacer()
        }
        .padding(.vertical, HawalaTheme.Spacing.lg)
    }
    
    // MARK: - Helpers
    
    private func calculateTotalBalance() -> Double {
        guard let keys = keys else { return 0 }
        var total: Double = 0
        
        for chain in keys.chainInfos {
            if let state = balanceStates[chain.id], case .loaded(let balanceStr, _) = state {
                if let balance = Double(balanceStr),
                   let priceState = priceStates[chain.id], 
                   case .loaded(let priceStr, _) = priceState,
                   let price = Double(priceStr) {
                    total += balance * price * fxMultiplier
                }
            }
        }
        
        return total
    }
    
    private var fxMultiplier: Double {
        fxRates[selectedFiatCurrency] ?? 1.0
    }
    
    private func formatLargeNumber(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.2fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.2fK", value / 1_000)
        } else {
            return String(format: "%.2f", value)
        }
    }
    
    private func filterChains(_ chains: [ChainInfo]) -> [ChainInfo] {
        // Testnet chain IDs to filter out when showTestnets is false
        let testnetChainIds = ["bitcoin-testnet", "ethereum-sepolia"]
        
        var filtered = chains
        
        // Filter out testnets if toggle is off
        if !showTestnets {
            filtered = filtered.filter { !testnetChainIds.contains($0.id) }
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { 
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.id.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return filtered
    }
    
    private func chainSymbol(for chainId: String) -> String {
        switch chainId {
        case "bitcoin", "bitcoin-testnet": return "BTC"
        case "ethereum", "ethereum-sepolia": return "ETH"
        case "litecoin": return "LTC"
        case "solana": return "SOL"
        case "xrp": return "XRP"
        case "bnb": return "BNB"
        case "monero": return "XMR"
        default: return chainId.uppercased()
        }
    }
    
    private func formatBalance(for chainId: String) -> String {
        if let state = balanceStates[chainId] {
            switch state {
            case .idle, .loading:
                return "..."
            case .loaded(let balance, _):
                if let val = Double(balance) {
                    return String(format: "%.6f", val)
                }
                return balance
            case .refreshing(let previous, _), .stale(let previous, _, _):
                return previous
            case .failed:
                return "Error"
            }
        }
        return "0.000000"
    }
    
    private func getRawBalance(for chainId: String) -> Double {
        if let state = balanceStates[chainId] {
            switch state {
            case .loaded(let balance, _):
                return Double(balance) ?? 0
            case .refreshing(let previous, _), .stale(let previous, _, _):
                return Double(previous) ?? 0
            default:
                return 0
            }
        }
        return 0
    }
    
    private func formatFiatValue(for chainId: String) -> String {
        guard let balanceState = balanceStates[chainId],
              case .loaded(let balanceStr, _) = balanceState,
              let balance = Double(balanceStr),
              let priceState = priceStates[chainId],
              case .loaded(let priceStr, _) = priceState,
              let price = Double(priceStr) else {
            return "\(selectedFiatSymbol)0.00"
        }
        
        let value = balance * price * fxMultiplier
        return "\(selectedFiatSymbol)\(String(format: "%.2f", value))"
    }
}

// MARK: - Account Card
struct AccountCard: View {
    let chain: ChainInfo
    let balance: String
    let fiatValue: String
    let isSelected: Bool
    var hideBalance: Bool = false
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(HawalaTheme.Colors.forChain(chain.id).opacity(0.15))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: chain.iconName)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(HawalaTheme.Colors.forChain(chain.id))
                    }
                    
                    Spacer()
                    
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14))
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(chain.title)
                        .font(HawalaTheme.Typography.h4)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    
                    Text(hideBalance ? "•••••" : balance)
                        .font(HawalaTheme.Typography.mono)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                    
                    Text(hideBalance ? "•••••" : fiatValue)
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
            }
            .padding(HawalaTheme.Spacing.lg)
            .frame(height: 160)
            .background(isSelected ? HawalaTheme.Colors.accentSubtle : (isHovered ? HawalaTheme.Colors.backgroundHover : HawalaTheme.Colors.backgroundSecondary))
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous)
                    .strokeBorder(isSelected ? HawalaTheme.Colors.accent.opacity(0.5) : HawalaTheme.Colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(HawalaTheme.Animation.fast) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Discover Card
struct DiscoverCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: HawalaTheme.Spacing.lg) {
                ZStack {
                    RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous)
                        .fill(color.opacity(0.15))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(color)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(HawalaTheme.Typography.h4)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    
                    Text(description)
                        .font(HawalaTheme.Typography.bodySmall)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            .padding(HawalaTheme.Spacing.lg)
            .frostedGlass(cornerRadius: HawalaTheme.Radius.lg, intensity: isHovered ? 0.25 : 0.15)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering // No animation - instant response
        }
    }
}

// MARK: - Bento Asset Card (Grid Cell) - Clickable
struct BentoAssetCard: View {
    let chain: ChainInfo
    let chainSymbol: String
    let chainColor: Color
    let balance: String
    let fiatValue: String
    let sparklineData: [Double]
    var hideBalance: Bool = false
    var onTap: (() -> Void)? = nil
    
    @State private var isPressed: Bool = false
    @State private var isHovered: Bool = false
    
    // Price change percentage from sparkline
    private var priceChange: Double {
        guard sparklineData.count >= 2 else { return 0 }
        let first = sparklineData.first ?? 1
        let last = sparklineData.last ?? 1
        guard first != 0 else { return 0 }
        return ((last - first) / first) * 100
    }
    
    var body: some View {
        // Clickable card with press animation
        VStack(alignment: .leading, spacing: 0) {
            // Header: Name + Price change (no icon)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(chain.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    
                    Text(chainSymbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
                
                Spacer()
                
                // Price change badge - monochrome with subtle tint
                if priceChange != 0 {
                    HStack(spacing: 2) {
                        Image(systemName: priceChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 9, weight: .bold))
                        Text(String(format: "%.1f%%", abs(priceChange)))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(Color.white.opacity(priceChange >= 0 ? 0.6 : 0.45))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                    )
                }
            }
            
            Spacer()
            
            // Sparkline chart - use Canvas for best performance
            if !sparklineData.isEmpty {
                BentoSparklineChart(data: sparklineData, color: .white, isPositive: priceChange >= 0)
                    .frame(height: 50)
                    .padding(.vertical, 8)
            } else {
                // Placeholder for no data
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.03))
                    .frame(height: 50)
                    .padding(.vertical, 8)
            }
            
            Spacer()
            
            // Footer: Balance & Fiat value
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if hideBalance {
                        Text("••••••")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(HawalaTheme.Colors.textPrimary)
                    } else {
                        Text(fiatValue)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(HawalaTheme.Colors.textPrimary)
                        
                        Text("\(balance) \(chainSymbol)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                    }
                }
                
                Spacer()
            }
        }
        .padding(14)
        .frame(height: 175)
        .background(
            // Professional dark gray semi-transparent background with hover effect
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.14).opacity(isHovered ? 0.95 : 0.85))
        )
        .overlay(
            // Border with gradient - brighter on hover
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(isHovered ? 0.15 : 0.08),
                            .white.opacity(isHovered ? 0.05 : 0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(isHovered ? 0.25 : 0.15), radius: isHovered ? 12 : 8, x: 0, y: isHovered ? 6 : 4)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            // Press animation
            withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                    isPressed = false
                }
                onTap?()
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg))
        // GPU-accelerated compositing for smooth scrolling
        .drawingGroup(opaque: false)
    }
}

// MARK: - Shimmer Modifier (Optimized - simple opacity pulse, no GeometryReader)
struct ShimmerModifier: ViewModifier {
    @State private var opacity: Double = 0.4
    
    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .onAppear {
                // Simple opacity pulse - very lightweight
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    opacity = 1.0
                }
            }
    }
}

// MARK: - Bento Empty State
struct BentoEmptyState: View {
    let onGenerate: () -> Void
    var isLoading: Bool = false
    
    var body: some View {
        VStack(spacing: HawalaTheme.Spacing.xl) {
            ZStack {
                Circle()
                    .fill(HawalaTheme.Colors.accent.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "wallet.pass")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(HawalaTheme.Colors.accent)
            }
            
            VStack(spacing: HawalaTheme.Spacing.sm) {
                Text("No Wallets Yet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text("Generate your multi-chain wallet to get started")
                    .font(.system(size: 14))
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            HawalaPrimaryButton(isLoading ? "Generating..." : "Generate Wallet", icon: isLoading ? nil : "key.fill", isLoading: isLoading, action: onGenerate)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, HawalaTheme.Spacing.xxl)
    }
}

// MARK: - Bento Sparkline Chart (Optimized with drawingGroup)
struct BentoSparklineChart: View {
    let data: [Double]
    let color: Color
    let isPositive: Bool
    
    var body: some View {
        Canvas { context, size in
            guard data.count > 1 else { return }
            
            let width = size.width
            let height = size.height
            
            let minVal = data.min() ?? 0
            let maxVal = data.max() ?? 1
            let range = max(maxVal - minVal, 0.0001) // Prevent division by zero
            
            // Create the line path
            var linePath = Path()
            
            for (index, value) in data.enumerated() {
                let x = width * CGFloat(index) / CGFloat(data.count - 1)
                let y = height - (height * CGFloat((value - minVal) / range))
                
                if index == 0 {
                    linePath.move(to: CGPoint(x: x, y: y))
                } else {
                    linePath.addLine(to: CGPoint(x: x, y: y))
                }
            }
            
            // Draw the line
            context.stroke(
                linePath,
                with: .color(Color.white.opacity(0.25)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
            
            // Create fill path
            var fillPath = linePath
            fillPath.addLine(to: CGPoint(x: width, y: height))
            fillPath.addLine(to: CGPoint(x: 0, y: height))
            fillPath.closeSubpath()
            
            // Draw gradient fill
            context.fill(
                fillPath,
                with: .linearGradient(
                    Gradient(colors: [Color.white.opacity(0.04), Color.white.opacity(0.0)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: height)
                )
            )
        }
        .drawingGroup() // GPU acceleration for Canvas rendering - improves 120fps performance
    }
}

// MARK: - Traffic Light Buttons (Close, Minimize, Zoom)
struct TrafficLightButtons: View {
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Close button (red)
            TrafficLightButton(color: Color(red: 1.0, green: 0.38, blue: 0.35), icon: "xmark") {
                NSApplication.shared.terminate(nil)
            }
            
            // Minimize button (yellow)
            TrafficLightButton(color: Color(red: 1.0, green: 0.75, blue: 0.25), icon: "minus") {
                NSApplication.shared.windows.first?.miniaturize(nil)
            }
            
            // Zoom button (green)
            TrafficLightButton(color: Color(red: 0.35, green: 0.78, blue: 0.35), icon: "plus") {
                NSApplication.shared.windows.first?.zoom(nil)
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .environment(\.trafficLightHovered, isHovered)
    }
}

struct TrafficLightButton: View {
    let color: Color
    let icon: String
    let action: () -> Void
    
    @Environment(\.trafficLightHovered) var isGroupHovered
    @State private var isButtonHovered = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                
                if isGroupHovered {
                    Image(systemName: icon)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(Color.black.opacity(0.6))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isButtonHovered = hovering
        }
    }
}

// Environment key for traffic light hover state
private struct TrafficLightHoveredKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var trafficLightHovered: Bool {
        get { self[TrafficLightHoveredKey.self] }
        set { self[TrafficLightHoveredKey.self] = newValue }
    }
}

// MARK: - Empty State Illustration Component
struct EmptyStateIllustration: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    
    @State private var iconScale: CGFloat = 0.8
    @State private var iconOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Animated icon with floating effect
            ZStack {
                // Glow background (reduced blur for performance)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                HawalaTheme.Colors.accent.opacity(0.15),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 50
                        )
                    )
                    .frame(width: 100, height: 100)
                    .blur(radius: 6) // Reduced from 10 for GPU performance
                
                // Icon container
                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [HawalaTheme.Colors.accent, HawalaTheme.Colors.accent.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .scaleEffect(iconScale)
            .opacity(iconOpacity)
            .modifier(FloatingEffect())
            
            // Text content
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .opacity(textOpacity)
            
            // Optional action button
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text(actionTitle)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [HawalaTheme.Colors.accent, HawalaTheme.Colors.accent.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .scaleEffect(isHovered ? 1.05 : 1.0)
                    .shadow(color: HawalaTheme.Colors.accent.opacity(isHovered ? 0.4 : 0.2), radius: isHovered ? 12 : 8, y: 4)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isHovered = hovering
                    }
                }
                .opacity(textOpacity)
            }
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                textOpacity = 1.0
            }
        }
    }
}

// Floating animation effect modifier
struct FloatingEffect: ViewModifier {
    @State private var offset: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .onAppear {
                withAnimation(
                    Animation
                        .easeInOut(duration: 2.0)
                        .repeatForever(autoreverses: true)
                ) {
                    offset = -6
                }
            }
    }
}

// MARK: - Error Shake Modifier
struct ErrorShakeModifier: ViewModifier {
    @Binding var shake: Bool
    
    func body(content: Content) -> some View {
        content
            .offset(x: shake ? -10 : 0)
            .animation(
                // 120fps optimized shake - tighter spring for snappier feedback
                shake ? Animation.interpolatingSpring(stiffness: 400, damping: 12).repeatCount(3) : .default,
                value: shake
            )
            .onChange(of: shake) { newValue in
                if newValue {
                    // Haptic feedback for error
                    #if os(macOS)
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                    #endif
                    
                    // Reset after animation - faster reset for 120fps
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        shake = false
                    }
                }
            }
    }
}

extension View {
    func errorShake(_ shake: Binding<Bool>) -> some View {
        modifier(ErrorShakeModifier(shake: shake))
    }
}

// MARK: - Error Toast Badge
struct ErrorToastBadge: View {
    let message: String
    @State private var opacity: Double = 0
    @State private var offset: CGFloat = -20
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
            
            Text(message)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(HawalaTheme.Colors.error)
                .shadow(color: HawalaTheme.Colors.error.opacity(0.4), radius: 10, y: 4)
        )
        .opacity(opacity)
        .offset(y: offset)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                opacity = 1.0
                offset = 0
            }
            
            // Auto dismiss after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeOut(duration: 0.3)) {
                    opacity = 0
                    offset = -20
                }
            }
        }
    }
}

// MARK: - Haptic Feedback Helper
struct HapticFeedback {
    static func light() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #endif
    }
    
    static func medium() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        #endif
    }
    
    static func heavy() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #endif
    }
    
    static func success() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        #endif
    }
    
    static func error() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        #endif
    }
    
    static func selection() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #endif
    }
}

// MARK: - Animated Number Display
struct AnimatedNumberDisplay: View {
    let value: Double
    let format: String
    let prefix: String
    
    @State private var displayValue: Double = 0
    
    init(_ value: Double, format: String = "%.2f", prefix: String = "$") {
        self.value = value
        self.format = format
        self.prefix = prefix
    }
    
    var body: some View {
        Text(prefix + String(format: format, displayValue))
            .monospacedDigit()
            .onAppear {
                animateValue()
            }
            .onChange(of: value) { _ in
                animateValue()
            }
    }
    
    private func animateValue() {
        let startValue = displayValue
        let endValue = value
        let duration: Double = 0.6
        let steps = 30
        let stepDuration = duration / Double(steps)
        
        for step in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(step)) {
                let progress = Double(step) / Double(steps)
                let eased = 1 - pow(1 - progress, 3) // Ease out cubic
                displayValue = startValue + (endValue - startValue) * eased
            }
        }
    }
}

// MARK: - Parallax Scroll Effect
struct ParallaxScrollModifier: ViewModifier {
    let speed: CGFloat
    @State private var offset: CGFloat = 0
    
    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content
                .offset(y: calculateOffset(geometry))
        }
    }
    
    private func calculateOffset(_ geometry: GeometryProxy) -> CGFloat {
        let minY = geometry.frame(in: .global).minY
        return minY > 0 ? -minY * speed : 0
    }
}

extension View {
    func parallaxEffect(speed: CGFloat = 0.5) -> some View {
        modifier(ParallaxScrollModifier(speed: speed))
    }
}

// MARK: - Scroll Offset Preference Key
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Scroll View with Offset Tracking
struct ScrollViewWithOffset<Content: View>: View {
    let axes: Axis.Set
    let showsIndicators: Bool
    let onOffsetChange: (CGFloat) -> Void
    let content: () -> Content
    
    init(
        _ axes: Axis.Set = .vertical,
        showsIndicators: Bool = true,
        onOffsetChange: @escaping (CGFloat) -> Void = { _ in },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.onOffsetChange = onOffsetChange
        self.content = content
    }
    
    var body: some View {
        ScrollView(axes, showsIndicators: showsIndicators) {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ScrollOffsetPreferenceKey.self,
                    value: geometry.frame(in: .named("scrollView")).minY
                )
            }
            .frame(height: 0)
            
            content()
        }
        .coordinateSpace(name: "scrollView")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self, perform: onOffsetChange)
    }
}

// MARK: - Staggered Animation Modifier
struct StaggeredAnimation: ViewModifier {
    let index: Int
    let totalCount: Int
    @State private var appeared = false
    
    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .onAppear {
                let delay = Double(index) * 0.05
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8).delay(delay)) {
                    appeared = true
                }
            }
    }
}

extension View {
    func staggeredAppearance(index: Int, total: Int = 10) -> some View {
        modifier(StaggeredAnimation(index: index, totalCount: total))
    }
}

// MARK: - Bounce Effect on Press (120fps optimized)
struct BouncePress: ViewModifier {
    @State private var isPressed = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(OptimizedAnimations.snappySpring, value: isPressed) // 120fps optimized
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            HapticFeedback.light()
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                    }
            )
    }
}

extension View {
    func bounceOnPress() -> some View {
        modifier(BouncePress())
    }
}

// MARK: - Glow Effect Modifier (Optimized for 120fps - single shadow)
struct GlowEffect: ViewModifier {
    let color: Color
    let radius: CGFloat
    let isActive: Bool
    
    func body(content: Content) -> some View {
        content
            // Single shadow instead of double for better GPU performance
            .shadow(color: isActive ? color.opacity(0.45) : Color.clear, radius: radius * 1.5)
            .animation(OptimizedAnimations.standard, value: isActive) // 120fps optimized
    }
}

extension View {
    func glowEffect(color: Color, radius: CGFloat = 10, isActive: Bool = true) -> some View {
        modifier(GlowEffect(color: color, radius: radius, isActive: isActive))
    }
}

// MARK: - Asset Detail Info Model
struct AssetDetailInfo: Identifiable, Equatable {
    let id = UUID()
    let chain: ChainInfo
    let chainSymbol: String
    let balance: String
    let rawBalance: Double
    let fiatValue: String
    let currentPrice: Double
    let sparklineData: [Double]
    let canSend: Bool
    
    static func == (lhs: AssetDetailInfo, rhs: AssetDetailInfo) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Asset Detail Popup (Premium Apple-Style Liquid Glass)
struct AssetDetailPopup: View {
    let assetInfo: AssetDetailInfo
    @Binding var isPresented: Bool
    var onSend: () -> Void
    var onReceive: () -> Void
    
    // Animation states
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92
    @State private var chartProgress: CGFloat = 0
    
    // Data states
    @State private var selectedTimeframe: ChartTimeframe = .day
    @State private var isLoadingPrice: Bool = true
    @State private var isLoadingChart: Bool = false
    @State private var livePrice: Double = 0
    @State private var priceChange: Double = 0
    @State private var fetchError: String? = nil
    @State private var chartData: [Double] = []
    
    // Hover states
    @State private var sendHovered: Bool = false
    @State private var receiveHovered: Bool = false
    
    // Cache for different timeframes
    @State private var cachedChartData: [ChartTimeframe: [Double]] = [:]
    @State private var cachedPriceChanges: [ChartTimeframe: Double] = [:]
    
    enum ChartTimeframe: String, CaseIterable {
        case day = "24H"
        case week = "7D"
        case month = "30D"
        
        var days: Int {
            switch self {
            case .day: return 1
            case .week: return 7
            case .month: return 30
            }
        }
        
        var label: String {
            switch self {
            case .day: return "24h"
            case .week: return "7d"
            case .month: return "30d"
            }
        }
    }
    
    private var displayPrice: Double {
        if livePrice > 0 { return livePrice }
        else if assetInfo.currentPrice > 0 { return assetInfo.currentPrice }
        return 0
    }
    
    private var formattedPrice: String {
        let price = displayPrice
        guard price > 0 else { return "—" }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        
        if price >= 10000 {
            formatter.maximumFractionDigits = 0
        } else if price >= 100 {
            formatter.maximumFractionDigits = 2
        } else if price >= 1 {
            formatter.maximumFractionDigits = 2
        } else {
            formatter.maximumFractionDigits = 6
        }
        
        return formatter.string(from: NSNumber(value: price)) ?? String(format: "$%.2f", price)
    }
    
    private var currentChartData: [Double] {
        if !chartData.isEmpty { return chartData }
        return assetInfo.sparklineData
    }
    
    private var calculatedPriceChange: Double {
        if priceChange != 0 { return priceChange }
        guard currentChartData.count >= 2 else { return 0 }
        let first = currentChartData.first ?? 1
        let last = currentChartData.last ?? 1
        guard first != 0 else { return 0 }
        return ((last - first) / first) * 100
    }
    
    private var isPositiveChange: Bool { calculatedPriceChange >= 0 }
    
    var body: some View {
        ZStack {
            // Dimmed backdrop
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture { dismissPopup() }
            
            // Main popup container
            VStack(spacing: 0) {
                // Header - centered cryptocurrency name
                ZStack {
                    // Centered title
                    Text(assetInfo.chain.title)
                        .font(.clashGroteskMedium(size: 20))
                        .foregroundColor(.white)
                    
                    // Close button aligned to the right
                    HStack {
                        Spacer()
                        Button(action: dismissPopup) {
                            Circle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Image(systemName: "xmark")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(Color.white.opacity(0.5))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)
                
                // Price section
                VStack(alignment: .center, spacing: 8) {
                    if isLoadingPrice {
                        SkeletonShape(width: 160, height: 42, cornerRadius: 8)
                    } else {
                        Text(formattedPrice)
                            .font(.clashGroteskBold(size: 42))
                            .foregroundColor(.white)
                            .contentTransition(.numericText())
                    }
                    
                    // Price change indicator
                    HStack(spacing: 6) {
                        if isLoadingChart {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: isPositiveChange ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        
                        Text(String(format: "%@%.2f%%", isPositiveChange ? "+" : "", calculatedPriceChange))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .monospacedDigit()
                        
                        Text(selectedTimeframe.label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.4))
                    }
                    .foregroundColor(Color.white.opacity(isPositiveChange ? 0.7 : 0.5))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 24)
                .opacity(contentOpacity)
                
                // Timeframe selector
                HStack(spacing: 6) {
                    ForEach(ChartTimeframe.allCases, id: \.self) { timeframe in
                        Button(action: {
                            guard selectedTimeframe != timeframe else { return }
                            withAnimation(.easeOut(duration: 0.2)) {
                                selectedTimeframe = timeframe
                                chartProgress = 0
                            }
                            fetchChartData(for: timeframe)
                            // Animate chart after fetch
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeOut(duration: 0.5)) {
                                    chartProgress = 1
                                }
                            }
                        }) {
                            Text(timeframe.rawValue)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(selectedTimeframe == timeframe ? .white : Color.white.opacity(0.4))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(selectedTimeframe == timeframe ? Color.white.opacity(0.1) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .opacity(contentOpacity)
                
                // Chart
                ZStack {
                    if isLoadingChart && currentChartData.isEmpty {
                        SkeletonShape(width: .infinity, height: 100, cornerRadius: 8)
                            .padding(.horizontal, 24)
                    } else if !currentChartData.isEmpty {
                        MonochromeChartView(
                            data: currentChartData,
                            isPositive: isPositiveChange,
                            progress: chartProgress
                        )
                        .opacity(isLoadingChart ? 0.5 : 1)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.03))
                            .overlay(
                                Text("No chart data")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color.white.opacity(0.25))
                            )
                    }
                }
                .frame(height: 100)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .opacity(contentOpacity)
                
                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                
                // Holdings section
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Holdings")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.4))
                    
                    Text(assetInfo.fiatValue)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("\(assetInfo.balance) \(assetInfo.chainSymbol)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .opacity(contentOpacity)
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 12) {
                    // Send button
                    Button(action: {
                        dismissPopup()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onSend() }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Send")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(sendHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(sendHovered ? 0.15 : 0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!assetInfo.canSend)
                    .opacity(assetInfo.canSend ? 1 : 0.4)
                    .onHover { sendHovered = $0 }
                    
                    // Receive button
                    Button(action: {
                        dismissPopup()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onReceive() }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Receive")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(receiveHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(receiveHovered ? 0.15 : 0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { receiveHovered = $0 }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .opacity(contentOpacity)
            }
            .frame(width: 400, height: 480)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.1), Color.white.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.5), radius: 50, x: 0, y: 25)
            .scaleEffect(cardScale)
        }
        .background(
            EscapeKeyHandler(isPresented: $isPresented, onEscape: dismissPopup)
        )
        .onAppear {
            // Smooth entrance
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                cardScale = 1
                contentOpacity = 1
            }
            
            // Chart animation
            withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
                chartProgress = 1
            }
            
            fetchLivePrice()
        }
    }
    
    // Fetch real-time price AND 24h change from CryptoCompare API
    private func fetchLivePrice() {
        // Map chain ID to CryptoCompare symbol
        let symbolMap: [String: String] = [
            "bitcoin": "BTC",
            "bitcoin-testnet": "BTC",
            "ethereum": "ETH",
            "ethereum-sepolia": "ETH",
            "litecoin": "LTC",
            "solana": "SOL",
            "solana-devnet": "SOL",
            "xrp": "XRP",
            "xrp-testnet": "XRP",
            "bnb": "BNB",
            "monero": "XMR",
            "polygon": "MATIC",
            "arbitrum": "ARB"
        ]
        
        let chainId = assetInfo.chain.id
        print("💰 [Popup] Fetching price for chain: \(chainId)")
        print("💰 [Popup] Passed-in currentPrice: \(assetInfo.currentPrice)")
        
        // If we already have a price from priceStates, use it immediately for display
        if assetInfo.currentPrice > 0 {
            print("✅ [Popup] Using passed-in price: $\(assetInfo.currentPrice)")
            self.livePrice = assetInfo.currentPrice
            self.isLoadingPrice = false
            // Don't return! Continue to fetch 24h change
        }
        
        guard let symbol = symbolMap[chainId] else {
            print("⚠️ [Popup] No symbol mapping for chain: \(chainId)")
            if assetInfo.currentPrice == 0 {
                isLoadingPrice = false
            }
            return
        }
        
        // Use CryptoCompare API to get the 24h change percentage
        let urlString = "https://min-api.cryptocompare.com/data/pricemultifull?fsyms=\(symbol)&tsyms=USD"
        print("💰 [Popup] CryptoCompare URL: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            print("⚠️ [Popup] Invalid URL")
            if assetInfo.currentPrice == 0 {
                isLoadingPrice = false
            }
            return
        }
        
        Task {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                request.setValue("HawalaWallet/2.0", forHTTPHeaderField: "User-Agent")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("💰 [Popup] CryptoCompare response status: \(httpResponse.statusCode)")
                }
                
                // Parse CryptoCompare response: {"RAW":{"BTC":{"USD":{"PRICE":95000,"CHANGEPCT24HOUR":-0.5}}}}
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let raw = json["RAW"] as? [String: Any],
                   let symbolData = raw[symbol] as? [String: Any],
                   let usdData = symbolData["USD"] as? [String: Any] {
                    
                    let apiPrice = usdData["PRICE"] as? Double ?? 0
                    let change = usdData["CHANGEPCT24HOUR"] as? Double ?? 0
                    
                    print("✅ [Popup] CryptoCompare price: $\(apiPrice), 24h change: \(change)%")
                    
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            // Only update price if we didn't already have one
                            if self.livePrice == 0 {
                                self.livePrice = apiPrice
                            }
                            // Update the 24h change (only if we're on day timeframe)
                            if self.selectedTimeframe == .day {
                                self.priceChange = change
                            }
                            // Cache it
                            self.cachedPriceChanges[.day] = change
                            self.isLoadingPrice = false
                            self.fetchError = nil
                        }
                        // Also fetch initial chart data for 24h
                        self.fetchChartData(for: .day)
                    }
                } else {
                    print("⚠️ [Popup] Failed to parse CryptoCompare JSON")
                    let responseString = String(data: data, encoding: .utf8) ?? "nil"
                    print("💰 [Popup] Raw response: \(responseString.prefix(200))")
                    await MainActor.run {
                        self.fetchError = "Parse error"
                        if self.livePrice == 0 {
                            self.isLoadingPrice = false
                        }
                    }
                }
            } catch {
                print("❌ [Popup] CryptoCompare fetch error: \(error.localizedDescription)")
                await MainActor.run {
                    self.fetchError = error.localizedDescription
                    self.isLoadingPrice = false
                }
            }
        }
    }
    
    // Fetch historical chart data from CryptoCompare
    private func fetchChartData(for timeframe: ChartTimeframe) {
        // Check cache first
        if let cached = cachedChartData[timeframe], !cached.isEmpty {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.chartData = cached
                if let cachedChange = cachedPriceChanges[timeframe] {
                    self.priceChange = cachedChange
                }
            }
            return
        }
        
        // Map chain ID to CryptoCompare symbol
        let symbolMap: [String: String] = [
            "bitcoin": "BTC",
            "bitcoin-testnet": "BTC",
            "ethereum": "ETH",
            "ethereum-sepolia": "ETH",
            "litecoin": "LTC",
            "solana": "SOL",
            "solana-devnet": "SOL",
            "xrp": "XRP",
            "xrp-testnet": "XRP",
            "bnb": "BNB",
            "monero": "XMR",
            "polygon": "MATIC",
            "arbitrum": "ARB"
        ]
        
        let chainId = assetInfo.chain.id
        guard let symbol = symbolMap[chainId] else {
            print("⚠️ [Chart] No symbol mapping for chain: \(chainId)")
            return
        }
        
        isLoadingChart = true
        
        // Use histohour for 24H, histoday for 7D and 30D
        let endpoint: String
        let limit: Int
        
        switch timeframe {
        case .day:
            endpoint = "histohour"
            limit = 24
        case .week:
            endpoint = "histoday"
            limit = 7
        case .month:
            endpoint = "histoday"
            limit = 30
        }
        
        let urlString = "https://min-api.cryptocompare.com/data/v2/\(endpoint)?fsym=\(symbol)&tsym=USD&limit=\(limit)"
        print("📊 [Chart] Fetching \(timeframe.rawValue) data: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            isLoadingChart = false
            return
        }
        
        Task {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                request.setValue("HawalaWallet/2.0", forHTTPHeaderField: "User-Agent")
                
                let (data, _) = try await URLSession.shared.data(for: request)
                
                // Parse response: {"Data":{"Data":[{"close":95000},{"close":95100},...]}}
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let dataWrapper = json["Data"] as? [String: Any],
                   let dataArray = dataWrapper["Data"] as? [[String: Any]] {
                    
                    let prices = dataArray.compactMap { $0["close"] as? Double }
                    
                    guard prices.count >= 2 else {
                        print("⚠️ [Chart] Not enough price points: \(prices.count)")
                        await MainActor.run { self.isLoadingChart = false }
                        return
                    }
                    
                    // Calculate price change for this timeframe
                    let firstPrice = prices.first ?? 1
                    let lastPrice = prices.last ?? 1
                    let changePercent = firstPrice != 0 ? ((lastPrice - firstPrice) / firstPrice) * 100 : 0
                    
                    print("✅ [Chart] Got \(prices.count) points for \(timeframe.rawValue), change: \(String(format: "%.2f", changePercent))%")
                    
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            self.chartData = prices
                            self.priceChange = changePercent
                            self.cachedChartData[timeframe] = prices
                            self.cachedPriceChanges[timeframe] = changePercent
                            self.isLoadingChart = false
                        }
                    }
                } else {
                    print("⚠️ [Chart] Failed to parse CryptoCompare chart JSON")
                    await MainActor.run { self.isLoadingChart = false }
                }
            } catch {
                print("❌ [Chart] Fetch error: \(error.localizedDescription)")
                await MainActor.run { self.isLoadingChart = false }
            }
        }
    }
    
    private func dismissPopup() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            contentOpacity = 0
            cardScale = 0.95
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.1)) {
                isPresented = false
            }
        }
    }
}

// MARK: - Monochrome Chart View (Clean, smooth line chart)
struct MonochromeChartView: View {
    let data: [Double]
    let isPositive: Bool
    let progress: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            
            guard data.count >= 2 else {
                return AnyView(EmptyView())
            }
            
            let minVal = data.min() ?? 0
            let maxVal = data.max() ?? 1
            let range = max(maxVal - minVal, 0.0001)
            let padding: CGFloat = 8
            
            let points: [CGPoint] = data.enumerated().map { index, value in
                let x = CGFloat(index) / CGFloat(data.count - 1) * width
                let y = padding + (height - 2 * padding) * (1 - (CGFloat(value) - CGFloat(minVal)) / CGFloat(range))
                return CGPoint(x: x, y: y)
            }
            
            return AnyView(
                ZStack {
                    // Gradient fill under line
                    Path { path in
                        guard let firstPoint = points.first else { return }
                        path.move(to: CGPoint(x: firstPoint.x, y: height))
                        path.addLine(to: firstPoint)
                        
                        for i in 1..<points.count {
                            let p0 = points[i - 1]
                            let p1 = points[i]
                            let midX = (p0.x + p1.x) / 2
                            path.addCurve(
                                to: p1,
                                control1: CGPoint(x: midX, y: p0.y),
                                control2: CGPoint(x: midX, y: p1.y)
                            )
                        }
                        
                        if let lastPoint = points.last {
                            path.addLine(to: CGPoint(x: lastPoint.x, y: height))
                        }
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.02),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .mask(
                        Rectangle()
                            .scale(x: progress, y: 1, anchor: .leading)
                    )
                    
                    // Smooth curved line
                    Path { path in
                        guard let firstPoint = points.first else { return }
                        path.move(to: firstPoint)
                        
                        for i in 1..<points.count {
                            let p0 = points[i - 1]
                            let p1 = points[i]
                            let midX = (p0.x + p1.x) / 2
                            path.addCurve(
                                to: p1,
                                control1: CGPoint(x: midX, y: p0.y),
                                control2: CGPoint(x: midX, y: p1.y)
                            )
                        }
                    }
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color.white.opacity(0.5),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                    )
                    
                    // End point dot
                    if let lastPoint = points.last, progress > 0.95 {
                        Circle()
                            .fill(Color.white.opacity(0.6))
                            .frame(width: 6, height: 6)
                            .position(lastPoint)
                    }
                }
            )
        }
    }
}

// MARK: - Escape Key Handler (macOS 13+ compatible)
struct EscapeKeyHandler: NSViewRepresentable {
    @Binding var isPresented: Bool
    let onEscape: () -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyCaptureView()
        view.onEscape = onEscape
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let keyView = nsView as? KeyCaptureView {
            keyView.onEscape = onEscape
        }
    }
    
    class KeyCaptureView: NSView {
        var onEscape: (() -> Void)?
        
        override var acceptsFirstResponder: Bool { true }
        
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { // Escape key
                onEscape?()
            } else {
                super.keyDown(with: event)
            }
        }
    }
}

// MARK: - Detail Chart View (Premium Line Chart)
struct DetailChartView: View {
    let data: [Double]
    let isPositive: Bool
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            
            guard data.count >= 2 else {
                return AnyView(EmptyView())
            }
            
            let minVal = data.min() ?? 0
            let maxVal = data.max() ?? 1
            let range = max(maxVal - minVal, 0.0001) // Prevent division by zero
            
            let points: [CGPoint] = data.enumerated().map { index, value in
                let x = CGFloat(index) / CGFloat(data.count - 1) * width
                let y = height - ((CGFloat(value) - CGFloat(minVal)) / CGFloat(range) * height)
                return CGPoint(x: x, y: y)
            }
            
            return AnyView(
                ZStack {
                    // Gradient fill under the line
                    Path { path in
                        guard let firstPoint = points.first else { return }
                        path.move(to: CGPoint(x: firstPoint.x, y: height))
                        path.addLine(to: firstPoint)
                        
                        for i in 1..<points.count {
                            let p0 = points[i - 1]
                            let p1 = points[i]
                            let midX = (p0.x + p1.x) / 2
                            path.addCurve(
                                to: p1,
                                control1: CGPoint(x: midX, y: p0.y),
                                control2: CGPoint(x: midX, y: p1.y)
                            )
                        }
                        
                        if let lastPoint = points.last {
                            path.addLine(to: CGPoint(x: lastPoint.x, y: height))
                        }
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [
                                (isPositive ? HawalaTheme.Colors.success : HawalaTheme.Colors.error).opacity(0.3),
                                (isPositive ? HawalaTheme.Colors.success : HawalaTheme.Colors.error).opacity(0.05),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    // Main line
                    Path { path in
                        guard let firstPoint = points.first else { return }
                        path.move(to: firstPoint)
                        
                        for i in 1..<points.count {
                            let p0 = points[i - 1]
                            let p1 = points[i]
                            let midX = (p0.x + p1.x) / 2
                            path.addCurve(
                                to: p1,
                                control1: CGPoint(x: midX, y: p0.y),
                                control2: CGPoint(x: midX, y: p1.y)
                            )
                        }
                    }
                    .stroke(
                        LinearGradient(
                            colors: [
                                isPositive ? HawalaTheme.Colors.success : HawalaTheme.Colors.error,
                                isPositive ? HawalaTheme.Colors.success.opacity(0.7) : HawalaTheme.Colors.error.opacity(0.7)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                    )
                    
                    // End point indicator
                    if let lastPoint = points.last {
                        Circle()
                            .fill(isPositive ? HawalaTheme.Colors.success : HawalaTheme.Colors.error)
                            .frame(width: 8, height: 8)
                            .position(lastPoint)
                            .shadow(color: (isPositive ? HawalaTheme.Colors.success : HawalaTheme.Colors.error).opacity(0.5), radius: 6)
                    }
                }
            )
        }
    }
}
