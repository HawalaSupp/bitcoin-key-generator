import Foundation
import CryptoKit

// MARK: - Address Intelligence Manager
// Phase 5.4: Smart Transaction Features - Address Intelligence

/// Supported blockchain types for address analysis
enum AddressBlockchain: String, Codable, CaseIterable {
    case bitcoin = "Bitcoin"
    case ethereum = "Ethereum"
    case litecoin = "Litecoin"
    case solana = "Solana"
    case xrp = "XRP"
    case unknown = "Unknown"
    
    var addressPrefix: [String] {
        switch self {
        case .bitcoin:
            return ["1", "3", "bc1", "tb1"]  // Legacy, SegWit, Bech32, Testnet
        case .ethereum:
            return ["0x"]
        case .litecoin:
            return ["L", "M", "ltc1"]
        case .solana:
            return []  // Base58 encoded, 32-44 chars
        case .xrp:
            return ["r"]
        case .unknown:
            return []
        }
    }
    
    static func detect(from address: String) -> AddressBlockchain {
        let addr = address.lowercased()
        
        // Ethereum
        if addr.hasPrefix("0x") && addr.count == 42 {
            return .ethereum
        }
        
        // Bitcoin
        if addr.hasPrefix("bc1") || addr.hasPrefix("tb1") {
            return .bitcoin
        }
        if (addr.hasPrefix("1") || addr.hasPrefix("3")) && addr.count >= 26 && addr.count <= 35 {
            return .bitcoin
        }
        
        // Litecoin
        if addr.hasPrefix("ltc1") {
            return .litecoin
        }
        if (address.hasPrefix("L") || address.hasPrefix("M")) && addr.count >= 26 && addr.count <= 35 {
            return .litecoin
        }
        
        // XRP
        if address.hasPrefix("r") && addr.count >= 25 && addr.count <= 35 {
            return .xrp
        }
        
        // Solana (base58, 32-44 chars)
        if addr.count >= 32 && addr.count <= 44 && !addr.contains("0") && !addr.contains("o") && !addr.contains("i") && !addr.contains("l") {
            return .solana
        }
        
        return .unknown
    }
}

/// Risk level for an address
enum AddressRiskLevel: String, Codable, Comparable {
    case safe = "Safe"
    case low = "Low Risk"
    case medium = "Medium Risk"
    case high = "High Risk"
    case critical = "Critical Risk"
    
    var icon: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .low: return "shield.fill"
        case .medium: return "exclamationmark.triangle.fill"
        case .high: return "exclamationmark.octagon.fill"
        case .critical: return "xmark.shield.fill"
        }
    }
    
    var color: String {
        switch self {
        case .safe: return "green"
        case .low: return "blue"
        case .medium: return "yellow"
        case .high: return "orange"
        case .critical: return "red"
        }
    }
    
    static func < (lhs: AddressRiskLevel, rhs: AddressRiskLevel) -> Bool {
        let order: [AddressRiskLevel] = [.safe, .low, .medium, .high, .critical]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

/// Type of known service
enum ServiceType: String, Codable {
    case exchange = "Exchange"
    case dex = "DEX"
    case defi = "DeFi"
    case bridge = "Bridge"
    case mixer = "Mixer"
    case gambling = "Gambling"
    case nftMarketplace = "NFT Marketplace"
    case wallet = "Wallet Service"
    case payment = "Payment Service"
    case scam = "Known Scam"
    case sanctioned = "Sanctioned"
    case unknown = "Unknown"
    
    var icon: String {
        switch self {
        case .exchange: return "building.columns.fill"
        case .dex: return "arrow.triangle.2.circlepath.circle.fill"
        case .defi: return "chart.line.uptrend.xyaxis.circle.fill"
        case .bridge: return "arrow.left.arrow.right.circle.fill"
        case .mixer: return "shuffle.circle.fill"
        case .gambling: return "dice.fill"
        case .nftMarketplace: return "photo.stack.fill"
        case .wallet: return "wallet.pass.fill"
        case .payment: return "creditcard.fill"
        case .scam: return "exclamationmark.shield.fill"
        case .sanctioned: return "hand.raised.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
    
    var riskLevel: AddressRiskLevel {
        switch self {
        case .exchange, .wallet, .payment: return .safe
        case .dex, .defi, .bridge, .nftMarketplace: return .low
        case .mixer, .gambling: return .medium
        case .scam: return .high
        case .sanctioned: return .critical
        case .unknown: return .low
        }
    }
}

/// Information about a known service
struct KnownService: Codable {
    let name: String
    let type: ServiceType
    let website: String?
    let isVerified: Bool
    let riskWarning: String?
}

/// Analysis result for an address
struct AddressAnalysis: Identifiable {
    let id = UUID()
    let address: String
    let blockchain: AddressBlockchain
    let isValid: Bool
    let checksumValid: Bool?  // nil if checksum not applicable
    
    // Historical data
    let firstSeen: Date?
    let lastActive: Date?
    let transactionCount: Int
    let totalReceived: Decimal?
    let totalSent: Decimal?
    
    // Service identification
    let knownService: KnownService?
    let isContract: Bool
    let contractName: String?
    
    // Risk assessment
    let riskLevel: AddressRiskLevel
    let riskFactors: [RiskFactor]
    let isScamReported: Bool
    let isSanctioned: Bool
    
    // User history
    let previouslySentTo: Bool
    let previouslySentCount: Int
    let lastSentDate: Date?
    let savedLabel: String?
    
    // Metadata
    let analysisDate: Date
    let dataSource: String
}

/// Individual risk factor
struct RiskFactor: Identifiable {
    let id = UUID()
    let level: AddressRiskLevel
    let title: String
    let description: String
    let recommendation: String?
}

/// Cached address info
struct CachedAddressInfo: Codable {
    let address: String
    let blockchain: AddressBlockchain
    let firstSeen: Date?
    let transactionCount: Int
    let knownServiceName: String?
    let knownServiceType: ServiceType?
    let isContract: Bool
    let lastUpdated: Date
}

/// User's address label for intelligence tracking
struct IntelAddressLabel: Codable, Identifiable {
    let id: UUID
    let address: String
    let label: String
    let notes: String?
    let createdAt: Date
    var lastUsed: Date?
    var sendCount: Int
}

// MARK: - Address Intelligence Manager

@MainActor
final class AddressIntelligenceManager: ObservableObject {
    static let shared = AddressIntelligenceManager()
    
    // MARK: - Published Properties
    
    @Published var addressLabels: [String: IntelAddressLabel] = [:]
    @Published var scamAddresses: Set<String> = []
    @Published var sanctionedAddresses: Set<String> = []
    @Published var addressCache: [String: CachedAddressInfo] = [:]
    @Published var isAnalyzing: Bool = false
    
    // MARK: - Private Properties
    
    private let userDefaults = UserDefaults.standard
    private let keyPrefix = "hawala_addr_intel_"
    private var knownExchanges: [String: KnownService] = [:]
    private var knownContracts: [String: KnownService] = [:]
    private var sentHistory: [String: (count: Int, lastDate: Date)] = [:]
    
    // MARK: - Initialization
    
    private init() {
        loadData()
        loadKnownServices()
        loadScamDatabase()
        loadSanctionedAddresses()
        
        print("🔍 Address Intelligence Manager initialized")
        print("   Labels: \(addressLabels.count)")
        print("   Cached addresses: \(addressCache.count)")
        print("   Known exchanges: \(knownExchanges.count)")
        print("   Scam addresses: \(scamAddresses.count)")
    }
    
    // MARK: - Public API
    
    /// Analyze an address for risks and information
    func analyzeAddress(_ address: String) async -> AddressAnalysis {
        isAnalyzing = true
        defer { isAnalyzing = false }
        
        let blockchain = AddressBlockchain.detect(from: address)
        let normalizedAddress = normalizeAddress(address, blockchain: blockchain)
        
        // Check validity
        let isValid = validateAddress(normalizedAddress, blockchain: blockchain)
        let checksumValid = validateChecksum(normalizedAddress, blockchain: blockchain)
        
        // Get cached data or fetch new
        var cachedInfo = addressCache[normalizedAddress]
        if cachedInfo == nil || shouldRefreshCache(cachedInfo!) {
            cachedInfo = await fetchAddressInfo(normalizedAddress, blockchain: blockchain)
            if let info = cachedInfo {
                addressCache[normalizedAddress] = info
                saveCache()
            }
        }
        
        // Check known services
        let knownService = lookupKnownService(normalizedAddress)
        
        // Check scam/sanctions
        let isScam = scamAddresses.contains(normalizedAddress.lowercased())
        let isSanctioned = sanctionedAddresses.contains(normalizedAddress.lowercased())
        
        // Get user history
        let label = addressLabels[normalizedAddress.lowercased()]
        let sentHistoryEntry = sentHistory[normalizedAddress.lowercased()]
        
        // Calculate risk factors
        let riskFactors = calculateRiskFactors(
            address: normalizedAddress,
            blockchain: blockchain,
            isValid: isValid,
            checksumValid: checksumValid,
            cachedInfo: cachedInfo,
            knownService: knownService,
            isScam: isScam,
            isSanctioned: isSanctioned,
            previouslySent: sentHistoryEntry != nil
        )
        
        // Overall risk level
        let overallRisk = calculateOverallRisk(riskFactors, isScam: isScam, isSanctioned: isSanctioned)
        
        return AddressAnalysis(
            address: normalizedAddress,
            blockchain: blockchain,
            isValid: isValid,
            checksumValid: checksumValid,
            firstSeen: cachedInfo?.firstSeen,
            lastActive: nil,
            transactionCount: cachedInfo?.transactionCount ?? 0,
            totalReceived: nil,
            totalSent: nil,
            knownService: knownService,
            isContract: cachedInfo?.isContract ?? false,
            contractName: cachedInfo?.knownServiceName,
            riskLevel: overallRisk,
            riskFactors: riskFactors,
            isScamReported: isScam,
            isSanctioned: isSanctioned,
            previouslySentTo: sentHistoryEntry != nil,
            previouslySentCount: sentHistoryEntry?.count ?? 0,
            lastSentDate: sentHistoryEntry?.lastDate,
            savedLabel: label?.label,
            analysisDate: Date(),
            dataSource: "Local Analysis"
        )
    }
    
    /// Quick check if an address is high risk
    func quickRiskCheck(_ address: String) -> AddressRiskLevel {
        let normalized = normalizeAddress(address, blockchain: AddressBlockchain.detect(from: address)).lowercased()
        
        // Critical checks
        if sanctionedAddresses.contains(normalized) {
            return .critical
        }
        if scamAddresses.contains(normalized) {
            return .high
        }
        
        // Check known services
        if let service = lookupKnownService(normalized) {
            return service.type.riskLevel
        }
        
        // Check if previously used
        if sentHistory[normalized] != nil {
            return .safe
        }
        
        return .medium  // Unknown address
    }
    
    /// Check for clipboard hijacking
    func detectClipboardHijack(expected: String, pasted: String) -> Bool {
        guard !expected.isEmpty && !pasted.isEmpty else { return false }
        guard expected != pasted else { return false }
        
        // Both should be same blockchain type
        let expectedChain = AddressBlockchain.detect(from: expected)
        let pastedChain = AddressBlockchain.detect(from: pasted)
        
        guard expectedChain == pastedChain else { return true }  // Different chains = suspicious
        
        // Check for similar prefix/suffix (common hijack pattern)
        let expectedNorm = expected.lowercased()
        let pastedNorm = pasted.lowercased()
        
        // If only a few characters differ in the middle, it's suspicious
        if expectedNorm.prefix(4) == pastedNorm.prefix(4) && 
           expectedNorm.suffix(4) == pastedNorm.suffix(4) &&
           expectedNorm != pastedNorm {
            return true
        }
        
        return false
    }
    
    /// Validate address format and checksum
    func validateAddressFully(_ address: String) -> (isValid: Bool, checksumValid: Bool?, errors: [String]) {
        let blockchain = AddressBlockchain.detect(from: address)
        var errors: [String] = []
        
        let isValid = validateAddress(address, blockchain: blockchain)
        if !isValid {
            errors.append("Invalid address format for \(blockchain.rawValue)")
        }
        
        let checksumValid = validateChecksum(address, blockchain: blockchain)
        if let checksum = checksumValid, !checksum {
            errors.append("Address checksum validation failed")
        }
        
        return (isValid, checksumValid, errors)
    }
    
    // MARK: - Label Management
    
    /// Add or update an address label
    func setLabel(for address: String, label: String, notes: String? = nil) {
        let normalized = normalizeAddress(address, blockchain: AddressBlockchain.detect(from: address)).lowercased()
        
        if var existing = addressLabels[normalized] {
            existing = IntelAddressLabel(
                id: existing.id,
                address: existing.address,
                label: label,
                notes: notes ?? existing.notes,
                createdAt: existing.createdAt,
                lastUsed: existing.lastUsed,
                sendCount: existing.sendCount
            )
            addressLabels[normalized] = existing
        } else {
            addressLabels[normalized] = IntelAddressLabel(
                id: UUID(),
                address: normalized,
                label: label,
                notes: notes,
                createdAt: Date(),
                lastUsed: nil,
                sendCount: 0
            )
        }
        saveLabels()
    }
    
    /// Remove an address label
    func removeLabel(for address: String) {
        let normalized = address.lowercased()
        addressLabels.removeValue(forKey: normalized)
        saveLabels()
    }
    
    /// Get label for an address
    func getLabel(for address: String) -> String? {
        let normalized = address.lowercased()
        return addressLabels[normalized]?.label ?? lookupKnownService(address)?.name
    }
    
    /// Record a send to an address
    func recordSend(to address: String) {
        let normalized = address.lowercased()
        
        if var existing = sentHistory[normalized] {
            existing.count += 1
            existing.lastDate = Date()
            sentHistory[normalized] = existing
        } else {
            sentHistory[normalized] = (count: 1, lastDate: Date())
        }
        
        // Update label if exists
        if var label = addressLabels[normalized] {
            label.lastUsed = Date()
            label.sendCount += 1
            addressLabels[normalized] = IntelAddressLabel(
                id: label.id,
                address: label.address,
                label: label.label,
                notes: label.notes,
                createdAt: label.createdAt,
                lastUsed: Date(),
                sendCount: label.sendCount + 1
            )
            saveLabels()
        }
        
        saveSentHistory()
    }
    
    /// Check if this is first time sending to address
    func isFirstTimeSend(to address: String) -> Bool {
        let normalized = address.lowercased()
        return sentHistory[normalized] == nil
    }
    
    // MARK: - Scam Reporting
    
    /// Report an address as scam
    func reportScam(_ address: String) {
        let normalized = address.lowercased()
        scamAddresses.insert(normalized)
        saveScamDatabase()
    }
    
    /// Remove scam report
    func removeScamReport(_ address: String) {
        let normalized = address.lowercased()
        scamAddresses.remove(normalized)
        saveScamDatabase()
    }
    
    // MARK: - Private Methods
    
    private func normalizeAddress(_ address: String, blockchain: AddressBlockchain) -> String {
        switch blockchain {
        case .ethereum:
            // Ethereum addresses should be checksum encoded
            return address.lowercased()  // Store lowercase, validate checksum separately
        default:
            return address
        }
    }
    
    private func validateAddress(_ address: String, blockchain: AddressBlockchain) -> Bool {
        switch blockchain {
        case .bitcoin:
            return validateBitcoinAddress(address)
        case .ethereum:
            return validateEthereumAddress(address)
        case .litecoin:
            return validateLitecoinAddress(address)
        case .solana:
            return validateSolanaAddress(address)
        case .xrp:
            return validateXRPAddress(address)
        case .unknown:
            return false
        }
    }
    
    private func validateBitcoinAddress(_ address: String) -> Bool {
        // Bech32 (SegWit)
        if address.lowercased().hasPrefix("bc1") || address.lowercased().hasPrefix("tb1") {
            return address.count >= 42 && address.count <= 62
        }
        // Legacy (P2PKH and P2SH)
        if address.hasPrefix("1") || address.hasPrefix("3") || address.hasPrefix("m") || address.hasPrefix("n") || address.hasPrefix("2") {
            return address.count >= 26 && address.count <= 35
        }
        return false
    }
    
    private func validateEthereumAddress(_ address: String) -> Bool {
        guard address.lowercased().hasPrefix("0x") else { return false }
        guard address.count == 42 else { return false }
        
        let hexPart = address.dropFirst(2)
        return hexPart.allSatisfy { $0.isHexDigit }
    }
    
    private func validateLitecoinAddress(_ address: String) -> Bool {
        if address.lowercased().hasPrefix("ltc1") {
            return address.count >= 42 && address.count <= 62
        }
        if address.hasPrefix("L") || address.hasPrefix("M") || address.hasPrefix("3") {
            return address.count >= 26 && address.count <= 35
        }
        return false
    }
    
    private func validateSolanaAddress(_ address: String) -> Bool {
        // Base58 encoded, 32-44 characters
        guard address.count >= 32 && address.count <= 44 else { return false }
        let base58Chars = CharacterSet(charactersIn: "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        return address.unicodeScalars.allSatisfy { base58Chars.contains($0) }
    }
    
    private func validateXRPAddress(_ address: String) -> Bool {
        guard address.hasPrefix("r") else { return false }
        guard address.count >= 25 && address.count <= 35 else { return false }
        let base58Chars = CharacterSet(charactersIn: "rpshnaf39wBUDNEGHJKLM4PQRST7VWXYZ2bcdeCg65jkm8oFqi1tuvAxyz")
        return address.unicodeScalars.allSatisfy { base58Chars.contains($0) }
    }
    
    private func validateChecksum(_ address: String, blockchain: AddressBlockchain) -> Bool? {
        switch blockchain {
        case .ethereum:
            return validateEthereumChecksum(address)
        default:
            return nil  // Checksum validation not implemented for other chains
        }
    }
    
    private func validateEthereumChecksum(_ address: String) -> Bool {
        guard address.hasPrefix("0x") && address.count == 42 else { return false }
        
        let addressWithoutPrefix = String(address.dropFirst(2))
        
        // All lowercase or all uppercase is valid (no checksum)
        if addressWithoutPrefix == addressWithoutPrefix.lowercased() ||
           addressWithoutPrefix == addressWithoutPrefix.uppercased() {
            return true
        }
        
        // Check EIP-55 checksum
        let lowercased = addressWithoutPrefix.lowercased()
        let hash = SHA256.hash(data: Data(lowercased.utf8))
        let hashHex = hash.compactMap { String(format: "%02x", $0) }.joined()
        
        for (i, char) in addressWithoutPrefix.enumerated() {
            guard i < hashHex.count else { break }
            let hashChar = hashHex[hashHex.index(hashHex.startIndex, offsetBy: i)]
            let hashValue = Int(String(hashChar), radix: 16) ?? 0
            
            if char.isLetter {
                let shouldBeUppercase = hashValue >= 8
                let isUppercase = char.isUppercase
                if shouldBeUppercase != isUppercase {
                    return false
                }
            }
        }
        
        return true
    }
    
    private func fetchAddressInfo(_ address: String, blockchain: AddressBlockchain) async -> CachedAddressInfo? {
        // In a real implementation, this would query blockchain APIs
        // For now, return basic info
        return CachedAddressInfo(
            address: address,
            blockchain: blockchain,
            firstSeen: nil,
            transactionCount: 0,
            knownServiceName: lookupKnownService(address)?.name,
            knownServiceType: lookupKnownService(address)?.type,
            isContract: false,
            lastUpdated: Date()
        )
    }
    
    private func shouldRefreshCache(_ info: CachedAddressInfo) -> Bool {
        // Refresh if older than 24 hours
        return Date().timeIntervalSince(info.lastUpdated) > 86400
    }
    
    private func lookupKnownService(_ address: String) -> KnownService? {
        let normalized = address.lowercased()
        return knownExchanges[normalized] ?? knownContracts[normalized]
    }
    
    private func calculateRiskFactors(
        address: String,
        blockchain: AddressBlockchain,
        isValid: Bool,
        checksumValid: Bool?,
        cachedInfo: CachedAddressInfo?,
        knownService: KnownService?,
        isScam: Bool,
        isSanctioned: Bool,
        previouslySent: Bool
    ) -> [RiskFactor] {
        var factors: [RiskFactor] = []
        
        // Invalid address
        if !isValid {
            factors.append(RiskFactor(
                level: .critical,
                title: "Invalid Address",
                description: "This address format is invalid for \(blockchain.rawValue)",
                recommendation: "Do not send to this address"
            ))
        }
        
        // Checksum failed
        if let checksum = checksumValid, !checksum {
            factors.append(RiskFactor(
                level: .high,
                title: "Checksum Failed",
                description: "The address checksum is invalid, indicating a typo or tampering",
                recommendation: "Verify the address character by character"
            ))
        }
        
        // Scam address
        if isScam {
            factors.append(RiskFactor(
                level: .high,
                title: "Reported Scam Address",
                description: "This address has been reported as a scam",
                recommendation: "Do not send funds to this address"
            ))
        }
        
        // Sanctioned
        if isSanctioned {
            factors.append(RiskFactor(
                level: .critical,
                title: "Sanctioned Address",
                description: "This address is on sanctions lists",
                recommendation: "Sending to this address may be illegal"
            ))
        }
        
        // Known service risks
        if let service = knownService {
            if service.type == .mixer {
                factors.append(RiskFactor(
                    level: .medium,
                    title: "Mixer Service",
                    description: "This is a cryptocurrency mixing service",
                    recommendation: "Be aware of legal implications in your jurisdiction"
                ))
            }
            if service.type == .gambling {
                factors.append(RiskFactor(
                    level: .medium,
                    title: "Gambling Platform",
                    description: "This is a gambling service",
                    recommendation: "Ensure gambling is legal in your jurisdiction"
                ))
            }
            if let warning = service.riskWarning {
                factors.append(RiskFactor(
                    level: .low,
                    title: "Service Warning",
                    description: warning,
                    recommendation: nil
                ))
            }
        }
        
        // First time sending
        if !previouslySent && knownService == nil {
            factors.append(RiskFactor(
                level: .medium,
                title: "First Time Recipient",
                description: "You have never sent to this address before",
                recommendation: "Double-check the address is correct"
            ))
        }
        
        // New/unknown address
        if cachedInfo?.transactionCount == 0 && knownService == nil {
            factors.append(RiskFactor(
                level: .low,
                title: "New Address",
                description: "This address has no transaction history",
                recommendation: "Consider sending a small test amount first"
            ))
        }
        
        return factors
    }
    
    private func calculateOverallRisk(_ factors: [RiskFactor], isScam: Bool, isSanctioned: Bool) -> AddressRiskLevel {
        if isSanctioned {
            return .critical
        }
        if isScam {
            return .high
        }
        
        if factors.contains(where: { $0.level == .critical }) {
            return .critical
        }
        if factors.contains(where: { $0.level == .high }) {
            return .high
        }
        if factors.contains(where: { $0.level == .medium }) {
            return .medium
        }
        if factors.contains(where: { $0.level == .low }) {
            return .low
        }
        
        return .safe
    }
    
    // MARK: - Known Services Database
    
    private func loadKnownServices() {
        // Major Exchanges
        knownExchanges = [
            // Coinbase
            "0x71660c4005ba85c37ccec55d0c4493e66fe775d3": KnownService(name: "Coinbase", type: .exchange, website: "coinbase.com", isVerified: true, riskWarning: nil),
            "0x503828976d22510aad0201ac7ec88293211d23da": KnownService(name: "Coinbase 2", type: .exchange, website: "coinbase.com", isVerified: true, riskWarning: nil),
            "0xddfabcdc4d8ffc6d5beaf154f18b778f892a0740": KnownService(name: "Coinbase 3", type: .exchange, website: "coinbase.com", isVerified: true, riskWarning: nil),
            
            // Binance
            "0x3f5ce5fbfe3e9af3971dd833d26ba9b5c936f0be": KnownService(name: "Binance", type: .exchange, website: "binance.com", isVerified: true, riskWarning: nil),
            "0xd551234ae421e3bcba99a0da6d736074f22192ff": KnownService(name: "Binance 2", type: .exchange, website: "binance.com", isVerified: true, riskWarning: nil),
            "0x564286362092d8e7936f0549571a803b203aaced": KnownService(name: "Binance 3", type: .exchange, website: "binance.com", isVerified: true, riskWarning: nil),
            "0x28c6c06298d514db089934071355e5743bf21d60": KnownService(name: "Binance 14", type: .exchange, website: "binance.com", isVerified: true, riskWarning: nil),
            
            // Kraken
            "0x2910543af39aba0cd09dbb2d50200b3e800a63d2": KnownService(name: "Kraken", type: .exchange, website: "kraken.com", isVerified: true, riskWarning: nil),
            "0x0a869d79a7052c7f1b55a8ebabbea3420f0d1e13": KnownService(name: "Kraken 2", type: .exchange, website: "kraken.com", isVerified: true, riskWarning: nil),
            
            // Gemini
            "0xd24400ae8bfebb18ca49be86258a3c749cf46853": KnownService(name: "Gemini", type: .exchange, website: "gemini.com", isVerified: true, riskWarning: nil),
            "0x6fc82a5fe25a5cdb58bc74600a40a69c065263f8": KnownService(name: "Gemini 2", type: .exchange, website: "gemini.com", isVerified: true, riskWarning: nil),
            
            // FTX (defunct)
            "0x2faf487a4414fe77e2327f0bf4ae2a264a776ad2": KnownService(name: "FTX (Defunct)", type: .exchange, website: nil, isVerified: true, riskWarning: "FTX is defunct - do not send funds"),
        ]
        
        // DeFi Contracts
        knownContracts = [
            // Uniswap
            "0x7a250d5630b4cf539739df2c5dacb4c659f2488d": KnownService(name: "Uniswap V2 Router", type: .dex, website: "uniswap.org", isVerified: true, riskWarning: nil),
            "0xe592427a0aece92de3edee1f18e0157c05861564": KnownService(name: "Uniswap V3 Router", type: .dex, website: "uniswap.org", isVerified: true, riskWarning: nil),
            "0x68b3465833fb72a70ecdf485e0e4c7bd8665fc45": KnownService(name: "Uniswap Universal Router", type: .dex, website: "uniswap.org", isVerified: true, riskWarning: nil),
            
            // Aave
            "0x7d2768de32b0b80b7a3454c06bdac94a69ddc7a9": KnownService(name: "Aave V2 Pool", type: .defi, website: "aave.com", isVerified: true, riskWarning: nil),
            "0x87870bca3f3fd6335c3f4ce8392d69350b4fa4e2": KnownService(name: "Aave V3 Pool", type: .defi, website: "aave.com", isVerified: true, riskWarning: nil),
            
            // Compound
            "0x3d9819210a31b4961b30ef54be2aed79b9c9cd3b": KnownService(name: "Compound Comptroller", type: .defi, website: "compound.finance", isVerified: true, riskWarning: nil),
            
            // OpenSea
            "0x00000000006c3852cbef3e08e8df289169ede581": KnownService(name: "OpenSea Seaport", type: .nftMarketplace, website: "opensea.io", isVerified: true, riskWarning: nil),
            "0x00000000000000adc04c56bf30ac9d3c0aaf14dc": KnownService(name: "OpenSea Seaport 1.5", type: .nftMarketplace, website: "opensea.io", isVerified: true, riskWarning: nil),
            
            // Bridges
            "0x3ee18b2214aff97000d974cf647e7c347e8fa585": KnownService(name: "Wormhole Bridge", type: .bridge, website: "wormhole.com", isVerified: true, riskWarning: "Bridge transactions may take time to complete"),
            
            // Tornado Cash (Sanctioned)
            "0x722122df12d4e14e13ac3b6895a86e84145b6967": KnownService(name: "Tornado Cash", type: .mixer, website: nil, isVerified: true, riskWarning: "OFAC Sanctioned - Using this service is illegal in many jurisdictions"),
        ]
    }
    
    private func loadScamDatabase() {
        // Load from UserDefaults
        let key = keyPrefix + "scam_addresses"
        if let data = userDefaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            scamAddresses = decoded
        }
        
        // Add some known scam patterns (these would be updated from an online source in production)
        // Note: These are examples, not real scam addresses
    }
    
    private func loadSanctionedAddresses() {
        // OFAC sanctioned addresses (public list)
        sanctionedAddresses = [
            // Tornado Cash addresses (sanctioned by OFAC)
            "0x722122df12d4e14e13ac3b6895a86e84145b6967",
            "0xdd4c48c0b24039969fc16d1cdf626eab821d3384",
            "0xd90e2f925da726b50c4ed8d0fb90ad053324f31b",
            "0xd96f2b1c14db8458374d9aca76e26c3d18364307",
            "0x4736dcf1b7a3d580672cce6e7c65cd5cc9cfba9d",
        ].map { $0.lowercased() }.reduce(into: Set<String>()) { $0.insert($1) }
    }
    
    // MARK: - Persistence
    
    private func loadData() {
        loadLabels()
        loadCache()
        loadSentHistory()
    }
    
    private func loadLabels() {
        let key = keyPrefix + "labels"
        if let data = userDefaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: IntelAddressLabel].self, from: data) {
            addressLabels = decoded
        }
    }
    
    private func saveLabels() {
        let key = keyPrefix + "labels"
        if let data = try? JSONEncoder().encode(addressLabels) {
            userDefaults.set(data, forKey: key)
        }
    }
    
    private func loadCache() {
        let key = keyPrefix + "cache"
        if let data = userDefaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: CachedAddressInfo].self, from: data) {
            addressCache = decoded
        }
    }
    
    private func saveCache() {
        let key = keyPrefix + "cache"
        if let data = try? JSONEncoder().encode(addressCache) {
            userDefaults.set(data, forKey: key)
        }
    }
    
    private func loadSentHistory() {
        let key = keyPrefix + "sent_history"
        if let data = userDefaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: SentHistoryEntry].self, from: data) {
            sentHistory = decoded.mapValues { ($0.count, $0.lastDate) }
        }
    }
    
    private func saveSentHistory() {
        let key = keyPrefix + "sent_history"
        let encodable = sentHistory.mapValues { SentHistoryEntry(count: $0.count, lastDate: $0.lastDate) }
        if let data = try? JSONEncoder().encode(encodable) {
            userDefaults.set(data, forKey: key)
        }
    }
    
    private func saveScamDatabase() {
        let key = keyPrefix + "scam_addresses"
        if let data = try? JSONEncoder().encode(scamAddresses) {
            userDefaults.set(data, forKey: key)
        }
    }
}

// Helper for encoding sent history
private struct SentHistoryEntry: Codable {
    let count: Int
    let lastDate: Date
}
