import Foundation

// MARK: - Sparkline Cache

/// Manages sparkline data fetching with proper caching and rate limiting
/// to avoid CoinGecko API issues
@MainActor
final class SparklineCache: ObservableObject {
    static let shared = SparklineCache()
    
    /// Cached sparkline data per chain
    @Published var sparklines: [String: [Double]] = [:]
    
    /// Whether a fetch is currently in progress
    @Published var isFetching = false
    
    /// Last fetch time per chain (for cache invalidation)
    private var lastFetchTime: [String: Date] = [:]
    
    /// Cache duration - 5 minutes
    private let cacheDuration: TimeInterval = 300
    
    /// Delay between API calls to respect rate limits (3 seconds for free tier)
    private let requestDelay: UInt64 = 3_000_000_000
    
    /// Current fetch task
    private var fetchTask: Task<Void, Never>?
    
    /// Coin ID mappings for CoinGecko
    private let coinMappings: [String: String] = [
        "bitcoin": "bitcoin",
        "ethereum": "ethereum", 
        "litecoin": "litecoin",
        "solana": "solana",
        "xrp": "ripple",
        "bnb": "binancecoin",
        "monero": "monero"
    ]
    
    /// CoinGecko API key (optional, for pro tier)
    var apiKey: String?
    
    private init() {
        loadFromDisk()
    }
    
    // MARK: - Public API
    
    /// Fetch sparklines for all chains, using cache when valid
    func fetchAllSparklines(force: Bool = false) {
        // Cancel any existing fetch
        fetchTask?.cancel()
        
        fetchTask = Task { [weak self] in
            guard let self = self else { return }
            
            await MainActor.run { self.isFetching = true }
            
            for (chainId, coinId) in coinMappings {
                // Check if cancelled
                if Task.isCancelled { break }
                
                // Skip if cache is still valid (unless forced)
                if !force, let lastFetch = lastFetchTime[chainId],
                   Date().timeIntervalSince(lastFetch) < cacheDuration,
                   sparklines[chainId] != nil {
                    continue
                }
                
                // Fetch with retry
                await fetchSparkline(chainId: chainId, coinId: coinId)
                
                // Delay between requests
                if !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: requestDelay)
                }
            }
            
            await MainActor.run { 
                self.isFetching = false
                self.saveToDisk()
            }
        }
    }
    
    /// Get sparkline for a specific chain (returns cached or empty)
    func sparkline(for chainId: String) -> [Double] {
        return sparklines[chainId] ?? []
    }
    
    /// Check if we have valid cached data for a chain
    func hasCachedData(for chainId: String) -> Bool {
        guard let lastFetch = lastFetchTime[chainId],
              Date().timeIntervalSince(lastFetch) < cacheDuration,
              let data = sparklines[chainId], !data.isEmpty else {
            return false
        }
        return true
    }
    
    // MARK: - Private Fetching
    
    private func fetchSparkline(chainId: String, coinId: String) async {
        let baseURL: String
        if let apiKey = apiKey, !apiKey.isEmpty {
            baseURL = "https://pro-api.coingecko.com/api/v3/coins/\(coinId)/market_chart?vs_currency=usd&days=1&x_cg_pro_api_key=\(apiKey)"
        } else {
            baseURL = "https://api.coingecko.com/api/v3/coins/\(coinId)/market_chart?vs_currency=usd&days=1"
        }
        
        guard let url = URL(string: baseURL) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30 // Longer timeout
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else { return }
            
            // Handle rate limiting - wait and retry once
            if httpResponse.statusCode == 429 {
                print("Rate limited on \(chainId), waiting 10s...")
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                // Don't retry here - let next cycle handle it
                return
            }
            
            guard httpResponse.statusCode == 200 else { return }
            
            // Parse response
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let prices = json["prices"] as? [[Any]] else {
                return
            }
            
            // Extract prices and downsample
            let allPrices = prices.compactMap { $0.last as? Double }
            guard !allPrices.isEmpty else { return }
            
            let targetPoints = 24
            let points: [Double]
            if allPrices.count <= targetPoints {
                points = allPrices
            } else {
                let step = max(1, allPrices.count / targetPoints)
                points = stride(from: 0, to: allPrices.count, by: step).map { allPrices[$0] }
            }
            
            await MainActor.run {
                self.sparklines[chainId] = points
                self.lastFetchTime[chainId] = Date()
            }
            
        } catch is CancellationError {
            // Silently ignore cancellation
        } catch {
            // Only log actual errors, not cancellations
            if (error as NSError).code != NSURLErrorCancelled {
                print("Sparkline fetch error for \(chainId): \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Persistence
    
    private var cacheFileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("sparkline_cache.json")
    }
    
    private func saveToDisk() {
        guard let url = cacheFileURL else { return }
        
        let cacheData = CacheData(
            sparklines: sparklines,
            lastFetchTimes: lastFetchTime.mapValues { $0.timeIntervalSince1970 }
        )
        
        if let data = try? JSONEncoder().encode(cacheData) {
            try? data.write(to: url)
        }
    }
    
    private func loadFromDisk() {
        guard let url = cacheFileURL,
              let data = try? Data(contentsOf: url),
              let cacheData = try? JSONDecoder().decode(CacheData.self, from: data) else {
            return
        }
        
        sparklines = cacheData.sparklines
        lastFetchTime = cacheData.lastFetchTimes.mapValues { Date(timeIntervalSince1970: $0) }
    }
    
    private struct CacheData: Codable {
        let sparklines: [String: [Double]]
        let lastFetchTimes: [String: TimeInterval]
    }
}
