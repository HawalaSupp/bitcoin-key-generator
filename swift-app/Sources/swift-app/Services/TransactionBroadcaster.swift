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
    
    private init() {}
    
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
            rpcEndpoints = [
                "https://sepolia.infura.io/v3/YOUR_INFURA_KEY",
                "https://rpc.sepolia.org",
                "https://ethereum-sepolia.publicnode.com"
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
    
    private func broadcastEthereumViaRPC(_ rawTxHex: String, rpcURL: String) async throws -> String {
        guard let url = URL(string: rpcURL) else {
            throw BroadcastError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let txWithPrefix = rawTxHex.hasPrefix("0x") ? rawTxHex : "0x\(rawTxHex)"
        
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_sendRawTransaction",
            "params": [txWithPrefix],
            "id": 1
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
        
        guard let txid = json["result"] as? String else {
            throw BroadcastError.invalidResponse
        }
        
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
}

// MARK: - Broadcast Errors

enum BroadcastError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case broadcastFailed(String)
    case allEndpointsFailed
    case unsupportedChain
    
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
        }
    }
}
