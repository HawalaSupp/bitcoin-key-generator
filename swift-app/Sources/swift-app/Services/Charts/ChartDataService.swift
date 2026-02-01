import SwiftUI
import Charts

/// Token price chart service for fetching and displaying historical data
@MainActor
final class ChartDataService: ObservableObject {
    static let shared = ChartDataService()
    
    @Published var isLoading = false
    @Published var error: String?
    @Published var chartData: ChartData?
    @Published var tokenInfo: TokenInfo?
    
    private init() {}
    
    // MARK: - Types
    
    enum TimeRange: String, CaseIterable {
        case hour1 = "1H"
        case hour24 = "24H"
        case day7 = "7D"
        case day30 = "30D"
        case day90 = "90D"
        case year1 = "1Y"
        case all = "ALL"
        
        var days: String {
            switch self {
            case .hour1, .hour24: return "1"
            case .day7: return "7"
            case .day30: return "30"
            case .day90: return "90"
            case .year1: return "365"
            case .all: return "max"
            }
        }
    }
    
    struct PricePoint: Identifiable {
        let id = UUID()
        let timestamp: Date
        let price: Double
    }
    
    struct VolumePoint: Identifiable {
        let id = UUID()
        let timestamp: Date
        let volume: Double
    }
    
    struct ChartData {
        let tokenId: String
        let currency: String
        let range: TimeRange
        var prices: [PricePoint]
        var volumes: [VolumePoint]
        
        var currentPrice: Double? { prices.last?.price }
        var startPrice: Double? { prices.first?.price }
        var highPrice: Double? { prices.map { $0.price }.max() }
        var lowPrice: Double? { prices.map { $0.price }.min() }
        
        var priceChange: Double? {
            guard let start = startPrice, let current = currentPrice else { return nil }
            return current - start
        }
        
        var priceChangePercent: Double? {
            guard let start = startPrice, let current = currentPrice, start > 0 else { return nil }
            return ((current - start) / start) * 100
        }
        
        var isPriceUp: Bool { (priceChange ?? 0) > 0 }
    }
    
    struct TokenInfo {
        let id: String
        let symbol: String
        let name: String
        let currentPrice: Double
        let priceChange24h: Double
        let priceChangePercent24h: Double
        let marketCap: Double
        let marketCapRank: Int?
        let totalVolume: Double
        let high24h: Double
        let low24h: Double
        let ath: Double
        let athChangePercent: Double
        let atl: Double
        let atlChangePercent: Double
        let circulatingSupply: Double
        let totalSupply: Double?
        let maxSupply: Double?
        let imageUrl: String?
    }
    
    // MARK: - Known Token IDs
    
    static let knownTokenIds: [String: String] = [
        "BTC": "bitcoin",
        "ETH": "ethereum",
        "USDT": "tether",
        "BNB": "binancecoin",
        "SOL": "solana",
        "XRP": "ripple",
        "USDC": "usd-coin",
        "ADA": "cardano",
        "AVAX": "avalanche-2",
        "DOGE": "dogecoin",
        "DOT": "polkadot",
        "MATIC": "matic-network",
        "LINK": "chainlink",
        "UNI": "uniswap",
        "LTC": "litecoin",
        "ATOM": "cosmos",
        "NEAR": "near",
        "APT": "aptos",
        "SUI": "sui",
        "ARB": "arbitrum",
        "OP": "optimism",
        "RUNE": "thorchain",
    ]
    
    // MARK: - API
    
    func fetchChartData(tokenId: String, currency: String = "usd", range: TimeRange = .day7) async {
        isLoading = true
        error = nil
        
        let urlString = "https://api.coingecko.com/api/v3/coins/\(tokenId)/market_chart?vs_currency=\(currency)&days=\(range.days)"
        
        guard let url = URL(string: urlString) else {
            error = "Invalid URL"
            isLoading = false
            return
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                error = "API request failed"
                isLoading = false
                return
            }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            var chartData = ChartData(tokenId: tokenId, currency: currency, range: range, prices: [], volumes: [])
            
            // Parse prices
            if let pricesArray = json?["prices"] as? [[Double]] {
                chartData.prices = pricesArray.compactMap { arr in
                    guard arr.count >= 2 else { return nil }
                    return PricePoint(
                        timestamp: Date(timeIntervalSince1970: arr[0] / 1000),
                        price: arr[1]
                    )
                }
            }
            
            // Parse volumes
            if let volumesArray = json?["total_volumes"] as? [[Double]] {
                chartData.volumes = volumesArray.compactMap { arr -> VolumePoint? in
                    guard arr.count >= 2 else { return nil }
                    return VolumePoint(
                        timestamp: Date(timeIntervalSince1970: arr[0] / 1000),
                        volume: arr[1]
                    )
                }
            }
            
            self.chartData = chartData
            isLoading = false
            
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }
    
    func fetchTokenInfo(tokenId: String) async {
        let urlString = "https://api.coingecko.com/api/v3/coins/\(tokenId)?localization=false&tickers=false&community_data=false&developer_data=false"
        
        guard let url = URL(string: urlString) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            guard let marketData = json?["market_data"] as? [String: Any] else { return }
            
            let getValue: ([String: Any], String, String) -> Double = { dict, key, currency in
                (dict[key] as? [String: Double])?[currency] ?? 0
            }
            
            tokenInfo = TokenInfo(
                id: json?["id"] as? String ?? "",
                symbol: json?["symbol"] as? String ?? "",
                name: json?["name"] as? String ?? "",
                currentPrice: getValue(marketData, "current_price", "usd"),
                priceChange24h: marketData["price_change_24h"] as? Double ?? 0,
                priceChangePercent24h: marketData["price_change_percentage_24h"] as? Double ?? 0,
                marketCap: getValue(marketData, "market_cap", "usd"),
                marketCapRank: json?["market_cap_rank"] as? Int,
                totalVolume: getValue(marketData, "total_volume", "usd"),
                high24h: getValue(marketData, "high_24h", "usd"),
                low24h: getValue(marketData, "low_24h", "usd"),
                ath: getValue(marketData, "ath", "usd"),
                athChangePercent: getValue(marketData, "ath_change_percentage", "usd"),
                atl: getValue(marketData, "atl", "usd"),
                atlChangePercent: getValue(marketData, "atl_change_percentage", "usd"),
                circulatingSupply: marketData["circulating_supply"] as? Double ?? 0,
                totalSupply: marketData["total_supply"] as? Double,
                maxSupply: marketData["max_supply"] as? Double,
                imageUrl: (json?["image"] as? [String: String])?["large"]
            )
        } catch {
            print("Failed to fetch token info: \(error)")
        }
    }
    
    // MARK: - Helpers
    
    static func tokenId(for symbol: String) -> String? {
        knownTokenIds[symbol.uppercased()]
    }
    
    static func formatPrice(_ price: Double, currency: String = "USD") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        
        if price < 1 {
            formatter.maximumFractionDigits = 6
        } else if price < 100 {
            formatter.maximumFractionDigits = 4
        } else {
            formatter.maximumFractionDigits = 2
        }
        
        return formatter.string(from: NSNumber(value: price)) ?? "$\(price)"
    }
    
    static func formatChange(_ change: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.positivePrefix = "+"
        return (formatter.string(from: NSNumber(value: change)) ?? "\(change)") + "%"
    }
    
    static func formatLargeNumber(_ number: Double) -> String {
        let absNumber = abs(number)
        
        if absNumber >= 1_000_000_000_000 {
            return String(format: "$%.2fT", number / 1_000_000_000_000)
        } else if absNumber >= 1_000_000_000 {
            return String(format: "$%.2fB", number / 1_000_000_000)
        } else if absNumber >= 1_000_000 {
            return String(format: "$%.2fM", number / 1_000_000)
        } else if absNumber >= 1_000 {
            return String(format: "$%.2fK", number / 1_000)
        } else {
            return String(format: "$%.2f", number)
        }
    }
}
