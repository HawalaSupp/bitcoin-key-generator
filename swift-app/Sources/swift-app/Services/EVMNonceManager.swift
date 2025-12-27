import Foundation

// MARK: - EVM Nonce Manager

/// Manages nonces for EVM transactions to prevent conflicts and enable proper replacement
@MainActor
final class EVMNonceManager: ObservableObject {
    static let shared = EVMNonceManager()
    
    // MARK: - Published State
    
    @Published var pendingNonces: [String: Set<UInt64>] = [:] // chainId -> pending nonces
    @Published var lastKnownNonce: [String: UInt64] = [:] // chainId -> last confirmed nonce
    
    // MARK: - Private State
    
    private var nonceCache: [String: [String: UInt64]] = [:] // chainId -> [address: nonce]
    
    private init() {}
    
    // MARK: - Public API
    
    /// Get the next available nonce for an address on a chain
    func getNextNonce(for address: String, chainId: String) async throws -> UInt64 {
        // First, fetch the current nonce from the network
        let networkNonce = try await fetchNetworkNonce(address: address, chainId: chainId)
        
        // Get pending nonces for this chain
        let pending = pendingNonces[chainId] ?? []
        
        // Find the next available nonce that's not pending
        var nextNonce = networkNonce
        while pending.contains(nextNonce) {
            nextNonce += 1
        }
        
        return nextNonce
    }
    
    /// Reserve a nonce for a pending transaction
    func reserveNonce(_ nonce: UInt64, chainId: String) {
        if pendingNonces[chainId] == nil {
            pendingNonces[chainId] = []
        }
        pendingNonces[chainId]?.insert(nonce)
        print("[NonceManager] Reserved nonce \(nonce) for chain \(chainId)")
    }
    
    /// Release a nonce when transaction is confirmed or failed
    func releaseNonce(_ nonce: UInt64, chainId: String) {
        pendingNonces[chainId]?.remove(nonce)
        print("[NonceManager] Released nonce \(nonce) for chain \(chainId)")
    }
    
    /// Mark a nonce as confirmed (update last known nonce)
    func confirmNonce(_ nonce: UInt64, chainId: String) {
        releaseNonce(nonce, chainId: chainId)
        
        if let current = lastKnownNonce[chainId] {
            lastKnownNonce[chainId] = max(current, nonce + 1)
        } else {
            lastKnownNonce[chainId] = nonce + 1
        }
        
        print("[NonceManager] Confirmed nonce \(nonce) for chain \(chainId), next: \(lastKnownNonce[chainId] ?? 0)")
    }
    
    /// Get nonce for replacement transaction (same nonce as original)
    func getNonceForReplacement(originalNonce: UInt64, chainId: String) -> UInt64 {
        // For RBF/cancel, we use the same nonce
        return originalNonce
    }
    
    /// Check for nonce gaps (transactions that might be stuck)
    func detectNonceGaps(chainId: String) -> [UInt64] {
        guard let pending = pendingNonces[chainId], !pending.isEmpty else {
            return []
        }
        
        let sortedPending = pending.sorted()
        var gaps: [UInt64] = []
        
        for i in 0..<(sortedPending.count - 1) {
            let current = sortedPending[i]
            let next = sortedPending[i + 1]
            
            if next > current + 1 {
                // There's a gap
                for gapNonce in (current + 1)..<next {
                    gaps.append(gapNonce)
                }
            }
        }
        
        return gaps
    }
    
    /// Clear all pending nonces for a chain (e.g., after wallet reset)
    func clearPendingNonces(chainId: String) {
        pendingNonces[chainId] = []
        print("[NonceManager] Cleared pending nonces for chain \(chainId)")
    }
    
    // MARK: - Network Fetching
    
    private func fetchNetworkNonce(address: String, chainId: String) async throws -> UInt64 {
        let rpcURL = getRPCURL(for: chainId)
        
        guard let url = URL(string: rpcURL) else {
            throw NonceError.invalidRPCURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getTransactionCount",
            "params": [address, "pending"], // Use "pending" to include mempool txs
            "id": 1
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NonceError.networkError
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultHex = json["result"] as? String else {
            throw NonceError.invalidResponse
        }
        
        // Parse hex nonce
        let nonceString = resultHex.hasPrefix("0x") ? String(resultHex.dropFirst(2)) : resultHex
        guard let nonce = UInt64(nonceString, radix: 16) else {
            throw NonceError.invalidNonceFormat
        }
        
        return nonce
    }
    
    private func getRPCURL(for chainId: String) -> String {
        switch chainId {
        case "ethereum", "1":
            return "https://eth.llamarpc.com"
        case "ethereum-sepolia", "11155111":
            return "https://ethereum-sepolia-rpc.publicnode.com"
        case "bnb", "56":
            return "https://bsc-dataseed.binance.org/"
        case "bnb-testnet", "97":
            return "https://data-seed-prebsc-1-s1.binance.org:8545/"
        case "polygon", "137":
            return "https://polygon-rpc.com"
        case "polygon-mumbai", "80001":
            return "https://rpc-mumbai.maticvigil.com"
        default:
            return "https://eth.llamarpc.com"
        }
    }
}

// MARK: - Nonce Error

enum NonceError: Error, LocalizedError {
    case invalidRPCURL
    case networkError
    case invalidResponse
    case invalidNonceFormat
    case nonceAlreadyUsed
    case nonceGapDetected
    
    var errorDescription: String? {
        switch self {
        case .invalidRPCURL:
            return "Invalid RPC URL for chain"
        case .networkError:
            return "Failed to fetch nonce from network"
        case .invalidResponse:
            return "Invalid response from RPC"
        case .invalidNonceFormat:
            return "Could not parse nonce from response"
        case .nonceAlreadyUsed:
            return "Nonce has already been used"
        case .nonceGapDetected:
            return "Nonce gap detected - previous transactions may be stuck"
        }
    }
}

// MARK: - Nonce Conflict Resolution

extension EVMNonceManager {
    
    /// Resolve nonce conflict by finding the first available nonce
    func resolveNonceConflict(address: String, chainId: String) async throws -> UInt64 {
        // Fetch fresh nonce from network
        let networkNonce = try await fetchNetworkNonce(address: address, chainId: chainId)
        
        // Clear stale pending nonces that are below network nonce
        if var pending = pendingNonces[chainId] {
            pending = pending.filter { $0 >= networkNonce }
            pendingNonces[chainId] = pending
        }
        
        // Return the next available nonce
        return try await getNextNonce(for: address, chainId: chainId)
    }
    
    /// Get status of pending transactions for an address
    func getPendingTransactionStatus(address: String, chainId: String) async throws -> PendingNonceStatus {
        let networkNonce = try await fetchNetworkNonce(address: address, chainId: chainId)
        let pending = pendingNonces[chainId] ?? []
        
        let gaps = detectNonceGaps(chainId: chainId)
        let stuckNonces = pending.filter { $0 < networkNonce }
        
        return PendingNonceStatus(
            networkNonce: networkNonce,
            pendingNonces: Array(pending).sorted(),
            gaps: gaps,
            stuckNonces: Array(stuckNonces).sorted()
        )
    }
}

// MARK: - Pending Nonce Status

struct PendingNonceStatus {
    let networkNonce: UInt64
    let pendingNonces: [UInt64]
    let gaps: [UInt64]
    let stuckNonces: [UInt64]
    
    var hasIssues: Bool {
        !gaps.isEmpty || !stuckNonces.isEmpty
    }
    
    var description: String {
        var parts: [String] = []
        parts.append("Network nonce: \(networkNonce)")
        
        if !pendingNonces.isEmpty {
            parts.append("Pending: \(pendingNonces.map(String.init).joined(separator: ", "))")
        }
        
        if !gaps.isEmpty {
            parts.append("⚠️ Gaps: \(gaps.map(String.init).joined(separator: ", "))")
        }
        
        if !stuckNonces.isEmpty {
            parts.append("⚠️ Stuck: \(stuckNonces.map(String.init).joined(separator: ", "))")
        }
        
        return parts.joined(separator: " | ")
    }
}
