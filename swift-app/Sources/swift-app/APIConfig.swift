import Foundation

struct APIConfig {
    // MARK: - Alchemy Configuration
    // API keys are loaded from APIKeys.swift (not tracked in Git)
    // See APIKeys.swift.template for setup instructions
    static let alchemyAPIKey = APIKeys.alchemyAPIKey
    
    // Alchemy endpoints
    static var alchemyMainnetURL: String {
        "https://eth-mainnet.g.alchemy.com/v2/\(alchemyAPIKey)"
    }
    
    // MARK: - RPC Configuration
    private static let xrplPrimaryURL = "https://xrplcluster.com"
    private static let xrplSecondaryURL = "https://xrpl.ws"
    private static let xrplLegacyURL = "https://s1.ripple.com:51234/"

    static var xrplEndpoints: [String] {
        [xrplPrimaryURL, xrplSecondaryURL, xrplLegacyURL]
    }

    static var xrplPublicURL: String { xrplEndpoints.first ?? xrplLegacyURL }
    
    // MARK: - Helper Methods
    static func isAlchemyConfigured() -> Bool {
        return !alchemyAPIKey.isEmpty && alchemyAPIKey != "YOUR_ALCHEMY_API_KEY_HERE"
    }
}
