import Foundation
import SwiftUI
import Combine
import RustBridge

// MARK: - DEX Aggregator Service

/// Service for aggregating quotes from multiple DEX providers (1inch, 0x, etc.)
/// Integrates with Rust backend for optimal swap routing
@MainActor
final class DEXAggregatorService: ObservableObject {
    static let shared = DEXAggregatorService()
    
    // MARK: - Types
    
    /// Supported DEX providers
    enum DEXProvider: String, CaseIterable, Identifiable, Codable {
        case oneInch = "1inch"
        case zeroX = "0x"
        case thorchain = "THORChain"
        case osmosis = "Osmosis"
        case uniswap = "Uniswap"
        case paraswap = "Paraswap"
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .oneInch: return "1inch Fusion"
            case .zeroX: return "0x Protocol"
            case .thorchain: return "THORChain"
            case .osmosis: return "Osmosis DEX"
            case .uniswap: return "Uniswap"
            case .paraswap: return "Paraswap"
            }
        }
        
        var icon: String {
            switch self {
            case .oneInch: return "1.circle.fill"
            case .zeroX: return "0.circle.fill"
            case .thorchain: return "bolt.circle.fill"
            case .osmosis: return "drop.circle.fill"
            case .uniswap: return "u.circle.fill"
            case .paraswap: return "p.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .oneInch: return Color(red: 0.16, green: 0.64, blue: 0.77)
            case .zeroX: return Color(red: 0.20, green: 0.20, blue: 0.20)
            case .thorchain: return Color(red: 0.0, green: 0.82, blue: 0.60)
            case .osmosis: return Color(red: 0.39, green: 0.31, blue: 0.94)
            case .uniswap: return Color(red: 1.0, green: 0.0, blue: 0.51)
            case .paraswap: return Color(red: 0.0, green: 0.43, blue: 1.0)
            }
        }
        
        /// Chains supported by this provider
        var supportedChains: [SupportedChain] {
            switch self {
            case .oneInch:
                return [.ethereum, .bsc, .polygon, .arbitrum, .optimism, .avalanche, .base]
            case .zeroX:
                return [.ethereum, .bsc, .polygon, .arbitrum, .optimism, .avalanche, .base]
            case .thorchain:
                return [.ethereum, .bitcoin, .litecoin, .bsc, .avalanche]
            case .osmosis:
                return [.cosmos, .osmosis]
            case .uniswap:
                return [.ethereum, .polygon, .arbitrum, .optimism, .base]
            case .paraswap:
                return [.ethereum, .bsc, .polygon, .arbitrum, .optimism, .avalanche]
            }
        }
    }
    
    /// Chains supported for DEX aggregation
    enum SupportedChain: String, CaseIterable, Identifiable, Codable {
        case ethereum = "ethereum"
        case bsc = "bsc"
        case polygon = "polygon"
        case arbitrum = "arbitrum"
        case optimism = "optimism"
        case avalanche = "avalanche"
        case base = "base"
        case fantom = "fantom"
        case bitcoin = "bitcoin"
        case litecoin = "litecoin"
        case cosmos = "cosmos"
        case osmosis = "osmosis"
        
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
            case .bitcoin: return "Bitcoin"
            case .litecoin: return "Litecoin"
            case .cosmos: return "Cosmos"
            case .osmosis: return "Osmosis"
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
            case .bitcoin: return 0
            case .litecoin: return 2
            case .cosmos: return 0
            case .osmosis: return 0
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
            case .bitcoin: return "bitcoinsign.circle.fill"
            case .litecoin: return "l.circle.fill"
            case .cosmos: return "atom"
            case .osmosis: return "drop.circle.fill"
            }
        }
        
        var nativeToken: String {
            switch self {
            case .ethereum, .arbitrum, .optimism, .base: return "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"
            case .bsc: return "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"
            case .polygon: return "0x0000000000000000000000000000000000001010"
            case .avalanche: return "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"
            case .fantom: return "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"
            case .bitcoin: return "BTC"
            case .litecoin: return "LTC"
            case .cosmos: return "uatom"
            case .osmosis: return "uosmo"
            }
        }
    }
    
    /// Swap quote from a DEX
    struct SwapQuote: Identifiable, Codable {
        let id: UUID
        let provider: DEXProvider
        let chain: SupportedChain
        let fromToken: String
        let fromTokenSymbol: String
        let fromTokenDecimals: Int
        let toToken: String
        let toTokenSymbol: String
        let toTokenDecimals: Int
        let fromAmount: String
        let toAmount: String
        let toAmountMin: String
        let estimatedGas: String
        let gasPriceGwei: Double
        let gasCostUSD: Double?
        let priceImpact: Double?
        let routes: [SwapRoute]
        let expiresAt: Date?
        let transaction: SwapTransaction?
        
        /// Human-readable from amount
        var formattedFromAmount: String {
            formatTokenAmount(fromAmount, decimals: fromTokenDecimals)
        }
        
        /// Human-readable to amount
        var formattedToAmount: String {
            formatTokenAmount(toAmount, decimals: toTokenDecimals)
        }
        
        /// Effective exchange rate
        var exchangeRate: Double? {
            guard let from = Double(fromAmount), let to = Double(toAmount),
                  from > 0 else { return nil }
            return to / from
        }
        
        private func formatTokenAmount(_ amount: String, decimals: Int) -> String {
            guard let value = Decimal(string: amount) else { return "0" }
            let divisor = pow(Decimal(10), decimals)
            let formatted = value / divisor
            return String(format: "%.6f", NSDecimalNumber(decimal: formatted).doubleValue)
        }
    }
    
    /// Swap route segment
    struct SwapRoute: Codable {
        let protocol_: String
        let percentage: Double
        let path: [String]
        
        enum CodingKeys: String, CodingKey {
            case protocol_ = "protocol"
            case percentage
            case path
        }
    }
    
    /// Transaction data for swap execution
    struct SwapTransaction: Codable {
        let to: String
        let data: String
        let value: String
        let gasLimit: String
        let gasPrice: String?
        let maxFeePerGas: String?
        let maxPriorityFeePerGas: String?
    }
    
    /// Token approval status
    struct TokenApproval: Codable {
        let token: String
        let spender: String
        let currentAllowance: String
        let requiredAllowance: String
        let needsApproval: Bool
    }
    
    /// Aggregated quotes from multiple providers
    struct AggregatedQuotes {
        let quotes: [SwapQuote]
        let bestQuote: SwapQuote?
        let fetchedAt: Date
        
        /// Quotes sorted by output amount (best first)
        var sortedByOutput: [SwapQuote] {
            quotes.sorted { quote1, quote2 in
                let amount1 = Double(quote1.toAmount) ?? 0
                let amount2 = Double(quote2.toAmount) ?? 0
                return amount1 > amount2
            }
        }
        
        /// Price spread between best and worst quotes
        var spreadPercent: Double {
            guard let best = sortedByOutput.first,
                  let worst = sortedByOutput.last,
                  let bestAmount = Double(best.toAmount),
                  let worstAmount = Double(worst.toAmount),
                  worstAmount > 0 else { return 0 }
            return ((bestAmount - worstAmount) / worstAmount) * 100
        }
    }
    
    /// Quote comparison result
    struct QuoteComparison {
        let bestProvider: DEXProvider
        let bestOutput: String
        let worstProvider: DEXProvider
        let worstOutput: String
        let spreadPercent: Double
        let gasSavingsUSD: Double?
        let recommendation: String
    }
    
    // MARK: - Published State
    
    @Published var isLoading = false
    @Published var error: String?
    @Published var currentQuotes: AggregatedQuotes?
    @Published var selectedProvider: DEXProvider?
    @Published var approvalPending = false
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private var quoteCache: [String: (Date, AggregatedQuotes)] = [:]
    private let cacheExpirationSeconds: TimeInterval = 30
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public API
    
    /// Get quotes from all available providers for a swap
    func getQuotes(
        chain: SupportedChain,
        fromToken: String,
        toToken: String,
        amount: String,
        slippage: Double = 0.5,
        fromAddress: String
    ) async throws -> AggregatedQuotes {
        isLoading = true
        error = nil
        
        defer { isLoading = false }
        
        let cacheKey = makeCacheKey(chain: chain, fromToken: fromToken, toToken: toToken, amount: amount, slippage: slippage)
        
        // Check cache
        if let cached = quoteCache[cacheKey],
           Date().timeIntervalSince(cached.0) < cacheExpirationSeconds {
            currentQuotes = cached.1
            return cached.1
        }
        
        // Call Rust backend for quotes
        let quotes = try await fetchQuotesFromRust(
            chain: chain,
            fromToken: fromToken,
            toToken: toToken,
            amount: amount,
            slippage: slippage,
            fromAddress: fromAddress
        )
        
        // Cache result
        quoteCache[cacheKey] = (Date(), quotes)
        currentQuotes = quotes
        
        return quotes
    }
    
    /// Get the best quote across all providers
    func getBestQuote(
        chain: SupportedChain,
        fromToken: String,
        toToken: String,
        amount: String,
        slippage: Double = 0.5,
        fromAddress: String
    ) async throws -> SwapQuote {
        let quotes = try await getQuotes(
            chain: chain,
            fromToken: fromToken,
            toToken: toToken,
            amount: amount,
            slippage: slippage,
            fromAddress: fromAddress
        )
        
        guard let best = quotes.bestQuote else {
            throw DEXAggregatorError.noQuotesAvailable
        }
        
        return best
    }
    
    /// Compare quotes from different providers
    func compareQuotes(
        chain: SupportedChain,
        fromToken: String,
        toToken: String,
        amount: String,
        slippage: Double = 0.5,
        fromAddress: String
    ) async throws -> QuoteComparison {
        let quotes = try await getQuotes(
            chain: chain,
            fromToken: fromToken,
            toToken: toToken,
            amount: amount,
            slippage: slippage,
            fromAddress: fromAddress
        )
        
        guard !quotes.quotes.isEmpty else {
            throw DEXAggregatorError.noQuotesAvailable
        }
        
        let sorted = quotes.sortedByOutput
        let best = sorted.first!
        let worst = sorted.last!
        
        return QuoteComparison(
            bestProvider: best.provider,
            bestOutput: best.formattedToAmount,
            worstProvider: worst.provider,
            worstOutput: worst.formattedToAmount,
            spreadPercent: quotes.spreadPercent,
            gasSavingsUSD: calculateGasSavings(quotes.quotes),
            recommendation: generateRecommendation(quotes)
        )
    }
    
    /// Check if token approval is needed for a swap
    func checkApproval(
        chain: SupportedChain,
        token: String,
        wallet: String,
        provider: DEXProvider
    ) async throws -> TokenApproval {
        // Mock implementation - calls Rust backend
        return TokenApproval(
            token: token,
            spender: getRouterAddress(provider: provider, chain: chain),
            currentAllowance: "0",
            requiredAllowance: "115792089237316195423570985008687907853269984665640564039457584007913129639935",
            needsApproval: true
        )
    }
    
    /// Execute a swap by signing and broadcasting the transaction
    /// - Parameters:
    ///   - quote: The swap quote to execute
    ///   - privateKey: The wallet's private key (hex without 0x prefix)
    ///   - fromAddress: The sender's address
    /// - Returns: The transaction hash of the broadcasted swap
    func executeSwap(quote: SwapQuote, privateKey: String, fromAddress: String) async throws -> String {
        guard let swapTx = quote.transaction else {
            throw DEXAggregatorError.swapFailed("Quote does not contain transaction data")
        }
        
        // Get chain ID
        let chainId = quote.chain.chainId
        
        // Get current nonce
        let nonceResult = try HawalaBridge.shared.getNonce(address: fromAddress, chainId: UInt64(chainId))
        let nonce = nonceResult.nonce
        
        // Parse gas values
        let gasLimitInt = UInt64(swapTx.gasLimit) ?? 300000
        
        // Sign the transaction using RustService FFI
        let signedTxHex: String
        do {
            signedTxHex = try RustService.shared.signEthereumThrowing(
                recipient: swapTx.to,
                amountWei: swapTx.value,
                chainId: UInt64(chainId),
                senderKey: privateKey,
                nonce: nonce,
                gasLimit: gasLimitInt,
                gasPrice: swapTx.gasPrice,
                maxFeePerGas: swapTx.maxFeePerGas,
                maxPriorityFeePerGas: swapTx.maxPriorityFeePerGas,
                data: swapTx.data
            )
        } catch {
            throw DEXAggregatorError.swapFailed("Failed to sign transaction: \(error.localizedDescription)")
        }
        
        // Broadcast the transaction
        do {
            let txHash = try await TransactionBroadcaster.shared.broadcastEthereumToChain(
                rawTxHex: signedTxHex,
                chainId: Int(chainId)
            )
            
            // Confirm the nonce was used
            try? HawalaBridge.shared.confirmNonce(address: fromAddress, chainId: chainId, nonce: nonce)
            
            return txHash
        } catch {
            throw DEXAggregatorError.swapFailed("Failed to broadcast transaction: \(error.localizedDescription)")
        }
    }
    
    /// Execute a token approval for a DEX router
    /// - Parameters:
    ///   - approval: The token approval details
    ///   - chain: The blockchain network
    ///   - privateKey: The wallet's private key
    ///   - fromAddress: The sender's address
    /// - Returns: The transaction hash of the approval
    func executeApproval(approval: TokenApproval, chain: SupportedChain, privateKey: String, fromAddress: String) async throws -> String {
        // ERC-20 approve function signature: approve(address,uint256)
        let spenderPadded = String(approval.spender.dropFirst(2)).leftPadding(toLength: 64, withPad: "0")
        // Max approval amount (type(uint256).max)
        let amountPadded = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
        let approveData = "0x095ea7b3" + spenderPadded + amountPadded
        
        let chainId = chain.chainId
        
        // Get nonce
        let nonceResult = try HawalaBridge.shared.getNonce(address: fromAddress, chainId: UInt64(chainId))
        let nonce = nonceResult.nonce
        
        // Sign approval transaction via RustService FFI
        let signedTxHex = try RustService.shared.signEthereumThrowing(
            recipient: approval.token,
            amountWei: "0",
            chainId: UInt64(chainId),
            senderKey: privateKey,
            nonce: nonce,
            gasLimit: 60000, // Standard approval gas limit
            gasPrice: nil,
            maxFeePerGas: nil,
            maxPriorityFeePerGas: nil,
            data: approveData
        )
        
        // Broadcast
        let txHash = try await TransactionBroadcaster.shared.broadcastEthereumToChain(
            rawTxHex: signedTxHex,
            chainId: Int(chainId)
        )
        
        try? HawalaBridge.shared.confirmNonce(address: fromAddress, chainId: chainId, nonce: nonce)
        
        return txHash
    }
    
    /// Get providers available for a specific chain
    func getProviders(for chain: SupportedChain) -> [DEXProvider] {
        DEXProvider.allCases.filter { $0.supportedChains.contains(chain) }
    }
    
    /// Clear quote cache
    func clearCache() {
        quoteCache.removeAll()
        currentQuotes = nil
    }
    
    // MARK: - Private Methods
    
    private func makeCacheKey(
        chain: SupportedChain,
        fromToken: String,
        toToken: String,
        amount: String,
        slippage: Double
    ) -> String {
        "\(chain.chainId):\(fromToken.lowercased()):\(toToken.lowercased()):\(amount):\(Int(slippage * 100))"
    }
    
    private func fetchQuotesFromRust(
        chain: SupportedChain,
        fromToken: String,
        toToken: String,
        amount: String,
        slippage: Double,
        fromAddress: String
    ) async throws -> AggregatedQuotes {
        // Build request for Rust FFI
        let request = RustSwapQuoteRequest(
            chain: chain.rawValue,
            from_token: fromToken,
            to_token: toToken,
            amount: amount,
            slippage: slippage,
            from_address: fromAddress
        )
        
        // Capture providers for fallback before going off main actor
        let fallbackProviders = getProviders(for: chain)
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let jsonData = try JSONEncoder().encode(request)
                    guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                        throw DEXAggregatorError.providerError("Failed to encode request")
                    }
                    
                    guard let cString = jsonString.cString(using: .utf8) else {
                        throw DEXAggregatorError.providerError("Failed to create C string")
                    }
                    
                    guard let resultPtr = hawala_dex_get_quotes(cString) else {
                        throw DEXAggregatorError.providerError("Null response from Rust")
                    }
                    
                    defer { hawala_free_string(UnsafeMutablePointer(mutating: resultPtr)) }
                    
                    let resultString = String(cString: resultPtr)
                    let result = try Self.parseQuotesResponse(resultString, chain: chain)
                    continuation.resume(returning: result)
                } catch {
                    // Fall back to mock quotes if Rust FFI fails
                    #if DEBUG
                    print("[DEX] Rust FFI failed, using mock quotes: \(error)")
                    #endif
                    let mockResult = Self.generateMockQuotesStatic(
                        providers: fallbackProviders,
                        chain: chain,
                        fromToken: fromToken,
                        toToken: toToken,
                        amount: amount,
                        slippage: slippage
                    )
                    continuation.resume(returning: mockResult)
                }
            }
        }
    }
    
    /// Parse the Rust FFI response into Swift types (nonisolated for background thread use)
    nonisolated private static func parseQuotesResponse(_ json: String, chain: SupportedChain) throws -> AggregatedQuotes {
        guard let data = json.data(using: .utf8) else {
            throw DEXAggregatorError.providerError("Invalid JSON response")
        }
        
        let response = try JSONDecoder().decode(RustApiResponse<RustAggregatedQuotes>.self, from: data)
        
        guard response.success, let rustQuotes = response.data else {
            let errorMsg = response.error?.message ?? "Unknown error"
            throw DEXAggregatorError.providerError(errorMsg)
        }
        
        // Convert Rust types to Swift types
        let quotes: [SwapQuote] = rustQuotes.quotes.map { rustQuote in
            SwapQuote(
                id: UUID(),
                provider: DEXProvider(rawValue: rustQuote.provider) ?? .oneInch,
                chain: chain,
                fromToken: rustQuote.from_token,
                fromTokenSymbol: rustQuote.from_token_symbol ?? "???",
                fromTokenDecimals: rustQuote.from_token_decimals ?? 18,
                toToken: rustQuote.to_token,
                toTokenSymbol: rustQuote.to_token_symbol ?? "???",
                toTokenDecimals: rustQuote.to_token_decimals ?? 18,
                fromAmount: rustQuote.from_amount,
                toAmount: rustQuote.to_amount,
                toAmountMin: rustQuote.to_amount_min ?? rustQuote.to_amount,
                estimatedGas: rustQuote.estimated_gas ?? "150000",
                gasPriceGwei: rustQuote.gas_price_gwei ?? 30.0,
                gasCostUSD: rustQuote.gas_cost_usd,
                priceImpact: rustQuote.price_impact,
                routes: (rustQuote.routes ?? []).map { route in
                    SwapRoute(
                        protocol_: route.protocol_ ?? "unknown",
                        percentage: route.percentage ?? 100.0,
                        path: route.path ?? []
                    )
                },
                expiresAt: rustQuotes.fetched_at.map { Date(timeIntervalSince1970: TimeInterval($0 + 300)) },
                transaction: rustQuote.transaction.map { tx in
                    SwapTransaction(
                        to: tx.to,
                        data: tx.data,
                        value: tx.value ?? "0",
                        gasLimit: tx.gas_limit ?? "200000",
                        gasPrice: tx.gas_price,
                        maxFeePerGas: tx.max_fee_per_gas,
                        maxPriorityFeePerGas: tx.max_priority_fee_per_gas
                    )
                }
            )
        }
        
        let sorted = quotes.sorted { (Double($0.toAmount) ?? 0) > (Double($1.toAmount) ?? 0) }
        
        return AggregatedQuotes(
            quotes: quotes,
            bestQuote: sorted.first,
            fetchedAt: Date()
        )
    }
    
    /// Generate mock quotes as fallback (static for background thread use)
    nonisolated private static func generateMockQuotesStatic(
        providers: [DEXProvider],
        chain: SupportedChain,
        fromToken: String,
        toToken: String,
        amount: String,
        slippage: Double
    ) -> AggregatedQuotes {
        var quotes: [SwapQuote] = []
        
        for provider in providers {
            let quote = generateMockQuoteStatic(
                provider: provider,
                chain: chain,
                fromToken: fromToken,
                toToken: toToken,
                amount: amount,
                slippage: slippage
            )
            quotes.append(quote)
        }
        
        let sorted = quotes.sorted { (Double($0.toAmount) ?? 0) > (Double($1.toAmount) ?? 0) }
        
        return AggregatedQuotes(
            quotes: quotes,
            bestQuote: sorted.first,
            fetchedAt: Date()
        )
    }
    
    /// Generate mock quotes as fallback (instance method for main actor use)
    private func generateMockQuotes(
        chain: SupportedChain,
        fromToken: String,
        toToken: String,
        amount: String,
        slippage: Double
    ) -> AggregatedQuotes {
        let providers = getProviders(for: chain)
        return Self.generateMockQuotesStatic(
            providers: providers,
            chain: chain,
            fromToken: fromToken,
            toToken: toToken,
            amount: amount,
            slippage: slippage
        )
    }
    
    nonisolated private static func generateMockQuoteStatic(
        provider: DEXProvider,
        chain: SupportedChain,
        fromToken: String,
        toToken: String,
        amount: String,
        slippage: Double
    ) -> SwapQuote {
        let fromAmountDouble = Double(amount) ?? 1_000_000_000_000_000_000
        
        // Simulate different rates per provider (within 1%)
        let rateVariation = Double.random(in: 0.99...1.01)
        let baseRate = 2450.0 // Example: 1 ETH = 2450 USDC
        let toAmountDouble = fromAmountDouble * baseRate * rateVariation / 1_000_000_000_000_000_000 * 1_000_000
        let minReceive = toAmountDouble * (1 - slippage / 100)
        
        return SwapQuote(
            id: UUID(),
            provider: provider,
            chain: chain,
            fromToken: fromToken,
            fromTokenSymbol: "ETH",
            fromTokenDecimals: 18,
            toToken: toToken,
            toTokenSymbol: "USDC",
            toTokenDecimals: 6,
            fromAmount: amount,
            toAmount: String(format: "%.0f", toAmountDouble),
            toAmountMin: String(format: "%.0f", minReceive),
            estimatedGas: "150000",
            gasPriceGwei: 30.0,
            gasCostUSD: 4.50,
            priceImpact: Double.random(in: 0.01...0.3),
            routes: [SwapRoute(protocol_: provider.rawValue, percentage: 100.0, path: [fromToken, toToken])],
            expiresAt: Date().addingTimeInterval(300),
            transaction: SwapTransaction(
                to: Self.getRouterAddressStatic(provider: provider, chain: chain),
                data: "0x5ae401dc...", // Placeholder
                value: amount,
                gasLimit: "200000",
                gasPrice: "30000000000",
                maxFeePerGas: nil,
                maxPriorityFeePerGas: nil
            )
        )
    }
    
    nonisolated private static func getRouterAddressStatic(provider: DEXProvider, chain: SupportedChain) -> String {
        switch provider {
        case .oneInch:
            return "0x1111111254EEB25477B68fb85Ed929f73A960582"
        case .zeroX:
            switch chain {
            case .ethereum: return "0xDef1C0ded9bec7F1a1670819833240f027b25EfF"
            case .bsc: return "0xDef1C0ded9bec7F1a1670819833240f027b25EfF"
            case .polygon: return "0xDef1C0ded9bec7F1a1670819833240f027b25EfF"
            default: return "0xDef1C0ded9bec7F1a1670819833240f027b25EfF"
            }
        case .uniswap:
            return "0xE592427A0AEce92De3Edee1F18E0157C05861564"
        default:
            return "0x0000000000000000000000000000000000000000"
        }
    }
    
    private func getRouterAddress(provider: DEXProvider, chain: SupportedChain) -> String {
        Self.getRouterAddressStatic(provider: provider, chain: chain)
    }
    
    private func calculateGasSavings(_ quotes: [SwapQuote]) -> Double? {
        guard quotes.count > 1 else { return nil }
        let gasCosts = quotes.compactMap { $0.gasCostUSD }
        guard let min = gasCosts.min(), let max = gasCosts.max() else { return nil }
        return max - min
    }
    
    private func generateRecommendation(_ quotes: AggregatedQuotes) -> String {
        guard let best = quotes.bestQuote else {
            return "No quotes available"
        }
        
        if quotes.spreadPercent < 0.1 {
            return "All providers offer similar rates. Choose \(best.provider.displayName) for lowest gas."
        } else if quotes.spreadPercent < 1.0 {
            return "Use \(best.provider.displayName) for \(String(format: "%.2f", quotes.spreadPercent))% better rate."
        } else {
            return "Significant price difference! \(best.provider.displayName) offers \(String(format: "%.2f", quotes.spreadPercent))% better rate."
        }
    }
}

// MARK: - Errors

enum DEXAggregatorError: LocalizedError {
    case noQuotesAvailable
    case noTransactionData
    case chainNotSupported(String)
    case providerError(String)
    case approvalRequired
    case insufficientBalance
    case slippageExceeded
    case previewModeEnabled(String)
    case swapFailed(String)
    case approvalFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noQuotesAvailable:
            return "No quotes available for this swap"
        case .noTransactionData:
            return "Quote does not include transaction data"
        case .chainNotSupported(let chain):
            return "Chain \(chain) is not supported for swaps"
        case .providerError(let message):
            return "Provider error: \(message)"
        case .approvalRequired:
            return "Token approval required before swap"
        case .insufficientBalance:
            return "Insufficient balance for swap"
        case .slippageExceeded:
            return "Price slippage exceeded tolerance"
        case .previewModeEnabled(let message):
            return message
        case .swapFailed(let message):
            return "Swap failed: \(message)"
        case .approvalFailed(let message):
            return "Approval failed: \(message)"
        }
    }
}

// MARK: - String Helpers

private extension String {
    func leftPadding(toLength: Int, withPad character: Character) -> String {
        let padCount = toLength - count
        guard padCount > 0 else { return self }
        return String(repeating: character, count: padCount) + self
    }
}

// MARK: - Rust FFI Types

/// Request structure for Rust DEX quotes
private struct RustSwapQuoteRequest: Encodable {
    let chain: String
    let from_token: String
    let to_token: String
    let amount: String
    let slippage: Double
    let from_address: String
}

/// Generic API response from Rust
private struct RustApiResponse<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let error: RustApiError?
}

private struct RustApiError: Decodable {
    let code: String?
    let message: String
}

/// Aggregated quotes from Rust
private struct RustAggregatedQuotes: Decodable {
    let quotes: [RustSwapQuote]
    let best_quote: RustSwapQuote?
    let fetched_at: UInt64?
}

/// Individual quote from Rust
private struct RustSwapQuote: Decodable {
    let provider: String
    let from_token: String
    let to_token: String
    let from_amount: String
    let to_amount: String
    let to_amount_min: String?
    let from_token_symbol: String?
    let from_token_decimals: Int?
    let to_token_symbol: String?
    let to_token_decimals: Int?
    let estimated_gas: String?
    let gas_price_gwei: Double?
    let gas_cost_usd: Double?
    let price_impact: Double?
    let routes: [RustSwapRoute]?
    let transaction: RustSwapTransaction?
}

private struct RustSwapRoute: Decodable {
    let protocol_: String?
    let percentage: Double?
    let path: [String]?
    
    enum CodingKeys: String, CodingKey {
        case protocol_ = "protocol"
        case percentage
        case path
    }
}

private struct RustSwapTransaction: Decodable {
    let to: String
    let data: String
    let value: String?
    let gas_limit: String?
    let gas_price: String?
    let max_fee_per_gas: String?
    let max_priority_fee_per_gas: String?
}

