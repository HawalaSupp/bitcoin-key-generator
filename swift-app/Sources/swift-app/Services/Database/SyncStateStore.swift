import Foundation
import GRDB

// MARK: - Sync State Store

/// Data Access Object for sync state persistence
/// Tracks last synced block per wallet/chain for incremental sync
actor SyncStateStore {
    
    // MARK: - Singleton
    
    static let shared = SyncStateStore()
    
    // MARK: - Properties
    
    private var db: DatabaseManager { DatabaseManager.shared }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Create/Update
    
    /// Get or create sync state for a wallet/chain
    func getOrCreate(walletId: String, chainId: String) async throws -> SyncStateRecord {
        try await db.writeAsync { dbConn in
            let id = SyncStateRecord.makeId(walletId: walletId, chainId: chainId)
            
            if let existing = try SyncStateRecord.fetchOne(dbConn, key: id) {
                return existing
            }
            
            let newState = SyncStateRecord(
                id: id,
                walletId: walletId,
                chainId: chainId,
                lastBlockHeight: 0,
                lastBlockHash: nil,
                lastSyncedAt: nil,
                syncStatus: .idle,
                errorMessage: nil
            )
            try newState.insert(dbConn)
            return newState
        }
    }
    
    /// Update sync state after successful sync
    func updateAfterSync(
        walletId: String,
        chainId: String,
        blockHeight: Int,
        blockHash: String?
    ) async throws {
        try await db.writeAsync { dbConn in
            let id = SyncStateRecord.makeId(walletId: walletId, chainId: chainId)
            
            if var state = try SyncStateRecord.fetchOne(dbConn, key: id) {
                state.lastBlockHeight = blockHeight
                state.lastBlockHash = blockHash
                state.lastSyncedAt = Date()
                state.syncStatus = .idle
                state.errorMessage = nil
                try state.update(dbConn)
            }
        }
    }
    
    /// Mark sync as started
    func markSyncing(walletId: String, chainId: String) async throws {
        try await db.writeAsync { dbConn in
            let id = SyncStateRecord.makeId(walletId: walletId, chainId: chainId)
            
            if var state = try SyncStateRecord.fetchOne(dbConn, key: id) {
                state.syncStatus = .syncing
                state.errorMessage = nil
                try state.update(dbConn)
            }
        }
    }
    
    /// Mark sync as failed
    func markError(walletId: String, chainId: String, error: String) async throws {
        try await db.writeAsync { dbConn in
            let id = SyncStateRecord.makeId(walletId: walletId, chainId: chainId)
            
            if var state = try SyncStateRecord.fetchOne(dbConn, key: id) {
                state.syncStatus = .error
                state.errorMessage = error
                try state.update(dbConn)
            }
        }
    }
    
    // MARK: - Read
    
    /// Get sync state for a wallet/chain
    func get(walletId: String, chainId: String) async throws -> SyncStateRecord? {
        try await db.readAsync { dbConn in
            let id = SyncStateRecord.makeId(walletId: walletId, chainId: chainId)
            return try SyncStateRecord.fetchOne(dbConn, key: id)
        }
    }
    
    /// Get all sync states for a wallet
    func getAll(walletId: String) async throws -> [SyncStateRecord] {
        try await db.readAsync { dbConn in
            try SyncStateRecord
                .filter(Column("walletId") == walletId)
                .fetchAll(dbConn)
        }
    }
    
    /// Get last synced block height
    func lastBlockHeight(walletId: String, chainId: String) async throws -> Int {
        try await db.readAsync { dbConn in
            let id = SyncStateRecord.makeId(walletId: walletId, chainId: chainId)
            return try SyncStateRecord.fetchOne(dbConn, key: id)?.lastBlockHeight ?? 0
        }
    }
    
    /// Check if any chain is currently syncing
    func isSyncing(walletId: String) async throws -> Bool {
        try await db.readAsync { dbConn in
            try SyncStateRecord
                .filter(Column("walletId") == walletId)
                .filter(Column("syncStatus") == SyncStateRecord.SyncStatus.syncing.rawValue)
                .fetchCount(dbConn) > 0
        }
    }
    
    /// Get chains with errors
    func getChainsWithErrors(walletId: String) async throws -> [SyncStateRecord] {
        try await db.readAsync { dbConn in
            try SyncStateRecord
                .filter(Column("walletId") == walletId)
                .filter(Column("syncStatus") == SyncStateRecord.SyncStatus.error.rawValue)
                .fetchAll(dbConn)
        }
    }
    
    /// Get chains that need sync (not synced recently)
    func getStaleChains(walletId: String, staleAfter: TimeInterval = 300) async throws -> [SyncStateRecord] {
        let cutoff = Date().addingTimeInterval(-staleAfter)
        return try await db.readAsync { dbConn in
            try SyncStateRecord
                .filter(Column("walletId") == walletId)
                .filter(Column("lastSyncedAt") == nil || Column("lastSyncedAt") < cutoff)
                .fetchAll(dbConn)
        }
    }
    
    // MARK: - Delete
    
    /// Delete sync state for a wallet
    func delete(walletId: String) async throws {
        _ = try await db.writeAsync { dbConn in
            try SyncStateRecord
                .filter(Column("walletId") == walletId)
                .deleteAll(dbConn)
        }
    }
    
    /// Reset sync state (force full resync)
    func reset(walletId: String, chainId: String) async throws {
        try await db.writeAsync { dbConn in
            let id = SyncStateRecord.makeId(walletId: walletId, chainId: chainId)
            
            if var state = try SyncStateRecord.fetchOne(dbConn, key: id) {
                state.lastBlockHeight = 0
                state.lastBlockHash = nil
                state.lastSyncedAt = nil
                state.syncStatus = .idle
                state.errorMessage = nil
                try state.update(dbConn)
            }
        }
    }
}
