import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Transaction History View

struct TransactionHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = TransactionHistoryViewModel()
    
    @State private var selectedFilter: TransactionFilter = .all
    @State private var selectedTransaction: TransactionDisplayItem?
    @State private var showingDetail = false
    @State private var appearAnimation = false
    
    var body: some View {
        ZStack {
            // Background
            HawalaTheme.Colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                historyHeader
                
                // Filter Pills
                filterSection
                
                // Content
                if viewModel.isLoading && viewModel.transactions.isEmpty {
                    loadingView
                } else if filteredTransactions.isEmpty {
                    emptyStateView
                } else {
                    transactionList
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(HawalaTheme.Animation.spring) {
                appearAnimation = true
            }
            viewModel.loadTransactions()
        }
        .sheet(item: $selectedTransaction) { transaction in
            TransactionDetailViewModern(transaction: transaction)
                .frame(minWidth: 400, minHeight: 500)
        }
    }
    
    // MARK: - Header
    
    private var historyHeader: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Text("Transaction History")
                .font(HawalaTheme.Typography.h3)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
            
            Spacer()
            
            // Refresh Button
            Button(action: { viewModel.refresh() }) {
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(HawalaTheme.Colors.accent)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .frame(width: 32, height: 32)
        }
        .padding(.horizontal, HawalaTheme.Spacing.lg)
        .padding(.vertical, HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.background)
    }
    
    // MARK: - Filter Section
    
    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HawalaTheme.Spacing.sm) {
                ForEach(TransactionFilter.allCases) { filter in
                    FilterPill(
                        filter: filter,
                        count: countForFilter(filter),
                        isSelected: selectedFilter == filter,
                        action: { selectedFilter = filter }
                    )
                }
            }
            .padding(.horizontal, HawalaTheme.Spacing.lg)
        }
        .padding(.vertical, HawalaTheme.Spacing.sm)
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 10)
    }
    
    // MARK: - Transaction List
    
    private var transactionList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: HawalaTheme.Spacing.sm) {
                // Group by date
                ForEach(groupedTransactions.keys.sorted().reversed(), id: \.self) { date in
                    if let transactions = groupedTransactions[date] {
                        Section {
                            ForEach(transactions) { transaction in
                                TransactionRowView(transaction: transaction)
                                    .onTapGesture {
                                        selectedTransaction = transaction
                                    }
                            }
                        } header: {
                            HStack {
                                Text(formatSectionDate(date))
                                    .font(HawalaTheme.Typography.label)
                                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                                    .tracking(1)
                                Spacer()
                            }
                            .padding(.horizontal, HawalaTheme.Spacing.lg)
                            .padding(.top, HawalaTheme.Spacing.md)
                            .padding(.bottom, HawalaTheme.Spacing.xs)
                        }
                    }
                }
            }
            .padding(.bottom, HawalaTheme.Spacing.xxl)
        }
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
        .animation(HawalaTheme.Animation.spring.delay(0.1), value: appearAnimation)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(HawalaTheme.Colors.accent)
            
            Text("Loading transactions...")
                .font(HawalaTheme.Typography.body)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: HawalaTheme.Spacing.lg) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(HawalaTheme.Colors.backgroundTertiary)
                    .frame(width: 100, height: 100)
                
                Image(systemName: emptyStateIcon)
                    .font(.system(size: 40))
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            
            VStack(spacing: HawalaTheme.Spacing.sm) {
                Text(emptyStateTitle)
                    .font(HawalaTheme.Typography.h3)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text(emptyStateMessage)
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .padding(HawalaTheme.Spacing.xl)
        .opacity(appearAnimation ? 1 : 0)
        .animation(HawalaTheme.Animation.spring.delay(0.2), value: appearAnimation)
    }
    
    // MARK: - Computed Properties
    
    private var filteredTransactions: [TransactionDisplayItem] {
        switch selectedFilter {
        case .all:
            return viewModel.transactions
        case .pending:
            return viewModel.transactions.filter { $0.status == .pending }
        case .sent:
            return viewModel.transactions.filter { $0.type == .send }
        case .received:
            return viewModel.transactions.filter { $0.type == .receive }
        }
    }
    
    private var groupedTransactions: [Date: [TransactionDisplayItem]] {
        let calendar = Calendar.current
        return Dictionary(grouping: filteredTransactions) { transaction in
            calendar.startOfDay(for: transaction.timestamp ?? Date())
        }
    }
    
    private func countForFilter(_ filter: TransactionFilter) -> Int {
        switch filter {
        case .all: return viewModel.transactions.count
        case .pending: return viewModel.transactions.filter { $0.status == .pending }.count
        case .sent: return viewModel.transactions.filter { $0.type == .send }.count
        case .received: return viewModel.transactions.filter { $0.type == .receive }.count
        }
    }
    
    private var emptyStateIcon: String {
        switch selectedFilter {
        case .all: return "doc.text.magnifyingglass"
        case .pending: return "clock"
        case .sent: return "arrow.up.circle"
        case .received: return "arrow.down.circle"
        }
    }
    
    private var emptyStateTitle: String {
        switch selectedFilter {
        case .all: return "No Transactions"
        case .pending: return "No Pending"
        case .sent: return "No Sent"
        case .received: return "No Received"
        }
    }
    
    private var emptyStateMessage: String {
        switch selectedFilter {
        case .all: return "Your transaction history will appear here once you send or receive crypto."
        case .pending: return "You don't have any pending transactions."
        case .sent: return "You haven't sent any transactions yet."
        case .received: return "You haven't received any transactions yet."
        }
    }
    
    private func formatSectionDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "TODAY"
        } else if calendar.isDateInYesterday(date) {
            return "YESTERDAY"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM d, yyyy"
            return formatter.string(from: date).uppercased()
        }
    }
}

// MARK: - Transaction Filter

enum TransactionFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case pending = "Pending"
    case sent = "Sent"
    case received = "Received"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .all: return "list.bullet"
        case .pending: return "clock"
        case .sent: return "arrow.up"
        case .received: return "arrow.down"
        }
    }
}

// MARK: - Filter Pill

struct FilterPill: View {
    let filter: TransactionFilter
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: filter.icon)
                    .font(.system(size: 12, weight: .medium))
                
                Text(filter.rawValue)
                    .font(HawalaTheme.Typography.captionBold)
                
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            isSelected
                                ? Color.white.opacity(0.2)
                                : HawalaTheme.Colors.backgroundSecondary
                        )
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, HawalaTheme.Spacing.md)
            .padding(.vertical, HawalaTheme.Spacing.sm)
            .background(isSelected ? HawalaTheme.Colors.accent : HawalaTheme.Colors.backgroundTertiary)
            .foregroundColor(isSelected ? .white : HawalaTheme.Colors.textSecondary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Transaction Row View

struct TransactionRowView: View {
    let transaction: TransactionDisplayItem
    var onSpeedUp: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil
    var onViewExplorer: (() -> Void)? = nil
    
    /// Whether this transaction can be sped up/cancelled
    private var canSpeedUp: Bool {
        guard transaction.status == .pending else { return false }
        // Bitcoin/Litecoin: RBF enabled transactions can be replaced
        // Ethereum: pending transactions can be replaced with higher gas
        switch transaction.chainId {
        case "bitcoin", "bitcoin-testnet", "litecoin":
            return true // Assume RBF enabled
        case "ethereum", "ethereum-sepolia", "bnb":
            return true // Can always replace pending ETH
        default:
            return false
        }
    }
    
    var body: some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconBackgroundColor)
                    .frame(width: 44, height: 44)
                
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            
            // Details
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(transaction.title)
                        .font(HawalaTheme.Typography.body)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    
                    Spacer()
                    
                    Text(amountText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(amountColor)
                }
                
                HStack {
                    // Chain badge
                    HStack(spacing: 4) {
                        Circle()
                            .fill(HawalaTheme.Colors.forChain(transaction.chainId))
                            .frame(width: 6, height: 6)
                        Text(transaction.chainName)
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                    }
                    
                    Text("•")
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                    
                    Text(timeText)
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                    
                    Spacer()
                    
                    // Status badge
                    statusBadge
                }
                
                // RBF Action buttons for pending sent transactions
                if canSpeedUp && transaction.type == .send {
                    HStack(spacing: 8) {
                        Button {
                            onSpeedUp?()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 10))
                                Text("Speed Up")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            onCancel?()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                Text("Cancel")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.15))
                            .foregroundColor(.red)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                    }
                    .padding(.top, 6)
                }
            }
        }
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
        .padding(.horizontal, HawalaTheme.Spacing.lg)
        .contextMenu {
            if let explorer = onViewExplorer {
                Button {
                    explorer()
                } label: {
                    Label("View on Explorer", systemImage: "arrow.up.right.square")
                }
            }
            
            if canSpeedUp && transaction.type == .send {
                Divider()
                
                Button {
                    onSpeedUp?()
                } label: {
                    Label("Speed Up", systemImage: "bolt.fill")
                }
                
                Button(role: .destructive) {
                    onCancel?()
                } label: {
                    Label("Cancel Transaction", systemImage: "xmark.circle.fill")
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var iconName: String {
        switch transaction.type {
        case .send: return "arrow.up.right"
        case .receive: return "arrow.down.left"
        case .unknown: return "questionmark"
        }
    }
    
    private var iconColor: Color {
        switch transaction.type {
        case .send: return HawalaTheme.Colors.error
        case .receive: return HawalaTheme.Colors.success
        case .unknown: return HawalaTheme.Colors.textTertiary
        }
    }
    
    private var iconBackgroundColor: Color {
        iconColor.opacity(0.15)
    }
    
    private var amountText: String {
        let sign = transaction.type == .receive ? "+" : "-"
        return "\(sign)\(transaction.formattedAmount) \(transaction.symbol)"
    }
    
    private var amountColor: Color {
        switch transaction.type {
        case .receive: return HawalaTheme.Colors.success
        case .send: return HawalaTheme.Colors.textPrimary
        case .unknown: return HawalaTheme.Colors.textSecondary
        }
    }
    
    private var timeText: String {
        guard let timestamp = transaction.timestamp else { return "Pending" }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            
            Text(statusText)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(statusColor.opacity(0.15))
        .clipShape(Capsule())
    }
    
    private var statusColor: Color {
        switch transaction.status {
        case .pending: return HawalaTheme.Colors.warning
        case .confirmed: return HawalaTheme.Colors.success
        case .failed: return HawalaTheme.Colors.error
        }
    }
    
    private var statusText: String {
        switch transaction.status {
        case .pending: return "Pending"
        case .confirmed: return transaction.confirmations > 0 ? "\(transaction.confirmations) conf" : "Confirmed"
        case .failed: return "Failed"
        }
    }
}

// MARK: - Transaction Display Item

struct TransactionDisplayItem: Identifiable {
    let id: String
    let txHash: String
    let chainId: String
    let chainName: String
    let type: TransactionType
    let status: TransactionStatus
    let amount: Double
    let symbol: String
    let fromAddress: String?
    let toAddress: String?
    let fee: Double?
    let timestamp: Date?
    let confirmations: Int
    let blockHeight: Int?
    let note: String?
    
    var formattedAmount: String {
        if amount < 0.0001 {
            return String(format: "%.8f", amount)
        } else if amount < 0.01 {
            return String(format: "%.6f", amount)
        } else if amount < 1 {
            return String(format: "%.4f", amount)
        } else {
            return String(format: "%.4f", amount)
        }
    }
    
    var title: String {
        switch type {
        case .send:
            if let to = toAddress {
                return "Sent to \(truncateAddress(to))"
            }
            return "Sent"
        case .receive:
            if let from = fromAddress {
                return "Received from \(truncateAddress(from))"
            }
            return "Received"
        case .unknown:
            return "Transaction"
        }
    }
    
    private func truncateAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
    
    enum TransactionType {
        case send
        case receive
        case unknown
    }
    
    enum TransactionStatus {
        case pending
        case confirmed
        case failed
    }
}

// MARK: - Transaction History View Model

@MainActor
class TransactionHistoryViewModel: ObservableObject {
    @Published var transactions: [TransactionDisplayItem] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let transactionStore = TransactionStore.shared
    private let walletRepository = WalletRepository.shared
    
    func loadTransactions() {
        guard !isLoading else { return }
        isLoading = true
        
        Task {
            do {
                // For demo, create some mock transactions
                // In production, fetch from TransactionStore
                let mockTransactions = createMockTransactions()
                
                await MainActor.run {
                    self.transactions = mockTransactions
                    self.isLoading = false
                }
            }
        }
    }
    
    func refresh() {
        transactions = []
        loadTransactions()
    }
    
    private func createMockTransactions() -> [TransactionDisplayItem] {
        // Return empty for now - real transactions will come from database
        // This allows the empty state to show
        return []
    }
}
