import Foundation

// MARK: - Honeypot Token Detection (ROADMAP-08 E9/A3)
// Uses GoPlus Security API to detect honeypot tokens
// that can be bought but not sold, trapping user funds.

@MainActor
final class HoneypotDetector: ObservableObject {
    
    // MARK: - Singleton
    static let shared = HoneypotDetector()
    
    // MARK: - Published State
    @Published var isChecking = false
    @Published var lastError: String?
    
    // MARK: - Cache
    /// Cache results to avoid repeated API calls (token address → result)
    private var cache: [String: HoneypotResult] = [:]
    private let cacheExpiry: TimeInterval = 3600 // 1 hour
    
    private init() {}
    
    // MARK: - Types
    
    struct HoneypotResult {
        let tokenAddress: String
        let chainId: String
        let isHoneypot: Bool
        let buyTax: Double       // Percentage (0-100)
        let sellTax: Double      // Percentage (0-100)
        let cannotSellAll: Bool  // Can't sell entire holding
        let cannotBuy: Bool      // Buy function disabled
        let hasProxy: Bool       // Upgradeable contract (risky)
        let isOpenSource: Bool   // Source code verified
        let holderCount: Int
        let ownerAddress: String?
        let creatorAddress: String?
        let isAntiWhale: Bool    // Has max transaction limits
        let tradingCooldown: Bool // Enforced cooldown between trades
        let transferPausable: Bool // Owner can pause transfers
        let hiddenOwner: Bool    // Owner can be hidden
        let externalCall: Bool   // Contract makes external calls (rug risk)
        let warnings: [String]
        let timestamp: Date
        
        /// Overall risk level
        var riskLevel: HoneypotRiskLevel {
            if isHoneypot || cannotSellAll || cannotBuy { return .critical }
            if sellTax > 30 || buyTax > 30 || hiddenOwner || externalCall { return .high }
            if sellTax > 10 || buyTax > 10 || hasProxy || transferPausable { return .medium }
            if sellTax > 3 || buyTax > 3 || !isOpenSource { return .low }
            return .safe
        }
        
        /// Human-readable warning message
        var warningMessage: String {
            if isHoneypot {
                return "⛔ HONEYPOT: This token cannot be sold after purchase. Your funds will be trapped."
            }
            if cannotSellAll {
                return "⚠️ Cannot sell entire holding. You may not be able to fully exit this position."
            }
            if sellTax > 30 {
                return "⚠️ Extreme sell tax (\(String(format: "%.0f", sellTax))%). You will lose most of your value when selling."
            }
            if sellTax > 10 {
                return "⚠️ High sell tax (\(String(format: "%.0f", sellTax))%). You will receive significantly less when selling."
            }
            if hiddenOwner {
                return "⚠️ Contract has a hidden owner who may be able to manipulate the token."
            }
            if externalCall {
                return "⚠️ Contract makes external calls which could be used for a rug pull."
            }
            return ""
        }
    }
    
    enum HoneypotRiskLevel: Comparable {
        case safe
        case low
        case medium
        case high
        case critical
        
        var displayName: String {
            switch self {
            case .safe: return "Safe"
            case .low: return "Low Risk"
            case .medium: return "Medium Risk"
            case .high: return "High Risk"
            case .critical: return "Honeypot"
            }
        }
        
        var icon: String {
            switch self {
            case .safe: return "checkmark.shield.fill"
            case .low: return "shield.fill"
            case .medium: return "exclamationmark.shield.fill"
            case .high: return "exclamationmark.triangle.fill"
            case .critical: return "xmark.octagon.fill"
            }
        }
    }
    
    // MARK: - Public API
    
    /// Check if a token is a honeypot using GoPlus Security API
    /// - Parameters:
    ///   - tokenAddress: The token contract address
    ///   - chainId: GoPlus chain ID (e.g., "1" for Ethereum, "56" for BSC)
    /// - Returns: HoneypotResult or nil on network failure
    func checkToken(_ tokenAddress: String, chainId: String = "1") async -> HoneypotResult? {
        let cacheKey = "\(chainId):\(tokenAddress.lowercased())"
        
        // Check cache
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.timestamp) < cacheExpiry {
            return cached
        }
        
        isChecking = true
        lastError = nil
        defer { isChecking = false }
        
        // GoPlus Token Security endpoint
        let urlString = "https://api.gopluslabs.io/api/v1/token_security/\(chainId)?contract_addresses=\(tokenAddress)"
        guard let url = URL(string: urlString) else {
            lastError = "Invalid URL"
            return nil
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                lastError = "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                return nil
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let code = json["code"] as? Int, code == 1,
                  let result = json["result"] as? [String: Any] else {
                lastError = "Invalid API response"
                return nil
            }
            
            // GoPlus returns results keyed by lowercase address
            let tokenKey = tokenAddress.lowercased()
            guard let tokenData = result[tokenKey] as? [String: Any] else {
                lastError = "Token not found in API response"
                return nil
            }
            
            let honeypotResult = parseGoPlusTokenSecurity(tokenData, tokenAddress: tokenAddress, chainId: chainId)
            
            // Cache the result
            cache[cacheKey] = honeypotResult
            
            if honeypotResult.isHoneypot {
                print("🍯 Honeypot detected: \(tokenAddress.prefix(10))... on chain \(chainId)")
            }
            
            return honeypotResult
            
        } catch {
            lastError = error.localizedDescription
            print("⚠️ GoPlus token security check failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Quick check from cache only (no API call)
    func cachedResult(for tokenAddress: String, chainId: String = "1") -> HoneypotResult? {
        let cacheKey = "\(chainId):\(tokenAddress.lowercased())"
        return cache[cacheKey]
    }
    
    /// Clear the cache
    func clearCache() {
        cache.removeAll()
    }
    
    // MARK: - GoPlus Response Parsing
    
    private func parseGoPlusTokenSecurity(_ data: [String: Any], tokenAddress: String, chainId: String) -> HoneypotResult {
        // Parse boolean flags (GoPlus returns "0"/"1" strings)
        func flag(_ key: String) -> Bool { (data[key] as? String) == "1" }
        
        // Parse tax percentages
        func tax(_ key: String) -> Double {
            if let str = data[key] as? String, let val = Double(str) {
                return val * 100 // Convert from 0-1 to 0-100
            }
            return 0
        }
        
        let isHoneypot = flag("is_honeypot")
        let buyTax = tax("buy_tax")
        let sellTax = tax("sell_tax")
        let cannotSellAll = flag("cannot_sell_all")
        let cannotBuy = flag("cannot_buy")
        let hasProxy = flag("is_proxy")
        let isOpenSource = flag("is_open_source")
        let isAntiWhale = flag("is_anti_whale")
        let tradingCooldown = flag("trading_cooldown")
        let transferPausable = flag("transfer_pausable")
        let hiddenOwner = flag("hidden_owner")
        let externalCall = flag("external_call")
        
        let holderCount = (data["holder_count"] as? String).flatMap { Int($0) } ?? 0
        let ownerAddress = data["owner_address"] as? String
        let creatorAddress = data["creator_address"] as? String
        
        // Build warnings list
        var warnings: [String] = []
        if isHoneypot { warnings.append("Token is a confirmed honeypot") }
        if cannotSellAll { warnings.append("Cannot sell entire holding") }
        if cannotBuy { warnings.append("Buy function is disabled") }
        if sellTax > 10 { warnings.append("High sell tax: \(String(format: "%.1f", sellTax))%") }
        if buyTax > 10 { warnings.append("High buy tax: \(String(format: "%.1f", buyTax))%") }
        if hasProxy { warnings.append("Upgradeable proxy contract") }
        if !isOpenSource { warnings.append("Contract source code not verified") }
        if hiddenOwner { warnings.append("Hidden contract owner") }
        if externalCall { warnings.append("Makes external calls (rug pull risk)") }
        if transferPausable { warnings.append("Transfers can be paused by owner") }
        if tradingCooldown { warnings.append("Trading cooldown enforced") }
        if holderCount < 50 { warnings.append("Very few holders (\(holderCount))") }
        
        return HoneypotResult(
            tokenAddress: tokenAddress,
            chainId: chainId,
            isHoneypot: isHoneypot,
            buyTax: buyTax,
            sellTax: sellTax,
            cannotSellAll: cannotSellAll,
            cannotBuy: cannotBuy,
            hasProxy: hasProxy,
            isOpenSource: isOpenSource,
            holderCount: holderCount,
            ownerAddress: ownerAddress,
            creatorAddress: creatorAddress,
            isAntiWhale: isAntiWhale,
            tradingCooldown: tradingCooldown,
            transferPausable: transferPausable,
            hiddenOwner: hiddenOwner,
            externalCall: externalCall,
            warnings: warnings,
            timestamp: Date()
        )
    }
    
    // MARK: - Chain ID Mapping
    
    /// Convert our chain names to GoPlus chain IDs
    static func goPlusChainId(from chain: String) -> String? {
        switch chain.lowercased() {
        case "ethereum", "eth": return "1"
        case "bsc", "bnb": return "56"
        case "polygon", "matic": return "137"
        case "arbitrum": return "42161"
        case "optimism": return "10"
        case "avalanche", "avax": return "43114"
        case "base": return "8453"
        case "fantom", "ftm": return "250"
        default: return nil
        }
    }
}
