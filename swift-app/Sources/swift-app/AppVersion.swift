import Foundation

/// Centralized app version management
/// Increment the patch version for each release
enum AppVersion {
    /// Major version - breaking changes or major milestones
    static let major = 1
    
    /// Minor version - new features
    static let minor = 5
    
    /// Patch version - bug fixes and small improvements
    static let patch = 0
    
    /// Build number - auto-incremented by CI or manual bump
    static let build = 1
    
    /// Full version string (e.g., "1.5.0")
    static var version: String {
        "\(major).\(minor).\(patch)"
    }
    
    /// Full version with build (e.g., "1.5.0 (1)")
    static var versionWithBuild: String {
        "\(version) (\(build))"
    }
    
    /// Short display version (e.g., "v1.5")
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
 */
