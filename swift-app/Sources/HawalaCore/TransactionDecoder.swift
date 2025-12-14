import Foundation

// MARK: - Transaction Decoder Service
/// Decodes EVM transaction data into human-readable format
/// Shows token transfers, approvals, swaps in plain English

public final class TransactionDecoder: ObservableObject {
    public static let shared = TransactionDecoder()
    
    // MARK: - Published State
    @Published public private(set) var isSimulating = false
    @Published public private(set) var lastSimulationResult: SimulationResult?
    
    // MARK: - Known Method Signatures (4-byte selectors)
    private let methodSignatures: [String: MethodInfo] = [
        // ERC-20 Methods
        "a9059cbb": MethodInfo(name: "transfer", description: "Transfer tokens", params: ["address", "uint256"]),
        "23b872dd": MethodInfo(name: "transferFrom", description: "Transfer tokens from another address", params: ["address", "address", "uint256"]),
        "095ea7b3": MethodInfo(name: "approve", description: "Approve token spending", params: ["address", "uint256"]),
        "dd62ed3e": MethodInfo(name: "allowance", description: "Check spending allowance", params: ["address", "address"]),
        "70a08231": MethodInfo(name: "balanceOf", description: "Check token balance", params: ["address"]),
        "18160ddd": MethodInfo(name: "totalSupply", description: "Get total token supply", params: []),
        
        // ERC-721 Methods (NFTs)
        "42842e0e": MethodInfo(name: "safeTransferFrom", description: "Transfer NFT safely", params: ["address", "address", "uint256"]),
        "b88d4fde": MethodInfo(name: "safeTransferFrom", description: "Transfer NFT with data", params: ["address", "address", "uint256", "bytes"]),
        "a22cb465": MethodInfo(name: "setApprovalForAll", description: "Approve all NFTs", params: ["address", "bool"]),
        "081812fc": MethodInfo(name: "getApproved", description: "Get NFT approval", params: ["uint256"]),
        "e985e9c5": MethodInfo(name: "isApprovedForAll", description: "Check approval for all", params: ["address", "address"]),
        
        // ERC-1155 Methods (Multi-token)
        "f242432a": MethodInfo(name: "safeTransferFrom", description: "Transfer multi-token", params: ["address", "address", "uint256", "uint256", "bytes"]),
        "2eb2c2d6": MethodInfo(name: "safeBatchTransferFrom", description: "Batch transfer", params: ["address", "address", "uint256[]", "uint256[]", "bytes"]),
        
        // Common DEX Methods (Uniswap-style)
        "7ff36ab5": MethodInfo(name: "swapExactETHForTokens", description: "Swap ETH for tokens", params: ["uint256", "address[]", "address", "uint256"]),
        "18cbafe5": MethodInfo(name: "swapExactTokensForETH", description: "Swap tokens for ETH", params: ["uint256", "uint256", "address[]", "address", "uint256"]),
        "38ed1739": MethodInfo(name: "swapExactTokensForTokens", description: "Swap tokens for tokens", params: ["uint256", "uint256", "address[]", "address", "uint256"]),
        "8803dbee": MethodInfo(name: "swapTokensForExactTokens", description: "Swap tokens for exact tokens", params: ["uint256", "uint256", "address[]", "address", "uint256"]),
        "fb3bdb41": MethodInfo(name: "swapETHForExactTokens", description: "Swap ETH for exact tokens", params: ["uint256", "address[]", "address", "uint256"]),
        "4a25d94a": MethodInfo(name: "swapTokensForExactETH", description: "Swap tokens for exact ETH", params: ["uint256", "uint256", "address[]", "address", "uint256"]),
        
        // Uniswap V3 Router
        "c04b8d59": MethodInfo(name: "exactInput", description: "Exact input swap (V3)", params: ["tuple"]),
        "db3e2198": MethodInfo(name: "exactOutput", description: "Exact output swap (V3)", params: ["tuple"]),
        "414bf389": MethodInfo(name: "exactInputSingle", description: "Single exact input swap", params: ["tuple"]),
        "f28c0498": MethodInfo(name: "exactOutputSingle", description: "Single exact output swap", params: ["tuple"]),
        
        // WETH
        "d0e30db0": MethodInfo(name: "deposit", description: "Wrap ETH to WETH", params: []),
        "2e1a7d4d": MethodInfo(name: "withdraw", description: "Unwrap WETH to ETH", params: ["uint256"]),
        
        // OpenSea Seaport
        "fb0f3ee1": MethodInfo(name: "fulfillBasicOrder", description: "Buy NFT on OpenSea", params: ["tuple"]),
        "87201b41": MethodInfo(name: "fulfillAdvancedOrder", description: "Buy NFT (advanced)", params: ["tuple", "tuple[]", "bytes32", "address"]),
        
        // Permit2
        "2b67b570": MethodInfo(name: "permit", description: "Gasless approval", params: ["address", "tuple", "bytes"]),
        
        // Multicall
        "ac9650d8": MethodInfo(name: "multicall", description: "Execute multiple calls", params: ["bytes[]"]),
        "5ae401dc": MethodInfo(name: "multicall", description: "Execute multiple calls with deadline", params: ["uint256", "bytes[]"]),
        
        // Proxy/Upgradeable
        "3659cfe6": MethodInfo(name: "upgradeTo", description: "⚠️ Upgrade contract", params: ["address"]),
        "4f1ef286": MethodInfo(name: "upgradeToAndCall", description: "⚠️ Upgrade and call", params: ["address", "bytes"]),
    ]
    
    // MARK: - Known Contracts
    private let knownContracts: [String: ContractInfo] = [
        // Ethereum Mainnet
        "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2": ContractInfo(name: "WETH", type: .token, verified: true),
        "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48": ContractInfo(name: "USDC", type: .token, verified: true),
        "0xdac17f958d2ee523a2206206994597c13d831ec7": ContractInfo(name: "USDT", type: .token, verified: true),
        "0x6b175474e89094c44da98b954eedeac495271d0f": ContractInfo(name: "DAI", type: .token, verified: true),
        "0x7a250d5630b4cf539739df2c5dacb4c659f2488d": ContractInfo(name: "Uniswap V2 Router", type: .dex, verified: true),
        "0xe592427a0aece92de3edee1f18e0157c05861564": ContractInfo(name: "Uniswap V3 Router", type: .dex, verified: true),
        "0x68b3465833fb72a70ecdf485e0e4c7bd8665fc45": ContractInfo(name: "Uniswap Universal Router", type: .dex, verified: true),
        "0x00000000006c3852cbef3e08e8df289169ede581": ContractInfo(name: "OpenSea Seaport", type: .nftMarketplace, verified: true),
        "0x1e0049783f008a0085193e00003d00cd54003c71": ContractInfo(name: "Blur Marketplace", type: .nftMarketplace, verified: true),
        
        // Sepolia Testnet
        "0xfff9976782d46cc05630d1f6ebab18b2324d6b14": ContractInfo(name: "WETH (Sepolia)", type: .token, verified: true),
        "0x1c7d4b196cb0c7b01d743fbc6116a902379c7238": ContractInfo(name: "USDC (Sepolia)", type: .token, verified: true),
    ]
    
    // MARK: - Max Approval Value
    private let maxUint256 = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Decode transaction data into human-readable format
    public func decode(data: String, to: String?, value: String?) -> DecodedTransaction {
        var result = DecodedTransaction()
        
        // Clean data
        let cleanData = data.hasPrefix("0x") ? String(data.dropFirst(2)) : data
        
        // Parse value
        if let value = value, !value.isEmpty, value != "0x0" {
            let cleanValue = value.hasPrefix("0x") ? String(value.dropFirst(2)) : value
            if let valueInt = UInt64(cleanValue, radix: 16), valueInt > 0 {
                result.nativeValue = formatEther(cleanValue)
            }
        }
        
        // Check destination contract
        if let to = to {
            let lowerTo = to.lowercased()
            if let contractInfo = knownContracts[lowerTo] {
                result.contractName = contractInfo.name
                result.contractType = contractInfo.type
                result.isVerified = contractInfo.verified
            } else {
                result.warnings.append(.unverifiedContract)
            }
        }
        
        // Empty data = simple transfer
        guard cleanData.count >= 8 else {
            result.methodName = "Native Transfer"
            result.humanReadable = "Send \(result.nativeValue ?? "0") ETH"
            return result
        }
        
        // Extract method selector (first 4 bytes = 8 hex chars)
        let selector = String(cleanData.prefix(8)).lowercased()
        let params = String(cleanData.dropFirst(8))
        
        // Decode method
        if let methodInfo = methodSignatures[selector] {
            result.methodName = methodInfo.name
            result.methodDescription = methodInfo.description
            
            // Decode specific methods
            switch selector {
            case "a9059cbb": // transfer(address, uint256)
                result = decodeTransfer(params: params, result: result)
                
            case "095ea7b3": // approve(address, uint256)
                result = decodeApproval(params: params, result: result)
                
            case "23b872dd": // transferFrom(address, address, uint256)
                result = decodeTransferFrom(params: params, result: result)
                
            case "a22cb465": // setApprovalForAll(address, bool)
                result = decodeApprovalForAll(params: params, result: result)
                
            case "7ff36ab5", "18cbafe5", "38ed1739": // Swaps
                result = decodeSwap(selector: selector, params: params, result: result, value: result.nativeValue)
                
            case "d0e30db0": // deposit (wrap ETH)
                result.humanReadable = "Wrap \(result.nativeValue ?? "?") ETH to WETH"
                
            case "2e1a7d4d": // withdraw (unwrap WETH)
                let amount = decodeUint256(from: params, offset: 0)
                result.humanReadable = "Unwrap \(formatTokenAmount(amount)) WETH to ETH"
                
            default:
                result.humanReadable = "\(methodInfo.description)"
            }
        } else {
            result.methodName = "Unknown Method"
            result.methodDescription = "Function selector: 0x\(selector)"
            result.warnings.append(.unknownMethod)
            result.humanReadable = "⚠️ Unknown contract interaction"
        }
        
        return result
    }
    
    /// Simulate transaction and predict balance changes
    public func simulate(
        from: String,
        to: String,
        data: String,
        value: String?,
        chainId: Int
    ) async throws -> SimulationResult {
        await MainActor.run { isSimulating = true }
        defer { Task { @MainActor in isSimulating = false } }
        
        // For now, return a decoded preview without actual simulation
        // TODO: Integrate with Tenderly/Alchemy Simulation API
        let decoded = decode(data: data, to: to, value: value)
        
        var balanceChanges: [BalanceChange] = []
        
        // Predict ETH change
        if let nativeValue = decoded.nativeValue, Double(nativeValue) ?? 0 > 0 {
            balanceChanges.append(BalanceChange(
                asset: "ETH",
                amount: "-\(nativeValue)",
                isPositive: false
            ))
        }
        
        // Predict token changes based on decoded method
        if let tokenAmount = decoded.decodedParams["amount"] as? String,
           let tokenValue = Double(tokenAmount) {
            let formattedAmount = String(format: "%.6f", tokenValue)
            
            if decoded.methodName == "transfer" {
                balanceChanges.append(BalanceChange(
                    asset: decoded.contractName ?? "Token",
                    amount: "-\(formattedAmount)",
                    isPositive: false
                ))
            }
        }
        
        let result = SimulationResult(
            success: true,
            balanceChanges: balanceChanges,
            gasEstimate: nil, // Would come from simulation API
            warnings: decoded.warnings,
            decoded: decoded
        )
        
        await MainActor.run { lastSimulationResult = result }
        return result
    }
    
    // MARK: - Private Decoding Methods
    
    private func decodeTransfer(params: String, result: DecodedTransaction) -> DecodedTransaction {
        var result = result
        let recipient = decodeAddress(from: params, offset: 0)
        let amount = decodeUint256(from: params, offset: 64)
        
        let formattedAmount = formatTokenAmount(amount)
        result.decodedParams["recipient"] = recipient
        result.decodedParams["amount"] = formattedAmount
        
        let tokenName = result.contractName ?? "tokens"
        result.humanReadable = "Transfer \(formattedAmount) \(tokenName) to \(shortenAddress(recipient))"
        
        return result
    }
    
    private func decodeApproval(params: String, result: DecodedTransaction) -> DecodedTransaction {
        var result = result
        let spender = decodeAddress(from: params, offset: 0)
        let amount = decodeUint256(from: params, offset: 64)
        
        result.decodedParams["spender"] = spender
        result.decodedParams["amount"] = amount
        
        let spenderName = knownContracts[spender.lowercased()]?.name ?? shortenAddress(spender)
        
        if amount.lowercased() == maxUint256 || amount.count >= 64 && amount.filter({ $0 == "f" }).count > 50 {
            result.warnings.append(.unlimitedApproval)
            result.humanReadable = "⚠️ UNLIMITED approval to \(spenderName)"
            result.riskLevel = .high
        } else {
            let formattedAmount = formatTokenAmount(amount)
            result.humanReadable = "Approve \(spenderName) to spend \(formattedAmount) tokens"
            result.riskLevel = .medium
        }
        
        return result
    }
    
    private func decodeTransferFrom(params: String, result: DecodedTransaction) -> DecodedTransaction {
        var result = result
        let from = decodeAddress(from: params, offset: 0)
        let to = decodeAddress(from: params, offset: 64)
        let amount = decodeUint256(from: params, offset: 128)
        
        result.decodedParams["from"] = from
        result.decodedParams["to"] = to
        result.decodedParams["amount"] = formatTokenAmount(amount)
        
        result.humanReadable = "Transfer tokens from \(shortenAddress(from)) to \(shortenAddress(to))"
        
        return result
    }
    
    private func decodeApprovalForAll(params: String, result: DecodedTransaction) -> DecodedTransaction {
        var result = result
        let operator_ = decodeAddress(from: params, offset: 0)
        let approved = params.count >= 128 && params.suffix(1) == "1"
        
        result.decodedParams["operator"] = operator_
        result.decodedParams["approved"] = approved
        
        let operatorName = knownContracts[operator_.lowercased()]?.name ?? shortenAddress(operator_)
        
        if approved {
            result.warnings.append(.approvalForAll)
            result.humanReadable = "⚠️ Approve ALL NFTs to \(operatorName)"
            result.riskLevel = .high
        } else {
            result.humanReadable = "Revoke NFT approval from \(operatorName)"
            result.riskLevel = .low
        }
        
        return result
    }
    
    private func decodeSwap(selector: String, params: String, result: DecodedTransaction, value: String?) -> DecodedTransaction {
        var result = result
        
        switch selector {
        case "7ff36ab5": // swapExactETHForTokens
            result.humanReadable = "Swap \(value ?? "?") ETH for tokens"
            
        case "18cbafe5": // swapExactTokensForETH
            let amountIn = decodeUint256(from: params, offset: 0)
            result.humanReadable = "Swap \(formatTokenAmount(amountIn)) tokens for ETH"
            
        case "38ed1739": // swapExactTokensForTokens
            let amountIn = decodeUint256(from: params, offset: 0)
            result.humanReadable = "Swap \(formatTokenAmount(amountIn)) tokens"
            
        default:
            result.humanReadable = "Token swap"
        }
        
        return result
    }
    
    // MARK: - Utility Methods
    
    private func decodeAddress(from data: String, offset: Int) -> String {
        guard data.count >= offset + 64 else { return "0x0" }
        let start = data.index(data.startIndex, offsetBy: offset + 24) // Skip 24 chars of padding
        let end = data.index(start, offsetBy: 40)
        return "0x" + String(data[start..<end])
    }
    
    private func decodeUint256(from data: String, offset: Int) -> String {
        guard data.count >= offset + 64 else { return "0" }
        let start = data.index(data.startIndex, offsetBy: offset)
        let end = data.index(start, offsetBy: 64)
        return String(data[start..<end])
    }
    
    private func formatTokenAmount(_ hexAmount: String) -> String {
        guard let value = BigUInt(hexAmount, radix: 16) else { return "0" }
        // Assume 18 decimals (most common)
        let divisor = BigUInt(10).power(18)
        let whole = value / divisor
        let fraction = value % divisor
        
        if fraction == BigUInt(0) {
            return whole.description
        }
        
        let fractionStr = String(fraction.description.prefix(4))
        return "\(whole).\(fractionStr)"
    }
    
    private func formatEther(_ hexValue: String) -> String {
        return formatTokenAmount(hexValue)
    }
    
    private func shortenAddress(_ address: String) -> String {
        guard address.count > 10 else { return address }
        let start = address.prefix(6)
        let end = address.suffix(4)
        return "\(start)...\(end)"
    }
}

// MARK: - Supporting Types

public struct MethodInfo {
    let name: String
    let description: String
    let params: [String]
}

public struct ContractInfo {
    let name: String
    let type: ContractType
    let verified: Bool
}

public enum ContractType: String, Codable {
    case token = "Token"
    case dex = "DEX"
    case nftMarketplace = "NFT Marketplace"
    case lending = "Lending"
    case bridge = "Bridge"
    case unknown = "Unknown"
}

public struct DecodedTransaction {
    public var methodName: String = ""
    public var methodDescription: String = ""
    public var humanReadable: String = ""
    public var contractName: String?
    public var contractType: ContractType?
    public var isVerified: Bool = false
    public var nativeValue: String?
    public var decodedParams: [String: Any] = [:]
    public var warnings: [TransactionWarning] = []
    public var riskLevel: RiskLevel = .low
}

public enum TransactionWarning: String, CaseIterable {
    case unlimitedApproval = "Unlimited token approval requested"
    case approvalForAll = "Approving access to ALL NFTs"
    case unverifiedContract = "Interacting with unverified contract"
    case unknownMethod = "Unknown contract method"
    case highValue = "High value transaction"
    case newContract = "Contract deployed recently"
    
    public var icon: String {
        switch self {
        case .unlimitedApproval: return "⚠️"
        case .approvalForAll: return "🚨"
        case .unverifiedContract: return "❓"
        case .unknownMethod: return "❔"
        case .highValue: return "💰"
        case .newContract: return "🆕"
        }
    }
    
    public var severity: RiskLevel {
        switch self {
        case .unlimitedApproval, .approvalForAll: return .high
        case .unverifiedContract, .unknownMethod, .newContract: return .medium
        case .highValue: return .low
        }
    }
}

public enum RiskLevel: String, Codable, Comparable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case critical = "Critical"
    
    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        let order: [RiskLevel] = [.low, .medium, .high, .critical]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

public struct SimulationResult {
    public let success: Bool
    public let balanceChanges: [BalanceChange]
    public let gasEstimate: String?
    public let warnings: [TransactionWarning]
    public let decoded: DecodedTransaction
}

public struct BalanceChange: Identifiable {
    public let id = UUID()
    public let asset: String
    public let amount: String
    public let isPositive: Bool
}

// MARK: - Simple BigUInt (for token amounts)

struct BigUInt: Equatable, Comparable, CustomStringConvertible {
    private var value: [UInt64] // Little-endian limbs
    
    init(_ value: UInt64) {
        self.value = value == 0 ? [] : [value]
    }
    
    init?(_ string: String, radix: Int) {
        guard radix == 16 else { return nil }
        var result = BigUInt(0)
        let base = BigUInt(16)
        
        for char in string.lowercased() {
            guard let digit = Int(String(char), radix: 16) else { return nil }
            result = result * base + BigUInt(UInt64(digit))
        }
        
        self = result
    }
    
    var description: String {
        if value.isEmpty { return "0" }
        
        var result = ""
        var temp = self
        let ten = BigUInt(10)
        
        while temp > BigUInt(0) {
            let (quotient, remainder) = temp.quotientAndRemainder(dividingBy: ten)
            result = "\(remainder.value.first ?? 0)" + result
            temp = quotient
        }
        
        return result.isEmpty ? "0" : result
    }
    
    func power(_ exponent: Int) -> BigUInt {
        if exponent == 0 { return BigUInt(1) }
        var result = BigUInt(1)
        for _ in 0..<exponent {
            result = result * self
        }
        return result
    }
    
    static func + (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        var result = BigUInt(0)
        let maxLen = max(lhs.value.count, rhs.value.count)
        result.value = Array(repeating: 0, count: maxLen + 1)
        
        var carry: UInt64 = 0
        for i in 0..<maxLen {
            let a = i < lhs.value.count ? lhs.value[i] : 0
            let b = i < rhs.value.count ? rhs.value[i] : 0
            let sum = a &+ b &+ carry
            result.value[i] = sum
            carry = (a > UInt64.max - b || sum < a) ? 1 : 0
        }
        
        if carry > 0 {
            result.value[maxLen] = carry
        }
        
        while result.value.last == 0 && result.value.count > 0 {
            result.value.removeLast()
        }
        
        return result
    }
    
    static func * (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        if lhs.value.isEmpty || rhs.value.isEmpty { return BigUInt(0) }
        
        var result = BigUInt(0)
        result.value = Array(repeating: 0, count: lhs.value.count + rhs.value.count)
        
        for i in 0..<lhs.value.count {
            var carry: UInt64 = 0
            for j in 0..<rhs.value.count {
                let (hi, lo) = lhs.value[i].multipliedFullWidth(by: rhs.value[j])
                let current = result.value[i + j]
                let (sum1, overflow1) = current.addingReportingOverflow(lo)
                let (sum2, overflow2) = sum1.addingReportingOverflow(carry)
                result.value[i + j] = sum2
                carry = hi + (overflow1 ? 1 : 0) + (overflow2 ? 1 : 0)
            }
            if carry > 0 && i + rhs.value.count < result.value.count {
                result.value[i + rhs.value.count] = result.value[i + rhs.value.count] &+ carry
            }
        }
        
        while result.value.last == 0 && result.value.count > 0 {
            result.value.removeLast()
        }
        
        return result
    }
    
    static func / (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        return lhs.quotientAndRemainder(dividingBy: rhs).0
    }
    
    static func % (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        return lhs.quotientAndRemainder(dividingBy: rhs).1
    }
    
    func quotientAndRemainder(dividingBy divisor: BigUInt) -> (BigUInt, BigUInt) {
        if divisor.value.isEmpty { fatalError("Division by zero") }
        if self < divisor { return (BigUInt(0), self) }
        
        // Simple long division for small numbers
        if value.count == 1 && divisor.value.count == 1 {
            let q = value[0] / divisor.value[0]
            let r = value[0] % divisor.value[0]
            return (BigUInt(q), BigUInt(r))
        }
        
        // Binary long division for larger numbers
        var quotient = BigUInt(0)
        var remainder = BigUInt(0)
        
        // Process bit by bit from MSB
        for i in (0..<value.count).reversed() {
            for bit in (0..<64).reversed() {
                remainder = remainder * BigUInt(2)
                if (value[i] >> bit) & 1 == 1 {
                    remainder = remainder + BigUInt(1)
                }
                
                if remainder >= divisor {
                    remainder = remainder - divisor
                    // Set bit in quotient
                    while quotient.value.count <= i {
                        quotient.value.append(0)
                    }
                    quotient.value[i] |= (1 << bit)
                }
            }
        }
        
        while quotient.value.last == 0 && quotient.value.count > 0 {
            quotient.value.removeLast()
        }
        
        return (quotient, remainder)
    }
    
    static func - (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        guard lhs >= rhs else { return BigUInt(0) }
        
        var result = BigUInt(0)
        result.value = Array(repeating: 0, count: lhs.value.count)
        
        var borrow: UInt64 = 0
        for i in 0..<lhs.value.count {
            let a = lhs.value[i]
            let b = i < rhs.value.count ? rhs.value[i] : 0
            
            if a >= b + borrow {
                result.value[i] = a - b - borrow
                borrow = 0
            } else {
                result.value[i] = UInt64.max - b - borrow + a + 1
                borrow = 1
            }
        }
        
        while result.value.last == 0 && result.value.count > 0 {
            result.value.removeLast()
        }
        
        return result
    }
    
    static func < (lhs: BigUInt, rhs: BigUInt) -> Bool {
        if lhs.value.count != rhs.value.count {
            return lhs.value.count < rhs.value.count
        }
        for i in (0..<lhs.value.count).reversed() {
            if lhs.value[i] != rhs.value[i] {
                return lhs.value[i] < rhs.value[i]
            }
        }
        return false
    }
    
    static func <= (lhs: BigUInt, rhs: BigUInt) -> Bool {
        return lhs < rhs || lhs == rhs
    }
    
    static func > (lhs: BigUInt, rhs: BigUInt) -> Bool {
        return rhs < lhs
    }
    
    static func >= (lhs: BigUInt, rhs: BigUInt) -> Bool {
        return rhs <= lhs
    }
}
