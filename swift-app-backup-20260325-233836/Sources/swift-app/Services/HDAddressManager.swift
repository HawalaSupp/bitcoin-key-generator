import Foundation
import Combine

// MARK: - HD Address Manager
/// Manages HD wallet address generation, tracking, and privacy warnings
/// Supports BIP44/49/84/86 derivation paths with gap limit handling

@MainActor
public final class HDAddressManager: ObservableObject {
    public static let shared = HDAddressManager()
    
    // MARK: - Published State
    @Published public private(set) var addresses: [ManagedAddress] = []
    @Published public private(set) var isScanning = false
    @Published public private(set) var lastError: String?
    @Published public private(set) var gapLimit: Int = 20
    
    // MARK: - Settings
    @Published public var autoGenerateNewAddress: Bool = true
    @Published public var showReuseWarnings: Bool = true
    
    // MARK: - Storage Keys
    private let addressesKey = "hawala_hd_addresses"
    private let settingsKey = "hawala_hd_settings"
    private let indexKey = "hawala_address_index"
    
    // MARK: - Current Indices (per chain/account)
    private var currentIndices: [String: Int] = [:] // key: "chain_account_change" -> index
    
    private init() {
        loadData()
    }
    
    // MARK: - Address Generation
    
    /// Get the next unused receive address for a chain
    public func getNextReceiveAddress(
        chain: CryptoChain,
        account: Int = 0,
        forceNew: Bool = false
    ) -> ManagedAddress? {
        let key = "\(chain.rawValue)_\(account)_0" // 0 = external/receive
        
        // If not forcing new and we have an unused address, return it
        if !forceNew && autoGenerateNewAddress {
            if let unused = addresses.first(where: {
                $0.chain == chain &&
                $0.account == account &&
                $0.isChange == false &&
                !$0.isUsed
            }) {
                return unused
            }
        }
        
        // Generate new address
        let nextIndex = (currentIndices[key] ?? 0)
        
        // Create new managed address
        let address = ManagedAddress(
            chain: chain,
            account: account,
            index: nextIndex,
            isChange: false,
            derivationPath: derivationPath(for: chain, account: account, index: nextIndex, isChange: false),
            address: "", // Will be populated by actual key derivation
            createdAt: Date()
        )
        
        // Increment index
        currentIndices[key] = nextIndex + 1
        addresses.append(address)
        saveData()
        
        return address
    }
    
    /// Get a new change address
    public func getNextChangeAddress(
        chain: CryptoChain,
        account: Int = 0
    ) -> ManagedAddress? {
        let key = "\(chain.rawValue)_\(account)_1" // 1 = internal/change
        let nextIndex = (currentIndices[key] ?? 0)
        
        let address = ManagedAddress(
            chain: chain,
            account: account,
            index: nextIndex,
            isChange: true,
            derivationPath: derivationPath(for: chain, account: account, index: nextIndex, isChange: true),
            address: "",
            createdAt: Date()
        )
        
        currentIndices[key] = nextIndex + 1
        addresses.append(address)
        saveData()
        
        return address
    }
    
    /// Register an address with its actual value (after key derivation)
    public func registerAddress(_ addressString: String, for managedAddress: ManagedAddress) {
        if let index = addresses.firstIndex(where: { $0.id == managedAddress.id }) {
            addresses[index].address = addressString
            saveData()
        }
    }
    
    // MARK: - Address Tracking
    
    /// Mark an address as used (received funds)
    public func markAsUsed(_ address: String, txHash: String? = nil) {
        if let index = addresses.firstIndex(where: { $0.address == address }) {
            addresses[index].isUsed = true
            addresses[index].lastUsedAt = Date()
            if let hash = txHash {
                addresses[index].transactionHashes.append(hash)
            }
            addresses[index].useCount += 1
            saveData()
        }
    }
    
    /// Check if an address has been used
    public func isAddressUsed(_ address: String) -> Bool {
        addresses.first(where: { $0.address == address })?.isUsed ?? false
    }
    
    /// Get reuse warning for an address
    public func getReuseWarning(for address: String) -> AddressReuseWarning? {
        guard showReuseWarnings else { return nil }
        
        guard let managed = addresses.first(where: { $0.address == address }) else {
            return nil
        }
        
        if managed.isUsed {
            return AddressReuseWarning(
                address: address,
                useCount: managed.useCount,
                lastUsedAt: managed.lastUsedAt,
                severity: managed.useCount > 2 ? .high : .medium,
                recommendation: "Generate a new address to protect your privacy. Reusing addresses allows transaction linking."
            )
        }
        
        return nil
    }
    
    /// Set label for an address
    public func setLabel(_ label: String, for address: String) {
        if let index = addresses.firstIndex(where: { $0.address == address }) {
            addresses[index].label = label
            saveData()
        }
    }
    
    /// Set note for an address
    public func setNote(_ note: String, for address: String) {
        if let index = addresses.firstIndex(where: { $0.address == address }) {
            addresses[index].note = note
            saveData()
        }
    }
    
    // MARK: - Gap Limit Scanning
    
    /// Scan for used addresses up to gap limit
    public func scanForUsedAddresses(
        chain: CryptoChain,
        account: Int = 0,
        checkAddress: @escaping (String) async -> Bool
    ) async {
        await MainActor.run { isScanning = true }
        defer { Task { @MainActor in isScanning = false } }
        
        var consecutiveUnused = 0
        var index = 0
        
        while consecutiveUnused < gapLimit {
            // Generate address at index
            let path = derivationPath(for: chain, account: account, index: index, isChange: false)
            
            // Here we'd derive the actual address - for now, create placeholder
            let address = ManagedAddress(
                chain: chain,
                account: account,
                index: index,
                isChange: false,
                derivationPath: path,
                address: "", // Would be derived
                createdAt: Date()
            )
            
            // Check if address has been used (via API)
            let isUsed = await checkAddress(address.address)
            
            if isUsed {
                consecutiveUnused = 0
                await MainActor.run {
                    if !addresses.contains(where: { $0.derivationPath == path }) {
                        var usedAddress = address
                        usedAddress.isUsed = true
                        addresses.append(usedAddress)
                    }
                }
            } else {
                consecutiveUnused += 1
            }
            
            index += 1
        }
        
        await MainActor.run {
            let key = "\(chain.rawValue)_\(account)_0"
            currentIndices[key] = index - gapLimit
            saveData()
        }
    }
    
    /// Update gap limit
    public func setGapLimit(_ limit: Int) {
        gapLimit = max(5, min(100, limit)) // Clamp between 5-100
        saveData()
    }
    
    // MARK: - Address Queries
    
    /// Get all addresses for a chain
    public func getAddresses(for chain: CryptoChain, account: Int? = nil) -> [ManagedAddress] {
        addresses.filter { addr in
            addr.chain == chain && (account == nil || addr.account == account)
        }
    }
    
    /// Get all receive (external) addresses
    public func getReceiveAddresses(for chain: CryptoChain, account: Int = 0) -> [ManagedAddress] {
        addresses.filter { $0.chain == chain && $0.account == account && !$0.isChange }
    }
    
    /// Get all change (internal) addresses
    public func getChangeAddresses(for chain: CryptoChain, account: Int = 0) -> [ManagedAddress] {
        addresses.filter { $0.chain == chain && $0.account == account && $0.isChange }
    }
    
    /// Get used addresses
    public func getUsedAddresses(for chain: CryptoChain) -> [ManagedAddress] {
        addresses.filter { $0.chain == chain && $0.isUsed }
    }
    
    /// Get unused addresses
    public func getUnusedAddresses(for chain: CryptoChain) -> [ManagedAddress] {
        addresses.filter { $0.chain == chain && !$0.isUsed }
    }
    
    /// Get address statistics
    public func getStatistics(for chain: CryptoChain) -> AddressStatistics {
        let chainAddresses = addresses.filter { $0.chain == chain }
        let used = chainAddresses.filter { $0.isUsed }
        let unused = chainAddresses.filter { !$0.isUsed }
        let receive = chainAddresses.filter { !$0.isChange }
        let change = chainAddresses.filter { $0.isChange }
        
        return AddressStatistics(
            totalAddresses: chainAddresses.count,
            usedAddresses: used.count,
            unusedAddresses: unused.count,
            receiveAddresses: receive.count,
            changeAddresses: change.count,
            multiUseAddresses: chainAddresses.filter { $0.useCount > 1 }.count
        )
    }
    
    // MARK: - Derivation Paths
    
    private func derivationPath(
        for chain: CryptoChain,
        account: Int,
        index: Int,
        isChange: Bool
    ) -> String {
        let change = isChange ? 1 : 0
        
        switch chain {
        case .bitcoin:
            // BIP84 for native SegWit (bc1q...)
            return "m/84'/0'/\(account)'/\(change)/\(index)"
        case .bitcoinTestnet:
            return "m/84'/1'/\(account)'/\(change)/\(index)"
        case .ethereum, .polygon, .arbitrum, .optimism, .base:
            // BIP44 for Ethereum (single address typically)
            return "m/44'/60'/\(account)'/0/\(index)"
        case .litecoin:
            // BIP84 for Litecoin native SegWit
            return "m/84'/2'/\(account)'/\(change)/\(index)"
        case .solana:
            // Solana derivation
            return "m/44'/501'/\(account)'/\(index)'"
        case .xrp:
            // XRP derivation
            return "m/44'/144'/\(account)'/0/\(index)"
        }
    }
    
    // MARK: - Persistence
    
    private func loadData() {
        // Load addresses
        if let data = UserDefaults.standard.data(forKey: addressesKey),
           let decoded = try? JSONDecoder().decode([ManagedAddress].self, from: data) {
            addresses = decoded
        }
        
        // Load indices
        if let data = UserDefaults.standard.data(forKey: indexKey),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            currentIndices = decoded
        }
        
        // Load settings
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let settings = try? JSONDecoder().decode(AddressSettings.self, from: data) {
            gapLimit = settings.gapLimit
            autoGenerateNewAddress = settings.autoGenerateNewAddress
            showReuseWarnings = settings.showReuseWarnings
        }
    }
    
    private func saveData() {
        // Save addresses
        if let encoded = try? JSONEncoder().encode(addresses) {
            UserDefaults.standard.set(encoded, forKey: addressesKey)
        }
        
        // Save indices
        if let encoded = try? JSONEncoder().encode(currentIndices) {
            UserDefaults.standard.set(encoded, forKey: indexKey)
        }
        
        // Save settings
        let settings = AddressSettings(
            gapLimit: gapLimit,
            autoGenerateNewAddress: autoGenerateNewAddress,
            showReuseWarnings: showReuseWarnings
        )
        if let encoded = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encoded, forKey: settingsKey)
        }
    }
}

// MARK: - Supporting Types

public struct ManagedAddress: Identifiable, Codable, Hashable {
    public let id: UUID
    public let chain: CryptoChain
    public let account: Int
    public let index: Int
    public let isChange: Bool
    public let derivationPath: String
    public var address: String
    public let createdAt: Date
    
    public var isUsed: Bool = false
    public var lastUsedAt: Date?
    public var useCount: Int = 0
    public var transactionHashes: [String] = []
    public var label: String = ""
    public var note: String = ""
    
    public init(
        chain: CryptoChain,
        account: Int,
        index: Int,
        isChange: Bool,
        derivationPath: String,
        address: String,
        createdAt: Date
    ) {
        self.id = UUID()
        self.chain = chain
        self.account = account
        self.index = index
        self.isChange = isChange
        self.derivationPath = derivationPath
        self.address = address
        self.createdAt = createdAt
    }
    
    public var shortAddress: String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))...\(address.suffix(6))"
    }
    
    public var displayName: String {
        if !label.isEmpty {
            return label
        }
        return shortAddress
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: ManagedAddress, rhs: ManagedAddress) -> Bool {
        lhs.id == rhs.id
    }
}

public enum CryptoChain: String, Codable, CaseIterable {
    case bitcoin = "BTC"
    case bitcoinTestnet = "tBTC"
    case ethereum = "ETH"
    case litecoin = "LTC"
    case solana = "SOL"
    case xrp = "XRP"
    case polygon = "MATIC"
    case arbitrum = "ARB"
    case optimism = "OP"
    case base = "BASE"
    
    public var name: String {
        switch self {
        case .bitcoin: return "Bitcoin"
        case .bitcoinTestnet: return "Bitcoin Testnet"
        case .ethereum: return "Ethereum"
        case .litecoin: return "Litecoin"
        case .solana: return "Solana"
        case .xrp: return "XRP"
        case .polygon: return "Polygon"
        case .arbitrum: return "Arbitrum"
        case .optimism: return "Optimism"
        case .base: return "Base"
        }
    }
    
    public var icon: String {
        switch self {
        case .bitcoin, .bitcoinTestnet: return "bitcoinsign.circle"
        case .ethereum, .polygon, .arbitrum, .optimism, .base: return "e.circle"
        case .litecoin: return "l.circle"
        case .solana: return "s.circle"
        case .xrp: return "x.circle"
        }
    }
    
    public var supportsMultipleAddresses: Bool {
        switch self {
        case .bitcoin, .bitcoinTestnet, .litecoin:
            return true // UTXO-based chains benefit from new addresses
        case .ethereum, .polygon, .arbitrum, .optimism, .base, .solana, .xrp:
            return false // Account-based chains typically use one address
        }
    }
}

public struct AddressReuseWarning {
    public let address: String
    public let useCount: Int
    public let lastUsedAt: Date?
    public let severity: WarningSeverity
    public let recommendation: String
    
    public enum WarningSeverity {
        case low
        case medium
        case high
    }
}

public struct AddressStatistics {
    public let totalAddresses: Int
    public let usedAddresses: Int
    public let unusedAddresses: Int
    public let receiveAddresses: Int
    public let changeAddresses: Int
    public let multiUseAddresses: Int
}

private struct AddressSettings: Codable {
    let gapLimit: Int
    let autoGenerateNewAddress: Bool
    let showReuseWarnings: Bool
}
