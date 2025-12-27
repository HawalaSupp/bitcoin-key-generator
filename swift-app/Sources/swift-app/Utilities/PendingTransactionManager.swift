import Foundation

/// Tracks pending (unconfirmed) transactions and polls for confirmation status
actor PendingTransactionManager {
    
    // MARK: - Types
    
    enum TransactionStatus: String, Codable, Equatable {
        case pending = "pending"
        case confirmed = "confirmed"
        case failed = "failed"
        case replaced = "replaced" // RBF replaced
    }
    
    struct PendingTransaction: Identifiable, Codable, Equatable {
        let id: String // txid/hash
        let chainId: String
        let chainName: String
        let amount: String
        let recipient: String
        let timestamp: Date
        var status: TransactionStatus
        var confirmations: Int
        var explorerURL: URL?
        var isRBFEnabled: Bool // Whether tx was sent with RBF flag
        var originalFeeRate: Int? // sat/vB for Bitcoin, gwei for ETH
        var nonce: Int? // For Ethereum speedup
        
        var displayStatus: String {
            switch status {
            case .pending:
                return confirmations > 0 ? "\(confirmations) conf." : "Pending"
            case .confirmed:
                return "Confirmed"
            case .failed:
                return "Failed"
            case .replaced:
                return "Replaced"
            }
        }
        
        /// Whether this transaction can be sped up
        var canSpeedUp: Bool {
            guard status == .pending else { return false }
            // Bitcoin/Litecoin: need RBF flag
            // Ethereum/BNB: can always replace with same nonce
            switch chainId {
            case "bitcoin", "bitcoin-testnet", "litecoin":
                return isRBFEnabled
            case "ethereum", "ethereum-sepolia", "bnb":
                return nonce != nil
            default:
                return false
            }
        }
    }
    
    // MARK: - Properties
    
    private var transactions: [PendingTransaction] = []
    private var pollingTask: Task<Void, Never>?
    private let storageKey = "hawala.pendingTransactions"
    private let pollingInterval: TimeInterval = 15 // seconds
    
    // Required confirmations per chain
    private let confirmationThresholds: [String: Int] = [
        "bitcoin": 6,
        "bitcoin-testnet": 1,
        "litecoin": 6,
        "ethereum": 12,
        "ethereum-sepolia": 1,
        "bnb": 15,
        "solana": 1,
        "xrp": 1
    ]
    
    // MARK: - Public API
    
    static let shared = PendingTransactionManager()
    
    private init() {
        Task { await loadFromStorage() }
    }
    
    /// Add a new pending transaction after broadcast
    func add(
        txid: String,
        chainId: String,
        chainName: String,
        amount: String,
        recipient: String,
        isRBFEnabled: Bool = false,
        feeRate: Int? = nil,
        nonce: Int? = nil
    ) async {
        let tx = PendingTransaction(
            id: txid,
            chainId: chainId,
            chainName: chainName,
            amount: amount,
            recipient: recipient,
            timestamp: Date(),
            status: .pending,
            confirmations: 0,
            explorerURL: explorerURL(for: chainId, txid: txid),
            isRBFEnabled: isRBFEnabled,
            originalFeeRate: feeRate,
            nonce: nonce
        )
        transactions.insert(tx, at: 0)
        await saveToStorage()
        startPollingIfNeeded()
    }

    /// Mark a transaction as replaced (after RBF)
    func markReplaced(_ txid: String, replacedBy newTxid: String) async {
        if let index = transactions.firstIndex(where: { $0.id == txid }) {
            transactions[index].status = .replaced
        }
        await saveToStorage()
    }
    
    /// Get a specific transaction by ID
    func get(_ txid: String) -> PendingTransaction? {
        transactions.first { $0.id == txid }
    }
    
    /// Get all pending transactions
    func getPending() -> [PendingTransaction] {
        transactions.filter { $0.status == .pending }
    }
    
    /// Get all transactions (including recently confirmed)
    func getAll() -> [PendingTransaction] {
        transactions
    }
    
    /// Clear confirmed transactions older than 1 hour
    func pruneOldConfirmed() async {
        let oneHourAgo = Date().addingTimeInterval(-3600)
        transactions.removeAll { tx in
            tx.status == .confirmed && tx.timestamp < oneHourAgo
        }
        await saveToStorage()
    }
    
    /// Mark a transaction as failed
    func markFailed(_ txid: String) async {
        if let index = transactions.firstIndex(where: { $0.id == txid }) {
            transactions[index].status = .failed
            await saveToStorage()
        }
    }
    
    /// Remove a transaction from tracking
    func remove(_ txid: String) async {
        transactions.removeAll { $0.id == txid }
        await saveToStorage()
    }
    
    // MARK: - Polling
    
    private func startPollingIfNeeded() {
        guard pollingTask == nil, !getPending().isEmpty else { return }
        
        pollingTask = Task {
            while !Task.isCancelled {
                await checkAllPendingTransactions()
                
                // Stop polling if no more pending
                if getPending().isEmpty {
                    pollingTask = nil
                    break
                }
                
                try? await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
            }
        }
    }
    
    private func checkAllPendingTransactions() async {
        let pending = getPending()
        
        for tx in pending {
            let (confirmations, confirmed) = await checkConfirmations(tx)
            
            if let index = transactions.firstIndex(where: { $0.id == tx.id }) {
                transactions[index].confirmations = confirmations
                
                let threshold = confirmationThresholds[tx.chainId] ?? 6
                if confirmed || confirmations >= threshold {
                    transactions[index].status = .confirmed
                }
            }
        }
        
        await saveToStorage()
    }
    
    // MARK: - Confirmation Checking
    
    private func checkConfirmations(_ tx: PendingTransaction) async -> (Int, Bool) {
        switch tx.chainId {
        case "bitcoin", "bitcoin-testnet":
            return await checkBitcoinConfirmations(tx)
        case "litecoin":
            return await checkLitecoinConfirmations(tx)
        case "ethereum", "ethereum-sepolia":
            return await checkEthereumConfirmations(tx)
        case "bnb":
            return await checkBNBConfirmations(tx)
        case "solana":
            return await checkSolanaConfirmations(tx)
        case "xrp":
            return await checkXRPConfirmations(tx)
        default:
            return (0, false)
        }
    }
    
    private func checkBitcoinConfirmations(_ tx: PendingTransaction) async -> (Int, Bool) {
        let isTestnet = tx.chainId == "bitcoin-testnet"
        let baseURL = isTestnet
            ? "https://blockstream.info/testnet/api"
            : "https://blockstream.info/api"
        
        guard let url = URL(string: "\(baseURL)/tx/\(tx.id)") else {
            return (0, false)
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            if let status = json?["status"] as? [String: Any],
               let confirmed = status["confirmed"] as? Bool {
                if confirmed, let blockHeight = status["block_height"] as? Int {
                    // Get current block height
                    if let tipURL = URL(string: "\(baseURL)/blocks/tip/height"),
                       let (tipData, _) = try? await URLSession.shared.data(from: tipURL),
                       let tipHeight = Int(String(data: tipData, encoding: .utf8) ?? "") {
                        let confirmations = tipHeight - blockHeight + 1
                        return (confirmations, confirmations >= (confirmationThresholds[tx.chainId] ?? 6))
                    }
                }
                return (confirmed ? 1 : 0, false)
            }
        } catch {
            // Transaction not found or error - might still be pending
        }
        
        return (0, false)
    }
    
    private func checkLitecoinConfirmations(_ tx: PendingTransaction) async -> (Int, Bool) {
        guard let url = URL(string: "https://litecoinspace.org/api/tx/\(tx.id)") else {
            return (0, false)
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            if let status = json?["status"] as? [String: Any],
               let confirmed = status["confirmed"] as? Bool {
                if confirmed, let blockHeight = status["block_height"] as? Int {
                    if let tipURL = URL(string: "https://litecoinspace.org/api/blocks/tip/height"),
                       let (tipData, _) = try? await URLSession.shared.data(from: tipURL),
                       let tipHeight = Int(String(data: tipData, encoding: .utf8) ?? "") {
                        let confirmations = tipHeight - blockHeight + 1
                        return (confirmations, confirmations >= 6)
                    }
                }
                return (confirmed ? 1 : 0, false)
            }
        } catch {}
        
        return (0, false)
    }
    
    private func checkEthereumConfirmations(_ tx: PendingTransaction) async -> (Int, Bool) {
        let isTestnet = tx.chainId == "ethereum-sepolia"
        let rpcURL = isTestnet
            ? "https://ethereum-sepolia-rpc.publicnode.com"
            : "https://eth.llamarpc.com"
        
        guard let url = URL(string: rpcURL) else {
            return (0, false)
        }
        
        do {
            // Get transaction receipt
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let receiptPayload: [String: Any] = [
                "jsonrpc": "2.0",
                "method": "eth_getTransactionReceipt",
                "params": [tx.id],
                "id": 1
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: receiptPayload)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            guard let result = json?["result"] as? [String: Any],
                  let blockNumberHex = result["blockNumber"] as? String,
                  let blockNumber = Int(blockNumberHex.dropFirst(2), radix: 16) else {
                return (0, false) // Still pending or not found
            }
            
            // Get current block number
            let blockPayload: [String: Any] = [
                "jsonrpc": "2.0",
                "method": "eth_blockNumber",
                "params": [],
                "id": 2
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: blockPayload)
            
            let (blockData, _) = try await URLSession.shared.data(for: request)
            let blockJson = try JSONSerialization.jsonObject(with: blockData) as? [String: Any]
            
            if let currentBlockHex = blockJson?["result"] as? String,
               let currentBlock = Int(currentBlockHex.dropFirst(2), radix: 16) {
                let confirmations = currentBlock - blockNumber + 1
                let threshold = confirmationThresholds[tx.chainId] ?? 12
                return (confirmations, confirmations >= threshold)
            }
        } catch {}
        
        return (0, false)
    }
    
    private func checkBNBConfirmations(_ tx: PendingTransaction) async -> (Int, Bool) {
        guard let url = URL(string: "https://bsc-dataseed.binance.org/") else {
            return (0, false)
        }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let receiptPayload: [String: Any] = [
                "jsonrpc": "2.0",
                "method": "eth_getTransactionReceipt",
                "params": [tx.id],
                "id": 1
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: receiptPayload)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            guard let result = json?["result"] as? [String: Any],
                  let blockNumberHex = result["blockNumber"] as? String,
                  let blockNumber = Int(blockNumberHex.dropFirst(2), radix: 16) else {
                return (0, false)
            }
            
            let blockPayload: [String: Any] = [
                "jsonrpc": "2.0",
                "method": "eth_blockNumber",
                "params": [],
                "id": 2
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: blockPayload)
            
            let (blockData, _) = try await URLSession.shared.data(for: request)
            let blockJson = try JSONSerialization.jsonObject(with: blockData) as? [String: Any]
            
            if let currentBlockHex = blockJson?["result"] as? String,
               let currentBlock = Int(currentBlockHex.dropFirst(2), radix: 16) {
                let confirmations = currentBlock - blockNumber + 1
                return (confirmations, confirmations >= 15)
            }
        } catch {}
        
        return (0, false)
    }
    
    private func checkSolanaConfirmations(_ tx: PendingTransaction) async -> (Int, Bool) {
        guard let url = URL(string: "https://api.mainnet-beta.solana.com") else {
            return (0, false)
        }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let payload: [String: Any] = [
                "jsonrpc": "2.0",
                "method": "getSignatureStatuses",
                "params": [[tx.id], ["searchTransactionHistory": true]],
                "id": 1
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            if let result = json?["result"] as? [String: Any],
               let value = result["value"] as? [[String: Any]?],
               let first = value.first,
               let status = first {
                
                if let confirmationStatus = status["confirmationStatus"] as? String {
                    if confirmationStatus == "finalized" {
                        return (32, true) // Solana finalized = fully confirmed
                    } else if confirmationStatus == "confirmed" {
                        return (1, true) // Single confirmation is usually enough for Solana
                    }
                }
                
                if let confirmations = status["confirmations"] as? Int {
                    return (confirmations, confirmations >= 1)
                }
            }
        } catch {}
        
        return (0, false)
    }
    
    private func checkXRPConfirmations(_ tx: PendingTransaction) async -> (Int, Bool) {
        guard let url = URL(string: "https://s1.ripple.com:51234") else {
            return (0, false)
        }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let payload: [String: Any] = [
                "method": "tx",
                "params": [["transaction": tx.id, "binary": false]]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            if let result = json?["result"] as? [String: Any],
               let validated = result["validated"] as? Bool {
                return (validated ? 1 : 0, validated)
            }
        } catch {}
        
        return (0, false)
    }
    
    // MARK: - Explorer URLs
    
    private func explorerURL(for chainId: String, txid: String) -> URL? {
        let urlString: String
        
        switch chainId {
        case "bitcoin":
            urlString = "https://blockstream.info/tx/\(txid)"
        case "bitcoin-testnet":
            urlString = "https://blockstream.info/testnet/tx/\(txid)"
        case "litecoin":
            urlString = "https://litecoinspace.org/tx/\(txid)"
        case "ethereum":
            urlString = "https://etherscan.io/tx/\(txid)"
        case "ethereum-sepolia":
            urlString = "https://sepolia.etherscan.io/tx/\(txid)"
        case "bnb":
            urlString = "https://bscscan.com/tx/\(txid)"
        case "solana":
            urlString = "https://explorer.solana.com/tx/\(txid)"
        case "xrp":
            urlString = "https://xrpscan.com/tx/\(txid)"
        default:
            return nil
        }
        
        return URL(string: urlString)
    }
    
    // MARK: - Storage
    
    private func loadFromStorage() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([PendingTransaction].self, from: data) {
            transactions = decoded
            startPollingIfNeeded()
        }
    }
    
    private func saveToStorage() async {
        if let encoded = try? JSONEncoder().encode(transactions) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
}
