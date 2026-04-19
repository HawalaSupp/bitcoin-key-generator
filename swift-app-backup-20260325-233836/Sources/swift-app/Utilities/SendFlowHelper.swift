import Foundation

/// Pure utility methods for the send flow — no UI or state dependencies.
enum SendFlowHelper {
    /// Map a chain-ID string to the `Chain` enum used by `SendView`.
    static func mapToChain(_ chainId: String) -> Chain {
        if chainId == "bitcoin-testnet" { return .bitcoinTestnet }
        if chainId == "bitcoin" || chainId == "bitcoin-mainnet" { return .bitcoinMainnet }
        if chainId == "ethereum-sepolia" { return .ethereumSepolia }
        if chainId == "ethereum" || chainId == "ethereum-mainnet" { return .ethereumMainnet }
        if chainId == "polygon" { return .polygon }
        if chainId == "bnb" { return .bnb }
        if chainId == "solana-devnet" { return .solanaDevnet }
        if chainId == "solana" || chainId == "solana-mainnet" { return .solanaMainnet }
        if chainId == "xrp-testnet" { return .xrpTestnet }
        if chainId == "xrp" || chainId == "xrp-mainnet" { return .xrpMainnet }
        if chainId == "monero" { return .monero }
        if chainId == "arbitrum" { return .arbitrum }
        if chainId == "optimism" { return .optimism }
        if chainId == "base" { return .base }
        if chainId == "avalanche" { return .avalanche }
        if chainId == "fantom" { return .fantom }
        if chainId == "gnosis" { return .gnosis }
        if chainId == "scroll" { return .scroll }
        return .bitcoinTestnet
    }

    /// Filter the wallet's chain list to only chains that support sending.
    static func sendEligibleChains(from keys: AllKeys) -> [ChainInfo] {
        keys.chainInfos.filter { isSendSupported(chainID: $0.id) }
    }

    /// Whether a given chain ID supports sending.
    static func isSendSupported(chainID: String) -> Bool {
        ChainCapabilityRegistry.supportsSend(chainID)
    }
}
