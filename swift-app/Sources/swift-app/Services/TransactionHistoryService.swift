import Foundation

// MARK: - Transaction History Service

/// Centralized service for fetching transaction history across all chains
/// with caching, rate limiting, and proper error handling
@MainActor
final class TransactionHistoryService: ObservableObject {
    static let shared = TransactionHistoryService()
    
    // MARK: - Published State
    
    @Published var entries: [TransactionEntry] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var lastUpdated: Date?
    
    // MARK: - Cache
    
    private var cachedEntries: [String: [TransactionEntry]] = [:] // chainId -> entries
    private var lastFetchTime: [String: Date] = [:]
    private let cacheDuration: TimeInterval = 120 // 2 minutes
    
    // MARK: - API Keys (optional)
    
    var etherscanAPIKey: String?
    var bscscanAPIKey: String?
    
    private init() {
        loadFromDisk()
    }
    
    // MARK: - Public API
    
    /// Fetch history for all provided addresses
    func fetchAllHistory(targets: [HistoryTarget], force: Bool = false) async {
        isLoading = true
        error = nil
        
        var allEntries: [TransactionEntry] = []
        var errorMessages: [String] = []
        
        for target in targets {
            // Check cache unless forced
            if !force, let cached = cachedEntries[target.chainId],
               let lastFetch = lastFetchTime[target.chainId],
               Date().timeIntervalSince(lastFetch) < cacheDuration {
                allEntries.append(contentsOf: cached)
                continue
            }
            
            do {
                let entries = try await fetchHistory(for: target)
                cachedEntries[target.chainId] = entries
                lastFetchTime[target.chainId] = Date()
                allEntries.append(contentsOf: entries)
            } catch {
                // Don't fail entirely, just note the error
                errorMessages.append("\(target.displayName): \(error.localizedDescription)")
            }
            
            // Small delay between chains to avoid rate limits
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        }
        
        // Sort by timestamp descending
        allEntries.sort { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
        
        entries = allEntries
        isLoading = false
        lastUpdated = Date()
        
        if !errorMessages.isEmpty && allEntries.isEmpty {
            error = errorMessages.first
        }
        
        saveToDisk()
    }
    
    /// Fetch history for a single chain
    func fetchHistory(for target: HistoryTarget) async throws -> [TransactionEntry] {
        switch target.chainId {
        case "bitcoin", "bitcoin-testnet":
            return try await fetchBitcoinHistory(target: target)
        case "litecoin":
            return try await fetchLitecoinHistory(target: target)
        case "ethereum", "ethereum-sepolia":
            return try await fetchEthereumHistory(target: target)
        case "bnb":
            return try await fetchBNBHistory(target: target)
        case "solana":
            return try await fetchSolanaHistory(target: target)
        case "xrp":
            return try await fetchXRPHistory(target: target)
        default:
            return []
        }
    }
    
    // MARK: - Bitcoin/Litecoin (Blockstream/Blockcypher)
    
    private func fetchBitcoinHistory(target: HistoryTarget) async throws -> [TransactionEntry] {
        let baseURL: String
        if target.chainId == "bitcoin-testnet" {
            baseURL = "https://blockstream.info/testnet/api/address/\(target.address)/txs"
        } else {
            baseURL = "https://blockstream.info/api/address/\(target.address)/txs"
        }
        
        guard let url = URL(string: baseURL) else {
            throw HistoryError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HistoryError.invalidResponse
        }
        
        if httpResponse.statusCode == 429 {
            throw HistoryError.rateLimited
        }
        
        guard httpResponse.statusCode == 200 else {
            throw HistoryError.httpError(httpResponse.statusCode)
        }
        
        let txs = try JSONDecoder().decode([BlockstreamTx].self, from: data)
        
        return txs.prefix(50).map { tx -> TransactionEntry in
            // Calculate net amount for this address
            var inputSum: Int64 = 0
            var outputSum: Int64 = 0
            
            for vin in tx.vin {
                if vin.prevout?.scriptpubkey_address == target.address {
                    inputSum += Int64(vin.prevout?.value ?? 0)
                }
            }
            
            for vout in tx.vout {
                if vout.scriptpubkey_address == target.address {
                    outputSum += Int64(vout.value)
                }
            }
            
            let netSats = outputSum - inputSum
            let isReceive = netSats > 0
            let amountBTC = Double(abs(netSats)) / 100_000_000.0
            
            let timestamp: Date?
            if let blockTime = tx.status.block_time {
                timestamp = Date(timeIntervalSince1970: TimeInterval(blockTime))
            } else {
                timestamp = nil
            }
            
            let confirmations = tx.status.confirmed ? (tx.status.block_height.map { currentHeight(for: target.chainId) - $0 + 1 } ?? 1) : 0
            
            // Calculate fee
            let totalIn = tx.vin.compactMap { $0.prevout?.value }.reduce(0, +)
            let totalOut = tx.vout.map { $0.value }.reduce(0, +)
            let feeSats = totalIn - totalOut
            let feeBTC = feeSats > 0 ? Double(feeSats) / 100_000_000.0 : nil
            
            return TransactionEntry(
                id: "\(target.chainId)-\(tx.txid)",
                chainId: target.chainId,
                txHash: tx.txid,
                type: isReceive ? .receive : .send,
                amount: amountBTC,
                symbol: target.symbol,
                timestamp: timestamp,
                status: tx.status.confirmed ? .confirmed : .pending,
                confirmations: confirmations,
                fee: feeBTC,
                feeSymbol: target.symbol,
                blockNumber: tx.status.block_height
            )
        }
    }
    
    private func fetchLitecoinHistory(target: HistoryTarget) async throws -> [TransactionEntry] {
        // Use Blockchair API for Litecoin
        let urlString = "https://api.blockchair.com/litecoin/dashboards/address/\(target.address)?transaction_details=true&limit=50"
        
        guard let url = URL(string: urlString) else {
            throw HistoryError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw HistoryError.invalidResponse
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let addressData = dataDict[target.address] as? [String: Any],
              let transactions = addressData["transactions"] as? [[String: Any]] else {
            return []
        }
        
        return transactions.prefix(50).compactMap { tx -> TransactionEntry? in
            guard let hash = tx["hash"] as? String,
                  let balanceChange = tx["balance_change"] as? Int else {
                return nil
            }
            
            let isReceive = balanceChange > 0
            let amountLTC = Double(abs(balanceChange)) / 100_000_000.0
            
            var timestamp: Date? = nil
            if let timeString = tx["time"] as? String {
                let formatter = ISO8601DateFormatter()
                timestamp = formatter.date(from: timeString)
            }
            
            let blockId = tx["block_id"] as? Int
            let confirmed = blockId != nil && blockId! > 0
            
            return TransactionEntry(
                id: "\(target.chainId)-\(hash)",
                chainId: target.chainId,
                txHash: hash,
                type: isReceive ? .receive : .send,
                amount: amountLTC,
                symbol: target.symbol,
                timestamp: timestamp,
                status: confirmed ? .confirmed : .pending,
                confirmations: nil,
                fee: nil,
                feeSymbol: target.symbol,
                blockNumber: blockId
            )
        }
    }
    
    // MARK: - Ethereum/BNB (Etherscan/BSCScan)
    
    private func fetchEthereumHistory(target: HistoryTarget) async throws -> [TransactionEntry] {
        let baseURL: String
        let apiKey = etherscanAPIKey ?? ""
        
        if target.chainId == "ethereum-sepolia" {
            baseURL = "https://api-sepolia.etherscan.io/api"
        } else {
            baseURL = "https://api.etherscan.io/api"
        }
        
        var urlString = "\(baseURL)?module=account&action=txlist&address=\(target.address)&startblock=0&endblock=99999999&sort=desc"
        if !apiKey.isEmpty {
            urlString += "&apikey=\(apiKey)"
        }
        
        guard let url = URL(string: urlString) else {
            throw HistoryError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        // Parse response - handle both array and error string responses
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HistoryError.invalidResponse
        }
        
        // Check for error response
        if let message = json["message"] as? String, message != "OK" {
            if message.contains("rate") || message.contains("limit") {
                throw HistoryError.rateLimited
            }
            // Empty result is okay
            if json["result"] is String {
                return []
            }
        }
        
        guard let results = json["result"] as? [[String: Any]] else {
            return []
        }
        
        return results.prefix(50).compactMap { tx -> TransactionEntry? in
            guard let hash = tx["hash"] as? String,
                  let toAddress = tx["to"] as? String,
                  let valueString = tx["value"] as? String,
                  let timestampString = tx["timeStamp"] as? String else {
                return nil
            }
            
            let isReceive = toAddress.lowercased() == target.address.lowercased()
            
            // Convert wei to ETH
            let weiValue = Decimal(string: valueString) ?? 0
            let ethValue = weiValue / Decimal(string: "1000000000000000000")!
            let amount = NSDecimalNumber(decimal: ethValue).doubleValue
            
            let timestamp = UInt64(timestampString).map { Date(timeIntervalSince1970: TimeInterval($0)) }
            
            let confirmations = (tx["confirmations"] as? String).flatMap { Int($0) }
            let status: TransactionStatus = (confirmations ?? 0) > 0 ? .confirmed : .pending
            
            // Calculate fee
            var fee: Double? = nil
            if let gasUsed = tx["gasUsed"] as? String,
               let gasPrice = tx["gasPrice"] as? String,
               let gasUsedDecimal = Decimal(string: gasUsed),
               let gasPriceDecimal = Decimal(string: gasPrice) {
                let feeWei = gasUsedDecimal * gasPriceDecimal
                let feeEth = feeWei / Decimal(string: "1000000000000000000")!
                fee = NSDecimalNumber(decimal: feeEth).doubleValue
            }
            
            let blockNumber = (tx["blockNumber"] as? String).flatMap { Int($0) }
            
            return TransactionEntry(
                id: "\(target.chainId)-\(hash)",
                chainId: target.chainId,
                txHash: hash,
                type: isReceive ? .receive : .send,
                amount: amount,
                symbol: target.symbol,
                timestamp: timestamp,
                status: status,
                confirmations: confirmations,
                fee: fee,
                feeSymbol: target.symbol,
                blockNumber: blockNumber
            )
        }
    }
    
    private func fetchBNBHistory(target: HistoryTarget) async throws -> [TransactionEntry] {
        let apiKey = bscscanAPIKey ?? ""
        var urlString = "https://api.bscscan.com/api?module=account&action=txlist&address=\(target.address)&startblock=0&endblock=99999999&sort=desc"
        if !apiKey.isEmpty {
            urlString += "&apikey=\(apiKey)"
        }
        
        guard let url = URL(string: urlString) else {
            throw HistoryError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["result"] as? [[String: Any]] else {
            return []
        }
        
        return results.prefix(50).compactMap { tx -> TransactionEntry? in
            guard let hash = tx["hash"] as? String,
                  let toAddress = tx["to"] as? String,
                  let valueString = tx["value"] as? String,
                  let timestampString = tx["timeStamp"] as? String else {
                return nil
            }
            
            let isReceive = toAddress.lowercased() == target.address.lowercased()
            
            let weiValue = Decimal(string: valueString) ?? 0
            let bnbValue = weiValue / Decimal(string: "1000000000000000000")!
            let amount = NSDecimalNumber(decimal: bnbValue).doubleValue
            
            let timestamp = UInt64(timestampString).map { Date(timeIntervalSince1970: TimeInterval($0)) }
            let confirmations = (tx["confirmations"] as? String).flatMap { Int($0) }
            let status: TransactionStatus = (confirmations ?? 0) > 0 ? .confirmed : .pending
            
            var fee: Double? = nil
            if let gasUsed = tx["gasUsed"] as? String,
               let gasPrice = tx["gasPrice"] as? String,
               let gasUsedDecimal = Decimal(string: gasUsed),
               let gasPriceDecimal = Decimal(string: gasPrice) {
                let feeWei = gasUsedDecimal * gasPriceDecimal
                let feeBnb = feeWei / Decimal(string: "1000000000000000000")!
                fee = NSDecimalNumber(decimal: feeBnb).doubleValue
            }
            
            return TransactionEntry(
                id: "\(target.chainId)-\(hash)",
                chainId: target.chainId,
                txHash: hash,
                type: isReceive ? .receive : .send,
                amount: amount,
                symbol: target.symbol,
                timestamp: timestamp,
                status: status,
                confirmations: confirmations,
                fee: fee,
                feeSymbol: target.symbol,
                blockNumber: (tx["blockNumber"] as? String).flatMap { Int($0) }
            )
        }
    }
    
    // MARK: - Solana
    
    private func fetchSolanaHistory(target: HistoryTarget) async throws -> [TransactionEntry] {
        guard let url = URL(string: "https://api.mainnet-beta.solana.com") else {
            throw HistoryError.invalidURL
        }
        
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getSignaturesForAddress",
            "params": [target.address, ["limit": 50]]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["result"] as? [[String: Any]] else {
            return []
        }
        
        return results.compactMap { sig -> TransactionEntry? in
            guard let signature = sig["signature"] as? String else { return nil }
            
            let blockTime = sig["blockTime"] as? Int
            let timestamp = blockTime.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            
            let confirmationStatus = sig["confirmationStatus"] as? String
            let hasError = sig["err"] != nil
            
            let status: TransactionStatus
            if hasError {
                status = .failed
            } else if confirmationStatus == "finalized" {
                status = .confirmed
            } else {
                status = .pending
            }
            
            return TransactionEntry(
                id: "\(target.chainId)-\(signature)",
                chainId: target.chainId,
                txHash: signature,
                type: .unknown, // Solana needs tx detail fetch for direction
                amount: nil, // Would need getTransaction RPC call
                symbol: target.symbol,
                timestamp: timestamp,
                status: status,
                confirmations: nil,
                fee: nil,
                feeSymbol: "SOL",
                blockNumber: nil
            )
        }
    }
    
    // MARK: - XRP
    
    private func fetchXRPHistory(target: HistoryTarget) async throws -> [TransactionEntry] {
        // Try XRPScan API
        let urlString = "https://api.xrpscan.com/api/v1/account/\(target.address)/transactions?limit=50"
        
        guard let url = URL(string: urlString) else {
            throw HistoryError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HistoryError.invalidResponse
        }
        
        if httpResponse.statusCode == 403 || httpResponse.statusCode == 429 {
            throw HistoryError.rateLimited
        }
        
        guard httpResponse.statusCode == 200 else {
            throw HistoryError.httpError(httpResponse.statusCode)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let transactions = json["transactions"] as? [[String: Any]] else {
            // Try parsing as array directly
            if let txArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return parseXRPTransactions(txArray, target: target)
            }
            return []
        }
        
        return parseXRPTransactions(transactions, target: target)
    }
    
    private func parseXRPTransactions(_ transactions: [[String: Any]], target: HistoryTarget) -> [TransactionEntry] {
        return transactions.prefix(50).compactMap { tx -> TransactionEntry? in
            guard let hash = tx["hash"] as? String else { return nil }
            
            let isReceive: Bool
            if let dest = tx["Destination"] as? String {
                isReceive = dest == target.address
            } else {
                isReceive = false
            }
            
            var amount: Double? = nil
            if let amountObj = tx["Amount"] as? [String: Any],
               let value = amountObj["value"] as? String {
                amount = Double(value)
            } else if let drops = tx["Amount"] as? String, let dropsInt = Int64(drops) {
                amount = Double(dropsInt) / 1_000_000.0
            }
            
            var timestamp: Date? = nil
            if let closeTime = tx["date"] as? Int {
                // XRP epoch starts at Jan 1, 2000
                timestamp = Date(timeIntervalSince1970: TimeInterval(closeTime + 946684800))
            }
            
            let validated = tx["validated"] as? Bool ?? false
            
            var fee: Double? = nil
            if let feeDrops = tx["Fee"] as? String, let feeInt = Int64(feeDrops) {
                fee = Double(feeInt) / 1_000_000.0
            }
            
            return TransactionEntry(
                id: "\(target.chainId)-\(hash)",
                chainId: target.chainId,
                txHash: hash,
                type: isReceive ? .receive : .send,
                amount: amount,
                symbol: target.symbol,
                timestamp: timestamp,
                status: validated ? .confirmed : .pending,
                confirmations: nil,
                fee: fee,
                feeSymbol: "XRP",
                blockNumber: tx["ledger_index"] as? Int
            )
        }
    }
    
    // MARK: - Helpers
    
    private func currentHeight(for chainId: String) -> Int {
        // Approximate current block heights (updated periodically)
        switch chainId {
        case "bitcoin": return 870000
        case "bitcoin-testnet": return 2900000
        case "litecoin": return 2700000
        default: return 0
        }
    }
    
    // MARK: - Persistence
    
    private var cacheFileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("transaction_history_cache.json")
    }
    
    private func saveToDisk() {
        guard let url = cacheFileURL else { return }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        
        if let data = try? encoder.encode(entries) {
            try? data.write(to: url)
        }
    }
    
    private func loadFromDisk() {
        guard let url = cacheFileURL,
              let data = try? Data(contentsOf: url) else { return }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        
        if let cached = try? decoder.decode([TransactionEntry].self, from: data) {
            entries = cached
        }
    }
    
    // MARK: - Conversion to HawalaTransactionEntry
    
    /// Convert internal TransactionEntry to HawalaTransactionEntry for UI display
    var hawalaEntries: [HawalaTransactionEntry] {
        entries.map { $0.toHawalaEntry() }
    }
    
    /// Fetch and return as HawalaTransactionEntry array
    func fetchAllHistoryAsHawala(targets: [HistoryTarget], force: Bool = false) async -> [HawalaTransactionEntry] {
        await fetchAllHistory(targets: targets, force: force)
        return hawalaEntries
    }
}

// MARK: - TransactionEntry -> HawalaTransactionEntry Conversion

extension TransactionEntry {
    /// Convert to HawalaTransactionEntry for UI display
    func toHawalaEntry() -> HawalaTransactionEntry {
        let typeString: String
        switch type {
        case .send: typeString = "Send"
        case .receive: typeString = "Receive"
        case .swap: typeString = "Swap"
        case .stake: typeString = "Stake"
        case .unstake: typeString = "Unstake"
        case .unknown: typeString = "Transaction"
        }
        
        let statusString: String
        switch status {
        case .confirmed: statusString = "Confirmed"
        case .pending: statusString = "Pending"
        case .failed: statusString = "Failed"
        }
        
        // Format asset name from chainId
        let assetName: String
        switch chainId {
        case "bitcoin", "bitcoin-testnet": assetName = "Bitcoin"
        case "litecoin": assetName = "Litecoin"
        case "ethereum", "ethereum-sepolia": assetName = "Ethereum"
        case "bnb": assetName = "BNB"
        case "solana": assetName = "Solana"
        case "xrp": assetName = "XRP"
        default: assetName = symbol.uppercased()
        }
        
        return HawalaTransactionEntry(
            id: id,
            type: typeString,
            asset: assetName,
            amountDisplay: formattedAmount,
            status: statusString,
            timestamp: formattedTimestamp,
            sortTimestamp: timestamp?.timeIntervalSince1970,
            txHash: txHash,
            chainId: chainId,
            confirmations: confirmations,
            fee: formattedFee,
            blockNumber: blockNumber,
            counterparty: nil
        )
    }
}

// MARK: - Models

struct HistoryTarget {
    let chainId: String
    let address: String
    let displayName: String
    let symbol: String
}

enum TransactionType: String, Codable {
    case send
    case receive
    case swap
    case stake
    case unstake
    case unknown
}

enum TransactionStatus: String, Codable {
    case pending
    case confirmed
    case failed
}

struct TransactionEntry: Identifiable, Codable, Equatable {
    let id: String
    let chainId: String
    let txHash: String
    let type: TransactionType
    let amount: Double?
    let symbol: String
    let timestamp: Date?
    let status: TransactionStatus
    let confirmations: Int?
    let fee: Double?
    let feeSymbol: String?
    let blockNumber: Int?
    
    var formattedAmount: String {
        guard let amount = amount else { return "View details" }
        let prefix = type == .receive ? "+" : (type == .send ? "-" : "")
        return "\(prefix)\(String(format: "%.8f", amount)) \(symbol)"
    }
    
    var formattedFee: String? {
        guard let fee = fee, let symbol = feeSymbol else { return nil }
        return String(format: "%.8f %@", fee, symbol)
    }
    
    var formattedTimestamp: String {
        guard let timestamp = timestamp else { return "Pending" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    var explorerURL: URL? {
        switch chainId {
        case "bitcoin":
            return URL(string: "https://mempool.space/tx/\(txHash)")
        case "bitcoin-testnet":
            return URL(string: "https://mempool.space/testnet/tx/\(txHash)")
        case "litecoin":
            return URL(string: "https://blockchair.com/litecoin/transaction/\(txHash)")
        case "ethereum":
            return URL(string: "https://etherscan.io/tx/\(txHash)")
        case "ethereum-sepolia":
            return URL(string: "https://sepolia.etherscan.io/tx/\(txHash)")
        case "bnb":
            return URL(string: "https://bscscan.com/tx/\(txHash)")
        case "solana":
            return URL(string: "https://solscan.io/tx/\(txHash)")
        case "xrp":
            return URL(string: "https://xrpscan.com/tx/\(txHash)")
        default:
            return nil
        }
    }
}

// MARK: - Errors

enum HistoryError: LocalizedError {
    case invalidURL
    case invalidResponse
    case rateLimited
    case httpError(Int)
    case parseError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .invalidResponse: return "Invalid response from server"
        case .rateLimited: return "Rate limited - try again later"
        case .httpError(let code): return "HTTP error: \(code)"
        case .parseError: return "Failed to parse response"
        }
    }
}

// MARK: - Blockstream Models

private struct BlockstreamTx: Decodable {
    let txid: String
    let vin: [BlockstreamVin]
    let vout: [BlockstreamVout]
    let status: BlockstreamStatus
}

private struct BlockstreamVin: Decodable {
    let prevout: BlockstreamPrevout?
}

private struct BlockstreamPrevout: Decodable {
    let scriptpubkey_address: String?
    let value: Int?
}

private struct BlockstreamVout: Decodable {
    let scriptpubkey_address: String?
    let value: Int
}

private struct BlockstreamStatus: Decodable {
    let confirmed: Bool
    let block_height: Int?
    let block_time: Int?
}
