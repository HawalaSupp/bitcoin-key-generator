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
    
    /// Cache duration - 15 minutes (increased to reduce API calls)
    private let cacheDuration: TimeInterval = 900
    
    /// Delay between API calls to respect rate limits (5 seconds for free tier)
    private let requestDelay: UInt64 = 5_000_000_000
    
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
            
            print("📊 Starting sparkline fetch (force=\(force))...")
            var fetchedCount = 0
            var skippedCount = 0
            
            for (chainId, coinId) in coinMappings {
                // Check if cancelled
                if Task.isCancelled { break }
                
                // Skip if cache is still valid (unless forced)
                if !force, let lastFetch = lastFetchTime[chainId],
                   Date().timeIntervalSince(lastFetch) < cacheDuration,
                   sparklines[chainId] != nil {
                    skippedCount += 1
                    continue
                }
                
                // Fetch with retry
                await fetchSparkline(chainId: chainId, coinId: coinId)
                fetchedCount += 1
                
                // Delay between requests
                if !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: requestDelay)
                }
            }
            
            print("📊 Sparkline fetch complete: \(fetchedCount) fetched, \(skippedCount) cached")
            
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
        // Use MultiProviderAPI with automatic fallbacks
        do {
            let points = try await MultiProviderAPI.shared.fetchSparkline(for: chainId)
            
            // Downsample if needed
            let targetPoints = 24
            let finalPoints: [Double]
            if points.count <= targetPoints {
                finalPoints = points
            } else {
                let step = max(1, points.count / targetPoints)
                finalPoints = stride(from: 0, to: points.count, by: step).map { points[$0] }
            }
            
            print("📊 Fetched \(finalPoints.count) sparkline points for \(chainId)")
            
            await MainActor.run {
                self.sparklines[chainId] = finalPoints
                self.lastFetchTime[chainId] = Date()
            }
        } catch is CancellationError {
            // Silently ignore cancellation
        } catch {
            print("⚠️ Sparkline fetch error for \(chainId): \(error.localizedDescription)")
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
            print("📊 No cached sparkline data found on disk")
            return
        }
        
        sparklines = cacheData.sparklines
        lastFetchTime = cacheData.lastFetchTimes.mapValues { Date(timeIntervalSince1970: $0) }
        print("📊 Loaded \(sparklines.count) sparklines from disk cache")
    }
    
    private struct CacheData: Codable {
        let sparklines: [String: [Double]]
        let lastFetchTimes: [String: TimeInterval]
    }
}
