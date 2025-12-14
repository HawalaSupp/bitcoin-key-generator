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
    
    // Settings
    @AppStorage("showBalances") private var showBalances = true
    @AppStorage("showTestnets") private var showTestnets = false
    @AppStorage("selectedBackgroundType") private var selectedBackgroundType = "none"
    
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
    
    // Transaction history
    @Binding var historyEntries: [HawalaTransactionEntry]
    @Binding var isHistoryLoading: Bool
    @Binding var historyError: String?
    
    // Transaction detail sheet
    @State private var selectedTransaction: HawalaTransactionEntry?
    
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
                .ignoresSafeArea()
            
            // Main content (full width now)
            mainContentView
                .padding(.top, 70) // Space for floating nav bar
            
            // Floating liquid glass navigation bar
            liquidGlassNavBar
                .padding(.top, HawalaTheme.Spacing.lg)
            
            // Hidden keyboard shortcut buttons
            keyboardShortcutHandlers
            
            // Toast notifications overlay
            ToastContainer()
        }
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
            // Logo - uses custom image with background removed, auto-inverts for dark/light mode
            if let logoURL = Bundle.module.url(forResource: "HawalaLogo", withExtension: "png"),
               let nsImage = NSImage(contentsOf: logoURL) {
                Image(nsImage: nsImage)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 16)
            }
            
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
                
                // Network status indicator
                NetworkStatusBar()
                
                GlassIconButton(icon: "arrow.up.arrow.down") {
                    showSendPicker = true
                }
                
                GlassIconButton(icon: "qrcode") {
                    showReceiveSheet = true
                }
                
                GlassIconButton(icon: "gearshape") {
                    showSettingsPanel = true
                }
                
                GlassIconButton(icon: "bell", badge: NotificationManager.shared.unreadCount) {
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
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                hoveredTab = hovering ? tab : nil
            }
        }
    }
    
    // MARK: - Glass Icon Button
    struct GlassIconButton: View {
        let icon: String
        var badge: Int? = nil
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
                    .id(selectedTab)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98)).animation(.easeOut(duration: 0.25)),
                        removal: .opacity.animation(.easeIn(duration: 0.15))
                    ))
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .refreshable {
                // Pull-to-refresh triggers balance reload
                await refreshData()
            }
        }
        .onChange(of: selectedTab) { newTab in
            previousTab = selectedTab
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
                        .font(.system(size: 56, weight: .light, design: .rounded))
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                        .opacity(0.5)
                } else {
                    let total = calculateTotalBalance()
                    
                    // Main balance - large, light weight, no background
                    if showBalances {
                        Text(selectedFiatSymbol + formatLargeNumber(total))
                            .font(.system(size: 56, weight: .light, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white)
                    } else {
                        Text("••••••")
                            .font(.system(size: 56, weight: .light, design: .rounded))
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                    }
                    
                    // Subtle P&L indicator
                    if showBalances {
                        HStack(spacing: HawalaTheme.Spacing.xs) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .medium))
                            Text("+5.2%")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(HawalaTheme.Colors.success)
                        .opacity(0.8)
                    }
                }
            } else {
                // No keys state - minimal
                VStack(spacing: HawalaTheme.Spacing.lg) {
                    Text("$0.00")
                        .font(.system(size: 56, weight: .light, design: .rounded))
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
                            isSelected: selectedChain?.id == chain.id,
                            hideBalance: !showBalances,
                            onSelect: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                    selectedChain = chain
                                }
                            },
                            onSend: {
                                // Quick send action - show send sheet
                                selectedChain = chain
                                showSendPicker = true
                            },
                            onReceive: {
                                // Quick receive action - show receive sheet  
                                selectedChain = chain
                                showReceiveSheet = true
                            },
                            canSend: sendEnabledChainIDs.contains(chain.id)
                        )
                    }
                }
                .padding(.horizontal, HawalaTheme.Spacing.xl)
            } else {
                BentoEmptyState(onGenerate: onGenerateKeys)
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
                    AnimatedCounter(value: total, prefix: selectedFiatSymbol, duration: 1.0, hideBalance: !showBalances)
                    
                    // P&L indicator (simulated for now - would need purchase history)
                    if showBalances {
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
                    
                    HawalaPrimaryButton("Generate Wallet", icon: "key.fill", action: onGenerateKeys)
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
                                    hideBalance: !showBalances,
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
                    actionTitle: "Generate Wallet",
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
                            hideBalance: !showBalances
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
                    // Empty state
                    VStack(spacing: HawalaTheme.Spacing.md) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 32))
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                        
                        Text("No transactions yet")
                            .font(HawalaTheme.Typography.body)
                            .foregroundColor(HawalaTheme.Colors.textPrimary)
                        
                        Text("Your activity will appear here once you make your first transaction.")
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, HawalaTheme.Spacing.xxl)
                } else {
                    // Real transaction list
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

// MARK: - Bento Asset Card (Grid Cell)
struct BentoAssetCard: View {
    let chain: ChainInfo
    let chainSymbol: String
    let chainColor: Color
    let balance: String
    let fiatValue: String
    let sparklineData: [Double]
    let isSelected: Bool
    var hideBalance: Bool = false
    var onSelect: () -> Void
    var onSend: (() -> Void)? = nil
    var onReceive: (() -> Void)? = nil
    var canSend: Bool = true
    
    @State private var isHovered = false
    
    // Price change percentage from sparkline
    private var priceChange: Double {
        guard sparklineData.count >= 2 else { return 0 }
        let first = sparklineData.first ?? 1
        let last = sparklineData.last ?? 1
        guard first != 0 else { return 0 }
        return ((last - first) / first) * 100
    }
    
    var body: some View {
        Button(action: {
            // Haptic feedback on selection
            #if os(macOS)
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            #endif
            onSelect()
        }) {
            VStack(alignment: .leading, spacing: 0) {
                // Header: Icon + Name + Price change
                HStack(spacing: 10) {
                    // Chain icon - monochrome
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: chain.iconName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.5))
                    }
                    
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
                
                // Sparkline chart - monochrome
                if !sparklineData.isEmpty {
                    EnhancedSparkline(data: sparklineData, color: .white, showGradient: isHovered)
                        .frame(height: 50)
                        .padding(.vertical, 8)
                } else {
                    // Placeholder for no data
                    SkeletonView(height: 50)
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
                ZStack {
                    // Glassmorphism card background
                    if #available(macOS 12.0, *) {
                        RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .opacity(0.6)
                    } else {
                        RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous)
                            .fill(Color(white: 0.12, opacity: 0.9))
                    }
                    
                    // Border with gradient
                    RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(isSelected ? 0.3 : (isHovered ? 0.15 : 0.1)),
                                    .white.opacity(isSelected ? 0.1 : (isHovered ? 0.05 : 0.02))
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                }
            )
            .drawingGroup() // GPU-accelerated rendering for smooth scrolling
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            // Quick actions context menu
            if canSend, let send = onSend {
                Button(action: {
                    #if os(macOS)
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                    #endif
                    send()
                }) {
                    Label("Send \(chainSymbol)", systemImage: "arrow.up.circle.fill")
                }
            }
            
            if let receive = onReceive {
                Button(action: {
                    #if os(macOS)
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                    #endif
                    receive()
                }) {
                    Label("Receive \(chainSymbol)", systemImage: "arrow.down.circle.fill")
                }
            }
            
            Divider()
            
            Button(action: {
                #if os(macOS)
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                #endif
                // Copy address to clipboard
                if let address = chain.receiveAddress {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(address, forType: .string)
                    #endif
                }
            }) {
                Label("Copy Address", systemImage: "doc.on.doc")
            }
        }
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
            
            HawalaPrimaryButton("Generate Wallet", icon: "key.fill", action: onGenerate)
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
    }
}
