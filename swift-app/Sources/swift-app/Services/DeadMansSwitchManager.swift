import Foundation
import SwiftUI
import Security
import CryptoKit

// MARK: - Dead Man's Switch Manager

/// Manages inheritance protocol with timelock-based fund transfers
/// If user doesn't check in within specified period, funds automatically transfer to heirs
@MainActor
final class DeadMansSwitchManager: ObservableObject {
    static let shared = DeadMansSwitchManager()
    
    // MARK: - Published State
    
    @Published private(set) var isConfigured = false
    @Published private(set) var config: InheritanceConfig?
    @Published private(set) var lastCheckIn: Date?
    @Published private(set) var nextCheckInDue: Date?
    @Published private(set) var daysUntilTrigger: Int?
    @Published private(set) var isTriggered = false
    @Published private(set) var warningLevel: WarningLevel = .none
    
    // MARK: - Private State
    
    private let keychainService = "com.hawala.wallet.inheritance"
    private let configKey = "inheritance_config"
    private let checkInKey = "last_check_in"
    private let preSignedTxKey = "presigned_transactions"
    
    private var checkTimer: Timer?
    
    // MARK: - Initialization
    
    private init() {
        loadConfiguration()
        startCheckTimer()
    }
    
    // MARK: - Public API
    
    /// Configure the inheritance protocol
    func configure(_ newConfig: InheritanceConfig) -> Result<Void, InheritanceError> {
        // Validate heirs
        guard !newConfig.heirs.isEmpty else {
            return .failure(.noHeirsConfigured)
        }
        
        // Validate total allocation
        let totalAllocation = newConfig.heirs.reduce(0) { $0 + $1.allocation }
        guard totalAllocation == 100 else {
            return .failure(.invalidAllocation(actual: totalAllocation))
        }
        
        // Validate inactivity period
        guard newConfig.inactivityDays >= 30 else {
            return .failure(.periodTooShort)
        }
        
        // Save configuration
        guard saveConfig(newConfig) else {
            return .failure(.saveFailed)
        }
        
        // Record initial check-in
        recordCheckIn()
        
        config = newConfig
        isConfigured = true
        
        // Generate pre-signed transactions if needed
        if newConfig.useBitcoinTimelocks {
            generatePreSignedTransactions(config: newConfig)
        }
        
        return .success(())
    }
    
    /// Record a check-in (user is still alive/active)
    func recordCheckIn() {
        lastCheckIn = Date()
        saveCheckInDate(lastCheckIn!)
        updateNextCheckInDue()
        warningLevel = .none
        
        // Reset warning notifications
        NotificationManager.shared.cancelDeadMansSwitchWarnings()
    }
    
    /// Check current status
    func checkStatus() -> InheritanceStatus {
        guard let config = config, let lastCheckIn = lastCheckIn else {
            return .notConfigured
        }
        
        let daysSinceCheckIn = Calendar.current.dateComponents([.day], from: lastCheckIn, to: Date()).day ?? 0
        let daysRemaining = config.inactivityDays - daysSinceCheckIn
        
        if daysRemaining <= 0 {
            return .triggered
        } else if daysRemaining <= config.warningDays {
            return .warning(daysRemaining: daysRemaining)
        } else {
            return .active(daysRemaining: daysRemaining)
        }
    }
    
    /// Cancel the inheritance protocol and emergency stop
    func emergencyCancel(passcode: String) -> Result<Void, InheritanceError> {
        // Verify passcode
        guard PasscodeManager.shared.verifyPasscode(passcode) else {
            return .failure(.invalidPasscode)
        }
        
        // Cancel any scheduled transactions
        cancelPreSignedTransactions()
        
        // Reset state
        _ = deleteConfig()
        _ = deleteCheckInDate()
        
        config = nil
        isConfigured = false
        lastCheckIn = nil
        nextCheckInDue = nil
        isTriggered = false
        warningLevel = .none
        
        return .success(())
    }
    
    /// Modify heir allocations
    func updateHeirs(_ heirs: [Heir]) -> Result<Void, InheritanceError> {
        guard var currentConfig = config else {
            return .failure(.notConfigured)
        }
        
        let totalAllocation = heirs.reduce(0) { $0 + $1.allocation }
        guard totalAllocation == 100 else {
            return .failure(.invalidAllocation(actual: totalAllocation))
        }
        
        currentConfig.heirs = heirs
        return configure(currentConfig)
    }
    
    /// Update inactivity period
    func updateInactivityPeriod(_ days: Int) -> Result<Void, InheritanceError> {
        guard var currentConfig = config else {
            return .failure(.notConfigured)
        }
        
        guard days >= 30 else {
            return .failure(.periodTooShort)
        }
        
        currentConfig.inactivityDays = days
        return configure(currentConfig)
    }
    
    /// Get pre-signed transaction details for review
    func getPreSignedTransactions() -> [PreSignedTransaction]? {
        guard let data = loadFromKeychain(key: preSignedTxKey) else {
            return nil
        }
        return try? JSONDecoder().decode([PreSignedTransaction].self, from: data)
    }
    
    // MARK: - Private Methods
    
    private func loadConfiguration() {
        config = loadConfig()
        isConfigured = config != nil
        lastCheckIn = loadCheckInDate()
        updateNextCheckInDue()
        
        if let status = checkStatus() as? InheritanceStatus {
            switch status {
            case .triggered:
                isTriggered = true
                triggerInheritance()
            case .warning(let days):
                warningLevel = days <= 7 ? .critical : .warning
            default:
                break
            }
        }
    }
    
    private func startCheckTimer() {
        // Check status every hour
        checkTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performStatusCheck()
            }
        }
    }
    
    private func performStatusCheck() {
        guard let config = config, let lastCheckIn = lastCheckIn else { return }
        
        let daysSinceCheckIn = Calendar.current.dateComponents([.day], from: lastCheckIn, to: Date()).day ?? 0
        let daysRemaining = config.inactivityDays - daysSinceCheckIn
        daysUntilTrigger = max(0, daysRemaining)
        
        // Update warning level
        if daysRemaining <= 0 {
            if !isTriggered {
                triggerInheritance()
            }
        } else if daysRemaining <= 7 {
            warningLevel = .critical
            sendWarningNotification(daysRemaining: daysRemaining)
        } else if daysRemaining <= config.warningDays {
            warningLevel = .warning
            sendWarningNotification(daysRemaining: daysRemaining)
        } else {
            warningLevel = .none
        }
    }
    
    private func updateNextCheckInDue() {
        guard let config = config, let lastCheckIn = lastCheckIn else {
            nextCheckInDue = nil
            daysUntilTrigger = nil
            return
        }
        
        nextCheckInDue = Calendar.current.date(byAdding: .day, value: config.inactivityDays, to: lastCheckIn)
        
        let daysSinceCheckIn = Calendar.current.dateComponents([.day], from: lastCheckIn, to: Date()).day ?? 0
        daysUntilTrigger = max(0, config.inactivityDays - daysSinceCheckIn)
    }
    
    private func triggerInheritance() {
        isTriggered = true
        
        // Execute pre-signed transactions for Bitcoin
        executePreSignedTransactions()
        
        // For Ethereum, deploy timelock contract or execute existing one
        executeEthereumInheritance()
        
        // Send notifications
        sendTriggerNotification()
    }
    
    private func sendWarningNotification(daysRemaining: Int) {
        guard let config = config else { return }
        
        let title = "Inheritance Protocol Warning"
        let body = "You have \(daysRemaining) day(s) to check in before your inheritance protocol triggers. Open Hawala to check in."
        
        NotificationManager.shared.scheduleDeadMansSwitchWarning(
            title: title,
            body: body,
            daysRemaining: daysRemaining
        )
    }
    
    private func sendTriggerNotification() {
        let title = "Inheritance Protocol Triggered"
        let body = "Your inheritance protocol has been triggered due to inactivity. Funds are being transferred to designated heirs."
        
        Task {
            await NotificationManager.shared.sendNotification(
                type: .securityReminder,
                title: title,
                body: body
            )
        }
    }
    
    // MARK: - Bitcoin Timelock Transactions
    
    private func generatePreSignedTransactions(config: InheritanceConfig) {
        // This would generate pre-signed transactions with CLTV timelocks
        // The transactions would be stored encrypted and broadcast when triggered
        
        var preSignedTxs: [PreSignedTransaction] = []
        
        for heir in config.heirs {
            let tx = PreSignedTransaction(
                id: UUID(),
                heirName: heir.name,
                heirAddress: heir.address,
                chain: heir.chain,
                allocation: heir.allocation,
                lockTime: calculateLockTime(daysFromNow: config.inactivityDays),
                status: .pending,
                createdAt: Date()
            )
            preSignedTxs.append(tx)
        }
        
        if let data = try? JSONEncoder().encode(preSignedTxs) {
            _ = saveToKeychain(data, key: preSignedTxKey)
        }
    }
    
    private func calculateLockTime(daysFromNow: Int) -> UInt32 {
        // Bitcoin CLTV locktime in Unix timestamp
        let futureDate = Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date())!
        return UInt32(futureDate.timeIntervalSince1970)
    }
    
    private func executePreSignedTransactions() {
        // In production, this would broadcast the pre-signed transactions
        // For now, we log the intent
        print("[INHERITANCE] Executing pre-signed Bitcoin transactions")
        
        // Update transaction status
        if var txs = getPreSignedTransactions() {
            for i in txs.indices {
                txs[i].status = .executed
                txs[i].executedAt = Date()
            }
            if let data = try? JSONEncoder().encode(txs) {
                _ = saveToKeychain(data, key: preSignedTxKey)
            }
        }
    }
    
    private func executeEthereumInheritance() {
        // In production, this would interact with a timelock smart contract
        print("[INHERITANCE] Executing Ethereum inheritance contract")
    }
    
    private func cancelPreSignedTransactions() {
        _ = deleteFromKeychain(key: preSignedTxKey)
    }
    
    // MARK: - Keychain Operations
    
    private func saveConfig(_ config: InheritanceConfig) -> Bool {
        guard let data = try? JSONEncoder().encode(config) else { return false }
        return saveToKeychain(data, key: configKey)
    }
    
    private func loadConfig() -> InheritanceConfig? {
        guard let data = loadFromKeychain(key: configKey) else { return nil }
        return try? JSONDecoder().decode(InheritanceConfig.self, from: data)
    }
    
    private func deleteConfig() -> Bool {
        deleteFromKeychain(key: configKey)
    }
    
    private func saveCheckInDate(_ date: Date) {
        let data = Data("\(date.timeIntervalSince1970)".utf8)
        _ = saveToKeychain(data, key: checkInKey)
    }
    
    private func loadCheckInDate() -> Date? {
        guard let data = loadFromKeychain(key: checkInKey),
              let str = String(data: data, encoding: .utf8),
              let interval = Double(str) else { return nil }
        return Date(timeIntervalSince1970: interval)
    }
    
    private func deleteCheckInDate() -> Bool {
        deleteFromKeychain(key: checkInKey)
    }
    
    private func saveToKeychain(_ data: Data, key: String) -> Bool {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    private func loadFromKeychain(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIAllow
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        // Handle user cancellation gracefully
        if status == errSecUserCanceled {
            return nil
        }
        
        guard status == errSecSuccess else {
            return nil
        }
        return result as? Data
    }
    
    private func deleteFromKeychain(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

// MARK: - Models

struct InheritanceConfig: Codable, Equatable {
    var heirs: [Heir]
    var inactivityDays: Int  // Days before trigger
    var warningDays: Int     // Days before trigger to start warnings
    var useBitcoinTimelocks: Bool
    var useEthereumContract: Bool
    var requirePasscodeForCheckIn: Bool
    var notifyHeirsOnSetup: Bool
    
    init() {
        self.heirs = []
        self.inactivityDays = 365  // 1 year default
        self.warningDays = 30
        self.useBitcoinTimelocks = true
        self.useEthereumContract = false
        self.requirePasscodeForCheckIn = false
        self.notifyHeirsOnSetup = false
    }
    
    static let inactivityOptions: [(days: Int, label: String)] = [
        (90, "3 Months"),
        (180, "6 Months"),
        (365, "1 Year"),
        (730, "2 Years"),
        (1095, "3 Years")
    ]
}

struct Heir: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var email: String?
    var address: String      // Crypto address
    var chain: String        // "bitcoin", "ethereum", etc.
    var allocation: Int      // Percentage (must total 100)
    var notes: String?
    
    init(name: String = "", email: String? = nil, address: String = "", chain: String = "bitcoin", allocation: Int = 100, notes: String? = nil) {
        self.id = UUID()
        self.name = name
        self.email = email
        self.address = address
        self.chain = chain
        self.allocation = allocation
        self.notes = notes
    }
}

struct PreSignedTransaction: Codable, Identifiable {
    let id: UUID
    let heirName: String
    let heirAddress: String
    let chain: String
    let allocation: Int
    let lockTime: UInt32
    var status: TransactionStatus
    let createdAt: Date
    var executedAt: Date?
    var txHash: String?
    
    enum TransactionStatus: String, Codable {
        case pending
        case ready       // Locktime passed, ready to broadcast
        case executed
        case cancelled
    }
}

enum InheritanceStatus {
    case notConfigured
    case active(daysRemaining: Int)
    case warning(daysRemaining: Int)
    case triggered
}

enum WarningLevel {
    case none
    case warning
    case critical
}

enum InheritanceError: Error, LocalizedError {
    case noHeirsConfigured
    case invalidAllocation(actual: Int)
    case periodTooShort
    case saveFailed
    case notConfigured
    case invalidPasscode
    case transactionGenerationFailed
    
    var errorDescription: String? {
        switch self {
        case .noHeirsConfigured:
            return "At least one heir must be configured"
        case .invalidAllocation(let actual):
            return "Heir allocations must total 100% (currently \(actual)%)"
        case .periodTooShort:
            return "Inactivity period must be at least 30 days"
        case .saveFailed:
            return "Failed to save configuration"
        case .notConfigured:
            return "Inheritance protocol is not configured"
        case .invalidPasscode:
            return "Invalid passcode"
        case .transactionGenerationFailed:
            return "Failed to generate pre-signed transactions"
        }
    }
}

// MARK: - Notification Manager Extension

extension NotificationManager {
    func scheduleDeadMansSwitchWarning(title: String, body: String, daysRemaining: Int) {
        // Schedule a local notification using the existing notification system
        Task {
            await self.sendNotification(
                type: .securityReminder,
                title: title,
                body: body,
                metadata: ["daysRemaining": "\(daysRemaining)"]
            )
        }
    }
    
    func cancelDeadMansSwitchWarnings() {
        // Clear warnings - in a real implementation this would remove specific notifications
        // For now, we just prevent new ones from being sent
    }
}
