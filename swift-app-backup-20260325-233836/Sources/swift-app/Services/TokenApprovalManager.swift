import Foundation

// MARK: - Token Approval Manager

/// Service for managing ERC-20 token approvals
/// Allows viewing and revoking spending permissions granted to contracts
@MainActor
class TokenApprovalManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published var approvals: [TokenApproval] = []
    @Published var isLoading = false
    @Published var lastError: String?
    
    // MARK: - Singleton
    
    static let shared = TokenApprovalManager()
    
    // MARK: - Configuration
    
    // Etherscan API keys - free tier allows limited requests
    // For production, add these to APIConfig
    private let etherscanAPIKey = ""  // Free tier works without key, but rate limited
    private let bscscanAPIKey = ""    // Same for BSCscan
    
    // API endpoints
    private let endpoints: [Int: String] = [
        1: "https://api.etherscan.io/api",
        11155111: "https://api-sepolia.etherscan.io/api",
        56: "https://api.bscscan.com/api",
        137: "https://api.polygonscan.com/api",
    ]
    
    // Known spender contracts (for display names)
    private let knownSpenders: [String: String] = [
        // Ethereum Mainnet
        "0x7a250d5630b4cf539739df2c5dacb4c659f2488d": "Uniswap V2 Router",
        "0xe592427a0aece92de3edee1f18e0157c05861564": "Uniswap V3 Router",
        "0x3fc91a3afd70395cd496c647d5a6cc9d4b2b7fad": "Uniswap Universal Router",
        "0x68b3465833fb72a70ecdf485e0e4c7bd8665fc45": "Uniswap Swap Router 02",
        "0xd9e1ce17f2641f24ae83637ab66a2cca9c378b9f": "SushiSwap Router",
        "0x1111111254eeb25477b68fb85ed929f73a960582": "1inch Router V5",
        "0x1111111254fb6c44bac0bed2854e76f90643097d": "1inch Router V4",
        "0xdef1c0ded9bec7f1a1670819833240f027b25eff": "0x Exchange Proxy",
        "0x00000000000000adc04c56bf30ac9d3c0aaf14dc": "OpenSea Seaport",
        "0x00000000006c3852cbef3e08e8df289169ede581": "OpenSea Seaport 1.1",
        "0x000000000022d473030f116ddee9f6b43ac78ba3": "Uniswap Permit2",
        "0x87870bca3f3fd6335c3f4ce8392d69350b4fa4e2": "Aave V3 Pool",
        "0x7d2768de32b0b80b7a3454c06bdac94a69ddc7a9": "Aave V2 Pool",
        "0xc3d688b66703497daa19211eedff47f25384cdc3": "Compound V3 USDC",
        // BSC
        "0x10ed43c718714eb63d5aa57b78b54704e256024e": "PancakeSwap Router",
        "0x13f4ea83d0bd40e75c8222255bc855a974568dd4": "PancakeSwap Smart Router",
    ]
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Fetch Approvals
    
    /// Fetch all token approvals for an address on a specific chain
    func fetchApprovals(address: String, chainId: Int) async {
        isLoading = true
        lastError = nil
        
        defer { isLoading = false }
        
        guard let endpoint = endpoints[chainId] else {
            lastError = "Unsupported chain"
            return
        }
        
        let apiKey = chainId == 56 ? bscscanAPIKey : etherscanAPIKey
        
        do {
            // Fetch ERC-20 approval events
            let erc20Approvals = try await fetchERC20Approvals(
                address: address,
                endpoint: endpoint,
                apiKey: apiKey,
                chainId: chainId
            )
            
            // Sort by timestamp
            var combined = erc20Approvals
            combined.sort { ($0.timestamp ?? 0) > ($1.timestamp ?? 0) }
            
            approvals = combined
        } catch {
            lastError = error.localizedDescription
        }
    }
    
    // MARK: - ERC-20 Approvals
    
    private func fetchERC20Approvals(
        address: String,
        endpoint: String,
        apiKey: String,
        chainId: Int
    ) async throws -> [TokenApproval] {
        // Approval event topic: keccak256("Approval(address,address,uint256)")
        let approvalTopic = "0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925"
        
        // Owner address (padded to 32 bytes)
        let ownerTopic = "0x" + String(repeating: "0", count: 24) + address.dropFirst(2).lowercased()
        
        var urlComponents = URLComponents(string: endpoint)!
        urlComponents.queryItems = [
            URLQueryItem(name: "module", value: "logs"),
            URLQueryItem(name: "action", value: "getLogs"),
            URLQueryItem(name: "topic0", value: approvalTopic),
            URLQueryItem(name: "topic1", value: ownerTopic),
            URLQueryItem(name: "topic1_2_opr", value: "and"),
            URLQueryItem(name: "apikey", value: apiKey),
        ]
        
        let (data, _) = try await URLSession.shared.data(from: urlComponents.url!)
        let response = try JSONDecoder().decode(EtherscanLogResponse.self, from: data)
        
        guard response.status == "1", let logs = response.result else {
            return []
        }
        
        // Process logs into approvals
        var approvalMap: [String: TokenApproval] = [:]
        
        for log in logs {
            guard log.topics.count >= 3 else { continue }
            
            let tokenAddress = log.address.lowercased()
            let spenderAddress = "0x" + log.topics[2].suffix(40).lowercased()
            let amount = parseApprovalAmount(log.data)
            
            // Create unique key for token+spender combination
            let key = "\(tokenAddress)-\(spenderAddress)"
            
            // Only keep the most recent approval for each token+spender
            if let existing = approvalMap[key] {
                if let existingTime = existing.timestamp, let newTime = parseTimestamp(log.timeStamp), newTime > existingTime {
                    // Update with newer approval
                } else {
                    continue
                }
            }
            
            // Get token info
            let tokenInfo = await getTokenInfo(address: tokenAddress, chainId: chainId)
            
            approvalMap[key] = TokenApproval(
                id: key,
                tokenAddress: tokenAddress,
                tokenName: tokenInfo?.name ?? "Unknown Token",
                tokenSymbol: tokenInfo?.symbol ?? "???",
                tokenDecimals: tokenInfo?.decimals ?? 18,
                spenderAddress: spenderAddress,
                spenderName: knownSpenders[spenderAddress] ?? nil,
                approvalAmount: amount,
                isUnlimited: amount == nil || amount == .max,
                chainId: chainId,
                timestamp: parseTimestamp(log.timeStamp),
                transactionHash: log.transactionHash
            )
        }
        
        // Filter out zero approvals (revoked)
        return Array(approvalMap.values).filter { $0.approvalAmount != 0 }
    }
    
    // MARK: - Revoke Approval
    
    /// Generate transaction data for revoking an ERC-20 approval
    func generateRevokeData(approval: TokenApproval) -> String {
        // approve(address,uint256) - set to 0
        let selector = "095ea7b3"
        let spender = String(repeating: "0", count: 24) + approval.spenderAddress.dropFirst(2)
        let value = String(repeating: "0", count: 64) // 0
        return "0x\(selector)\(spender)\(value)"
    }
    
    /// Get gas estimate for revoke transaction
    func estimateRevokeGas(approval: TokenApproval, from: String, chainId: Int) async -> UInt64? {
        let rpc = chainId == 1 ? "https://eth-mainnet.g.alchemy.com/v2/demo" : "https://eth-sepolia.g.alchemy.com/v2/demo"
        
        let data = generateRevokeData(approval: approval)
        
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_estimateGas",
            "params": [[
                "from": from,
                "to": approval.tokenAddress,
                "data": data
            ]],
            "id": 1
        ]
        
        guard let url = URL(string: rpc) else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            if let result = response?["result"] as? String {
                let cleanResult = result.hasPrefix("0x") ? String(result.dropFirst(2)) : result
                return UInt64(cleanResult, radix: 16)
            }
        } catch {}
        
        return 50000 // Default estimate for approval revocation
    }
    
    // MARK: - Helpers
    
    private func parseApprovalAmount(_ data: String) -> UInt64? {
        let clean = data.hasPrefix("0x") ? String(data.dropFirst(2)) : data
        guard !clean.isEmpty else { return nil }
        
        // Check for max uint256 (unlimited)
        if clean.contains("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff") {
            return .max
        }
        
        return UInt64(clean, radix: 16)
    }
    
    private func parseTimestamp(_ hex: String) -> TimeInterval? {
        let clean = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard let value = UInt64(clean, radix: 16) else { return nil }
        return TimeInterval(value)
    }
    
    private func getTokenInfo(address: String, chainId: Int) async -> (name: String, symbol: String, decimals: Int)? {
        let rpc = chainId == 1 ? "https://eth-mainnet.g.alchemy.com/v2/demo" : "https://eth-sepolia.g.alchemy.com/v2/demo"
        
        // Query symbol
        let symbolData = "0x95d89b41"
        let symbolResult = await ethCall(to: address, data: symbolData, rpc: rpc)
        
        // Query name
        let nameData = "0x06fdde03"
        let nameResult = await ethCall(to: address, data: nameData, rpc: rpc)
        
        // Query decimals
        let decimalsData = "0x313ce567"
        let decimalsResult = await ethCall(to: address, data: decimalsData, rpc: rpc)
        
        let symbol = decodeString(symbolResult) ?? "???"
        let name = decodeString(nameResult) ?? "Unknown"
        let decimals = decodeUint(decimalsResult) ?? 18
        
        return (name, symbol, Int(decimals))
    }
    
    private func ethCall(to: String, data: String, rpc: String) async -> String? {
        guard let url = URL(string: rpc) else { return nil }
        
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_call",
            "params": [["to": to, "data": data], "latest"],
            "id": 1
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return response?["result"] as? String
        } catch {
            return nil
        }
    }
    
    private func decodeString(_ hex: String?) -> String? {
        guard let hex = hex, hex.count > 130 else { return nil }
        let clean = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        
        let lengthHex = String(clean.dropFirst(64).prefix(64))
        guard let length = UInt64(lengthHex, radix: 16), length > 0, length < 100 else { return nil }
        
        let dataHex = String(clean.dropFirst(128).prefix(Int(length * 2)))
        guard let data = Data(hex: dataHex) else { return nil }
        
        return String(data: data, encoding: .utf8)
    }
    
    private func decodeUint(_ hex: String?) -> UInt64? {
        guard let hex = hex else { return nil }
        let clean = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        return UInt64(clean, radix: 16)
    }
}

// MARK: - Models

struct TokenApproval: Identifiable {
    let id: String
    let tokenAddress: String
    let tokenName: String
    let tokenSymbol: String
    let tokenDecimals: Int
    let spenderAddress: String
    let spenderName: String?
    let approvalAmount: UInt64?
    let isUnlimited: Bool
    let chainId: Int
    let timestamp: TimeInterval?
    let transactionHash: String?
    
    var displayAmount: String {
        if isUnlimited || approvalAmount == .max {
            return "Unlimited"
        }
        guard let amount = approvalAmount else { return "Unknown" }
        let value = Double(amount) / pow(10, Double(tokenDecimals))
        return String(format: "%.4f", value)
    }
    
    var riskLevel: ApprovalRiskLevel {
        if isUnlimited || approvalAmount == .max {
            return .high
        }
        return .low
    }
}

enum ApprovalRiskLevel {
    case low
    case medium
    case high
    
    var color: String {
        switch self {
        case .low: return "green"
        case .medium: return "yellow"
        case .high: return "red"
        }
    }
    
    var icon: String {
        switch self {
        case .low: return "checkmark.shield"
        case .medium: return "exclamationmark.triangle"
        case .high: return "exclamationmark.octagon"
        }
    }
}

// MARK: - Etherscan Response Models

private struct EtherscanLogResponse: Codable {
    let status: String
    let message: String
    let result: [EtherscanLog]?
}

private struct EtherscanLog: Codable {
    let address: String
    let topics: [String]
    let data: String
    let blockNumber: String
    let timeStamp: String
    let gasPrice: String?
    let gasUsed: String?
    let transactionHash: String
}
