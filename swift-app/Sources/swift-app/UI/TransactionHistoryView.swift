import SwiftUI

// MARK: - Transaction History View with Filtering & Search
struct TransactionHistoryView: View {
    @StateObject private var historyService = TransactionHistoryService.shared
    
    // Filtering state
    @State private var searchText: String = ""
    @State private var selectedFilter: TransactionFilter = .all
    @State private var selectedChain: String? = nil
    @State private var dateRange: DateRangeFilter = .all
    @State private var showFilters: Bool = false
    
    // Available chains for filtering
    let availableChains: [String]
    
    init(availableChains: [String] = []) {
        self.availableChains = availableChains
    }
    
    enum TransactionFilter: String, CaseIterable {
        case all = "All"
        case received = "Received"
        case sent = "Sent"
        case swaps = "Swaps"
        case pending = "Pending"
        case failed = "Failed"
        
        var icon: String {
            switch self {
            case .all: return "list.bullet"
            case .received: return "arrow.down.circle"
            case .sent: return "arrow.up.circle"
            case .swaps: return "arrow.left.arrow.right"
            case .pending: return "clock"
            case .failed: return "xmark.circle"
            }
        }
    }
    
    enum DateRangeFilter: String, CaseIterable {
        case all = "All Time"
        case today = "Today"
        case week = "This Week"
        case month = "This Month"
        case quarter = "Last 3 Months"
        case year = "This Year"
        
        var dateThreshold: Date {
            let calendar = Calendar.current
            let now = Date()
            switch self {
            case .all: return .distantPast
            case .today: return calendar.startOfDay(for: now)
            case .week: return calendar.date(byAdding: .day, value: -7, to: now) ?? now
            case .month: return calendar.date(byAdding: .month, value: -1, to: now) ?? now
            case .quarter: return calendar.date(byAdding: .month, value: -3, to: now) ?? now
            case .year: return calendar.date(byAdding: .year, value: -1, to: now) ?? now
            }
        }
    }
    
    var filteredTransactions: [TransactionEntry] {
        historyService.entries.filter { entry in
            // Search filter
            let matchesSearch = searchText.isEmpty ||
                entry.txHash.localizedCaseInsensitiveContains(searchText) ||
                entry.chainId.localizedCaseInsensitiveContains(searchText)
            
            // Type filter
            let matchesType: Bool
            switch selectedFilter {
            case .all:
                matchesType = true
            case .received:
                matchesType = entry.type == .receive
            case .sent:
                matchesType = entry.type == .send
            case .swaps:
                matchesType = entry.type == .swap
            case .pending:
                matchesType = entry.status == .pending
            case .failed:
                matchesType = entry.status == .failed
            }
            
            // Chain filter
            let matchesChain = selectedChain == nil || entry.chainId == selectedChain
            
            // Date filter
            let matchesDate = (entry.timestamp ?? .distantPast) >= dateRange.dateThreshold
            
            return matchesSearch && matchesType && matchesChain && matchesDate
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with search and filters
            headerSection
            
            // Filter chips
            filterChipsSection
            
            // Transaction list or empty state
            if historyService.isLoading && historyService.entries.isEmpty {
                loadingState
            } else if filteredTransactions.isEmpty {
                emptyState
            } else {
                transactionList
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            HStack(spacing: HawalaTheme.Spacing.md) {
                // Search field
                HStack(spacing: HawalaTheme.Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                    
                    TextField("Search transactions...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(HawalaTheme.Typography.body)
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(HawalaTheme.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(HawalaTheme.Spacing.sm)
                .background(HawalaTheme.Colors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
                
                // Filter button
                Button(action: { withAnimation { showFilters.toggle() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text("Filters")
                            .font(HawalaTheme.Typography.caption)
                    }
                    .foregroundColor(showFilters ? HawalaTheme.Colors.accent : HawalaTheme.Colors.textSecondary)
                    .padding(.horizontal, HawalaTheme.Spacing.md)
                    .padding(.vertical, HawalaTheme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous)
                            .fill(showFilters ? HawalaTheme.Colors.accentSubtle : HawalaTheme.Colors.backgroundSecondary)
                    )
                }
                .buttonStyle(.plain)
                
                // Refresh button
                Button(action: refreshHistory) {
                    Image(systemName: historyService.isLoading ? "arrow.clockwise" : "arrow.clockwise")
                        .rotationEffect(.degrees(historyService.isLoading ? 360 : 0))
                        .animation(historyService.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: historyService.isLoading)
                        .foregroundColor(HawalaTheme.Colors.accent)
                        .padding(HawalaTheme.Spacing.sm)
                        .background(HawalaTheme.Colors.backgroundSecondary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(historyService.isLoading)
            }
            
            // Expanded filters
            if showFilters {
                expandedFilters
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(HawalaTheme.Spacing.lg)
    }
    
    // MARK: - Expanded Filters
    private var expandedFilters: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            // Date range picker
            HStack {
                Text("Date Range")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                
                Spacer()
                
                Picker("", selection: $dateRange) {
                    ForEach(DateRangeFilter.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            
            // Chain filter
            if !availableChains.isEmpty {
                HStack {
                    Text("Chain")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                    
                    Spacer()
                    
                    Picker("", selection: $selectedChain) {
                        Text("All Chains").tag(nil as String?)
                        ForEach(availableChains, id: \.self) { chain in
                            Text(chainDisplayName(chain)).tag(chain as String?)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
        }
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
    }
    
    // MARK: - Filter Chips
    private var filterChipsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HawalaTheme.Spacing.sm) {
                ForEach(TransactionFilter.allCases, id: \.self) { filter in
                    FilterChip(
                        title: filter.rawValue,
                        icon: filter.icon,
                        isSelected: selectedFilter == filter
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedFilter = filter
                        }
                    }
                }
            }
            .padding(.horizontal, HawalaTheme.Spacing.lg)
            .padding(.vertical, HawalaTheme.Spacing.sm)
        }
    }
    
    // MARK: - Transaction List
    private var transactionList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Stats header
                transactionStats
                    .padding(.horizontal, HawalaTheme.Spacing.lg)
                    .padding(.bottom, HawalaTheme.Spacing.md)
                
                // Grouped by date
                let grouped = groupTransactionsByDate(filteredTransactions)
                
                ForEach(grouped.keys.sorted().reversed(), id: \.self) { dateKey in
                    Section {
                        VStack(spacing: 0) {
                            ForEach(grouped[dateKey] ?? [], id: \.id) { transaction in
                                TransactionRowView(transaction: transaction)
                                
                                if transaction.id != grouped[dateKey]?.last?.id {
                                    Divider()
                                        .background(HawalaTheme.Colors.divider)
                                        .padding(.horizontal, HawalaTheme.Spacing.lg)
                                }
                            }
                        }
                        .background(HawalaTheme.Colors.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous))
                    } header: {
                        Text(dateKey)
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, HawalaTheme.Spacing.lg)
                            .padding(.vertical, HawalaTheme.Spacing.sm)
                    }
                    .padding(.horizontal, HawalaTheme.Spacing.lg)
                    .padding(.bottom, HawalaTheme.Spacing.md)
                }
            }
            .padding(.vertical, HawalaTheme.Spacing.md)
        }
    }
    
    // MARK: - Transaction Stats
    private var transactionStats: some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            StatBadge(
                title: "Total",
                value: "\(filteredTransactions.count)",
                color: HawalaTheme.Colors.textSecondary
            )
            
            StatBadge(
                title: "Received",
                value: "\(filteredTransactions.filter { $0.type == .receive }.count)",
                color: HawalaTheme.Colors.success
            )
            
            StatBadge(
                title: "Sent",
                value: "\(filteredTransactions.filter { $0.type == .send }.count)",
                color: HawalaTheme.Colors.error
            )
            
            Spacer()
            
            if let lastUpdated = historyService.lastUpdated {
                Text("Updated \(lastUpdated.formatted(.relative(presentation: .named)))")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
        }
    }
    
    // MARK: - Loading State
    private var loadingState: some View {
        VStack(spacing: HawalaTheme.Spacing.lg) {
            ForEach(0..<5, id: \.self) { index in
                SkeletonTransactionRow()
                    .opacity(1.0 - Double(index) * 0.15)
            }
        }
        .padding(HawalaTheme.Spacing.lg)
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: HawalaTheme.Spacing.lg) {
            Spacer()
            
            Image(systemName: searchText.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(HawalaTheme.Colors.textTertiary)
            
            Text(searchText.isEmpty ? "No Transactions Yet" : "No Results Found")
                .font(HawalaTheme.Typography.h3)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
            
            Text(searchText.isEmpty
                ? "Your transaction history will appear here once you start transacting."
                : "Try adjusting your search or filters."
            )
                .font(HawalaTheme.Typography.body)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            
            if !searchText.isEmpty {
                Button("Clear Filters") {
                    searchText = ""
                    selectedFilter = .all
                    selectedChain = nil
                    dateRange = .all
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
        }
        .padding(HawalaTheme.Spacing.xxl)
    }
    
    // MARK: - Helpers
    private func refreshHistory() {
        // This would be called with actual targets from the parent view
        ToastManager.shared.info("Refreshing", message: "Fetching transaction history...")
    }
    
    private func groupTransactionsByDate(_ transactions: [TransactionEntry]) -> [String: [TransactionEntry]] {
        let calendar = Calendar.current
        let now = Date()
        
        return Dictionary(grouping: transactions) { transaction in
            guard let date = transaction.timestamp else { return "Unknown" }
            
            if calendar.isDateInToday(date) {
                return "Today"
            } else if calendar.isDateInYesterday(date) {
                return "Yesterday"
            } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
                return "This Week"
            } else if calendar.isDate(date, equalTo: now, toGranularity: .month) {
                return "This Month"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM yyyy"
                return formatter.string(from: date)
            }
        }
    }
    
    private func chainDisplayName(_ chainId: String) -> String {
        switch chainId {
        case "bitcoin": return "Bitcoin"
        case "bitcoin-testnet": return "Bitcoin Testnet"
        case "ethereum": return "Ethereum"
        case "ethereum-sepolia": return "Ethereum Sepolia"
        case "litecoin": return "Litecoin"
        case "solana": return "Solana"
        case "xrp": return "XRP"
        case "bnb": return "BNB Chain"
        case "monero": return "Monero"
        default: return chainId.capitalized
        }
    }
}

// MARK: - Supporting Views

struct FilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(HawalaTheme.Typography.caption)
            }
            .foregroundColor(isSelected ? .white : HawalaTheme.Colors.textSecondary)
            .padding(.horizontal, HawalaTheme.Spacing.md)
            .padding(.vertical, HawalaTheme.Spacing.sm)
            .background(
                Capsule()
                    .fill(isSelected ? HawalaTheme.Colors.accent : (isHovered ? HawalaTheme.Colors.backgroundHover : HawalaTheme.Colors.backgroundSecondary))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct StatBadge: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Text(value)
                .font(HawalaTheme.Typography.body)
                .fontWeight(.semibold)
                .foregroundColor(color)
            
            Text(title)
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
        }
        .padding(.horizontal, HawalaTheme.Spacing.sm)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
}

struct TransactionRowView: View {
    let transaction: TransactionEntry
    
    @State private var isHovered = false
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack(spacing: HawalaTheme.Spacing.md) {
                    // Type icon
                    ZStack {
                        Circle()
                            .fill(typeColor.opacity(0.15))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: typeIcon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(typeColor)
                    }
                    
                    // Details
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(typeLabel)
                                .font(HawalaTheme.Typography.body)
                                .fontWeight(.medium)
                                .foregroundColor(HawalaTheme.Colors.textPrimary)
                            
                            // Chain badge
                            Text(chainBadge)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(HawalaTheme.Colors.textTertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(HawalaTheme.Colors.backgroundTertiary)
                                .clipShape(Capsule())
                        }
                    }
                    
                    Spacer()
                    
                    // Amount and status
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(transaction.type == .receive ? "+" : "-")
                            Text(transaction.formattedAmount)
                        }
                        .font(HawalaTheme.Typography.body)
                        .fontWeight(.medium)
                        .foregroundColor(transaction.type == .receive ? HawalaTheme.Colors.success : HawalaTheme.Colors.textPrimary)
                        
                        HStack(spacing: 4) {
                            statusIndicator
                            Text(transaction.formattedTimestamp)
                                .font(HawalaTheme.Typography.caption)
                                .foregroundColor(HawalaTheme.Colors.textTertiary)
                        }
                    }
                    
                    // Expand indicator
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(HawalaTheme.Spacing.md)
                .background(isHovered ? HawalaTheme.Colors.backgroundHover : Color.clear)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            
            // Expanded details
            if isExpanded {
                expandedDetails
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    // MARK: - Expanded Details
    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
            DetailRow(label: "Transaction Hash", value: transaction.txHash, isCopyable: true)
            
            if let fee = transaction.formattedFee {
                DetailRow(label: "Network Fee", value: fee, isCopyable: false)
            }
            
            if let timestamp = transaction.timestamp {
                DetailRow(label: "Date & Time", value: timestamp.formatted(date: .long, time: .shortened), isCopyable: false)
            }
            
            // Explorer link
            if let explorerURL = transaction.explorerURL {
                Link(destination: explorerURL) {
                    HStack(spacing: 4) {
                        Image(systemName: "safari")
                        Text("View in Explorer")
                    }
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.accent)
                }
                .padding(.top, HawalaTheme.Spacing.xs)
            }
        }
        .padding(HawalaTheme.Spacing.md)
        .padding(.leading, 56) // Align with content after icon
        .background(HawalaTheme.Colors.backgroundTertiary.opacity(0.5))
    }
    
    // MARK: - Computed Properties
    private var typeColor: Color {
        switch transaction.type {
        case .receive: return HawalaTheme.Colors.success
        case .send: return HawalaTheme.Colors.warning
        case .swap: return HawalaTheme.Colors.info
        case .stake, .unstake: return HawalaTheme.Colors.accent
        case .unknown: return HawalaTheme.Colors.textSecondary
        }
    }
    
    private var typeIcon: String {
        switch transaction.type {
        case .receive: return "arrow.down.left"
        case .send: return "arrow.up.right"
        case .swap: return "arrow.left.arrow.right"
        case .stake: return "lock.fill"
        case .unstake: return "lock.open.fill"
        case .unknown: return "questionmark.circle"
        }
    }
    
    private var typeLabel: String {
        switch transaction.type {
        case .receive: return "Received"
        case .send: return "Sent"
        case .swap: return "Swap"
        case .stake: return "Staked"
        case .unstake: return "Unstaked"
        case .unknown: return "Transaction"
        }
    }
    
    private var chainBadge: String {
        switch transaction.chainId {
        case "bitcoin", "bitcoin-testnet": return "BTC"
        case "ethereum", "ethereum-sepolia": return "ETH"
        case "litecoin": return "LTC"
        case "solana": return "SOL"
        case "xrp": return "XRP"
        case "bnb": return "BNB"
        case "monero": return "XMR"
        default: return transaction.chainId.uppercased()
        }
    }
    
    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 6, height: 6)
    }
    
    private var statusColor: Color {
        switch transaction.status {
        case .confirmed: return HawalaTheme.Colors.success
        case .pending: return HawalaTheme.Colors.warning
        case .failed: return HawalaTheme.Colors.error
        }
    }
    
    private func truncateAddress(_ address: String) -> String {
        guard address.count > 16 else { return address }
        return "\(address.prefix(8))...\(address.suffix(6))"
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Unknown" }
        
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        } else {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    let isCopyable: Bool
    
    @State private var showCopied = false
    
    var body: some View {
        HStack {
            Text(label)
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
            
            Spacer()
            
            Text(isCopyable && value.count > 20 ? truncate(value) : value)
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
                .lineLimit(1)
            
            if isCopyable {
                Button(action: copyValue) {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundColor(showCopied ? HawalaTheme.Colors.success : HawalaTheme.Colors.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func truncate(_ string: String) -> String {
        guard string.count > 24 else { return string }
        return "\(string.prefix(12))...\(string.suffix(8))"
    }
    
    private func copyValue() {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
        
        showCopied = true
        ToastManager.shared.copied()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopied = false
        }
    }
}

#Preview {
    TransactionHistoryView(availableChains: ["bitcoin", "ethereum", "solana"])
        .frame(width: 600, height: 800)
        .background(HawalaTheme.Colors.background)
}
