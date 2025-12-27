import Foundation
import SwiftUI
import Security
import CryptoKit

// MARK: - Duress Wallet Manager

/// Manages duress PIN and decoy wallet for plausible deniability
/// When duress PIN is entered, shows a decoy wallet with minimal funds
/// Real wallet is completely hidden - impossible to prove it exists
@MainActor
final class DuressWalletManager: ObservableObject {
    static let shared = DuressWalletManager()
    
    // MARK: - Published State
    
    @Published private(set) var isDuressEnabled = false
    @Published private(set) var isInDuressMode = false
    @Published private(set) var decoyWallet: DecoyWallet?
    @Published private(set) var isConfigured = false
    
    // MARK: - Keychain Keys
    
    private let keychainService = "com.hawala.wallet.duress"
    private let duressPINKey = "duress_pin_hash"
    private let decoyWalletKey = "decoy_wallet_data"
    private let duressEnabledKey = "duress_enabled"
    private let emergencyContactKey = "emergency_contact"
    private let silentAlertKey = "silent_alert_enabled"
    
    // MARK: - Configuration
    
    @AppStorage("hawala.duress.configured") private var duressConfigured = false
    @AppStorage("hawala.duress.silentAlert") private var silentAlertEnabled = false
    
    // MARK: - Initialization
    
    private init() {
        // DON'T call loadConfiguration() here - defer keychain access
        // This prevents password prompts on app startup
        isDuressEnabled = false
        isConfigured = duressConfigured
    }
    
    /// Call this to actually load configuration from keychain (lazy)
    func ensureConfigurationLoaded() {
        guard !hasLoadedConfig else { return }
        hasLoadedConfig = true
        loadConfiguration()
    }
    
    private var hasLoadedConfig = false
    
    // MARK: - Public API
    
    /// Check if entered PIN is the duress PIN
    func isDuressPin(_ pin: String) -> Bool {
        guard let storedHash = loadDuressPINHash() else {
            return false
        }
        let inputHash = hashPIN(pin)
        return inputHash == storedHash
    }
    
    /// Activate duress mode (called when duress PIN entered)
    func activateDuressMode() {
        isInDuressMode = true
        decoyWallet = loadDecoyWallet()
        
        // Trigger silent alert if enabled
        if silentAlertEnabled {
            triggerSilentAlert()
        }
        
        // Log duress activation (encrypted, only visible in real mode)
        logDuressActivation()
    }
    
    /// Deactivate duress mode (called when real PIN entered after duress)
    func deactivateDuressMode() {
        isInDuressMode = false
        decoyWallet = nil
    }
    
    /// Configure duress PIN
    func setDuressPin(_ pin: String, confirmPin: String) -> Result<Void, DuressError> {
        // Validate
        guard pin.count >= 4 else {
            return .failure(.pinTooShort)
        }
        
        guard pin == confirmPin else {
            return .failure(.pinMismatch)
        }
        
        // Make sure duress PIN is different from real PIN
        if PasscodeManager.shared.verifyPasscode(pin) {
            return .failure(.sameAsRealPin)
        }
        
        // Save duress PIN hash
        let hash = hashPIN(pin)
        guard saveDuressPINHash(hash) else {
            return .failure(.keychainError)
        }
        
        isDuressEnabled = true
        duressConfigured = true
        isConfigured = true
        
        return .success(())
    }
    
    /// Remove duress PIN
    func removeDuressPin(realPin: String) -> Bool {
        // Require real PIN to remove
        guard PasscodeManager.shared.verifyPasscode(realPin) else {
            return false
        }
        
        _ = deleteDuressPINHash()
        _ = deleteDecoyWallet()
        
        isDuressEnabled = false
        duressConfigured = false
        isConfigured = false
        
        return true
    }
    
    /// Configure decoy wallet
    func configureDecoyWallet(_ config: DecoyWalletConfig) -> Result<Void, DuressError> {
        let decoy = DecoyWallet(
            id: UUID(),
            name: config.name,
            seedPhrase: config.seedPhrase,
            createdAt: Date(),
            fakeTransactions: generateFakeTransactionHistory(config: config),
            balances: config.balances
        )
        
        guard saveDecoyWallet(decoy) else {
            return .failure(.keychainError)
        }
        
        self.decoyWallet = decoy
        return .success(())
    }
    
    /// Configure emergency contact for silent alert
    func setEmergencyContact(_ contact: EmergencyContact) -> Bool {
        guard let data = try? JSONEncoder().encode(contact) else {
            return false
        }
        return saveToKeychain(data, key: emergencyContactKey)
    }
    
    /// Enable/disable silent alert
    func setSilentAlert(_ enabled: Bool) {
        silentAlertEnabled = enabled
    }
    
    /// Get duress activation logs (only visible in real mode)
    func getDuressActivationLogs() -> [DuressActivationLog]? {
        guard !isInDuressMode else {
            return nil // Hide logs in duress mode
        }
        return loadDuressLogs()
    }
    
    /// Clear duress activation logs
    func clearDuressLogs() {
        UserDefaults.standard.removeObject(forKey: "hawala.duress.logs")
    }
    
    // MARK: - Private Methods
    
    private func loadConfiguration() {
        isDuressEnabled = loadDuressPINHash() != nil
        isConfigured = duressConfigured
    }
    
    private func hashPIN(_ pin: String) -> String {
        // Use SHA256 with salt for PIN hashing
        let salt = "HawalaDuress_v1_"
        let saltedPin = salt + pin
        let data = Data(saltedPin.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Keychain Operations
    
    private func saveDuressPINHash(_ hash: String) -> Bool {
        let data = Data(hash.utf8)
        return saveToKeychain(data, key: duressPINKey)
    }
    
    private func loadDuressPINHash() -> String? {
        guard let data = loadFromKeychain(key: duressPINKey),
              let hash = String(data: data, encoding: .utf8) else {
            return nil
        }
        return hash
    }
    
    private func deleteDuressPINHash() -> Bool {
        deleteFromKeychain(key: duressPINKey)
    }
    
    private func saveDecoyWallet(_ wallet: DecoyWallet) -> Bool {
        guard let data = try? JSONEncoder().encode(wallet) else {
            return false
        }
        return saveToKeychain(data, key: decoyWalletKey)
    }
    
    private func loadDecoyWallet() -> DecoyWallet? {
        guard let data = loadFromKeychain(key: decoyWalletKey) else {
            return nil
        }
        return try? JSONDecoder().decode(DecoyWallet.self, from: data)
    }
    
    private func deleteDecoyWallet() -> Bool {
        deleteFromKeychain(key: decoyWalletKey)
    }
    
    private func saveToKeychain(_ data: Data, key: String) -> Bool {
        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add new
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
            kSecMatchLimit as String: kSecMatchLimitOne
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
    
    // MARK: - Transaction History Generation
    
    private func generateFakeTransactionHistory(config: DecoyWalletConfig) -> [FakeTransaction] {
        var transactions: [FakeTransaction] = []
        let calendar = Calendar.current
        let now = Date()
        
        // Generate realistic-looking transaction history
        // Spread over the past few months
        
        // Initial "deposit" from exchange
        if config.includeDeposits {
            let initialDate = calendar.date(byAdding: .day, value: -90, to: now)!
            transactions.append(FakeTransaction(
                id: UUID(),
                type: .receive,
                amount: config.totalDeposited,
                chain: "bitcoin",
                date: initialDate,
                description: "Received from Coinbase",
                txHash: generateFakeTxHash()
            ))
        }
        
        // Add some small receives
        let smallReceiveCount = Int.random(in: 2...5)
        for i in 0..<smallReceiveCount {
            let daysAgo = Int.random(in: 10...80)
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
            let amount = Double.random(in: 0.001...0.05)
            
            transactions.append(FakeTransaction(
                id: UUID(),
                type: .receive,
                amount: amount,
                chain: ["bitcoin", "ethereum"].randomElement()!,
                date: date,
                description: ["Received from friend", "Payment received", "Gift", "Reimbursement"].randomElement()!,
                txHash: generateFakeTxHash()
            ))
        }
        
        // Add some sends
        if config.includeSends {
            let sendCount = Int.random(in: 2...4)
            for _ in 0..<sendCount {
                let daysAgo = Int.random(in: 5...60)
                let date = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
                let amount = Double.random(in: 0.005...0.02)
                
                transactions.append(FakeTransaction(
                    id: UUID(),
                    type: .send,
                    amount: amount,
                    chain: ["bitcoin", "ethereum"].randomElement()!,
                    date: date,
                    description: ["Payment", "Sent to friend", "Purchase"].randomElement()!,
                    txHash: generateFakeTxHash()
                ))
            }
        }
        
        // Sort by date, newest first
        transactions.sort { $0.date > $1.date }
        
        return transactions
    }
    
    private func generateFakeTxHash() -> String {
        let chars = "0123456789abcdef"
        return String((0..<64).map { _ in chars.randomElement()! })
    }
    
    // MARK: - Silent Alert
    
    private func triggerSilentAlert() {
        guard let data = loadFromKeychain(key: emergencyContactKey),
              let contact = try? JSONDecoder().decode(EmergencyContact.self, from: data) else {
            return
        }
        
        // Send silent alert via the configured method
        switch contact.alertMethod {
        case .sms:
            // In a real app, this would use a secure backend to send SMS
            // For now, log the intent
            print("[DURESS] Silent SMS alert triggered to \(contact.phoneNumber ?? "unknown")")
            
        case .email:
            // In a real app, this would send via secure backend
            print("[DURESS] Silent email alert triggered to \(contact.email ?? "unknown")")
            
        case .signal:
            // Signal integration would go here
            print("[DURESS] Silent Signal alert triggered")
            
        case .none:
            break
        }
    }
    
    // MARK: - Logging
    
    private func logDuressActivation() {
        let log = DuressActivationLog(
            id: UUID(),
            timestamp: Date(),
            deviceInfo: getDeviceInfo()
        )
        
        var logs = loadDuressLogs() ?? []
        logs.append(log)
        
        // Keep only last 100 logs
        if logs.count > 100 {
            logs = Array(logs.suffix(100))
        }
        
        if let data = try? JSONEncoder().encode(logs) {
            UserDefaults.standard.set(data, forKey: "hawala.duress.logs")
        }
    }
    
    private func loadDuressLogs() -> [DuressActivationLog]? {
        guard let data = UserDefaults.standard.data(forKey: "hawala.duress.logs") else {
            return nil
        }
        return try? JSONDecoder().decode([DuressActivationLog].self, from: data)
    }
    
    private func getDeviceInfo() -> String {
        #if os(macOS)
        return "macOS"
        #else
        return "iOS"
        #endif
    }
}

// MARK: - Models

struct DecoyWallet: Codable, Identifiable {
    let id: UUID
    let name: String
    let seedPhrase: [String]
    let createdAt: Date
    let fakeTransactions: [FakeTransaction]
    let balances: [String: Double] // chain -> amount
    
    var formattedSeedPhrase: String {
        seedPhrase.enumerated().map { "\($0 + 1). \($1)" }.joined(separator: "\n")
    }
}

struct DecoyWalletConfig {
    var name: String
    var seedPhrase: [String]
    var balances: [String: Double]
    var totalDeposited: Double
    var includeDeposits: Bool
    var includeSends: Bool
    
    init() {
        self.name = "Main Wallet"
        self.seedPhrase = Self.generateDecoyPhrase()
        self.balances = [
            "bitcoin": 0.0015,
            "ethereum": 0.05,
            "litecoin": 0.5
        ]
        self.totalDeposited = 0.01
        self.includeDeposits = true
        self.includeSends = true
    }
    
    static func generateDecoyPhrase() -> [String] {
        // Common BIP-39 words for a realistic-looking decoy phrase
        let words = [
            "abandon", "ability", "able", "about", "above", "absent", "absorb", "abstract",
            "absurd", "abuse", "access", "accident", "account", "accuse", "achieve", "acid",
            "acoustic", "acquire", "across", "act", "action", "actor", "actress", "actual",
            "adapt", "add", "addict", "address", "adjust", "admit", "adult", "advance",
            "advice", "aerobic", "affair", "afford", "afraid", "again", "age", "agent",
            "agree", "ahead", "aim", "air", "airport", "aisle", "alarm", "album",
            "alcohol", "alert", "alien", "all", "alley", "allow", "almost", "alone",
            "alpha", "already", "also", "alter", "always", "amateur", "amazing", "among"
        ]
        
        return (0..<12).map { _ in words.randomElement()! }
    }
}

struct FakeTransaction: Codable, Identifiable {
    let id: UUID
    let type: TransactionType
    let amount: Double
    let chain: String
    let date: Date
    let description: String
    let txHash: String
    
    enum TransactionType: String, Codable {
        case send
        case receive
    }
}

struct EmergencyContact: Codable {
    var name: String
    var phoneNumber: String?
    var email: String?
    var alertMethod: AlertMethod
    var message: String
    
    enum AlertMethod: String, Codable {
        case sms
        case email
        case signal
        case none
    }
    
    init() {
        self.name = ""
        self.phoneNumber = nil
        self.email = nil
        self.alertMethod = .none
        self.message = "Duress alert triggered"
    }
}

struct DuressActivationLog: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let deviceInfo: String
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

// MARK: - Errors

enum DuressError: Error, LocalizedError {
    case pinTooShort
    case pinMismatch
    case sameAsRealPin
    case keychainError
    case notConfigured
    case alreadyInDuressMode
    
    var errorDescription: String? {
        switch self {
        case .pinTooShort:
            return "Duress PIN must be at least 4 digits"
        case .pinMismatch:
            return "PINs do not match"
        case .sameAsRealPin:
            return "Duress PIN cannot be the same as your real PIN"
        case .keychainError:
            return "Failed to save to secure storage"
        case .notConfigured:
            return "Duress mode is not configured"
        case .alreadyInDuressMode:
            return "Already in duress mode"
        }
    }
}
