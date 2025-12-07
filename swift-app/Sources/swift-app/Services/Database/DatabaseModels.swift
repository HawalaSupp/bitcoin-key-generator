import Foundation
import GRDB

// MARK: - Wallet Record

/// Database record for wallet metadata (keys stored separately in Keychain)
struct WalletRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "wallet"
    
    var id: String
    var name: String
    var createdAt: Date
    var isWatchOnly: Bool
    var colorIndex: Int
    var displayOrder: Int
    var lastSyncedAt: Date?
    
    // MARK: - Associations
    
    static let addresses = hasMany(AddressRecord.self)
    static let transactions = hasMany(TransactionRecord.self)
    static let utxos = hasMany(UTXORecord.self)
    static let syncStates = hasMany(SyncStateRecord.self)
    static let cachedBalances = hasMany(CachedBalanceRecord.self)
    
    var addresses: QueryInterfaceRequest<AddressRecord> {
        request(for: WalletRecord.addresses)
    }
    
    var transactions: QueryInterfaceRequest<TransactionRecord> {
        request(for: WalletRecord.transactions)
    }
    
    var utxos: QueryInterfaceRequest<UTXORecord> {
        request(for: WalletRecord.utxos)
    }
}

// MARK: - Address Record

/// Database record for derived addresses
struct AddressRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "address"
    
    var id: String
    var walletId: String
    var chainId: String
    var address: String
    var derivationPath: String?
    var label: String?
    var isChange: Bool
    var createdAt: Date
    
    // MARK: - Associations
    
    static let wallet = belongsTo(WalletRecord.self)
}

// MARK: - Transaction Record

/// Database record for transaction history
struct TransactionRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "transaction"
    
    var id: String
    var walletId: String
    var chainId: String
    var txHash: String
    var blockHeight: Int?
    var blockHash: String?
    var timestamp: Date?
    var status: TransactionStatus
    var type: TransactionType
    var fromAddress: String?
    var toAddress: String?
    var amount: String
    var fee: String?
    var feeAsset: String?
    var asset: String
    var confirmations: Int
    var rawData: Data?
    var note: String?
    var fiatValueAtTime: Double?
    var createdAt: Date
    var updatedAt: Date
    
    // MARK: - Associations
    
    static let wallet = belongsTo(WalletRecord.self)
    
    // MARK: - Enums
    
    enum TransactionStatus: String, Codable, Sendable {
        case pending
        case confirming
        case confirmed
        case failed
        case dropped
    }
    
    enum TransactionType: String, Codable, Sendable {
        case send
        case receive
        case swap
        case approve
        case stake
        case unstake
        case contract
        case unknown
    }
}

// MARK: - UTXO Record

/// Database record for Bitcoin/Litecoin unspent transaction outputs
struct UTXORecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "utxo"
    
    var id: String
    var walletId: String
    var chainId: String
    var txHash: String
    var outputIndex: Int
    var address: String
    var amount: Int64 // Satoshis
    var scriptPubKey: String
    var blockHeight: Int?
    var isSpent: Bool
    var spentInTxHash: String?
    var createdAt: Date
    var updatedAt: Date
    
    // MARK: - Associations
    
    static let wallet = belongsTo(WalletRecord.self)
    
    // MARK: - Computed Properties
    
    /// Amount in BTC/LTC
    var amountInCoin: Double {
        Double(amount) / 100_000_000.0
    }
    
    /// Unique identifier for this UTXO (txHash:outputIndex)
    var outpoint: String {
        "\(txHash):\(outputIndex)"
    }
}

// MARK: - Sync State Record

/// Database record for tracking sync progress per chain
struct SyncStateRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "syncState"
    
    var id: String // walletId + chainId
    var walletId: String
    var chainId: String
    var lastBlockHeight: Int
    var lastBlockHash: String?
    var lastSyncedAt: Date?
    var syncStatus: SyncStatus
    var errorMessage: String?
    
    // MARK: - Associations
    
    static let wallet = belongsTo(WalletRecord.self)
    
    // MARK: - Enums
    
    enum SyncStatus: String, Codable, Sendable {
        case idle
        case syncing
        case error
    }
    
    // MARK: - Factory
    
    static func makeId(walletId: String, chainId: String) -> String {
        "\(walletId):\(chainId)"
    }
}

// MARK: - Cached Balance Record

/// Database record for cached balances
struct CachedBalanceRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "cachedBalance"
    
    var id: String // walletId + chainId
    var walletId: String
    var chainId: String
    var balance: String
    var pendingBalance: String?
    var lastUpdatedAt: Date
    
    // MARK: - Associations
    
    static let wallet = belongsTo(WalletRecord.self)
    
    // MARK: - Factory
    
    static func makeId(walletId: String, chainId: String) -> String {
        "\(walletId):\(chainId)"
    }
}

// MARK: - Extensions for Query Building

extension WalletRecord {
    /// Fetch all addresses for a specific chain
    func addresses(for chainId: String) -> QueryInterfaceRequest<AddressRecord> {
        AddressRecord
            .filter(Column("walletId") == id)
            .filter(Column("chainId") == chainId)
    }
    
    /// Fetch all unspent UTXOs for a specific chain
    func unspentUTXOs(for chainId: String) -> QueryInterfaceRequest<UTXORecord> {
        UTXORecord
            .filter(Column("walletId") == id)
            .filter(Column("chainId") == chainId)
            .filter(Column("isSpent") == false)
            .order(Column("amount").desc) // Largest UTXOs first for coin selection
    }
    
    /// Fetch recent transactions for a specific chain
    func recentTransactions(for chainId: String, limit: Int = 50) -> QueryInterfaceRequest<TransactionRecord> {
        TransactionRecord
            .filter(Column("walletId") == id)
            .filter(Column("chainId") == chainId)
            .order(Column("timestamp").desc)
            .limit(limit)
    }
    
    /// Fetch pending transactions
    func pendingTransactions() -> QueryInterfaceRequest<TransactionRecord> {
        TransactionRecord
            .filter(Column("walletId") == id)
            .filter(Column("status") == TransactionRecord.TransactionStatus.pending.rawValue)
            .order(Column("createdAt").desc)
    }
}

extension UTXORecord {
    /// Calculate total unspent balance in satoshis for a wallet/chain
    static func totalBalance(walletId: String, chainId: String, in db: Database) throws -> Int64 {
        try UTXORecord
            .filter(Column("walletId") == walletId)
            .filter(Column("chainId") == chainId)
            .filter(Column("isSpent") == false)
            .select(sum(Column("amount")))
            .fetchOne(db) ?? 0
    }
}
