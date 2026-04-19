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
    public var providerName: String? = nil
    public var secondaryTxHash: String? = nil
    public var secondaryChainId: String? = nil
    public var detailNote: String? = nil
    public var externalActionTitle: String? = nil
    public var externalActionURL: URL? = nil
    
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
        counterparty: String? = nil,
        providerName: String? = nil,
        secondaryTxHash: String? = nil,
        secondaryChainId: String? = nil,
        detailNote: String? = nil,
        externalActionTitle: String? = nil,
        externalActionURL: URL? = nil
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
        self.providerName = providerName
        self.secondaryTxHash = secondaryTxHash
        self.secondaryChainId = secondaryChainId
        self.detailNote = detailNote
        self.externalActionTitle = externalActionTitle
        self.externalActionURL = externalActionURL
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
        return Self.explorerURL(for: chain, txHash: hash)
    }

    public var secondaryExplorerURL: URL? {
        guard let hash = secondaryTxHash, let chain = secondaryChainId else { return nil }
        return Self.explorerURL(for: chain, txHash: hash)
    }
    
    /// Get a color for the transaction type
    public var typeColor: TransactionTypeColor {
        switch type.lowercased() {
        case "receive":
            return .receive
        case "send":
            return .send
        case "swap", "bridge":
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
        case "pending", "processing", "arriving", "in transit":
            return .pending
        case "failed":
            return .failed
        default:
            return .neutral
        }
    }

    private static func explorerURL(for chain: String, txHash: String) -> URL? {
        switch chain {
        case "bitcoin":
            return URL(string: "https://mempool.space/tx/\(txHash)")
        case "bitcoin-testnet":
            return URL(string: "https://mempool.space/testnet/tx/\(txHash)")
        case "litecoin":
            return URL(string: "https://blockchair.com/litecoin/transaction/\(txHash)")
        case "ethereum":
            return URL(string: "https://etherscan.io/tx/\(txHash)")
        case "ethereum-sepolia":
            return URL(string: "https://sepolia.etherscan.io/tx/\(txHash)")
        case "bnb", "bsc":
            return URL(string: "https://bscscan.com/tx/\(txHash)")
        case "polygon":
            return URL(string: "https://polygonscan.com/tx/\(txHash)")
        case "arbitrum":
            return URL(string: "https://arbiscan.io/tx/\(txHash)")
        case "optimism":
            return URL(string: "https://optimistic.etherscan.io/tx/\(txHash)")
        case "avalanche":
            return URL(string: "https://snowtrace.io/tx/\(txHash)")
        case "base":
            return URL(string: "https://basescan.org/tx/\(txHash)")
        case "fantom":
            return URL(string: "https://ftmscan.com/tx/\(txHash)")
        case "solana", "solana-devnet":
            return URL(string: "https://solscan.io/tx/\(txHash)")
        case "xrp", "xrp-testnet":
            return URL(string: "https://xrpscan.com/tx/\(txHash)")
        default:
            return nil
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

// MARK: - Transaction Date Range Filter (ROADMAP-18 E6)

/// Date range options for filtering transaction history
public enum TransactionDateRange: String, CaseIterable, Identifiable {
    case all = "All Time"
    case today = "Today"
    case week = "Last 7 Days"
    case month = "Last 30 Days"
    case quarter = "Last 90 Days"
    case year = "Last Year"

    public var id: String { rawValue }
    public var label: String { rawValue }

    /// Returns the cutoff date for this range, or nil for `.all`.
    public var cutoffDate: Date? {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .all: return nil
        case .today: return cal.startOfDay(for: now)
        case .week: return cal.date(byAdding: .day, value: -7, to: now)
        case .month: return cal.date(byAdding: .day, value: -30, to: now)
        case .quarter: return cal.date(byAdding: .day, value: -90, to: now)
        case .year: return cal.date(byAdding: .year, value: -1, to: now)
        }
    }
}

// MARK: - Failed Transaction Error Reasons (ROADMAP-18 E10)

/// Provides human-readable explanations for common transaction failure reasons.
public enum TransactionFailureReason {
    /// Analyze a failed transaction's status string and return a user-friendly explanation.
    public static func explanation(
        status: String,
        chainId: String?,
        fee: String?
    ) -> TransactionFailureExplanation? {
        guard status.lowercased() == "failed" else { return nil }

        // Check for gas-related failures
        if let feeStr = fee, feeStr.lowercased().contains("out of gas") {
            return TransactionFailureExplanation(
                reason: "Ran out of gas",
                explanation: "The transaction used all available gas before completing. Try again with a higher gas limit.",
                suggestion: "Increase gas limit and retry",
                icon: "fuelpump.exclamationmark.fill"
            )
        }

        // Chain-specific default explanations
        let isEVM = chainId == "ethereum" || chainId == "ethereum-sepolia" || chainId == "bnb" || chainId == "polygon"

        if isEVM {
            return TransactionFailureExplanation(
                reason: "Transaction Failed",
                explanation: "The contract execution reverted or the transaction ran out of gas. This can happen when conditions change between submission and execution.",
                suggestion: "Check contract conditions and retry with higher gas",
                icon: "xmark.octagon.fill"
            )
        }

        return TransactionFailureExplanation(
            reason: "Transaction Failed",
            explanation: "The transaction could not be completed by the network. This may be due to insufficient funds, an invalid address, or network issues.",
            suggestion: "Verify details and try again",
            icon: "xmark.octagon.fill"
        )
    }
}

/// Structured explanation for a failed transaction.
public struct TransactionFailureExplanation {
    public let reason: String
    public let explanation: String
    public let suggestion: String
    public let icon: String
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
