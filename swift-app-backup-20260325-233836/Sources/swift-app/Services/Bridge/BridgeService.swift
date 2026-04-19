import Foundation
import SwiftUI
import Combine
import RustBridge

// MARK: - Bridge Service

/// Service for cross-chain token bridges (Wormhole, LayerZero, Stargate)
/// Aggregates quotes and executes bridge transfers across multiple providers
@MainActor
final class BridgeService: ObservableObject {
    static let shared = BridgeService()
    
    // MARK: - Types
    
    /// Bridge provider enumeration
    enum BridgeProvider: String, CaseIterable, Identifiable, Codable {
        case wormhole = "Wormhole"
        case layerZero = "LayerZero"
        case stargate = "Stargate"
        case across = "Across"
        case hop = "Hop"
        case synapse = "Synapse"
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .wormhole: return "Wormhole"
            case .layerZero: return "LayerZero"
            case .stargate: return "Stargate Finance"
            case .across: return "Across Protocol"
            case .hop: return "Hop Protocol"
            case .synapse: return "Synapse"
            }
        }
        
        var icon: String {
            switch self {
            case .wormhole: return "waveform.circle.fill"
            case .layerZero: return "0.circle.fill"
            case .stargate: return "star.circle.fill"
            case .across: return "arrow.left.arrow.right.circle.fill"
            case .hop: return "hare.fill"
            case .synapse: return "s.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .wormhole: return Color(red: 0.0, green: 0.8, blue: 0.8)
            case .layerZero: return Color(red: 0.2, green: 0.2, blue: 0.2)
            case .stargate: return Color(red: 0.4, green: 0.3, blue: 0.9)
            case .across: return Color(red: 0.0, green: 0.7, blue: 0.4)
            case .hop: return Color(red: 0.9, green: 0.3, blue: 0.5)
            case .synapse: return Color(red: 0.8, green: 0.0, blue: 0.8)
            }
        }

        var dashboardURL: URL? {
            switch self {
            case .wormhole: return URL(string: "https://wormholescan.io")
            case .layerZero: return URL(string: "https://layerzeroscan.com")
            case .stargate: return URL(string: "https://stargate.finance/transfer")
            case .across: return URL(string: "https://app.across.to")
            case .hop: return URL(string: "https://app.hop.exchange")
            case .synapse: return URL(string: "https://synapseprotocol.com")
            }
        }

        var operationalWarning: String {
            switch self {
            case .wormhole:
                return "Wormhole bridges rely on guardian-based message attestation. Destination settlement can lag source confirmation and refunds are provider-dependent."
            case .layerZero:
                return "LayerZero routes depend on cross-chain message delivery. Finality can differ by source and destination chain, so monitor destination settlement before assuming completion."
            case .stargate:
                return "Stargate routes depend on pool liquidity and destination chain availability. Expect fee or ETA changes during volatile periods."
            case .across:
                return "Across routes may use relayer fulfillment and can pause on destination-side issues. If settlement stalls, verify the source tx and relayer status before retrying."
            case .hop:
                return "Hop routes can take longer during destination liquidity or bonder stress. Refund paths are provider-specific and not immediate."
            case .synapse:
                return "Synapse routes depend on bridge inventory and chain health. Large quotes may require extra review if fees or ETA spike materially."
            }
        }
        
        /// Average transfer time in minutes
        func averageTime(from source: SupportedChain, to destination: SupportedChain) -> Int {
            switch self {
            case .wormhole:
                return source == .ethereum ? 15 : 5
            case .layerZero:
                return source == .ethereum || destination == .ethereum ? 10 : 3
            case .stargate:
                return 2
            case .across:
                return 2
            case .hop:
                return 5
            case .synapse:
                return 5
            }
        }
    }
    
    /// Chains supported for bridging
    enum SupportedChain: String, CaseIterable, Identifiable, Codable {
        case ethereum = "ethereum"
        case bsc = "bsc"
        case polygon = "polygon"
        case arbitrum = "arbitrum"
        case optimism = "optimism"
        case avalanche = "avalanche"
        case base = "base"
        case fantom = "fantom"
        case solana = "solana"
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .ethereum: return "Ethereum"
            case .bsc: return "BNB Chain"
            case .polygon: return "Polygon"
            case .arbitrum: return "Arbitrum"
            case .optimism: return "Optimism"
            case .avalanche: return "Avalanche"
            case .base: return "Base"
            case .fantom: return "Fantom"
            case .solana: return "Solana"
            }
        }
        
        var icon: String {
            switch self {
            case .ethereum: return "diamond.fill"
            case .bsc: return "b.circle.fill"
            case .polygon: return "hexagon.fill"
            case .arbitrum: return "a.circle.fill"
            case .optimism: return "o.circle.fill"
            case .avalanche: return "triangle.fill"
            case .base: return "b.square.fill"
            case .fantom: return "f.circle.fill"
            case .solana: return "s.circle.fill"
            }
        }
        
        var chainId: UInt64 {
            switch self {
            case .ethereum: return 1
            case .bsc: return 56
            case .polygon: return 137
            case .arbitrum: return 42161
            case .optimism: return 10
            case .avalanche: return 43114
            case .base: return 8453
            case .fantom: return 250
            case .solana: return 0 // Non-EVM
            }
        }
        
        var nativeSymbol: String {
            switch self {
            case .ethereum, .arbitrum, .optimism, .base: return "ETH"
            case .bsc: return "BNB"
            case .polygon: return "MATIC"
            case .avalanche: return "AVAX"
            case .fantom: return "FTM"
            case .solana: return "SOL"
            }
        }
        
        /// Providers available for this chain
        var availableProviders: [BridgeProvider] {
            switch self {
            case .ethereum, .arbitrum, .optimism, .polygon, .base, .avalanche:
                return [.wormhole, .layerZero, .stargate, .across, .hop]
            case .bsc, .fantom:
                return [.wormhole, .layerZero, .stargate]
            case .solana:
                return [.wormhole]
            }
        }
    }
    
    /// Bridge quote
    struct BridgeQuote: Identifiable, Codable {
        let id: UUID
        let provider: BridgeProvider
        let sourceChain: SupportedChain
        let destinationChain: SupportedChain
        let token: String
        let tokenSymbol: String
        let amountIn: String
        let amountOut: String
        let amountOutMin: String
        let bridgeFee: String
        let bridgeFeeUSD: Double?
        let sourceGasUSD: Double?
        let destinationGasUSD: Double?
        let totalFeeUSD: Double?
        let estimatedTimeMinutes: Int
        let exchangeRate: Double
        let priceImpact: Double?
        let expiresAt: Date
        let transaction: BridgeTransaction?
        
        var isValid: Bool {
            Date() < expiresAt
        }
        
        var formattedAmountIn: String {
            formatAmount(amountIn, decimals: 18)
        }
        
        var formattedAmountOut: String {
            formatAmount(amountOut, decimals: 18)
        }
        
        private func formatAmount(_ amount: String, decimals: Int) -> String {
            guard let value = Decimal(string: amount) else { return "0" }
            let divisor = pow(Decimal(10), decimals)
            let formatted = value / divisor
            return String(format: "%.6f", NSDecimalNumber(decimal: formatted).doubleValue)
        }
    }
    
    /// Transaction data for bridge
    struct BridgeTransaction: Codable {
        let to: String
        let data: String
        let value: String
        let gasLimit: String
        let gasPrice: String?
        let maxFeePerGas: String?
        let maxPriorityFeePerGas: String?
        let chainId: UInt64
    }
    
    /// Bridge transfer status
    enum BridgeStatus: String, Codable {
        case pending = "pending"
        case sourceConfirmed = "source_confirmed"
        case inTransit = "in_transit"
        case waitingDestination = "waiting_destination"
        case completed = "completed"
        case failed = "failed"
        case refunded = "refunded"
        
        var displayName: String {
            switch self {
            case .pending: return "Pending"
            case .sourceConfirmed: return "Confirmed"
            case .inTransit: return "In Transit"
            case .waitingDestination: return "Arriving"
            case .completed: return "Complete"
            case .failed: return "Failed"
            case .refunded: return "Refunded"
            }
        }
        
        var color: Color {
            switch self {
            case .pending: return .orange
            case .sourceConfirmed, .inTransit, .waitingDestination: return .blue
            case .completed: return .green
            case .failed: return .red
            case .refunded: return .purple
            }
        }
        
        var isFinal: Bool {
            self == .completed || self == .failed || self == .refunded
        }
    }
    
    /// Tracked bridge transfer
    struct BridgeTransfer: Identifiable, Codable {
        let id: String
        let provider: BridgeProvider
        let sourceChain: SupportedChain
        let destinationChain: SupportedChain
        let tokenSymbol: String
        let amountIn: String
        let amountOut: String
        let sourceTxHash: String
        var destinationTxHash: String?
        var status: BridgeStatus
        let initiatedAt: Date
        var completedAt: Date?
        let estimatedCompletion: Date
        var lastStatusCheckAt: Date?
        var lastTrackingError: String?
        let minimumAmountOut: String
        let totalFeeUSD: Double?
        let priceImpact: Double?
        let quoteExpiresAt: Date
    }
    
    /// Aggregated bridge quotes
    struct AggregatedQuotes {
        let quotes: [BridgeQuote]
        let bestQuote: BridgeQuote?
        let cheapestQuote: BridgeQuote?
        let fastestQuote: BridgeQuote?
        let fetchedAt: Date
        
        var sortedByOutput: [BridgeQuote] {
            quotes.sorted { (Double($0.amountOut) ?? 0) > (Double($1.amountOut) ?? 0) }
        }
        
        var sortedByFee: [BridgeQuote] {
            quotes.sorted { ($0.totalFeeUSD ?? .infinity) < ($1.totalFeeUSD ?? .infinity) }
        }
        
        var sortedByTime: [BridgeQuote] {
            quotes.sorted { $0.estimatedTimeMinutes < $1.estimatedTimeMinutes }
        }
    }
    
    /// Quote comparison result
    struct QuoteComparison {
        let bestOutputProvider: BridgeProvider
        let bestOutputAmount: String
        let cheapestProvider: BridgeProvider
        let cheapestFeeUSD: Double?
        let fastestProvider: BridgeProvider
        let fastestTimeMinutes: Int
        let outputSpreadPercent: Double
        let feeSpreadUSD: Double
        let timeSpreadMinutes: Int
        let recommendation: String
    }
    
    // MARK: - Published State
    
    @Published var isLoading = false
    @Published var error: String?
    @Published var currentQuotes: AggregatedQuotes?
    @Published var selectedProvider: BridgeProvider?
    @Published var activeTransfers: [BridgeTransfer] = []
    @Published var recentTransfers: [BridgeTransfer] = []
    
    // MARK: - Private Properties
    
    private var quoteCache: [String: (Date, AggregatedQuotes)] = [:]
    private let cacheExpirationSeconds: TimeInterval = 30
    private let activeTransfersKey = "activeTransfers"
    private let recentTransfersKey = "recentBridgeTransfers"
    private let recentTransfersLimit = 25
    
    // MARK: - Initialization
    
    private init() {
        loadActiveTransfers()
        loadRecentTransfers()
    }
    
    // MARK: - Public API
    
    /// Get available providers for a route
    func getProviders(from source: SupportedChain, to destination: SupportedChain) -> [BridgeProvider] {
        let sourceProviders = Set(source.availableProviders)
        let destProviders = Set(destination.availableProviders)
        return Array(sourceProviders.intersection(destProviders))
    }
    
    /// Get bridge quotes from all available providers
    func getQuotes(
        sourceChain: SupportedChain,
        destinationChain: SupportedChain,
        token: String,
        amount: String,
        slippage: Double = 0.5,
        sender: String,
        recipient: String
    ) async throws -> AggregatedQuotes {
        isLoading = true
        error = nil
        currentQuotes = nil
        defer { isLoading = false }
        
        let cacheKey = makeCacheKey(
            source: sourceChain,
            destination: destinationChain,
            token: token,
            amount: amount,
            slippage: slippage
        )
        
        // Check cache
        if let cached = quoteCache[cacheKey],
           Date().timeIntervalSince(cached.0) < cacheExpirationSeconds {
            currentQuotes = cached.1
            return cached.1
        }
        
        do {
            let quotes = try await fetchQuotesFromRust(
                sourceChain: sourceChain,
                destinationChain: destinationChain,
                token: token,
                amount: amount,
                slippage: slippage,
                sender: sender,
                recipient: recipient
            )

            guard !quotes.quotes.isEmpty else {
                throw BridgeError.noQuotesAvailable
            }

            quoteCache[cacheKey] = (Date(), quotes)
            currentQuotes = quotes

            return quotes
        } catch {
            currentQuotes = nil
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            self.error = message
            throw error
        }
    }
    
    /// Get the best quote (highest output)
    func getBestQuote(
        sourceChain: SupportedChain,
        destinationChain: SupportedChain,
        token: String,
        amount: String,
        slippage: Double = 0.5,
        sender: String,
        recipient: String
    ) async throws -> BridgeQuote {
        let quotes = try await getQuotes(
            sourceChain: sourceChain,
            destinationChain: destinationChain,
            token: token,
            amount: amount,
            slippage: slippage,
            sender: sender,
            recipient: recipient
        )
        
        guard let best = quotes.bestQuote else {
            throw BridgeError.noQuotesAvailable
        }
        
        return best
    }
    
    /// Compare quotes from different providers
    func compareQuotes(
        sourceChain: SupportedChain,
        destinationChain: SupportedChain,
        token: String,
        amount: String,
        slippage: Double = 0.5,
        sender: String,
        recipient: String
    ) async throws -> QuoteComparison {
        let quotes = try await getQuotes(
            sourceChain: sourceChain,
            destinationChain: destinationChain,
            token: token,
            amount: amount,
            slippage: slippage,
            sender: sender,
            recipient: recipient
        )
        
        guard !quotes.quotes.isEmpty else {
            throw BridgeError.noQuotesAvailable
        }
        
        let byOutput = quotes.sortedByOutput
        let byFee = quotes.sortedByFee
        let byTime = quotes.sortedByTime
        
        let best = byOutput.first!
        let worst = byOutput.last!
        let cheapest = byFee.first!
        let fastest = byTime.first!
        
        let bestAmount = Double(best.amountOut) ?? 0
        let worstAmount = Double(worst.amountOut) ?? 0
        
        let outputSpread = worstAmount > 0 ? ((bestAmount - worstAmount) / worstAmount) * 100 : 0
        let feeSpread = (byFee.last?.totalFeeUSD ?? 0) - (cheapest.totalFeeUSD ?? 0)
        let timeSpread = (byTime.last?.estimatedTimeMinutes ?? 0) - fastest.estimatedTimeMinutes
        
        return QuoteComparison(
            bestOutputProvider: best.provider,
            bestOutputAmount: best.formattedAmountOut,
            cheapestProvider: cheapest.provider,
            cheapestFeeUSD: cheapest.totalFeeUSD,
            fastestProvider: fastest.provider,
            fastestTimeMinutes: fastest.estimatedTimeMinutes,
            outputSpreadPercent: outputSpread,
            feeSpreadUSD: feeSpread,
            timeSpreadMinutes: timeSpread,
            recommendation: generateRecommendation(quotes: quotes)
        )
    }
    
    /// Execute a bridge transfer
    /// - Parameters:
    ///   - quote: The bridge quote to execute
    ///   - privateKey: The sender's private key for signing
    ///   - fromAddress: The sender's address
    /// - Returns: A BridgeTransfer object for tracking
    func executeBridge(
        quote: BridgeQuote,
        privateKey: String,
        fromAddress: String
    ) async throws -> BridgeTransfer {
        guard let transaction = quote.transaction else {
            throw BridgeError.noTransactionData
        }
        
        // Validate quote hasn't expired
        guard quote.isValid else {
            throw BridgeError.quoteExpired
        }
        
        let chainId = UInt64(transaction.chainId)
        
        // Get nonce for the sender address
        let nonceResult = try HawalaBridge.shared.getNonce(address: fromAddress, chainId: chainId)
        let nonce = nonceResult.nonce
        
        // Parse gas parameters
        let gasLimit = UInt64(transaction.gasLimit) ?? 300000
        
        // Sign the transaction via RustService FFI
        let signedTx: String
        do {
            signedTx = try await Task.detached { [transaction, privateKey, nonce, gasLimit, chainId] in
                try RustService.shared.signEthereumThrowing(
                    recipient: transaction.to,
                    amountWei: transaction.value,
                    chainId: chainId,
                    senderKey: privateKey,
                    nonce: nonce,
                    gasLimit: gasLimit,
                    gasPrice: transaction.gasPrice,
                    maxFeePerGas: transaction.maxFeePerGas,
                    maxPriorityFeePerGas: transaction.maxPriorityFeePerGas,
                    data: transaction.data
                )
            }.value
        } catch {
            throw BridgeError.bridgeFailed("Failed to sign transaction: \(error.localizedDescription)")
        }
        
        // Confirm nonce usage
        try? HawalaBridge.shared.confirmNonce(address: fromAddress, chainId: chainId, nonce: nonce)
        
        // Broadcast the transaction
        let txHash: String
        do {
            txHash = try await TransactionBroadcaster.shared.broadcastEthereumToChain(
                rawTxHex: signedTx,
                chainId: Int(chainId)
            )
        } catch {
            throw BridgeError.bridgeFailed("Failed to broadcast transaction: \(error.localizedDescription)")
        }
        
        // Create transfer tracking record
        let transfer = BridgeTransfer(
            id: UUID().uuidString,
            provider: quote.provider,
            sourceChain: quote.sourceChain,
            destinationChain: quote.destinationChain,
            tokenSymbol: quote.tokenSymbol,
            amountIn: quote.amountIn,
            amountOut: quote.amountOut,
            sourceTxHash: txHash,
            destinationTxHash: nil,
            status: .pending,
            initiatedAt: Date(),
            completedAt: nil,
            estimatedCompletion: Date().addingTimeInterval(TimeInterval(quote.estimatedTimeMinutes * 60)),
            lastStatusCheckAt: nil,
            lastTrackingError: nil,
            minimumAmountOut: quote.amountOutMin,
            totalFeeUSD: quote.totalFeeUSD,
            priceImpact: quote.priceImpact,
            quoteExpiresAt: quote.expiresAt
        )
        
        activeTransfers.append(transfer)
        saveActiveTransfers()
        
        return transfer
    }
    
    /// Track a bridge transfer status
    func trackTransfer(id: String) async throws -> BridgeTransfer {
        guard let index = activeTransfers.firstIndex(where: { $0.id == id }) else {
            throw BridgeError.transferNotFound
        }
        
        var transfer = activeTransfers[index]
        
        // Try to get status from Rust FFI first
        do {
            let updatedTransfer = try await fetchTransferStatusFromRust(transfer: transfer)
            storeUpdatedTransfer(updatedTransfer, replacingAt: index)
            return updatedTransfer
        } catch {
            #if DEBUG
            print("[BridgeService] Rust tracking failed: \(error)")
            #endif
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            transfer.lastStatusCheckAt = Date()
            transfer.lastTrackingError = "Live tracking is temporarily unavailable: \(message)"
        }
        
        storeUpdatedTransfer(transfer, replacingAt: index)
        
        return transfer
    }
    
    /// Fetch transfer status from Rust FFI
    private func fetchTransferStatusFromRust(transfer: BridgeTransfer) async throws -> BridgeTransfer {
        let request = RustTrackTransferRequest(
            source_tx_hash: transfer.sourceTxHash,
            source_chain: transfer.sourceChain.rawValue,
            provider: transfer.provider.rawValue
        )
        
        let jsonData = try JSONEncoder().encode(request)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw BridgeError.providerError("Failed to encode tracking request")
        }
        
        // Call Rust FFI on background thread
        return try await Task.detached { [transfer] in
            try Self.callRustBridgeTrack(jsonString: jsonString, transfer: transfer)
        }.value
    }
    
    /// Call Rust FFI for tracking - nonisolated for background thread
    nonisolated private static func callRustBridgeTrack(
        jsonString: String,
        transfer: BridgeTransfer
    ) throws -> BridgeTransfer {
        guard let resultPtr = hawala_bridge_track_transfer(jsonString) else {
            throw BridgeError.providerError("Failed to call Rust tracking")
        }
        defer { hawala_free_string(UnsafeMutablePointer(mutating: resultPtr)) }
        
        let resultString = String(cString: resultPtr)
        guard let resultData = resultString.data(using: .utf8) else {
            throw BridgeError.providerError("Invalid response from Rust")
        }
        
        let response = try JSONDecoder().decode(RustBridgeApiResponse<RustTransferStatus>.self, from: resultData)
        
        guard response.success, let status = response.data else {
            if let error = response.error {
                throw BridgeError.providerError(error.message)
            }
            throw BridgeError.providerError("No status data returned")
        }
        
        // Convert Rust status to Swift
        return updateTransferWithRustStatus(transfer: transfer, rustStatus: status)
    }
    
    /// Update transfer with Rust status - nonisolated for background thread
    nonisolated private static func updateTransferWithRustStatus(
        transfer: BridgeTransfer,
        rustStatus: RustTransferStatus
    ) -> BridgeTransfer {
        let swiftStatus: BridgeStatus = {
            switch rustStatus.status.lowercased() {
            case "pending": return .pending
            case "source_confirmed", "confirmed": return .sourceConfirmed
            case "in_transit", "transit": return .inTransit
            case "waiting_destination", "arriving": return .waitingDestination
            case "completed", "complete", "success": return .completed
            case "failed", "error": return .failed
            case "refunded", "refund": return .refunded
            default: return .pending
            }
        }()
        
        var updated = transfer
        updated.status = swiftStatus
        updated.destinationTxHash = rustStatus.destination_tx_hash ?? transfer.destinationTxHash
        updated.lastStatusCheckAt = Date()
        updated.lastTrackingError = nil
        
        if swiftStatus == .completed {
            updated.completedAt = Date()
        }
        
        return updated
    }
    
    /// Clear quote cache
    func clearCache() {
        quoteCache.removeAll()
        currentQuotes = nil
    }
    
    /// Remove completed transfers from tracking
    func clearCompletedTransfers() {
        recentTransfers.removeAll { $0.status.isFinal }
        saveRecentTransfers()
        saveActiveTransfers()
    }

    func historyEntries() -> [HawalaTransactionEntry] {
        let transfers = Dictionary(
            (activeTransfers + recentTransfers).map { ($0.id, $0) },
            uniquingKeysWith: { current, _ in current }
        ).values.sorted { $0.initiatedAt > $1.initiatedAt }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        return transfers.map { transfer in
            let status: String = {
                switch transfer.status {
                case .pending:
                    return "Pending"
                case .sourceConfirmed, .inTransit, .waitingDestination:
                    return "Processing"
                case .completed:
                    return "Confirmed"
                case .failed:
                    return "Failed"
                case .refunded:
                    return "Refunded"
                }
            }()

            let fee = transfer.totalFeeUSD.map { "$\(String(format: "%.2f", $0))" }
            let noteParts = [transfer.provider.operationalWarning, transfer.lastTrackingError].compactMap { $0 }

            return HawalaTransactionEntry(
                id: "bridge-\(transfer.id)",
                type: "Bridge",
                asset: transfer.tokenSymbol,
                amountDisplay: "\(formatHistoryAmount(transfer.amountIn)) \(transfer.tokenSymbol)",
                status: status,
                timestamp: formatter.string(from: transfer.initiatedAt),
                sortTimestamp: transfer.initiatedAt.timeIntervalSince1970,
                txHash: transfer.sourceTxHash,
                chainId: transfer.sourceChain.rawValue,
                confirmations: nil,
                fee: fee,
                blockNumber: nil,
                counterparty: "\(transfer.sourceChain.displayName) -> \(transfer.destinationChain.displayName)",
                providerName: transfer.provider.displayName,
                secondaryTxHash: transfer.destinationTxHash,
                secondaryChainId: transfer.destinationChain.rawValue,
                detailNote: noteParts.joined(separator: "\n\n"),
                externalActionTitle: "Open \(transfer.provider.displayName) Dashboard",
                externalActionURL: transfer.provider.dashboardURL
            )
        }
    }
    
    // MARK: - Private Methods
    
    private func makeCacheKey(
        source: SupportedChain,
        destination: SupportedChain,
        token: String,
        amount: String,
        slippage: Double
    ) -> String {
        "\(source.rawValue):\(destination.rawValue):\(token.lowercased()):\(amount):\(Int(slippage * 100))"
    }

    private func formatHistoryAmount(_ amount: String) -> String {
        guard let value = Double(amount) else { return amount }
        return String(format: "%.6f", value / 1e18)
    }
    
    private func fetchQuotesFromRust(
        sourceChain: SupportedChain,
        destinationChain: SupportedChain,
        token: String,
        amount: String,
        slippage: Double,
        sender: String,
        recipient: String
    ) async throws -> AggregatedQuotes {
        let request = RustBridgeQuoteRequest(
            source_chain: sourceChain.rawValue,
            destination_chain: destinationChain.rawValue,
            token: token,
            amount: amount,
            slippage: slippage,
            sender: sender,
            recipient: recipient
        )
        
        let jsonData = try JSONEncoder().encode(request)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw BridgeError.providerError("Failed to encode request")
        }

        do {
            let result: AggregatedQuotes? = try await Task.detached {
                try Self.callRustBridgeQuotes(jsonString: jsonString, sourceChain: sourceChain, destinationChain: destinationChain)
            }.value

            guard let rustQuotes = result, !rustQuotes.quotes.isEmpty else {
                throw BridgeError.noQuotesAvailable
            }

            return rustQuotes
        } catch {
            #if DEBUG
            print("[BridgeService] Rust FFI bridge quote retrieval failed: \(error)")
            #endif
            throw BridgeError.quoteBackendUnavailable(
                "Live bridge quotes are unavailable. Hawala no longer falls back to mock bridge routes. Check Rust bridge routing, provider connectivity, and API configuration."
            )
        }
    }
    
    /// Call Rust FFI for bridge quotes - nonisolated for background thread use
    nonisolated private static func callRustBridgeQuotes(
        jsonString: String,
        sourceChain: SupportedChain,
        destinationChain: SupportedChain
    ) throws -> AggregatedQuotes? {
        guard let resultPtr = hawala_bridge_get_quotes(jsonString) else {
            return nil
        }
        defer { hawala_free_string(UnsafeMutablePointer(mutating: resultPtr)) }
        
        let resultString = String(cString: resultPtr)
        guard let resultData = resultString.data(using: .utf8) else {
            return nil
        }
        
        return try parseQuotesResponse(resultData, sourceChain: sourceChain, destinationChain: destinationChain)
    }
    
    /// Parse Rust response - nonisolated for background thread use
    nonisolated private static func parseQuotesResponse(
        _ data: Data,
        sourceChain: SupportedChain,
        destinationChain: SupportedChain
    ) throws -> AggregatedQuotes? {
        let response = try JSONDecoder().decode(RustBridgeApiResponse<RustAggregatedQuotes>.self, from: data)
        
        guard response.success, let rustQuotes = response.data else {
            if let error = response.error {
                throw BridgeError.providerError(error.message)
            }
            return nil
        }
        
        // Convert Rust quotes to Swift types
        let quotes = rustQuotes.quotes.compactMap { convertRustQuote($0, sourceChain: sourceChain, destinationChain: destinationChain) }
        let best = rustQuotes.best_quote.flatMap { convertRustQuote($0, sourceChain: sourceChain, destinationChain: destinationChain) }
        let cheapest = rustQuotes.cheapest_quote.flatMap { convertRustQuote($0, sourceChain: sourceChain, destinationChain: destinationChain) }
        let fastest = rustQuotes.fastest_quote.flatMap { convertRustQuote($0, sourceChain: sourceChain, destinationChain: destinationChain) }
        
        return AggregatedQuotes(
            quotes: quotes,
            bestQuote: best ?? quotes.max(by: { (Double($0.amountOut) ?? 0) < (Double($1.amountOut) ?? 0) }),
            cheapestQuote: cheapest ?? quotes.min(by: { ($0.totalFeeUSD ?? .infinity) < ($1.totalFeeUSD ?? .infinity) }),
            fastestQuote: fastest ?? quotes.min(by: { $0.estimatedTimeMinutes < $1.estimatedTimeMinutes }),
            fetchedAt: Date()
        )
    }
    
    /// Convert Rust quote to Swift quote - nonisolated for background thread use
    nonisolated private static func convertRustQuote(
        _ rust: RustBridgeQuote,
        sourceChain: SupportedChain,
        destinationChain: SupportedChain
    ) -> BridgeQuote? {
        guard let provider = BridgeProvider.allCases.first(where: { $0.rawValue.lowercased() == rust.provider.lowercased() }) else {
            return nil
        }
        
        let transaction: BridgeTransaction? = rust.transaction.map { tx in
            BridgeTransaction(
                to: tx.to,
                data: tx.data,
                value: tx.value,
                gasLimit: tx.gas_limit ?? "300000",
                gasPrice: tx.gas_price,
                maxFeePerGas: tx.max_fee_per_gas,
                maxPriorityFeePerGas: tx.max_priority_fee_per_gas,
                chainId: tx.chain_id ?? sourceChain.chainId
            )
        }
        
        let expiresAt: Date = {
            if let timestamp = rust.expires_at {
                return Date(timeIntervalSince1970: TimeInterval(timestamp))
            }
            return Date().addingTimeInterval(300)
        }()
        
        return BridgeQuote(
            id: UUID(),
            provider: provider,
            sourceChain: sourceChain,
            destinationChain: destinationChain,
            token: rust.token,
            tokenSymbol: rust.token_symbol ?? getTokenSymbolStatic(rust.token),
            amountIn: rust.amount_in,
            amountOut: rust.amount_out,
            amountOutMin: rust.amount_out_min ?? rust.amount_out,
            bridgeFee: rust.bridge_fee ?? "0",
            bridgeFeeUSD: rust.bridge_fee_usd,
            sourceGasUSD: rust.source_gas_usd,
            destinationGasUSD: rust.destination_gas_usd,
            totalFeeUSD: rust.total_fee_usd,
            estimatedTimeMinutes: rust.estimated_time_minutes ?? provider.averageTime(from: sourceChain, to: destinationChain),
            exchangeRate: rust.exchange_rate ?? 1.0,
            priceImpact: rust.price_impact,
            expiresAt: expiresAt,
            transaction: transaction
        )
    }
    
    /// Get token symbol - nonisolated static for background thread use
    nonisolated private static func getTokenSymbolStatic(_ token: String) -> String {
        if token.lowercased().contains("native") || token.hasPrefix("0xEeee") {
            return "ETH"
        } else if token.count <= 10 {
            return token.uppercased()
        }
        return "TOKEN"
    }
    
    private func getTokenSymbol(_ token: String) -> String {
        if token.lowercased().contains("native") || token.hasPrefix("0xEeee") {
            return "ETH"
        } else if token.count <= 10 {
            return token.uppercased()
        }
        return "TOKEN"
    }
    
    private func generateRecommendation(quotes: AggregatedQuotes) -> String {
        guard let best = quotes.bestQuote,
              let cheapest = quotes.cheapestQuote,
              let fastest = quotes.fastestQuote else {
            return "No quotes available"
        }
        
        // If same provider wins all categories
        if best.provider == cheapest.provider && cheapest.provider == fastest.provider {
            return "\(best.provider.displayName) offers the best rate, lowest fees, and fastest transfer"
        }
        
        // Recommend based on output difference
        let sorted = quotes.sortedByOutput
        if sorted.count >= 2 {
            let bestAmount = Double(sorted[0].amountOut) ?? 0
            let secondAmount = Double(sorted[1].amountOut) ?? 0
            let diff = ((bestAmount - secondAmount) / secondAmount) * 100
            
            if diff > 1.0 {
                return "Use \(best.provider.displayName) for \(String(format: "%.1f", diff))% more tokens"
            }
        }
        
        // Default to fastest if similar rates
        return "Use \(fastest.provider.displayName) for fastest transfer (\(fastest.estimatedTimeMinutes) min)"
    }
    
    private func loadActiveTransfers() {
        if let data = UserDefaults.standard.data(forKey: activeTransfersKey),
           let transfers = try? JSONDecoder().decode([BridgeTransfer].self, from: data) {
            activeTransfers = transfers.filter { !$0.status.isFinal }
        }
    }

    private func loadRecentTransfers() {
        if let data = UserDefaults.standard.data(forKey: recentTransfersKey),
           let transfers = try? JSONDecoder().decode([BridgeTransfer].self, from: data) {
            recentTransfers = transfers.sorted { $0.initiatedAt > $1.initiatedAt }
        }
    }
    
    private func saveActiveTransfers() {
        if let data = try? JSONEncoder().encode(activeTransfers) {
            UserDefaults.standard.set(data, forKey: activeTransfersKey)
        }
    }

    private func saveRecentTransfers() {
        if let data = try? JSONEncoder().encode(recentTransfers) {
            UserDefaults.standard.set(data, forKey: recentTransfersKey)
        }
    }

    private func storeUpdatedTransfer(_ transfer: BridgeTransfer, replacingAt index: Int) {
        if transfer.status.isFinal {
            activeTransfers.remove(at: index)
            archiveTransfer(transfer)
        } else {
            activeTransfers[index] = transfer
        }
        saveActiveTransfers()
    }

    private func archiveTransfer(_ transfer: BridgeTransfer) {
        recentTransfers.removeAll { $0.id == transfer.id }
        recentTransfers.insert(transfer, at: 0)
        if recentTransfers.count > recentTransfersLimit {
            recentTransfers = Array(recentTransfers.prefix(recentTransfersLimit))
        }
        saveRecentTransfers()
    }
}

// MARK: - Errors

enum BridgeError: LocalizedError {
    case noQuotesAvailable
    case noTransactionData
    case routeNotSupported(String, String)
    case insufficientLiquidity
    case amountTooSmall(String)
    case amountTooLarge(String)
    case quoteExpired
    case transferNotFound
    case providerError(String)
    case quoteBackendUnavailable(String)
    case previewModeEnabled(String)
    case bridgeFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noQuotesAvailable:
            return "No bridge quotes available for this route"
        case .noTransactionData:
            return "Quote does not include transaction data"
        case .routeNotSupported(let source, let dest):
            return "Bridge route \(source) → \(dest) is not supported"
        case .insufficientLiquidity:
            return "Insufficient liquidity for this transfer"
        case .amountTooSmall(let min):
            return "Amount below minimum: \(min)"
        case .amountTooLarge(let max):
            return "Amount exceeds maximum: \(max)"
        case .quoteExpired:
            return "Bridge quote has expired"
        case .transferNotFound:
            return "Transfer not found"
        case .providerError(let msg):
            return "Bridge provider error: \(msg)"
        case .quoteBackendUnavailable(let message):
            return message
        case .previewModeEnabled(let message):
            return message
        case .bridgeFailed(let reason):
            return "Bridge execution failed: \(reason)"
        }
    }
}

// MARK: - Rust FFI Types

/// Request for Rust bridge quote
private struct RustBridgeQuoteRequest: Codable {
    let source_chain: String
    let destination_chain: String
    let token: String
    let amount: String
    let slippage: Double
    let sender: String
    let recipient: String
}

/// Rust API response wrapper
private struct RustBridgeApiResponse<T: Codable>: Codable {
    let success: Bool
    let data: T?
    let error: RustBridgeError?
}

/// Rust error type
private struct RustBridgeError: Codable {
    let code: String
    let message: String
}

/// Aggregated quotes from Rust
private struct RustAggregatedQuotes: Codable {
    let quotes: [RustBridgeQuote]
    let best_quote: RustBridgeQuote?
    let cheapest_quote: RustBridgeQuote?
    let fastest_quote: RustBridgeQuote?
}

/// Bridge quote from Rust
private struct RustBridgeQuote: Codable {
    let id: String?
    let provider: String
    let source_chain: String
    let destination_chain: String
    let token: String
    let token_symbol: String?
    let amount_in: String
    let amount_out: String
    let amount_out_min: String?
    let bridge_fee: String?
    let bridge_fee_usd: Double?
    let source_gas_usd: Double?
    let destination_gas_usd: Double?
    let total_fee_usd: Double?
    let estimated_time_minutes: Int?
    let exchange_rate: Double?
    let price_impact: Double?
    let expires_at: Int64?
    let transaction: RustBridgeTransaction?
}

/// Bridge transaction from Rust
private struct RustBridgeTransaction: Codable {
    let to: String
    let data: String
    let value: String
    let gas_limit: String?
    let gas_price: String?
    let max_fee_per_gas: String?
    let max_priority_fee_per_gas: String?
    let chain_id: UInt64?
}

/// Request for tracking transfer
private struct RustTrackTransferRequest: Codable {
    let source_tx_hash: String
    let source_chain: String
    let provider: String
}

/// Transfer status from Rust
private struct RustTransferStatus: Codable {
    let status: String
    let source_tx_hash: String
    let destination_tx_hash: String?
    let source_confirmations: Int?
    let destination_confirmations: Int?
    let estimated_completion: Int64?
    let error: String?
}
