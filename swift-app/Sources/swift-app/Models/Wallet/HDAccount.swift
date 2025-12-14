import Foundation

// MARK: - HD Account

/// A derived account within an HD wallet for a specific blockchain.
/// Contains the derivation path and cached address (derived from public key).
/// Private keys are derived on-demand and never stored.
struct HDAccount: Identifiable, Codable, Sendable, Equatable, Hashable {
    /// Unique identifier for this account
    let id: UUID
    
    /// The blockchain this account is for
    let chainId: ChainIdentifier
    
    /// Account index in BIP44 derivation (m/purpose'/coin'/account'/...)
    let accountIndex: UInt32
    
    /// The full derivation path used
    let derivationPath: String
    
    /// The derived address (cached for display)
    let address: String
    
    /// User-defined label for this account
    var label: String?
    
    /// When this account was derived
    let derivedAt: Date
    
    // MARK: - Initialization
    
    init(
        chainId: ChainIdentifier,
        accountIndex: UInt32,
        derivationPath: String,
        address: String,
        label: String? = nil
    ) {
        self.id = UUID()
        self.chainId = chainId
        self.accountIndex = accountIndex
        self.derivationPath = derivationPath
        self.address = address
        self.label = label
        self.derivedAt = Date()
    }
    
    /// Create from existing data (e.g., loaded from storage)
    init(
        id: UUID,
        chainId: ChainIdentifier,
        accountIndex: UInt32,
        derivationPath: String,
        address: String,
        label: String?,
        derivedAt: Date
    ) {
        self.id = id
        self.chainId = chainId
        self.accountIndex = accountIndex
        self.derivationPath = derivationPath
        self.address = address
        self.label = label
        self.derivedAt = derivedAt
    }
    
    // MARK: - Display
    
    /// Display name for the account
    var displayName: String {
        if let label = label, !label.isEmpty {
            return label
        }
        return "\(chainId.displayName) Account \(accountIndex)"
    }
    
    /// Shortened address for display
    var shortAddress: String {
        guard address.count > 12 else { return address }
        let prefix = address.prefix(6)
        let suffix = address.suffix(4)
        return "\(prefix)…\(suffix)"
    }
}

// MARK: - Debug Description

extension HDAccount: CustomDebugStringConvertible {
    var debugDescription: String {
        "HDAccount(\(chainId.symbol), index: \(accountIndex), address: \(shortAddress))"
    }
}
