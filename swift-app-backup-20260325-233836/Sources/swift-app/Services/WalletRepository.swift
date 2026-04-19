import Foundation
import Security

// MARK: - Wallet Repository

/// Manages multiple wallets/seed phrases with secure storage
@MainActor
final class WalletRepository: ObservableObject {
    static let shared = WalletRepository()
    
    // MARK: - Published Properties
    
    @Published private(set) var wallets: [WalletProfile] = []
    @Published private(set) var activeWalletId: UUID?
    @Published private(set) var isLoading = false
    @Published private(set) var error: WalletError?
    
    // MARK: - Private Properties
    
    private let keychainService = "com.hawala.walletrepository"
    private let walletsKey = "hawala_wallet_profiles"
    private let activeWalletKey = "hawala_active_wallet"
    private var hasLoadedConfig = false
    
    // MARK: - Computed Properties
    
    var activeWallet: WalletProfile? {
        guard let id = activeWalletId else { return wallets.first }
        return wallets.first { $0.id == id }
    }
    
    var hasWallets: Bool {
        !wallets.isEmpty
    }
    
    var walletCount: Int {
        wallets.count
    }
    
    // MARK: - Initialization
    
    private init() {
        // DON'T load from keychain on init - defer to avoid password prompts
    }
    
    /// Lazy load configuration from keychain
    public func ensureConfigurationLoaded() {
        guard !hasLoadedConfig else { return }
        hasLoadedConfig = true
        loadWallets()
    }
    
    // MARK: - Public Methods
    
    /// Create a new wallet with generated or imported seed phrase
    func createWallet(
        name: String,
        seedPhrase: [String],
        passphrase: String? = nil,
        isWatchOnly: Bool = false
    ) async throws -> WalletProfile {
        isLoading = true
        defer { isLoading = false }
        
        // Validate seed phrase
        guard validateSeedPhrase(seedPhrase) else {
            throw WalletError.invalidSeedPhrase
        }
        
        // Check for duplicate
        let phraseHash = hashSeedPhrase(seedPhrase)
        if wallets.contains(where: { $0.seedPhraseHash == phraseHash }) {
            throw WalletError.duplicateWallet
        }
        
        // Create wallet profile
        let wallet = WalletProfile(
            id: UUID(),
            name: name,
            createdAt: Date(),
            seedPhraseHash: phraseHash,
            hasPassphrase: passphrase != nil,
            isWatchOnly: isWatchOnly,
            order: wallets.count,
            colorIndex: wallets.count % WalletProfile.availableColors.count
        )
        
        // Store seed phrase securely
        try storeSeedPhrase(seedPhrase, for: wallet.id, passphrase: passphrase)
        
        // Update wallets list
        wallets.append(wallet)
        saveWallets()
        
        // Set as active if first wallet
        if wallets.count == 1 {
            setActiveWallet(wallet.id)
        }
        
        return wallet
    }
    
    /// Import a watch-only wallet (address only, no private keys)
    func importWatchOnlyWallet(
        name: String,
        addresses: [WatchOnlyAddress]
    ) throws -> WalletProfile {
        let wallet = WalletProfile(
            id: UUID(),
            name: name,
            createdAt: Date(),
            seedPhraseHash: nil,
            hasPassphrase: false,
            isWatchOnly: true,
            order: wallets.count,
            colorIndex: wallets.count % WalletProfile.availableColors.count,
            watchOnlyAddresses: addresses
        )
        
        wallets.append(wallet)
        saveWallets()
        
        if wallets.count == 1 {
            setActiveWallet(wallet.id)
        }
        
        return wallet
    }
    
    /// Set the active wallet
    func setActiveWallet(_ id: UUID) {
        guard wallets.contains(where: { $0.id == id }) else { return }
        activeWalletId = id
        UserDefaults.standard.set(id.uuidString, forKey: activeWalletKey)
    }
    
    /// Rename a wallet
    func renameWallet(_ id: UUID, to newName: String) {
        guard let index = wallets.firstIndex(where: { $0.id == id }) else { return }
        wallets[index].name = newName
        saveWallets()
    }
    
    /// Update wallet color
    func updateWalletColor(_ id: UUID, colorIndex: Int) {
        guard let index = wallets.firstIndex(where: { $0.id == id }) else { return }
        wallets[index].colorIndex = colorIndex
        saveWallets()
    }
    
    /// Reorder wallets
    func reorderWallets(from source: IndexSet, to destination: Int) {
        var updated = wallets
        updated.move(fromOffsets: source, toOffset: destination)
        wallets = updated
        for (index, _) in wallets.enumerated() {
            wallets[index].order = index
        }
        saveWallets()
    }
    
    /// Delete a wallet
    func deleteWallet(_ id: UUID) throws {
        guard let index = wallets.firstIndex(where: { $0.id == id }) else {
            throw WalletError.walletNotFound
        }
        
        // Delete seed phrase from keychain
        deleteSeedPhrase(for: id)
        
        // Remove from list
        wallets.remove(at: index)
        saveWallets()
        
        // Update active wallet if needed
        if activeWalletId == id {
            activeWalletId = wallets.first?.id
            if let newActive = activeWalletId {
                UserDefaults.standard.set(newActive.uuidString, forKey: activeWalletKey)
            }
        }
    }
    
    /// Retrieve seed phrase for a wallet (requires authentication)
    func getSeedPhrase(for walletId: UUID) throws -> [String]? {
        guard let wallet = wallets.first(where: { $0.id == walletId }),
              !wallet.isWatchOnly else {
            return nil
        }
        
        return try retrieveSeedPhrase(for: walletId)
    }
    
    /// Verify if a seed phrase matches the stored one
    func verifySeedPhrase(_ phrase: [String], for walletId: UUID) -> Bool {
        guard let wallet = wallets.first(where: { $0.id == walletId }),
              let storedHash = wallet.seedPhraseHash else {
            return false
        }
        
        return hashSeedPhrase(phrase) == storedHash
    }
    
    // MARK: - Private Methods
    
    private func loadWallets() {
        // Load wallet profiles from UserDefaults
        if let data = UserDefaults.standard.data(forKey: walletsKey),
           let decoded = try? JSONDecoder().decode([WalletProfile].self, from: data) {
            wallets = decoded.sorted { $0.order < $1.order }
        }
        
        // Load active wallet
        if let activeIdString = UserDefaults.standard.string(forKey: activeWalletKey),
           let activeId = UUID(uuidString: activeIdString),
           wallets.contains(where: { $0.id == activeId }) {
            activeWalletId = activeId
        } else {
            activeWalletId = wallets.first?.id
        }
    }
    
    private func saveWallets() {
        if let encoded = try? JSONEncoder().encode(wallets) {
            UserDefaults.standard.set(encoded, forKey: walletsKey)
        }
    }
    
    private func validateSeedPhrase(_ phrase: [String]) -> Bool {
        // Valid BIP39 seed phrases are 12, 15, 18, 21, or 24 words
        let validLengths = [12, 15, 18, 21, 24]
        guard validLengths.contains(phrase.count) else { return false }
        
        // All words should be lowercase letters only
        for word in phrase {
            guard word.allSatisfy({ $0.isLetter && $0.isLowercase }) else {
                return false
            }
        }
        
        return true
    }
    
    private func hashSeedPhrase(_ phrase: [String]) -> String {
        let combined = phrase.joined(separator: " ")
        guard let data = combined.data(using: .utf8) else { return "" }
        
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    private func storeSeedPhrase(_ phrase: [String], for walletId: UUID, passphrase: String?) throws {
        let combined = phrase.joined(separator: " ")
        guard let data = combined.data(using: .utf8) else {
            throw WalletError.encryptionFailed
        }
        
        // If passphrase provided, encrypt the data
        let dataToStore: Data
        if let passphrase = passphrase, !passphrase.isEmpty {
            dataToStore = try encryptData(data, with: passphrase)
        } else {
            dataToStore = data
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: walletId.uuidString,
            kSecValueData as String: dataToStore,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete existing if any
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw WalletError.keychainError(status)
        }
    }
    
    private func retrieveSeedPhrase(for walletId: UUID) throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: walletId.uuidString,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        // Handle user cancellation gracefully
        if status == errSecUserCanceled {
            throw WalletError.userCancelled
        }
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let phrase = String(data: data, encoding: .utf8) else {
            throw WalletError.keychainError(status)
        }
        
        return phrase.split(separator: " ").map(String.init)
    }
    
    private func deleteSeedPhrase(for walletId: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: walletId.uuidString
        ]
        
        SecItemDelete(query as CFDictionary)
    }
    
    private func encryptData(_ data: Data, with passphrase: String) throws -> Data {
        // Simple XOR encryption for demo - in production use AES-GCM
        guard let passphraseData = passphrase.data(using: .utf8) else {
            throw WalletError.encryptionFailed
        }
        
        var encrypted = Data(count: data.count)
        for i in 0..<data.count {
            encrypted[i] = data[i] ^ passphraseData[i % passphraseData.count]
        }
        
        return encrypted
    }
}

// MARK: - Wallet Profile Model

struct WalletProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let createdAt: Date
    let seedPhraseHash: String?
    let hasPassphrase: Bool
    let isWatchOnly: Bool
    var order: Int
    var colorIndex: Int
    var watchOnlyAddresses: [WatchOnlyAddress]?
    
    // Available colors for wallet identification
    static let availableColors: [String] = [
        "blue", "green", "orange", "purple", "pink", "cyan", "yellow", "red", "indigo", "mint"
    ]
    
    var colorName: String {
        Self.availableColors[colorIndex % Self.availableColors.count]
    }
    
    var icon: String {
        isWatchOnly ? "eye.circle.fill" : "wallet.pass.fill"
    }
    
    var subtitle: String {
        if isWatchOnly {
            let count = watchOnlyAddresses?.count ?? 0
            return "\(count) address\(count == 1 ? "" : "es") • Watch-only"
        } else {
            return hasPassphrase ? "Protected with passphrase" : "Standard wallet"
        }
    }
}

// MARK: - Watch-Only Address Model

struct WatchOnlyAddress: Codable, Identifiable, Equatable {
    let id: UUID
    let chain: String  // "bitcoin", "ethereum", etc.
    let address: String
    var label: String?
    let addedAt: Date
    
    init(chain: String, address: String, label: String? = nil) {
        self.id = UUID()
        self.chain = chain
        self.address = address
        self.label = label
        self.addedAt = Date()
    }
}

// MARK: - Wallet Error

enum WalletError: Error, LocalizedError {
    case invalidSeedPhrase
    case duplicateWallet
    case walletNotFound
    case keychainError(OSStatus)
    case encryptionFailed
    case decryptionFailed
    case userCancelled
    
    var errorDescription: String? {
        switch self {
        case .invalidSeedPhrase:
            return "Invalid seed phrase. Must be 12, 15, 18, 21, or 24 words."
        case .duplicateWallet:
            return "A wallet with this seed phrase already exists."
        case .walletNotFound:
            return "Wallet not found."
        case .keychainError(let status):
            return "Keychain error: \(status)"
        case .encryptionFailed:
            return "Failed to encrypt wallet data."
        case .decryptionFailed:
            return "Failed to decrypt wallet data."
        case .userCancelled:
            return "Keychain authentication was cancelled by user"
        }
    }
}

// MARK: - CommonCrypto Import

import CommonCrypto
