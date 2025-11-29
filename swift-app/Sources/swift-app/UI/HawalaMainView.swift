import SwiftUI

// MARK: - Main App Shell (Modern Glass Design)
struct HawalaMainView: View {
    @Binding var keys: AllKeys?
    @Binding var selectedChain: ChainInfo?
    @Binding var balanceStates: [String: ChainBalanceState]
    @Binding var priceStates: [String: ChainPriceState]
    @StateObject var sparklineCache: SparklineCache
    
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
    
    // Actions
    var onGenerateKeys: () -> Void
    var onRefreshBalances: () -> Void
    var selectedFiatSymbol: String
    var fxRates: [String: Double]
    var selectedFiatCurrency: String
    
    enum NavigationTab: String, CaseIterable, Comparable {
        case portfolio = "Portfolio"
        case accounts = "Accounts"
        case activity = "Activity"
        case discover = "Discover"
        
        var icon: String {
            switch self {
            case .portfolio: return "chart.pie.fill"
            case .accounts: return "wallet.pass.fill"
            case .activity: return "clock.arrow.circlepath"
            case .discover: return "sparkles"
            }
        }
        
        var index: Int {
            switch self {
            case .portfolio: return 0
            case .accounts: return 1
            case .activity: return 2
            case .discover: return 3
            }
        }
        
        static func < (lhs: NavigationTab, rhs: NavigationTab) -> Bool {
            lhs.index < rhs.index
        }
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // Subtle particle background for depth
            ParticleBackgroundView(particleCount: 15, colors: [
                HawalaTheme.Colors.accent.opacity(0.15),
                HawalaTheme.Colors.ethereum.opacity(0.1),
                Color.white.opacity(0.05)
            ])
            .opacity(0.6)
            
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
    }
    
    // MARK: - Keyboard Shortcut Handlers
    private var keyboardShortcutHandlers: some View {
        Group {
            // Tab navigation: Cmd+1, Cmd+2, Cmd+3, Cmd+4
            Button("") {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    selectedTab = .portfolio
                }
            }
            .keyboardShortcut("1", modifiers: .command)
            .opacity(0)
            
            Button("") {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    selectedTab = .accounts
                }
            }
            .keyboardShortcut("2", modifiers: .command)
            .opacity(0)
            
            Button("") {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    selectedTab = .activity
                }
            }
            .keyboardShortcut("3", modifiers: .command)
            .opacity(0)
            
            Button("") {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    selectedTab = .discover
                }
            }
            .keyboardShortcut("4", modifiers: .command)
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
        HStack(spacing: HawalaTheme.Spacing.md) {
            // Logo
            HStack(spacing: HawalaTheme.Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [HawalaTheme.Colors.accent, HawalaTheme.Colors.accent.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                    
                    Text("H")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                
                Text("Hawala")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
            }
            
            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 1, height: 24)
            
            // Navigation tabs
            HStack(spacing: HawalaTheme.Spacing.xs) {
                ForEach(NavigationTab.allCases, id: \.self) { tab in
                    liquidGlassTab(tab)
                }
            }
            
            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 1, height: 24)
            
            // Right side actions
            HStack(spacing: HawalaTheme.Spacing.sm) {
                // Network status indicator
                NetworkStatusBar()
                
                glassIconButton("arrow.up.arrow.down") {
                    showSendPicker = true
                }
                
                glassIconButton("qrcode") {
                    showReceiveSheet = true
                }
                
                glassIconButton("gearshape") {
                    showSettingsPanel = true
                }
                
                glassIconButton("bell", badge: NotificationManager.shared.unreadCount) {
                    showNotificationsSheet = true
                }
            }
        }
        .padding(.horizontal, HawalaTheme.Spacing.lg)
        .frame(height: 52)
        .background(
            ZStack {
                // Liquid glass effect
                Capsule()
                    .fill(.ultraThinMaterial)
                
                // Subtle gradient overlay
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.02)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Border glow
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.2),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
        .shadow(color: HawalaTheme.Colors.accent.opacity(0.1), radius: 30, x: 0, y: 5)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isNavBarHovered)
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
            HStack(spacing: HawalaTheme.Spacing.xs) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: .medium))
                
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(isSelected ? HawalaTheme.Colors.textPrimary : HawalaTheme.Colors.textSecondary)
            .padding(.horizontal, HawalaTheme.Spacing.md)
            .padding(.vertical, HawalaTheme.Spacing.sm)
            .background(
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                        
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    } else if isHovered {
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                    }
                }
            )
            .scaleEffect(isSelected ? 1.02 : (isHovered ? 1.01 : 1.0))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredTab = hovering ? tab : nil
            }
        }
    }
    
    // MARK: - Glass Icon Button
    private func glassIconButton(_ icon: String, badge: Int? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.06))
                    )
                
                if let badge = badge, badge > 0 {
                    Circle()
                        .fill(HawalaTheme.Colors.accent)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Text("\(min(badge, 9))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            // Could add hover effect here
        }
    }
    
    // MARK: - Main Content (with page transitions)
    private var mainContentView: some View {
        VStack(spacing: 0) {
            // Content based on selected tab with smooth transitions
            ScrollView {
                ZStack {
                    // Use transition based on tab direction
                    Group {
                        switch selectedTab {
                        case .portfolio:
                            portfolioView
                        case .accounts:
                            accountsView
                        case .activity:
                            activityView
                        case .discover:
                            discoverView
                        }
                    }
                    .id(selectedTab)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: selectedTab > previousTab ? .trailing : .leading)
                                .combined(with: .opacity),
                            removal: .move(edge: selectedTab > previousTab ? .leading : .trailing)
                                .combined(with: .opacity)
                        )
                    )
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: selectedTab)
            }
        }
        .onChange(of: selectedTab) { newTab in
            previousTab = selectedTab
        }
    }
    
    // MARK: - Portfolio View
    private var portfolioView: some View {
        VStack(alignment: .center, spacing: HawalaTheme.Spacing.xl) {
            // Total balance hero
            totalBalanceCard
                .padding(.horizontal, HawalaTheme.Spacing.xl)
            
            // Assets list
            assetsSection
        }
        .padding(.top, HawalaTheme.Spacing.md)
        .padding(.bottom, HawalaTheme.Spacing.xxl)
    }
    
    // MARK: - Total Balance Card
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
                    AnimatedCounter(value: total, prefix: selectedFiatSymbol, duration: 1.0)
                    
                    // P&L indicator (simulated for now - would need purchase history)
                    ProfitLossIndicator(
                        currentValue: total,
                        purchaseValue: total * 0.95, // Simulated 5% gain
                        currencySymbol: selectedFiatSymbol,
                        size: .medium
                    )
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
                            isSelected: selectedChain?.id == chain.id
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
            Text("Recent Activity")
                .font(HawalaTheme.Typography.h2)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
                .padding(.horizontal, HawalaTheme.Spacing.xl)
            
            // Placeholder transactions
            VStack(spacing: 0) {
                HawalaTransactionRow(
                    type: .receive,
                    amount: "0.0523",
                    symbol: "BTC",
                    fiatValue: "$4,892.32",
                    date: "Today",
                    status: .confirmed,
                    counterparty: "bc1q...x4f2"
                )
                
                Divider()
                    .background(HawalaTheme.Colors.divider)
                    .padding(.horizontal, HawalaTheme.Spacing.md)
                
                HawalaTransactionRow(
                    type: .send,
                    amount: "1.25",
                    symbol: "ETH",
                    fiatValue: "$4,125.00",
                    date: "Yesterday",
                    status: .processing,
                    counterparty: "0x742d...4F6a"
                )
                
                Divider()
                    .background(HawalaTheme.Colors.divider)
                    .padding(.horizontal, HawalaTheme.Spacing.md)
                
                HawalaTransactionRow(
                    type: .receive,
                    amount: "250.00",
                    symbol: "SOL",
                    fiatValue: "$45,000.00",
                    date: "Nov 24",
                    status: .pending,
                    counterparty: "7xKX...9Hm2"
                )
                
                Divider()
                    .background(HawalaTheme.Colors.divider)
                    .padding(.horizontal, HawalaTheme.Spacing.md)
                
                HawalaTransactionRow(
                    type: .swap,
                    amount: "500",
                    symbol: "USDC",
                    fiatValue: "$500.00",
                    date: "Nov 23",
                    status: .failed,
                    counterparty: nil
                )
            }
            .padding(HawalaTheme.Spacing.sm)
            .frostedGlass(cornerRadius: HawalaTheme.Radius.lg, intensity: 0.2)
            .padding(.horizontal, HawalaTheme.Spacing.xl)
        }
        .padding(.vertical, HawalaTheme.Spacing.lg)
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
        if searchText.isEmpty {
            return chains
        }
        return chains.filter { 
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.id.localizedCaseInsensitiveContains(searchText)
        }
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
            return "\(selectedFiatSymbol)--"
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
                    
                    Text(balance)
                        .font(HawalaTheme.Typography.mono)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                    
                    Text(fiatValue)
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
            .scaleEffect(isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
    }
}
