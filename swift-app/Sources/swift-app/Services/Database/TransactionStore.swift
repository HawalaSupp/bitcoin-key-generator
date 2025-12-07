import Foundation
import GRDB

// MARK: - Transaction Store

/// Data Access Object for transaction persistence
/// Provides CRUD operations and specialized queries for transaction history
actor TransactionStore {
    
    // MARK: - Singleton
    
    static let shared = TransactionStore()
    
    // MARK: - Properties
    
    private var db: DatabaseManager { DatabaseManager.shared }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Create/Update
    
    /// Insert or update a transaction
    func save(_ transaction: TransactionRecord) async throws {
        try await db.writeAsync { dbConn in
            try transaction.save(dbConn)
        }
    }
    
    /// Insert or update multiple transactions (batch operation)
    func saveAll(_ transactions: [TransactionRecord]) async throws {
        try await db.writeAsync { dbConn in
            for tx in transactions {
                try tx.save(dbConn)
            }
        }
    }
    
    /// Update transaction status
    func updateStatus(txHash: String, chainId: String, status: TransactionRecord.TransactionStatus, confirmations: Int? = nil) async throws {
        try await db.writeAsync { dbConn in
            if var tx = try TransactionRecord
                .filter(Column("txHash") == txHash)
                .filter(Column("chainId") == chainId)
                .fetchOne(dbConn) {
                tx.status = status
                if let confirmations = confirmations {
                    tx.confirmations = confirmations
                }
                tx.updatedAt = Date()
                try tx.update(dbConn)
            }
        }
    }
    
    /// Update transaction with block info (when confirmed)
    func updateBlockInfo(txHash: String, chainId: String, blockHeight: Int, blockHash: String?, timestamp: Date?) async throws {
        try await db.writeAsync { dbConn in
            if var tx = try TransactionRecord
                .filter(Column("txHash") == txHash)
                .filter(Column("chainId") == chainId)
                .fetchOne(dbConn) {
                tx.blockHeight = blockHeight
                tx.blockHash = blockHash
                if let timestamp = timestamp {
                    tx.timestamp = timestamp
                }
                tx.status = .confirmed
                tx.updatedAt = Date()
                try tx.update(dbConn)
            }
        }
    }
    
    /// Add/update user note on transaction
    func updateNote(txHash: String, note: String?) async throws {
        try await db.writeAsync { dbConn in
            if var tx = try TransactionRecord
                .filter(Column("txHash") == txHash)
                .fetchOne(dbConn) {
                tx.note = note
                tx.updatedAt = Date()
                try tx.update(dbConn)
            }
        }
    }
    
    // MARK: - Read
    
    /// Fetch all transactions for a wallet
    func fetchAll(walletId: String) async throws -> [TransactionRecord] {
        try await db.readAsync { dbConn in
            try TransactionRecord
                .filter(Column("walletId") == walletId)
                .order(Column("timestamp").desc)
                .fetchAll(dbConn)
        }
    }
    
    /// Fetch transactions for a specific chain
    func fetch(walletId: String, chainId: String, limit: Int = 100) async throws -> [TransactionRecord] {
        try await db.readAsync { dbConn in
            try TransactionRecord
                .filter(Column("walletId") == walletId)
                .filter(Column("chainId") == chainId)
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(dbConn)
        }
    }
    
    /// Fetch a single transaction by hash
    func fetch(txHash: String, chainId: String) async throws -> TransactionRecord? {
        try await db.readAsync { dbConn in
            try TransactionRecord
                .filter(Column("txHash") == txHash)
                .filter(Column("chainId") == chainId)
                .fetchOne(dbConn)
        }
    }
    
    /// Fetch pending transactions for a wallet
    func fetchPending(walletId: String) async throws -> [TransactionRecord] {
        try await db.readAsync { dbConn in
            try TransactionRecord
                .filter(Column("walletId") == walletId)
                .filter(Column("status") == TransactionRecord.TransactionStatus.pending.rawValue)
                .order(Column("createdAt").desc)
                .fetchAll(dbConn)
        }
    }
    
    /// Fetch transactions since a specific timestamp
    func fetchSince(walletId: String, chainId: String, since: Date) async throws -> [TransactionRecord] {
        try await db.readAsync { dbConn in
            try TransactionRecord
                .filter(Column("walletId") == walletId)
                .filter(Column("chainId") == chainId)
                .filter(Column("timestamp") > since)
                .order(Column("timestamp").desc)
                .fetchAll(dbConn)
        }
    }
    
    /// Count transactions for a wallet/chain
    func count(walletId: String, chainId: String? = nil) async throws -> Int {
        try await db.readAsync { dbConn in
            var request = TransactionRecord.filter(Column("walletId") == walletId)
            if let chainId = chainId {
                request = request.filter(Column("chainId") == chainId)
            }
            return try request.fetchCount(dbConn)
        }
    }
    
    /// Check if a transaction exists
    func exists(txHash: String, chainId: String) async throws -> Bool {
        try await db.readAsync { dbConn in
            try TransactionRecord
                .filter(Column("txHash") == txHash)
                .filter(Column("chainId") == chainId)
                .fetchCount(dbConn) > 0
        }
    }
    
    // MARK: - Delete
    
    /// Delete a transaction
    func delete(txHash: String, chainId: String) async throws {
        _ = try await db.writeAsync { dbConn in
            try TransactionRecord
                .filter(Column("txHash") == txHash)
                .filter(Column("chainId") == chainId)
                .deleteAll(dbConn)
        }
    }
    
    /// Delete all transactions for a wallet
    func deleteAll(walletId: String) async throws {
        _ = try await db.writeAsync { dbConn in
            try TransactionRecord
                .filter(Column("walletId") == walletId)
                .deleteAll(dbConn)
        }
    }
    
    // MARK: - Statistics
    
    /// Get transaction statistics for a wallet
    func getStats(walletId: String) async throws -> TransactionStats {
        try await db.readAsync { dbConn in
            let total = try TransactionRecord
                .filter(Column("walletId") == walletId)
                .fetchCount(dbConn)
            
            let pending = try TransactionRecord
                .filter(Column("walletId") == walletId)
                .filter(Column("status") == TransactionRecord.TransactionStatus.pending.rawValue)
                .fetchCount(dbConn)
            
            let sent = try TransactionRecord
                .filter(Column("walletId") == walletId)
                .filter(Column("type") == TransactionRecord.TransactionType.send.rawValue)
                .fetchCount(dbConn)
            
            let received = try TransactionRecord
                .filter(Column("walletId") == walletId)
                .filter(Column("type") == TransactionRecord.TransactionType.receive.rawValue)
                .fetchCount(dbConn)
            
            return TransactionStats(
                total: total,
                pending: pending,
                sent: sent,
                received: received
            )
        }
    }
}

// MARK: - Transaction Stats

struct TransactionStats: Sendable {
    let total: Int
    let pending: Int
    let sent: Int
    let received: Int
}

// MARK: - Factory Methods

extension TransactionRecord {
    /// Create a new transaction record from API response
    static func from(
        walletId: String,
        chainId: String,
        txHash: String,
        type: TransactionType,
        fromAddress: String?,
        toAddress: String?,
        amount: String,
        fee: String?,
        asset: String,
        timestamp: Date?,
        status: TransactionStatus = .pending
    ) -> TransactionRecord {
        let now = Date()
        return TransactionRecord(
            id: UUID().uuidString,
            walletId: walletId,
            chainId: chainId,
            txHash: txHash,
            blockHeight: nil,
            blockHash: nil,
            timestamp: timestamp,
            status: status,
            type: type,
            fromAddress: fromAddress,
            toAddress: toAddress,
            amount: amount,
            fee: fee,
            feeAsset: asset,
            asset: asset,
            confirmations: 0,
            rawData: nil,
            note: nil,
            fiatValueAtTime: nil,
            createdAt: now,
            updatedAt: now
        )
    }
}
