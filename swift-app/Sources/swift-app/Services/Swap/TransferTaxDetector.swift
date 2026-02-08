import Foundation

// MARK: - Transfer Tax Token Detection (ROADMAP-07 E11)

/// Detects tokens with built-in transfer taxes (e.g., SafeMoon, EverGrow)
/// that can cause users to receive less than quoted in swaps.
struct TransferTaxDetector {
    
    /// Known taxed token info
    struct TaxedToken {
        let symbol: String
        let name: String
        let taxPercentage: Double
        let addresses: [String: String] // chainId → address (lowercased)
    }
    
    /// Registry of known transfer-tax tokens
    /// Addresses are lowercased for case-insensitive matching
    static let knownTaxTokens: [TaxedToken] = [
        TaxedToken(
            symbol: "SFM",
            name: "SafeMoon V2",
            taxPercentage: 10.0,
            addresses: [
                "bsc": "0x42981d0bfbaf196529376ee702f2a9eb9092fcb5"
            ]
        ),
        TaxedToken(
            symbol: "EGC",
            name: "EverGrow Coin",
            taxPercentage: 14.0,
            addresses: [
                "bsc": "0xc001bbe2b87079294c63ece98bdd0a88d761434e"
            ]
        ),
        TaxedToken(
            symbol: "BABYDOGE",
            name: "Baby Doge Coin",
            taxPercentage: 10.0,
            addresses: [
                "bsc": "0xc748673057861a797275cd8a068abb95a902e8de",
                "ethereum": "0xac57de9c1a09fec648e93eb98a1b5a4cf3e05386"
            ]
        ),
        TaxedToken(
            symbol: "FLOKI",
            name: "Floki Inu",
            taxPercentage: 3.0,
            addresses: [
                "bsc": "0xfb5b838b6cfeedc2873ab27866079ac55363d37e",
                "ethereum": "0xcf0c122c6b73ff809c693db761e7baebe62b6a2e"
            ]
        ),
        TaxedToken(
            symbol: "SAFEMOON",
            name: "SafeMoon V1 (Deprecated)",
            taxPercentage: 10.0,
            addresses: [
                "bsc": "0x8076c74c5e3f5852037f31ff0093eeb8c8add8d3"
            ]
        ),
        TaxedToken(
            symbol: "TKING",
            name: "Tiger King",
            taxPercentage: 5.0,
            addresses: [
                "ethereum": "0x24e89bdf2f65326b94e36978a7edeac63623dafa"
            ]
        ),
        TaxedToken(
            symbol: "TSUKA",
            name: "Dejitaru Tsuka",
            taxPercentage: 5.0,
            addresses: [
                "ethereum": "0xc5fb36dd2fb59d3b98deff88425a3f425ee469ed"
            ]
        ),
        TaxedToken(
            symbol: "LUFFY",
            name: "Luffy",
            taxPercentage: 5.0,
            addresses: [
                "ethereum": "0x7121d00b4fa18f13da6c2e30d19c04844e6afdc8"
            ]
        ),
    ]
    
    /// Check if a token address is a known transfer-tax token
    /// - Parameters:
    ///   - address: The token contract address
    ///   - chainId: The chain identifier (e.g., "ethereum", "bsc")
    /// - Returns: The TaxedToken info if found, nil otherwise
    static func detectTax(address: String, chainId: String) -> TaxedToken? {
        let normalizedAddress = address.lowercased()
        let normalizedChain = chainId.lowercased()
        
        return knownTaxTokens.first { token in
            token.addresses[normalizedChain]?.lowercased() == normalizedAddress
        }
    }
    
    /// Check if a token symbol might be a known transfer-tax token
    /// This is a fallback for when we don't have the contract address
    /// - Parameter symbol: The token symbol (e.g., "SFM", "BABYDOGE")
    /// - Returns: The TaxedToken info if found, nil otherwise
    static func detectTaxBySymbol(_ symbol: String) -> TaxedToken? {
        let normalized = symbol.uppercased()
        return knownTaxTokens.first { $0.symbol.uppercased() == normalized }
    }
    
    /// Format a user-facing warning message for a taxed token
    static func warningMessage(for token: TaxedToken) -> String {
        "⚠️ \(token.name) (\(token.symbol)) has a ~\(String(format: "%.0f", token.taxPercentage))% transfer tax. You may receive less than the quoted amount."
    }
}
