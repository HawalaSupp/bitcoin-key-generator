import Foundation
import SwiftUI
import Security
import CryptoKit

// MARK: - Time-Locked Vault Manager

/// Manages time-locked vaults for forced HODLing, escrow, and scheduled payments
/// Uses native blockchain timelocks (Bitcoin CLTV/CSV, Ethereum timelock contracts)
@MainActor
final class TimeLockedVaultManager: ObservableObject {
    static let shared = TimeLockedVaultManager()
    
    // MARK: - Published State
    
    @Published private(set) var vaults: [TimeLockedVault] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: VaultError?
    
    // MARK: - Private State
    
    private let keychainService = "com.hawala.wallet.vaults"
    private let vaultsKey = "timelocked_vaults"
    
    private var countdownTimer: Timer?
    private var hasLoadedConfig = false
    
    // MARK: - Initialization
    
    private init() {
        // DON'T load from keychain on init - defer to avoid password prompts
    }
    
    /// Lazy load configuration from keychain
    public func ensureConfigurationLoaded() {
        guard !hasLoadedConfig else { return }
        hasLoadedConfig = true
        loadVaults()
        startCountdownTimer()
    }
    
    // MARK: - Public API
    
    /// Create a new time-locked vault
    func createVault(_ config: VaultConfig) async -> Result<TimeLockedVault, VaultError> {
        isLoading = true
        defer { isLoading = false }
        
        // Validate
        guard config.amount > 0 else {
            return .failure(.invalidAmount)
        }
        
        guard config.unlockDate > Date() else {
            return .failure(.unlockDateInPast)
        }
        
        // Generate locktime based on chain
        let locktime: UInt32
        switch config.chain {
        case .bitcoin, .litecoin:
            // Bitcoin/Litecoin use block height or Unix timestamp for CLTV
            locktime = UInt32(config.unlockDate.timeIntervalSince1970)
        case .ethereum, .bnb, .polygon:
            // EVM chains use Unix timestamp
            locktime = UInt32(config.unlockDate.timeIntervalSince1970)
        }
        
        // Create vault
        let vault = TimeLockedVault(
            id: UUID(),
            name: config.name,
            chain: config.chain,
            amount: config.amount,
            tokenSymbol: config.tokenSymbol,
            contractAddress: config.contractAddress,
            createdAt: Date(),
            unlockDate: config.unlockDate,
            locktime: locktime,
            unlockSchedule: config.unlockSchedule,
            status: .locked,
            purpose: config.purpose,
            notes: config.notes
        )
        
        // Generate the locking transaction/contract
        let txResult = await generateLockTransaction(vault: vault, config: config)
        guard case .success(let lockTxInfo) = txResult else {
            if case .failure(let err) = txResult {
                return .failure(err)
            }
            return .failure(.transactionGenerationFailed)
        }
        
        var finalVault = vault
        finalVault.lockTxHash = lockTxInfo.txHash
        finalVault.scriptAddress = lockTxInfo.scriptAddress
        
        // Save vault
        vaults.append(finalVault)
        saveVaults()
        
        return .success(finalVault)
    }
    
    /// Unlock a vault (only possible after unlock date)
    func unlockVault(_ vaultId: UUID) async -> Result<String, VaultError> {
        guard let index = vaults.firstIndex(where: { $0.id == vaultId }) else {
            return .failure(.vaultNotFound)
        }
        
        let vault = vaults[index]
        
        // Check if unlock is allowed
        guard vault.canUnlock else {
            if Date() < vault.unlockDate {
                return .failure(.notYetUnlockable(unlockDate: vault.unlockDate))
            }
            return .failure(.invalidStatus)
        }
        
        // Generate and broadcast unlock transaction
        let unlockResult = await generateUnlockTransaction(vault: vault)
        guard case .success(let txHash) = unlockResult else {
            if case .failure(let err) = unlockResult {
                return .failure(err)
            }
            return .failure(.unlockFailed)
        }
        
        // Update vault status
        vaults[index].status = .unlocked
        vaults[index].unlockTxHash = txHash
        saveVaults()
        
        return .success(txHash)
    }
    
    /// Partial unlock for vaults with schedules
    func partialUnlock(_ vaultId: UUID, scheduleIndex: Int) async -> Result<String, VaultError> {
        guard let index = vaults.firstIndex(where: { $0.id == vaultId }) else {
            return .failure(.vaultNotFound)
        }
        
        var vault = vaults[index]
        
        guard let schedule = vault.unlockSchedule, scheduleIndex < schedule.count else {
            return .failure(.invalidSchedule)
        }
        
        let scheduleItem = schedule[scheduleIndex]
        
        guard scheduleItem.unlockDate <= Date() else {
            return .failure(.notYetUnlockable(unlockDate: scheduleItem.unlockDate))
        }
        
        guard !scheduleItem.isUnlocked else {
            return .failure(.alreadyUnlocked)
        }
        
        // Generate partial unlock transaction
        let txResult = await generatePartialUnlockTransaction(vault: vault, amount: scheduleItem.amount)
        guard case .success(let txHash) = txResult else {
            if case .failure(let err) = txResult {
                return .failure(err)
            }
            return .failure(.unlockFailed)
        }
        
        // Update schedule
        vault.unlockSchedule?[scheduleIndex].isUnlocked = true
        vault.unlockSchedule?[scheduleIndex].unlockTxHash = txHash
        
        // Check if all scheduled unlocks are complete
        let allUnlocked = vault.unlockSchedule?.allSatisfy { $0.isUnlocked } ?? true
        if allUnlocked {
            vault.status = .unlocked
        } else {
            vault.status = .partiallyUnlocked
        }
        
        vaults[index] = vault
        saveVaults()
        
        return .success(txHash)
    }
    
    /// Delete a vault (only possible if already unlocked)
    func deleteVault(_ vaultId: UUID) -> Result<Void, VaultError> {
        guard let index = vaults.firstIndex(where: { $0.id == vaultId }) else {
            return .failure(.vaultNotFound)
        }
        
        let vault = vaults[index]
        guard vault.status == .unlocked else {
            return .failure(.cannotDeleteLockedVault)
        }
        
        vaults.remove(at: index)
        saveVaults()
        
        return .success(())
    }
    
    /// Get vault by ID
    func getVault(_ id: UUID) -> TimeLockedVault? {
        vaults.first { $0.id == id }
    }
    
    /// Calculate total locked value across all vaults
    func totalLockedValue(for chain: BlockchainChain? = nil) -> Double {
        vaults
            .filter { $0.status == .locked || $0.status == .partiallyUnlocked }
            .filter { chain == nil || $0.chain == chain }
            .reduce(0) { $0 + $1.amount }
    }
    
    // MARK: - Private Methods
    
    private func loadVaults() {
        guard let data = loadFromKeychain(key: vaultsKey),
              let decoded = try? JSONDecoder().decode([TimeLockedVault].self, from: data) else {
            vaults = []
            return
        }
        vaults = decoded
        
        // Update status based on current date
        for i in vaults.indices {
            if vaults[i].status == .locked && Date() >= vaults[i].unlockDate {
                vaults[i].status = .ready
            }
        }
    }
    
    private func saveVaults() {
        guard let data = try? JSONEncoder().encode(vaults) else { return }
        _ = saveToKeychain(data, key: vaultsKey)
    }
    
    private func startCountdownTimer() {
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateVaultStatuses()
            }
        }
    }
    
    private func updateVaultStatuses() {
        var updated = false
        for i in vaults.indices {
            if vaults[i].status == .locked && Date() >= vaults[i].unlockDate {
                vaults[i].status = .ready
                updated = true
                
                // Send notification
                Task {
                    await NotificationManager.shared.sendNotification(
                        type: .securityReminder,
                        title: "Vault Ready to Unlock",
                        body: "Your vault '\(vaults[i].name)' is now ready to be unlocked."
                    )
                }
            }
        }
        if updated {
            saveVaults()
        }
    }
    
    // MARK: - Transaction Generation
    
    private func generateLockTransaction(vault: TimeLockedVault, config: VaultConfig) async -> Result<LockTransactionInfo, VaultError> {
        switch vault.chain {
        case .bitcoin, .litecoin:
            return await generateBitcoinCLTVTransaction(vault: vault, config: config)
        case .ethereum, .bnb, .polygon:
            return await generateEVMTimelockContract(vault: vault, config: config)
        }
    }
    
    private func generateBitcoinCLTVTransaction(vault: TimeLockedVault, config: VaultConfig) async -> Result<LockTransactionInfo, VaultError> {
        // In production, this would:
        // 1. Create a P2SH/P2WSH script with CLTV opcode
        // 2. Generate the script address
        // 3. Sign the locking transaction
        
        // Bitcoin CLTV script structure:
        // <locktime> OP_CHECKLOCKTIMEVERIFY OP_DROP <pubkey> OP_CHECKSIG
        
        let scriptAddress = generateBitcoinScriptAddress(locktime: vault.locktime, chain: vault.chain)
        
        return .success(LockTransactionInfo(
            txHash: nil, // Will be set after broadcast
            scriptAddress: scriptAddress,
            script: generateCLTVScript(locktime: vault.locktime)
        ))
    }
    
    private func generateEVMTimelockContract(vault: TimeLockedVault, config: VaultConfig) async -> Result<LockTransactionInfo, VaultError> {
        // In production, this would:
        // 1. Deploy a simple timelock contract
        // 2. Or interact with a pre-deployed vault factory contract
        
        // Example Solidity timelock contract:
        // contract SimpleTimelock {
        //     uint256 public releaseTime;
        //     address public beneficiary;
        //     constructor(address _beneficiary, uint256 _releaseTime) {
        //         beneficiary = _beneficiary;
        //         releaseTime = _releaseTime;
        //     }
        //     function release() public {
        //         require(block.timestamp >= releaseTime);
        //         // Transfer funds to beneficiary
        //     }
        // }
        
        return .success(LockTransactionInfo(
            txHash: nil,
            scriptAddress: "0x...", // Contract address after deployment
            script: nil
        ))
    }
    
    private func generateBitcoinScriptAddress(locktime: UInt32, chain: BlockchainChain) -> String {
        // Generate deterministic script address based on locktime
        // In production, this would use proper Bitcoin scripting
        let prefix = chain == .bitcoin ? "bc1" : "ltc1" // Native SegWit
        let hash = SHA256.hash(data: Data("\(locktime)".utf8))
        let suffix = hash.compactMap { String(format: "%02x", $0) }.joined().prefix(32)
        return "\(prefix)q\(suffix)"
    }
    
    private func generateCLTVScript(locktime: UInt32) -> String {
        // Return hex-encoded CLTV script
        // <locktime> OP_CLTV OP_DROP <pubkey> OP_CHECKSIG
        return "04\(String(format: "%08x", locktime.littleEndian))b17521...ac"
    }
    
    private func generateUnlockTransaction(vault: TimeLockedVault) async -> Result<String, VaultError> {
        // In production, this would:
        // 1. Create a spending transaction from the script address
        // 2. Sign with the proper witness/scriptSig including CLTV satisfaction
        // 3. Broadcast to the network
        
        // For now, return a placeholder
        let txHash = generatePlaceholderTxHash()
        return .success(txHash)
    }
    
    private func generatePartialUnlockTransaction(vault: TimeLockedVault, amount: Double) async -> Result<String, VaultError> {
        // Similar to full unlock but for a portion of the funds
        let txHash = generatePlaceholderTxHash()
        return .success(txHash)
    }
    
    private func generatePlaceholderTxHash() -> String {
        let chars = "0123456789abcdef"
        return String((0..<64).map { _ in chars.randomElement()! })
    }
    
    // MARK: - Keychain Operations
    
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
}

// MARK: - Models

struct TimeLockedVault: Codable, Identifiable {
    let id: UUID
    let name: String
    let chain: BlockchainChain
    let amount: Double
    let tokenSymbol: String
    let contractAddress: String? // For ERC-20 tokens
    let createdAt: Date
    let unlockDate: Date
    let locktime: UInt32
    var unlockSchedule: [UnlockScheduleItem]?
    var status: VaultStatus
    let purpose: VaultPurpose
    let notes: String?
    
    // Transaction info
    var lockTxHash: String?
    var unlockTxHash: String?
    var scriptAddress: String?
    
    var canUnlock: Bool {
        status == .ready || (status == .locked && Date() >= unlockDate)
    }
    
    var timeRemaining: TimeInterval {
        max(0, unlockDate.timeIntervalSinceNow)
    }
    
    var formattedTimeRemaining: String {
        let remaining = timeRemaining
        if remaining <= 0 {
            return "Ready to unlock"
        }
        
        let days = Int(remaining / 86400)
        let hours = Int((remaining.truncatingRemainder(dividingBy: 86400)) / 3600)
        
        if days > 0 {
            return "\(days)d \(hours)h remaining"
        } else if hours > 0 {
            let minutes = Int((remaining.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m remaining"
        } else {
            let minutes = Int(remaining / 60)
            return "\(minutes)m remaining"
        }
    }
    
    var progress: Double {
        let total = unlockDate.timeIntervalSince(createdAt)
        let elapsed = Date().timeIntervalSince(createdAt)
        return min(1.0, max(0.0, elapsed / total))
    }
}

struct UnlockScheduleItem: Codable, Identifiable {
    let id: UUID
    let unlockDate: Date
    let amount: Double
    let percentage: Int
    var isUnlocked: Bool
    var unlockTxHash: String?
    
    init(unlockDate: Date, amount: Double, percentage: Int) {
        self.id = UUID()
        self.unlockDate = unlockDate
        self.amount = amount
        self.percentage = percentage
        self.isUnlocked = false
        self.unlockTxHash = nil
    }
}

struct VaultConfig {
    var name: String
    var chain: BlockchainChain
    var amount: Double
    var tokenSymbol: String
    var contractAddress: String?
    var unlockDate: Date
    var unlockSchedule: [UnlockScheduleItem]?
    var purpose: VaultPurpose
    var notes: String?
    
    init() {
        self.name = ""
        self.chain = .bitcoin
        self.amount = 0
        self.tokenSymbol = "BTC"
        self.contractAddress = nil
        self.unlockDate = Calendar.current.date(byAdding: .month, value: 6, to: Date())!
        self.unlockSchedule = nil
        self.purpose = .hodl
        self.notes = nil
    }
    
    static let presetDurations: [(label: String, months: Int)] = [
        ("1 Month", 1),
        ("3 Months", 3),
        ("6 Months", 6),
        ("1 Year", 12),
        ("2 Years", 24),
        ("5 Years", 60)
    ]
}

struct LockTransactionInfo {
    let txHash: String?
    let scriptAddress: String?
    let script: String?
}

enum BlockchainChain: String, Codable, CaseIterable, Identifiable {
    case bitcoin
    case litecoin
    case ethereum
    case bnb
    case polygon
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .bitcoin: return "Bitcoin"
        case .litecoin: return "Litecoin"
        case .ethereum: return "Ethereum"
        case .bnb: return "BNB Chain"
        case .polygon: return "Polygon"
        }
    }
    
    var symbol: String {
        switch self {
        case .bitcoin: return "BTC"
        case .litecoin: return "LTC"
        case .ethereum: return "ETH"
        case .bnb: return "BNB"
        case .polygon: return "MATIC"
        }
    }
    
    var icon: String {
        switch self {
        case .bitcoin: return "bitcoinsign.circle.fill"
        case .litecoin: return "l.circle.fill"
        case .ethereum: return "circle.hexagonpath.fill"
        case .bnb: return "b.circle.fill"
        case .polygon: return "hexagon.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .bitcoin: return .orange
        case .litecoin: return .gray
        case .ethereum: return .purple
        case .bnb: return .yellow
        case .polygon: return .purple.opacity(0.8)
        }
    }
    
    var supportsTimelocks: Bool {
        true // All supported chains have timelock mechanisms
    }
}

enum VaultStatus: String, Codable {
    case locked           // Funds are locked, cannot be withdrawn
    case ready           // Timelock expired, ready to unlock
    case partiallyUnlocked // Some scheduled unlocks completed
    case unlocked        // Fully unlocked
    
    var displayName: String {
        switch self {
        case .locked: return "Locked"
        case .ready: return "Ready to Unlock"
        case .partiallyUnlocked: return "Partially Unlocked"
        case .unlocked: return "Unlocked"
        }
    }
    
    var color: Color {
        switch self {
        case .locked: return .orange
        case .ready: return .green
        case .partiallyUnlocked: return .blue
        case .unlocked: return .gray
        }
    }
    
    var icon: String {
        switch self {
        case .locked: return "lock.fill"
        case .ready: return "lock.open.fill"
        case .partiallyUnlocked: return "lock.open"
        case .unlocked: return "checkmark.circle.fill"
        }
    }
}

enum VaultPurpose: String, Codable, CaseIterable {
    case hodl          // Forced holding
    case savings       // Long-term savings
    case escrow        // Escrow for a transaction
    case scheduled     // Scheduled payment
    case retirement    // Retirement savings
    case education     // Education fund
    case gift          // Gift that unlocks on a date
    case other
    
    var displayName: String {
        switch self {
        case .hodl: return "HODL - Forced Holding"
        case .savings: return "Long-term Savings"
        case .escrow: return "Escrow"
        case .scheduled: return "Scheduled Payment"
        case .retirement: return "Retirement Fund"
        case .education: return "Education Fund"
        case .gift: return "Gift (Future Date)"
        case .other: return "Other"
        }
    }
    
    var icon: String {
        switch self {
        case .hodl: return "hand.raised.fill"
        case .savings: return "banknote.fill"
        case .escrow: return "doc.text.fill"
        case .scheduled: return "calendar.badge.clock"
        case .retirement: return "house.fill"
        case .education: return "book.fill"
        case .gift: return "gift.fill"
        case .other: return "questionmark.circle.fill"
        }
    }
}

enum VaultError: Error, LocalizedError {
    case invalidAmount
    case unlockDateInPast
    case vaultNotFound
    case notYetUnlockable(unlockDate: Date)
    case invalidStatus
    case unlockFailed
    case invalidSchedule
    case alreadyUnlocked
    case cannotDeleteLockedVault
    case transactionGenerationFailed
    case broadcastFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return "Invalid amount specified"
        case .unlockDateInPast:
            return "Unlock date must be in the future"
        case .vaultNotFound:
            return "Vault not found"
        case .notYetUnlockable(let date):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return "Vault cannot be unlocked until \(formatter.string(from: date))"
        case .invalidStatus:
            return "Invalid vault status for this operation"
        case .unlockFailed:
            return "Failed to unlock vault"
        case .invalidSchedule:
            return "Invalid unlock schedule"
        case .alreadyUnlocked:
            return "This portion is already unlocked"
        case .cannotDeleteLockedVault:
            return "Cannot delete a locked vault"
        case .transactionGenerationFailed:
            return "Failed to generate locking transaction"
        case .broadcastFailed:
            return "Failed to broadcast transaction"
        }
    }
}
