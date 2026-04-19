import SwiftUI

// MARK: - Scheduled Transactions View
// Phase 5: Advanced Automation - Transaction Scheduling UI

struct ScheduledTransactionsView: View {
    @StateObject private var scheduler = TransactionScheduler.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedFilter: TransactionFilter = .all
    @State private var selectedChain: SchedulableChain?
    @State private var showCreateSheet = false
    @State private var showSettingsSheet = false
    @State private var selectedTransaction: ScheduledTransaction?
    @State private var searchText = ""
    
    enum TransactionFilter: String, CaseIterable {
        case all = "All"
        case active = "Active"
        case recurring = "Recurring"
        case completed = "Completed"
        case failed = "Failed"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            HSplitView {
                // Sidebar
                sidebarView
                    .frame(minWidth: 220, maxWidth: 280)
                
                // Main Content
                VStack(spacing: 0) {
                    // Toolbar
                    toolbarView
                    
                    Divider()
                    
                    // Transaction List
                    if filteredTransactions.isEmpty {
                        emptyStateView
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredTransactions) { transaction in
                                    ScheduledTransactionCard(transaction: transaction)
                                        .onTapGesture {
                                            selectedTransaction = transaction
                                        }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
        }
        .frame(minWidth: 950, minHeight: 650)
        .sheet(isPresented: $showCreateSheet) {
            CreateScheduledTransactionSheet()
        }
        .sheet(isPresented: $showSettingsSheet) {
            SchedulerSettingsSheet()
        }
        .sheet(item: $selectedTransaction) { transaction in
            ScheduledTransactionDetailSheet(transaction: transaction)
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Scheduled Transactions")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Automate recurring and future payments")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Processing Indicator
            if scheduler.isProcessing {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Processing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Actions
            Button(action: { showCreateSheet = true }) {
                Label("Schedule", systemImage: "calendar.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            
            Button(action: { showSettingsSheet = true }) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.bordered)
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    // MARK: - Sidebar
    
    private var sidebarView: some View {
        VStack(spacing: 0) {
            // Statistics
            VStack(alignment: .leading, spacing: 12) {
                Text("OVERVIEW")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                
                let stats = scheduler.getStatistics()
                
                HStack(spacing: 16) {
                    StatBox(title: "Active", value: "\(stats.activeCount)", color: .blue)
                    StatBox(title: "Recurring", value: "\(stats.recurringCount)", color: .purple)
                }
                .padding(.horizontal, 12)
                
                HStack(spacing: 16) {
                    StatBox(title: "Completed", value: "\(stats.completedCount)", color: .green)
                    StatBox(title: "Failed", value: "\(stats.failedCount)", color: .red)
                }
                .padding(.horizontal, 12)
                
                if stats.totalExecutions > 0 {
                    HStack {
                        Text("Success Rate")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(stats.successRatePercentage)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 12)
            
            Divider()
            
            // Filters
            VStack(alignment: .leading, spacing: 8) {
                Text("FILTER")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                
                ForEach(TransactionFilter.allCases, id: \.self) { filter in
                    SchedulerFilterRow(
                        title: filter.rawValue,
                        icon: filterIcon(for: filter),
                        count: filterCount(for: filter),
                        isSelected: selectedFilter == filter
                    )
                    .onTapGesture {
                        selectedFilter = filter
                    }
                }
            }
            .padding(.vertical, 12)
            
            Divider()
            
            // Chain Filter
            VStack(alignment: .leading, spacing: 8) {
                Text("CHAIN")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                
                SchedulerFilterRow(
                    title: "All Chains",
                    icon: "link",
                    count: scheduler.scheduledTransactions.count,
                    isSelected: selectedChain == nil
                )
                .onTapGesture {
                    selectedChain = nil
                }
                
                ForEach(SchedulableChain.allCases) { chain in
                    SchedulerFilterRow(
                        title: chain.displayName,
                        icon: chain.icon,
                        count: scheduler.getTransactions(for: chain).count,
                        isSelected: selectedChain == chain
                    )
                    .onTapGesture {
                        selectedChain = chain
                    }
                }
            }
            .padding(.vertical, 12)
            
            Spacer()
            
            // Upcoming
            VStack(alignment: .leading, spacing: 8) {
                Text("NEXT UP")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                
                let upcoming = scheduler.getUpcomingTransactions(limit: 3)
                
                if upcoming.isEmpty {
                    Text("No upcoming transactions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                } else {
                    ForEach(upcoming) { tx in
                        UpcomingRow(transaction: tx)
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Toolbar
    
    private var toolbarView: some View {
        HStack {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search transactions...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .frame(maxWidth: 300)
            
            Spacer()
            
            // Ready Count
            let readyCount = scheduler.getReadyTransactions().count
            if readyCount > 0 {
                Button(action: executeAllReady) {
                    Label("\(readyCount) Ready", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            
            // Sort
            Menu {
                Button("Date (Newest)") {}
                Button("Date (Oldest)") {}
                Button("Amount (High to Low)") {}
                Button("Amount (Low to High)") {}
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            
            Text("No Scheduled Transactions")
                .font(.headline)
            
            Text("Create automated payments that execute on a schedule or recurring basis.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 350)
            
            Button(action: { showCreateSheet = true }) {
                Label("Schedule Transaction", systemImage: "calendar.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            
            Spacer()
        }
    }
    
    // MARK: - Computed Properties
    
    private var filteredTransactions: [ScheduledTransaction] {
        var transactions = scheduler.scheduledTransactions
        
        // Filter by status
        switch selectedFilter {
        case .all:
            break
        case .active:
            transactions = transactions.filter { $0.isActive }
        case .recurring:
            transactions = transactions.filter { $0.isRecurring && $0.isActive }
        case .completed:
            transactions = transactions.filter { $0.status == .completed }
        case .failed:
            transactions = transactions.filter { $0.status == .failed }
        }
        
        // Filter by chain
        if let chain = selectedChain {
            transactions = transactions.filter { $0.chain == chain }
        }
        
        // Filter by search
        if !searchText.isEmpty {
            transactions = transactions.filter {
                $0.recipientAddress.localizedCaseInsensitiveContains(searchText) ||
                $0.label?.localizedCaseInsensitiveContains(searchText) == true ||
                $0.chain.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Sort by next execution date
        return transactions.sorted {
            ($0.nextExecutionDate ?? .distantFuture) < ($1.nextExecutionDate ?? .distantFuture)
        }
    }
    
    // MARK: - Helper Methods
    
    private func filterIcon(for filter: TransactionFilter) -> String {
        switch filter {
        case .all: return "tray.full"
        case .active: return "clock"
        case .recurring: return "repeat"
        case .completed: return "checkmark.circle"
        case .failed: return "xmark.circle"
        }
    }
    
    private func filterCount(for filter: TransactionFilter) -> Int {
        switch filter {
        case .all: return scheduler.scheduledTransactions.count
        case .active: return scheduler.scheduledTransactions.filter { $0.isActive }.count
        case .recurring: return scheduler.scheduledTransactions.filter { $0.isRecurring && $0.isActive }.count
        case .completed: return scheduler.scheduledTransactions.filter { $0.status == .completed }.count
        case .failed: return scheduler.scheduledTransactions.filter { $0.status == .failed }.count
        }
    }
    
    private func executeAllReady() {
        let ready = scheduler.getReadyTransactions()
        for transaction in ready {
            Task {
                await scheduler.executeNow(transaction)
            }
        }
    }
}

// MARK: - Supporting Views

struct StatBox: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct SchedulerFilterRow: View {
    let title: String
    let icon: String
    let count: Int
    let isSelected: Bool
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(isSelected ? .accentColor : .secondary)
            
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
            
            Spacer()
            
            Text("\(count)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(6)
        .padding(.horizontal, 8)
    }
}

struct UpcomingRow: View {
    let transaction: ScheduledTransaction
    
    var body: some View {
        HStack {
            Image(systemName: transaction.chain.icon)
                .foregroundColor(.orange)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("\(transaction.amount) \(transaction.chain.rawValue)")
                    .font(.caption)
                    .fontWeight(.medium)
                
                if let nextDate = transaction.nextExecutionDate {
                    Text(nextDate, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

struct ScheduledTransactionCard: View {
    let transaction: ScheduledTransaction
    @StateObject private var scheduler = TransactionScheduler.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                // Chain Icon
                Image(systemName: transaction.chain.icon)
                    .font(.title2)
                    .foregroundColor(chainColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    if let label = transaction.label {
                        Text(label)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    Text(transaction.recipientAddress)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Amount
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(transaction.amount)")
                        .font(.headline)
                    Text(transaction.chain.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // Schedule Info
            HStack {
                // Status Badge
                ScheduleStatusBadge(status: transaction.status)
                
                Spacer()
                
                // Frequency
                if transaction.isRecurring {
                    Label(transaction.frequency.rawValue, systemImage: "repeat")
                        .font(.caption)
                        .foregroundColor(.purple)
                }
                
                // Next Execution
                if let nextDate = transaction.nextExecutionDate, transaction.isActive {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(nextDate, style: .relative)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            
            // Execution History Summary
            if !transaction.executionHistory.isEmpty {
                HStack {
                    let completed = transaction.executionHistory.filter { $0.status == .completed }.count
                    let failed = transaction.executionHistory.filter { $0.status == .failed }.count
                    
                    Text("\(completed) completed")
                        .font(.caption)
                        .foregroundColor(.green)
                    
                    if failed > 0 {
                        Text("• \(failed) failed")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    
                    Spacer()
                }
            }
            
            // Quick Actions
            HStack {
                if transaction.status == .ready {
                    Button(action: { Task { await scheduler.executeNow(transaction) } }) {
                        Label("Execute", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                
                if transaction.status == .paused {
                    Button(action: { scheduler.resumeTransaction(transaction) }) {
                        Label("Resume", systemImage: "play")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if transaction.isActive && transaction.status != .ready {
                    Button(action: { scheduler.pauseTransaction(transaction) }) {
                        Label("Pause", systemImage: "pause")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                if transaction.isRecurring && transaction.isActive {
                    Button(action: { scheduler.skipNextOccurrence(transaction) }) {
                        Label("Skip", systemImage: "forward")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                Spacer()
                
                if transaction.isActive {
                    Button(role: .destructive, action: { scheduler.cancelTransaction(transaction) }) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var chainColor: Color {
        switch transaction.chain {
        case .bitcoin: return .orange
        case .ethereum: return .purple
        case .litecoin: return .gray
        case .solana: return .cyan
        case .xrp: return .blue
        }
    }
}

struct ScheduleStatusBadge: View {
    let status: ScheduledTransactionStatus
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.icon)
            Text(status.rawValue)
        }
        .font(.caption)
        .fontWeight(.medium)
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor)
        .cornerRadius(6)
    }
    
    private var statusColor: Color {
        switch status.color {
        case "blue": return .blue
        case "orange": return .orange
        case "purple": return .purple
        case "green": return .green
        case "red": return .red
        case "gray": return .gray
        case "yellow": return .yellow
        default: return .gray
        }
    }
}

// MARK: - Create Sheet

struct CreateScheduledTransactionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scheduler = TransactionScheduler.shared
    
    @State private var selectedChain: SchedulableChain = .bitcoin
    @State private var recipientAddress = ""
    @State private var amount = ""
    @State private var label = ""
    @State private var memo = ""
    @State private var scheduledDate = Date().addingTimeInterval(3600)
    @State private var frequency: RecurrenceFrequency = .once
    @State private var hasEndDate = false
    @State private var endDate = Date().addingTimeInterval(86400 * 30)
    @State private var maxOccurrences = ""
    @State private var requireConfirmation = false
    @State private var notifyBefore = true
    @State private var errorMessage: String?
    @State private var isCreating = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Schedule Transaction")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Chain Selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Network")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Picker("Chain", selection: $selectedChain) {
                            ForEach(SchedulableChain.allCases) { chain in
                                HStack {
                                    Image(systemName: chain.icon)
                                    Text(chain.displayName)
                                }
                                .tag(chain)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    // Recipient
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recipient Address")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        TextField("Enter \(selectedChain.displayName) address", text: $recipientAddress)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    // Amount
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Amount")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack {
                            TextField("0.00", text: $amount)
                                .textFieldStyle(.roundedBorder)
                            
                            Text(selectedChain.rawValue)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Label
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Label (Optional)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        TextField("e.g., Rent Payment, Savings", text: $label)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Divider()
                    
                    // Schedule
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Schedule")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        DatePicker("Execute on", selection: $scheduledDate, in: Date()...)
                            .datePickerStyle(.compact)
                    }
                    
                    // Frequency
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Frequency")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Picker("Frequency", selection: $frequency) {
                            ForEach(RecurrenceFrequency.allCases) { freq in
                                HStack {
                                    Image(systemName: freq.icon)
                                    Text(freq.rawValue)
                                }
                                .tag(freq)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    
                    // End Conditions (for recurring)
                    if frequency != .once {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Set End Date", isOn: $hasEndDate)
                            
                            if hasEndDate {
                                DatePicker("End on", selection: $endDate, in: scheduledDate...)
                                    .datePickerStyle(.compact)
                            } else {
                                HStack {
                                    Text("Max Occurrences")
                                    TextField("Unlimited", text: $maxOccurrences)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 100)
                                }
                            }
                        }
                        .padding()
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    Divider()
                    
                    // Options
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Options")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Toggle("Require manual confirmation", isOn: $requireConfirmation)
                        Toggle("Notify before execution", isOn: $notifyBefore)
                    }
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Actions
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(action: createTransaction) {
                    if isCreating {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Label("Schedule", systemImage: "calendar.badge.plus")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(recipientAddress.isEmpty || amount.isEmpty || isCreating)
            }
            .padding()
        }
        .frame(width: 500, height: 650)
    }
    
    private func createTransaction() {
        guard let amountDecimal = Decimal(string: amount) else {
            errorMessage = "Invalid amount"
            return
        }
        
        isCreating = true
        errorMessage = nil
        
        do {
            _ = try scheduler.scheduleTransaction(
                chain: selectedChain,
                recipientAddress: recipientAddress,
                amount: amountDecimal,
                scheduledDate: scheduledDate,
                frequency: frequency,
                endDate: hasEndDate ? endDate : nil,
                maxOccurrences: Int(maxOccurrences),
                label: label.isEmpty ? nil : label,
                memo: memo.isEmpty ? nil : memo,
                requireConfirmation: requireConfirmation,
                notifyBefore: notifyBefore
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isCreating = false
    }
}

// MARK: - Settings Sheet

struct SchedulerSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scheduler = TransactionScheduler.shared
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Scheduler Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            Form {
                Section("Execution") {
                    Toggle("Auto-execute when ready", isOn: $scheduler.autoExecuteEnabled)
                    
                    Toggle("Require unlock for execution", isOn: $scheduler.requireUnlockForExecution)
                }
                
                Section("Notifications") {
                    Picker("Default notification lead time", selection: $scheduler.defaultNotificationLeadTime) {
                        Text("1 minute").tag(TimeInterval(60))
                        Text("5 minutes").tag(TimeInterval(300))
                        Text("15 minutes").tag(TimeInterval(900))
                        Text("30 minutes").tag(TimeInterval(1800))
                        Text("1 hour").tag(TimeInterval(3600))
                    }
                }
                
                Section("Display") {
                    Toggle("Show completed transactions", isOn: $scheduler.showCompletedTransactions)
                }
                
                Section("About") {
                    Text("Scheduled transactions allow you to automate payments on a one-time or recurring basis. Transactions are checked every minute and executed when their scheduled time arrives.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
            
            Spacer()
            
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .frame(width: 450, height: 450)
    }
}

// MARK: - Transaction Detail Sheet

struct ScheduledTransactionDetailSheet: View {
    let transaction: ScheduledTransaction
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scheduler = TransactionScheduler.shared
    
    @State private var editedLabel = ""
    @State private var editedNotes = ""
    @State private var showDeleteConfirm = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Transaction Details")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Status & Amount
                    HStack {
                        ScheduleStatusBadge(status: transaction.status)
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text("\(transaction.amount) \(transaction.chain.rawValue)")
                                .font(.title)
                                .fontWeight(.bold)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    
                    // Details
                    ScheduleDetailRow(title: "Recipient", value: transaction.recipientAddress, isMonospace: true)
                    ScheduleDetailRow(title: "Network", value: transaction.chain.displayName)
                    ScheduleDetailRow(title: "Frequency", value: transaction.frequency.rawValue)
                    
                    if let nextDate = transaction.nextExecutionDate {
                        ScheduleDetailRow(title: "Next Execution", value: nextDate.formatted())
                    }
                    
                    ScheduleDetailRow(title: "Created", value: transaction.createdAt.formatted())
                    
                    // Editable Fields
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Label")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            TextField("Add label", text: $editedLabel)
                                .textFieldStyle(.roundedBorder)
                            
                            Button("Save") {
                                var updated = transaction
                                updated.label = editedLabel.isEmpty ? nil : editedLabel
                                scheduler.updateTransaction(updated)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    
                    // Execution History
                    if !transaction.executionHistory.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Execution History")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            ForEach(transaction.executionHistory.suffix(5)) { record in
                                HStack {
                                    Circle()
                                        .fill(record.status == .completed ? Color.green : Color.red)
                                        .frame(width: 8, height: 8)
                                    
                                    Text(record.executedAt, style: .date)
                                        .font(.caption)
                                    
                                    Spacer()
                                    
                                    Text(record.status.rawValue)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    if let txHash = record.txHash {
                                        Text(txHash.prefix(10) + "...")
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    
                    // Actions
                    HStack {
                        if transaction.isActive {
                            Button(role: .destructive, action: { showDeleteConfirm = true }) {
                                Label("Delete", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Spacer()
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 550)
        .onAppear {
            editedLabel = transaction.label ?? ""
            editedNotes = transaction.notes ?? ""
        }
        .alert("Delete Transaction?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                scheduler.deleteTransaction(transaction)
                dismiss()
            }
        } message: {
            Text("This will permanently delete this scheduled transaction.")
        }
    }
}

struct ScheduleDetailRow: View {
    let title: String
    let value: String
    var isMonospace: Bool = false
    
    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            Text(value)
                .font(isMonospace ? .system(.caption, design: .monospaced) : .caption)
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
        }
    }
}

// MARK: - Preview

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    ScheduledTransactionsView()
}
#endif
#endif
#endif
