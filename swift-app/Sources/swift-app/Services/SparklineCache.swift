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
    
    /// Delay between API calls for priority coins - 500ms (fast loading)
    private let priorityRequestDelay: UInt64 = 500_000_000
    
    /// Delay between API calls for other coins - 2 seconds
    private let normalRequestDelay: UInt64 = 2_000_000_000
    
    /// Priority coins to load first (top 15 by market cap)
    private let priorityChains: [String] = [
        "bitcoin", "ethereum", "solana", "xrp", "bnb",
        "cardano", "dogecoin", "tron", "litecoin", "polkadot",
        "monero", "ton", "stellar", "near", "sui"
    ]
    
    /// Current fetch task
    private var fetchTask: Task<Void, Never>?
    
    /// Coin ID mappings for CoinGecko
    private let coinMappings: [String: String] = [
        // Core chains
        "bitcoin": "bitcoin",
        "ethereum": "ethereum", 
        "litecoin": "litecoin",
        "solana": "solana",
        "xrp": "ripple",
        "bnb": "binancecoin",
        "monero": "monero",
        // Extended chains from wallet-core
        "ton": "the-open-network",
        "aptos": "aptos",
        "sui": "sui",
        "polkadot": "polkadot",
        // Extended chain support
        "dogecoin": "dogecoin",
        "bitcoin-cash": "bitcoin-cash",
        "cosmos": "cosmos",
        "cardano": "cardano",
        "tron": "tron",
        "algorand": "algorand",
        "stellar": "stellar",
        "near": "near",
        "tezos": "tezos",
        "hedera": "hedera-hashgraph",
        // 16 new chains
        "zcash": "zcash",
        "dash": "dash",
        "ravencoin": "ravencoin",
        "vechain": "vechain",
        "filecoin": "filecoin",
        "harmony": "harmony",
        "oasis": "oasis-network",
        "internet-computer": "internet-computer",
        "waves": "waves",
        "multiversx": "elrond-erd-2",
        "flow": "flow",
        "mina": "mina-protocol",
        "zilliqa": "zilliqa",
        "eos": "eos",
        "neo": "neo",
        "nervos": "nervos-network",
        // Stablecoins
        "usdt-erc20": "tether",
        "usdc-erc20": "usd-coin",
        "dai-erc20": "dai"
    ]
    
    /// CoinGecko API key (optional, for pro tier)
    var apiKey: String?
    
    private init() {
        loadFromDisk()
    }
    
    // MARK: - Public API
    
    /// Fetch sparklines for all chains, using cache when valid
    func fetchAllSparklines(force: Bool = false) {
        // If a fetch is already in progress and not forcing, skip
        if !force && isFetching {
            print("📊 Sparkline fetch already in progress, skipping duplicate call")
            return
        }
        
        // Cancel any existing fetch if forcing
        if force {
            fetchTask?.cancel()
        }
        
        fetchTask = Task { [weak self] in
            guard let self = self else { return }
            
            await MainActor.run { self.isFetching = true }
            
            print("📊 Starting sparkline fetch (force=\(force))...")
            var fetchedCount = 0
            var skippedCount = 0
            
            // PHASE 1: Fetch priority coins first (fast)
            print("📊 Phase 1: Loading top 15 coins...")
            for chainId in priorityChains {
                if Task.isCancelled { break }
                
                guard let coinId = coinMappings[chainId] else { continue }
                
                // Skip if cache is still valid (unless forced)
                if !force, let lastFetch = lastFetchTime[chainId],
                   Date().timeIntervalSince(lastFetch) < cacheDuration,
                   sparklines[chainId] != nil {
                    skippedCount += 1
                    continue
                }
                
                await fetchSparkline(chainId: chainId, coinId: coinId)
                fetchedCount += 1
                
                // Short delay for priority coins
                if !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: priorityRequestDelay)
                }
            }
            
            print("📊 Phase 1 complete: \(fetchedCount) priority coins loaded")
            
            // PHASE 2: Fetch remaining coins (slower)
            let remainingChains = coinMappings.keys.filter { !priorityChains.contains($0) }
            for chainId in remainingChains {
                if Task.isCancelled { break }
                
                guard let coinId = coinMappings[chainId] else { continue }
                
                // Skip if cache is still valid (unless forced)
                if !force, let lastFetch = lastFetchTime[chainId],
                   Date().timeIntervalSince(lastFetch) < cacheDuration,
                   sparklines[chainId] != nil {
                    skippedCount += 1
                    continue
                }
                
                await fetchSparkline(chainId: chainId, coinId: coinId)
                fetchedCount += 1
                
                // Normal delay for other coins
                if !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: normalRequestDelay)
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
