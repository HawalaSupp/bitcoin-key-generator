import Foundation

// MARK: - dApp Access Manager

/// Manages allowlist and blocklist for WalletConnect dApps.
/// Persists lists in UserDefaults and provides access decisions
/// before showing session proposals or processing requests.
@MainActor
final class DAppAccessManager: ObservableObject {
    static let shared = DAppAccessManager()
    
    // MARK: - Access Decision
    
    enum AccessDecision: Equatable {
        case allowed
        case blocked(reason: String)
        case unknown
    }
    
    // MARK: - Published State
    
    @Published private(set) var allowedDomains: Set<String> = []
    @Published private(set) var blockedDomains: Set<String> = []
    
    // MARK: - Persistence Keys
    
    private let allowlistKey = "dapp_allowlist"
    private let blocklistKey = "dapp_blocklist"
    
    // MARK: - Built-in Blocklist (known scam domains)
    
    static let builtInBlocklist: Set<String> = [
        "airdrop-claim.xyz",
        "free-nft-mint.com",
        "uniswap-airdrop.org",
        "metamask-verify.com",
        "opensea-claim.net",
        "eth2-staking-rewards.com",
        "wallet-connect-bridge.com",
        "defi-airdrop-claim.xyz",
        "pancakeswap-airdrop.org",
        "nft-free-mint.xyz",
    ]
    
    // MARK: - Initialization
    
    private init() {
        loadLists()
    }
    
    // MARK: - Access Check
    
    /// Check whether a dApp domain is allowed, blocked, or unknown.
    /// Normalizes the domain before checking.
    func checkAccess(domain: String) -> AccessDecision {
        let normalized = normalizeDomain(domain)
        
        // Check explicit blocklist first (user's list takes priority)
        if blockedDomains.contains(normalized) {
            return .blocked(reason: "This dApp is on your blocklist")
        }
        
        // Check built-in blocklist
        if Self.builtInBlocklist.contains(normalized) {
            return .blocked(reason: "This dApp is a known scam site")
        }
        
        // Check against parent domain patterns in blocklist
        for blocked in blockedDomains {
            if normalized.hasSuffix(".\(blocked)") {
                return .blocked(reason: "This dApp's parent domain is blocked")
            }
        }
        for blocked in Self.builtInBlocklist {
            if normalized.hasSuffix(".\(blocked)") {
                return .blocked(reason: "This dApp's parent domain is a known scam site")
            }
        }
        
        // Check explicit allowlist
        if allowedDomains.contains(normalized) {
            return .allowed
        }
        
        // Check parent domain in allowlist
        for allowed in allowedDomains {
            if normalized.hasSuffix(".\(allowed)") {
                return .allowed
            }
        }
        
        return .unknown
    }
    
    /// Check access for a WCPeer from a session proposal
    func checkAccess(peer: WCPeer) -> AccessDecision {
        let domain = extractDomain(from: peer.url)
        return checkAccess(domain: domain)
    }
    
    // MARK: - Allowlist Management
    
    func addToAllowlist(domain: String) {
        let normalized = normalizeDomain(domain)
        allowedDomains.insert(normalized)
        blockedDomains.remove(normalized) // Remove from blocklist if present
        saveLists()
    }
    
    func removeFromAllowlist(domain: String) {
        let normalized = normalizeDomain(domain)
        allowedDomains.remove(normalized)
        saveLists()
    }
    
    // MARK: - Blocklist Management
    
    func addToBlocklist(domain: String) {
        let normalized = normalizeDomain(domain)
        blockedDomains.insert(normalized)
        allowedDomains.remove(normalized) // Remove from allowlist if present
        saveLists()
    }
    
    func removeFromBlocklist(domain: String) {
        let normalized = normalizeDomain(domain)
        blockedDomains.remove(normalized)
        saveLists()
    }
    
    // MARK: - Bulk Operations
    
    func clearAllowlist() {
        allowedDomains.removeAll()
        saveLists()
    }
    
    func clearBlocklist() {
        blockedDomains.removeAll()
        saveLists()
    }
    
    // MARK: - Domain Extraction & Normalization
    
    /// Extract domain from a URL string (e.g., "https://app.uniswap.org/swap" → "app.uniswap.org")
    func extractDomain(from urlString: String) -> String {
        if let url = URL(string: urlString), let host = url.host {
            return normalizeDomain(host)
        }
        // Fallback: treat as domain directly
        return normalizeDomain(urlString)
    }
    
    /// Normalize domain: lowercase, strip www prefix, trim whitespace
    func normalizeDomain(_ domain: String) -> String {
        var normalized = domain
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Strip protocol if present
        if normalized.hasPrefix("https://") { normalized = String(normalized.dropFirst(8)) }
        if normalized.hasPrefix("http://") { normalized = String(normalized.dropFirst(7)) }
        
        // Strip path
        if let slashIndex = normalized.firstIndex(of: "/") {
            normalized = String(normalized[..<slashIndex])
        }
        
        // Strip www. prefix
        if normalized.hasPrefix("www.") { normalized = String(normalized.dropFirst(4)) }
        
        // Strip port
        if let colonIndex = normalized.firstIndex(of: ":") {
            normalized = String(normalized[..<colonIndex])
        }
        
        return normalized
    }
    
    // MARK: - Persistence
    
    private func saveLists() {
        let allowArray = Array(allowedDomains)
        let blockArray = Array(blockedDomains)
        UserDefaults.standard.set(allowArray, forKey: allowlistKey)
        UserDefaults.standard.set(blockArray, forKey: blocklistKey)
    }
    
    private func loadLists() {
        if let allowed = UserDefaults.standard.stringArray(forKey: allowlistKey) {
            allowedDomains = Set(allowed)
        }
        if let blocked = UserDefaults.standard.stringArray(forKey: blocklistKey) {
            blockedDomains = Set(blocked)
        }
    }
}
