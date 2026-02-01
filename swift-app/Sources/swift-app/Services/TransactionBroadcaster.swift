import Foundation
import CryptoKit

// MARK: - Transaction Broadcaster Service

/// Unified service for broadcasting transactions across all supported chains.
/// Handles the final step of sending signed transactions to the network.
@MainActor
final class TransactionBroadcaster: ObservableObject {
    static let shared = TransactionBroadcaster()
    
    @Published var lastBroadcast: BroadcastResult?
    @Published var isBroadcasting = false

    // Cache raw tx data for recently broadcasted transactions.
    // NOTE: This is intentionally in-memory (not persisted) as a first step.
    // If this proves useful, we can persist it to TransactionRecord.rawData.
    private var rawTxCache: [String: Data] = [:] // txid -> raw tx hex (utf8)
    
    private init() {}

    func cacheLastSignedRawTx(txid: String, rawTx: Data) {
        rawTxCache[txid] = rawTx
    }

    func getCachedRawTx(txid: String) -> String? {
        guard let data = rawTxCache[txid],
              let s = String(data: data, encoding: .utf8) else {
            return nil
        }
        return s
    }

    // MARK: - EVM Rebroadcast (best-effort)

    /// Rebroadcast a previously signed EVM raw transaction to a specific RPC.
    /// Useful when a tx becomes "notFound" across all providers (dropped/evicted).
    func rebroadcastRawEVM(rawTxHex: String, rpcURL: String) async throws -> String {
        guard let url = URL(string: rpcURL) else {
            throw BroadcastError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_sendRawTransaction",
            "params": [rawTxHex],
            "id": 1
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        if let result = json?["result"] as? String {
            return result
        }
        if let errorObj = json?["error"] as? [String: Any], let message = errorObj["message"] as? String {
            throw BroadcastError.broadcastFailed(message)
        }
        throw BroadcastError.broadcastFailed("Unknown rebroadcast response")
    }
    
    // MARK: - Broadcast Result
    
    struct BroadcastResult: Identifiable {
        let id = UUID()
        let chainId: String
        let txid: String
        let success: Bool
        let errorMessage: String?
        let timestamp: Date
        let explorerURL: URL?
    }
    
    // MARK: - Bitcoin Broadcast
    
    /// Broadcast a signed Bitcoin transaction
    func broadcastBitcoin(rawTxHex: String, isTestnet: Bool) async throws -> String {
        isBroadcasting = true
        defer { isBroadcasting = false }
        
        let baseURL = isTestnet ? "https://mempool.space/testnet/api" : "https://mempool.space/api"
        
        guard let url = URL(string: "\(baseURL)/tx") else {
            throw BroadcastError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = rawTxHex.data(using: .utf8)
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BroadcastError.invalidResponse
        }
        
        if httpResponse.statusCode == 200 {
            let txid = String(data: data, encoding: .utf8) ?? ""
            
            let explorerBase = isTestnet ? "https://mempool.space/testnet/tx/" : "https://mempool.space/tx/"
            lastBroadcast = BroadcastResult(
                chainId: isTestnet ? "bitcoin-testnet" : "bitcoin",
                txid: txid,
                success: true,
                errorMessage: nil,
                timestamp: Date(),
                explorerURL: URL(string: "\(explorerBase)\(txid)")
            )
            
            return txid
        } else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            lastBroadcast = BroadcastResult(
                chainId: isTestnet ? "bitcoin-testnet" : "bitcoin",
                txid: "",
                success: false,
                errorMessage: errorMsg,
                timestamp: Date(),
                explorerURL: nil
            )
            throw BroadcastError.broadcastFailed(errorMsg)
        }
    }
    
    // MARK: - Litecoin Broadcast
    
    /// Broadcast a signed Litecoin transaction
    func broadcastLitecoin(rawTxHex: String) async throws -> String {
        isBroadcasting = true
        defer { isBroadcasting = false }
        
        // Try Blockchair first
        do {
            let txid = try await broadcastLitecoinViaBlockchair(rawTxHex)
            lastBroadcast = BroadcastResult(
                chainId: "litecoin",
                txid: txid,
                success: true,
                errorMessage: nil,
                timestamp: Date(),
                explorerURL: URL(string: "https://blockchair.com/litecoin/transaction/\(txid)")
            )
            return txid
        } catch {
            // Try Blockcypher as fallback
            let txid = try await broadcastLitecoinViaBlockcypher(rawTxHex)
            lastBroadcast = BroadcastResult(
                chainId: "litecoin",
                txid: txid,
                success: true,
                errorMessage: nil,
                timestamp: Date(),
                explorerURL: URL(string: "https://blockchair.com/litecoin/transaction/\(txid)")
            )
            return txid
        }
    }
    
    private func broadcastLitecoinViaBlockchair(_ rawTxHex: String) async throws -> String {
        guard let url = URL(string: "https://api.blockchair.com/litecoin/push/transaction") else {
            throw BroadcastError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")
        
        let body = ["data": rawTxHex]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BroadcastError.broadcastFailed("Blockchair failed")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let txid = dataDict["transaction_hash"] as? String else {
            throw BroadcastError.invalidResponse
        }
        
        return txid
    }
    
    private func broadcastLitecoinViaBlockcypher(_ rawTxHex: String) async throws -> String {
        guard let url = URL(string: "https://api.blockcypher.com/v1/ltc/main/txs/push") else {
            throw BroadcastError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["tx": rawTxHex]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...201).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw BroadcastError.broadcastFailed(errorMsg)
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let txData = json["tx"] as? [String: Any],
              let txid = txData["hash"] as? String else {
            throw BroadcastError.invalidResponse
        }
        
        return txid
    }
    
    // MARK: - Ethereum Broadcast
    
    /// Broadcast a signed Ethereum transaction
    func broadcastEthereum(rawTxHex: String, isTestnet: Bool) async throws -> String {
        isBroadcasting = true
        defer { isBroadcasting = false }
        
        // Use multiple RPC endpoints for redundancy
        let rpcEndpoints: [String]
        if isTestnet {
            // Sepolia testnet - use reliable public endpoints
            rpcEndpoints = [
                "https://ethereum-sepolia-rpc.publicnode.com",
                "https://sepolia.drpc.org",
                "https://1rpc.io/sepolia"
            ]
        } else {
            rpcEndpoints = [
                "https://eth.llamarpc.com",
                "https://ethereum.publicnode.com",
                "https://rpc.ankr.com/eth"
            ]
        }
        
        var lastError: Error = BroadcastError.allEndpointsFailed
        
        for endpoint in rpcEndpoints {
            do {
                let txid = try await broadcastEthereumViaRPC(rawTxHex, rpcURL: endpoint)

                // Propagation check: confirm at least one *other* endpoint can see the tx.
                // This avoids returning success when a single RPC accepts the tx but doesn't
                // actually gossip it widely (the "secondary node" symptom on explorers).
                let otherEndpoints = rpcEndpoints.filter { $0 != endpoint }
                if !otherEndpoints.isEmpty {
                    let propagated = await verifyEthereumPropagation(txid: txid, rpcEndpoints: otherEndpoints)
                    if !propagated {
                        throw BroadcastError.propagationPending("Broadcast accepted by one RPC but not yet visible on other nodes (propagation pending).")
                    }
                }
                
                let explorerBase = isTestnet ? "https://sepolia.etherscan.io/tx/" : "https://etherscan.io/tx/"
                lastBroadcast = BroadcastResult(
                    chainId: isTestnet ? "ethereum-sepolia" : "ethereum",
                    txid: txid,
                    success: true,
                    errorMessage: nil,
                    timestamp: Date(),
                    explorerURL: URL(string: "\(explorerBase)\(txid)")
                )
                return txid
            } catch {
                lastError = error
                continue
            }
        }
        
        lastBroadcast = BroadcastResult(
            chainId: isTestnet ? "ethereum-sepolia" : "ethereum",
            txid: "",
            success: false,
            errorMessage: lastError.localizedDescription,
            timestamp: Date(),
            explorerURL: nil
        )
        
        throw lastError
    }

    private func verifyEthereumPropagation(txid: String, rpcEndpoints: [String]) async -> Bool {
        // Try a few quick rounds; we want to be fast but reduce false "success".
        // Total worst-case ~2.5s.
        let rounds = 3
        for round in 0..<rounds {
            for endpoint in rpcEndpoints {
                if await isEthereumTxVisible(txid: txid, rpcURL: endpoint) {
                    #if DEBUG
                    print("[ETH Broadcast] Propagation OK via: \(endpoint) (round \(round + 1)/\(rounds))")
                    #endif
                    return true
                }
            }
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s
        }
        #if DEBUG
        print("[ETH Broadcast] Propagation NOT confirmed across RPCs")
        #endif
        return false
    }

    private func isEthereumTxVisible(txid: String, rpcURL: String) async -> Bool {
        guard let url = URL(string: rpcURL) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 2

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getTransactionByHash",
            "params": [txid],
            "id": 1
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return false
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return false
            }

            // If result is a non-null object, the tx is visible to that node.
            if let result = json["result"] {
                if result is NSNull { return false }
                return true
            }
            return false
        } catch {
            return false
        }
    }
    
    private func broadcastEthereumViaRPC(_ rawTxHex: String, rpcURL: String) async throws -> String {
        guard let url = URL(string: rpcURL) else {
            throw BroadcastError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 12
        
        let txWithPrefix = rawTxHex.hasPrefix("0x") ? rawTxHex : "0x\(rawTxHex)"
        
        #if DEBUG
        print("[ETH Broadcast] Sending to RPC: \(rpcURL)")
        #endif
        #if DEBUG
        print("[ETH Broadcast] Raw TX (first 100 chars): \(String(txWithPrefix.prefix(100)))...")
        #endif
        
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_sendRawTransaction",
            "params": [txWithPrefix],
            "id": 1
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            #if DEBUG
            print("[ETH Broadcast] ERROR: Non-HTTP response")
            #endif
            throw BroadcastError.invalidResponse
        }
        
        #if DEBUG
        print("[ETH Broadcast] HTTP Status: \(httpResponse.statusCode)")
        #endif
        
        // Log raw response for debugging
        if let rawResponse = String(data: data, encoding: .utf8) {
            #if DEBUG
            print("[ETH Broadcast] Response: \(rawResponse)")
            #endif
        }
        
        guard httpResponse.statusCode == 200 else {
            throw BroadcastError.invalidResponse
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BroadcastError.invalidResponse
        }
        
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            #if DEBUG
            print("[ETH Broadcast] RPC ERROR: \(message)")
            #endif
            throw BroadcastError.broadcastFailed(message)
        }
        
        guard let txid = json["result"] as? String else {
            #if DEBUG
            print("[ETH Broadcast] ERROR: No txid in response")
            #endif
            throw BroadcastError.invalidResponse
        }
        
        #if DEBUG
        print("[ETH Broadcast] SUCCESS! TxID: \(txid)")
        #endif
        return txid
    }
    
    // MARK: - BNB Smart Chain Broadcast
    
    /// Broadcast a signed BNB Smart Chain transaction
    func broadcastBNB(rawTxHex: String) async throws -> String {
        isBroadcasting = true
        defer { isBroadcasting = false }
        
        let rpcEndpoints = [
            "https://bsc-dataseed.binance.org",
            "https://bsc-dataseed1.defibit.io",
            "https://bsc-dataseed1.ninicoin.io"
        ]
        
        var lastError: Error = BroadcastError.allEndpointsFailed
        
        for endpoint in rpcEndpoints {
            do {
                let txid = try await broadcastEthereumViaRPC(rawTxHex, rpcURL: endpoint)
                lastBroadcast = BroadcastResult(
                    chainId: "bnb",
                    txid: txid,
                    success: true,
                    errorMessage: nil,
                    timestamp: Date(),
                    explorerURL: URL(string: "https://bscscan.com/tx/\(txid)")
                )
                return txid
            } catch {
                lastError = error
                continue
            }
        }
        
        throw lastError
    }
    
    // MARK: - Solana Broadcast
    
    /// Broadcast a signed Solana transaction
    func broadcastSolana(rawTxBase64: String, isDevnet: Bool = false) async throws -> String {
        isBroadcasting = true
        defer { isBroadcasting = false }
        
        let rpcURL = isDevnet
            ? "https://api.devnet.solana.com"
            : "https://api.mainnet-beta.solana.com"
        
        guard let url = URL(string: rpcURL) else {
            throw BroadcastError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "sendTransaction",
            "params": [
                rawTxBase64,
                ["encoding": "base64", "preflightCommitment": "confirmed"]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BroadcastError.invalidResponse
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BroadcastError.invalidResponse
        }
        
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw BroadcastError.broadcastFailed(message)
        }
        
        guard let signature = json["result"] as? String else {
            throw BroadcastError.invalidResponse
        }
        
        let explorerBase = isDevnet ? "https://explorer.solana.com/tx/\(signature)?cluster=devnet" : "https://explorer.solana.com/tx/\(signature)"
        
        lastBroadcast = BroadcastResult(
            chainId: "solana",
            txid: signature,
            success: true,
            errorMessage: nil,
            timestamp: Date(),
            explorerURL: URL(string: explorerBase)
        )
        
        return signature
    }
    
    // MARK: - XRP Broadcast
    
    /// Broadcast a signed XRP transaction
    func broadcastXRP(rawTxHex: String, isTestnet: Bool = false) async throws -> String {
        isBroadcasting = true
        defer { isBroadcasting = false }
        
        let rpcURL = isTestnet
            ? "https://s.altnet.rippletest.net:51234"
            : "https://s1.ripple.com:51234"
            
        guard let url = URL(string: rpcURL) else {
            throw BroadcastError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "method": "submit",
            "params": [
                ["tx_blob": rawTxHex]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BroadcastError.invalidResponse
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any] else {
            throw BroadcastError.invalidResponse
        }
        
        // Check engine_result
        if let engineResult = result["engine_result"] as? String,
           engineResult != "tesSUCCESS" {
            let message = result["engine_result_message"] as? String ?? engineResult
            throw BroadcastError.broadcastFailed(message)
        }
        
        guard let txJson = result["tx_json"] as? [String: Any],
              let hash = txJson["hash"] as? String else {
             // Sometimes it's just in the result root depending on API version
             if let hash = result["tx_json"] as? [String: Any] {
                 if let h = hash["hash"] as? String { return h }
             }
             throw BroadcastError.invalidResponse
        }
        
        let explorerBase = isTestnet ? "https://testnet.xrpl.org/transactions/" : "https://livenet.xrpl.org/transactions/"
        
        lastBroadcast = BroadcastResult(
            chainId: "xrp",
            txid: hash,
            success: true,
            errorMessage: nil,
            timestamp: Date(),
            explorerURL: URL(string: "\(explorerBase)\(hash)")
        )
        
        return hash
    }
    
    // MARK: - Network Helpers
    
    func getEthereumNonce(address: String, isTestnet: Bool) async throws -> UInt64 {
        let rpcURL = isTestnet ? "https://ethereum-sepolia-rpc.publicnode.com" : "https://eth.llamarpc.com"
        guard let url = URL(string: rpcURL) else { throw BroadcastError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Use "pending" to include pending transactions in the count
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getTransactionCount",
            "params": [address, "pending"],
            "id": 1
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? String else {
            throw BroadcastError.invalidResponse
        }
        
        let nonce = UInt64(result.dropFirst(2), radix: 16) ?? 0
        #if DEBUG
        print("[Nonce] ETH \(isTestnet ? "Sepolia" : "Mainnet"): fetched pending nonce = \(nonce)")
        #endif
        return nonce
    }
    
    /// Get nonce for any EVM chain by chainId
    func getEthereumNonceForChain(address: String, chainId: Int) async throws -> UInt64 {
        let rpcURL = getRPCEndpoint(for: chainId)
        guard let url = URL(string: rpcURL) else { throw BroadcastError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Use "pending" to include pending transactions in the count
        // This prevents nonce conflicts when there are unconfirmed transactions
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getTransactionCount",
            "params": [address, "pending"],
            "id": 1
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? String else {
            throw BroadcastError.invalidResponse
        }
        
        let nonce = UInt64(result.dropFirst(2), radix: 16) ?? 0
        #if DEBUG
        print("[Nonce] Chain \(chainId): fetched pending nonce = \(nonce) for \(address.prefix(10))...")
        #endif
        return nonce
    }
    
    /// Broadcast a signed transaction to any EVM chain
    func broadcastEthereumToChain(rawTxHex: String, chainId: Int) async throws -> String {
        isBroadcasting = true
        defer { isBroadcasting = false }
        
        let rpcEndpoints = getRPCEndpoints(for: chainId)
        var lastError: Error = BroadcastError.allEndpointsFailed
        
        for endpoint in rpcEndpoints {
            do {
                let txid = try await broadcastEthereumViaRPC(rawTxHex, rpcURL: endpoint)
                
                let (explorerBase, chainName) = getExplorerInfo(for: chainId)
                lastBroadcast = BroadcastResult(
                    chainId: chainName,
                    txid: txid,
                    success: true,
                    errorMessage: nil,
                    timestamp: Date(),
                    explorerURL: URL(string: "\(explorerBase)\(txid)")
                )
                return txid
            } catch {
                lastError = error
                continue
            }
        }
        
        let (_, chainName) = getExplorerInfo(for: chainId)
        lastBroadcast = BroadcastResult(
            chainId: chainName,
            txid: "",
            success: false,
            errorMessage: lastError.localizedDescription,
            timestamp: Date(),
            explorerURL: nil
        )
        
        throw lastError
    }
    
    /// Get the primary RPC endpoint for a chain
    private func getRPCEndpoint(for chainId: Int) -> String {
        switch chainId {
        case 1: return "https://eth.llamarpc.com"
        case 11155111: return "https://ethereum-sepolia-rpc.publicnode.com"
        case 137: return "https://polygon-rpc.com"
        case 56: return "https://bsc-dataseed.binance.org"
        default: return "https://eth.llamarpc.com"
        }
    }
    
    /// Get multiple RPC endpoints for redundancy
    private func getRPCEndpoints(for chainId: Int) -> [String] {
        switch chainId {
        case 1:
            return ["https://eth.llamarpc.com", "https://ethereum.publicnode.com", "https://rpc.ankr.com/eth"]
        case 11155111:
            // Sepolia testnet - use reliable public endpoints
            return [
                "https://ethereum-sepolia-rpc.publicnode.com",
                "https://sepolia.drpc.org",
                "https://1rpc.io/sepolia"
            ]
        case 137:
            return ["https://polygon-rpc.com", "https://rpc.ankr.com/polygon", "https://polygon.llamarpc.com"]
        case 56:
            return ["https://bsc-dataseed.binance.org", "https://bsc-dataseed1.defibit.io", "https://rpc.ankr.com/bsc"]
        default:
            return ["https://eth.llamarpc.com"]
        }
    }
    
    /// Get explorer info for a chain
    private func getExplorerInfo(for chainId: Int) -> (baseURL: String, chainName: String) {
        switch chainId {
        case 1: return ("https://etherscan.io/tx/", "ethereum")
        case 11155111: return ("https://sepolia.etherscan.io/tx/", "ethereum-sepolia")
        case 137: return ("https://polygonscan.com/tx/", "polygon")
        case 56: return ("https://bscscan.com/tx/", "bnb")
        default: return ("https://etherscan.io/tx/", "ethereum")
        }
    }
    
    func getSolanaBlockhash(isDevnet: Bool) async throws -> String {
        let rpcURL = isDevnet ? "https://api.devnet.solana.com" : "https://api.mainnet-beta.solana.com"
        guard let url = URL(string: rpcURL) else { throw BroadcastError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getLatestBlockhash",
            "params": [["commitment": "finalized"]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let value = result["value"] as? [String: Any],
              let blockhash = value["blockhash"] as? String else {
            throw BroadcastError.invalidResponse
        }
        
        return blockhash
    }
    
    func getXRPSequence(address: String, isTestnet: Bool) async throws -> UInt32 {
        let rpcURL = isTestnet ? "https://s.altnet.rippletest.net:51234" : "https://s1.ripple.com:51234"
        guard let url = URL(string: rpcURL) else { throw BroadcastError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "method": "account_info",
            "params": [
                ["account": address, "ledger_index": "current"]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let accountData = result["account_data"] as? [String: Any],
              let sequence = accountData["Sequence"] as? Int else {
            throw BroadcastError.invalidResponse
        }
        
        return UInt32(sequence)
    }
    
    // MARK: - Transaction Status Tracking
    
    /// Transaction confirmation status
    enum TransactionStatus {
        case pending
        case confirmed(confirmations: Int)
        case failed(reason: String)
        case notFound
    }
    
    /// Check Bitcoin transaction status
    func checkBitcoinStatus(txid: String, isTestnet: Bool) async throws -> TransactionStatus {
        let baseURL = isTestnet ? "https://mempool.space/testnet/api" : "https://mempool.space/api"
        
        guard let url = URL(string: "\(baseURL)/tx/\(txid)") else {
            throw BroadcastError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BroadcastError.invalidResponse
        }
        
        if httpResponse.statusCode == 404 {
            return .notFound
        }
        
        guard httpResponse.statusCode == 200 else {
            throw BroadcastError.invalidResponse
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BroadcastError.invalidResponse
        }
        
        // Check if confirmed (has block_height)
        if let status = json["status"] as? [String: Any] {
            if let confirmed = status["confirmed"] as? Bool, confirmed {
                if let blockHeight = status["block_height"] as? Int {
                    // Get current block height to calculate confirmations
                    let currentHeight = try await getCurrentBitcoinBlockHeight(isTestnet: isTestnet)
                    let confirmations = currentHeight - blockHeight + 1
                    return .confirmed(confirmations: max(1, confirmations))
                }
                return .confirmed(confirmations: 1)
            }
        }
        
        return .pending
    }
    
    /// Get current Bitcoin block height
    private func getCurrentBitcoinBlockHeight(isTestnet: Bool) async throws -> Int {
        let baseURL = isTestnet ? "https://mempool.space/testnet/api" : "https://mempool.space/api"
        
        guard let url = URL(string: "\(baseURL)/blocks/tip/height") else {
            throw BroadcastError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(for: URLRequest(url: url))
        
        guard let heightStr = String(data: data, encoding: .utf8),
              let height = Int(heightStr.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw BroadcastError.invalidResponse
        }
        
        return height
    }
    
    /// Check Ethereum transaction status
    func checkEthereumStatus(txid: String, isTestnet: Bool) async throws -> TransactionStatus {
        // IMPORTANT: Do not rely on a single vendor endpoint here (Alchemy), because
        // pending tx visibility can differ between nodes. Use the same redundancy pool
        // as broadcasting to reduce false "pending forever" states.

        let rpcEndpoints: [String] = isTestnet
            ? [
                "https://ethereum-sepolia-rpc.publicnode.com",
                "https://sepolia.drpc.org",
                "https://1rpc.io/sepolia"
            ]
            : [
                "https://eth.llamarpc.com",
                "https://ethereum.publicnode.com",
                "https://rpc.ankr.com/eth"
            ]

        var lastError: Error = BroadcastError.allEndpointsFailed

        for endpoint in rpcEndpoints {
            do {
                // 1) Receipt check
                if let receipt = try await fetchEthereumReceipt(txid: txid, rpcURL: endpoint) {
                    if let statusHex = receipt["status"] as? String, statusHex != "0x1" {
                        return .failed(reason: "Transaction reverted")
                    }

                    if let blockNumberHex = receipt["blockNumber"] as? String {
                        let currentBlock = try await fetchEthereumBlockNumber(rpcURL: endpoint)
                        let txBlock = Int(blockNumberHex.dropFirst(2), radix: 16) ?? 0
                        let confirmations = currentBlock - txBlock + 1
                        return .confirmed(confirmations: max(1, confirmations))
                    }

                    return .confirmed(confirmations: 1)
                }

                // 2) Receipt missing: determine whether tx is visible in mempool.
                let visible = try await fetchEthereumTxExists(txid: txid, rpcURL: endpoint)
                return visible ? .pending : .notFound
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError
    }
    
    private func fetchEthereumReceipt(txid: String, rpcURL: String) async throws -> [String: Any]? {
        guard let url = URL(string: rpcURL) else { throw BroadcastError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getTransactionReceipt",
            "params": [txid],
            "id": 1
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw BroadcastError.invalidResponse
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BroadcastError.invalidResponse
        }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            throw BroadcastError.broadcastFailed(message)
        }
        if let result = json["result"] as? [String: Any] {
            return result
        }
        return nil
    }

    private func fetchEthereumTxExists(txid: String, rpcURL: String) async throws -> Bool {
        guard let url = URL(string: rpcURL) else { throw BroadcastError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 6

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getTransactionByHash",
            "params": [txid],
            "id": 1
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw BroadcastError.invalidResponse
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BroadcastError.invalidResponse
        }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            throw BroadcastError.broadcastFailed(message)
        }

        if let result = json["result"] {
            return !(result is NSNull)
        }
        return false
    }

    private func fetchEthereumBlockNumber(rpcURL: String) async throws -> Int {
        guard let url = URL(string: rpcURL) else { throw BroadcastError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 6

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_blockNumber",
            "params": [],
            "id": 1
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw BroadcastError.invalidResponse
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultHex = json["result"] as? String,
              let blockNumber = Int(resultHex.dropFirst(2), radix: 16) else {
            throw BroadcastError.invalidResponse
        }
        return blockNumber
    }
    
    /// Check Solana transaction status
    func checkSolanaStatus(signature: String, isDevnet: Bool) async throws -> TransactionStatus {
        let baseURL = isDevnet 
            ? "https://api.devnet.solana.com"
            : "https://api.mainnet-beta.solana.com"
        
        guard let url = URL(string: baseURL) else {
            throw BroadcastError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getSignatureStatuses",
            "params": [[signature], ["searchTransactionHistory": true]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let value = result["value"] as? [Any?] else {
            throw BroadcastError.invalidResponse
        }
        
        guard let statusInfo = value.first as? [String: Any]? else {
            return .notFound
        }
        
        guard let info = statusInfo else {
            return .notFound
        }
        
        // Check for error
        if let err = info["err"] {
            if !(err is NSNull) {
                return .failed(reason: "Transaction failed on-chain")
            }
        }
        
        // Check confirmations
        if let confirmations = info["confirmations"] as? Int {
            if confirmations > 0 {
                return .confirmed(confirmations: confirmations)
            }
        }
        
        // Check confirmation status
        if let status = info["confirmationStatus"] as? String {
            switch status {
            case "finalized":
                return .confirmed(confirmations: 32) // Finalized = max confirmations
            case "confirmed":
                return .confirmed(confirmations: 1)
            case "processed":
                return .pending
            default:
                return .pending
            }
        }
        
        return .pending
    }
    
    /// Check XRP transaction status
    func checkXRPStatus(txid: String, isTestnet: Bool) async throws -> TransactionStatus {
        let baseURL = isTestnet 
            ? "https://s.altnet.rippletest.net:51234"
            : "https://s1.ripple.com:51234"
        
        guard let url = URL(string: baseURL) else {
            throw BroadcastError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "method": "tx",
            "params": [
                ["transaction": txid]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any] else {
            throw BroadcastError.invalidResponse
        }
        
        // Check if transaction was found
        if let error = result["error"] as? String {
            if error == "txnNotFound" {
                return .notFound
            }
            return .failed(reason: error)
        }
        
        // Check validation status
        if let validated = result["validated"] as? Bool, validated {
            // Check result code
            if let meta = result["meta"] as? [String: Any],
               let transactionResult = meta["TransactionResult"] as? String {
                if transactionResult == "tesSUCCESS" {
                    return .confirmed(confirmations: 1) // XRP: validated = confirmed
                } else {
                    return .failed(reason: transactionResult)
                }
            }
            return .confirmed(confirmations: 1)
        }
        
        return .pending
    }
    
    /// Unified status check for any chain
    func checkTransactionStatus(txid: String, chainId: String) async throws -> TransactionStatus {
        switch chainId {
        case "bitcoin":
            return try await checkBitcoinStatus(txid: txid, isTestnet: false)
        case "bitcoin-testnet":
            return try await checkBitcoinStatus(txid: txid, isTestnet: true)
        case "ethereum":
            return try await checkEthereumStatus(txid: txid, isTestnet: false)
        case "ethereum-sepolia":
            return try await checkEthereumStatus(txid: txid, isTestnet: true)
        case "solana":
            return try await checkSolanaStatus(signature: txid, isDevnet: false)
        case "solana-devnet":
            return try await checkSolanaStatus(signature: txid, isDevnet: true)
        case "xrp":
            return try await checkXRPStatus(txid: txid, isTestnet: false)
        case "xrp-testnet":
            return try await checkXRPStatus(txid: txid, isTestnet: true)
        default:
            throw BroadcastError.unsupportedChain
        }
    }
}

enum BroadcastError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case broadcastFailed(String)
    case allEndpointsFailed
    case unsupportedChain
    /// The tx was accepted by at least one RPC, but could not be observed on other nodes yet.
    /// Treat this as a *retryable* state (often resolves within a few seconds).
    case propagationPending(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid broadcast URL"
        case .invalidResponse:
            return "Invalid response from network"
        case .broadcastFailed(let message):
            return "Broadcast failed: \(message)"
        case .allEndpointsFailed:
            return "All broadcast endpoints failed"
        case .unsupportedChain:
            return "Chain not supported for broadcasting"
        case .propagationPending(let message):
            return message
        }
    }
}
