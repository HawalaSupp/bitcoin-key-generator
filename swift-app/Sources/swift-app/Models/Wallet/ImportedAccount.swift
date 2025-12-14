import Foundation

// MARK: - Imported Account

/// A standalone account imported via private key or WIF.
/// These are NOT part of the HD wallet derivation tree.
/// The private key is stored separately in secure storage.
struct ImportedAccount: WalletIdentity, Equatable, Hashable {
    /// Unique identifier for this account
    let id: UUID
    
    /// User-defined name for this account
    var name: String
    
    /// The blockchain this account is for
    let chainId: ChainIdentifier
    
    /// The account address
    let address: String
    
    /// When the account was imported
    let createdAt: Date
    
    /// Import method used
    let importMethod: ImportMethod
    
    /// Version for migration support
    let version: Int
    
    // MARK: - Import Method
    
    enum ImportMethod: String, Codable, Sendable {
        case privateKey = "private_key"
        case wif = "wif"  // Wallet Import Format (Bitcoin)
        case keystore = "keystore"  // Ethereum JSON keystore
    }
    
    // MARK: - Initialization
    
    init(
        chainId: ChainIdentifier,
        address: String,
        name: String? = nil,
        importMethod: ImportMethod = .privateKey
    ) {
        self.id = UUID()
        self.chainId = chainId
        self.address = address
        self.name = name ?? "\(chainId.displayName) (Imported)"
        self.createdAt = Date()
        self.importMethod = importMethod
        self.version = 1
    }
    
    /// Create from existing data (e.g., loaded from storage)
    init(
        id: UUID,
        chainId: ChainIdentifier,
        address: String,
        name: String,
        createdAt: Date,
        importMethod: ImportMethod,
        version: Int = 1
    ) {
        self.id = id
        self.chainId = chainId
        self.address = address
        self.name = name
        self.createdAt = createdAt
        self.importMethod = importMethod
        self.version = version
    }
    
    // MARK: - Display
    
    /// Shortened address for display
    var shortAddress: String {
        guard address.count > 12 else { return address }
        let prefix = address.prefix(6)
        let suffix = address.suffix(4)
        return "\(prefix)…\(suffix)"
    }
    
    /// Type indicator for UI
    var typeLabel: String {
        "Imported"
    }
}

// MARK: - Codable

extension ImportedAccount: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, chainId, address, createdAt, importMethod, version
    }
}

// MARK: - Debug Description (Redacted)

extension ImportedAccount: CustomDebugStringConvertible {
    var debugDescription: String {
        "ImportedAccount(\(chainId.symbol), address: \(shortAddress))"
    }
}
