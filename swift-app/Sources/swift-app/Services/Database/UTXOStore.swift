import Foundation
import GRDB

// MARK: - UTXO Store

/// Data Access Object for UTXO (Unspent Transaction Output) persistence
/// Critical for Bitcoin/Litecoin transaction construction
actor UTXOStore {
    
    // MARK: - Singleton
    
    static let shared = UTXOStore()
    
    // MARK: - Properties
    
    private var db: DatabaseManager { DatabaseManager.shared }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Create/Update
    
    /// Insert or update a UTXO
    func save(_ utxo: UTXORecord) async throws {
        try await db.writeAsync { dbConn in
            try utxo.save(dbConn)
        }
    }
    
    /// Batch insert UTXOs (used during sync)
    func saveAll(_ utxos: [UTXORecord]) async throws {
        try await db.writeAsync { dbConn in
            for utxo in utxos {
                try utxo.save(dbConn)
            }
        }
    }
    
    /// Mark UTXO as spent
    func markSpent(txHash: String, outputIndex: Int, spentInTxHash: String) async throws {
        try await db.writeAsync { dbConn in
            if var utxo = try UTXORecord
                .filter(Column("txHash") == txHash)
                .filter(Column("outputIndex") == outputIndex)
                .fetchOne(dbConn) {
                utxo.isSpent = true
                utxo.spentInTxHash = spentInTxHash
                utxo.updatedAt = Date()
                try utxo.update(dbConn)
            }
        }
    }
    
    /// Mark multiple UTXOs as spent (batch operation for transaction inputs)
    func markSpent(outpoints: [(txHash: String, outputIndex: Int)], spentInTxHash: String) async throws {
        try await db.writeAsync { dbConn in
            for (txHash, outputIndex) in outpoints {
                if var utxo = try UTXORecord
                    .filter(Column("txHash") == txHash)
                    .filter(Column("outputIndex") == outputIndex)
                    .fetchOne(dbConn) {
                    utxo.isSpent = true
                    utxo.spentInTxHash = spentInTxHash
                    utxo.updatedAt = Date()
                    try utxo.update(dbConn)
                }
            }
        }
    }
    
    /// Unmark UTXO as spent (revert in case of failed/dropped transaction)
    func markUnspent(txHash: String, outputIndex: Int) async throws {
        try await db.writeAsync { dbConn in
            if var utxo = try UTXORecord
                .filter(Column("txHash") == txHash)
                .filter(Column("outputIndex") == outputIndex)
                .fetchOne(dbConn) {
                utxo.isSpent = false
                utxo.spentInTxHash = nil
                utxo.updatedAt = Date()
                try utxo.update(dbConn)
            }
        }
    }
    
    // MARK: - Read
    
    /// Fetch all unspent UTXOs for a wallet/chain
    func fetchUnspent(walletId: String, chainId: String) async throws -> [UTXORecord] {
        try await db.readAsync { dbConn in
            try UTXORecord
                .filter(Column("walletId") == walletId)
                .filter(Column("chainId") == chainId)
                .filter(Column("isSpent") == false)
                .order(Column("amount").desc) // Largest first for efficient coin selection
                .fetchAll(dbConn)
        }
    }
    
    /// Fetch unspent UTXOs for a specific address
    func fetchUnspent(address: String, chainId: String) async throws -> [UTXORecord] {
        try await db.readAsync { dbConn in
            try UTXORecord
                .filter(Column("address") == address)
                .filter(Column("chainId") == chainId)
                .filter(Column("isSpent") == false)
                .order(Column("amount").desc)
                .fetchAll(dbConn)
        }
    }
    
    /// Fetch a specific UTXO by outpoint
    func fetch(txHash: String, outputIndex: Int) async throws -> UTXORecord? {
        try await db.readAsync { dbConn in
            try UTXORecord
                .filter(Column("txHash") == txHash)
                .filter(Column("outputIndex") == outputIndex)
                .fetchOne(dbConn)
        }
    }
    
    /// Get total unspent balance in satoshis
    func totalBalance(walletId: String, chainId: String) async throws -> Int64 {
        try await db.readAsync { dbConn in
            let sum: Int64? = try UTXORecord
                .filter(Column("walletId") == walletId)
                .filter(Column("chainId") == chainId)
                .filter(Column("isSpent") == false)
                .select(sum(Column("amount")))
                .fetchOne(dbConn)
            return sum ?? 0
        }
    }
    
    /// Count unspent UTXOs
    func countUnspent(walletId: String, chainId: String) async throws -> Int {
        try await db.readAsync { dbConn in
            try UTXORecord
                .filter(Column("walletId") == walletId)
                .filter(Column("chainId") == chainId)
                .filter(Column("isSpent") == false)
                .fetchCount(dbConn)
        }
    }
    
    /// Check if UTXO exists
    func exists(txHash: String, outputIndex: Int) async throws -> Bool {
        try await db.readAsync { dbConn in
            try UTXORecord
                .filter(Column("txHash") == txHash)
                .filter(Column("outputIndex") == outputIndex)
                .fetchCount(dbConn) > 0
        }
    }
    
    // MARK: - Coin Selection
    
    /// Select UTXOs for a target amount using a simple largest-first algorithm
    /// Returns selected UTXOs and total amount in satoshis
    func selectCoins(
        walletId: String,
        chainId: String,
        targetAmount: Int64,
        feePerByte: Int64
    ) async throws -> CoinSelectionResult {
        let unspent = try await fetchUnspent(walletId: walletId, chainId: chainId)
        return selectCoins(from: unspent, targetAmount: targetAmount, feePerByte: feePerByte)
    }
    
    /// Select coins from a given set of UTXOs
    func selectCoins(
        from utxos: [UTXORecord],
        targetAmount: Int64,
        feePerByte: Int64
    ) -> CoinSelectionResult {
        // Simple largest-first selection
        // A more sophisticated implementation would use Branch and Bound or Knapsack
        
        var selected: [UTXORecord] = []
        var totalSelected: Int64 = 0
        
        // Estimate base transaction size (version, locktime, output count)
        let baseSize: Int64 = 10 + 34 // 1 output (34 bytes) minimum
        var estimatedSize: Int64 = baseSize
        
        for utxo in utxos.sorted(by: { $0.amount > $1.amount }) {
            // Each P2PKH input is ~148 bytes, P2WPKH is ~68 bytes (vbytes)
            // Using conservative P2PKH estimate
            let inputSize: Int64 = 148
            let newSize = estimatedSize + inputSize
            let estimatedFee = newSize * feePerByte
            
            selected.append(utxo)
            totalSelected += utxo.amount
            estimatedSize = newSize
            
            // Check if we have enough (target + fee)
            let totalNeeded = targetAmount + estimatedFee
            if totalSelected >= totalNeeded {
                // Add change output size if there's enough change
                let change = totalSelected - totalNeeded
                let changeOutputSize: Int64 = 34
                let finalFee = (estimatedSize + (change > 546 ? changeOutputSize : 0)) * feePerByte
                
                return CoinSelectionResult(
                    utxos: selected,
                    totalAmount: totalSelected,
                    fee: finalFee,
                    change: totalSelected - targetAmount - finalFee
                )
            }
        }
        
        // Couldn't select enough
        let finalFee = estimatedSize * feePerByte
        return CoinSelectionResult(
            utxos: selected,
            totalAmount: totalSelected,
            fee: finalFee,
            change: 0,
            isInsufficient: true
        )
    }
    
    // MARK: - Delete
    
    /// Delete a UTXO
    func delete(txHash: String, outputIndex: Int) async throws {
        try await db.writeAsync { dbConn in
            try UTXORecord
                .filter(Column("txHash") == txHash)
                .filter(Column("outputIndex") == outputIndex)
                .deleteAll(dbConn)
        }
    }
    
    /// Delete all UTXOs for a wallet
    func deleteAll(walletId: String) async throws {
        try await db.writeAsync { dbConn in
            try UTXORecord
                .filter(Column("walletId") == walletId)
                .deleteAll(dbConn)
        }
    }
    
    /// Delete spent UTXOs older than a certain date (cleanup)
    func deleteOldSpent(olderThan days: Int) async throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        try await db.writeAsync { dbConn in
            try UTXORecord
                .filter(Column("isSpent") == true)
                .filter(Column("updatedAt") < cutoff)
                .deleteAll(dbConn)
        }
    }
    
    // MARK: - Sync Support
    
    /// Replace all UTXOs for a wallet/chain (full resync)
    func replaceAll(walletId: String, chainId: String, with utxos: [UTXORecord]) async throws {
        try await db.writeAsync { dbConn in
            // Delete existing
            try UTXORecord
                .filter(Column("walletId") == walletId)
                .filter(Column("chainId") == chainId)
                .deleteAll(dbConn)
            
            // Insert new
            for utxo in utxos {
                try utxo.insert(dbConn)
            }
        }
    }
    
    /// Get the latest block height we have UTXOs from
    func latestBlockHeight(walletId: String, chainId: String) async throws -> Int? {
        try await db.readAsync { dbConn in
            try UTXORecord
                .filter(Column("walletId") == walletId)
                .filter(Column("chainId") == chainId)
                .select(max(Column("blockHeight")))
                .fetchOne(dbConn)
        }
    }
}

// MARK: - Coin Selection Result

struct CoinSelectionResult: Sendable {
    let utxos: [UTXORecord]
    let totalAmount: Int64
    let fee: Int64
    let change: Int64
    var isInsufficient: Bool = false
    
    var amountAvailableToSend: Int64 {
        max(0, totalAmount - fee)
    }
}

// MARK: - Factory Methods

extension UTXORecord {
    /// Create a UTXO record from API response
    static func from(
        walletId: String,
        chainId: String,
        txHash: String,
        outputIndex: Int,
        address: String,
        amount: Int64,
        scriptPubKey: String,
        blockHeight: Int?
    ) -> UTXORecord {
        let now = Date()
        return UTXORecord(
            id: "\(txHash):\(outputIndex)",
            walletId: walletId,
            chainId: chainId,
            txHash: txHash,
            outputIndex: outputIndex,
            address: address,
            amount: amount,
            scriptPubKey: scriptPubKey,
            blockHeight: blockHeight,
            isSpent: false,
            spentInTxHash: nil,
            createdAt: now,
            updatedAt: now
        )
    }
}
