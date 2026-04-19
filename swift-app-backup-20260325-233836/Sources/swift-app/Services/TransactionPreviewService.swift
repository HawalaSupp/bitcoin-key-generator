import Foundation
import CryptoKit

// MARK: - Transaction Preview & Simulation Service

/// Service for decoding and previewing Ethereum transactions
/// Detects risky operations, decodes contract calls, and simulates outcomes
@MainActor
class TransactionPreviewService: ObservableObject {
    
    // MARK: - Published State
    
    @Published var isLoading = false
    @Published var lastError: String?
    
    // MARK: - Configuration
    
    private let ethMainnetRPC = "https://eth-mainnet.g.alchemy.com/v2/demo"
    private let sepoliaRPC = "https://eth-sepolia.g.alchemy.com/v2/demo"
    
    // Known contract addresses (lowercase)
    private let knownContracts: [String: KnownContract] = [
        // Uniswap V2 Router
        "0x7a250d5630b4cf539739df2c5dacb4c659f2488d": KnownContract(
            name: "Uniswap V2 Router",
            category: .dex,
            riskLevel: .low
        ),
        // Uniswap V3 Router
        "0xe592427a0aece92de3edee1f18e0157c05861564": KnownContract(
            name: "Uniswap V3 Router",
            category: .dex,
            riskLevel: .low
        ),
        // Uniswap Universal Router
        "0x3fc91a3afd70395cd496c647d5a6cc9d4b2b7fad": KnownContract(
            name: "Uniswap Universal Router",
            category: .dex,
            riskLevel: .low
        ),
        // SushiSwap Router
        "0xd9e1ce17f2641f24ae83637ab66a2cca9c378b9f": KnownContract(
            name: "SushiSwap Router",
            category: .dex,
            riskLevel: .low
        ),
        // Aave V3 Pool
        "0x87870bca3f3fd6335c3f4ce8392d69350b4fa4e2": KnownContract(
            name: "Aave V3 Pool",
            category: .lending,
            riskLevel: .medium
        ),
        // Compound V3
        "0xc3d688b66703497daa19211eedff47f25384cdc3": KnownContract(
            name: "Compound V3 USDC",
            category: .lending,
            riskLevel: .medium
        ),
    ]
    
    // Known function selectors
    private let functionSelectors: [String: FunctionSignature] = [
        // ERC-20
        "a9059cbb": FunctionSignature(name: "transfer", description: "Transfer tokens", params: ["address", "uint256"]),
        "23b872dd": FunctionSignature(name: "transferFrom", description: "Transfer tokens from", params: ["address", "address", "uint256"]),
        "095ea7b3": FunctionSignature(name: "approve", description: "Approve token spending", params: ["address", "uint256"]),
        "39509351": FunctionSignature(name: "increaseAllowance", description: "Increase spending allowance", params: ["address", "uint256"]),
        "a457c2d7": FunctionSignature(name: "decreaseAllowance", description: "Decrease spending allowance", params: ["address", "uint256"]),
        
        // Uniswap V2
        "38ed1739": FunctionSignature(name: "swapExactTokensForTokens", description: "Swap exact tokens", params: ["uint256", "uint256", "address[]", "address", "uint256"]),
        "8803dbee": FunctionSignature(name: "swapTokensForExactTokens", description: "Swap for exact tokens", params: ["uint256", "uint256", "address[]", "address", "uint256"]),
        "7ff36ab5": FunctionSignature(name: "swapExactETHForTokens", description: "Swap ETH for tokens", params: ["uint256", "address[]", "address", "uint256"]),
        "18cbafe5": FunctionSignature(name: "swapExactTokensForETH", description: "Swap tokens for ETH", params: ["uint256", "uint256", "address[]", "address", "uint256"]),
        
        // Uniswap V3
        "c04b8d59": FunctionSignature(name: "exactInput", description: "Exact input swap", params: ["tuple"]),
        "db3e2198": FunctionSignature(name: "exactOutput", description: "Exact output swap", params: ["tuple"]),
        "414bf389": FunctionSignature(name: "exactInputSingle", description: "Single hop exact input", params: ["tuple"]),
        
        // Multicall
        "ac9650d8": FunctionSignature(name: "multicall", description: "Batch multiple calls", params: ["bytes[]"]),
        "5ae401dc": FunctionSignature(name: "multicall", description: "Multicall with deadline", params: ["uint256", "bytes[]"]),
        
        // Permit
        "d505accf": FunctionSignature(name: "permit", description: "ERC-2612 permit", params: ["address", "address", "uint256", "uint256", "uint8", "bytes32", "bytes32"]),
        
        // WETH
        "d0e30db0": FunctionSignature(name: "deposit", description: "Wrap ETH to WETH", params: []),
        "2e1a7d4d": FunctionSignature(name: "withdraw", description: "Unwrap WETH to ETH", params: ["uint256"]),
    ]
    
    // MARK: - Transaction Preview
    
    /// Decode and preview a transaction
    func preview(transaction: PreviewTransaction) async -> TransactionPreview {
        isLoading = true
        defer { isLoading = false }
        
        var preview = TransactionPreview(transaction: transaction)
        
        // Decode the transaction data
        if let data = transaction.data, !data.isEmpty, data != "0x" {
            preview.decodedCall = decodeCallData(data)
        }
        
        // Check if recipient is a known contract
        if let to = transaction.to?.lowercased() {
            if let known = knownContracts[to] {
                preview.recipientContract = known
            }
        }
        
        // Analyze risks
        preview.risks = analyzeRisks(transaction: transaction, decodedCall: preview.decodedCall)
        
        // Calculate estimated gas cost
        if let gasLimit = transaction.gasLimit, let gasPrice = transaction.gasPrice {
            let gasCost = Double(gasLimit) * Double(gasPrice) / 1e18
            preview.estimatedGasCost = gasCost
        }
        
        // Try to simulate the transaction
        if let simulation = await simulateTransaction(transaction) {
            preview.simulation = simulation
        }
        
        return preview
    }
    
    // MARK: - Call Data Decoding
    
    private func decodeCallData(_ data: String) -> DecodedCall? {
        let cleanData = data.hasPrefix("0x") ? String(data.dropFirst(2)) : data
        
        guard cleanData.count >= 8 else { return nil }
        
        let selector = String(cleanData.prefix(8)).lowercased()
        let params = String(cleanData.dropFirst(8))
        
        guard let signature = functionSelectors[selector] else {
            return DecodedCall(
                selector: selector,
                functionName: "Unknown function",
                description: "Unrecognized function call",
                parameters: [],
                rawParams: params
            )
        }
        
        // Decode parameters
        let decodedParams = decodeParameters(params, types: signature.params)
        
        return DecodedCall(
            selector: selector,
            functionName: signature.name,
            description: signature.description,
            parameters: decodedParams,
            rawParams: params
        )
    }
    
    private func decodeParameters(_ data: String, types: [String]) -> [DecodedParameter] {
        var params: [DecodedParameter] = []
        var offset = 0
        
        for (index, type) in types.enumerated() {
            guard offset + 64 <= data.count else { break }
            
            let chunk = String(data.dropFirst(offset).prefix(64))
            
            let decoded: String
            switch type {
            case "address":
                decoded = "0x" + String(chunk.suffix(40))
            case "uint256", "uint":
                if let value = UInt64(chunk, radix: 16) {
                    decoded = "\(value)"
                } else {
                    decoded = "0x" + chunk
                }
            case "bool":
                decoded = chunk.hasSuffix("1") ? "true" : "false"
            default:
                decoded = "0x" + chunk
            }
            
            params.append(DecodedParameter(
                index: index,
                type: type,
                value: decoded
            ))
            
            offset += 64
        }
        
        return params
    }
    
    // MARK: - Risk Analysis
    
    private func analyzeRisks(transaction: PreviewTransaction, decodedCall: DecodedCall?) -> [TransactionRisk] {
        var risks: [TransactionRisk] = []
        
        // Check for unlimited approval
        if let call = decodedCall, call.functionName == "approve" {
            if let amountParam = call.parameters.first(where: { $0.type == "uint256" }),
               let amount = UInt64(amountParam.value),
               amount == UInt64.max || amountParam.value.contains("ffffffff") {
                risks.append(TransactionRisk(
                    level: .high,
                    title: "Unlimited Token Approval",
                    description: "This transaction grants unlimited spending permission. Consider approving only the amount needed.",
                    recommendation: "Set a specific approval amount instead of unlimited"
                ))
            }
        }
        
        // Check for direct ETH transfer to contract
        if let value = transaction.value, value > 0 {
            if let to = transaction.to, to.lowercased().hasPrefix("0x") {
                // Could add contract check here
                if let data = transaction.data, data != "0x" && !data.isEmpty {
                    risks.append(TransactionRisk(
                        level: .medium,
                        title: "ETH Transfer to Contract",
                        description: "You're sending ETH along with a contract call.",
                        recommendation: "Verify the contract and function before proceeding"
                    ))
                }
            }
        }
        
        // Check for unknown function
        if let call = decodedCall, call.functionName == "Unknown function" {
            risks.append(TransactionRisk(
                level: .medium,
                title: "Unknown Function",
                description: "This transaction calls an unrecognized function.",
                recommendation: "Only proceed if you trust the source of this transaction"
            ))
        }
        
        // Check for large value transfer
        if let value = transaction.value {
            let ethValue = Double(value) / 1e18
            if ethValue > 1.0 {
                risks.append(TransactionRisk(
                    level: .medium,
                    title: "Large Value Transfer",
                    description: "This transaction involves \(String(format: "%.4f", ethValue)) ETH.",
                    recommendation: "Double-check the recipient address"
                ))
            }
        }
        
        // Check for high gas price
        if let gasPrice = transaction.gasPrice {
            let gweiPrice = Double(gasPrice) / 1e9
            if gweiPrice > 100 {
                risks.append(TransactionRisk(
                    level: .low,
                    title: "High Gas Price",
                    description: "Gas price is \(String(format: "%.0f", gweiPrice)) Gwei.",
                    recommendation: "Consider waiting for lower network fees"
                ))
            }
        }
        
        return risks
    }
    
    // MARK: - Transaction Simulation
    
    private func simulateTransaction(_ transaction: PreviewTransaction) async -> TransactionSimulation? {
        // Build eth_call request
        guard let to = transaction.to else { return nil }
        
        let rpc = transaction.chainId == 1 ? ethMainnetRPC : sepoliaRPC
        
        var callObject: [String: String] = [
            "to": to
        ]
        
        if let from = transaction.from {
            callObject["from"] = from
        }
        if let data = transaction.data, !data.isEmpty {
            callObject["data"] = data
        }
        if let value = transaction.value {
            callObject["value"] = "0x" + String(value, radix: 16)
        }
        
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_call",
            "params": [callObject, "latest"],
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
            
            if let error = response?["error"] as? [String: Any],
               let message = error["message"] as? String {
                return TransactionSimulation(
                    success: false,
                    revertReason: message,
                    gasUsed: nil
                )
            }
            
            if let _ = response?["result"] as? String {
                return TransactionSimulation(
                    success: true,
                    revertReason: nil,
                    gasUsed: nil
                )
            }
        } catch {
            return nil
        }
        
        return nil
    }
    
    // MARK: - Token Info
    
    /// Get ERC-20 token info
    func getTokenInfo(address: String, chainId: Int = 1) async -> TokenInfo? {
        let rpc = chainId == 1 ? ethMainnetRPC : sepoliaRPC
        
        // Query name, symbol, decimals
        async let nameResult = ethCall(
            to: address,
            data: "0x06fdde03", // name()
            rpc: rpc
        )
        async let symbolResult = ethCall(
            to: address,
            data: "0x95d89b41", // symbol()
            rpc: rpc
        )
        async let decimalsResult = ethCall(
            to: address,
            data: "0x313ce567", // decimals()
            rpc: rpc
        )
        
        let (name, symbol, decimals) = await (nameResult, symbolResult, decimalsResult)
        
        guard let symbolStr = decodeString(symbol),
              let decimalsValue = decodeUint(decimals) else {
            return nil
        }
        
        return TokenInfo(
            address: address,
            name: decodeString(name) ?? "Unknown",
            symbol: symbolStr,
            decimals: Int(decimalsValue)
        )
    }
    
    // MARK: - Helpers
    
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
        
        // ABI-encoded string: offset (32 bytes) + length (32 bytes) + data
        let lengthHex = String(clean.dropFirst(64).prefix(64))
        guard let length = UInt64(lengthHex, radix: 16), length > 0 else { return nil }
        
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

// MARK: - Preview Models

struct PreviewTransaction {
    let from: String?
    let to: String?
    let value: UInt64?
    let data: String?
    let gasLimit: UInt64?
    let gasPrice: UInt64?
    let chainId: Int
}

struct TransactionPreview {
    let transaction: PreviewTransaction
    var decodedCall: DecodedCall?
    var recipientContract: KnownContract?
    var risks: [TransactionRisk] = []
    var estimatedGasCost: Double?
    var simulation: TransactionSimulation?
    
    var overallRiskLevel: RiskLevel {
        risks.map { $0.level }.max() ?? .none
    }
}

struct DecodedCall {
    let selector: String
    let functionName: String
    let description: String
    let parameters: [DecodedParameter]
    let rawParams: String
}

struct DecodedParameter {
    let index: Int
    let type: String
    let value: String
}

struct TransactionRisk: Identifiable {
    let id = UUID()
    let level: RiskLevel
    let title: String
    let description: String
    let recommendation: String
}

enum RiskLevel: Int, Comparable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4
    
    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    var color: String {
        switch self {
        case .none: return "green"
        case .low: return "blue"
        case .medium: return "yellow"
        case .high: return "orange"
        case .critical: return "red"
        }
    }
    
    var icon: String {
        switch self {
        case .none: return "checkmark.shield.fill"
        case .low: return "info.circle.fill"
        case .medium: return "exclamationmark.triangle.fill"
        case .high: return "exclamationmark.octagon.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }
}

struct TransactionSimulation {
    let success: Bool
    let revertReason: String?
    let gasUsed: UInt64?
}

struct KnownContract {
    let name: String
    let category: ContractCategory
    let riskLevel: RiskLevel
}

enum ContractCategory {
    case dex
    case lending
    case bridge
    case unknown
    
    var displayName: String {
        switch self {
        case .dex: return "DEX"
        case .lending: return "Lending"
        case .bridge: return "Bridge"
        case .unknown: return "Unknown"
        }
    }
}

struct FunctionSignature {
    let name: String
    let description: String
    let params: [String]
}

struct TokenInfo {
    let address: String
    let name: String
    let symbol: String
    let decimals: Int
}
