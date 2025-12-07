import Foundation

// MARK: - Fee Estimation Service

/// Centralized service for fetching live fee estimates across all chains
@MainActor
final class FeeEstimationService: ObservableObject {
    static let shared = FeeEstimationService()
    
    // MARK: - Published State
    
    @Published var bitcoinFees: BitcoinFeeEstimate?
    @Published var ethereumFees: EthereumFeeEstimate?
    @Published var litecoinFees: LitecoinFeeEstimate?
    @Published var solanaFees: SolanaFeeEstimate?
    @Published var xrpFees: XRPFeeEstimate?
    @Published var isLoading = false
    @Published var lastUpdated: Date?
    
    // MARK: - Cache
    
    private var lastFetchTime: Date?
    private let cacheDuration: TimeInterval = 30 // 30 seconds
    
    private init() {}
    
    // MARK: - Public API
    
    /// Refresh all fee estimates
    func refreshAll(force: Bool = false) async {
        // Check cache unless forced
        if !force, let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheDuration {
            return
        }
        
        isLoading = true
        
        async let btc = fetchBitcoinFees()
        async let eth = fetchEthereumFees()
        async let ltc = fetchLitecoinFees()
        async let sol = fetchSolanaFees()
        async let xrp = fetchXRPFees()
        
        let (btcResult, ethResult, ltcResult, solResult, xrpResult) = await (btc, eth, ltc, sol, xrp)
        
        bitcoinFees = btcResult
        ethereumFees = ethResult
        litecoinFees = ltcResult
        solanaFees = solResult
        xrpFees = xrpResult
        
        lastFetchTime = Date()
        lastUpdated = Date()
        isLoading = false
    }
    
    // MARK: - Bitcoin Fee Estimation (mempool.space)
    
    func fetchBitcoinFees() async -> BitcoinFeeEstimate? {
        guard let url = URL(string: "https://mempool.space/api/v1/fees/recommended") else {
            return nil
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(MempoolFeeResponse.self, from: data)
            
            return BitcoinFeeEstimate(
                fastest: FeeLevel(
                    satPerByte: response.fastestFee,
                    estimatedMinutes: 10,
                    label: "Fastest"
                ),
                fast: FeeLevel(
                    satPerByte: response.halfHourFee,
                    estimatedMinutes: 30,
                    label: "Fast"
                ),
                medium: FeeLevel(
                    satPerByte: response.hourFee,
                    estimatedMinutes: 60,
                    label: "Medium"
                ),
                slow: FeeLevel(
                    satPerByte: response.economyFee,
                    estimatedMinutes: 120,
                    label: "Economy"
                ),
                minimum: FeeLevel(
                    satPerByte: response.minimumFee,
                    estimatedMinutes: 1440,
                    label: "Minimum"
                )
            )
        } catch {
            print("Bitcoin fee fetch error: \(error)")
            return nil
        }
    }
    
    // MARK: - Ethereum Fee Estimation (etherscan / RPC)
    
    func fetchEthereumFees() async -> EthereumFeeEstimate? {
        // Try Etherscan gas oracle first
        guard let url = URL(string: "https://api.etherscan.io/api?module=gastracker&action=gasoracle") else {
            return nil
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = json["result"] as? [String: Any] else {
                return nil
            }
            
            // Gas prices in Gwei
            let safeGas = Double(result["SafeGasPrice"] as? String ?? "0") ?? 0
            let proposeGas = Double(result["ProposeGasPrice"] as? String ?? "0") ?? 0
            let fastGas = Double(result["FastGasPrice"] as? String ?? "0") ?? 0
            
            // Base fee if available (EIP-1559)
            let baseFee = Double(result["suggestBaseFee"] as? String ?? "0") ?? 0
            
            return EthereumFeeEstimate(
                baseFee: baseFee,
                fast: GasLevel(
                    gasPrice: fastGas,
                    maxPriorityFee: max(2.0, fastGas - baseFee),
                    estimatedSeconds: 15,
                    label: "Fast"
                ),
                medium: GasLevel(
                    gasPrice: proposeGas,
                    maxPriorityFee: max(1.5, proposeGas - baseFee),
                    estimatedSeconds: 60,
                    label: "Medium"
                ),
                slow: GasLevel(
                    gasPrice: safeGas,
                    maxPriorityFee: max(1.0, safeGas - baseFee),
                    estimatedSeconds: 180,
                    label: "Slow"
                )
            )
        } catch {
            print("Ethereum fee fetch error: \(error)")
            return nil
        }
    }
    
    // MARK: - Litecoin Fee Estimation
    
    func fetchLitecoinFees() async -> LitecoinFeeEstimate? {
        // Litecoin fees are relatively stable, use blockchair or estimates
        guard let url = URL(string: "https://api.blockchair.com/litecoin/stats") else {
            return nil
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataDict = json["data"] as? [String: Any] else {
                return nil
            }
            
            // Suggested fee in satoshis per byte
            let suggestedFee = dataDict["suggested_transaction_fee_per_byte_sat"] as? Int ?? 10
            let mempoolTxs = dataDict["mempool_transactions"] as? Int ?? 0
            
            // Adjust based on mempool congestion
            let congestionMultiplier = mempoolTxs > 10000 ? 1.5 : (mempoolTxs > 5000 ? 1.2 : 1.0)
            let baseFee = Double(suggestedFee) * congestionMultiplier
            
            return LitecoinFeeEstimate(
                fast: FeeLevel(
                    satPerByte: Int(baseFee * 2),
                    estimatedMinutes: 10,
                    label: "Fast"
                ),
                medium: FeeLevel(
                    satPerByte: Int(baseFee),
                    estimatedMinutes: 30,
                    label: "Medium"
                ),
                slow: FeeLevel(
                    satPerByte: max(1, Int(baseFee * 0.5)),
                    estimatedMinutes: 120,
                    label: "Slow"
                )
            )
        } catch {
            print("Litecoin fee fetch error: \(error)")
            // Return default estimates
            return LitecoinFeeEstimate(
                fast: FeeLevel(satPerByte: 20, estimatedMinutes: 10, label: "Fast"),
                medium: FeeLevel(satPerByte: 10, estimatedMinutes: 30, label: "Medium"),
                slow: FeeLevel(satPerByte: 5, estimatedMinutes: 120, label: "Slow")
            )
        }
    }
    
    // MARK: - Solana Fee Estimation
    
    func fetchSolanaFees() async -> SolanaFeeEstimate? {
        guard let url = URL(string: "https://api.mainnet-beta.solana.com") else {
            return nil
        }
        
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getRecentPrioritizationFees",
            "params": [[]]
        ]
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["result"] as? [[String: Any]] else {
                return defaultSolanaFees()
            }
            
            // Calculate average priority fee from recent slots
            let fees = results.compactMap { $0["prioritizationFee"] as? Int }
            let avgFee = fees.isEmpty ? 0 : fees.reduce(0, +) / fees.count
            let maxFee = fees.max() ?? 0
            
            // Base fee is 5000 lamports (0.000005 SOL)
            let baseFee: UInt64 = 5000
            
            return SolanaFeeEstimate(
                baseFee: baseFee,
                priorityFee: PriorityFeeLevel(
                    low: UInt64(max(0, avgFee / 2)),
                    medium: UInt64(avgFee),
                    high: UInt64(max(avgFee * 2, maxFee)),
                    label: "Priority"
                )
            )
        } catch {
            print("Solana fee fetch error: \(error)")
            return defaultSolanaFees()
        }
    }
    
    private func defaultSolanaFees() -> SolanaFeeEstimate {
        return SolanaFeeEstimate(
            baseFee: 5000,
            priorityFee: PriorityFeeLevel(
                low: 1000,
                medium: 10000,
                high: 100000,
                label: "Priority"
            )
        )
    }
    
    // MARK: - XRP Fee Estimation
    
    func fetchXRPFees() async -> XRPFeeEstimate? {
        guard let url = URL(string: "https://s1.ripple.com:51234") else {
            return defaultXRPFees()
        }
        
        let payload: [String: Any] = [
            "method": "fee",
            "params": [[:]]
        ]
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = json["result"] as? [String: Any],
                  let drops = result["drops"] as? [String: Any] else {
                return defaultXRPFees()
            }
            
            // Parse fee values (in drops)
            let openLedgerFee = UInt64(drops["open_ledger_fee"] as? String ?? "12") ?? 12
            let minimumFee = UInt64(drops["minimum_fee"] as? String ?? "10") ?? 10
            let medianFee = UInt64(drops["median_fee"] as? String ?? "12") ?? 12
            
            // Parse queue info
            let currentQueue = result["current_queue_size"] as? Int ?? 0
            
            return XRPFeeEstimate(
                openLedgerFee: openLedgerFee,
                minimumFee: minimumFee,
                medianFee: medianFee,
                currentQueue: currentQueue
            )
        } catch {
            print("XRP fee fetch error: \(error)")
            return defaultXRPFees()
        }
    }
    
    private func defaultXRPFees() -> XRPFeeEstimate {
        return XRPFeeEstimate(
            openLedgerFee: 12,
            minimumFee: 10,
            medianFee: 12,
            currentQueue: 0
        )
    }
    
    // MARK: - Fee Calculation Helpers
    
    /// Calculate estimated BTC transaction fee
    func estimateBitcoinFee(inputs: Int, outputs: Int, feeLevel: FeeLevel) -> Double {
        // P2WPKH: ~68 vbytes per input, ~31 vbytes per output, ~10 vbytes overhead
        let estimatedVbytes = (inputs * 68) + (outputs * 31) + 10
        let feeSats = estimatedVbytes * feeLevel.satPerByte
        return Double(feeSats) / 100_000_000.0
    }
    
    /// Calculate estimated ETH transaction fee
    func estimateEthereumFee(gasLimit: UInt64, gasLevel: GasLevel) -> Double {
        // Fee = gasLimit * gasPrice (in Gwei)
        let feeGwei = Double(gasLimit) * gasLevel.gasPrice
        return feeGwei / 1_000_000_000.0 // Convert Gwei to ETH
    }
    
    /// Calculate estimated Solana fee
    func estimateSolanaFee(priorityLevel: PriorityFeeLevel, useHigh: Bool = false) -> Double {
        let baseFee: UInt64 = 5000
        let priorityFee = useHigh ? priorityLevel.high : priorityLevel.medium
        let totalLamports = baseFee + priorityFee
        return Double(totalLamports) / 1_000_000_000.0 // Convert lamports to SOL
    }
}

// MARK: - Fee Models

struct BitcoinFeeEstimate {
    let fastest: FeeLevel
    let fast: FeeLevel
    let medium: FeeLevel
    let slow: FeeLevel
    let minimum: FeeLevel
    
    var recommended: FeeLevel { medium }
    
    var allLevels: [FeeLevel] {
        [fastest, fast, medium, slow, minimum]
    }
}

struct LitecoinFeeEstimate {
    let fast: FeeLevel
    let medium: FeeLevel
    let slow: FeeLevel
    
    var recommended: FeeLevel { medium }
    
    var allLevels: [FeeLevel] {
        [fast, medium, slow]
    }
}

struct FeeLevel: Identifiable {
    let id = UUID()
    let satPerByte: Int
    let estimatedMinutes: Int
    let label: String
    
    var formattedRate: String {
        "\(satPerByte) sat/vB"
    }
    
    var formattedTime: String {
        if estimatedMinutes < 60 {
            return "~\(estimatedMinutes) min"
        } else if estimatedMinutes < 1440 {
            return "~\(estimatedMinutes / 60) hr"
        } else {
            return "~\(estimatedMinutes / 1440) day"
        }
    }
}

struct EthereumFeeEstimate {
    let baseFee: Double // Gwei
    let fast: GasLevel
    let medium: GasLevel
    let slow: GasLevel
    
    var recommended: GasLevel { medium }
    
    var allLevels: [GasLevel] {
        [fast, medium, slow]
    }
}

struct GasLevel: Identifiable {
    let id = UUID()
    let gasPrice: Double // Gwei
    let maxPriorityFee: Double // Gwei (for EIP-1559)
    let estimatedSeconds: Int
    let label: String
    
    var formattedPrice: String {
        String(format: "%.1f Gwei", gasPrice)
    }
    
    var formattedTime: String {
        if estimatedSeconds < 60 {
            return "~\(estimatedSeconds)s"
        } else {
            return "~\(estimatedSeconds / 60) min"
        }
    }
}

struct SolanaFeeEstimate {
    let baseFee: UInt64 // lamports
    let priorityFee: PriorityFeeLevel
    
    var totalFeeLamports: UInt64 {
        baseFee + priorityFee.medium
    }
    
    var formattedBaseFee: String {
        let sol = Double(baseFee) / 1_000_000_000.0
        return String(format: "%.6f SOL", sol)
    }
}

struct PriorityFeeLevel {
    let low: UInt64
    let medium: UInt64
    let high: UInt64
    let label: String
    
    func formatted(_ level: UInt64) -> String {
        let sol = Double(level) / 1_000_000_000.0
        return String(format: "%.6f SOL", sol)
    }
}

struct XRPFeeEstimate {
    let openLedgerFee: UInt64 // drops
    let minimumFee: UInt64 // drops
    let medianFee: UInt64 // drops
    let currentQueue: Int
    
    var formattedOpenLedger: String {
        let xrp = Double(openLedgerFee) / 1_000_000.0
        return String(format: "%.6f XRP", xrp)
    }
    
    var formattedMinimum: String {
        let xrp = Double(minimumFee) / 1_000_000.0
        return String(format: "%.6f XRP", xrp)
    }
    
    var recommendedFee: UInt64 {
        // Use median or open ledger fee, whichever is higher
        max(medianFee, openLedgerFee)
    }
}

// MARK: - API Response Models

private struct MempoolFeeResponse: Decodable {
    let fastestFee: Int
    let halfHourFee: Int
    let hourFee: Int
    let economyFee: Int
    let minimumFee: Int
}
