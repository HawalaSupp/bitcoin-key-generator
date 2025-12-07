import Foundation

// MARK: - Shared Transaction Entry for Display

/// A transaction entry for display in the UI across all views
public struct HawalaTransactionEntry: Identifiable, Equatable {
    public let id: String
    public let type: String // "Receive", "Send", "Swap"
    public let asset: String // "Bitcoin", "Ethereum", etc.
    public let amountDisplay: String // "+0.005 BTC" or "-1.25 ETH"
    public let status: String // "Confirmed", "Pending", "Failed"
    public let timestamp: String // Human readable "Dec 7, 2025"
    public let sortTimestamp: TimeInterval? // For sorting by date
    public var txHash: String? = nil
    public var chainId: String? = nil
    public var confirmations: Int? = nil
    public var fee: String? = nil
    public var blockNumber: Int? = nil
    public var counterparty: String? = nil // Address sent to/from
    
    public init(
        id: String,
        type: String,
        asset: String,
        amountDisplay: String,
        status: String,
        timestamp: String,
        sortTimestamp: TimeInterval?,
        txHash: String? = nil,
        chainId: String? = nil,
        confirmations: Int? = nil,
        fee: String? = nil,
        blockNumber: Int? = nil,
        counterparty: String? = nil
    ) {
        self.id = id
        self.type = type
        self.asset = asset
        self.amountDisplay = amountDisplay
        self.status = status
        self.timestamp = timestamp
        self.sortTimestamp = sortTimestamp
        self.txHash = txHash
        self.chainId = chainId
        self.confirmations = confirmations
        self.fee = fee
        self.blockNumber = blockNumber
        self.counterparty = counterparty
    }
    
    /// Human-readable confirmations display
    public var confirmationsDisplay: String? {
        guard let confs = confirmations else { return nil }
        if confs >= 6 {
            return "6+ confirmations"
        } else if confs == 1 {
            return "1 confirmation"
        } else {
            return "\(confs) confirmations"
        }
    }
    
    /// Returns the block explorer URL for this transaction
    public var explorerURL: URL? {
        guard let hash = txHash, let chain = chainId else { return nil }
        
        switch chain {
        case "bitcoin":
            return URL(string: "https://mempool.space/tx/\(hash)")
        case "bitcoin-testnet":
            return URL(string: "https://mempool.space/testnet/tx/\(hash)")
        case "litecoin":
            return URL(string: "https://blockchair.com/litecoin/transaction/\(hash)")
        case "ethereum":
            return URL(string: "https://etherscan.io/tx/\(hash)")
        case "ethereum-sepolia":
            return URL(string: "https://sepolia.etherscan.io/tx/\(hash)")
        case "bnb":
            return URL(string: "https://bscscan.com/tx/\(hash)")
        case "solana":
            return URL(string: "https://solscan.io/tx/\(hash)")
        case "xrp":
            return URL(string: "https://xrpscan.com/tx/\(hash)")
        default:
            return nil
        }
    }
    
    /// Get a color for the transaction type
    public var typeColor: TransactionTypeColor {
        switch type.lowercased() {
        case "receive":
            return .receive
        case "send":
            return .send
        case "swap":
            return .swap
        default:
            return .neutral
        }
    }
    
    /// Get status color
    public var statusColor: TransactionStatusColor {
        switch status.lowercased() {
        case "confirmed":
            return .confirmed
        case "pending", "processing":
            return .pending
        case "failed":
            return .failed
        default:
            return .neutral
        }
    }
}

// MARK: - Color Enums for Transaction Display

public enum TransactionTypeColor {
    case receive
    case send
    case swap
    case neutral
}

public enum TransactionStatusColor {
    case confirmed
    case pending
    case failed
    case neutral
}

// MARK: - Transaction History Response (JSON Format)

/// Response format for transaction history API
public struct TransactionHistoryResponse: Codable {
    public var transactions: [TransactionJSON]?
    public var error: TransactionError?
    
    public init(transactions: [TransactionJSON]? = nil, error: TransactionError? = nil) {
        self.transactions = transactions
        self.error = error
    }
}

/// JSON representation of a transaction
public struct TransactionJSON: Codable {
    public let transactionId: String
    public let date: String // ISO-8601 format
    public let amount: Double
    public let currency: String
    public let type: String // "buy", "sell", "transfer", "receive", "send"
    public let counterparty: String
    public let status: String // "completed", "pending", "failed"
    
    public init(
        transactionId: String,
        date: String,
        amount: Double,
        currency: String,
        type: String,
        counterparty: String,
        status: String
    ) {
        self.transactionId = transactionId
        self.date = date
        self.amount = amount
        self.currency = currency
        self.type = type
        self.counterparty = counterparty
        self.status = status
    }
}

/// Error response for transaction history
public struct TransactionError: Codable {
    public let message: String
    
    public init(message: String) {
        self.message = message
    }
}
