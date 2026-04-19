import Foundation
import Combine

// MARK: - UTXO Coin Control Manager
/// Advanced UTXO management with labeling, freezing, and privacy scoring

@MainActor
public final class UTXOCoinControlManager: ObservableObject {
    public static let shared = UTXOCoinControlManager()
    
    // MARK: - Published State
    @Published public private(set) var utxos: [ManagedUTXO] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var lastError: String?
    @Published public private(set) var lastRefresh: Date?
    
    // MARK: - Storage
    private var utxoMetadata: [String: UTXOMetadata] = [:] // key: txid:vout
    private let storageKey = "hawala_utxo_metadata"
    
    private init() {
        loadMetadata()
    }
    
    // MARK: - Public Methods
    
    /// Refresh UTXOs for an address
    func refreshUTXOs(for address: String, chain: Chain) async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        
        do {
            let rawUTXOs = try await fetchUTXOs(address: address, chain: chain)
            
            // Enrich with metadata
            utxos = rawUTXOs.map { utxo in
                let key = "\(utxo.txid):\(utxo.vout)"
                let metadata = utxoMetadata[key] ?? UTXOMetadata()
                
                return ManagedUTXO(
                    txid: utxo.txid,
                    vout: utxo.vout,
                    value: utxo.value,
                    confirmations: utxo.confirmations,
                    scriptPubKey: utxo.scriptPubKey,
                    address: address,
                    metadata: metadata,
                    privacyScore: calculatePrivacyScore(for: utxo, metadata: metadata)
                )
            }
            
            lastRefresh = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }
    
    /// Set label for a UTXO
    public func setLabel(_ label: String, for utxo: ManagedUTXO) {
        let key = "\(utxo.txid):\(utxo.vout)"
        var metadata = utxoMetadata[key] ?? UTXOMetadata()
        metadata.label = label
        utxoMetadata[key] = metadata
        updateUTXO(key: key, metadata: metadata)
        saveMetadata()
    }
    
    /// Set source category for a UTXO
    public func setSource(_ source: UTXOSource, for utxo: ManagedUTXO) {
        let key = "\(utxo.txid):\(utxo.vout)"
        var metadata = utxoMetadata[key] ?? UTXOMetadata()
        metadata.source = source
        utxoMetadata[key] = metadata
        updateUTXO(key: key, metadata: metadata)
        saveMetadata()
    }
    
    /// Freeze/unfreeze a UTXO
    public func setFrozen(_ frozen: Bool, for utxo: ManagedUTXO) {
        let key = "\(utxo.txid):\(utxo.vout)"
        var metadata = utxoMetadata[key] ?? UTXOMetadata()
        metadata.isFrozen = frozen
        utxoMetadata[key] = metadata
        updateUTXO(key: key, metadata: metadata)
        saveMetadata()
    }
    
    /// Add a note to UTXO
    public func setNote(_ note: String, for utxo: ManagedUTXO) {
        let key = "\(utxo.txid):\(utxo.vout)"
        var metadata = utxoMetadata[key] ?? UTXOMetadata()
        metadata.note = note
        utxoMetadata[key] = metadata
        updateUTXO(key: key, metadata: metadata)
        saveMetadata()
    }
    
    /// Get spendable UTXOs (not frozen)
    public var spendableUTXOs: [ManagedUTXO] {
        utxos.filter { !$0.metadata.isFrozen }
    }
    
    /// Get total balance (all UTXOs)
    public var totalBalance: UInt64 {
        utxos.reduce(0) { $0 + $1.value }
    }
    
    /// Get spendable balance (excluding frozen)
    public var spendableBalance: UInt64 {
        spendableUTXOs.reduce(0) { $0 + $1.value }
    }
    
    /// Get frozen balance
    public var frozenBalance: UInt64 {
        utxos.filter { $0.metadata.isFrozen }.reduce(0) { $0 + $1.value }
    }
    
    /// Select UTXOs for a specific amount with coin control
    public func selectUTXOs(
        for amount: UInt64,
        strategy: UTXOSelectionStrategy = .optimal,
        manualSelection: [ManagedUTXO]? = nil
    ) -> [ManagedUTXO] {
        // If manual selection provided, use it
        if let manual = manualSelection {
            return manual.filter { !$0.metadata.isFrozen }
        }
        
        let available = spendableUTXOs.sorted { compareUTXOs($0, $1, strategy: strategy) }
        
        var selected: [ManagedUTXO] = []
        var total: UInt64 = 0
        
        for utxo in available {
            if total >= amount { break }
            selected.append(utxo)
            total += utxo.value
        }
        
        return selected
    }
    
    /// Get average privacy score
    public var averagePrivacyScore: Double {
        guard !utxos.isEmpty else { return 0 }
        return Double(utxos.reduce(0) { $0 + $1.privacyScore }) / Double(utxos.count)
    }
    
    // MARK: - Private Methods
    
    private func fetchUTXOs(address: String, chain: Chain) async throws -> [RawUTXO] {
        let urlString: String
        switch chain {
        case .bitcoinMainnet: urlString = "https://mempool.space/api/address/\(address)/utxo"
        case .bitcoinTestnet: urlString = "https://mempool.space/testnet/api/address/\(address)/utxo"
        case .litecoin: urlString = "https://litecoinspace.org/api/address/\(address)/utxo"
        default: throw UTXOError.invalidAddress
        }
        
        guard let url = URL(string: urlString) else {
            throw UTXOError.invalidAddress
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw UTXOError.networkError
        }
        
        let decoder = JSONDecoder()
        let rawUTXOs = try decoder.decode([RawUTXO].self, from: data)
        
        return rawUTXOs
    }
    
    private func calculatePrivacyScore(for utxo: RawUTXO, metadata: UTXOMetadata) -> Int {
        var score = 100
        
        // Penalize low confirmation count (more traceable to recent activity)
        if utxo.confirmations < 6 {
            score -= 10
        }
        
        // Penalize round amounts (more obvious)
        let btcValue = Double(utxo.value) / 100_000_000
        if btcValue == floor(btcValue) || btcValue * 10 == floor(btcValue * 10) {
            score -= 15
        }
        
        // Penalize known exchange sources
        if metadata.source == .exchange {
            score -= 20
        }
        
        // Penalize if from a recent transaction (address reuse detection)
        if utxo.confirmations < 100 {
            score -= 5
        }
        
        // Bonus for old coins (better fungibility)
        if utxo.confirmations > 1000 {
            score += 10
        }
        
        // Bonus for labeled/audited coins
        if !metadata.label.isEmpty {
            score += 5
        }
        
        return max(0, min(100, score))
    }
    
    private func compareUTXOs(_ a: ManagedUTXO, _ b: ManagedUTXO, strategy: UTXOSelectionStrategy) -> Bool {
        switch strategy {
        case .largestFirst:
            return a.value > b.value
        case .smallestFirst:
            return a.value < b.value
        case .oldestFirst:
            return a.confirmations > b.confirmations
        case .newestFirst:
            return a.confirmations < b.confirmations
        case .privacyOptimized:
            return a.privacyScore > b.privacyScore
        case .optimal:
            // Balance between value and privacy
            let aScore = Double(a.value) / 100_000 + Double(a.privacyScore)
            let bScore = Double(b.value) / 100_000 + Double(b.privacyScore)
            return aScore > bScore
        }
    }
    
    private func updateUTXO(key: String, metadata: UTXOMetadata) {
        if let index = utxos.firstIndex(where: { "\($0.txid):\($0.vout)" == key }) {
            utxos[index].metadata = metadata
            utxos[index].privacyScore = calculatePrivacyScore(
                for: RawUTXO(
                    txid: utxos[index].txid,
                    vout: utxos[index].vout,
                    value: utxos[index].value,
                    status: .init(confirmed: utxos[index].confirmations > 0, block_height: nil, block_time: nil),
                    confirmations: utxos[index].confirmations
                ),
                metadata: metadata
            )
        }
    }
    
    // MARK: - Persistence
    
    private func loadMetadata() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: UTXOMetadata].self, from: data) {
            utxoMetadata = decoded
        }
    }
    
    private func saveMetadata() {
        if let encoded = try? JSONEncoder().encode(utxoMetadata) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
}

// MARK: - Supporting Types

public struct ManagedUTXO: Identifiable, Hashable {
    public var id: String { "\(txid):\(vout)" }
    public let txid: String
    public let vout: Int
    public let value: UInt64
    public let confirmations: Int
    public let scriptPubKey: String
    public let address: String
    public var metadata: UTXOMetadata
    public var privacyScore: Int
    
    public var formattedValue: String {
        let btc = Double(value) / 100_000_000
        if btc >= 0.001 {
            return String(format: "%.8f BTC", btc)
        } else {
            return "\(value) sats"
        }
    }
    
    public var shortTxid: String {
        "\(txid.prefix(8))...\(txid.suffix(8))"
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: ManagedUTXO, rhs: ManagedUTXO) -> Bool {
        lhs.id == rhs.id
    }
}

public struct UTXOMetadata: Codable, Hashable {
    public var label: String = ""
    public var source: UTXOSource = .unknown
    public var isFrozen: Bool = false
    public var note: String = ""
    public var dateAdded: Date = Date()
    
    public init() {}
}

public enum UTXOSource: String, Codable, CaseIterable {
    case unknown = "Unknown"
    case mining = "Mining"
    case exchange = "Exchange"
    case p2p = "P2P Trade"
    case salary = "Salary"
    case gift = "Gift"
    case change = "Change"
    case selfTransfer = "Self Transfer"
    case coinjoin = "CoinJoin"
    case lightning = "Lightning"
    
    public var icon: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .mining: return "hammer"
        case .exchange: return "building.columns"
        case .p2p: return "person.2"
        case .salary: return "dollarsign.circle"
        case .gift: return "gift"
        case .change: return "arrow.uturn.backward"
        case .selfTransfer: return "arrow.left.arrow.right"
        case .coinjoin: return "shuffle"
        case .lightning: return "bolt"
        }
    }
    
    public var privacyImpact: String {
        switch self {
        case .exchange: return "Low privacy - KYC linked"
        case .coinjoin: return "High privacy - Mixed coins"
        case .lightning: return "Good privacy - Off-chain"
        case .change: return "Medium - Links to previous tx"
        default: return "Standard"
        }
    }
}

public enum UTXOSelectionStrategy: String, CaseIterable {
    case largestFirst = "Largest First"
    case smallestFirst = "Smallest First"
    case oldestFirst = "Oldest First"
    case newestFirst = "Newest First"
    case privacyOptimized = "Privacy Optimized"
    case optimal = "Balanced (Optimal)"
    
    public var description: String {
        switch self {
        case .largestFirst: return "Minimizes number of inputs"
        case .smallestFirst: return "Consolidates small UTXOs"
        case .oldestFirst: return "Uses oldest coins first"
        case .newestFirst: return "Keeps aged coins"
        case .privacyOptimized: return "Maximizes privacy score"
        case .optimal: return "Balances value and privacy"
        }
    }
}

public enum BitcoinNetwork {
    case mainnet
    case testnet
}

struct RawUTXO: Codable {
    let txid: String
    let vout: Int
    let value: UInt64
    let status: UTXOStatus
    var confirmations: Int = 0
    
    var scriptPubKey: String { "" } // Would come from additional API call
    
    struct UTXOStatus: Codable {
        let confirmed: Bool
        let block_height: Int?
        let block_time: Int?
    }
}

enum UTXOError: Error, LocalizedError {
    case invalidAddress
    case networkError
    case parseError
    
    var errorDescription: String? {
        switch self {
        case .invalidAddress: return "Invalid Bitcoin address"
        case .networkError: return "Failed to fetch UTXOs"
        case .parseError: return "Failed to parse UTXO data"
        }
    }
}
