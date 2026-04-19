import Foundation

// MARK: - UTXO Coin Selector

/// Integrates UTXOStore with BitcoinTransactionBuilder for seamless transaction construction
/// Provides coin selection algorithms and fee estimation
@MainActor
final class UTXOCoinSelector {
    
    // MARK: - Singleton
    
    static let shared = UTXOCoinSelector()
    
    // MARK: - Properties
    
    private let utxoStore = UTXOStore.shared
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Coin Selection
    
    /// Select UTXOs for a Bitcoin/Litecoin transaction
    /// - Parameters:
    ///   - walletId: The wallet ID
    ///   - chainId: "bitcoin", "bitcoin-testnet", or "litecoin"
    ///   - amount: Amount to send in satoshis
    ///   - feeRate: Fee rate in sat/vB
    ///   - changeAddress: Address to send change to
    /// - Returns: Selected UTXOs, estimated fee, and change amount
    func selectUTXOs(
        walletId: String,
        chainId: String,
        amount: Int64,
        feeRate: Int64,
        changeAddress: String
    ) async throws -> CoinSelectionOutput {
        
        // Fetch all unspent UTXOs
        let allUTXOs = try await utxoStore.fetchUnspent(walletId: walletId, chainId: chainId)
        
        guard !allUTXOs.isEmpty else {
            throw CoinSelectionError.noUTXOs
        }
        
        // Calculate total available
        let totalAvailable = allUTXOs.reduce(Int64(0)) { $0 + $1.amount }
        
        guard totalAvailable >= amount else {
            throw CoinSelectionError.insufficientFunds(available: totalAvailable, required: amount)
        }
        
        // Use largest-first selection with fee estimation
        let result = selectLargestFirst(
            utxos: allUTXOs,
            targetAmount: amount,
            feeRate: feeRate,
            includeChange: true
        )
        
        guard !result.isInsufficient else {
            throw CoinSelectionError.insufficientFunds(
                available: result.totalAmount,
                required: amount + result.fee
            )
        }
        
        // Convert to BitcoinTransactionBuilder.Input format
        let inputs = result.utxos.map { utxo -> BitcoinInput in
            BitcoinInput(
                txid: utxo.txHash,
                vout: UInt32(utxo.outputIndex),
                value: utxo.amount,
                scriptPubKey: utxo.scriptPubKey,
                address: utxo.address
            )
        }
        
        return CoinSelectionOutput(
            inputs: inputs,
            totalInputAmount: result.totalAmount,
            fee: result.fee,
            change: result.change,
            changeAddress: result.change > 0 ? changeAddress : nil
        )
    }
    
    /// Estimate fee for sending a specific amount
    func estimateFee(
        walletId: String,
        chainId: String,
        amount: Int64,
        feeRate: Int64
    ) async throws -> Int64 {
        let selection = try await selectUTXOs(
            walletId: walletId,
            chainId: chainId,
            amount: amount,
            feeRate: feeRate,
            changeAddress: "" // Not needed for estimation
        )
        return selection.fee
    }
    
    /// Get maximum sendable amount (balance minus minimum fee)
    func getMaxSendable(
        walletId: String,
        chainId: String,
        feeRate: Int64
    ) async throws -> Int64 {
        let allUTXOs = try await utxoStore.fetchUnspent(walletId: walletId, chainId: chainId)
        
        guard !allUTXOs.isEmpty else {
            return 0
        }
        
        let totalBalance = allUTXOs.reduce(Int64(0)) { $0 + $1.amount }
        
        // Estimate fee for spending all UTXOs (no change output)
        let inputCount = allUTXOs.count
        let outputCount = 1 // Just destination, no change
        let estimatedSize = estimateTransactionSize(inputCount: inputCount, outputCount: outputCount)
        let fee = Int64(estimatedSize) * feeRate
        
        return max(0, totalBalance - fee)
    }
    
    // MARK: - Private Selection Algorithms
    
    /// Largest-first coin selection
    /// Simple and effective for most cases
    private func selectLargestFirst(
        utxos: [UTXORecord],
        targetAmount: Int64,
        feeRate: Int64,
        includeChange: Bool
    ) -> InternalSelectionResult {
        
        var selected: [UTXORecord] = []
        var totalSelected: Int64 = 0
        
        // Sort by amount descending
        let sorted = utxos.sorted { $0.amount > $1.amount }
        
        for utxo in sorted {
            selected.append(utxo)
            totalSelected += utxo.amount
            
            // Calculate fee with current selection
            let inputCount = selected.count
            let outputCount = includeChange ? 2 : 1 // destination + optional change
            let estimatedSize = estimateTransactionSize(inputCount: inputCount, outputCount: outputCount)
            let fee = Int64(estimatedSize) * feeRate
            
            let totalNeeded = targetAmount + fee
            
            if totalSelected >= totalNeeded {
                let change = totalSelected - totalNeeded
                
                // If change is dust (< 546 sats), don't include change output
                let dustThreshold: Int64 = 546
                if change < dustThreshold {
                    // Recalculate without change output
                    let noChangeSize = estimateTransactionSize(inputCount: inputCount, outputCount: 1)
                    let noChangeFee = Int64(noChangeSize) * feeRate
                    
                    if totalSelected >= targetAmount + noChangeFee {
                        return InternalSelectionResult(
                            utxos: selected,
                            totalAmount: totalSelected,
                            fee: noChangeFee,
                            change: 0
                        )
                    }
                    // Not enough even without change, continue selecting
                } else {
                    return InternalSelectionResult(
                        utxos: selected,
                        totalAmount: totalSelected,
                        fee: fee,
                        change: change
                    )
                }
            }
        }
        
        // Couldn't select enough
        let finalSize = estimateTransactionSize(inputCount: selected.count, outputCount: 1)
        let finalFee = Int64(finalSize) * feeRate
        
        return InternalSelectionResult(
            utxos: selected,
            totalAmount: totalSelected,
            fee: finalFee,
            change: 0,
            isInsufficient: true
        )
    }
    
    /// Estimate transaction virtual size in vbytes
    /// For P2WPKH (native SegWit)
    private func estimateTransactionSize(inputCount: Int, outputCount: Int) -> Int {
        // P2WPKH transaction structure:
        // - Version: 4 bytes
        // - Marker + Flag: 2 bytes (SegWit)
        // - Input count: 1 byte (varint, assuming < 253 inputs)
        // - Each input: 32 (txid) + 4 (vout) + 1 (scriptSig len) + 0 (scriptSig) + 4 (sequence) = 41 bytes
        // - Output count: 1 byte
        // - Each output: 8 (value) + 1 (scriptPubKey len) + 22 (P2WPKH scriptPubKey) = 31 bytes
        // - Witness: Each input has ~107 bytes (signature + pubkey)
        // - Locktime: 4 bytes
        
        // Non-witness data (weight = 4x)
        let baseSize = 4 + 2 + 1 + (inputCount * 41) + 1 + (outputCount * 31) + 4
        
        // Witness data (weight = 1x)
        let witnessSize = inputCount * 107
        
        // Virtual size = (weight units + 3) / 4
        let weight = baseSize * 4 + witnessSize
        return (weight + 3) / 4
    }
}

// MARK: - Supporting Types

/// Output of coin selection
struct CoinSelectionOutput {
    let inputs: [BitcoinInput]
    let totalInputAmount: Int64
    let fee: Int64
    let change: Int64
    let changeAddress: String?
    
    var amountAfterFee: Int64 {
        totalInputAmount - fee
    }
}

/// Input format for Bitcoin transaction building
struct BitcoinInput {
    let txid: String
    let vout: UInt32
    let value: Int64
    let scriptPubKey: String
    let address: String
    
    /// Convert to BitcoinTransactionBuilder.Input
    func toBuilderInput() -> BitcoinTransactionBuilder.Input {
        BitcoinTransactionBuilder.Input(
            txid: txid,
            vout: vout,
            value: value,
            scriptPubKey: Data(hex: scriptPubKey) ?? Data()
        )
    }
}

/// Internal result for coin selection algorithms
private struct InternalSelectionResult {
    let utxos: [UTXORecord]
    let totalAmount: Int64
    let fee: Int64
    let change: Int64
    var isInsufficient: Bool = false
}

/// Coin selection errors
enum CoinSelectionError: LocalizedError {
    case noUTXOs
    case insufficientFunds(available: Int64, required: Int64)
    case invalidAddress
    
    var errorDescription: String? {
        switch self {
        case .noUTXOs:
            return "No unspent outputs available"
        case .insufficientFunds(let available, let required):
            let availableBTC = Double(available) / 100_000_000
            let requiredBTC = Double(required) / 100_000_000
            return "Insufficient funds. Available: \(String(format: "%.8f", availableBTC)), Required: \(String(format: "%.8f", requiredBTC))"
        case .invalidAddress:
            return "Invalid Bitcoin address"
        }
    }
}
