import Foundation
import GRDB

// MARK: - Sync Engine

/// Coordinates blockchain data synchronization across all chains
/// Implements incremental sync to minimize API calls and improve performance
@MainActor
final class SyncEngine: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = SyncEngine()
    
    // MARK: - Published State
    
    @Published private(set) var isSyncing = false
    @Published private(set) var currentChain: String?
    @Published private(set) var progress: Double = 0
    @Published private(set) var lastError: String?
    @Published private(set) var lastSyncTime: Date?
    
    // MARK: - Properties
    
    private var syncTask: Task<Void, Never>?
    private let transactionStore = TransactionStore.shared
    private let utxoStore = UTXOStore.shared
    private let syncStateStore = SyncStateStore.shared
    private let balanceCacheStore = BalanceCacheStore.shared
    
    // Supported chain IDs
    private let supportedChains = ["bitcoin", "bitcoin-testnet", "ethereum", "ethereum-sepolia", "litecoin", "solana", "xrp"]
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public API
    
    /// Sync all chains for a wallet
    func syncAll(walletId: String, addresses: [SyncAddress], force: Bool = false) async {
        guard !isSyncing else { return }
        
        isSyncing = true
        lastError = nil
        progress = 0
        
        defer {
            isSyncing = false
            currentChain = nil
            lastSyncTime = Date()
        }
        
        let totalChains = Double(addresses.count)
        var completedChains = 0.0
        
        for address in addresses {
            currentChain = address.chainId
            
            do {
                // Check if we need to sync (unless forced)
                if !force {
                    let isStale = try await syncStateStore.get(walletId: walletId, chainId: address.chainId)
                        .map { Date().timeIntervalSince($0.lastSyncedAt ?? .distantPast) > 300 } ?? true
                    
                    if !isStale {
                        completedChains += 1
                        progress = completedChains / totalChains
                        continue
                    }
                }
                
                // Mark as syncing
                _ = try await syncStateStore.getOrCreate(walletId: walletId, chainId: address.chainId)
                try await syncStateStore.markSyncing(walletId: walletId, chainId: address.chainId)
                
                // Perform chain-specific sync
                try await syncChain(walletId: walletId, address: address)
                
            } catch {
                lastError = "[\(address.chainId)] \(error.localizedDescription)"
                try? await syncStateStore.markError(walletId: walletId, chainId: address.chainId, error: error.localizedDescription)
            }
            
            completedChains += 1
            progress = completedChains / totalChains
            
            // Small delay between chains to avoid rate limits
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }
    
    /// Sync a specific chain
    func syncChain(walletId: String, address: SyncAddress) async throws {
        switch address.chainId {
        case "bitcoin", "bitcoin-testnet":
            try await syncBitcoin(walletId: walletId, address: address)
        case "litecoin":
            try await syncLitecoin(walletId: walletId, address: address)
        case "ethereum", "ethereum-sepolia":
            try await syncEthereum(walletId: walletId, address: address)
        case "solana":
            try await syncSolana(walletId: walletId, address: address)
        case "xrp":
            try await syncXRP(walletId: walletId, address: address)
        default:
            throw SyncError.unsupportedChain(address.chainId)
        }
    }
    
    /// Cancel ongoing sync
    func cancelSync() {
        syncTask?.cancel()
        syncTask = nil
        isSyncing = false
    }
    
    // MARK: - Bitcoin/Litecoin Sync (UTXO-based)
    
    private func syncBitcoin(walletId: String, address: SyncAddress) async throws {
        let isTestnet = address.chainId == "bitcoin-testnet"
        let baseURL = isTestnet ? "https://blockstream.info/testnet/api" : "https://blockstream.info/api"
        
        // Fetch UTXOs
        try await syncUTXOs(
            walletId: walletId,
            chainId: address.chainId,
            address: address.address,
            apiURL: "\(baseURL)/address/\(address.address)/utxo"
        )
        
        // Fetch transactions incrementally
        let lastBlockHeight = try await syncStateStore.lastBlockHeight(walletId: walletId, chainId: address.chainId)
        
        try await syncTransactionsFromBlockstream(
            walletId: walletId,
            chainId: address.chainId,
            address: address.address,
            baseURL: baseURL,
            sinceBlock: lastBlockHeight
        )
    }
    
    private func syncLitecoin(walletId: String, address: SyncAddress) async throws {
        // Use Blockcypher for Litecoin
        let baseURL = "https://api.blockcypher.com/v1/ltc/main"
        
        // Fetch UTXOs from Blockcypher
        try await syncUTXOsFromBlockcypher(
            walletId: walletId,
            chainId: address.chainId,
            address: address.address,
            baseURL: baseURL
        )
        
        // Fetch transactions
        let lastBlockHeight = try await syncStateStore.lastBlockHeight(walletId: walletId, chainId: address.chainId)
        
        try await syncTransactionsFromBlockcypher(
            walletId: walletId,
            chainId: address.chainId,
            address: address.address,
            baseURL: baseURL,
            sinceBlock: lastBlockHeight
        )
    }
    
    // MARK: - Ethereum Sync
    
    private func syncEthereum(walletId: String, address: SyncAddress) async throws {
        let isTestnet = address.chainId == "ethereum-sepolia"
        let apiKey = "" // Use Alchemy instead for Ethereum
        let baseURL = isTestnet 
            ? "https://api-sepolia.etherscan.io/api"
            : "https://api.etherscan.io/api"
        
        let lastBlockHeight = try await syncStateStore.lastBlockHeight(walletId: walletId, chainId: address.chainId)
        
        // Fetch normal transactions
        let txURL = "\(baseURL)?module=account&action=txlist&address=\(address.address)&startblock=\(lastBlockHeight)&sort=desc&apikey=\(apiKey)"
        
        guard let url = URL(string: txURL) else {
            throw SyncError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SyncError.httpError
        }
        
        let ethResponse = try JSONDecoder().decode(SyncEtherscanTxListResponse.self, from: data)
        
        guard ethResponse.status == "1" else {
            // No transactions is okay, just means no new activity
            if ethResponse.message == "No transactions found" {
                return
            }
            throw SyncError.apiError(ethResponse.message)
        }
        
        // Convert and save transactions
        var highestBlock = lastBlockHeight
        var transactions: [TransactionRecord] = []
        
        for tx in ethResponse.result {
            let isReceive = tx.to.lowercased() == address.address.lowercased()
            let amountEth = (Double(tx.value) ?? 0) / 1e18
            
            let record = TransactionRecord.from(
                walletId: walletId,
                chainId: address.chainId,
                txHash: tx.hash,
                type: isReceive ? .receive : .send,
                fromAddress: tx.from,
                toAddress: tx.to,
                amount: String(format: "%.18f", amountEth),
                fee: calculateEthFee(gasUsed: tx.gasUsed, gasPrice: tx.gasPrice),
                asset: "ETH",
                timestamp: Date(timeIntervalSince1970: Double(tx.timeStamp) ?? 0),
                status: tx.isError == "0" ? .confirmed : .failed
            )
            
            transactions.append(record)
            
            if let blockNum = Int(tx.blockNumber), blockNum > highestBlock {
                highestBlock = blockNum
            }
        }
        
        // Save transactions
        try await transactionStore.saveAll(transactions)
        
        // Update sync state
        try await syncStateStore.updateAfterSync(
            walletId: walletId,
            chainId: address.chainId,
            blockHeight: highestBlock,
            blockHash: nil
        )
    }
    
    // MARK: - Solana Sync
    
    private func syncSolana(walletId: String, address: SyncAddress) async throws {
        // Solana uses signatures, not block heights for pagination
        // For now, fetch recent transactions
        
        let rpcURL = "https://api.mainnet-beta.solana.com"
        
        guard let url = URL(string: rpcURL) else {
            throw SyncError.invalidURL
        }
        
        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getSignaturesForAddress",
            "params": [
                address.address,
                ["limit": 50]
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        let response = try JSONDecoder().decode(SyncSolanaSignaturesResponse.self, from: data)
        
        guard let signatures = response.result else {
            return
        }
        
        // Fetch details for each signature
        var transactions: [TransactionRecord] = []
        
        for sig in signatures.prefix(25) { // Limit to 25 to avoid rate limits
            if let tx = try? await fetchSolanaTransaction(signature: sig.signature, walletId: walletId, chainId: address.chainId, address: address.address) {
                transactions.append(tx)
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
        }
        
        try await transactionStore.saveAll(transactions)
        
        // Update sync state with slot number
        if let lastSlot = signatures.first?.slot {
            try await syncStateStore.updateAfterSync(
                walletId: walletId,
                chainId: address.chainId,
                blockHeight: lastSlot,
                blockHash: nil
            )
        }
    }
    
    // MARK: - XRP Sync
    
    private func syncXRP(walletId: String, address: SyncAddress) async throws {
        let rpcURL = "https://s1.ripple.com:51234"
        
        guard let url = URL(string: rpcURL) else {
            throw SyncError.invalidURL
        }
        
        let lastLedgerIndex = try await syncStateStore.lastBlockHeight(walletId: walletId, chainId: address.chainId)
        
        let requestBody: [String: Any] = [
            "method": "account_tx",
            "params": [[
                "account": address.address,
                "ledger_index_min": lastLedgerIndex > 0 ? lastLedgerIndex : -1,
                "ledger_index_max": -1,
                "limit": 50
            ]]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let txArray = result["transactions"] as? [[String: Any]] else {
            return
        }
        
        var transactions: [TransactionRecord] = []
        var highestLedger = lastLedgerIndex
        
        for txWrapper in txArray {
            guard let tx = txWrapper["tx"] as? [String: Any],
                  let hash = tx["hash"] as? String,
                  let txType = tx["TransactionType"] as? String,
                  txType == "Payment" else {
                continue
            }
            
            let destination = tx["Destination"] as? String ?? ""
            let source = tx["Account"] as? String ?? ""
            let isReceive = destination.lowercased() == address.address.lowercased()
            
            // Amount can be string (drops) or object (token)
            var amountXRP = "0"
            if let amountStr = tx["Amount"] as? String {
                let drops = Double(amountStr) ?? 0
                amountXRP = String(format: "%.6f", drops / 1_000_000)
            }
            
            // Get ledger index
            let ledgerIndex = tx["ledger_index"] as? Int ?? 0
            if ledgerIndex > highestLedger {
                highestLedger = ledgerIndex
            }
            
            // Get timestamp from close_time_iso or date
            var timestamp: Date?
            if let dateStr = tx["date"] as? Int {
                // XRP dates are seconds since Jan 1, 2000
                timestamp = Date(timeIntervalSince1970: TimeInterval(dateStr) + 946684800)
            }
            
            let record = TransactionRecord.from(
                walletId: walletId,
                chainId: address.chainId,
                txHash: hash,
                type: isReceive ? .receive : .send,
                fromAddress: source,
                toAddress: destination,
                amount: amountXRP,
                fee: nil,
                asset: "XRP",
                timestamp: timestamp,
                status: .confirmed
            )
            
            transactions.append(record)
        }
        
        try await transactionStore.saveAll(transactions)
        
        try await syncStateStore.updateAfterSync(
            walletId: walletId,
            chainId: address.chainId,
            blockHeight: highestLedger,
            blockHash: nil
        )
    }
    
    // MARK: - Helper Methods
    
    private func syncUTXOs(walletId: String, chainId: String, address: String, apiURL: String) async throws {
        guard let url = URL(string: apiURL) else {
            throw SyncError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SyncError.httpError
        }
        
        let blockstreamUTXOs = try JSONDecoder().decode([SyncBlockstreamUTXO].self, from: data)
        
        // Convert to UTXORecord
        let utxos = blockstreamUTXOs.map { utxo in
            UTXORecord.from(
                walletId: walletId,
                chainId: chainId,
                txHash: utxo.txid,
                outputIndex: utxo.vout,
                address: address,
                amount: Int64(utxo.value),
                scriptPubKey: "", // Would need separate fetch
                blockHeight: utxo.status.block_height
            )
        }
        
        // Replace all UTXOs for this address
        try await utxoStore.replaceAll(walletId: walletId, chainId: chainId, with: utxos)
    }
    
    private func syncUTXOsFromBlockcypher(walletId: String, chainId: String, address: String, baseURL: String) async throws {
        let apiURL = "\(baseURL)/addrs/\(address)?unspentOnly=true"
        
        guard let url = URL(string: apiURL) else {
            throw SyncError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SyncError.httpError
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let txrefs = json["txrefs"] as? [[String: Any]] else {
            return
        }
        
        let utxos = txrefs.compactMap { ref -> UTXORecord? in
            guard let txHash = ref["tx_hash"] as? String,
                  let outputIndex = ref["tx_output_n"] as? Int,
                  let value = ref["value"] as? Int else {
                return nil
            }
            
            return UTXORecord.from(
                walletId: walletId,
                chainId: chainId,
                txHash: txHash,
                outputIndex: outputIndex,
                address: address,
                amount: Int64(value),
                scriptPubKey: ref["script"] as? String ?? "",
                blockHeight: ref["block_height"] as? Int
            )
        }
        
        try await utxoStore.replaceAll(walletId: walletId, chainId: chainId, with: utxos)
    }
    
    private func syncTransactionsFromBlockstream(walletId: String, chainId: String, address: String, baseURL: String, sinceBlock: Int) async throws {
        let txURL = "\(baseURL)/address/\(address)/txs"
        
        guard let url = URL(string: txURL) else {
            throw SyncError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SyncError.httpError
        }
        
        let txs = try JSONDecoder().decode([SyncBlockstreamTx].self, from: data)
        
        var transactions: [TransactionRecord] = []
        var highestBlock = sinceBlock
        
        for tx in txs {
            // Skip if we've already synced this block
            if let blockHeight = tx.status?.block_height, blockHeight <= sinceBlock {
                continue
            }
            
            // Calculate net amount for this address
            var inputSum: Int64 = 0
            var outputSum: Int64 = 0
            
            for vin in tx.vin ?? [] {
                if vin.prevout?.scriptpubkey_address == address {
                    inputSum += Int64(vin.prevout?.value ?? 0)
                }
            }
            
            for vout in tx.vout ?? [] {
                if vout.scriptpubkey_address == address {
                    outputSum += Int64(vout.value)
                }
            }
            
            let netSats = outputSum - inputSum
            let isReceive = netSats > 0
            let amountBTC = Double(abs(netSats)) / 100_000_000.0
            
            let timestamp: Date?
            if let blockTime = tx.status?.block_time {
                timestamp = Date(timeIntervalSince1970: TimeInterval(blockTime))
            } else {
                timestamp = nil
            }
            
            let record = TransactionRecord.from(
                walletId: walletId,
                chainId: chainId,
                txHash: tx.txid,
                type: isReceive ? .receive : .send,
                fromAddress: nil,
                toAddress: nil,
                amount: String(format: "%.8f", amountBTC),
                fee: tx.fee.map { String(format: "%.8f", Double($0) / 100_000_000.0) },
                asset: chainId == "litecoin" ? "LTC" : "BTC",
                timestamp: timestamp,
                status: tx.status?.confirmed == true ? .confirmed : .pending
            )
            
            transactions.append(record)
            
            if let blockHeight = tx.status?.block_height, blockHeight > highestBlock {
                highestBlock = blockHeight
            }
        }
        
        try await transactionStore.saveAll(transactions)
        
        try await syncStateStore.updateAfterSync(
            walletId: walletId,
            chainId: chainId,
            blockHeight: highestBlock,
            blockHash: nil
        )
    }
    
    private func syncTransactionsFromBlockcypher(walletId: String, chainId: String, address: String, baseURL: String, sinceBlock: Int) async throws {
        let txURL = "\(baseURL)/addrs/\(address)/full?limit=50"
        
        guard let url = URL(string: txURL) else {
            throw SyncError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SyncError.httpError
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let txs = json["txs"] as? [[String: Any]] else {
            return
        }
        
        var transactions: [TransactionRecord] = []
        var highestBlock = sinceBlock
        
        for tx in txs {
            guard let hash = tx["hash"] as? String,
                  let blockHeight = tx["block_height"] as? Int else {
                continue
            }
            
            if blockHeight <= sinceBlock {
                continue
            }
            
            // Calculate amount
            var inputTotal: Int64 = 0
            var outputTotal: Int64 = 0
            
            if let inputs = tx["inputs"] as? [[String: Any]] {
                for input in inputs {
                    if let addrs = input["addresses"] as? [String], addrs.contains(address) {
                        inputTotal += Int64(input["output_value"] as? Int ?? 0)
                    }
                }
            }
            
            if let outputs = tx["outputs"] as? [[String: Any]] {
                for output in outputs {
                    if let addrs = output["addresses"] as? [String], addrs.contains(address) {
                        outputTotal += Int64(output["value"] as? Int ?? 0)
                    }
                }
            }
            
            let netAmount = outputTotal - inputTotal
            let isReceive = netAmount > 0
            
            let timestamp: Date?
            if let confirmed = tx["confirmed"] as? String {
                let formatter = ISO8601DateFormatter()
                timestamp = formatter.date(from: confirmed)
            } else {
                timestamp = nil
            }
            
            let record = TransactionRecord.from(
                walletId: walletId,
                chainId: chainId,
                txHash: hash,
                type: isReceive ? .receive : .send,
                fromAddress: nil,
                toAddress: nil,
                amount: String(format: "%.8f", Double(abs(netAmount)) / 100_000_000.0),
                fee: (tx["fees"] as? Int).map { String(format: "%.8f", Double($0) / 100_000_000.0) },
                asset: "LTC",
                timestamp: timestamp,
                status: .confirmed
            )
            
            transactions.append(record)
            
            if blockHeight > highestBlock {
                highestBlock = blockHeight
            }
        }
        
        try await transactionStore.saveAll(transactions)
        
        try await syncStateStore.updateAfterSync(
            walletId: walletId,
            chainId: chainId,
            blockHeight: highestBlock,
            blockHash: nil
        )
    }
    
    private func fetchSolanaTransaction(signature: String, walletId: String, chainId: String, address: String) async throws -> TransactionRecord? {
        // Simplified - would need full transaction parsing for production
        return TransactionRecord.from(
            walletId: walletId,
            chainId: chainId,
            txHash: signature,
            type: .unknown,
            fromAddress: nil,
            toAddress: nil,
            amount: "0",
            fee: nil,
            asset: "SOL",
            timestamp: nil,
            status: .confirmed
        )
    }
    
    private func calculateEthFee(gasUsed: String, gasPrice: String) -> String? {
        guard let gas = Double(gasUsed), let price = Double(gasPrice) else {
            return nil
        }
        let feeWei = gas * price
        let feeEth = feeWei / 1e18
        return String(format: "%.18f", feeEth)
    }
}

// MARK: - Supporting Types

struct SyncAddress {
    let chainId: String
    let address: String
}

enum SyncError: LocalizedError {
    case unsupportedChain(String)
    case invalidURL
    case httpError
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .unsupportedChain(let chain):
            return "Unsupported chain: \(chain)"
        case .invalidURL:
            return "Invalid API URL"
        case .httpError:
            return "HTTP request failed"
        case .apiError(let message):
            return "API error: \(message)"
        }
    }
}

// MARK: - API Response Types (Sync-specific, prefixed to avoid conflicts)

private struct SyncBlockstreamUTXO: Codable {
    let txid: String
    let vout: Int
    let value: Int
    let status: SyncBlockstreamUTXOStatus
}

private struct SyncBlockstreamUTXOStatus: Codable {
    let confirmed: Bool
    let block_height: Int?
}

private struct SyncBlockstreamTx: Codable {
    let txid: String
    let fee: Int?
    let status: SyncBlockstreamTxStatus?
    let vin: [SyncBlockstreamVin]?
    let vout: [SyncBlockstreamVout]?
}

private struct SyncBlockstreamTxStatus: Codable {
    let confirmed: Bool
    let block_height: Int?
    let block_time: Int?
}

private struct SyncBlockstreamVin: Codable {
    let prevout: SyncBlockstreamPrevout?
}

private struct SyncBlockstreamPrevout: Codable {
    let scriptpubkey_address: String?
    let value: Int?
}

private struct SyncBlockstreamVout: Codable {
    let scriptpubkey_address: String?
    let value: Int
}

private struct SyncEtherscanTxListResponse: Codable {
    let status: String
    let message: String
    let result: [SyncEtherscanTx]
}

private struct SyncEtherscanTx: Codable {
    let hash: String
    let from: String
    let to: String
    let value: String
    let gasUsed: String
    let gasPrice: String
    let timeStamp: String
    let blockNumber: String
    let isError: String
}

private struct SyncSolanaSignaturesResponse: Codable {
    let result: [SyncSolanaSignature]?
}

private struct SyncSolanaSignature: Codable {
    let signature: String
    let slot: Int
}

