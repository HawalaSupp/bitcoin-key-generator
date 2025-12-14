import Foundation

struct APIConfig {
    // MARK: - Alchemy Configuration
    // API keys are loaded from APIKeys.swift (not tracked in Git)
    // See APIKeys.swift.template for setup instructions
    static let alchemyAPIKey = APIKeys.alchemyAPIKey
    
    // MARK: - WalletConnect Configuration
    // Project ID from https://cloud.walletconnect.com/
    static var walletConnectProjectId: String {
        // Try to get from APIKeys first, then environment variable
        if let apiKeysId = (APIKeys.self as AnyObject).value(forKey: "walletConnectProjectId") as? String,
           !apiKeysId.isEmpty && apiKeysId != "YOUR_WALLETCONNECT_PROJECT_ID_HERE" {
            return apiKeysId
        }
        return ProcessInfo.processInfo.environment["WALLETCONNECT_PROJECT_ID"] ?? ""
    }
    
    static func isWalletConnectConfigured() -> Bool {
        let projectId = walletConnectProjectId
        return !projectId.isEmpty && projectId != "YOUR_WALLETCONNECT_PROJECT_ID_HERE"
    }
    
    // Alchemy endpoints
    static var alchemyMainnetURL: String {
        "https://eth-mainnet.g.alchemy.com/v2/\(alchemyAPIKey)"
    }
    
    static var alchemySepoliaURL: String {
        "https://eth-sepolia.g.alchemy.com/v2/\(alchemyAPIKey)"
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
