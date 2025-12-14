import Foundation
// UserNotifications disabled - requires bundled .app to work
// import UserNotifications
import Combine

// MARK: - Transaction Scheduler
// Phase 5: Advanced Automation - Scheduled & Recurring Transactions

/// Frequency options for recurring transactions
enum RecurrenceFrequency: String, CaseIterable, Codable, Identifiable {
    case once = "Once"
    case daily = "Daily"
    case weekly = "Weekly"
    case biweekly = "Bi-Weekly"
    case monthly = "Monthly"
    case quarterly = "Quarterly"
    case yearly = "Yearly"
    
    var id: String { rawValue }
    
    var calendarComponent: Calendar.Component? {
        switch self {
        case .once: return nil
        case .daily: return .day
        case .weekly: return .weekOfYear
        case .biweekly: return .weekOfYear
        case .monthly: return .month
        case .quarterly: return .month
        case .yearly: return .year
        }
    }
    
    var componentValue: Int {
        switch self {
        case .once: return 0
        case .daily: return 1
        case .weekly: return 1
        case .biweekly: return 2
        case .monthly: return 1
        case .quarterly: return 3
        case .yearly: return 1
        }
    }
    
    var icon: String {
        switch self {
        case .once: return "1.circle"
        case .daily: return "sun.max"
        case .weekly: return "calendar.badge.clock"
        case .biweekly: return "calendar"
        case .monthly: return "calendar.circle"
        case .quarterly: return "chart.bar.doc.horizontal"
        case .yearly: return "sparkles"
        }
    }
}

/// Status of a scheduled transaction
enum ScheduledTransactionStatus: String, Codable {
    case pending = "Pending"
    case ready = "Ready"
    case executing = "Executing"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"
    case paused = "Paused"
    
    var color: String {
        switch self {
        case .pending: return "blue"
        case .ready: return "orange"
        case .executing: return "purple"
        case .completed: return "green"
        case .failed: return "red"
        case .cancelled: return "gray"
        case .paused: return "yellow"
        }
    }
    
    var icon: String {
        switch self {
        case .pending: return "clock"
        case .ready: return "clock.badge.exclamationmark"
        case .executing: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle"
        case .failed: return "xmark.circle"
        case .cancelled: return "slash.circle"
        case .paused: return "pause.circle"
        }
    }
}

/// Supported chains for scheduling
enum SchedulableChain: String, CaseIterable, Codable, Identifiable {
    case bitcoin = "BTC"
    case ethereum = "ETH"
    case litecoin = "LTC"
    case solana = "SOL"
    case xrp = "XRP"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .bitcoin: return "Bitcoin"
        case .ethereum: return "Ethereum"
        case .litecoin: return "Litecoin"
        case .solana: return "Solana"
        case .xrp: return "XRP"
        }
    }
    
    var icon: String {
        switch self {
        case .bitcoin: return "bitcoinsign.circle.fill"
        case .ethereum: return "diamond.fill"
        case .litecoin: return "l.circle.fill"
        case .solana: return "s.circle.fill"
        case .xrp: return "x.circle.fill"
        }
    }
    
    var minConfirmationTime: TimeInterval {
        switch self {
        case .bitcoin: return 600 // 10 minutes
        case .ethereum: return 15 // 15 seconds
        case .litecoin: return 150 // 2.5 minutes
        case .solana: return 1 // ~400ms
        case .xrp: return 4 // 3-5 seconds
        }
    }
}

// MARK: - Scheduled Transaction Model

/// A scheduled transaction
struct ScheduledTransaction: Codable, Identifiable {
    let id: UUID
    let chain: SchedulableChain
    
    // Transaction Details
    var recipientAddress: String
    var amount: Decimal
    var memo: String?
    
    // Scheduling
    var scheduledDate: Date
    var frequency: RecurrenceFrequency
    var endDate: Date? // For recurring, when to stop
    var maxOccurrences: Int? // Alternative to end date
    
    // Execution
    var status: ScheduledTransactionStatus
    var executionHistory: [ExecutionRecord]
    var nextExecutionDate: Date?
    
    // Options
    var requireManualConfirmation: Bool
    var notifyBeforeExecution: Bool
    var notificationLeadTime: TimeInterval // seconds before
    var pauseOnFailure: Bool
    var retryCount: Int
    var maxRetries: Int
    
    // Metadata
    var label: String?
    var notes: String?
    let createdAt: Date
    var updatedAt: Date
    
    // Computed
    var occurrencesCompleted: Int {
        executionHistory.filter { $0.status == .completed }.count
    }
    
    var isRecurring: Bool {
        frequency != .once
    }
    
    var isActive: Bool {
        status == .pending || status == .ready || status == .paused
    }
    
    init(chain: SchedulableChain, recipientAddress: String, amount: Decimal, 
         scheduledDate: Date, frequency: RecurrenceFrequency = .once,
         label: String? = nil) {
        self.id = UUID()
        self.chain = chain
        self.recipientAddress = recipientAddress
        self.amount = amount
        self.scheduledDate = scheduledDate
        self.frequency = frequency
        self.status = .pending
        self.executionHistory = []
        self.nextExecutionDate = scheduledDate
        self.requireManualConfirmation = false
        self.notifyBeforeExecution = true
        self.notificationLeadTime = 300 // 5 minutes
        self.pauseOnFailure = true
        self.retryCount = 0
        self.maxRetries = 3
        self.label = label
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

/// Record of a transaction execution attempt
struct ExecutionRecord: Codable, Identifiable {
    let id: UUID
    let scheduledDate: Date
    let executedAt: Date
    let status: ExecutionStatus
    var txHash: String?
    var errorMessage: String?
    var gasUsed: UInt64?
    var feesPaid: Decimal?
    
    enum ExecutionStatus: String, Codable {
        case completed = "Completed"
        case failed = "Failed"
        case skipped = "Skipped"
        case manualOverride = "Manual Override"
    }
    
    init(scheduledDate: Date, status: ExecutionStatus, txHash: String? = nil, error: String? = nil) {
        self.id = UUID()
        self.scheduledDate = scheduledDate
        self.executedAt = Date()
        self.status = status
        self.txHash = txHash
        self.errorMessage = error
    }
}

// MARK: - Transaction Scheduler Manager

@MainActor
class TransactionScheduler: ObservableObject {
    static let shared = TransactionScheduler()
    
    // MARK: - Published Properties
    
    @Published var scheduledTransactions: [ScheduledTransaction] = []
    @Published var isProcessing = false
    @Published var lastError: String?
    
    // MARK: - Settings
    
    @Published var autoExecuteEnabled: Bool = false {
        didSet { saveSettings() }
    }
    
    @Published var requireUnlockForExecution: Bool = true {
        didSet { saveSettings() }
    }
    
    @Published var defaultNotificationLeadTime: TimeInterval = 300 {
        didSet { saveSettings() }
    }
    
    @Published var showCompletedTransactions: Bool = true {
        didSet { saveSettings() }
    }
    
    // MARK: - Private Properties
    
    private let userDefaults = UserDefaults.standard
    private let keyPrefix = "scheduler_"
    private var checkTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    private init() {
        loadData()
        setupNotifications()
        // Defer timer setup to avoid issues with MainActor initialization
        DispatchQueue.main.async { [weak self] in
            self?.startScheduleChecker()
        }
    }
    
    // MARK: - Scheduling Operations
    
    /// Create a new scheduled transaction
    func scheduleTransaction(
        chain: SchedulableChain,
        recipientAddress: String,
        amount: Decimal,
        scheduledDate: Date,
        frequency: RecurrenceFrequency = .once,
        endDate: Date? = nil,
        maxOccurrences: Int? = nil,
        label: String? = nil,
        memo: String? = nil,
        requireConfirmation: Bool = false,
        notifyBefore: Bool = true
    ) throws -> ScheduledTransaction {
        // Validation
        guard scheduledDate > Date() else {
            throw SchedulerError.invalidDate("Scheduled date must be in the future")
        }
        
        guard amount > 0 else {
            throw SchedulerError.invalidAmount("Amount must be greater than 0")
        }
        
        guard !recipientAddress.isEmpty else {
            throw SchedulerError.invalidAddress("Recipient address is required")
        }
        
        var transaction = ScheduledTransaction(
            chain: chain,
            recipientAddress: recipientAddress,
            amount: amount,
            scheduledDate: scheduledDate,
            frequency: frequency,
            label: label
        )
        
        transaction.endDate = endDate
        transaction.maxOccurrences = maxOccurrences
        transaction.memo = memo
        transaction.requireManualConfirmation = requireConfirmation
        transaction.notifyBeforeExecution = notifyBefore
        transaction.notificationLeadTime = defaultNotificationLeadTime
        
        scheduledTransactions.append(transaction)
        saveTransactions()
        
        // Schedule notification if enabled
        if notifyBefore {
            scheduleNotification(for: transaction)
        }
        
        print("✅ Scheduled transaction: \(amount) \(chain.rawValue) to \(recipientAddress) on \(scheduledDate)")
        return transaction
    }
    
    /// Update an existing scheduled transaction
    func updateTransaction(_ transaction: ScheduledTransaction) {
        if let index = scheduledTransactions.firstIndex(where: { $0.id == transaction.id }) {
            var updated = transaction
            updated.updatedAt = Date()
            scheduledTransactions[index] = updated
            saveTransactions()
            
            // Reschedule notification
            cancelNotification(for: transaction)
            if updated.notifyBeforeExecution && updated.isActive {
                scheduleNotification(for: updated)
            }
        }
    }
    
    /// Cancel a scheduled transaction
    func cancelTransaction(_ transaction: ScheduledTransaction) {
        if let index = scheduledTransactions.firstIndex(where: { $0.id == transaction.id }) {
            scheduledTransactions[index].status = .cancelled
            scheduledTransactions[index].updatedAt = Date()
            saveTransactions()
            cancelNotification(for: transaction)
            print("❌ Cancelled scheduled transaction: \(transaction.id)")
        }
    }
    
    /// Pause a recurring transaction
    func pauseTransaction(_ transaction: ScheduledTransaction) {
        if let index = scheduledTransactions.firstIndex(where: { $0.id == transaction.id }) {
            scheduledTransactions[index].status = .paused
            scheduledTransactions[index].updatedAt = Date()
            saveTransactions()
            print("⏸ Paused scheduled transaction: \(transaction.id)")
        }
    }
    
    /// Resume a paused transaction
    func resumeTransaction(_ transaction: ScheduledTransaction) {
        if let index = scheduledTransactions.firstIndex(where: { $0.id == transaction.id }) {
            scheduledTransactions[index].status = .pending
            scheduledTransactions[index].updatedAt = Date()
            
            // Recalculate next execution date
            if let nextDate = calculateNextExecutionDate(for: scheduledTransactions[index]) {
                scheduledTransactions[index].nextExecutionDate = nextDate
            }
            
            saveTransactions()
            
            if scheduledTransactions[index].notifyBeforeExecution {
                scheduleNotification(for: scheduledTransactions[index])
            }
            
            print("▶️ Resumed scheduled transaction: \(transaction.id)")
        }
    }
    
    /// Delete a transaction completely
    func deleteTransaction(_ transaction: ScheduledTransaction) {
        cancelNotification(for: transaction)
        scheduledTransactions.removeAll { $0.id == transaction.id }
        saveTransactions()
        print("🗑 Deleted scheduled transaction: \(transaction.id)")
    }
    
    /// Execute a transaction immediately (manual trigger)
    func executeNow(_ transaction: ScheduledTransaction) async {
        guard let index = scheduledTransactions.firstIndex(where: { $0.id == transaction.id }) else {
            return
        }
        
        isProcessing = true
        scheduledTransactions[index].status = .executing
        
        do {
            let txHash = try await executeTransaction(transaction)
            
            // Record success
            let record = ExecutionRecord(
                scheduledDate: transaction.nextExecutionDate ?? Date(),
                status: .completed,
                txHash: txHash
            )
            scheduledTransactions[index].executionHistory.append(record)
            
            // Update status and next date
            if transaction.isRecurring {
                if let nextDate = calculateNextExecutionDate(for: transaction) {
                    scheduledTransactions[index].nextExecutionDate = nextDate
                    scheduledTransactions[index].status = .pending
                    
                    // Check if we've reached max occurrences or end date
                    if let maxOcc = transaction.maxOccurrences, 
                       scheduledTransactions[index].occurrencesCompleted >= maxOcc {
                        scheduledTransactions[index].status = .completed
                    } else if let endDate = transaction.endDate, nextDate > endDate {
                        scheduledTransactions[index].status = .completed
                    }
                } else {
                    scheduledTransactions[index].status = .completed
                }
            } else {
                scheduledTransactions[index].status = .completed
            }
            
            scheduledTransactions[index].retryCount = 0
            print("✅ Executed transaction: \(txHash)")
            
        } catch {
            // Record failure
            let record = ExecutionRecord(
                scheduledDate: transaction.nextExecutionDate ?? Date(),
                status: .failed,
                error: error.localizedDescription
            )
            scheduledTransactions[index].executionHistory.append(record)
            scheduledTransactions[index].retryCount += 1
            
            if scheduledTransactions[index].retryCount >= transaction.maxRetries {
                if transaction.pauseOnFailure {
                    scheduledTransactions[index].status = .paused
                } else {
                    scheduledTransactions[index].status = .failed
                }
            } else {
                scheduledTransactions[index].status = .pending
            }
            
            lastError = error.localizedDescription
            print("❌ Transaction failed: \(error.localizedDescription)")
        }
        
        scheduledTransactions[index].updatedAt = Date()
        saveTransactions()
        isProcessing = false
    }
    
    /// Skip the next occurrence of a recurring transaction
    func skipNextOccurrence(_ transaction: ScheduledTransaction) {
        guard let index = scheduledTransactions.firstIndex(where: { $0.id == transaction.id }) else {
            return
        }
        
        let record = ExecutionRecord(
            scheduledDate: transaction.nextExecutionDate ?? Date(),
            status: .skipped
        )
        scheduledTransactions[index].executionHistory.append(record)
        
        if let nextDate = calculateNextExecutionDate(for: transaction) {
            scheduledTransactions[index].nextExecutionDate = nextDate
        }
        
        scheduledTransactions[index].updatedAt = Date()
        saveTransactions()
        print("⏭ Skipped occurrence for transaction: \(transaction.id)")
    }
    
    // MARK: - Query Methods
    
    /// Get transactions due for execution
    func getReadyTransactions() -> [ScheduledTransaction] {
        let now = Date()
        return scheduledTransactions.filter { tx in
            guard tx.status == .pending || tx.status == .ready else { return false }
            guard let nextDate = tx.nextExecutionDate else { return false }
            return nextDate <= now
        }
    }
    
    /// Get upcoming transactions
    func getUpcomingTransactions(limit: Int = 10) -> [ScheduledTransaction] {
        scheduledTransactions
            .filter { $0.isActive && $0.nextExecutionDate != nil }
            .sorted { ($0.nextExecutionDate ?? .distantFuture) < ($1.nextExecutionDate ?? .distantFuture) }
            .prefix(limit)
            .map { $0 }
    }
    
    /// Get transactions for a specific chain
    func getTransactions(for chain: SchedulableChain) -> [ScheduledTransaction] {
        scheduledTransactions.filter { $0.chain == chain }
    }
    
    /// Get transaction statistics
    func getStatistics() -> SchedulerStatistics {
        let active = scheduledTransactions.filter { $0.isActive }
        let completed = scheduledTransactions.filter { $0.status == .completed }
        let failed = scheduledTransactions.filter { $0.status == .failed }
        let recurring = scheduledTransactions.filter { $0.isRecurring && $0.isActive }
        
        let totalExecuted = scheduledTransactions.reduce(0) { $0 + $1.executionHistory.count }
        let successfulExecutions = scheduledTransactions.reduce(0) { sum, tx in
            sum + tx.executionHistory.filter { $0.status == .completed }.count
        }
        
        return SchedulerStatistics(
            totalScheduled: scheduledTransactions.count,
            activeCount: active.count,
            completedCount: completed.count,
            failedCount: failed.count,
            recurringCount: recurring.count,
            totalExecutions: totalExecuted,
            successfulExecutions: successfulExecutions,
            successRate: totalExecuted > 0 ? Double(successfulExecutions) / Double(totalExecuted) : 0
        )
    }
    
    // MARK: - Private Methods
    
    private func executeTransaction(_ transaction: ScheduledTransaction) async throws -> String {
        // Simulate transaction execution
        // In production, this would call the actual blockchain transaction methods
        
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
        
        // Simulate occasional failures for testing
        if Int.random(in: 1...10) == 1 {
            throw SchedulerError.executionFailed("Network timeout")
        }
        
        // Generate mock tx hash
        let txHash = "0x" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return txHash
    }
    
    private func calculateNextExecutionDate(for transaction: ScheduledTransaction) -> Date? {
        guard transaction.isRecurring else { return nil }
        guard let component = transaction.frequency.calendarComponent else { return nil }
        
        let calendar = Calendar.current
        let baseDate = transaction.nextExecutionDate ?? transaction.scheduledDate
        
        return calendar.date(
            byAdding: component,
            value: transaction.frequency.componentValue,
            to: baseDate
        )
    }
    
    private func startScheduleChecker() {
        // Check every minute for transactions that need execution
        checkTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkScheduledTransactions()
            }
        }
    }
    
    private func checkScheduledTransactions() {
        let ready = getReadyTransactions()
        
        for transaction in ready {
            if let index = scheduledTransactions.firstIndex(where: { $0.id == transaction.id }) {
                scheduledTransactions[index].status = .ready
                
                if autoExecuteEnabled && !transaction.requireManualConfirmation {
                    Task {
                        await executeNow(transaction)
                    }
                }
            }
        }
        
        if !ready.isEmpty {
            saveTransactions()
        }
    }
    
    // MARK: - Notifications
    
    // Notifications are disabled for command-line Swift apps (no app bundle)
    // UNUserNotificationCenter requires a properly bundled .app to function
    // When Hawala is packaged as a proper macOS app, this can be re-enabled
    
    private func setupNotifications() {
        // Disabled: UNUserNotificationCenter crashes in non-bundled apps
        // with "bundleProxyForCurrentProcess is nil" error
        print("📝 Notifications disabled (command-line app mode)")
    }
    
    private func scheduleNotification(for transaction: ScheduledTransaction) {
        // Disabled for command-line app
        // In a bundled app, this would schedule local notifications
        print("📝 Would schedule notification for transaction: \(transaction.label ?? transaction.id.uuidString)")
    }
    
    private func cancelNotification(for transaction: ScheduledTransaction) {
        // Disabled for command-line app
    }
    
    // MARK: - Persistence
    
    private func saveTransactions() {
        if let data = try? JSONEncoder().encode(scheduledTransactions) {
            userDefaults.set(data, forKey: keyPrefix + "transactions")
        }
    }
    
    private func saveSettings() {
        userDefaults.set(autoExecuteEnabled, forKey: keyPrefix + "autoExecute")
        userDefaults.set(requireUnlockForExecution, forKey: keyPrefix + "requireUnlock")
        userDefaults.set(defaultNotificationLeadTime, forKey: keyPrefix + "notificationLead")
        userDefaults.set(showCompletedTransactions, forKey: keyPrefix + "showCompleted")
    }
    
    private func loadData() {
        // Load transactions
        if let data = userDefaults.data(forKey: keyPrefix + "transactions"),
           let decoded = try? JSONDecoder().decode([ScheduledTransaction].self, from: data) {
            scheduledTransactions = decoded
        }
        
        // Load settings
        autoExecuteEnabled = userDefaults.bool(forKey: keyPrefix + "autoExecute")
        requireUnlockForExecution = userDefaults.bool(forKey: keyPrefix + "requireUnlock")
        
        let leadTime = userDefaults.double(forKey: keyPrefix + "notificationLead")
        defaultNotificationLeadTime = leadTime > 0 ? leadTime : 300
        
        showCompletedTransactions = userDefaults.bool(forKey: keyPrefix + "showCompleted")
    }
}

// MARK: - Statistics Model

struct SchedulerStatistics {
    let totalScheduled: Int
    let activeCount: Int
    let completedCount: Int
    let failedCount: Int
    let recurringCount: Int
    let totalExecutions: Int
    let successfulExecutions: Int
    let successRate: Double
    
    var successRatePercentage: String {
        String(format: "%.1f%%", successRate * 100)
    }
}

// MARK: - Errors

enum SchedulerError: LocalizedError {
    case invalidDate(String)
    case invalidAmount(String)
    case invalidAddress(String)
    case executionFailed(String)
    case insufficientFunds
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidDate(let msg): return "Invalid date: \(msg)"
        case .invalidAmount(let msg): return "Invalid amount: \(msg)"
        case .invalidAddress(let msg): return "Invalid address: \(msg)"
        case .executionFailed(let msg): return "Execution failed: \(msg)"
        case .insufficientFunds: return "Insufficient funds for scheduled transaction"
        case .networkError(let msg): return "Network error: \(msg)"
        }
    }
}
