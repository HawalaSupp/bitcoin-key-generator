import Foundation
import CryptoKit

// MARK: - Transaction Intent Decoder
// Phase 5.3: Smart Transaction Features - Human-Readable Transaction Signing

/// Supported transaction types that can be decoded
enum IntentTransactionType: String, Codable {
    case transfer = "Transfer"
    case tokenTransfer = "Token Transfer"
    case tokenApproval = "Token Approval"
    case contractCall = "Contract Call"
    case swap = "Swap"
    case nftTransfer = "NFT Transfer"
    case stake = "Stake"
    case unstake = "Unstake"
    case wrap = "Wrap"
    case unwrap = "Unwrap"
    case bridge = "Bridge"
    case unknown = "Unknown"
    
    var icon: String {
        switch self {
        case .transfer: return "arrow.up.circle.fill"
        case .tokenTransfer: return "circle.circle.fill"
        case .tokenApproval: return "checkmark.seal.fill"
        case .contractCall: return "doc.text.fill"
        case .swap: return "arrow.triangle.2.circlepath.circle.fill"
        case .nftTransfer: return "photo.fill"
        case .stake: return "lock.fill"
        case .unstake: return "lock.open.fill"
        case .wrap: return "gift.fill"
        case .unwrap: return "shippingbox.fill"
        case .bridge: return "arrow.left.arrow.right.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .transfer, .tokenTransfer: return "blue"
        case .tokenApproval: return "orange"
        case .contractCall: return "purple"
        case .swap: return "green"
        case .nftTransfer: return "pink"
        case .stake, .unstake: return "indigo"
        case .wrap, .unwrap: return "teal"
        case .bridge: return "cyan"
        case .unknown: return "gray"
        }
    }
}

/// Risk level for transaction warnings
enum IntentRiskLevel: String, Codable {
    case safe = "Safe"
    case caution = "Caution"
    case warning = "Warning"
    case danger = "Danger"
    
    var icon: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.octagon.fill"
        case .danger: return "xmark.shield.fill"
        }
    }
    
    var color: String {
        switch self {
        case .safe: return "green"
        case .caution: return "yellow"
        case .warning: return "orange"
        case .danger: return "red"
        }
    }
}

/// Warning about a transaction
struct IntentWarning: Identifiable {
    let id = UUID()
    let level: IntentRiskLevel
    let title: String
    let description: String
    let recommendation: String?
}

/// Token information for display
struct IntentTokenInfo: Codable {
    let symbol: String
    let name: String
    let decimals: Int
    let contractAddress: String?
    let logoURL: String?
    let isVerified: Bool
    
    static let eth = IntentTokenInfo(symbol: "ETH", name: "Ethereum", decimals: 18, contractAddress: nil, logoURL: nil, isVerified: true)
    static let btc = IntentTokenInfo(symbol: "BTC", name: "Bitcoin", decimals: 8, contractAddress: nil, logoURL: nil, isVerified: true)
    static let ltc = IntentTokenInfo(symbol: "LTC", name: "Litecoin", decimals: 8, contractAddress: nil, logoURL: nil, isVerified: true)
}

/// Decoded transaction intent for display
struct DecodedTransactionIntent: Identifiable {
    let id = UUID()
    let type: IntentTransactionType
    let chain: String
    
    // Parties
    let fromAddress: String
    let toAddress: String
    let toAddressLabel: String?  // ENS, contact name, or known service
    
    // Amounts
    let amount: Decimal
    let token: IntentTokenInfo
    let fiatValue: Decimal?
    
    // Fee
    let fee: Decimal
    let feeToken: IntentTokenInfo
    let feeFiatValue: Decimal?
    
    // For approvals
    let approvalAmount: Decimal?
    let isUnlimitedApproval: Bool
    let spenderAddress: String?
    let spenderLabel: String?
    
    // Contract interaction
    let contractName: String?
    let functionName: String?
    let functionParameters: [String: String]?
    
    // Warnings
    let warnings: [IntentWarning]
    let overallRisk: IntentRiskLevel
    
    // Raw data
    let rawTransaction: String
    let timestamp: Date
    
    // Human-readable summary
    var summary: String {
        switch type {
        case .transfer:
            return "Send \(formatAmount(amount)) \(token.symbol) to \(toAddressLabel ?? shortAddress(toAddress))"
        case .tokenTransfer:
            return "Send \(formatAmount(amount)) \(token.symbol) to \(toAddressLabel ?? shortAddress(toAddress))"
        case .tokenApproval:
            if isUnlimitedApproval {
                return "Approve UNLIMITED \(token.symbol) for \(spenderLabel ?? shortAddress(spenderAddress ?? "unknown"))"
            } else {
                return "Approve \(formatAmount(approvalAmount ?? 0)) \(token.symbol) for \(spenderLabel ?? shortAddress(spenderAddress ?? "unknown"))"
            }
        case .swap:
            return "Swap \(formatAmount(amount)) \(token.symbol)"
        case .nftTransfer:
            return "Transfer NFT to \(toAddressLabel ?? shortAddress(toAddress))"
        case .stake:
            return "Stake \(formatAmount(amount)) \(token.symbol)"
        case .unstake:
            return "Unstake \(formatAmount(amount)) \(token.symbol)"
        case .contractCall:
            return "Call \(functionName ?? "function") on \(contractName ?? shortAddress(toAddress))"
        default:
            return "\(type.rawValue): \(formatAmount(amount)) \(token.symbol)"
        }
    }
    
    private func formatAmount(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 8
        formatter.minimumFractionDigits = 0
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
    
    private func shortAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
}

/// Balance change from transaction
struct IntentBalanceChange: Identifiable {
    let id = UUID()
    let token: IntentTokenInfo
    let amount: Decimal
    let isIncoming: Bool
    let fiatValue: Decimal?
    
    var displayAmount: String {
        let sign = isIncoming ? "+" : "-"
        return "\(sign)\(abs(amount))"
    }
}

/// Type alias for backward compatibility
typealias TransactionIntent = DecodedTransactionIntent

// MARK: - Transaction Intent Decoder

@MainActor
final class TransactionIntentDecoder: ObservableObject {
    static let shared = TransactionIntentDecoder()
    
    // MARK: - Published Properties
    
    @Published var lastDecodedIntent: DecodedTransactionIntent?
    @Published var isDecoding: Bool = false
    @Published var lastError: String?
    
    // MARK: - Known Contracts Database
    
    private var knownContracts: [String: KnownContract] = [:]
    private var knownAddresses: [String: String] = [:]  // address -> label
    private var scamAddresses: Set<String> = []
    
    // MARK: - Initialization
    
    private init() {
        loadKnownContracts()
        loadKnownAddresses()
        loadScamDatabase()
        
        #if DEBUG
        print("🔍 Transaction Intent Decoder initialized")
        print("   Known contracts: \(knownContracts.count)")
        print("   Known addresses: \(knownAddresses.count)")
        print("   Scam addresses: \(scamAddresses.count)")
        #endif
    }
    
    // MARK: - Public API
    
    /// Decode a raw Ethereum transaction
    func decodeEthereumTransaction(
        from: String,
        to: String,
        value: String,
        data: String,
        gasPrice: String,
        gasLimit: String
    ) -> DecodedTransactionIntent {
        isDecoding = true
        defer { isDecoding = false }
        
        var warnings: [IntentWarning] = []
        var type: IntentTransactionType = .transfer
        var contractName: String? = nil
        var functionName: String? = nil
        var functionParams: [String: String]? = nil
        var tokenInfo = IntentTokenInfo.eth
        var amount = weiToEth(value)
        var approvalAmount: Decimal? = nil
        var isUnlimited = false
        var spender: String? = nil
        
        // Check for known contract
        let toAddressLower = to.lowercased()
        if let contract = knownContracts[toAddressLower] {
            contractName = contract.name
        }
        
        // Decode transaction data
        if data.count > 2 && data != "0x" {
            let decoded = decodeEthereumData(data)
            type = decoded.type
            functionName = decoded.functionName
            functionParams = decoded.params
            
            if let token = decoded.token {
                tokenInfo = token
            }
            if let amt = decoded.amount {
                amount = amt
            }
            if let approval = decoded.approvalAmount {
                approvalAmount = approval
                isUnlimited = approval > Decimal(string: "1000000000000000000000000000")!
            }
            if let sp = decoded.spender {
                spender = sp
            }
        }
        
        // Generate warnings
        warnings.append(contentsOf: generateWarnings(
            type: type,
            to: to,
            amount: amount,
            isUnlimited: isUnlimited,
            contractName: contractName
        ))
        
        // Calculate fee
        let gasP = weiToGwei(gasPrice)
        let gasL = Decimal(string: gasLimit) ?? 21000
        let feeInGwei = gasP * gasL
        let feeInEth = feeInGwei / Decimal(1_000_000_000)
        
        // Estimate fiat values (placeholder - would use real price)
        let ethPrice: Decimal = 4000
        let fiatValue = amount * ethPrice
        let feeFiatValue = feeInEth * ethPrice
        
        let intent = DecodedTransactionIntent(
            type: type,
            chain: "Ethereum",
            fromAddress: from,
            toAddress: to,
            toAddressLabel: knownAddresses[toAddressLower] ?? contractName,
            amount: amount,
            token: tokenInfo,
            fiatValue: fiatValue,
            fee: feeInEth,
            feeToken: IntentTokenInfo.eth,
            feeFiatValue: feeFiatValue,
            approvalAmount: approvalAmount,
            isUnlimitedApproval: isUnlimited,
            spenderAddress: spender,
            spenderLabel: spender != nil ? knownAddresses[spender!.lowercased()] : nil,
            contractName: contractName,
            functionName: functionName,
            functionParameters: functionParams,
            warnings: warnings,
            overallRisk: calculateOverallRisk(warnings),
            rawTransaction: data,
            timestamp: Date()
        )
        
        lastDecodedIntent = intent
        return intent
    }
    
    /// Decode a Bitcoin transaction
    func decodeBitcoinTransaction(
        from: String,
        to: String,
        amountSats: Int64,
        feeSats: Int64,
        isRBF: Bool = false
    ) -> DecodedTransactionIntent {
        isDecoding = true
        defer { isDecoding = false }
        
        var warnings: [IntentWarning] = []
        let amount = Decimal(amountSats) / Decimal(100_000_000)
        let fee = Decimal(feeSats) / Decimal(100_000_000)
        
        // Check for first-time send
        if !knownAddresses.keys.contains(to.lowercased()) {
            warnings.append(IntentWarning(
                level: .caution,
                title: "First-time recipient",
                description: "You haven't sent to this address before",
                recommendation: "Double-check the address is correct"
            ))
        }
        
        // Check for scam address
        if scamAddresses.contains(to.lowercased()) {
            warnings.append(IntentWarning(
                level: .danger,
                title: "Known scam address",
                description: "This address has been reported as a scam",
                recommendation: "DO NOT send to this address"
            ))
        }
        
        // High fee warning
        let feePercent = (fee / amount) * 100
        if feePercent > 5 {
            warnings.append(IntentWarning(
                level: .warning,
                title: "High fee",
                description: "Fee is \(feePercent)% of transaction amount",
                recommendation: "Consider waiting for lower network fees"
            ))
        }
        
        // RBF indicator
        if isRBF {
            warnings.append(IntentWarning(
                level: .caution,
                title: "RBF Enabled",
                description: "This transaction can be replaced before confirmation",
                recommendation: "Normal for most transactions"
            ))
        }
        
        // Estimate fiat values
        let btcPrice: Decimal = 100000
        let fiatValue = amount * btcPrice
        let feeFiatValue = fee * btcPrice
        
        let intent = DecodedTransactionIntent(
            type: .transfer,
            chain: "Bitcoin",
            fromAddress: from,
            toAddress: to,
            toAddressLabel: knownAddresses[to.lowercased()],
            amount: amount,
            token: IntentTokenInfo.btc,
            fiatValue: fiatValue,
            fee: fee,
            feeToken: IntentTokenInfo.btc,
            feeFiatValue: feeFiatValue,
            approvalAmount: nil,
            isUnlimitedApproval: false,
            spenderAddress: nil,
            spenderLabel: nil,
            contractName: nil,
            functionName: nil,
            functionParameters: nil,
            warnings: warnings,
            overallRisk: calculateOverallRisk(warnings),
            rawTransaction: "",
            timestamp: Date()
        )
        
        lastDecodedIntent = intent
        return intent
    }
    
    /// Simulate balance changes
    func simulateBalanceChanges(intent: DecodedTransactionIntent) -> [IntentBalanceChange] {
        var changes: [IntentBalanceChange] = []
        
        // Outgoing amount
        if intent.amount > 0 {
            changes.append(IntentBalanceChange(
                token: intent.token,
                amount: intent.amount,
                isIncoming: false,
                fiatValue: intent.fiatValue
            ))
        }
        
        // Fee
        changes.append(IntentBalanceChange(
            token: intent.feeToken,
            amount: intent.fee,
            isIncoming: false,
            fiatValue: intent.feeFiatValue
        ))
        
        return changes
    }
    
    /// Add a known address
    func addKnownAddress(_ address: String, label: String) {
        knownAddresses[address.lowercased()] = label
        saveKnownAddresses()
    }
    
    /// Report a scam address
    func reportScamAddress(_ address: String) {
        scamAddresses.insert(address.lowercased())
        saveScamDatabase()
    }
    
    // MARK: - Ethereum Data Decoding
    
    private struct DecodedData {
        var type: IntentTransactionType
        var functionName: String?
        var params: [String: String]?
        var token: IntentTokenInfo?
        var amount: Decimal?
        var approvalAmount: Decimal?
        var spender: String?
    }
    
    private func decodeEthereumData(_ data: String) -> DecodedData {
        guard data.count >= 10 else {
            return DecodedData(type: .contractCall)
        }
        
        let methodId = String(data.prefix(10)).lowercased()
        
        // Known ERC-20 method signatures
        switch methodId {
        case "0xa9059cbb":  // transfer(address,uint256)
            let params = parseTransferParams(data)
            return DecodedData(
                type: .tokenTransfer,
                functionName: "transfer",
                params: params,
                amount: params["amount"].flatMap { parseAmount($0) }
            )
            
        case "0x095ea7b3":  // approve(address,uint256)
            let params = parseApproveParams(data)
            let approvalAmt = params["amount"].flatMap { parseAmount($0) }
            return DecodedData(
                type: .tokenApproval,
                functionName: "approve",
                params: params,
                approvalAmount: approvalAmt,
                spender: params["spender"]
            )
            
        case "0x23b872dd":  // transferFrom(address,address,uint256)
            return DecodedData(
                type: .tokenTransfer,
                functionName: "transferFrom",
                params: parseTransferFromParams(data)
            )
            
        case "0x38ed1739", "0x8803dbee", "0x7ff36ab5":  // Uniswap swaps
            return DecodedData(
                type: .swap,
                functionName: "swap"
            )
            
        case "0xa694fc3a":  // stake(uint256)
            return DecodedData(
                type: .stake,
                functionName: "stake"
            )
            
        case "0x2e1a7d4d":  // withdraw(uint256)
            return DecodedData(
                type: .unstake,
                functionName: "withdraw"
            )
            
        case "0xd0e30db0":  // deposit() - WETH wrap
            return DecodedData(
                type: .wrap,
                functionName: "deposit"
            )
            
        default:
            return DecodedData(
                type: .contractCall,
                functionName: "Unknown (\(methodId))"
            )
        }
    }
    
    private func parseTransferParams(_ data: String) -> [String: String] {
        guard data.count >= 138 else { return [:] }
        
        let toAddress = "0x" + String(data.dropFirst(10).prefix(64)).suffix(40)
        let amountHex = String(data.dropFirst(74).prefix(64))
        
        return [
            "to": toAddress,
            "amount": amountHex
        ]
    }
    
    private func parseApproveParams(_ data: String) -> [String: String] {
        guard data.count >= 138 else { return [:] }
        
        let spender = "0x" + String(data.dropFirst(10).prefix(64)).suffix(40)
        let amountHex = String(data.dropFirst(74).prefix(64))
        
        return [
            "spender": String(spender),
            "amount": amountHex
        ]
    }
    
    private func parseTransferFromParams(_ data: String) -> [String: String] {
        guard data.count >= 202 else { return [:] }
        
        let from = "0x" + String(data.dropFirst(10).prefix(64)).suffix(40)
        let to = "0x" + String(data.dropFirst(74).prefix(64)).suffix(40)
        let amountHex = String(data.dropFirst(138).prefix(64))
        
        return [
            "from": String(from),
            "to": String(to),
            "amount": amountHex
        ]
    }
    
    private func parseAmount(_ hexAmount: String) -> Decimal? {
        // Remove leading zeros and convert from hex
        let cleaned = hexAmount.trimmingCharacters(in: CharacterSet(charactersIn: "0"))
        guard !cleaned.isEmpty else { return 0 }
        
        // Simple hex to decimal conversion (for display purposes)
        if let value = UInt64(cleaned, radix: 16) {
            return Decimal(value) / Decimal(1_000_000_000_000_000_000)  // Assuming 18 decimals
        }
        return nil
    }
    
    // MARK: - Warning Generation
    
    private func generateWarnings(
        type: IntentTransactionType,
        to: String,
        amount: Decimal,
        isUnlimited: Bool,
        contractName: String?
    ) -> [IntentWarning] {
        var warnings: [IntentWarning] = []
        
        // Check for scam address
        if scamAddresses.contains(to.lowercased()) {
            warnings.append(IntentWarning(
                level: .danger,
                title: "⚠️ Known Scam Address",
                description: "This address has been reported as malicious",
                recommendation: "DO NOT proceed with this transaction"
            ))
        }
        
        // First-time interaction
        if !knownAddresses.keys.contains(to.lowercased()) && contractName == nil {
            warnings.append(IntentWarning(
                level: .caution,
                title: "New Address",
                description: "You haven't interacted with this address before",
                recommendation: "Verify the address is correct before proceeding"
            ))
        }
        
        // Unlimited approval warning
        if type == .tokenApproval && isUnlimited {
            warnings.append(IntentWarning(
                level: .warning,
                title: "Unlimited Approval",
                description: "This will allow unlimited spending of your tokens",
                recommendation: "Consider approving only the amount needed"
            ))
        }
        
        // Unverified contract
        if type == .contractCall && contractName == nil {
            warnings.append(IntentWarning(
                level: .caution,
                title: "Unverified Contract",
                description: "This contract is not in our verified list",
                recommendation: "Verify the contract on Etherscan before proceeding"
            ))
        }
        
        // Large amount warning
        if amount > 10 {  // More than 10 ETH/BTC
            warnings.append(IntentWarning(
                level: .caution,
                title: "Large Transaction",
                description: "This is a significant amount",
                recommendation: "Double-check all details before confirming"
            ))
        }
        
        return warnings
    }
    
    private func calculateOverallRisk(_ warnings: [IntentWarning]) -> IntentRiskLevel {
        if warnings.contains(where: { $0.level == .danger }) {
            return .danger
        }
        if warnings.contains(where: { $0.level == .warning }) {
            return .warning
        }
        if warnings.contains(where: { $0.level == .caution }) {
            return .caution
        }
        return .safe
    }
    
    // MARK: - Helper Functions
    
    private func weiToEth(_ weiString: String) -> Decimal {
        guard let wei = Decimal(string: weiString.hasPrefix("0x") 
            ? String(UInt64(weiString.dropFirst(2), radix: 16) ?? 0)
            : weiString) else { return 0 }
        return wei / Decimal(1_000_000_000_000_000_000)
    }
    
    private func weiToGwei(_ weiString: String) -> Decimal {
        guard let wei = Decimal(string: weiString.hasPrefix("0x")
            ? String(UInt64(weiString.dropFirst(2), radix: 16) ?? 0)
            : weiString) else { return 0 }
        return wei / Decimal(1_000_000_000)
    }
    
    // MARK: - Known Contracts Database
    
    private struct KnownContract {
        let address: String
        let name: String
        let category: String
        let isVerified: Bool
    }
    
    private func loadKnownContracts() {
        // Popular DeFi contracts
        knownContracts = [
            // Uniswap
            "0x7a250d5630b4cf539739df2c5dacb4c659f2488d": KnownContract(
                address: "0x7a250d5630b4cf539739df2c5dacb4c659f2488d",
                name: "Uniswap V2 Router",
                category: "DEX",
                isVerified: true
            ),
            "0xe592427a0aece92de3edee1f18e0157c05861564": KnownContract(
                address: "0xe592427a0aece92de3edee1f18e0157c05861564",
                name: "Uniswap V3 Router",
                category: "DEX",
                isVerified: true
            ),
            
            // WETH
            "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2": KnownContract(
                address: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
                name: "Wrapped ETH (WETH)",
                category: "Token",
                isVerified: true
            ),
            
            // USDT
            "0xdac17f958d2ee523a2206206994597c13d831ec7": KnownContract(
                address: "0xdac17f958d2ee523a2206206994597c13d831ec7",
                name: "Tether USD (USDT)",
                category: "Stablecoin",
                isVerified: true
            ),
            
            // USDC
            "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48": KnownContract(
                address: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                name: "USD Coin (USDC)",
                category: "Stablecoin",
                isVerified: true
            ),
            
            // Aave
            "0x7d2768de32b0b80b7a3454c06bdac94a69ddc7a9": KnownContract(
                address: "0x7d2768de32b0b80b7a3454c06bdac94a69ddc7a9",
                name: "Aave V2 Pool",
                category: "Lending",
                isVerified: true
            ),
            
            // Compound
            "0x3d9819210a31b4961b30ef54be2aed79b9c9cd3b": KnownContract(
                address: "0x3d9819210a31b4961b30ef54be2aed79b9c9cd3b",
                name: "Compound Comptroller",
                category: "Lending",
                isVerified: true
            ),
            
            // OpenSea
            "0x00000000006c3852cbef3e08e8df289169ede581": KnownContract(
                address: "0x00000000006c3852cbef3e08e8df289169ede581",
                name: "OpenSea Seaport",
                category: "NFT Marketplace",
                isVerified: true
            ),
        ]
    }
    
    private func loadKnownAddresses() {
        // Load from UserDefaults
        let key = "hawala_known_addresses"
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            knownAddresses = decoded
        }
        
        // Add some well-known addresses
        knownAddresses["0x0000000000000000000000000000000000000000"] = "Null Address (Burn)"
        knownAddresses["0x000000000000000000000000000000000000dead"] = "Dead Address (Burn)"
    }
    
    private func saveKnownAddresses() {
        let key = "hawala_known_addresses"
        if let data = try? JSONEncoder().encode(knownAddresses) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    private func loadScamDatabase() {
        // Load from UserDefaults
        let key = "hawala_scam_addresses"
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            scamAddresses = decoded
        }
        
        // Add some known scam addresses (examples - would be updated from online source)
        // These are fabricated examples - in production would use real scam database
    }
    
    private func saveScamDatabase() {
        let key = "hawala_scam_addresses"
        if let data = try? JSONEncoder().encode(scamAddresses) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Clipboard Hijack Detection

extension TransactionIntentDecoder {
    /// Check if an address might have been clipboard-hijacked
    func checkClipboardHijack(expected: String, actual: String) -> Bool {
        guard expected != actual else { return false }
        
        // Check if addresses look similar (first/last characters match but middle differs)
        let expPrefix = expected.prefix(6)
        let actPrefix = actual.prefix(6)
        let expSuffix = expected.suffix(4)
        let actSuffix = actual.suffix(4)
        
        // Suspicious if prefix OR suffix matches but the rest is different
        if (expPrefix == actPrefix || expSuffix == actSuffix) && expected != actual {
            return true
        }
        
        return false
    }
    
    /// Validate address checksum (Ethereum)
    func validateEthereumChecksum(_ address: String) -> Bool {
        guard address.hasPrefix("0x"), address.count == 42 else { return false }
        
        let addressWithoutPrefix = String(address.dropFirst(2))
        
        // For lowercase addresses, checksum doesn't apply
        if addressWithoutPrefix == addressWithoutPrefix.lowercased() {
            return true
        }
        
        // Check EIP-55 checksum
        let lowercased = addressWithoutPrefix.lowercased()
        let hash = SHA256.hash(data: Data(lowercased.utf8))
        let hashHex = hash.compactMap { String(format: "%02x", $0) }.joined()
        
        for (i, char) in addressWithoutPrefix.enumerated() {
            let hashChar = hashHex[hashHex.index(hashHex.startIndex, offsetBy: i)]
            let hashValue = Int(String(hashChar), radix: 16) ?? 0
            
            if char.isLetter {
                let shouldBeUppercase = hashValue >= 8
                let isUppercase = char.isUppercase
                if shouldBeUppercase != isUppercase {
                    return false
                }
            }
        }
        
        return true
    }
}
