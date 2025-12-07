import Foundation

// MARK: - Fee Priority

enum FeePriority: String, CaseIterable, Identifiable {
    case slow = "Slow"
    case average = "Average"
    case fast = "Fast"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .slow: return "tortoise.fill"
        case .average: return "gauge.medium"
        case .fast: return "hare.fill"
        }
    }
    
    var description: String {
        switch self {
        case .slow: return "~60 min"
        case .average: return "~30 min"
        case .fast: return "~10 min"
        }
    }
    
    var ethDescription: String {
        switch self {
        case .slow: return "~5 min"
        case .average: return "~2 min"
        case .fast: return "~30 sec"
        }
    }
}

// MARK: - Fee Estimate

struct FeeEstimate: Equatable {
    let priority: FeePriority
    let feeRate: Double // sat/vB for BTC, Gwei for ETH
    let estimatedFee: Double // Total fee in native units (BTC/ETH)
    let estimatedTime: String
    let fiatValue: Double? // USD equivalent
    
    var formattedFeeRate: String {
        if feeRate < 1 {
            return String(format: "%.2f", feeRate)
        } else if feeRate < 100 {
            return String(format: "%.1f", feeRate)
        } else {
            return String(format: "%.0f", feeRate)
        }
    }
}

// MARK: - Bitcoin Fee Response (Mempool.space)

struct MempoolFeeEstimates: Codable {
    let fastestFee: Int
    let halfHourFee: Int
    let hourFee: Int
    let economyFee: Int
    let minimumFee: Int
}

// MARK: - Ethereum Gas Response

struct EthGasOracleResponse: Codable {
    let result: EthGasResult
    
    struct EthGasResult: Codable {
        let SafeGasPrice: String
        let ProposeGasPrice: String
        let FastGasPrice: String
        let suggestBaseFee: String?
    }
}

// Alternative: BlockNative style response
struct BlockNativeGasResponse: Codable {
    let blockPrices: [BlockPrice]?
    
    struct BlockPrice: Codable {
        let estimatedPrices: [EstimatedPrice]?
    }
    
    struct EstimatedPrice: Codable {
        let confidence: Int
        let price: Double
        let maxFeePerGas: Double?
        let maxPriorityFeePerGas: Double?
    }
}

// MARK: - Fee Estimator Service

@MainActor
final class FeeEstimator: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = FeeEstimator()
    
    // MARK: - Published State
    
    @Published var bitcoinEstimates: [FeeEstimate] = []
    @Published var ethereumEstimates: [FeeEstimate] = []
    @Published var isLoadingBitcoin = false
    @Published var isLoadingEthereum = false
    @Published var lastUpdated: Date?
    @Published var error: String?
    
    // MARK: - Configuration
    
    private let mempoolMainnetURL = "https://mempool.space/api/v1/fees/recommended"
    private let mempoolTestnetURL = "https://mempool.space/testnet/api/v1/fees/recommended"
    
    // Using public Ethereum gas APIs
    private let etherscanGasURL = "https://api.etherscan.io/api?module=gastracker&action=gasoracle"
    
    // Fallback: Alchemy gas estimation (if API key available)
    private var alchemyGasURL: String {
        let apiKey = APIKeys.alchemyAPIKey
        if !apiKey.isEmpty {
            return "https://eth-mainnet.g.alchemy.com/v2/\(apiKey)"
        }
        return ""
    }
    
    // Cache duration (30 seconds)
    private let cacheDuration: TimeInterval = 30
    
    // Default estimates for when APIs fail
    private let defaultBitcoinEstimates: [FeeEstimate] = [
        FeeEstimate(priority: .slow, feeRate: 1, estimatedFee: 0, estimatedTime: "~60 min", fiatValue: nil),
        FeeEstimate(priority: .average, feeRate: 5, estimatedFee: 0, estimatedTime: "~30 min", fiatValue: nil),
        FeeEstimate(priority: .fast, feeRate: 10, estimatedFee: 0, estimatedTime: "~10 min", fiatValue: nil)
    ]
    
    private let defaultEthereumEstimates: [FeeEstimate] = [
        FeeEstimate(priority: .slow, feeRate: 10, estimatedFee: 0, estimatedTime: "~5 min", fiatValue: nil),
        FeeEstimate(priority: .average, feeRate: 20, estimatedFee: 0, estimatedTime: "~2 min", fiatValue: nil),
        FeeEstimate(priority: .fast, feeRate: 35, estimatedFee: 0, estimatedTime: "~30 sec", fiatValue: nil)
    ]
    
    // MARK: - Initialization
    
    private init() {
        // Load with defaults initially
        bitcoinEstimates = defaultBitcoinEstimates
        ethereumEstimates = defaultEthereumEstimates
    }
    
    // MARK: - Public API
    
    /// Fetch Bitcoin fee estimates from mempool.space
    func fetchBitcoinFees(isTestnet: Bool = true, txSizeVBytes: Int = 140) async {
        // Check cache
        if let lastUpdate = lastUpdated,
           Date().timeIntervalSince(lastUpdate) < cacheDuration,
           !bitcoinEstimates.isEmpty {
            return
        }
        
        isLoadingBitcoin = true
        error = nil
        
        let urlString = isTestnet ? mempoolTestnetURL : mempoolMainnetURL
        
        guard let url = URL(string: urlString) else {
            isLoadingBitcoin = false
            return
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw FeeEstimatorError.invalidResponse
            }
            
            let estimates = try JSONDecoder().decode(MempoolFeeEstimates.self, from: data)
            
            // Calculate total fees based on typical tx size
            let slowFee = Double(estimates.hourFee * txSizeVBytes) / 100_000_000
            let avgFee = Double(estimates.halfHourFee * txSizeVBytes) / 100_000_000
            let fastFee = Double(estimates.fastestFee * txSizeVBytes) / 100_000_000
            
            // Get BTC price for fiat conversion
            let btcPrice = await getBTCPrice()
            
            bitcoinEstimates = [
                FeeEstimate(
                    priority: .slow,
                    feeRate: Double(estimates.hourFee),
                    estimatedFee: slowFee,
                    estimatedTime: "~60 min",
                    fiatValue: btcPrice.map { slowFee * $0 }
                ),
                FeeEstimate(
                    priority: .average,
                    feeRate: Double(estimates.halfHourFee),
                    estimatedFee: avgFee,
                    estimatedTime: "~30 min",
                    fiatValue: btcPrice.map { avgFee * $0 }
                ),
                FeeEstimate(
                    priority: .fast,
                    feeRate: Double(estimates.fastestFee),
                    estimatedFee: fastFee,
                    estimatedTime: "~10 min",
                    fiatValue: btcPrice.map { fastFee * $0 }
                )
            ]
            
            lastUpdated = Date()
            
        } catch {
            self.error = "Failed to fetch Bitcoin fees: \(error.localizedDescription)"
            // Keep default estimates
            if bitcoinEstimates.isEmpty {
                bitcoinEstimates = defaultBitcoinEstimates
            }
        }
        
        isLoadingBitcoin = false
    }
    
    /// Fetch Ethereum gas estimates
    func fetchEthereumFees(gasLimit: UInt64 = 21000) async {
        // Check cache
        if let lastUpdate = lastUpdated,
           Date().timeIntervalSince(lastUpdate) < cacheDuration,
           !ethereumEstimates.isEmpty {
            return
        }
        
        isLoadingEthereum = true
        error = nil
        
        // Try Alchemy first if available
        if !alchemyGasURL.isEmpty {
            if let estimates = await fetchAlchemyGasEstimates(gasLimit: gasLimit) {
                ethereumEstimates = estimates
                lastUpdated = Date()
                isLoadingEthereum = false
                return
            }
        }
        
        // Fallback to public estimate
        await fetchPublicEthereumFees(gasLimit: gasLimit)
        
        isLoadingEthereum = false
    }
    
    /// Get estimate for a specific priority
    func getBitcoinEstimate(for priority: FeePriority) -> FeeEstimate? {
        bitcoinEstimates.first { $0.priority == priority }
    }
    
    func getEthereumEstimate(for priority: FeePriority) -> FeeEstimate? {
        ethereumEstimates.first { $0.priority == priority }
    }
    
    /// Calculate total Bitcoin fee for a specific tx size
    func calculateBitcoinFee(feeRate: Double, txSizeVBytes: Int) -> Double {
        return (feeRate * Double(txSizeVBytes)) / 100_000_000 // Convert to BTC
    }
    
    /// Calculate total Ethereum fee
    func calculateEthereumFee(gasPriceGwei: Double, gasLimit: UInt64) -> Double {
        return (gasPriceGwei * Double(gasLimit)) / 1_000_000_000 // Convert to ETH
    }
    
    // MARK: - Private Methods
    
    private func fetchAlchemyGasEstimates(gasLimit: UInt64) async -> [FeeEstimate]? {
        guard let url = URL(string: alchemyGasURL) else { return nil }
        
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_gasPrice",
            "params": [],
            "id": 1
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            struct GasPriceResponse: Codable {
                let result: String
            }
            
            let response = try JSONDecoder().decode(GasPriceResponse.self, from: data)
            
            // Convert hex to Gwei
            guard let gasPriceWei = UInt64(response.result.dropFirst(2), radix: 16) else {
                return nil
            }
            
            let basePriceGwei = Double(gasPriceWei) / 1_000_000_000
            
            // Create estimates based on current price
            let ethPrice = await getETHPrice()
            
            let slowGwei = basePriceGwei * 0.8
            let avgGwei = basePriceGwei
            let fastGwei = basePriceGwei * 1.3
            
            let slowFee = calculateEthereumFee(gasPriceGwei: slowGwei, gasLimit: gasLimit)
            let avgFee = calculateEthereumFee(gasPriceGwei: avgGwei, gasLimit: gasLimit)
            let fastFee = calculateEthereumFee(gasPriceGwei: fastGwei, gasLimit: gasLimit)
            
            return [
                FeeEstimate(
                    priority: .slow,
                    feeRate: slowGwei,
                    estimatedFee: slowFee,
                    estimatedTime: "~5 min",
                    fiatValue: ethPrice.map { slowFee * $0 }
                ),
                FeeEstimate(
                    priority: .average,
                    feeRate: avgGwei,
                    estimatedFee: avgFee,
                    estimatedTime: "~2 min",
                    fiatValue: ethPrice.map { avgFee * $0 }
                ),
                FeeEstimate(
                    priority: .fast,
                    feeRate: fastGwei,
                    estimatedFee: fastFee,
                    estimatedTime: "~30 sec",
                    fiatValue: ethPrice.map { fastFee * $0 }
                )
            ]
        } catch {
            print("⚠️ Alchemy gas fetch failed: \(error)")
            return nil
        }
    }
    
    private func fetchPublicEthereumFees(gasLimit: UInt64) async {
        // Use a simple estimation based on network conditions
        // In production, you'd use EIP-1559 fee estimation
        
        let ethPrice = await getETHPrice()
        
        // Default reasonable estimates for Sepolia/Mainnet
        let slowGwei: Double = 10
        let avgGwei: Double = 20
        let fastGwei: Double = 35
        
        let slowFee = calculateEthereumFee(gasPriceGwei: slowGwei, gasLimit: gasLimit)
        let avgFee = calculateEthereumFee(gasPriceGwei: avgGwei, gasLimit: gasLimit)
        let fastFee = calculateEthereumFee(gasPriceGwei: fastGwei, gasLimit: gasLimit)
        
        ethereumEstimates = [
            FeeEstimate(
                priority: .slow,
                feeRate: slowGwei,
                estimatedFee: slowFee,
                estimatedTime: "~5 min",
                fiatValue: ethPrice.map { slowFee * $0 }
            ),
            FeeEstimate(
                priority: .average,
                feeRate: avgGwei,
                estimatedFee: avgFee,
                estimatedTime: "~2 min",
                fiatValue: ethPrice.map { avgFee * $0 }
            ),
            FeeEstimate(
                priority: .fast,
                feeRate: fastGwei,
                estimatedFee: fastFee,
                estimatedTime: "~30 sec",
                fiatValue: ethPrice.map { fastFee * $0 }
            )
        ]
        
        lastUpdated = Date()
    }
    
    private func getBTCPrice() async -> Double? {
        // Try to get from PriceService if available
        if let priceService = await getPriceFromCache(symbol: "BTC") {
            return priceService
        }
        return nil
    }
    
    private func getETHPrice() async -> Double? {
        if let priceService = await getPriceFromCache(symbol: "ETH") {
            return priceService
        }
        return nil
    }
    
    private func getPriceFromCache(symbol: String) async -> Double? {
        // Simple price fetch from CoinGecko
        let ids = symbol == "BTC" ? "bitcoin" : "ethereum"
        guard let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=\(ids)&vs_currencies=usd") else {
            return nil
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let priceData = json?[ids] as? [String: Any]
            return priceData?["usd"] as? Double
        } catch {
            return nil
        }
    }
}

// MARK: - Errors

enum FeeEstimatorError: LocalizedError {
    case invalidResponse
    case networkError(Error)
    case parseError
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from fee API"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .parseError: return "Failed to parse fee data"
        }
    }
}
