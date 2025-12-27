import SwiftUI
import Foundation

// MARK: - Transaction Cancellation Manager
/// Comprehensive transaction cancellation for Bitcoin (RBF) and Ethereum (nonce replacement)

@MainActor
final class TransactionCancellationManager: ObservableObject {
    static let shared = TransactionCancellationManager()
    
    // MARK: - Published State
    @Published var isProcessing = false
    @Published var lastError: TransactionCancelError?
    @Published var mempoolInfo: MempoolInfo?
    
    // MARK: - Types
    
    /// Information about current mempool state
    struct MempoolInfo {
        let fastestFee: Int      // sat/vB or gwei
        let halfHourFee: Int
        let hourFee: Int
        let minimumFee: Int
        let mempoolSize: Int?    // Number of unconfirmed txs
        let nextBlockFee: Int?   // Fee to get into next block
        let fetchedAt: Date
        
        var isStale: Bool {
            Date().timeIntervalSince(fetchedAt) > 60 // Stale after 1 minute
        }
    }
    
    /// Result of a cancellation attempt
    struct CancellationResult {
        let success: Bool
        let originalTxid: String
        let replacementTxid: String?
        let method: CancellationMethod
        let newFeeRate: Int
        let message: String
    }
    
    enum CancellationMethod: String {
        case rbfCancel = "RBF Cancel (send to self)"
        case rbfSpeedUp = "RBF Speed Up"
        case ethNonceReplace = "Nonce Replacement"
        case cpfp = "CPFP (Child Pays for Parent)"
    }
    
    /// Stored UTXO data for pending transactions (needed for RBF)
    struct StoredUTXO: Codable {
        let txid: String
        let vout: UInt32
        let value: Int64
        let scriptPubKey: String
    }
    
    /// Pending transaction with full data for cancellation
    struct CancellableTx: Codable, Identifiable {
        let id: String  // txid
        let chainId: String
        let inputs: [StoredUTXO]
        let outputAddress: String
        let outputValue: Int64
        let changeAddress: String?
        let changeValue: Int64?
        let feeRate: Int
        let nonce: Int?
        let timestamp: Date
        let rawHex: String?
        
        var totalInputValue: Int64 {
            inputs.reduce(0) { $0 + $1.value }
        }
        
        var totalFee: Int64 {
            let outputTotal = outputValue + (changeValue ?? 0)
            return totalInputValue - outputTotal
        }
    }
    
    // MARK: - Storage
    private let storageKey = "hawala.cancellableTxs"
    private var cancellableTxs: [String: CancellableTx] = [:]
    
    private init() {
        loadFromStorage()
    }
    
    // MARK: - Public API
    
    /// Store transaction data when broadcasting (called from send flow)
    func storeCancellableTransaction(_ tx: CancellableTx) {
        cancellableTxs[tx.id] = tx
        saveToStorage()
    }
    
    /// Check if a transaction can be cancelled
    func canCancel(txid: String, chainId: String) -> (canCancel: Bool, reason: String) {
        // Check if we have the data to cancel
        if let tx = cancellableTxs[txid] {
            switch chainId {
            case "bitcoin", "bitcoin-testnet", "litecoin":
                return (true, "RBF enabled - can cancel or speed up")
            case "ethereum", "ethereum-sepolia", "bnb":
                if tx.nonce != nil {
                    return (true, "Can replace with higher gas")
                } else {
                    return (false, "Missing nonce - cannot replace")
                }
            default:
                return (false, "Cancellation not supported for \(chainId)")
            }
        }
        
        // We don't have stored data, but might still be able to cancel ETH
        if ["ethereum", "ethereum-sepolia", "bnb"].contains(chainId) {
            return (true, "Can cancel by sending 0 ETH to self with same nonce")
        }
        
        return (false, "Transaction data not available for cancellation")
    }
    
    /// Cancel a Bitcoin transaction (RBF - send all funds back to self)
    func cancelBitcoinTransaction(
        pendingTx: PendingTransactionManager.PendingTransaction,
        privateKeyWIF: String,
        returnAddress: String,
        newFeeRate: Int
    ) async throws -> CancellationResult {
        
        isProcessing = true
        lastError = nil
        
        defer { isProcessing = false }
        
        // Get stored transaction data
        guard let storedTx = cancellableTxs[pendingTx.id] else {
            throw TransactionCancelError.missingTransactionData
        }
        
        let isTestnet = pendingTx.chainId == "bitcoin-testnet"
        
        // Validate fee rate is higher than original
        guard newFeeRate > storedTx.feeRate else {
            throw TransactionCancelError.feeTooLow(
                minimum: storedTx.feeRate + 1,
                provided: newFeeRate
            )
        }
        
        // Build cancellation transaction (all inputs → return address)
        let inputs = storedTx.inputs.map { utxo in
            BitcoinTransactionBuilder.Input(
                txid: utxo.txid,
                vout: utxo.vout,
                value: utxo.value,
                scriptPubKey: Data(hex: utxo.scriptPubKey) ?? Data()
            )
        }
        
        // Calculate new fee based on estimated vsize (~110 vB for 1-in-1-out P2WPKH)
        let estimatedVsize = 110 + (inputs.count - 1) * 68 // Additional inputs ~68 vB each
        let newFee = Int64(newFeeRate * estimatedVsize)
        
        // Output value = total input - new fee
        let outputValue = storedTx.totalInputValue - newFee
        
        guard outputValue > 546 else { // Dust limit
            throw TransactionCancelError.outputBelowDust(value: outputValue)
        }
        
        let outputs = [
            BitcoinTransactionBuilder.Output(
                address: returnAddress,
                value: outputValue
            )
        ]
        
        // Build and sign
        let signedTx = try BitcoinTransactionBuilder.buildAndSign(
            inputs: inputs,
            outputs: outputs,
            privateKeyWIF: privateKeyWIF,
            isTestnet: isTestnet
        )
        
        // Broadcast
        let txid = try await broadcastBitcoinTransaction(
            rawHex: signedTx.rawHex,
            isTestnet: isTestnet,
            isLitecoin: pendingTx.chainId == "litecoin"
        )
        
        // Update tracking
        await PendingTransactionManager.shared.markReplaced(pendingTx.id, replacedBy: txid)
        
        // Remove old stored data, add new
        cancellableTxs.removeValue(forKey: pendingTx.id)
        cancellableTxs[txid] = CancellableTx(
            id: txid,
            chainId: pendingTx.chainId,
            inputs: storedTx.inputs,
            outputAddress: returnAddress,
            outputValue: outputValue,
            changeAddress: nil,
            changeValue: nil,
            feeRate: newFeeRate,
            nonce: nil,
            timestamp: Date(),
            rawHex: signedTx.rawHex
        )
        saveToStorage()
        
        return CancellationResult(
            success: true,
            originalTxid: pendingTx.id,
            replacementTxid: txid,
            method: .rbfCancel,
            newFeeRate: newFeeRate,
            message: "Transaction cancelled. Funds returning to \(truncate(returnAddress))"
        )
    }
    
    /// Speed up a Bitcoin transaction (RBF - same outputs, higher fee from change)
    func speedUpBitcoinTransaction(
        pendingTx: PendingTransactionManager.PendingTransaction,
        privateKeyWIF: String,
        newFeeRate: Int
    ) async throws -> CancellationResult {
        
        isProcessing = true
        lastError = nil
        
        defer { isProcessing = false }
        
        guard let storedTx = cancellableTxs[pendingTx.id] else {
            throw TransactionCancelError.missingTransactionData
        }
        
        let isTestnet = pendingTx.chainId == "bitcoin-testnet"
        
        guard newFeeRate > storedTx.feeRate else {
            throw TransactionCancelError.feeTooLow(
                minimum: storedTx.feeRate + 1,
                provided: newFeeRate
            )
        }
        
        // Build inputs
        let inputs = storedTx.inputs.map { utxo in
            BitcoinTransactionBuilder.Input(
                txid: utxo.txid,
                vout: utxo.vout,
                value: utxo.value,
                scriptPubKey: Data(hex: utxo.scriptPubKey) ?? Data()
            )
        }
        
        // Calculate new fee
        let estimatedVsize = 110 + (inputs.count - 1) * 68 + (storedTx.changeAddress != nil ? 31 : 0)
        let newFee = Int64(newFeeRate * estimatedVsize)
        let additionalFee = newFee - storedTx.totalFee
        
        // Build outputs - keep original recipient output, reduce change
        var outputs: [BitcoinTransactionBuilder.Output] = [
            BitcoinTransactionBuilder.Output(
                address: storedTx.outputAddress,
                value: storedTx.outputValue
            )
        ]
        
        // Calculate new change
        if let changeAddr = storedTx.changeAddress, let originalChange = storedTx.changeValue {
            let newChange = originalChange - additionalFee
            if newChange > 546 { // Above dust
                outputs.append(BitcoinTransactionBuilder.Output(
                    address: changeAddr,
                    value: newChange
                ))
            }
            // If below dust, entire change becomes fee (acceptable for speed-up)
        } else {
            // No change output - fee increase must come from... somewhere
            // This shouldn't happen in normal usage, but handle gracefully
            throw TransactionCancelError.insufficientFunds
        }
        
        // Build and sign
        let signedTx = try BitcoinTransactionBuilder.buildAndSign(
            inputs: inputs,
            outputs: outputs,
            privateKeyWIF: privateKeyWIF,
            isTestnet: isTestnet
        )
        
        // Broadcast
        let txid = try await broadcastBitcoinTransaction(
            rawHex: signedTx.rawHex,
            isTestnet: isTestnet,
            isLitecoin: pendingTx.chainId == "litecoin"
        )
        
        // Update tracking
        await PendingTransactionManager.shared.markReplaced(pendingTx.id, replacedBy: txid)
        
        // Update stored data
        cancellableTxs.removeValue(forKey: pendingTx.id)
        let newChangeValue = outputs.count > 1 ? outputs[1].value : nil
        cancellableTxs[txid] = CancellableTx(
            id: txid,
            chainId: pendingTx.chainId,
            inputs: storedTx.inputs,
            outputAddress: storedTx.outputAddress,
            outputValue: storedTx.outputValue,
            changeAddress: outputs.count > 1 ? storedTx.changeAddress : nil,
            changeValue: newChangeValue,
            feeRate: newFeeRate,
            nonce: nil,
            timestamp: Date(),
            rawHex: signedTx.rawHex
        )
        saveToStorage()
        
        return CancellationResult(
            success: true,
            originalTxid: pendingTx.id,
            replacementTxid: txid,
            method: .rbfSpeedUp,
            newFeeRate: newFeeRate,
            message: "Transaction sped up with \(newFeeRate) sat/vB fee"
        )
    }
    
    /// Cancel an Ethereum transaction (send 0 ETH to self with same nonce)
    func cancelEthereumTransaction(
        pendingTx: PendingTransactionManager.PendingTransaction,
        privateKeyHex: String,
        senderAddress: String,
        newGasPrice: UInt64 // in wei
    ) async throws -> CancellationResult {
        
        isProcessing = true
        lastError = nil
        
        defer { isProcessing = false }
        
        guard let nonce = pendingTx.nonce else {
            throw TransactionCancelError.missingNonce
        }
        
        let chainId = getChainId(for: pendingTx.chainId)
        let rpcURL = getRPCURL(for: pendingTx.chainId)
        
        // Get current gas price to ensure we're above it
        let currentGasPrice = try await fetchGasPrice(rpcURL: rpcURL)
        let originalGasWei = UInt64(pendingTx.originalFeeRate ?? 0) * 1_000_000_000
        
        // Must be at least 10% higher than original
        let minimumGas = max(UInt64(Double(originalGasWei) * 1.1), currentGasPrice)
        guard newGasPrice >= minimumGas else {
            throw TransactionCancelError.gasTooLow(minimum: minimumGas, provided: newGasPrice)
        }
        
        // Build cancellation tx: 0 ETH to self
        // Use EIP-1559 for Ethereum mainnet and Sepolia
        let signedTx: String
        if chainId == 1 || chainId == 11155111 {
            // EIP-1559 transaction
            let priorityFeeMultiplier = chainId == 11155111 ? 0.5 : 0.1
            let maxPriorityFeeWei = UInt64(max(2_500_000_000, Double(newGasPrice) * priorityFeeMultiplier))
            signedTx = try EthereumTransaction.buildAndSignEIP1559(
                to: senderAddress,
                value: "0",
                gasLimit: 21000,
                maxFeePerGas: String(newGasPrice),
                maxPriorityFeePerGas: String(maxPriorityFeeWei),
                nonce: nonce,
                chainId: chainId,
                privateKeyHex: privateKeyHex,
                data: "0x"
            )
        } else {
            // Legacy transaction for BSC
            signedTx = try EthereumTransaction.buildAndSign(
                to: senderAddress,
                value: "0",
                gasLimit: 21000,
                gasPrice: String(newGasPrice),
                nonce: nonce,
                chainId: chainId,
                privateKeyHex: privateKeyHex,
                data: "0x"
            )
        }
        
        // Broadcast
        let txid = try await broadcastEthereumTransaction(signedTx: signedTx, rpcURL: rpcURL)
        
        // Update tracking
        await PendingTransactionManager.shared.markReplaced(pendingTx.id, replacedBy: txid)
        
        return CancellationResult(
            success: true,
            originalTxid: pendingTx.id,
            replacementTxid: txid,
            method: .ethNonceReplace,
            newFeeRate: Int(newGasPrice / 1_000_000_000), // Convert to gwei
            message: "Transaction cancelled. Nonce \(nonce) consumed."
        )
    }
    
    /// Speed up an Ethereum transaction (same tx with higher gas)
    func speedUpEthereumTransaction(
        pendingTx: PendingTransactionManager.PendingTransaction,
        privateKeyHex: String,
        newGasPrice: UInt64 // in wei
    ) async throws -> CancellationResult {
        
        isProcessing = true
        lastError = nil
        
        defer { isProcessing = false }
        
        guard let nonce = pendingTx.nonce else {
            throw TransactionCancelError.missingNonce
        }
        
        let chainId = getChainId(for: pendingTx.chainId)
        let rpcURL = getRPCURL(for: pendingTx.chainId)
        
        // Parse amount
        let amountString = pendingTx.amount.components(separatedBy: " ").first ?? "0"
        guard let amountDouble = Double(amountString) else {
            throw TransactionCancelError.invalidAmount
        }
        let weiAmount = UInt64(amountDouble * 1e18)
        
        // Validate gas price
        let originalGasWei = UInt64(pendingTx.originalFeeRate ?? 0) * 1_000_000_000
        let minimumGas = UInt64(Double(originalGasWei) * 1.1)
        guard newGasPrice >= minimumGas else {
            throw TransactionCancelError.gasTooLow(minimum: minimumGas, provided: newGasPrice)
        }
        
        // Build replacement transaction
        // Use EIP-1559 for Ethereum mainnet and Sepolia
        let signedTx: String
        if chainId == 1 || chainId == 11155111 {
            // EIP-1559 transaction
            let priorityFeeMultiplier = chainId == 11155111 ? 0.5 : 0.1
            let maxPriorityFeeWei = UInt64(max(2_500_000_000, Double(newGasPrice) * priorityFeeMultiplier))
            signedTx = try EthereumTransaction.buildAndSignEIP1559(
                to: pendingTx.recipient,
                value: String(weiAmount),
                gasLimit: 21000,
                maxFeePerGas: String(newGasPrice),
                maxPriorityFeePerGas: String(maxPriorityFeeWei),
                nonce: nonce,
                chainId: chainId,
                privateKeyHex: privateKeyHex,
                data: "0x"
            )
        } else {
            // Legacy transaction for BSC
            signedTx = try EthereumTransaction.buildAndSign(
                to: pendingTx.recipient,
                value: String(weiAmount),
                gasLimit: 21000,
                gasPrice: String(newGasPrice),
                nonce: nonce,
                chainId: chainId,
                privateKeyHex: privateKeyHex,
                data: "0x"
            )
        }
        
        // Broadcast
        let txid = try await broadcastEthereumTransaction(signedTx: signedTx, rpcURL: rpcURL)
        
        // Update tracking
        await PendingTransactionManager.shared.markReplaced(pendingTx.id, replacedBy: txid)
        
        return CancellationResult(
            success: true,
            originalTxid: pendingTx.id,
            replacementTxid: txid,
            method: .ethNonceReplace,
            newFeeRate: Int(newGasPrice / 1_000_000_000),
            message: "Transaction sped up with \(newGasPrice / 1_000_000_000) gwei gas"
        )
    }
    
    // MARK: - Fee Estimation
    
    /// Fetch current mempool fee estimates
    func fetchMempoolInfo(chainId: String) async throws -> MempoolInfo {
        switch chainId {
        case "bitcoin", "bitcoin-testnet", "litecoin":
            return try await fetchBitcoinMempoolInfo(chainId: chainId)
        case "ethereum", "ethereum-sepolia", "bnb":
            return try await fetchEthereumGasInfo(chainId: chainId)
        default:
            throw TransactionCancelError.unsupportedChain(chainId)
        }
    }
    
    private func fetchBitcoinMempoolInfo(chainId: String) async throws -> MempoolInfo {
        let baseURL: String
        switch chainId {
        case "bitcoin-testnet":
            baseURL = "https://mempool.space/testnet/api"
        case "litecoin":
            baseURL = "https://litecoinspace.org/api"
        default:
            baseURL = "https://mempool.space/api"
        }
        
        // Fetch fee estimates
        guard let feeURL = URL(string: "\(baseURL)/v1/fees/recommended") else {
            throw TransactionCancelError.networkError("Invalid URL")
        }
        
        let (feeData, _) = try await URLSession.shared.data(from: feeURL)
        let fees = try JSONDecoder().decode(BitcoinFeeEstimates.self, from: feeData)
        
        // Fetch mempool stats
        var mempoolSize: Int?
        if let statsURL = URL(string: "\(baseURL)/mempool"),
           let (statsData, _) = try? await URLSession.shared.data(from: statsURL),
           let stats = try? JSONSerialization.jsonObject(with: statsData) as? [String: Any],
           let count = stats["count"] as? Int {
            mempoolSize = count
        }
        
        let info = MempoolInfo(
            fastestFee: fees.fastestFee,
            halfHourFee: fees.halfHourFee,
            hourFee: fees.hourFee,
            minimumFee: fees.minimumFee,
            mempoolSize: mempoolSize,
            nextBlockFee: fees.fastestFee,
            fetchedAt: Date()
        )
        
        await MainActor.run {
            self.mempoolInfo = info
        }
        
        return info
    }
    
    private func fetchEthereumGasInfo(chainId: String) async throws -> MempoolInfo {
        let rpcURL = getRPCURL(for: chainId)
        let gasPrice = try await fetchGasPrice(rpcURL: rpcURL)
        let gasPriceGwei = Int(gasPrice / 1_000_000_000)
        
        // Estimate different tiers
        let info = MempoolInfo(
            fastestFee: Int(Double(gasPriceGwei) * 1.5),
            halfHourFee: Int(Double(gasPriceGwei) * 1.2),
            hourFee: gasPriceGwei,
            minimumFee: max(1, Int(Double(gasPriceGwei) * 0.8)),
            mempoolSize: nil,
            nextBlockFee: Int(Double(gasPriceGwei) * 1.3),
            fetchedAt: Date()
        )
        
        await MainActor.run {
            self.mempoolInfo = info
        }
        
        return info
    }
    
    // MARK: - Broadcasting
    
    private func broadcastBitcoinTransaction(rawHex: String, isTestnet: Bool, isLitecoin: Bool) async throws -> String {
        let baseURL: String
        if isLitecoin {
            baseURL = "https://litecoinspace.org/api"
        } else if isTestnet {
            baseURL = "https://blockstream.info/testnet/api"
        } else {
            baseURL = "https://blockstream.info/api"
        }
        
        guard let url = URL(string: "\(baseURL)/tx") else {
            throw TransactionCancelError.networkError("Invalid broadcast URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = rawHex.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TransactionCancelError.networkError("Invalid response")
        }
        
        if httpResponse.statusCode == 200 {
            guard let txid = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw TransactionCancelError.broadcastFailed("No txid returned")
            }
            return txid
        } else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TransactionCancelError.broadcastFailed(errorMsg)
        }
    }
    
    private func broadcastEthereumTransaction(signedTx: String, rpcURL: String) async throws -> String {
        guard let url = URL(string: rpcURL) else {
            throw TransactionCancelError.networkError("Invalid RPC URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_sendRawTransaction",
            "params": [signedTx],
            "id": 1
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        if let error = json?["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw TransactionCancelError.broadcastFailed(message)
        }
        
        guard let txid = json?["result"] as? String else {
            throw TransactionCancelError.broadcastFailed("No transaction hash returned")
        }
        
        return txid
    }
    
    // MARK: - Helpers
    
    private func fetchGasPrice(rpcURL: String) async throws -> UInt64 {
        guard let url = URL(string: rpcURL) else {
            throw TransactionCancelError.networkError("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_gasPrice",
            "params": [],
            "id": 1
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let result = json?["result"] as? String,
              let gasPrice = UInt64(result.dropFirst(2), radix: 16) else {
            throw TransactionCancelError.networkError("Failed to parse gas price")
        }
        
        return gasPrice
    }
    
    private func getChainId(for chainId: String) -> Int {
        switch chainId {
        case "ethereum": return 1
        case "ethereum-sepolia": return 11155111
        case "bnb": return 56
        default: return 1
        }
    }
    
    private func getRPCURL(for chainId: String) -> String {
        switch chainId {
        case "ethereum": return "https://eth.llamarpc.com"
        case "ethereum-sepolia": return "https://ethereum-sepolia-rpc.publicnode.com"
        case "bnb": return "https://bsc-dataseed.binance.org/"
        default: return "https://eth.llamarpc.com"
        }
    }
    
    private func truncate(_ address: String) -> String {
        guard address.count > 16 else { return address }
        return "\(address.prefix(8))...\(address.suffix(6))"
    }
    
    // MARK: - Persistence
    
    private func loadFromStorage() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: CancellableTx].self, from: data) else {
            return
        }
        cancellableTxs = decoded
    }
    
    private func saveToStorage() {
        guard let data = try? JSONEncoder().encode(cancellableTxs) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
    
    /// Clean up old transaction data (older than 24 hours)
    func pruneOldTransactions() {
        let oneDayAgo = Date().addingTimeInterval(-86400)
        cancellableTxs = cancellableTxs.filter { $0.value.timestamp > oneDayAgo }
        saveToStorage()
    }
    
    // MARK: - UTXO Fetching (Fallback)
    
    /// Fetch transaction details from mempool API (for when we don't have stored data)
    func fetchTransactionDetails(txid: String, chainId: String) async throws -> CancellableTx? {
        let baseURL: String
        switch chainId {
        case "bitcoin-testnet":
            baseURL = "https://mempool.space/testnet/api"
        case "litecoin":
            baseURL = "https://litecoinspace.org/api"
        default:
            baseURL = "https://mempool.space/api"
        }
        
        guard let url = URL(string: "\(baseURL)/tx/\(txid)") else {
            throw TransactionCancelError.networkError("Invalid URL")
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? [String: Any] else {
            throw TransactionCancelError.networkError("Failed to parse transaction")
        }
        
        // Check if already confirmed
        if let confirmed = status["confirmed"] as? Bool, confirmed {
            throw TransactionCancelError.alreadyConfirmed
        }
        
        // Parse inputs
        guard let vin = json["vin"] as? [[String: Any]] else {
            throw TransactionCancelError.networkError("Failed to parse inputs")
        }
        
        var inputs: [StoredUTXO] = []
        for input in vin {
            guard let prevTxid = input["txid"] as? String,
                  let vout = input["vout"] as? UInt32,
                  let prevout = input["prevout"] as? [String: Any],
                  let value = prevout["value"] as? Int64,
                  let scriptpubkey = prevout["scriptpubkey"] as? String else {
                continue
            }
            inputs.append(StoredUTXO(
                txid: prevTxid,
                vout: vout,
                value: value,
                scriptPubKey: scriptpubkey
            ))
        }
        
        guard !inputs.isEmpty else {
            throw TransactionCancelError.transactionNotFound
        }
        
        // Parse outputs
        guard let vout = json["vout"] as? [[String: Any]] else {
            throw TransactionCancelError.networkError("Failed to parse outputs")
        }
        
        var outputAddress = ""
        var outputValue: Int64 = 0
        var changeAddress: String?
        var changeValue: Int64?
        
        for (index, output) in vout.enumerated() {
            guard let value = output["value"] as? Int64,
                  let scriptpubkey_address = output["scriptpubkey_address"] as? String else {
                continue
            }
            
            if index == 0 {
                outputAddress = scriptpubkey_address
                outputValue = value
            } else if index == 1 {
                changeAddress = scriptpubkey_address
                changeValue = value
            }
        }
        
        // Calculate fee rate
        guard let fee = json["fee"] as? Int64,
              let size = json["weight"] as? Int else {
            throw TransactionCancelError.networkError("Failed to parse fee data")
        }
        let vsize = (size + 3) / 4 // Virtual size from weight
        let feeRate = Int(fee) / max(vsize, 1)
        
        let tx = CancellableTx(
            id: txid,
            chainId: chainId,
            inputs: inputs,
            outputAddress: outputAddress,
            outputValue: outputValue,
            changeAddress: changeAddress,
            changeValue: changeValue,
            feeRate: feeRate,
            nonce: nil,
            timestamp: Date(),
            rawHex: nil
        )
        
        // Store for future use
        cancellableTxs[txid] = tx
        saveToStorage()
        
        return tx
    }
    
    /// Attempt to fetch transaction data if not stored, then cancel
    func cancelBitcoinTransactionWithFetch(
        pendingTx: PendingTransactionManager.PendingTransaction,
        privateKeyWIF: String,
        returnAddress: String,
        newFeeRate: Int
    ) async throws -> CancellationResult {
        // Try to get stored data first
        if cancellableTxs[pendingTx.id] == nil {
            // Fetch from mempool API
            let _ = try await fetchTransactionDetails(txid: pendingTx.id, chainId: pendingTx.chainId)
        }
        
        // Now call the regular cancel function
        return try await cancelBitcoinTransaction(
            pendingTx: pendingTx,
            privateKeyWIF: privateKeyWIF,
            returnAddress: returnAddress,
            newFeeRate: newFeeRate
        )
    }
    
    /// Attempt to fetch transaction data if not stored, then speed up
    func speedUpBitcoinTransactionWithFetch(
        pendingTx: PendingTransactionManager.PendingTransaction,
        privateKeyWIF: String,
        newFeeRate: Int
    ) async throws -> CancellationResult {
        // Try to get stored data first
        if cancellableTxs[pendingTx.id] == nil {
            // Fetch from mempool API
            let _ = try await fetchTransactionDetails(txid: pendingTx.id, chainId: pendingTx.chainId)
        }
        
        // Now call the regular speed up function
        return try await speedUpBitcoinTransaction(
            pendingTx: pendingTx,
            privateKeyWIF: privateKeyWIF,
            newFeeRate: newFeeRate
        )
    }
}

// MARK: - Errors

enum TransactionCancelError: LocalizedError {
    case missingTransactionData
    case missingNonce
    case feeTooLow(minimum: Int, provided: Int)
    case gasTooLow(minimum: UInt64, provided: UInt64)
    case outputBelowDust(value: Int64)
    case insufficientFunds
    case invalidAmount
    case unsupportedChain(String)
    case networkError(String)
    case broadcastFailed(String)
    case alreadyConfirmed
    case transactionNotFound
    
    var errorDescription: String? {
        switch self {
        case .missingTransactionData:
            return "Transaction data not available. Cannot cancel transactions not sent from this wallet."
        case .missingNonce:
            return "Transaction nonce not found. Cannot replace transaction."
        case .feeTooLow(let min, let provided):
            return "Fee too low. Minimum: \(min) sat/vB, provided: \(provided) sat/vB"
        case .gasTooLow(let min, let provided):
            return "Gas price too low. Minimum: \(min / 1_000_000_000) gwei, provided: \(provided / 1_000_000_000) gwei"
        case .outputBelowDust(let value):
            return "Output value (\(value) sats) is below dust limit (546 sats)"
        case .insufficientFunds:
            return "Insufficient funds to cover increased fee"
        case .invalidAmount:
            return "Invalid transaction amount"
        case .unsupportedChain(let chain):
            return "Transaction cancellation not supported for \(chain)"
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .broadcastFailed(let msg):
            return "Failed to broadcast: \(msg)"
        case .alreadyConfirmed:
            return "Transaction already confirmed. Cannot cancel."
        case .transactionNotFound:
            return "Transaction not found in mempool. It may have already confirmed or been dropped."
        }
    }
}
