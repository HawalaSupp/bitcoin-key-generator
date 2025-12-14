import Foundation
import CryptoKit

// MARK: - HD Wallet

/// A hierarchical deterministic wallet derived from a BIP39 seed phrase.
/// The seed phrase itself is stored separately in secure storage - this struct
/// only contains metadata and derived account information.
struct HDWallet: WalletIdentity, Equatable, Hashable {
    /// Unique identifier derived deterministically from the seed
    let id: UUID
    
    /// User-defined wallet name
    var name: String
    
    /// When the wallet was created
    let createdAt: Date
    
    /// The derivation scheme used (BIP44, BIP49, BIP84)
    let derivationScheme: DerivationScheme
    
    /// Derived accounts for each chain
    var accounts: [HDAccount]
    
    /// Whether a BIP39 passphrase is used (we don't store the passphrase itself)
    let hasPassphrase: Bool
    
    /// Version for migration support
    let version: Int
    
    // MARK: - Initialization
    
    /// Create a new HD wallet with a deterministic ID from seed
    /// - Parameters:
    ///   - seedFingerprint: First 8 bytes of SHA256(seed) used to derive wallet ID
    ///   - name: User-provided wallet name
    ///   - derivationScheme: The BIP derivation scheme to use
    ///   - hasPassphrase: Whether a BIP39 passphrase was used
    init(
        seedFingerprint: Data,
        name: String,
        derivationScheme: DerivationScheme = .bip84,
        hasPassphrase: Bool = false
    ) {
        // Create deterministic UUID from seed fingerprint
        self.id = HDWallet.deriveWalletID(from: seedFingerprint)
        self.name = name
        self.createdAt = Date()
        self.derivationScheme = derivationScheme
        self.accounts = []
        self.hasPassphrase = hasPassphrase
        self.version = 1
    }
    
    /// Create from existing data (e.g., loaded from storage)
    init(
        id: UUID,
        name: String,
        createdAt: Date,
        derivationScheme: DerivationScheme,
        accounts: [HDAccount],
        hasPassphrase: Bool,
        version: Int = 1
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.derivationScheme = derivationScheme
        self.accounts = accounts
        self.hasPassphrase = hasPassphrase
        self.version = version
    }
    
    // MARK: - ID Derivation
    
    /// Derive a deterministic wallet UUID from seed fingerprint
    /// This ensures the same seed always produces the same wallet ID
    static func deriveWalletID(from seedFingerprint: Data) -> UUID {
        // Use first 16 bytes of SHA256 hash as UUID bytes
        let hash = SHA256.hash(data: seedFingerprint)
        var uuidBytes = [UInt8](repeating: 0, count: 16)
        hash.withUnsafeBytes { hashBytes in
            for i in 0..<16 {
                uuidBytes[i] = hashBytes[i]
            }
        }
        // Set UUID version (4) and variant bits per RFC 4122
        uuidBytes[6] = (uuidBytes[6] & 0x0F) | 0x40  // Version 4
        uuidBytes[8] = (uuidBytes[8] & 0x3F) | 0x80  // Variant 1
        
        let uuid = UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))
        return uuid
    }
    
    /// Calculate seed fingerprint from raw seed bytes
    static func calculateFingerprint(from seed: Data) -> Data {
        let hash = SHA256.hash(data: seed)
        return Data(hash.prefix(8))
    }
    
    // MARK: - Account Management
    
    /// Get account for a specific chain
    func account(for chain: ChainIdentifier) -> HDAccount? {
        accounts.first { $0.chainId == chain }
    }
    
    /// Add or update an account for a chain
    mutating func setAccount(_ account: HDAccount) {
        if let index = accounts.firstIndex(where: { $0.chainId == account.chainId }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
    }
    
    /// Build derivation path for a specific chain and index
    func derivationPath(for chain: ChainIdentifier, accountIndex: UInt32 = 0, change: UInt32 = 0, addressIndex: UInt32 = 0) -> String {
        let purpose = derivationScheme.purpose
        let coinType = chain.coinType
        return "m/\(purpose)'/\(coinType)'/\(accountIndex)'/\(change)/\(addressIndex)"
    }
}

// MARK: - Codable

extension HDWallet: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, createdAt, derivationScheme, accounts, hasPassphrase, version
    }
}

// MARK: - Debug Description (Redacted)

extension HDWallet: CustomDebugStringConvertible {
    var debugDescription: String {
        "HDWallet(id: \(id.uuidString.prefix(8))..., name: \(name), accounts: \(accounts.count))"
    }
}
