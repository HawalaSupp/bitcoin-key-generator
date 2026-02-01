import Foundation

// MARK: - Bitcoin Transaction Types

struct BitcoinUTXO: Codable {
    let txid: String
    let vout: Int
    let value: Int64
    let scriptpubkey: String
    let status: UTXOStatus
    
    struct UTXOStatus: Codable {
        let confirmed: Bool
        let blockHeight: Int?
        let blockHash: String?
        let blockTime: Int?
        
        enum CodingKeys: String, CodingKey {
            case confirmed
            case blockHeight = "block_height"
            case blockHash = "block_hash"
            case blockTime = "block_time"
        }
    }
}

struct BitcoinFeeEstimates: Codable {
    let fastestFee: Int
    let halfHourFee: Int
    let hourFee: Int
    let economyFee: Int
    let minimumFee: Int
}

// MARK: - Ethereum Gas Types

enum EthGasSpeed: String, CaseIterable {
    case slow = "Slow"
    case standard = "Standard"
    case fast = "Fast"
    case instant = "Instant"
    
    var multiplier: Double {
        switch self {
        case .slow: return 0.8
        case .standard: return 1.0
        case .fast: return 1.3
        case .instant: return 1.6
        }
    }
    
    var estimatedTime: String {
        switch self {
        case .slow: return "~5 min"
        case .standard: return "~2 min"
        case .fast: return "~30 sec"
        case .instant: return "~15 sec"
        }
    }
    
    var icon: String {
        switch self {
        case .slow: return "tortoise.fill"
        case .standard: return "hare.fill"
        case .fast: return "bolt.fill"
        case .instant: return "bolt.horizontal.fill"
        }
    }
}

struct EthGasEstimates {
    let baseFee: Double // Gwei
    let slowPriorityFee: Double
    let standardPriorityFee: Double
    let fastPriorityFee: Double
    let instantPriorityFee: Double
    
    func gasPriceFor(_ speed: EthGasSpeed) -> Double {
        let priorityFee: Double
        switch speed {
        case .slow: priorityFee = slowPriorityFee
        case .standard: priorityFee = standardPriorityFee
        case .fast: priorityFee = fastPriorityFee
        case .instant: priorityFee = instantPriorityFee
        }
        return baseFee + priorityFee
    }
}

// MARK: - Bitcoin Send Errors

enum BitcoinSendError: LocalizedError {
    case invalidAddress
    case insufficientFunds
    case amountTooLow
    case networkError(String)
    case signingFailed
    case broadcastFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "Invalid Bitcoin address"
        case .insufficientFunds:
            return "Insufficient balance to cover amount + fees"
        case .amountTooLow:
            return "Amount must be greater than dust limit (546 sats)"
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .signingFailed:
            return "Failed to sign transaction"
        case .broadcastFailed(let msg):
            return "Broadcast failed: \(msg)"
        }
    }
}

// MARK: - Encrypted Backup Types

struct EncryptedPackage: Codable {
    let formatVersion: Int
    let createdAt: Date
    let salt: String
    let nonce: String
    let ciphertext: String
    let tag: String
}

enum SecureArchiveError: LocalizedError {
    case invalidEnvelope

    var errorDescription: String? {
        switch self {
        case .invalidEnvelope:
            return "Encrypted backup file is malformed or corrupted."
        }
    }
}

// MARK: - API Response Types

struct EthplorerAddressResponse: Decodable {
    let eth: Eth
    let tokens: [TokenBalance]?

    struct Eth: Decodable {
        let balance: Double

        enum CodingKeys: String, CodingKey {
            case balance
        }
    }

    struct TokenBalance: Decodable {
        let tokenInfo: TokenInfo?
        let balance: Double?
        let rawBalance: String?
    }

    struct TokenInfo: Decodable {
        let symbol: String?
        let decimals: String?
        let address: String?
    }

    enum CodingKeys: String, CodingKey {
        case eth = "ETH"
        case tokens
    }
}

struct XrpScanAccountResponse: Decodable {
    let xrpBalance: String?
    let balance: String?

    enum CodingKeys: String, CodingKey {
        case xrpBalance
        case balance = "Balance"
    }
}

struct RippleDataAccountBalanceResponse: Decodable {
    struct BalanceEntry: Decodable {
        let currency: String
        let value: String
    }

    let result: String?
    let balances: [BalanceEntry]?
    let message: String?

    var xrpBalanceValue: Decimal? {
        guard let entry = balances?.first(where: { $0.currency.uppercased() == "XRP" }) else {
            return nil
        }
        return Decimal(string: entry.value)
    }

    var isAccountMissing: Bool {
        guard let result else { return false }
        if result.lowercased() == "success" { return false }
        if let message = message?.lowercased(), message.contains("not found") {
            return true
        }
        return false
    }
}
