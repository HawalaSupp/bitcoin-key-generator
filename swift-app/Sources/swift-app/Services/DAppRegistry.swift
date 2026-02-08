import Foundation

// MARK: - dApp Verification Registry

/// Registry of known and verified dApps for WalletConnect.
/// Provides trust verification by matching dApp URLs against a curated list
/// of verified protocols. Shows verification badges and warnings.
@MainActor
final class DAppRegistry: ObservableObject {
    static let shared = DAppRegistry()
    
    // MARK: - Verification Status
    
    enum VerificationStatus: Equatable {
        case verified(info: DAppInfo)
        case unknown
        case suspicious(reason: String)
    }
    
    // MARK: - dApp Info
    
    struct DAppInfo: Equatable {
        let name: String
        let category: DAppCategory
        let description: String
        let verifiedDomains: [String]
        let chainIds: [String] // EVM chain IDs commonly used
    }
    
    enum DAppCategory: String, CaseIterable, Equatable {
        case dex = "DEX"
        case lending = "Lending"
        case nftMarketplace = "NFT Marketplace"
        case bridge = "Bridge"
        case derivatives = "Derivatives"
        case yield = "Yield"
        case dao = "DAO"
        case gaming = "Gaming"
        case wallet = "Wallet"
        case infrastructure = "Infrastructure"
        case other = "Other"
        
        var icon: String {
            switch self {
            case .dex: return "arrow.triangle.swap"
            case .lending: return "banknote"
            case .nftMarketplace: return "photo.artframe"
            case .bridge: return "arrow.left.arrow.right"
            case .derivatives: return "chart.line.uptrend.xyaxis"
            case .yield: return "leaf.fill"
            case .dao: return "person.3.fill"
            case .gaming: return "gamecontroller.fill"
            case .wallet: return "wallet.pass"
            case .infrastructure: return "server.rack"
            case .other: return "app.fill"
            }
        }
    }
    
    // MARK: - Verified Registry
    
    /// Curated list of verified dApps with their known domains
    static let verifiedDApps: [DAppInfo] = [
        // DEXes
        DAppInfo(
            name: "Uniswap",
            category: .dex,
            description: "Leading decentralized exchange",
            verifiedDomains: ["app.uniswap.org", "uniswap.org"],
            chainIds: ["eip155:1", "eip155:137", "eip155:42161", "eip155:10", "eip155:56"]
        ),
        DAppInfo(
            name: "SushiSwap",
            category: .dex,
            description: "Multi-chain decentralized exchange",
            verifiedDomains: ["app.sushi.com", "sushi.com", "sushiswap.fi"],
            chainIds: ["eip155:1", "eip155:137", "eip155:42161"]
        ),
        DAppInfo(
            name: "PancakeSwap",
            category: .dex,
            description: "BSC decentralized exchange",
            verifiedDomains: ["pancakeswap.finance", "pancakeswap.com"],
            chainIds: ["eip155:56", "eip155:1"]
        ),
        DAppInfo(
            name: "1inch",
            category: .dex,
            description: "DEX aggregator",
            verifiedDomains: ["app.1inch.io", "1inch.io"],
            chainIds: ["eip155:1", "eip155:56", "eip155:137", "eip155:42161", "eip155:10"]
        ),
        DAppInfo(
            name: "Curve Finance",
            category: .dex,
            description: "Stablecoin DEX",
            verifiedDomains: ["curve.fi"],
            chainIds: ["eip155:1", "eip155:137", "eip155:42161"]
        ),
        DAppInfo(
            name: "Balancer",
            category: .dex,
            description: "Automated portfolio manager and DEX",
            verifiedDomains: ["app.balancer.fi", "balancer.fi"],
            chainIds: ["eip155:1", "eip155:137", "eip155:42161"]
        ),
        
        // Lending
        DAppInfo(
            name: "Aave",
            category: .lending,
            description: "Decentralized lending and borrowing",
            verifiedDomains: ["app.aave.com", "aave.com"],
            chainIds: ["eip155:1", "eip155:137", "eip155:42161", "eip155:10", "eip155:43114"]
        ),
        DAppInfo(
            name: "Compound",
            category: .lending,
            description: "Algorithmic lending protocol",
            verifiedDomains: ["app.compound.finance", "compound.finance"],
            chainIds: ["eip155:1"]
        ),
        DAppInfo(
            name: "MakerDAO",
            category: .lending,
            description: "DAI stablecoin and lending",
            verifiedDomains: ["app.makerdao.com", "makerdao.com", "oasis.app"],
            chainIds: ["eip155:1"]
        ),
        DAppInfo(
            name: "Spark Protocol",
            category: .lending,
            description: "MakerDAO lending frontend",
            verifiedDomains: ["app.spark.fi", "spark.fi"],
            chainIds: ["eip155:1"]
        ),
        
        // NFT Marketplaces
        DAppInfo(
            name: "OpenSea",
            category: .nftMarketplace,
            description: "Largest NFT marketplace",
            verifiedDomains: ["opensea.io"],
            chainIds: ["eip155:1", "eip155:137", "eip155:42161"]
        ),
        DAppInfo(
            name: "Blur",
            category: .nftMarketplace,
            description: "Professional NFT marketplace",
            verifiedDomains: ["blur.io"],
            chainIds: ["eip155:1"]
        ),
        DAppInfo(
            name: "LooksRare",
            category: .nftMarketplace,
            description: "Community NFT marketplace",
            verifiedDomains: ["looksrare.org"],
            chainIds: ["eip155:1"]
        ),
        
        // Bridges
        DAppInfo(
            name: "Stargate",
            category: .bridge,
            description: "Cross-chain bridge (LayerZero)",
            verifiedDomains: ["stargate.finance"],
            chainIds: ["eip155:1", "eip155:56", "eip155:137", "eip155:42161", "eip155:10", "eip155:43114"]
        ),
        DAppInfo(
            name: "Across Protocol",
            category: .bridge,
            description: "Optimistic cross-chain bridge",
            verifiedDomains: ["across.to", "app.across.to"],
            chainIds: ["eip155:1", "eip155:137", "eip155:42161", "eip155:10"]
        ),
        
        // Derivatives
        DAppInfo(
            name: "dYdX",
            category: .derivatives,
            description: "Decentralized perpetuals exchange",
            verifiedDomains: ["dydx.exchange", "trade.dydx.exchange"],
            chainIds: ["eip155:1"]
        ),
        DAppInfo(
            name: "GMX",
            category: .derivatives,
            description: "Perpetuals DEX",
            verifiedDomains: ["app.gmx.io", "gmx.io"],
            chainIds: ["eip155:42161", "eip155:43114"]
        ),
        
        // Yield
        DAppInfo(
            name: "Lido",
            category: .yield,
            description: "Liquid staking",
            verifiedDomains: ["lido.fi", "stake.lido.fi"],
            chainIds: ["eip155:1"]
        ),
        DAppInfo(
            name: "Rocket Pool",
            category: .yield,
            description: "Decentralized ETH staking",
            verifiedDomains: ["rocketpool.net", "stake.rocketpool.net"],
            chainIds: ["eip155:1"]
        ),
        DAppInfo(
            name: "Yearn Finance",
            category: .yield,
            description: "Yield aggregator",
            verifiedDomains: ["yearn.fi", "yearn.finance"],
            chainIds: ["eip155:1"]
        ),
        DAppInfo(
            name: "Convex Finance",
            category: .yield,
            description: "Curve yield booster",
            verifiedDomains: ["convexfinance.com"],
            chainIds: ["eip155:1"]
        ),
        
        // DAO / Governance
        DAppInfo(
            name: "Snapshot",
            category: .dao,
            description: "Off-chain governance voting",
            verifiedDomains: ["snapshot.org"],
            chainIds: ["eip155:1"]
        ),
        DAppInfo(
            name: "Tally",
            category: .dao,
            description: "On-chain governance",
            verifiedDomains: ["tally.xyz", "www.tally.xyz"],
            chainIds: ["eip155:1"]
        ),
        
        // Infrastructure
        DAppInfo(
            name: "ENS Domains",
            category: .infrastructure,
            description: "Ethereum Name Service",
            verifiedDomains: ["app.ens.domains", "ens.domains"],
            chainIds: ["eip155:1"]
        ),
        DAppInfo(
            name: "Safe (Gnosis Safe)",
            category: .wallet,
            description: "Multi-sig wallet",
            verifiedDomains: ["app.safe.global", "safe.global", "gnosis-safe.io"],
            chainIds: ["eip155:1", "eip155:137", "eip155:56", "eip155:42161", "eip155:10"]
        ),
        DAppInfo(
            name: "Chainlink",
            category: .infrastructure,
            description: "Oracle network",
            verifiedDomains: ["chain.link", "staking.chain.link"],
            chainIds: ["eip155:1"]
        ),
    ]
    
    // MARK: - Suspicious Patterns
    
    private static let suspiciousPatterns: [(pattern: String, reason: String)] = [
        ("airdrop", "Domain contains 'airdrop' — common in phishing"),
        ("claim", "Domain contains 'claim' — common in phishing"),
        ("free-mint", "Domain contains 'free-mint' — common in phishing"),
        ("verify-wallet", "Domain contains 'verify-wallet' — common in phishing"),
        ("connect-wallet", "Domain contains 'connect-wallet' — common in phishing"),
        ("metamask-", "Domain impersonates MetaMask"),
        ("uniswap-", "Domain impersonates Uniswap"),
        ("opensea-", "Domain impersonates OpenSea"),
    ]
    
    // MARK: - Domain Lookup Index (built once)
    
    private let domainIndex: [String: DAppInfo]
    
    private init() {
        var index: [String: DAppInfo] = [:]
        for dapp in Self.verifiedDApps {
            for domain in dapp.verifiedDomains {
                index[domain.lowercased()] = dapp
            }
        }
        domainIndex = index
    }
    
    // MARK: - Verification
    
    /// Verify a dApp by its URL string
    func verify(url urlString: String) -> VerificationStatus {
        let domain = DAppAccessManager.shared.normalizeDomain(
            DAppAccessManager.shared.extractDomain(from: urlString)
        )
        return verify(domain: domain)
    }
    
    /// Verify a dApp by its domain
    func verify(domain: String) -> VerificationStatus {
        let normalized = domain.lowercased()
        
        // Direct match
        if let info = domainIndex[normalized] {
            return .verified(info: info)
        }
        
        // Check parent domain (e.g., "v2.app.uniswap.org" → "app.uniswap.org")
        let components = normalized.split(separator: ".")
        if components.count > 2 {
            let parentDomain = components.dropFirst().joined(separator: ".")
            if let info = domainIndex[parentDomain] {
                return .verified(info: info)
            }
        }
        
        // Check suspicious patterns
        for (pattern, reason) in Self.suspiciousPatterns {
            if normalized.contains(pattern) {
                return .suspicious(reason: reason)
            }
        }
        
        // Check for typosquatting (basic Levenshtein-style check)
        for (verifiedDomain, info) in domainIndex {
            // Strip TLD for comparison
            let verifiedBase = verifiedDomain.split(separator: ".").dropLast().joined(separator: ".")
            let checkBase = normalized.split(separator: ".").dropLast().joined(separator: ".")
            
            if !verifiedBase.isEmpty && !checkBase.isEmpty &&
               checkBase != verifiedBase &&
               levenshteinDistance(checkBase, verifiedBase) <= 2 {
                return .suspicious(reason: "Domain is similar to verified dApp '\(info.name)' — possible typosquatting")
            }
        }
        
        return .unknown
    }
    
    /// Verify a WCPeer
    func verify(peer: WCPeer) -> VerificationStatus {
        return verify(url: peer.url)
    }
    
    /// Get all verified dApps in a category
    func dApps(in category: DAppCategory) -> [DAppInfo] {
        Self.verifiedDApps.filter { $0.category == category }
    }
    
    /// Search verified dApps by name
    func search(query: String) -> [DAppInfo] {
        let q = query.lowercased()
        return Self.verifiedDApps.filter {
            $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
    }
    
    // MARK: - Levenshtein Distance
    
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1 = Array(s1)
        let s2 = Array(s2)
        let m = s1.count
        let n = s2.count
        
        if m == 0 { return n }
        if n == 0 { return m }
        
        var matrix = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        
        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }
        
        for i in 1...m {
            for j in 1...n {
                let cost = s1[i - 1] == s2[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }
        
        return matrix[m][n]
    }
}
