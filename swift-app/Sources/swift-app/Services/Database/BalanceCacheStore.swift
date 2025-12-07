import Foundation
import GRDB

// MARK: - Balance Cache Store

/// Data Access Object for cached balance persistence
/// Enables offline balance display and reduces API calls
actor BalanceCacheStore {
    
    // MARK: - Singleton
    
    static let shared = BalanceCacheStore()
    
    // MARK: - Properties
    
    private var db: DatabaseManager { DatabaseManager.shared }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Create/Update
    
    /// Save or update cached balance
    func save(
        walletId: String,
        chainId: String,
        balance: String,
        pendingBalance: String? = nil
    ) async throws {
        let now = Date()
        let record = CachedBalanceRecord(
            id: CachedBalanceRecord.makeId(walletId: walletId, chainId: chainId),
            walletId: walletId,
            chainId: chainId,
            balance: balance,
            pendingBalance: pendingBalance,
            lastUpdatedAt: now
        )
        
        try await db.writeAsync { dbConn in
            try record.save(dbConn)
        }
    }
    
    /// Batch save balances
    func saveAll(_ balances: [(walletId: String, chainId: String, balance: String)]) async throws {
        let now = Date()
        try await db.writeAsync { dbConn in
            for (walletId, chainId, balance) in balances {
                let record = CachedBalanceRecord(
                    id: CachedBalanceRecord.makeId(walletId: walletId, chainId: chainId),
                    walletId: walletId,
                    chainId: chainId,
                    balance: balance,
                    pendingBalance: nil,
                    lastUpdatedAt: now
                )
                try record.save(dbConn)
            }
        }
    }
    
    // MARK: - Read
    
    /// Get cached balance for a wallet/chain
    func get(walletId: String, chainId: String) async throws -> CachedBalanceRecord? {
        try await db.readAsync { dbConn in
            let id = CachedBalanceRecord.makeId(walletId: walletId, chainId: chainId)
            return try CachedBalanceRecord.fetchOne(dbConn, key: id)
        }
    }
    
    /// Get all cached balances for a wallet
    func getAll(walletId: String) async throws -> [CachedBalanceRecord] {
        try await db.readAsync { dbConn in
            try CachedBalanceRecord
                .filter(Column("walletId") == walletId)
                .fetchAll(dbConn)
        }
    }
    
    /// Get balance value, returns nil if not cached
    func getBalance(walletId: String, chainId: String) async throws -> String? {
        try await get(walletId: walletId, chainId: chainId)?.balance
    }
    
    /// Get balance with freshness info
    func getBalanceWithAge(walletId: String, chainId: String) async throws -> (balance: String, age: TimeInterval)? {
        guard let record = try await get(walletId: walletId, chainId: chainId) else {
            return nil
        }
        let age = Date().timeIntervalSince(record.lastUpdatedAt)
        return (record.balance, age)
    }
    
    /// Check if cache is stale
    func isStale(walletId: String, chainId: String, maxAge: TimeInterval = 300) async throws -> Bool {
        guard let record = try await get(walletId: walletId, chainId: chainId) else {
            return true // No cache = stale
        }
        return Date().timeIntervalSince(record.lastUpdatedAt) > maxAge
    }
    
    /// Get all stale balances for a wallet
    func getStaleBalances(walletId: String, maxAge: TimeInterval = 300) async throws -> [CachedBalanceRecord] {
        let cutoff = Date().addingTimeInterval(-maxAge)
        return try await db.readAsync { dbConn in
            try CachedBalanceRecord
                .filter(Column("walletId") == walletId)
                .filter(Column("lastUpdatedAt") < cutoff)
                .fetchAll(dbConn)
        }
    }
    
    // MARK: - Delete
    
    /// Delete cached balance
    func delete(walletId: String, chainId: String) async throws {
        try await db.writeAsync { dbConn in
            let id = CachedBalanceRecord.makeId(walletId: walletId, chainId: chainId)
            try CachedBalanceRecord.deleteOne(dbConn, key: id)
        }
    }
    
    /// Delete all cached balances for a wallet
    func deleteAll(walletId: String) async throws {
        try await db.writeAsync { dbConn in
            try CachedBalanceRecord
                .filter(Column("walletId") == walletId)
                .deleteAll(dbConn)
        }
    }
    
    /// Clear all cached balances (full refresh needed)
    func clearAll() async throws {
        try await db.writeAsync { dbConn in
            try CachedBalanceRecord.deleteAll(dbConn)
        }
    }
}
