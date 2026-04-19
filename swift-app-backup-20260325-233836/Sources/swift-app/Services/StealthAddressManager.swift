import Foundation
import CryptoKit

// MARK: - Stealth Address Manager
// Phase 4.3: Implements stealth addresses for enhanced transaction privacy
// Based on EIP-5564 (Ethereum) and BIP-352 (Bitcoin Silent Payments) concepts

/// Supported chains for stealth addresses
enum StealthChain: String, CaseIterable, Codable, Identifiable {
    case bitcoin = "BTC"
    case ethereum = "ETH"
    case litecoin = "LTC"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .bitcoin: return "Bitcoin"
        case .ethereum: return "Ethereum"
        case .litecoin: return "Litecoin"
        }
    }
    
    var icon: String {
        switch self {
        case .bitcoin: return "bitcoinsign.circle.fill"
        case .ethereum: return "diamond.fill"
        case .litecoin: return "l.circle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .bitcoin: return "orange"
        case .ethereum: return "purple"
        case .litecoin: return "gray"
        }
    }
    
    /// Prefix for stealth meta-address
    var stealthPrefix: String {
        switch self {
        case .bitcoin: return "st:btc:"
        case .ethereum: return "st:eth:"
        case .litecoin: return "st:ltc:"
        }
    }
}

// MARK: - Stealth Key Pair

/// A stealth key pair consisting of spending and viewing keys
struct StealthKeyPair: Codable, Identifiable {
    let id: UUID
    let chain: StealthChain
    
    /// Private spending key (used to spend received funds)
    let spendingPrivateKey: Data
    /// Public spending key
    let spendingPublicKey: Data
    
    /// Private viewing key (used to scan for incoming payments)
    let viewingPrivateKey: Data
    /// Public viewing key
    let viewingPublicKey: Data
    
    /// The stealth meta-address that can be shared publicly
    var metaAddress: String {
        let spendHex = spendingPublicKey.prefix(33).hexString
        let viewHex = viewingPublicKey.prefix(33).hexString
        return "\(chain.stealthPrefix)\(spendHex)\(viewHex)"
    }
    
    /// Creation timestamp
    let createdAt: Date
    
    /// Optional label for this key pair
    var label: String?
    
    /// Whether this is the default key pair for the chain
    var isDefault: Bool
    
    init(chain: StealthChain, spendingPrivateKey: Data, spendingPublicKey: Data, 
         viewingPrivateKey: Data, viewingPublicKey: Data, label: String? = nil, isDefault: Bool = false) {
        self.id = UUID()
        self.chain = chain
        self.spendingPrivateKey = spendingPrivateKey
        self.spendingPublicKey = spendingPublicKey
        self.viewingPrivateKey = viewingPrivateKey
        self.viewingPublicKey = viewingPublicKey
        self.createdAt = Date()
        self.label = label
        self.isDefault = isDefault
    }
}

// MARK: - Stealth Payment

/// Represents a detected stealth payment
struct StealthPayment: Codable, Identifiable {
    let id: UUID
    let chain: StealthChain
    
    /// The ephemeral public key from the sender
    let ephemeralPublicKey: Data
    
    /// The one-time address where funds were sent
    let oneTimeAddress: String
    
    /// The derived private key for spending (encrypted)
    let encryptedSpendingKey: Data
    
    /// Amount received (in smallest unit)
    let amount: UInt64
    
    /// Transaction hash
    let txHash: String
    
    /// Block height where payment was found
    let blockHeight: UInt64
    
    /// Timestamp of detection
    let detectedAt: Date
    
    /// Whether funds have been spent
    var isSpent: Bool
    
    /// Optional note
    var note: String?
    
    /// The key pair ID used to receive this payment
    let keyPairId: UUID
    
    init(chain: StealthChain, ephemeralPublicKey: Data, oneTimeAddress: String,
         encryptedSpendingKey: Data, amount: UInt64, txHash: String, blockHeight: UInt64,
         keyPairId: UUID, note: String? = nil) {
        self.id = UUID()
        self.chain = chain
        self.ephemeralPublicKey = ephemeralPublicKey
        self.oneTimeAddress = oneTimeAddress
        self.encryptedSpendingKey = encryptedSpendingKey
        self.amount = amount
        self.txHash = txHash
        self.blockHeight = blockHeight
        self.detectedAt = Date()
        self.isSpent = false
        self.note = note
        self.keyPairId = keyPairId
    }
}

// MARK: - Outgoing Stealth Payment

/// Represents an outgoing stealth payment we created
struct OutgoingStealthPayment: Codable, Identifiable {
    let id: UUID
    let chain: StealthChain
    
    /// Recipient's stealth meta-address
    let recipientMetaAddress: String
    
    /// The ephemeral key pair we generated (private key for proof, public shared with recipient)
    let ephemeralPrivateKey: Data
    let ephemeralPublicKey: Data
    
    /// The computed one-time address
    let oneTimeAddress: String
    
    /// Amount sent
    let amount: UInt64
    
    /// Transaction hash (once broadcast)
    var txHash: String?
    
    /// Status
    var status: PaymentStatus
    
    /// Creation timestamp
    let createdAt: Date
    
    /// Optional label
    var label: String?
    
    enum PaymentStatus: String, Codable {
        case pending = "Pending"
        case broadcast = "Broadcast"
        case confirmed = "Confirmed"
        case failed = "Failed"
    }
    
    init(chain: StealthChain, recipientMetaAddress: String, ephemeralPrivateKey: Data,
         ephemeralPublicKey: Data, oneTimeAddress: String, amount: UInt64, label: String? = nil) {
        self.id = UUID()
        self.chain = chain
        self.recipientMetaAddress = recipientMetaAddress
        self.ephemeralPrivateKey = ephemeralPrivateKey
        self.ephemeralPublicKey = ephemeralPublicKey
        self.oneTimeAddress = oneTimeAddress
        self.amount = amount
        self.status = .pending
        self.createdAt = Date()
        self.label = label
    }
}

// MARK: - Scan Progress

/// Tracks blockchain scanning progress
struct ScanProgress: Codable {
    var chain: StealthChain
    var lastScannedBlock: UInt64
    var totalBlocks: UInt64
    var isScanning: Bool
    var paymentsFound: Int
    var lastScanDate: Date?
    
    var progress: Double {
        guard totalBlocks > 0 else { return 0 }
        return Double(lastScannedBlock) / Double(totalBlocks)
    }
    
    var progressPercentage: String {
        String(format: "%.1f%%", progress * 100)
    }
}

// MARK: - Stealth Address Manager

@MainActor
class StealthAddressManager: ObservableObject {
    static let shared = StealthAddressManager()
    
    // MARK: - Published Properties
    
    @Published var keyPairs: [StealthKeyPair] = []
    @Published var receivedPayments: [StealthPayment] = []
    @Published var outgoingPayments: [OutgoingStealthPayment] = []
    @Published var scanProgress: [StealthChain: ScanProgress] = [:]
    
    @Published var isGeneratingKeys: Bool = false
    @Published var isScanningBlockchain: Bool = false
    @Published var lastError: String?
    
    // MARK: - Settings
    
    @Published var autoScanEnabled: Bool = true {
        didSet { saveSettings() }
    }
    
    @Published var scanIntervalMinutes: Int = 15 {
        didSet { saveSettings() }
    }
    
    @Published var notifyOnPayment: Bool = true {
        didSet { saveSettings() }
    }
    
    // MARK: - Private Properties
    
    private let userDefaults = UserDefaults.standard
    private let keyPrefix = "stealth_"
    
    // MARK: - Initialization
    
    private init() {
        loadData()
        initializeScanProgress()
    }
    
    // MARK: - Key Generation
    
    /// Generate a new stealth key pair for a chain
    func generateKeyPair(for chain: StealthChain, label: String? = nil) async throws -> StealthKeyPair {
        isGeneratingKeys = true
        defer { isGeneratingKeys = false }
        
        // Generate spending key pair using secp256k1 (simulated with P256 for demo)
        let spendingPrivateKey = P256.KeyAgreement.PrivateKey()
        let spendingPublicKey = spendingPrivateKey.publicKey
        
        // Generate viewing key pair
        let viewingPrivateKey = P256.KeyAgreement.PrivateKey()
        let viewingPublicKey = viewingPrivateKey.publicKey
        
        // Convert to compressed format (33 bytes)
        let spendPrivData = spendingPrivateKey.rawRepresentation
        let spendPubData = compressPublicKey(spendingPublicKey.rawRepresentation)
        let viewPrivData = viewingPrivateKey.rawRepresentation
        let viewPubData = compressPublicKey(viewingPublicKey.rawRepresentation)
        
        // Check if this should be default
        let isDefault = keyPairs.filter { $0.chain == chain }.isEmpty
        
        let keyPair = StealthKeyPair(
            chain: chain,
            spendingPrivateKey: spendPrivData,
            spendingPublicKey: spendPubData,
            viewingPrivateKey: viewPrivData,
            viewingPublicKey: viewPubData,
            label: label,
            isDefault: isDefault
        )
        
        keyPairs.append(keyPair)
        saveKeyPairs()
        
        #if DEBUG
        print("✅ Generated stealth key pair for \(chain.displayName)")
        #endif
        return keyPair
    }
    
    /// Set a key pair as default for its chain
    func setDefaultKeyPair(_ keyPair: StealthKeyPair) {
        for i in keyPairs.indices {
            if keyPairs[i].chain == keyPair.chain {
                keyPairs[i].isDefault = (keyPairs[i].id == keyPair.id)
            }
        }
        saveKeyPairs()
    }
    
    /// Delete a key pair (with confirmation that funds are spent)
    func deleteKeyPair(_ keyPair: StealthKeyPair) throws {
        // Check for unspent payments
        let unspentPayments = receivedPayments.filter { 
            $0.keyPairId == keyPair.id && !$0.isSpent 
        }
        
        if !unspentPayments.isEmpty {
            throw StealthError.unspentFundsExist(count: unspentPayments.count)
        }
        
        keyPairs.removeAll { $0.id == keyPair.id }
        saveKeyPairs()
    }
    
    /// Update label for a key pair
    func updateKeyPairLabel(_ keyPair: StealthKeyPair, label: String?) {
        if let index = keyPairs.firstIndex(where: { $0.id == keyPair.id }) {
            keyPairs[index].label = label
            saveKeyPairs()
        }
    }
    
    // MARK: - Sending Stealth Payments
    
    /// Compute a one-time address for sending to a stealth meta-address
    func computeStealthAddress(for metaAddress: String) throws -> OutgoingStealthPayment {
        // Parse the meta-address
        guard let (chain, spendPubKey, viewPubKey) = parseMetaAddress(metaAddress) else {
            throw StealthError.invalidMetaAddress
        }
        
        // Generate ephemeral key pair
        let ephemeralPrivateKey = P256.KeyAgreement.PrivateKey()
        let ephemeralPublicKey = ephemeralPrivateKey.publicKey
        
        // Perform ECDH: shared_secret = ephemeral_private * view_public
        let viewPublicKey = try P256.KeyAgreement.PublicKey(rawRepresentation: decompressPublicKey(viewPubKey))
        let sharedSecret = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: viewPublicKey)
        
        // Derive the stealth public key: P = spend_public + hash(shared_secret) * G
        let secretHash = SHA256.hash(data: sharedSecret.withUnsafeBytes { Data($0) })
        let oneTimeAddress = deriveOneTimeAddress(
            spendPublicKey: spendPubKey,
            secretHash: Data(secretHash),
            chain: chain
        )
        
        let payment = OutgoingStealthPayment(
            chain: chain,
            recipientMetaAddress: metaAddress,
            ephemeralPrivateKey: ephemeralPrivateKey.rawRepresentation,
            ephemeralPublicKey: compressPublicKey(ephemeralPublicKey.rawRepresentation),
            oneTimeAddress: oneTimeAddress,
            amount: 0 // Set when actually sending
        )
        
        outgoingPayments.append(payment)
        saveOutgoingPayments()
        
        #if DEBUG
        print("✅ Computed stealth address: \(oneTimeAddress)")
        #endif
        return payment
    }
    
    /// Update outgoing payment after broadcast
    func updateOutgoingPayment(_ payment: OutgoingStealthPayment, txHash: String, amount: UInt64, status: OutgoingStealthPayment.PaymentStatus) {
        if let index = outgoingPayments.firstIndex(where: { $0.id == payment.id }) {
            outgoingPayments[index].txHash = txHash
            outgoingPayments[index].status = status
            saveOutgoingPayments()
        }
    }
    
    // MARK: - Scanning for Payments
    
    /// Scan blockchain for incoming stealth payments
    func scanForPayments(chain: StealthChain, fromBlock: UInt64? = nil) async {
        guard !isScanningBlockchain else { return }
        
        isScanningBlockchain = true
        defer { isScanningBlockchain = false }
        
        let keyPairsForChain = keyPairs.filter { $0.chain == chain }
        guard !keyPairsForChain.isEmpty else {
            lastError = "No stealth keys for \(chain.displayName)"
            return
        }
        
        var progress = scanProgress[chain] ?? ScanProgress(
            chain: chain,
            lastScannedBlock: 0,
            totalBlocks: 0,
            isScanning: true,
            paymentsFound: 0
        )
        
        progress.isScanning = true
        scanProgress[chain] = progress
        
        // Simulate scanning (in production, would query blockchain)
        let startBlock = fromBlock ?? progress.lastScannedBlock
        let currentBlock = await getCurrentBlockHeight(chain: chain)
        
        progress.totalBlocks = currentBlock
        scanProgress[chain] = progress
        
        #if DEBUG
        print("🔍 Scanning \(chain.displayName) from block \(startBlock) to \(currentBlock)")
        #endif
        
        // Simulate finding payments (demo mode)
        // In production: iterate through blocks, find outputs, try to decrypt with viewing key
        for block in stride(from: startBlock, to: currentBlock, by: 1000) {
            // Update progress
            progress.lastScannedBlock = min(block + 1000, currentBlock)
            scanProgress[chain] = progress
            
            // Small delay to show progress
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
        
        progress.isScanning = false
        progress.lastScanDate = Date()
        scanProgress[chain] = progress
        saveScanProgress()
        
        #if DEBUG
        print("✅ Scan complete for \(chain.displayName)")
        #endif
    }
    
    /// Check if a transaction output belongs to us
    func checkOutput(ephemeralPubKey: Data, outputAddress: String, chain: StealthChain) -> StealthPayment? {
        for keyPair in keyPairs.filter({ $0.chain == chain }) {
            // Perform ECDH: shared_secret = viewing_private * ephemeral_public
            guard let ephemeralPublic = try? P256.KeyAgreement.PublicKey(rawRepresentation: decompressPublicKey(ephemeralPubKey)),
                  let viewingPrivate = try? P256.KeyAgreement.PrivateKey(rawRepresentation: keyPair.viewingPrivateKey) else {
                continue
            }
            
            guard let sharedSecret = try? viewingPrivate.sharedSecretFromKeyAgreement(with: ephemeralPublic) else {
                continue
            }
            
            // Derive expected address
            let secretHash = SHA256.hash(data: sharedSecret.withUnsafeBytes { Data($0) })
            let expectedAddress = deriveOneTimeAddress(
                spendPublicKey: keyPair.spendingPublicKey,
                secretHash: Data(secretHash),
                chain: chain
            )
            
            if expectedAddress == outputAddress {
                // Found a payment! Derive the spending key
                let spendingKey = deriveSpendingKey(
                    spendingPrivateKey: keyPair.spendingPrivateKey,
                    secretHash: Data(secretHash)
                )
                
                let payment = StealthPayment(
                    chain: chain,
                    ephemeralPublicKey: ephemeralPubKey,
                    oneTimeAddress: outputAddress,
                    encryptedSpendingKey: spendingKey, // Should encrypt in production
                    amount: 0, // Would get from transaction
                    txHash: "", // Would get from transaction
                    blockHeight: 0,
                    keyPairId: keyPair.id
                )
                
                return payment
            }
        }
        
        return nil
    }
    
    /// Mark a payment as spent
    func markPaymentSpent(_ payment: StealthPayment, txHash: String) {
        if let index = receivedPayments.firstIndex(where: { $0.id == payment.id }) {
            receivedPayments[index].isSpent = true
            saveReceivedPayments()
        }
    }
    
    /// Add note to payment
    func updatePaymentNote(_ payment: StealthPayment, note: String?) {
        if let index = receivedPayments.firstIndex(where: { $0.id == payment.id }) {
            receivedPayments[index].note = note
            saveReceivedPayments()
        }
    }
    
    // MARK: - Statistics
    
    func getStatistics(for chain: StealthChain) -> StealthStatistics {
        let chainKeyPairs = keyPairs.filter { $0.chain == chain }
        let chainReceived = receivedPayments.filter { $0.chain == chain }
        let chainOutgoing = outgoingPayments.filter { $0.chain == chain }
        
        return StealthStatistics(
            chain: chain,
            keyPairCount: chainKeyPairs.count,
            receivedPayments: chainReceived.count,
            unspentPayments: chainReceived.filter { !$0.isSpent }.count,
            outgoingPayments: chainOutgoing.count,
            totalReceived: chainReceived.reduce(0) { $0 + $1.amount },
            totalSent: chainOutgoing.reduce(0) { $0 + $1.amount }
        )
    }
    
    // MARK: - Helper Methods
    
    private func compressPublicKey(_ rawKey: Data) -> Data {
        // Simulated compression - in production use proper secp256k1
        // Raw P256 key is 64 bytes (x, y), compressed is 33 bytes (prefix + x)
        guard rawKey.count >= 32 else { return rawKey }
        
        let x = rawKey.prefix(32)
        let y = rawKey.suffix(32)
        let prefix: UInt8 = (y.last ?? 0) % 2 == 0 ? 0x02 : 0x03
        
        return Data([prefix]) + x
    }
    
    private func decompressPublicKey(_ compressed: Data) -> Data {
        // Simulated decompression - returns padded data for P256
        guard compressed.count == 33 else { return compressed }
        
        let x = compressed.dropFirst()
        // For demo, just pad with zeros (production would compute y from curve equation)
        return x + Data(repeating: 0, count: 32)
    }
    
    private func parseMetaAddress(_ metaAddress: String) -> (StealthChain, Data, Data)? {
        for chain in StealthChain.allCases {
            if metaAddress.hasPrefix(chain.stealthPrefix) {
                let hexPart = String(metaAddress.dropFirst(chain.stealthPrefix.count))
                guard hexPart.count == 132 else { return nil } // 66 chars per key
                
                let spendHex = String(hexPart.prefix(66))
                let viewHex = String(hexPart.suffix(66))
                
                guard let spendData = Data(hexString: spendHex),
                      let viewData = Data(hexString: viewHex) else {
                    return nil
                }
                
                return (chain, spendData, viewData)
            }
        }
        return nil
    }
    
    private func deriveOneTimeAddress(spendPublicKey: Data, secretHash: Data, chain: StealthChain) -> String {
        // Simplified address derivation - production would use proper EC math
        let combined = spendPublicKey + secretHash
        let hash = SHA256.hash(data: combined)
        let addressData = Data(hash).prefix(20)
        
        switch chain {
        case .bitcoin:
            return "bc1q" + addressData.hexString.prefix(38)
        case .ethereum:
            return "0x" + addressData.hexString.prefix(40)
        case .litecoin:
            return "ltc1q" + addressData.hexString.prefix(38)
        }
    }
    
    private func deriveSpendingKey(spendingPrivateKey: Data, secretHash: Data) -> Data {
        // spending_key = spending_private + hash(shared_secret)
        // Simplified - production would use proper modular addition
        var result = Data(count: 32)
        for i in 0..<min(spendingPrivateKey.count, secretHash.count, 32) {
            result[i] = spendingPrivateKey[i] &+ secretHash[i]
        }
        return result
    }
    
    private func getCurrentBlockHeight(chain: StealthChain) async -> UInt64 {
        // Simulated - would query actual blockchain
        switch chain {
        case .bitcoin: return 820000
        case .ethereum: return 18500000
        case .litecoin: return 2600000
        }
    }
    
    private func initializeScanProgress() {
        for chain in StealthChain.allCases {
            if scanProgress[chain] == nil {
                scanProgress[chain] = ScanProgress(
                    chain: chain,
                    lastScannedBlock: 0,
                    totalBlocks: 0,
                    isScanning: false,
                    paymentsFound: 0
                )
            }
        }
    }
    
    // MARK: - Persistence
    
    private func saveKeyPairs() {
        if let data = try? JSONEncoder().encode(keyPairs) {
            userDefaults.set(data, forKey: keyPrefix + "keyPairs")
        }
    }
    
    private func saveReceivedPayments() {
        if let data = try? JSONEncoder().encode(receivedPayments) {
            userDefaults.set(data, forKey: keyPrefix + "receivedPayments")
        }
    }
    
    private func saveOutgoingPayments() {
        if let data = try? JSONEncoder().encode(outgoingPayments) {
            userDefaults.set(data, forKey: keyPrefix + "outgoingPayments")
        }
    }
    
    private func saveScanProgress() {
        if let data = try? JSONEncoder().encode(scanProgress) {
            userDefaults.set(data, forKey: keyPrefix + "scanProgress")
        }
    }
    
    private func saveSettings() {
        userDefaults.set(autoScanEnabled, forKey: keyPrefix + "autoScan")
        userDefaults.set(scanIntervalMinutes, forKey: keyPrefix + "scanInterval")
        userDefaults.set(notifyOnPayment, forKey: keyPrefix + "notifyOnPayment")
    }
    
    private func loadData() {
        // Load key pairs
        if let data = userDefaults.data(forKey: keyPrefix + "keyPairs"),
           let decoded = try? JSONDecoder().decode([StealthKeyPair].self, from: data) {
            keyPairs = decoded
        }
        
        // Load received payments
        if let data = userDefaults.data(forKey: keyPrefix + "receivedPayments"),
           let decoded = try? JSONDecoder().decode([StealthPayment].self, from: data) {
            receivedPayments = decoded
        }
        
        // Load outgoing payments
        if let data = userDefaults.data(forKey: keyPrefix + "outgoingPayments"),
           let decoded = try? JSONDecoder().decode([OutgoingStealthPayment].self, from: data) {
            outgoingPayments = decoded
        }
        
        // Load scan progress
        if let data = userDefaults.data(forKey: keyPrefix + "scanProgress"),
           let decoded = try? JSONDecoder().decode([StealthChain: ScanProgress].self, from: data) {
            scanProgress = decoded
        }
        
        // Load settings
        autoScanEnabled = userDefaults.bool(forKey: keyPrefix + "autoScan")
        scanIntervalMinutes = userDefaults.integer(forKey: keyPrefix + "scanInterval")
        if scanIntervalMinutes == 0 { scanIntervalMinutes = 15 }
        notifyOnPayment = userDefaults.bool(forKey: keyPrefix + "notifyOnPayment")
    }
}

// MARK: - Statistics Model

struct StealthStatistics {
    let chain: StealthChain
    let keyPairCount: Int
    let receivedPayments: Int
    let unspentPayments: Int
    let outgoingPayments: Int
    let totalReceived: UInt64
    let totalSent: UInt64
}

// MARK: - Errors

enum StealthError: LocalizedError {
    case invalidMetaAddress
    case keyGenerationFailed
    case unspentFundsExist(count: Int)
    case scanFailed(reason: String)
    case addressDerivationFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidMetaAddress:
            return "Invalid stealth meta-address format"
        case .keyGenerationFailed:
            return "Failed to generate stealth keys"
        case .unspentFundsExist(let count):
            return "Cannot delete: \(count) unspent payment(s) exist"
        case .scanFailed(let reason):
            return "Scan failed: \(reason)"
        case .addressDerivationFailed:
            return "Failed to derive one-time address"
        }
    }
}
