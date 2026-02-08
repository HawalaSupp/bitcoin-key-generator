import Foundation

// MARK: - dApp Request Rate Limiter

/// Per-dApp rate limiter for WalletConnect requests.
/// Enforces a maximum of 10 requests per minute per dApp session topic.
/// Prevents malicious dApps from spamming the user with signing requests.
actor DAppRateLimiter {
    
    // MARK: - Configuration
    
    /// Maximum requests allowed per window
    let maxRequestsPerWindow: Int
    
    /// Time window in seconds
    let windowSeconds: TimeInterval
    
    // MARK: - State
    
    /// Request timestamps per dApp topic
    private var requestLog: [String: [Date]] = [:]
    
    /// Total requests blocked
    private(set) var totalBlocked: Int = 0
    
    /// Shared instance with default config (10 req/min)
    static let shared = DAppRateLimiter(maxRequests: 10, windowSeconds: 60)
    
    // MARK: - Initialization
    
    init(maxRequests: Int = 10, windowSeconds: TimeInterval = 60) {
        self.maxRequestsPerWindow = maxRequests
        self.windowSeconds = windowSeconds
    }
    
    // MARK: - Rate Limiting
    
    /// Check if a request from a dApp topic should be allowed.
    /// Returns true if allowed, false if rate limited.
    func shouldAllow(topic: String) -> Bool {
        let now = Date()
        pruneOldEntries(topic: topic, before: now)
        
        let count = requestLog[topic]?.count ?? 0
        return count < maxRequestsPerWindow
    }
    
    /// Record a request from a dApp topic.
    /// Returns true if the request was allowed, false if rate limited.
    @discardableResult
    func recordRequest(topic: String) -> Bool {
        let now = Date()
        pruneOldEntries(topic: topic, before: now)
        
        let count = requestLog[topic]?.count ?? 0
        
        if count >= maxRequestsPerWindow {
            totalBlocked += 1
            return false
        }
        
        if requestLog[topic] == nil {
            requestLog[topic] = []
        }
        requestLog[topic]?.append(now)
        return true
    }
    
    /// Get the number of requests made in the current window for a topic.
    func requestCount(for topic: String) -> Int {
        let now = Date()
        pruneOldEntries(topic: topic, before: now)
        return requestLog[topic]?.count ?? 0
    }
    
    /// Get the number of remaining requests allowed for a topic.
    func remainingRequests(for topic: String) -> Int {
        let count = requestLog[topic]?.count ?? 0
        return max(0, maxRequestsPerWindow - count)
    }
    
    /// Time in seconds until the next request slot opens for a topic.
    func timeUntilNextSlot(for topic: String) -> TimeInterval {
        guard let timestamps = requestLog[topic],
              timestamps.count >= maxRequestsPerWindow,
              let oldest = timestamps.first else {
            return 0
        }
        
        let expiry = oldest.addingTimeInterval(windowSeconds)
        let remaining = expiry.timeIntervalSince(Date())
        return max(0, remaining)
    }
    
    /// Reset all rate limiting state for a topic (e.g., on disconnect).
    func reset(topic: String) {
        requestLog.removeValue(forKey: topic)
    }
    
    /// Reset all rate limiting state.
    func resetAll() {
        requestLog.removeAll()
        totalBlocked = 0
    }
    
    /// Get statistics for all tracked topics.
    var statistics: (activeDApps: Int, totalBlocked: Int) {
        (requestLog.count, totalBlocked)
    }
    
    // MARK: - Private
    
    /// Remove entries older than the time window.
    private func pruneOldEntries(topic: String, before now: Date) {
        let cutoff = now.addingTimeInterval(-windowSeconds)
        requestLog[topic]?.removeAll { $0 < cutoff }
        
        // Clean up empty entries
        if requestLog[topic]?.isEmpty == true {
            requestLog.removeValue(forKey: topic)
        }
    }
}
