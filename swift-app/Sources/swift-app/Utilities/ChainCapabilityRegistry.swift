import Foundation

enum ChainSupportTier: String {
    case launch
    case internalTest
    case deferred
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
    private static let orderedCapabilities: [ChainCapability] = [
        .init(chainId: "bitcoin", displayName: "Bitcoin", supportTier: .launch, supportsSend: true, supportsReceive: true, supportsHistorySync: true, supportsSwap: false, supportsBridge: false, supportsStake: false, supportsWalletConnect: false, supportsAlerts: true, supportsCustomRPC: false),
        .init(chainId: "bitcoin-testnet", displayName: "Bitcoin Testnet", supportTier: .internalTest, supportsSend: true, supportsReceive: true, supportsHistorySync: true, supportsSwap: false, supportsBridge: false, supportsStake: false, supportsWalletConnect: false, supportsAlerts: false, supportsCustomRPC: false),
        .init(chainId: "litecoin", displayName: "Litecoin", supportTier: .launch, supportsSend: true, supportsReceive: true, supportsHistorySync: true, supportsSwap: false, supportsBridge: false, supportsStake: false, supportsWalletConnect: false, supportsAlerts: true, supportsCustomRPC: false),
        .init(chainId: "ethereum", displayName: "Ethereum", supportTier: .launch, supportsSend: true, supportsReceive: true, supportsHistorySync: true, supportsSwap: true, supportsBridge: true, supportsStake: true, supportsWalletConnect: true, supportsAlerts: true, supportsCustomRPC: true),
        .init(chainId: "ethereum-sepolia", displayName: "Sepolia", supportTier: .internalTest, supportsSend: true, supportsReceive: true, supportsHistorySync: true, supportsSwap: false, supportsBridge: false, supportsStake: false, supportsWalletConnect: false, supportsAlerts: false, supportsCustomRPC: true),
        .init(chainId: "bnb", displayName: "BNB", supportTier: .internalTest, supportsSend: true, supportsReceive: true, supportsHistorySync: false, supportsSwap: true, supportsBridge: true, supportsStake: false, supportsWalletConnect: true, supportsAlerts: false, supportsCustomRPC: true),
        .init(chainId: "solana", displayName: "Solana", supportTier: .launch, supportsSend: true, supportsReceive: true, supportsHistorySync: true, supportsSwap: true, supportsBridge: true, supportsStake: true, supportsWalletConnect: true, supportsAlerts: true, supportsCustomRPC: false),
        .init(chainId: "polygon", displayName: "Polygon", supportTier: .internalTest, supportsSend: true, supportsReceive: true, supportsHistorySync: false, supportsSwap: true, supportsBridge: true, supportsStake: false, supportsWalletConnect: true, supportsAlerts: true, supportsCustomRPC: true),
        .init(chainId: "xrp", displayName: "XRP", supportTier: .launch, supportsSend: true, supportsReceive: true, supportsHistorySync: true, supportsSwap: false, supportsBridge: false, supportsStake: false, supportsWalletConnect: false, supportsAlerts: true, supportsCustomRPC: false),
        .init(chainId: "xrp-testnet", displayName: "XRP Testnet", supportTier: .internalTest, supportsSend: true, supportsReceive: true, supportsHistorySync: false, supportsSwap: false, supportsBridge: false, supportsStake: false, supportsWalletConnect: false, supportsAlerts: false, supportsCustomRPC: false),
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

    static var customRPCChainNames: [String] {
        orderedCapabilities.filter(\.supportsCustomRPC).map(\.displayName)
    }

    static var syncSupportedChainIDs: [String] {
        orderedCapabilities.filter(\.supportsHistorySync).map(\.chainId)
    }

    static func capability(for chainId: String) -> ChainCapability? {
        capabilitiesByChainId[chainId.lowercased()]
    }

    static func supportsSend(_ chainId: String) -> Bool {
        if chainId.lowercased().contains("erc20") { return true }
        return capability(for: chainId)?.supportsSend ?? false
    }

    static func supportsHistorySync(_ chainId: String) -> Bool {
        capability(for: chainId)?.supportsHistorySync ?? false
    }

    static func supportsCustomRPC(displayName: String) -> Bool {
        orderedCapabilities.contains { $0.displayName == displayName && $0.supportsCustomRPC }
    }
}