import Foundation
@preconcurrency import UserNotifications

// MARK: - Bundle Check Helper

/// Check if we're running in a proper app bundle context
private var canUseUserNotifications: Bool {
    // UNUserNotificationCenter crashes if not running in a proper bundle
    
    // 1. Check for XCTest environment
    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
        return false
    }
    if NSClassFromString("XCTest") != nil {
        return false
    }
    
    // 2. Check for valid bundle identifier
    guard let bundleID = Bundle.main.bundleIdentifier else {
        return false
    }
    
    // 3. Check if bundle ID looks like a system tool (e.g. com.apple.dt.xctest.tool)
    if bundleID.contains("xctest") || bundleID.contains("com.apple.dt") {
        return false
    }
    
    return true
}

// MARK: - Notification Models

/// Types of notifications the app can send
enum NotificationType: String, Codable, CaseIterable {
    case transactionConfirmed = "tx_confirmed"
    case transactionFailed = "tx_failed"
    case priceAlert = "price_alert"
    case securityReminder = "security_reminder"
    case stakingReward = "staking_reward"
    
    var title: String {
        switch self {
        case .transactionConfirmed: return "Transaction Confirmed"
        case .transactionFailed: return "Transaction Failed"
        case .priceAlert: return "Price Alert"
        case .securityReminder: return "Security Reminder"
        case .stakingReward: return "Staking Reward"
        }
    }
    
    var icon: String {
        switch self {
        case .transactionConfirmed: return "checkmark.circle.fill"
        case .transactionFailed: return "xmark.circle.fill"
        case .priceAlert: return "chart.line.uptrend.xyaxis"
        case .securityReminder: return "shield.fill"
        case .stakingReward: return "gift.fill"
        }
    }
}

/// A price alert configuration
struct PriceAlert: Identifiable, Codable {
    let id: UUID
    let asset: String // e.g., "bitcoin", "ethereum"
    let symbol: String // e.g., "BTC", "ETH"
    let targetPrice: Double
    let isAbove: Bool // true = alert when price goes above, false = below
    let currency: String // e.g., "USD"
    var isActive: Bool
    var triggeredAt: Date?
    
    var description: String {
        let direction = isAbove ? "above" : "below"
        return "\(symbol) \(direction) \(currency) \(String(format: "%.2f", targetPrice))"
    }
}

/// A notification record for history
struct NotificationRecord: Identifiable, Codable {
    let id: UUID
    let type: NotificationType
    let title: String
    let body: String
    let timestamp: Date
    var isRead: Bool
    let metadata: [String: String]?
}

// MARK: - Notification Settings

struct NotificationSettings: Codable {
    var transactionAlerts: Bool = true
    var priceAlerts: Bool = true
    var securityReminders: Bool = true
    var stakingAlerts: Bool = true
    var soundEnabled: Bool = true
    var badgeEnabled: Bool = true
    
    static var `default`: NotificationSettings { NotificationSettings() }
}

// MARK: - Notification Manager

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var isAuthorized = false
    @Published var settings: NotificationSettings = .default
    @Published var priceAlerts: [PriceAlert] = []
    @Published var notificationHistory: [NotificationRecord] = []
    @Published var unreadCount: Int = 0
    
    private let userDefaults = UserDefaults.standard
    private let settingsKey = "notificationSettings"
    private let alertsKey = "priceAlerts"
    private let historyKey = "notificationHistory"
    
    private var priceMonitorTask: Task<Void, Never>?
    private var txMonitorTask: Task<Void, Never>?
    
    private init() {
        loadSettings()
        loadPriceAlerts()
        loadHistory()
        if canUseUserNotifications {
            Task { await checkAuthorization() }
        }
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() async -> Bool {
        guard canUseUserNotifications else {
            print("UserNotifications not available (no bundle context)")
            return false
        }
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            return granted
        } catch {
            print("Notification authorization error: \(error)")
            return false
        }
    }
    
    func checkAuthorization() async {
        guard canUseUserNotifications else {
            isAuthorized = false
            return
        }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }
    
    // MARK: - Send Notifications
    
    func sendNotification(
        type: NotificationType,
        title: String,
        body: String,
        metadata: [String: String]? = nil
    ) async {
        // Check if this type is enabled
        guard isNotificationTypeEnabled(type) else { return }
        
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = settings.soundEnabled ? .default : nil
        
        if settings.badgeEnabled {
            content.badge = NSNumber(value: unreadCount + 1)
        }
        
        // Add to history
        let record = NotificationRecord(
            id: UUID(),
            type: type,
            title: title,
            body: body,
            timestamp: Date(),
            isRead: false,
            metadata: metadata
        )
        notificationHistory.insert(record, at: 0)
        unreadCount += 1
        saveHistory()
        
        // Only schedule system notification if available
        guard canUseUserNotifications else { return }
        
        // Schedule notification
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Failed to send notification: \(error)")
        }
    }
    
    private func isNotificationTypeEnabled(_ type: NotificationType) -> Bool {
        switch type {
        case .transactionConfirmed, .transactionFailed:
            return settings.transactionAlerts
        case .priceAlert:
            return settings.priceAlerts
        case .securityReminder:
            return settings.securityReminders
        case .stakingReward:
            return settings.stakingAlerts
        }
    }
    
    // MARK: - Transaction Monitoring
    
    func notifyTransactionConfirmed(txHash: String, chain: String, amount: String) async {
        await sendNotification(
            type: .transactionConfirmed,
            title: "Transaction Confirmed",
            body: "\(amount) on \(chain.capitalized) has been confirmed",
            metadata: ["txHash": txHash, "chain": chain]
        )
    }
    
    func notifyTransactionFailed(txHash: String, chain: String, reason: String) async {
        await sendNotification(
            type: .transactionFailed,
            title: "Transaction Failed",
            body: "Your \(chain.capitalized) transaction failed: \(reason)",
            metadata: ["txHash": txHash, "chain": chain]
        )
    }
    
    // MARK: - Price Alerts
    
    func addPriceAlert(asset: String, symbol: String, targetPrice: Double, isAbove: Bool, currency: String = "USD") {
        let alert = PriceAlert(
            id: UUID(),
            asset: asset,
            symbol: symbol,
            targetPrice: targetPrice,
            isAbove: isAbove,
            currency: currency,
            isActive: true,
            triggeredAt: nil
        )
        priceAlerts.append(alert)
        savePriceAlerts()
    }
    
    func removePriceAlert(_ alert: PriceAlert) {
        priceAlerts.removeAll { $0.id == alert.id }
        savePriceAlerts()
    }
    
    func togglePriceAlert(_ alert: PriceAlert) {
        if let index = priceAlerts.firstIndex(where: { $0.id == alert.id }) {
            priceAlerts[index].isActive.toggle()
            savePriceAlerts()
        }
    }
    
    /// Start monitoring prices for alerts
    func startPriceMonitoring() {
        priceMonitorTask?.cancel()
        priceMonitorTask = Task {
            while !Task.isCancelled {
                await checkPriceAlerts()
                try? await Task.sleep(nanoseconds: 60_000_000_000) // Check every minute
            }
        }
    }
    
    func stopPriceMonitoring() {
        priceMonitorTask?.cancel()
        priceMonitorTask = nil
    }
    
    private func checkPriceAlerts() async {
        let activeAlerts = priceAlerts.filter { $0.isActive }
        guard !activeAlerts.isEmpty else { return }
        
        // Fetch current prices
        let assets = Set(activeAlerts.map { $0.asset })
        let prices = await fetchPrices(for: Array(assets))
        
        for alert in activeAlerts {
            guard let currentPrice = prices[alert.asset] else { continue }
            
            let triggered: Bool
            if alert.isAbove {
                triggered = currentPrice >= alert.targetPrice
            } else {
                triggered = currentPrice <= alert.targetPrice
            }
            
            if triggered {
                await triggerPriceAlert(alert, currentPrice: currentPrice)
            }
        }
    }
    
    private func triggerPriceAlert(_ alert: PriceAlert, currentPrice: Double) async {
        let direction = alert.isAbove ? "above" : "below"
        await sendNotification(
            type: .priceAlert,
            title: "\(alert.symbol) Price Alert",
            body: "\(alert.symbol) is now \(direction) \(alert.currency) \(String(format: "%.2f", alert.targetPrice)). Current: \(String(format: "%.2f", currentPrice))",
            metadata: ["asset": alert.asset, "price": String(currentPrice)]
        )
        
        // Deactivate the alert after triggering
        if let index = priceAlerts.firstIndex(where: { $0.id == alert.id }) {
            priceAlerts[index].isActive = false
            priceAlerts[index].triggeredAt = Date()
            savePriceAlerts()
        }
    }
    
    private func fetchPrices(for assets: [String]) async -> [String: Double] {
        let ids = assets.joined(separator: ",")
        guard let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=\(ids)&vs_currencies=usd") else {
            return [:]
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode([String: [String: Double]].self, from: data)
            return response.compactMapValues { $0["usd"] }
        } catch {
            print("Failed to fetch prices: \(error)")
            return [:]
        }
    }
    
    // MARK: - Security Reminders
    
    func sendBackupReminder() async {
        await sendNotification(
            type: .securityReminder,
            title: "Backup Reminder",
            body: "Have you backed up your recovery phrase recently? Keep your funds safe!"
        )
    }
    
    func sendSecurityCheckReminder() async {
        await sendNotification(
            type: .securityReminder,
            title: "Security Check",
            body: "Review your security settings and make sure biometric lock is enabled."
        )
    }
    
    // MARK: - History Management
    
    func markAsRead(_ notification: NotificationRecord) {
        if let index = notificationHistory.firstIndex(where: { $0.id == notification.id }) {
            notificationHistory[index].isRead = true
            unreadCount = max(0, unreadCount - 1)
            saveHistory()
        }
    }
    
    func markAllAsRead() {
        for i in notificationHistory.indices {
            notificationHistory[i].isRead = true
        }
        unreadCount = 0
        saveHistory()
        
        // Clear badge
        UNUserNotificationCenter.current().setBadgeCount(0)
    }
    
    func clearHistory() {
        notificationHistory.removeAll()
        unreadCount = 0
        saveHistory()
        UNUserNotificationCenter.current().setBadgeCount(0)
    }
    
    // MARK: - Persistence
    
    private func loadSettings() {
        if let data = userDefaults.data(forKey: settingsKey),
           let loaded = try? JSONDecoder().decode(NotificationSettings.self, from: data) {
            settings = loaded
        }
    }
    
    func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            userDefaults.set(data, forKey: settingsKey)
        }
    }
    
    private func loadPriceAlerts() {
        if let data = userDefaults.data(forKey: alertsKey),
           let loaded = try? JSONDecoder().decode([PriceAlert].self, from: data) {
            priceAlerts = loaded
        }
    }
    
    private func savePriceAlerts() {
        if let data = try? JSONEncoder().encode(priceAlerts) {
            userDefaults.set(data, forKey: alertsKey)
        }
    }
    
    private func loadHistory() {
        if let data = userDefaults.data(forKey: historyKey),
           let loaded = try? JSONDecoder().decode([NotificationRecord].self, from: data) {
            notificationHistory = loaded
            unreadCount = loaded.filter { !$0.isRead }.count
        }
    }
    
    private func saveHistory() {
        // Keep only last 100 notifications
        let trimmed = Array(notificationHistory.prefix(100))
        if let data = try? JSONEncoder().encode(trimmed) {
            userDefaults.set(data, forKey: historyKey)
        }
    }
}
