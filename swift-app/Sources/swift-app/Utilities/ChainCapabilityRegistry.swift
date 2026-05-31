import Foundation

enum ChainSupportTier: String {
    case launch
    case internalTest
    case deferred
}

enum ChainFeature: Sendable {
    case send
    case receive
    case historySync
    case swap
    case bridge
    case stake
    case walletConnect
    case alerts
    case customRPC
}

struct ChainCapability: Sendable {
    let chainId: String
    let displayName: String
    let supportTier: ChainSupportTier
    let supportsSend: Bool
    let supportsReceive: Bool
    let supportsHistorySync: Bool
    let supportsSwap: Bool
    let supportsBridge: Bool
    let supportsStake: Bool
    let supportsWalletConnect: Bool
    let supportsAlerts: Bool
    let supportsCustomRPC: Bool
}

enum ChainCapabilityRegistry {
    /// Internal/test and deferred chains stay hidden in normal builds. Engineers can
    /// inspect broader chain coverage by launching a DEBUG build with
    /// HAWALA_DEVELOPMENT_FEATURES=1.
    static var developmentFeaturesEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["HAWALA_DEVELOPMENT_FEATURES"] == "1"
        #else
        false
        #endif
    }

    private static let orderedCapabilities: [ChainCapability] = [
        .init(chainId: "bitcoin", displayName: "Bitcoin", supportTier: .launch, supportsSend: true, supportsReceive: true, supportsHistorySync: true, supportsSwap: false, supportsBridge: false, supportsStake: false, supportsWalletConnect: false, supportsAlerts: true, supportsCustomRPC: false),
        .init(chainId: "bitcoin-testnet", displayName: "Bitcoin Testnet", supportTier: .internalTest, supportsSend: true, supportsReceive: true, supportsHistorySync: true, supportsSwap: false, supportsBridge: false, supportsStake: false, supportsWalletConnect: false, supportsAlerts: false, supportsCustomRPC: false),
        .init(chainId: "litecoin", displayName: "Litecoin", supportTier: .launch, supportsSend: true, supportsReceive: true, supportsHistorySync: true, supportsSwap: false, supportsBridge: false, supportsStake: false, supportsWalletConnect: false, supportsAlerts: true, supportsCustomRPC: false),
        .init(chainId: "ethereum", displayName: "Ethereum", supportTier: .launch, supportsSend: true, supportsReceive: true, supportsHistorySync: true, supportsSwap: false, supportsBridge: false, supportsStake: false, supportsWalletConnect: true, supportsAlerts: true, supportsCustomRPC: true),
        .init(chainId: "ethereum-sepolia", displayName: "Sepolia", supportTier: .internalTest, supportsSend: true, supportsReceive: true, supportsHistorySync: true, supportsSwap: false, supportsBridge: false, supportsStake: false, supportsWalletConnect: false, supportsAlerts: false, supportsCustomRPC: true),
        .init(chainId: "bnb", displayName: "BNB", supportTier: .internalTest, supportsSend: true, supportsReceive: true, supportsHistorySync: false, supportsSwap: true, supportsBridge: true, supportsStake: false, supportsWalletConnect: true, supportsAlerts: false, supportsCustomRPC: true),
        .init(chainId: "solana", displayName: "Solana", supportTier: .launch, supportsSend: true, supportsReceive: true, supportsHistorySync: true, supportsSwap: false, supportsBridge: false, supportsStake: false, supportsWalletConnect: false, supportsAlerts: true, supportsCustomRPC: false),
        .init(chainId: "polygon", displayName: "Polygon", supportTier: .internalTest, supportsSend: true, supportsReceive: true, supportsHistorySync: false, supportsSwap: true, supportsBridge: true, supportsStake: false, supportsWalletConnect: true, supportsAlerts: true, supportsCustomRPC: true),
        .init(chainId: "xrp", displayName: "XRP", supportTier: .launch, supportsSend: true, supportsReceive: true, supportsHistorySync: true, supportsSwap: false, supportsBridge: false, supportsStake: false, supportsWalletConnect: false, supportsAlerts: true, supportsCustomRPC: false),
        .init(chainId: "xrp-testnet", displayName: "XRP Testnet", supportTier: .internalTest, supportsSend: true, supportsReceive: true, supportsHistorySync: false, supportsSwap: false, supportsBridge: false, supportsStake: false, supportsWalletConnect: false, supportsAlerts: false, supportsCustomRPC: false),
        .init(chainId: "usdt-erc20", displayName: "Tether USD", supportTier: .launch, supportsSend: true, supportsReceive: true, supportsHistorySync: true, supportsSwap: false, supportsBridge: false, supportsStake: false, supportsWalletConnect: false, supportsAlerts: true, supportsCustomRPC: false),
        .init(chainId: "usdc-erc20", displayName: "USD Coin", supportTier: .launch, supportsSend: true, supportsReceive: true, supportsHistorySync: true, supportsSwap: false, supportsBridge: false, supportsStake: false, supportsWalletConnect: false, supportsAlerts: true, supportsCustomRPC: false),
        .init(chainId: "dai-erc20", displayName: "Dai", supportTier: .launch, supportsSend: true, supportsReceive: true, supportsHistorySync: true, supportsSwap: false, supportsBridge: false, supportsStake: false, supportsWalletConnect: false, supportsAlerts: true, supportsCustomRPC: false),
        .init(chainId: "arbitrum", displayName: "Arbitrum", supportTier: .internalTest, supportsSend: true, supportsReceive: true, supportsHistorySync: false, supportsSwap: true, supportsBridge: true, supportsStake: false, supportsWalletConnect: true, supportsAlerts: true, supportsCustomRPC: true),
        .init(chainId: "optimism", displayName: "Optimism", supportTier: .internalTest, supportsSend: true, supportsReceive: true, supportsHistorySync: false, supportsSwap: true, supportsBridge: true, supportsStake: false, supportsWalletConnect: true, supportsAlerts: false, supportsCustomRPC: true),
        .init(chainId: "base", displayName: "Base", supportTier: .internalTest, supportsSend: true, supportsReceive: true, supportsHistorySync: false, supportsSwap: true, supportsBridge: true, supportsStake: false, supportsWalletConnect: true, supportsAlerts: false, supportsCustomRPC: true),
        .init(chainId: "avalanche", displayName: "Avalanche", supportTier: .internalTest, supportsSend: true, supportsReceive: true, supportsHistorySync: false, supportsSwap: true, supportsBridge: true, supportsStake: false, supportsWalletConnect: true, supportsAlerts: false, supportsCustomRPC: true),
        .init(chainId: "fantom", displayName: "Fantom", supportTier: .deferred, supportsSend: true, supportsReceive: true, supportsHistorySync: false, supportsSwap: true, supportsBridge: true, supportsStake: false, supportsWalletConnect: true, supportsAlerts: false, supportsCustomRPC: false),
        .init(chainId: "gnosis", displayName: "Gnosis", supportTier: .deferred, supportsSend: true, supportsReceive: true, supportsHistorySync: false, supportsSwap: true, supportsBridge: true, supportsStake: false, supportsWalletConnect: true, supportsAlerts: false, supportsCustomRPC: false),
        .init(chainId: "scroll", displayName: "Scroll", supportTier: .deferred, supportsSend: true, supportsReceive: true, supportsHistorySync: false, supportsSwap: true, supportsBridge: true, supportsStake: false, supportsWalletConnect: true, supportsAlerts: false, supportsCustomRPC: false),
        .init(chainId: "monero", displayName: "Monero", supportTier: .deferred, supportsSend: true, supportsReceive: true, supportsHistorySync: false, supportsSwap: false, supportsBridge: false, supportsStake: false, supportsWalletConnect: false, supportsAlerts: false, supportsCustomRPC: false),
    ]

    private static let capabilitiesByChainId = Dictionary(uniqueKeysWithValues: orderedCapabilities.map { ($0.chainId, $0) })

    static var launchChainIDs: [String] {
        orderedCapabilities.filter { $0.supportTier == .launch }.map(\.chainId)
    }

    static var customRPCChainNames: [String] {
        orderedCapabilities
            .filter { isVisible($0.chainId) && $0.supportsCustomRPC }
            .map(\.displayName)
    }

    static var syncSupportedChainIDs: [String] {
        orderedCapabilities
            .filter { isVisible($0.chainId) && $0.supportsHistorySync }
            .map(\.chainId)
    }

    static func capability(for chainId: String) -> ChainCapability? {
        capabilitiesByChainId[chainId.lowercased()]
    }

    static func isVisible(_ chainId: String) -> Bool {
        guard let capability = capability(for: chainId) else { return false }
        switch capability.supportTier {
        case .launch:
            return true
        case .internalTest, .deferred:
            return developmentFeaturesEnabled
        }
    }

    static func visibleChains(from chains: [ChainInfo]) -> [ChainInfo] {
        chains.filter { isVisible($0.id) }
    }

    static func hasVisibleSupport(for feature: ChainFeature) -> Bool {
        orderedCapabilities.contains { capability in
            supports(feature, chainId: capability.chainId)
        }
    }

    static func supports(_ feature: ChainFeature, chainId: String) -> Bool {
        guard isVisible(chainId), let capability = capability(for: chainId) else { return false }
        switch feature {
        case .send: return capability.supportsSend
        case .receive: return capability.supportsReceive
        case .historySync: return capability.supportsHistorySync
        case .swap: return capability.supportsSwap
        case .bridge: return capability.supportsBridge
        case .stake: return capability.supportsStake
        case .walletConnect: return capability.supportsWalletConnect
        case .alerts: return capability.supportsAlerts
        case .customRPC: return capability.supportsCustomRPC
        }
    }

    static func supportsSend(_ chainId: String) -> Bool {
        supports(.send, chainId: chainId)
    }

    static func supportsHistorySync(_ chainId: String) -> Bool {
        supports(.historySync, chainId: chainId)
    }

    static func supportsCustomRPC(displayName: String) -> Bool {
        orderedCapabilities.contains { capability in
            capability.displayName == displayName &&
            isVisible(capability.chainId) &&
            capability.supportsCustomRPC
        }
    }
}
