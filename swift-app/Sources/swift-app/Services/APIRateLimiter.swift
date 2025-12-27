import Foundation

// MARK: - API Rate Limiter

/// Thread-safe rate limiter for API calls
/// Prevents hitting rate limits by queueing requests and spacing them out
actor APIRateLimiter {
    
    // MARK: - Configuration
    
    struct Config {
        let requestsPerSecond: Double
        let burstSize: Int
        let retryAfterHeader: Bool
        
        static let `default` = Config(requestsPerSecond: 10, burstSize: 20, retryAfterHeader: true)
        static let conservative = Config(requestsPerSecond: 2, burstSize: 5, retryAfterHeader: true)
        static let aggressive = Config(requestsPerSecond: 30, burstSize: 50, retryAfterHeader: true)
    }
    
    // MARK: - Providers
    
    /// Pre-configured rate limiters for common providers
    static let mempool = APIRateLimiter(name: "Mempool", config: Config(requestsPerSecond: 5, burstSize: 10, retryAfterHeader: true))
    static let alchemy = APIRateLimiter(name: "Alchemy", config: Config(requestsPerSecond: 25, burstSize: 50, retryAfterHeader: true))
    static let coingecko = APIRateLimiter(name: "CoinGecko", config: Config(requestsPerSecond: 10, burstSize: 30, retryAfterHeader: true))
    static let coincap = APIRateLimiter(name: "CoinCap", config: Config(requestsPerSecond: 10, burstSize: 20, retryAfterHeader: true))
    static let cryptocompare = APIRateLimiter(name: "CryptoCompare", config: Config(requestsPerSecond: 50, burstSize: 100, retryAfterHeader: true))
    static let blockstream = APIRateLimiter(name: "Blockstream", config: Config(requestsPerSecond: 5, burstSize: 10, retryAfterHeader: true))
    static let solana = APIRateLimiter(name: "Solana", config: Config(requestsPerSecond: 10, burstSize: 20, retryAfterHeader: true))
    static let xrp = APIRateLimiter(name: "XRP", config: Config(requestsPerSecond: 5, burstSize: 10, retryAfterHeader: true))
    
    // MARK: - Properties
    
    private let name: String
    private let config: Config
    private var tokens: Double
    private var lastRefill: Date
    private var retryAfter: Date?
    private var pendingRequests: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []
    private var isProcessing = false
    
    // MARK: - Statistics
    
    private(set) var totalRequests: Int = 0
    private(set) var rateLimitedRequests: Int = 0
    private(set) var lastRequestTime: Date?
    
    // MARK: - Initialization
    
    init(name: String, config: Config = .default) {
        self.name = name
        self.config = config
        self.tokens = Double(config.burstSize)
        self.lastRefill = Date()
    }
    
    // MARK: - Public Interface
    
    /// Acquire permission to make a request
    /// Will wait if rate limited
    func acquire() async throws {
        totalRequests += 1
        
        // Check if we're in a forced retry-after period
        if let retryDate = retryAfter, Date() < retryDate {
            let waitTime = retryDate.timeIntervalSinceNow
            #if DEBUG
            print("🚦 [\(name)] Waiting \(String(format: "%.1f", waitTime))s for retry-after")
            #endif
            try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
        }
        
        // Refill tokens based on time elapsed
        refillTokens()
        
        // If we have tokens, consume one and proceed
        if tokens >= 1 {
            tokens -= 1
            lastRequestTime = Date()
            return
        }
        
        // No tokens available - queue request
        rateLimitedRequests += 1
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let id = UUID()
            pendingRequests.append((id: id, continuation: continuation))
            
            #if DEBUG
            print("🚦 [\(name)] Request queued (\(pendingRequests.count) pending)")
            #endif
            
            // Start processing queue if not already
            Task {
                await processPendingRequests()
            }
        }
        
        lastRequestTime = Date()
    }
    
    /// Report a rate limit response from the server
    func reportRateLimit(retryAfterSeconds: TimeInterval? = nil) {
        let waitTime = retryAfterSeconds ?? 60.0 // Default 60s wait if no header
        retryAfter = Date().addingTimeInterval(waitTime)
        
        #if DEBUG
        print("🚦 [\(name)] Rate limit reported - waiting \(waitTime)s")
        #endif
    }
    
    /// Report a 429 response with Retry-After header
    func reportHTTPResponse(_ response: HTTPURLResponse) {
        guard response.statusCode == 429 else { return }
        
        if let retryAfterString = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = Double(retryAfterString) {
            reportRateLimit(retryAfterSeconds: seconds)
        } else {
            reportRateLimit()
        }
    }
    
    /// Get current statistics
    var statistics: (total: Int, rateLimited: Int, pending: Int) {
        (totalRequests, rateLimitedRequests, pendingRequests.count)
    }
    
    // MARK: - Private Methods
    
    private func refillTokens() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefill)
        let refillAmount = elapsed * config.requestsPerSecond
        
        tokens = min(Double(config.burstSize), tokens + refillAmount)
        lastRefill = now
    }
    
    private func processPendingRequests() async {
        guard !isProcessing else { return }
        isProcessing = true
        
        while !pendingRequests.isEmpty {
            // Wait for a token to become available
            let waitTime = 1.0 / config.requestsPerSecond
            try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            
            // Refill and check
            refillTokens()
            
            if tokens >= 1, let next = pendingRequests.first {
                tokens -= 1
                pendingRequests.removeFirst()
                next.continuation.resume()
            }
        }
        
        isProcessing = false
    }
}

// MARK: - Rate-Limited URL Session

extension URLSession {
    
    /// Perform a rate-limited data request
    func rateLimitedData(from url: URL, limiter: APIRateLimiter) async throws -> (Data, URLResponse) {
        try await limiter.acquire()
        
        let (data, response) = try await data(from: url)
        
        // Check for rate limit response
        if let httpResponse = response as? HTTPURLResponse {
            await limiter.reportHTTPResponse(httpResponse)
            
            if httpResponse.statusCode == 429 {
                throw RateLimitError.tooManyRequests(retryAfter: httpResponse.value(forHTTPHeaderField: "Retry-After"))
            }
        }
        
        return (data, response)
    }
    
    /// Perform a rate-limited request
    func rateLimitedData(for request: URLRequest, limiter: APIRateLimiter) async throws -> (Data, URLResponse) {
        try await limiter.acquire()
        
        let (data, response) = try await data(for: request)
        
        // Check for rate limit response
        if let httpResponse = response as? HTTPURLResponse {
            await limiter.reportHTTPResponse(httpResponse)
            
            if httpResponse.statusCode == 429 {
                throw RateLimitError.tooManyRequests(retryAfter: httpResponse.value(forHTTPHeaderField: "Retry-After"))
            }
        }
        
        return (data, response)
    }
}

// MARK: - Rate Limit Error

enum RateLimitError: LocalizedError {
    case tooManyRequests(retryAfter: String?)
    
    var errorDescription: String? {
        switch self {
        case .tooManyRequests(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited. Please wait \(seconds) seconds."
            }
            return "Rate limited. Please wait a moment and try again."
        }
    }
}
