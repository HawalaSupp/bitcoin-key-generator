import Foundation

/// Centralized app version management
/// Increment the patch version for each release
enum AppVersion {
    /// Major version - breaking changes or major milestones
    static let major = 2
    
    /// Minor version - new features
    static let minor = 3
    
    /// Patch version - bug fixes and small improvements
    static let patch = 5
    
    /// Build number - auto-incremented by CI or manual bump
    static let build = 6
    
    /// Full version string (e.g., "2.2.0")
    static var version: String {
        "\(major).\(minor).\(patch)"
    }
    
    /// Full version with build (e.g., "2.2.0 (1)")
    static var versionWithBuild: String {
        "\(version) (\(build))"
    }
    
    /// Short display version (e.g., "v2.2")
    static var shortVersion: String {
        "v\(major).\(minor)"
    }
    
    /// Marketing version for UI display
    static var displayVersion: String {
        "Version \(major).\(minor)"
    }
}

// MARK: - Version History
/*
 Version History:
 
 v1.0 - Initial release with multi-chain key generation
 v1.1 - Added BIP-39 mnemonic support and encrypted backups
 v1.2 - Added send flows for Bitcoin, Ethereum, Litecoin, BNB, Solana
 v1.3 - Added biometric unlock, fiat currency selector, sparkline charts
 v1.4 - Added ENS/SNS resolution, clipboard auto-clear, pending tx tracking
 v1.5 - Added RBF/speed-up for stuck transactions, centralized version management
 v1.6 - Fixed CoinGecko rate limiting: increased polling interval to 2min, added API key support
 v1.7 - Biometric security: TouchID/FaceID required for sends and private key reveals
 v1.8 - Transaction history with live blockchain data and explorer links for all chains
 v1.9 - Dynamic gas fee controls: EIP-1559 support with speed selector for Ethereum sends
 v2.0 - Privacy blur: sensitive data hidden when app goes to background/app switcher
 v2.1 - Enhanced history: search/filter transactions, confirmations display, fee display, expandable details
 v2.2 - Contact address book, camera QR scanning, CSV export, transaction notes/labels
 */
