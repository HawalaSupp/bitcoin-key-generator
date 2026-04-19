import Foundation
import GRDB

// MARK: - Database Manager

/// Centralized SQLite database manager using GRDB.swift
/// Handles schema migrations, connection pooling, and provides type-safe access
final class DatabaseManager: Sendable {
    
    // MARK: - Singleton
    
    static let shared = DatabaseManager()
    
    // MARK: - Properties
    
    /// The database queue for all read/write operations
    let dbQueue: DatabaseQueue
    
    /// Current schema version
    static let schemaVersion: Int = 1
    
    // MARK: - Initialization
    
    private init() {
        do {
            let fileManager = FileManager.default
            
            // Create Application Support directory for Hawala
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let hawalaDir = appSupport.appendingPathComponent("Hawala", isDirectory: true)
            
            if !fileManager.fileExists(atPath: hawalaDir.path) {
                try fileManager.createDirectory(at: hawalaDir, withIntermediateDirectories: true)
            }
            
            let dbPath = hawalaDir.appendingPathComponent("hawala.sqlite")
            
            // Configure database
            var config = Configuration()
            config.prepareDatabase { db in
                // Enable foreign keys
                try db.execute(sql: "PRAGMA foreign_keys = ON")
                // Use WAL mode for better concurrent read performance
                try db.execute(sql: "PRAGMA journal_mode = WAL")
            }
            
            let queue = try DatabaseQueue(path: dbPath.path, configuration: config)
            dbQueue = queue
            
            // Run migrations
            try Self.runMigrations(on: queue)
            
            print("📦 Database initialized at: \(dbPath.path)")
        } catch {
            fatalError("❌ Failed to initialize database: \(error)")
        }
    }
    
    // MARK: - Migrations
    
    private static func runMigrations(on dbQueue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        
        // MARK: Migration v1 - Initial Schema
        migrator.registerMigration("v1_initial") { db in
            // Wallets table (metadata only, keys stored in Keychain)
            try db.create(table: "wallet") { t in
                t.primaryKey("id", .text).notNull()
                t.column("name", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("isWatchOnly", .boolean).notNull().defaults(to: false)
                t.column("colorIndex", .integer).notNull().defaults(to: 0)
                t.column("displayOrder", .integer).notNull().defaults(to: 0)
                t.column("lastSyncedAt", .datetime)
            }
            
            // Addresses table (derived addresses for each wallet/chain)
            try db.create(table: "address") { t in
                t.primaryKey("id", .text).notNull()
                t.belongsTo("wallet", onDelete: .cascade).notNull()
                t.column("chainId", .text).notNull()
                t.column("address", .text).notNull()
                t.column("derivationPath", .text)
                t.column("label", .text)
                t.column("isChange", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "address_wallet_chain", on: "address", columns: ["walletId", "chainId"])
            try db.create(index: "address_address", on: "address", columns: ["address"])
            
            // Transactions table (unified transaction history)
            try db.create(table: "transaction") { t in
                t.primaryKey("id", .text).notNull()
                t.belongsTo("wallet", onDelete: .cascade).notNull()
                t.column("chainId", .text).notNull()
                t.column("txHash", .text).notNull()
                t.column("blockHeight", .integer)
                t.column("blockHash", .text)
                t.column("timestamp", .datetime)
                t.column("status", .text).notNull() // pending, confirmed, failed
                t.column("type", .text).notNull() // send, receive, swap, approve
                t.column("fromAddress", .text)
                t.column("toAddress", .text)
                t.column("amount", .text).notNull() // String to preserve precision
                t.column("fee", .text)
                t.column("feeAsset", .text)
                t.column("asset", .text).notNull() // BTC, ETH, SOL, etc.
                t.column("confirmations", .integer).notNull().defaults(to: 0)
                t.column("rawData", .blob) // JSON blob for chain-specific data
                t.column("note", .text) // User note
                t.column("fiatValueAtTime", .double) // USD value at transaction time
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "transaction_wallet_chain", on: "transaction", columns: ["walletId", "chainId"])
            try db.create(index: "transaction_txhash", on: "transaction", columns: ["txHash"])
            try db.create(index: "transaction_timestamp", on: "transaction", columns: ["timestamp"])
            try db.create(index: "transaction_status", on: "transaction", columns: ["status"])
            
            // UTXOs table (Bitcoin/Litecoin unspent outputs)
            try db.create(table: "utxo") { t in
                t.primaryKey("id", .text).notNull()
                t.belongsTo("wallet", onDelete: .cascade).notNull()
                t.column("chainId", .text).notNull()
                t.column("txHash", .text).notNull()
                t.column("outputIndex", .integer).notNull()
                t.column("address", .text).notNull()
                t.column("amount", .integer).notNull() // Satoshis
                t.column("scriptPubKey", .text).notNull()
                t.column("blockHeight", .integer)
                t.column("isSpent", .boolean).notNull().defaults(to: false)
                t.column("spentInTxHash", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "utxo_wallet_chain", on: "utxo", columns: ["walletId", "chainId"])
            try db.create(index: "utxo_txhash_index", on: "utxo", columns: ["txHash", "outputIndex"], unique: true)
            try db.create(index: "utxo_unspent", on: "utxo", columns: ["walletId", "chainId", "isSpent"])
            
            // Sync state table (tracks last synced block per chain)
            try db.create(table: "syncState") { t in
                t.primaryKey("id", .text).notNull() // walletId + chainId
                t.belongsTo("wallet", onDelete: .cascade).notNull()
                t.column("chainId", .text).notNull()
                t.column("lastBlockHeight", .integer).notNull().defaults(to: 0)
                t.column("lastBlockHash", .text)
                t.column("lastSyncedAt", .datetime)
                t.column("syncStatus", .text).notNull() // idle, syncing, error
                t.column("errorMessage", .text)
            }
            try db.create(index: "syncState_wallet_chain", on: "syncState", columns: ["walletId", "chainId"], unique: true)
            
            // Cached balances table
            try db.create(table: "cachedBalance") { t in
                t.primaryKey("id", .text).notNull() // walletId + chainId
                t.belongsTo("wallet", onDelete: .cascade).notNull()
                t.column("chainId", .text).notNull()
                t.column("balance", .text).notNull() // String for precision
                t.column("pendingBalance", .text)
                t.column("lastUpdatedAt", .datetime).notNull()
            }
            try db.create(index: "cachedBalance_wallet_chain", on: "cachedBalance", columns: ["walletId", "chainId"], unique: true)
            
            print("✅ Migration v1_initial completed")
        }
        
        // Run all migrations
        try migrator.migrate(dbQueue)
    }
    
    // MARK: - Database Operations
    
    /// Read operation
    func read<T>(_ block: (Database) throws -> T) throws -> T {
        try dbQueue.read(block)
    }
    
    /// Write operation
    func write<T>(_ block: (Database) throws -> T) throws -> T {
        try dbQueue.write(block)
    }
    
    /// Async read operation
    func readAsync<T: Sendable>(_ block: @Sendable @escaping (Database) throws -> T) async throws -> T {
        try await dbQueue.read(block)
    }
    
    /// Async write operation
    func writeAsync<T: Sendable>(_ block: @Sendable @escaping (Database) throws -> T) async throws -> T {
        try await dbQueue.write(block)
    }
    
    // MARK: - Utility
    
    /// Clear all data (for testing or reset)
    func clearAllData() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM cachedBalance")
            try db.execute(sql: "DELETE FROM syncState")
            try db.execute(sql: "DELETE FROM utxo")
            try db.execute(sql: "DELETE FROM transaction")
            try db.execute(sql: "DELETE FROM address")
            try db.execute(sql: "DELETE FROM wallet")
        }
        print("🗑️ All database data cleared")
    }
    
    /// Get database file size
    func getDatabaseSize() -> Int64? {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbPath = appSupport.appendingPathComponent("Hawala/hawala.sqlite")
        
        guard let attrs = try? fileManager.attributesOfItem(atPath: dbPath.path),
              let size = attrs[.size] as? Int64 else {
            return nil
        }
        return size
    }
}
