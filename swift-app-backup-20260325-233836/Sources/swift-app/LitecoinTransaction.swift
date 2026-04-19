import Foundation
import CryptoKit

// MARK: - Litecoin Transaction Service

/// Litecoin uses the same transaction format as Bitcoin.
/// This service handles Litecoin-specific address validation and API calls.

struct LitecoinTransactionService {
    
    private static let blockchairBaseURL = "https://api.blockchair.com/litecoin"
    
    struct LitecoinUTXO: Codable {
        let txid: String
        let vout: Int
        let value: Int64
        let scriptPubKey: String
        let confirmations: Int
    }
    
    static func fetchUTXOs(for address: String) async throws -> [LitecoinUTXO] {
        guard let url = URL(string: "\(blockchairBaseURL)/dashboards/address/\(address)?limit=100") else {
            throw LitecoinError.networkError("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw LitecoinError.networkError("Failed to fetch UTXOs")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let addressData = dataDict[address] as? [String: Any],
              let utxosArray = addressData["utxo"] as? [[String: Any]] else {
            return []
        }
        
        return utxosArray.compactMap { utxo -> LitecoinUTXO? in
            guard let txid = utxo["transaction_hash"] as? String,
                  let vout = utxo["index"] as? Int,
                  let value = utxo["value"] as? Int64 else { return nil }
            let scriptPubKey = utxo["script_hex"] as? String ?? ""
            let confirmations = utxo["block_id"] as? Int ?? 0
            return LitecoinUTXO(txid: txid, vout: vout, value: value, scriptPubKey: scriptPubKey, confirmations: confirmations > 0 ? 1 : 0)
        }
    }
    
    static func broadcastTransaction(rawTxHex: String) async throws -> String {
        guard let url = URL(string: "\(blockchairBaseURL)/push/transaction") else {
            throw LitecoinError.networkError("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": rawTxHex])
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let txid = dataDict["transaction_hash"] as? String else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LitecoinError.broadcastFailed(errorMsg)
        }
        
        return txid
    }
    
    static func isValidAddress(_ address: String) -> Bool {
        if address.lowercased().hasPrefix("ltc1") {
            return address.count >= 26 && address.count <= 90
        }
        if address.hasPrefix("L") || address.hasPrefix("M") {
            return address.count >= 26 && address.count <= 35
        }
        return false
    }
}

enum LitecoinError: Error, LocalizedError {
    case invalidAddress
    case invalidTxid
    case invalidWIF
    case invalidKey
    case insufficientFunds
    case dustAmount
    case networkError(String)
    case broadcastFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidAddress: return "Invalid Litecoin address"
        case .invalidTxid: return "Invalid transaction ID"
        case .invalidWIF: return "Invalid private key format"
        case .invalidKey: return "Invalid key"
        case .insufficientFunds: return "Insufficient funds"
        case .dustAmount: return "Amount is below dust limit"
        case .networkError(let msg): return "Network error: \(msg)"
        case .broadcastFailed(let msg): return "Broadcast failed: \(msg)"
        }
    }
}
