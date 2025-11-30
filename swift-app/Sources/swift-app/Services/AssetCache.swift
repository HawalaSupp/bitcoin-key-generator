import Foundation

// MARK: - Asset Cache
/// Caches balance and price data to disk for faster app startup
/// Loads cached data immediately and refreshes in background

@MainActor
final class AssetCache: ObservableObject {
    static let shared = AssetCache()
    
    /// Cached balance data per chain
    @Published var cachedBalances: [String: CachedAssetBalance] = [:]
    
    /// Cached price data per chain
    @Published var cachedPrices: [String: CachedAssetPrice] = [:]
    
    /// Last cache update time
    @Published var lastCacheUpdate: Date?
    
    /// Cache duration before considered stale (5 minutes)
    private let cacheDuration: TimeInterval = 300
    
    /// Cache file URL
    private var cacheFileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("asset_cache.json")
    }
    
    private init() {
        loadFromDisk()
    }
    
    // MARK: - Public API
    
    /// Save current balance to cache
    func cacheBalance(chainId: String, balance: String, numericValue: Double) {
        cachedBalances[chainId] = CachedAssetBalance(
            chainId: chainId,
            balance: balance,
            numericValue: numericValue,
            lastUpdated: Date()
        )
        saveToDisk()
    }
    
    /// Save current price to cache
    func cachePrice(chainId: String, price: String, numericValue: Double, change24h: Double?) {
        cachedPrices[chainId] = CachedAssetPrice(
            chainId: chainId,
            price: price,
            numericValue: numericValue,
            change24h: change24h,
            lastUpdated: Date()
        )
        saveToDisk()
    }
    
    /// Get cached balance for a chain
    func getCachedBalance(for chainId: String) -> CachedAssetBalance? {
        return cachedBalances[chainId]
    }
    
    /// Get cached price for a chain
    func getCachedPrice(for chainId: String) -> CachedAssetPrice? {
        return cachedPrices[chainId]
    }
    
    /// Check if cache is stale (older than cacheDuration)
    func isCacheStale(for chainId: String) -> Bool {
        guard let balance = cachedBalances[chainId],
              let price = cachedPrices[chainId] else {
            return true
        }
        
        let now = Date()
        let balanceAge = now.timeIntervalSince(balance.lastUpdated)
        let priceAge = now.timeIntervalSince(price.lastUpdated)
        
        return balanceAge > cacheDuration || priceAge > cacheDuration
    }
    
    /// Check if we have any cached data for a chain
    func hasCachedData(for chainId: String) -> Bool {
        return cachedBalances[chainId] != nil || cachedPrices[chainId] != nil
    }
    
    /// Clear all cached data
    func clearCache() {
        cachedBalances.removeAll()
        cachedPrices.removeAll()
        lastCacheUpdate = nil
        
        if let url = cacheFileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    /// Get total cached portfolio value
    func getCachedTotalValue() -> Double {
        var total: Double = 0
        
        for (chainId, balance) in cachedBalances {
            guard let price = cachedPrices[chainId] else { continue }
            total += balance.numericValue * price.numericValue
        }
        
        return total
    }
    
    /// Get cache age description
    func getCacheAgeDescription() -> String? {
        guard let lastUpdate = lastCacheUpdate else { return nil }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastUpdate, relativeTo: Date())
    }
    
    // MARK: - Persistence
    
    private func saveToDisk() {
        guard let url = cacheFileURL else { return }
        
        let cacheData = AssetCacheData(
            balances: cachedBalances,
            prices: cachedPrices,
            lastUpdate: Date()
        )
        
        do {
            let data = try JSONEncoder().encode(cacheData)
            try data.write(to: url)
            lastCacheUpdate = Date()
        } catch {
            print("Failed to save asset cache: \(error)")
        }
    }
    
    private func loadFromDisk() {
        guard let url = cacheFileURL,
              let data = try? Data(contentsOf: url),
              let cacheData = try? JSONDecoder().decode(AssetCacheData.self, from: data) else {
            return
        }
        
        cachedBalances = cacheData.balances
        cachedPrices = cacheData.prices
        lastCacheUpdate = cacheData.lastUpdate
        
        print("Loaded asset cache: \(cachedBalances.count) balances, \(cachedPrices.count) prices")
    }
}

// MARK: - Cache Data Models

struct CachedAssetBalance: Codable, Equatable {
    let chainId: String
    let balance: String
    let numericValue: Double
    let lastUpdated: Date
}

struct CachedAssetPrice: Codable, Equatable {
    let chainId: String
    let price: String
    let numericValue: Double
    let change24h: Double?
    let lastUpdated: Date
}

private struct AssetCacheData: Codable {
    let balances: [String: CachedAssetBalance]
    let prices: [String: CachedAssetPrice]
    let lastUpdate: Date
}
