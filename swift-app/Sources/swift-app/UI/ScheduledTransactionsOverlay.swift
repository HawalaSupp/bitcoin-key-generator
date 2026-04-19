import SwiftUI

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Scheduled Transactions Overlay
// Unified transaction scheduling hub.
// Four sections: Upcoming · All · Create · Settings.
// Wired to TransactionScheduler.shared — zero mock data.
// Monumental. Monochrome. Schedule-grade.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct ScheduledTransactionsOverlay: View {
    @Binding var isPresented: Bool
    var onBackToSettings: (() -> Void)? = nil
    var initialTab: STTab? = nil

    // ── Tab ──
    enum STTab: String, CaseIterable {
        case upcoming = "UPCOMING"
        case all      = "ALL"
        case create   = "CREATE"
        case settings = "SETTINGS"
    }

    @State private var selectedTab: STTab = .upcoming

    // ── Real manager ──
    @ObservedObject private var scheduler = TransactionScheduler.shared

    // ── ALL tab state ──
    @State private var allSearch = ""
    @State private var allStatusFilter: StatusFilter = .all
    @State private var allChainFilter: SchedulableChain? = nil
    @State private var expandedTransactionId: UUID? = nil
    @State private var editLabel = ""
    @State private var editNotes = ""
    @State private var showDeleteConfirm = false
    @State private var deleteTarget: ScheduledTransaction? = nil

    enum StatusFilter: String, CaseIterable {
        case all       = "All"
        case active    = "Active"
        case recurring = "Recurring"
        case completed = "Completed"
        case failed    = "Failed"
    }

    // ── CREATE tab state ──
    @State private var createChain: SchedulableChain = .bitcoin
    @State private var createAddress = ""
    @State private var createAmount = ""
    @State private var createLabel = ""
    @State private var createMemo = ""
    @State private var createDate = Date().addingTimeInterval(3600)
    @State private var createFrequency: RecurrenceFrequency = .once
    @State private var createHasEndDate = false
    @State private var createEndDate = Date().addingTimeInterval(86400 * 30)
    @State private var createMaxOccurrences = ""
    @State private var createRequireConfirmation = false
    @State private var createNotifyBefore = true
    @State private var createError: String? = nil
    @State private var createInProgress = false

    // ── Animation ──
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92
    @State private var silkPhase: CGFloat = 0

    // ── Hover ──
    @State private var closeHovered = false
    @State private var backHovered = false

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Body
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    var body: some View {
        ZStack {
            backdrop
            cardContainer
        }
        .background(
            EscapeKeyHandler(isPresented: $isPresented, onEscape: dismissOverlay)
        )
        .onAppear {
            if let tab = initialTab { selectedTab = tab }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                cardScale = 1
                contentOpacity = 1
            }
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                silkPhase = 1
            }
        }
        .alert("Delete Transaction?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { deleteTarget = nil }
            Button("Delete", role: .destructive) {
                if let tx = deleteTarget {
                    scheduler.deleteTransaction(tx)
                    deleteTarget = nil
                    expandedTransactionId = nil
                }
            }
        } message: {
            Text("This scheduled transaction will be permanently removed.")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Backdrop
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var backdrop: some View {
        Color.black.opacity(0.75)
            .ignoresSafeArea()
            .onTapGesture { dismissOverlay() }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Card
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var cardContainer: some View {
        VStack(spacing: 0) {
            headerBar
            tabBar
            tabContent
        }
        .frame(width: 700, height: 650)
        .background(cardBg)
        .overlay(cardStroke)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.5), radius: 50, y: 25)
        .scaleEffect(cardScale)
        .opacity(contentOpacity)
    }

    private var cardBg: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.07)
            LinearGradient(
                colors: [.clear, Color.white.opacity(0.015), .clear],
                startPoint: UnitPoint(x: silkPhase - 0.3, y: 0),
                endPoint: UnitPoint(x: silkPhase + 0.3, y: 1)
            )
        }
    }

    private var cardStroke: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.10), Color.white.opacity(0.03)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ), lineWidth: 1
            )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Header
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var headerBar: some View {
        HStack {
            if onBackToSettings != nil {
                Button {
                    dismissOverlay()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onBackToSettings?()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Settings")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(Color.white.opacity(backHovered ? 0.7 : 0.3))
                }
                .buttonStyle(.plain)
                .onHover { backHovered = $0 }
            }

            Spacer()

            HStack(spacing: 6) {
                if scheduler.isProcessing {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 14, height: 14)
                }
                Text("Scheduled Transactions")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
            }

            Spacer()

            Button { dismissOverlay() } label: {
                Circle()
                    .fill(Color.white.opacity(closeHovered ? 0.12 : 0.06))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.4))
                    )
            }
            .buttonStyle(.plain)
            .onHover { closeHovered = $0 }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Tab Bar
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(STTab.allCases, id: \.self) { tab in
                stTabButton(tab)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private func stTabButton(_ tab: STTab) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selectedTab = tab
            }
        } label: {
            Text(tab.rawValue)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.25))
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(
                    selectedTab == tab
                        ? Color.white.opacity(0.08)
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Tab Content
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    @ViewBuilder
    private var tabContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                switch selectedTab {
                case .upcoming:  upcomingTab
                case .all:       allTab
                case .create:    createTab
                case .settings:  settingsTab
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – UPCOMING TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var upcomingTab: some View {
        VStack(spacing: 16) {
            upcomingStatsRow
            upcomingReadySection
            upcomingListSection
        }
    }

    private var upcomingStatsRow: some View {
        let stats = scheduler.getStatistics()
        return HStack(spacing: 8) {
            statBox("Active", "\(stats.activeCount)", .white)
            statBox("Recurring", "\(stats.recurringCount)", .purple)
            statBox("Completed", "\(stats.completedCount)", .green)
            statBox("Failed", "\(stats.failedCount)", .red)
            statBox("Success", stats.successRatePercentage, .cyan)
        }
    }

    private func statBox(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(color.opacity(0.9))
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.25))
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.04), lineWidth: 1)
        )
    }

    private var upcomingReadySection: some View {
        let ready = scheduler.getReadyTransactions()
        return Group {
            if !ready.isEmpty {
                VStack(spacing: 8) {
                    HStack {
                        Text("READY TO EXECUTE")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(.white.opacity(0.25))
                        Spacer()
                        Button {
                            for tx in ready { Task { await scheduler.executeNow(tx) } }
                        } label: {
                            Text("Execute All (\(ready.count))")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.orange.opacity(0.9))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(ready) { tx in
                        readyCard(tx)
                    }
                }
            }
        }
    }

    private func readyCard(_ tx: ScheduledTransaction) -> some View {
        HStack(spacing: 10) {
            Image(systemName: tx.chain.icon)
                .font(.system(size: 14))
                .foregroundColor(chainColor(for: tx.chain))
                .frame(width: 28, height: 28)
                .background(chainColor(for: tx.chain).opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(tx.label ?? tx.recipientAddress)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
                Text("\(tx.amount) \(tx.chain.rawValue)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }

            Spacer()

            if scheduler.isProcessing {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 24, height: 24)
            } else {
                Button {
                    Task { await scheduler.executeNow(tx) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8))
                        Text("Execute")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.1), lineWidth: 1)
        )
    }

    private var upcomingListSection: some View {
        let upcoming = scheduler.getUpcomingTransactions(limit: 8)
        return VStack(spacing: 8) {
            HStack {
                Text("UPCOMING")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.25))
                Spacer()
                if !upcoming.isEmpty {
                    Text("\(upcoming.count)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.2))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }

            if upcoming.isEmpty {
                emptyState(
                    icon: "calendar.badge.clock",
                    title: "No upcoming transactions",
                    subtitle: "Schedule a transaction from the Create tab."
                )
            } else {
                ForEach(upcoming) { tx in
                    upcomingRow(tx)
                }
            }
        }
    }

    private func upcomingRow(_ tx: ScheduledTransaction) -> some View {
        HStack(spacing: 10) {
            Image(systemName: tx.chain.icon)
                .font(.system(size: 12))
                .foregroundColor(chainColor(for: tx.chain))
                .frame(width: 24, height: 24)
                .background(chainColor(for: tx.chain).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tx.label ?? shortenAddress(tx.recipientAddress))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                    if tx.isRecurring {
                        Image(systemName: "repeat")
                            .font(.system(size: 8))
                            .foregroundColor(.purple.opacity(0.5))
                    }
                }
                Text("\(tx.amount) \(tx.chain.rawValue)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
            }

            Spacer()

            if let nextDate = tx.nextExecutionDate {
                Text(nextDate, style: .relative)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.25))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func shortenAddress(_ addr: String) -> String {
        guard addr.count > 14 else { return addr }
        return String(addr.prefix(6)) + "..." + String(addr.suffix(4))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – ALL TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var allTab: some View {
        VStack(spacing: 12) {
            allFilterBar
            allTransactionsList
        }
    }

    // ── Filter Bar ──

    private var allFilterBar: some View {
        VStack(spacing: 8) {
            // Status pills
            HStack(spacing: 4) {
                ForEach(StatusFilter.allCases, id: \.self) { filter in
                    filterPill(filter.rawValue, isSelected: allStatusFilter == filter) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            allStatusFilter = filter
                        }
                    }
                }
                Spacer()
            }

            HStack(spacing: 8) {
                // Chain filter
                chainFilterMenu

                // Search
                searchField(text: $allSearch, placeholder: "Search by address, label...")
            }
        }
    }

    private func filterPill(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isSelected ? .white : .white.opacity(0.25))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.white.opacity(0.10) : Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var chainFilterMenu: some View {
        Menu {
            Button("All Chains") { allChainFilter = nil }
            Divider()
            ForEach(SchedulableChain.allCases) { chain in
                Button {
                    allChainFilter = chain
                } label: {
                    Label(chain.displayName, systemImage: chain.icon)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: allChainFilter?.icon ?? "link")
                    .font(.system(size: 10))
                Text(allChainFilter?.displayName ?? "All Chains")
                    .font(.system(size: 10, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundColor(.white.opacity(0.35))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // ── Transaction List ──

    private var allTransactionsList: some View {
        let txs = filteredTransactions
        return Group {
            if txs.isEmpty {
                emptyState(
                    icon: "tray",
                    title: "No transactions found",
                    subtitle: allStatusFilter == .all && allChainFilter == nil && allSearch.isEmpty
                        ? "Schedule your first transaction from the Create tab."
                        : "Try adjusting your filters."
                )
            } else {
                ForEach(txs) { tx in
                    txCard(tx)
                }
            }
        }
    }

    // ── Transaction Card ──

    private func txCard(_ tx: ScheduledTransaction) -> some View {
        let isExpanded = expandedTransactionId == tx.id
        return VStack(spacing: 0) {
            txCardHeader(tx)
            if isExpanded {
                txCardDetail(tx)
            }
        }
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(isExpanded ? 0.08 : 0.04), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                if expandedTransactionId == tx.id {
                    expandedTransactionId = nil
                } else {
                    expandedTransactionId = tx.id
                    editLabel = tx.label ?? ""
                    editNotes = tx.notes ?? ""
                }
            }
        }
    }

    private func txCardHeader(_ tx: ScheduledTransaction) -> some View {
        HStack(spacing: 10) {
            // Chain icon
            Image(systemName: tx.chain.icon)
                .font(.system(size: 13))
                .foregroundColor(chainColor(for: tx.chain))
                .frame(width: 30, height: 30)
                .background(chainColor(for: tx.chain).opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            // Label + address
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tx.label ?? shortenAddress(tx.recipientAddress))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                    if tx.isRecurring {
                        Text(tx.frequency.rawValue)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.purple.opacity(0.6))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                }
                Text(shortenAddress(tx.recipientAddress))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
                    .lineLimit(1)
            }

            Spacer()

            // Amount
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(tx.amount)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                Text(tx.chain.rawValue)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.2))
            }

            // Status badge
            txStatusBadge(tx.status)
        }
        .padding(12)
    }

    private func txStatusBadge(_ status: ScheduledTransactionStatus) -> some View {
        let color = statusColor(for: status)
        return HStack(spacing: 3) {
            Image(systemName: status.icon)
                .font(.system(size: 7))
            Text(status.rawValue)
                .font(.system(size: 8, weight: .semibold))
        }
        .foregroundColor(color.opacity(0.8))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    // ── Card Detail (inline expansion) ──

    private func txCardDetail(_ tx: ScheduledTransaction) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.04))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 12) {
                txDetailInfo(tx)
                txDetailEditable(tx)
                txDetailHistory(tx)
                txDetailActions(tx)
            }
            .padding(12)
        }
    }

    private func txDetailInfo(_ tx: ScheduledTransaction) -> some View {
        VStack(spacing: 6) {
            detailRow("Recipient", tx.recipientAddress, monospaced: true)
            detailRow("Network", tx.chain.displayName)
            detailRow("Frequency", tx.frequency.rawValue)
            if let next = tx.nextExecutionDate, tx.isActive {
                detailRow("Next Execution", next.formatted(date: .abbreviated, time: .shortened))
            }
            if let end = tx.endDate {
                detailRow("End Date", end.formatted(date: .abbreviated, time: .omitted))
            }
            if let max = tx.maxOccurrences {
                detailRow("Occurrences", "\(tx.occurrencesCompleted)/\(max)")
            }
            if let memo = tx.memo, !memo.isEmpty {
                detailRow("Memo", memo)
            }
            detailRow("Created", tx.createdAt.formatted(date: .abbreviated, time: .shortened))
            if tx.retryCount > 0 {
                detailRow("Retries", "\(tx.retryCount)/\(tx.maxRetries)")
            }
        }
    }

    private func detailRow(_ title: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.25))
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.system(size: 10, design: monospaced ? .monospaced : .default))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }

    private func txDetailEditable(_ tx: ScheduledTransaction) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text("Label")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.25))
                    .frame(width: 90, alignment: .leading)
                TextField("Add label", text: $editLabel)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(6)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                Button("Save") {
                    var updated = tx
                    updated.label = editLabel.isEmpty ? nil : editLabel
                    updated.notes = editNotes.isEmpty ? nil : editNotes
                    scheduler.updateTransaction(updated)
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.35))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                Text("Notes")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.25))
                    .frame(width: 90, alignment: .leading)
                TextField("Add notes", text: $editNotes)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(6)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
    }

    private func txDetailHistory(_ tx: ScheduledTransaction) -> some View {
        Group {
            if !tx.executionHistory.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("EXECUTION HISTORY")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.white.opacity(0.2))

                    ForEach(tx.executionHistory.suffix(10).reversed()) { record in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(record.status == .completed ? Color.green.opacity(0.6) : record.status == .skipped ? Color.yellow.opacity(0.5) : Color.red.opacity(0.6))
                                .frame(width: 6, height: 6)

                            Text(record.executedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.3))

                            Text(record.status.rawValue)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.4))

                            Spacer()

                            if let hash = record.txHash {
                                Text(String(hash.prefix(10)) + "...")
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.2))
                            }
                            if let err = record.errorMessage {
                                Text(err)
                                    .font(.system(size: 8))
                                    .foregroundColor(.red.opacity(0.5))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.02))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func txDetailActions(_ tx: ScheduledTransaction) -> some View {
        HStack(spacing: 6) {
            if tx.status == .ready {
                actionPill("Execute", icon: "play.fill", color: .white) {
                    Task { await scheduler.executeNow(tx) }
                }
            }
            if tx.status == .paused {
                actionPill("Resume", icon: "play", color: .white) {
                    scheduler.resumeTransaction(tx)
                }
            } else if tx.isActive && tx.status != .ready {
                actionPill("Pause", icon: "pause", color: .white) {
                    scheduler.pauseTransaction(tx)
                }
            }
            if tx.isRecurring && tx.isActive {
                actionPill("Skip", icon: "forward", color: .white) {
                    scheduler.skipNextOccurrence(tx)
                }
            }
            if tx.isActive {
                actionPill("Cancel", icon: "xmark", color: .white) {
                    scheduler.cancelTransaction(tx)
                }
            }

            Spacer()

            Button {
                deleteTarget = tx
                showDeleteConfirm = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "trash")
                        .font(.system(size: 9))
                    Text("Delete")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(.red.opacity(0.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func actionPill(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8))
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(color.opacity(0.5))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // ── Filtered Transactions ──

    private var filteredTransactions: [ScheduledTransaction] {
        var txs = scheduler.scheduledTransactions

        switch allStatusFilter {
        case .all:       break
        case .active:    txs = txs.filter { $0.isActive }
        case .recurring: txs = txs.filter { $0.isRecurring && $0.isActive }
        case .completed: txs = txs.filter { $0.status == .completed }
        case .failed:    txs = txs.filter { $0.status == .failed }
        }

        if let chain = allChainFilter {
            txs = txs.filter { $0.chain == chain }
        }

        if !allSearch.isEmpty {
            txs = txs.filter {
                $0.recipientAddress.localizedCaseInsensitiveContains(allSearch) ||
                $0.label?.localizedCaseInsensitiveContains(allSearch) == true ||
                $0.chain.displayName.localizedCaseInsensitiveContains(allSearch)
            }
        }

        return txs.sorted {
            ($0.nextExecutionDate ?? .distantFuture) < ($1.nextExecutionDate ?? .distantFuture)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – CREATE TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var createTab: some View {
        VStack(spacing: 16) {
            createNetworkSection
            createRecipientSection
            createScheduleSection
            createOptionsSection
            createSubmitSection
        }
    }

    private var createNetworkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NETWORK")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.white.opacity(0.25))

            HStack(spacing: 6) {
                ForEach(SchedulableChain.allCases) { chain in
                    let isSelected = createChain == chain
                    let isDisabled = chain == .xrp
                    Button {
                        if !isDisabled { createChain = chain }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: chain.icon)
                                .font(.system(size: 14))
                            Text(chain.displayName)
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(isDisabled ? .white.opacity(0.1) : isSelected ? .white.opacity(0.9) : .white.opacity(0.3))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isSelected ? chainColor(for: chain).opacity(0.12) : Color.white.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(isSelected ? chainColor(for: chain).opacity(0.2) : Color.white.opacity(0.04), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(isDisabled ? "XRP not yet supported for scheduled transactions" : chain.displayName)
                }
            }
        }
    }

    private var createRecipientSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DETAILS")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.white.opacity(0.25))

            formField("Recipient", text: $createAddress, placeholder: "Enter \(createChain.displayName) address", monospaced: true)
            HStack(spacing: 8) {
                formField("Amount", text: $createAmount, placeholder: "0.00")
                Text(createChain.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.25))
            }
            formField("Label", text: $createLabel, placeholder: "e.g., Rent Payment (optional)")
            formField("Memo", text: $createMemo, placeholder: "Optional memo")
        }
    }

    private var createScheduleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SCHEDULE")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.white.opacity(0.25))

            // Date picker
            HStack(spacing: 8) {
                Text("Execute on")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(width: 70, alignment: .leading)
                DatePicker("", selection: $createDate, in: Date()...)
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }

            // Frequency
            HStack(spacing: 8) {
                Text("Frequency")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(width: 70, alignment: .leading)
                Picker("", selection: $createFrequency) {
                    ForEach(RecurrenceFrequency.allCases) { freq in
                        HStack {
                            Image(systemName: freq.icon)
                            Text(freq.rawValue)
                        }
                        .tag(freq)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            // End conditions for recurring
            if createFrequency != .once {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Toggle("End date", isOn: $createHasEndDate)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.35))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    if createHasEndDate {
                        HStack(spacing: 8) {
                            Text("End on")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.3))
                                .frame(width: 70, alignment: .leading)
                            DatePicker("", selection: $createEndDate, in: createDate...)
                                .datePickerStyle(.compact)
                                .labelsHidden()
                        }
                    } else {
                        formField("Max runs", text: $createMaxOccurrences, placeholder: "Unlimited")
                    }
                }
                .padding(10)
                .background(Color.purple.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.purple.opacity(0.08), lineWidth: 1)
                )
            }
        }
    }

    private var createOptionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OPTIONS")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.white.opacity(0.25))

            HStack {
                Toggle("Require manual confirmation", isOn: $createRequireConfirmation)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            HStack {
                Toggle("Notify before execution", isOn: $createNotifyBefore)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
    }

    private var createSubmitSection: some View {
        VStack(spacing: 8) {
            if let error = createError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button {
                    resetCreateForm()
                } label: {
                    Text("Reset")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: submitCreate) {
                    HStack(spacing: 5) {
                        if createInProgress {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 11))
                        }
                        Text("Schedule")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white.opacity(createAddress.isEmpty || createAmount.isEmpty ? 0.2 : 0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(createAddress.isEmpty || createAmount.isEmpty ? 0.04 : 0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(createAddress.isEmpty || createAmount.isEmpty || createInProgress)
            }
        }
    }

    private func submitCreate() {
        guard let amountDecimal = Decimal(string: createAmount) else {
            createError = "Invalid amount"
            return
        }

        createInProgress = true
        createError = nil

        do {
            _ = try scheduler.scheduleTransaction(
                chain: createChain,
                recipientAddress: createAddress,
                amount: amountDecimal,
                scheduledDate: createDate,
                frequency: createFrequency,
                endDate: createHasEndDate ? createEndDate : nil,
                maxOccurrences: Int(createMaxOccurrences),
                label: createLabel.isEmpty ? nil : createLabel,
                memo: createMemo.isEmpty ? nil : createMemo,
                requireConfirmation: createRequireConfirmation,
                notifyBefore: createNotifyBefore
            )
            resetCreateForm()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selectedTab = .all
            }
        } catch {
            createError = error.localizedDescription
        }

        createInProgress = false
    }

    private func resetCreateForm() {
        createChain = .bitcoin
        createAddress = ""
        createAmount = ""
        createLabel = ""
        createMemo = ""
        createDate = Date().addingTimeInterval(3600)
        createFrequency = .once
        createHasEndDate = false
        createEndDate = Date().addingTimeInterval(86400 * 30)
        createMaxOccurrences = ""
        createRequireConfirmation = false
        createNotifyBefore = true
        createError = nil
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – SETTINGS TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var settingsTab: some View {
        VStack(spacing: 12) {
            Text("EXECUTION")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.white.opacity(0.25))
                .frame(maxWidth: .infinity, alignment: .leading)

            settingsRow(
                icon: "play.circle",
                title: "Auto-execute when ready",
                subtitle: "Automatically execute transactions when their scheduled time arrives."
            ) {
                Toggle("", isOn: $scheduler.autoExecuteEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            settingsRow(
                icon: "faceid",
                title: "Require unlock for execution",
                subtitle: "Biometric authentication required before executing any transaction."
            ) {
                Toggle("", isOn: $scheduler.requireUnlockForExecution)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1).padding(.vertical, 4)

            Text("NOTIFICATIONS")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.white.opacity(0.25))
                .frame(maxWidth: .infinity, alignment: .leading)

            settingsRow(
                icon: "bell",
                title: "Notification lead time",
                subtitle: "How far in advance to notify before execution."
            ) {
                Picker("", selection: $scheduler.defaultNotificationLeadTime) {
                    Text("1 min").tag(TimeInterval(60))
                    Text("5 min").tag(TimeInterval(300))
                    Text("15 min").tag(TimeInterval(900))
                    Text("30 min").tag(TimeInterval(1800))
                    Text("1 hour").tag(TimeInterval(3600))
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }

            Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1).padding(.vertical, 4)

            Text("DISPLAY")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.white.opacity(0.25))
                .frame(maxWidth: .infinity, alignment: .leading)

            settingsRow(
                icon: "checkmark.circle",
                title: "Show completed transactions",
                subtitle: "Include completed and cancelled transactions in the All tab."
            ) {
                Toggle("", isOn: $scheduler.showCompletedTransactions)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1).padding(.vertical, 4)

            // Info section
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.15))
                Text("Scheduled transactions are checked every minute. When a transaction's time arrives, it will either execute automatically (if enabled) or move to the \"Ready\" state for manual execution.")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.2))
                    .lineSpacing(2)
            }
            .padding(10)
            .background(Color.white.opacity(0.02))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func settingsRow<Trailing: View>(icon: String, title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.25))
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.2))
                    .lineLimit(2)
            }
            Spacer()
            trailing()
        }
        .padding(10)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Helpers
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func dismissOverlay() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            cardScale = 0.95
            contentOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isPresented = false
        }
    }

    private func searchField(text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.2))
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(8)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.08))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.25))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.15))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
    }

    private func formField(_ label: String, text: Binding<String>, placeholder: String, monospaced: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.3))
                .frame(width: 70, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: monospaced ? .monospaced : .default))
                .foregroundColor(.white.opacity(0.7))
                .padding(8)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        }
    }

    private func chainColor(for chain: SchedulableChain) -> Color {
        switch chain {
        case .bitcoin:  return .orange
        case .ethereum: return .purple
        case .litecoin: return .gray
        case .solana:   return .cyan
        case .xrp:      return .blue
        }
    }

    private func statusColor(for status: ScheduledTransactionStatus) -> Color {
        switch status.color {
        case "blue":   return .blue
        case "orange": return .orange
        case "purple": return .purple
        case "green":  return .green
        case "red":    return .red
        case "gray":   return .gray
        case "yellow": return .yellow
        default:       return .gray
        }
    }
}
