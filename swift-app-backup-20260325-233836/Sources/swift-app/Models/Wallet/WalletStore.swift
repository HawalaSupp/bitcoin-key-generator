import Foundation

// MARK: - Wallet Store Protocol

/// Protocol defining the interface for wallet persistence.
/// Implementations may use Keychain, encrypted files, or other secure storage.
protocol WalletStoreProtocol: Sendable {
    // MARK: - HD Wallet Operations
    
    /// Save or update an HD wallet's metadata (not the seed)
    func saveHDWallet(_ wallet: HDWallet) async throws
    
    /// Load an HD wallet by ID
    func loadHDWallet(id: UUID) async throws -> HDWallet?
    
    /// Load all HD wallets
    func loadAllHDWallets() async throws -> [HDWallet]
    
    /// Delete an HD wallet and all associated accounts
    func deleteHDWallet(id: UUID) async throws
    
    // MARK: - Imported Account Operations
    
    /// Save or update an imported account's metadata (not the private key)
    func saveImportedAccount(_ account: ImportedAccount) async throws
    
    /// Load an imported account by ID
    func loadImportedAccount(id: UUID) async throws -> ImportedAccount?
    
    /// Load all imported accounts
    func loadAllImportedAccounts() async throws -> [ImportedAccount]
    
    /// Delete an imported account
    func deleteImportedAccount(id: UUID) async throws
    
    // MARK: - Batch Operations
    
    /// Check if any wallets exist
    func hasWallets() async throws -> Bool
    
    /// Delete all wallets and accounts (for reset)
    func deleteAll() async throws
}

// MARK: - Wallet Store Errors

enum WalletStoreError: LocalizedError {
    case walletNotFound(UUID)
    case accountNotFound(UUID)
    case encodingFailed(Error)
    case decodingFailed(Error)
    case storageFailed(Error)
    case migrationRequired(fromVersion: Int, toVersion: Int)
    
    var errorDescription: String? {
        switch self {
        case .walletNotFound(let id):
            return "Wallet not found: \(id.uuidString.prefix(8))..."
        case .accountNotFound(let id):
            return "Account not found: \(id.uuidString.prefix(8))..."
        case .encodingFailed(let error):
            return "Failed to encode wallet data: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "Failed to decode wallet data: \(error.localizedDescription)"
        case .storageFailed(let error):
            return "Storage operation failed: \(error.localizedDescription)"
        case .migrationRequired(let from, let to):
            return "Migration required from version \(from) to \(to)"
        }
    }
}

// MARK: - Wallet Store Container

/// Container holding all wallet metadata for serialization.
/// Secrets (seeds, private keys) are stored separately.
struct WalletStoreContainer: Codable, Sendable {
    /// Container format version for migrations
    let version: Int
    
    /// HD wallets (metadata only)
    var hdWallets: [HDWallet]
    
    /// Imported accounts (metadata only)
    var importedAccounts: [ImportedAccount]
    
    /// Last modified timestamp
    var lastModified: Date
    
    static let currentVersion = 1
    
    init(
        hdWallets: [HDWallet] = [],
        importedAccounts: [ImportedAccount] = []
    ) {
        self.version = Self.currentVersion
        self.hdWallets = hdWallets
        self.importedAccounts = importedAccounts
        self.lastModified = Date()
    }
}

// MARK: - User Defaults Wallet Store (Development Only)

/// Simple UserDefaults-based store for development/testing.
/// In production, use KeychainWalletStore or EncryptedFileStore.
final class UserDefaultsWalletStore: WalletStoreProtocol, @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let key = "com.hawala.wallet.store"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
    
    // MARK: - Private Helpers
    
    private func loadContainer() throws -> WalletStoreContainer {
        guard let data = userDefaults.data(forKey: key) else {
            return WalletStoreContainer()
        }
        do {
            return try decoder.decode(WalletStoreContainer.self, from: data)
        } catch {
            throw WalletStoreError.decodingFailed(error)
        }
    }
    
    private func saveContainer(_ container: WalletStoreContainer) throws {
        var mutableContainer = container
        mutableContainer.lastModified = Date()
        do {
            let data = try encoder.encode(mutableContainer)
            userDefaults.set(data, forKey: key)
        } catch {
            throw WalletStoreError.encodingFailed(error)
        }
    }
    
    // MARK: - HD Wallet Operations
    
    func saveHDWallet(_ wallet: HDWallet) async throws {
        var container = try loadContainer()
        if let index = container.hdWallets.firstIndex(where: { $0.id == wallet.id }) {
            container.hdWallets[index] = wallet
        } else {
            container.hdWallets.append(wallet)
        }
        try saveContainer(container)
    }
    
    func loadHDWallet(id: UUID) async throws -> HDWallet? {
        let container = try loadContainer()
        return container.hdWallets.first { $0.id == id }
    }
    
    func loadAllHDWallets() async throws -> [HDWallet] {
        let container = try loadContainer()
        return container.hdWallets
    }
    
    func deleteHDWallet(id: UUID) async throws {
        var container = try loadContainer()
        container.hdWallets.removeAll { $0.id == id }
        try saveContainer(container)
    }
    
    // MARK: - Imported Account Operations
    
    func saveImportedAccount(_ account: ImportedAccount) async throws {
        var container = try loadContainer()
        if let index = container.importedAccounts.firstIndex(where: { $0.id == account.id }) {
            container.importedAccounts[index] = account
        } else {
            container.importedAccounts.append(account)
        }
        try saveContainer(container)
    }
    
    func loadImportedAccount(id: UUID) async throws -> ImportedAccount? {
        let container = try loadContainer()
        return container.importedAccounts.first { $0.id == id }
    }
    
    func loadAllImportedAccounts() async throws -> [ImportedAccount] {
        let container = try loadContainer()
        return container.importedAccounts
    }
    
    func deleteImportedAccount(id: UUID) async throws {
        var container = try loadContainer()
        container.importedAccounts.removeAll { $0.id == id }
        try saveContainer(container)
    }
    
    // MARK: - Batch Operations
    
    func hasWallets() async throws -> Bool {
        let container = try loadContainer()
        return !container.hdWallets.isEmpty || !container.importedAccounts.isEmpty
    }
    
    func deleteAll() async throws {
        userDefaults.removeObject(forKey: key)
    }
}
