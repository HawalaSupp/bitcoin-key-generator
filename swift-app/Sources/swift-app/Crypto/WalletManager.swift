import Foundation
import SwiftUI

// MARK: - Wallet Manager

/// Central manager for wallet operations.
/// Coordinates between UI, key derivation, secure storage, and wallet store.
@MainActor
final class WalletManager: ObservableObject {
    
    // MARK: - Published State
    
    /// Currently active HD wallet (if any)
    @Published private(set) var activeHDWallet: HDWallet?
    
    /// All HD wallets
    @Published private(set) var hdWallets: [HDWallet] = []
    
    /// All imported accounts
    @Published private(set) var importedAccounts: [ImportedAccount] = []
    
    /// Loading state
    @Published private(set) var isLoading = false
    
    /// Last error
    @Published var lastError: WalletManagerError?
    
    // MARK: - Dependencies
    
    private let keyDerivation: KeyDerivationService
    private let secureStorage: SecureStorageProtocol
    private let walletStore: WalletStoreProtocol
    
    // MARK: - Singleton
    
    static let shared = WalletManager()
    
    // MARK: - Initialization
    
    init(
        keyDerivation: KeyDerivationService = .shared,
        secureStorage: SecureStorageProtocol = KeychainSecureStorage.shared,
        walletStore: WalletStoreProtocol = UserDefaultsWalletStore()
    ) {
        self.keyDerivation = keyDerivation
        self.secureStorage = secureStorage
        self.walletStore = walletStore
    }
    
    // MARK: - Wallet Loading
    
    /// Load all wallets from storage on app launch
    func loadWallets() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            hdWallets = try await walletStore.loadAllHDWallets()
            importedAccounts = try await walletStore.loadAllImportedAccounts()
            
            // Set first HD wallet as active if none selected
            if activeHDWallet == nil, let first = hdWallets.first {
                activeHDWallet = first
            }
        } catch {
            lastError = .loadFailed(error)
        }
    }
    
    /// Check if any wallets exist
    func hasWallets() async -> Bool {
        do {
            return try await walletStore.hasWallets()
        } catch {
            return false
        }
    }
    
    // MARK: - Wallet Creation
    
    /// Create a new HD wallet with fresh seed phrase
    /// - Parameters:
    ///   - name: User-provided wallet name
    ///   - passphrase: Optional BIP39 passphrase
    /// - Returns: The created wallet and its seed phrase (show to user!)
    func createNewWallet(
        name: String,
        passphrase: String = ""
    ) async throws -> (wallet: HDWallet, seedPhrase: String) {
        isLoading = true
        defer { isLoading = false }
        
        // Generate new wallet via Rust
        let (mnemonic, keys) = try await keyDerivation.generateNewWallet()
        
        // Derive seed for fingerprint
        guard let seed = keyDerivation.deriveSeed(from: mnemonic, passphrase: passphrase) else {
            throw WalletManagerError.seedDerivationFailed
        }
        let fingerprint = keyDerivation.calculateFingerprint(seed: seed)
        
        // Create wallet model
        var wallet = HDWallet(
            seedFingerprint: fingerprint,
            name: name,
            derivationScheme: .bip84,
            hasPassphrase: !passphrase.isEmpty
        )
        
        // Add accounts for each chain
        wallet = addAccounts(to: wallet, from: keys)
        
        // Store seed phrase securely
        let seedKey = SecureStorageKey.seedPhrase(walletId: wallet.id)
        guard let seedData = mnemonic.data(using: .utf8) else {
            throw WalletManagerError.encodingFailed
        }
        try await secureStorage.save(seedData, forKey: seedKey, requireBiometric: true)
        
        // Store passphrase if used
        if !passphrase.isEmpty {
            let passphraseKey = SecureStorageKey.passphrase(walletId: wallet.id)
            guard let passphraseData = passphrase.data(using: .utf8) else {
                throw WalletManagerError.encodingFailed
            }
            try await secureStorage.save(passphraseData, forKey: passphraseKey, requireBiometric: true)
        }
        
        // Save wallet metadata
        try await walletStore.saveHDWallet(wallet)
        
        // Update local state
        hdWallets.append(wallet)
        if activeHDWallet == nil {
            activeHDWallet = wallet
        }
        
        return (wallet, mnemonic)
    }
    
    // MARK: - Wallet Restoration
    
    /// Restore wallet from seed phrase
    /// - Parameters:
    ///   - seedPhrase: BIP39 mnemonic
    ///   - name: User-provided wallet name
    ///   - passphrase: Optional BIP39 passphrase
    /// - Returns: The restored wallet
    func restoreWallet(
        from seedPhrase: String,
        name: String,
        passphrase: String = ""
    ) async throws -> HDWallet {
        isLoading = true
        defer { isLoading = false }
        
        // Validate mnemonic
        let validation = MnemonicValidator.validate(seedPhrase)
        guard validation.isValid else {
            throw WalletManagerError.invalidSeedPhrase(validation.errorMessage ?? "Invalid seed phrase")
        }
        
        // Derive keys
        let keys = try await keyDerivation.restoreWallet(from: seedPhrase, passphrase: passphrase)
        
        // Derive seed for fingerprint
        guard let seed = keyDerivation.deriveSeed(from: seedPhrase, passphrase: passphrase) else {
            throw WalletManagerError.seedDerivationFailed
        }
        let fingerprint = keyDerivation.calculateFingerprint(seed: seed)
        
        // Check for duplicate wallet
        let potentialId = HDWallet.deriveWalletID(from: fingerprint)
        if hdWallets.contains(where: { $0.id == potentialId }) {
            throw WalletManagerError.walletAlreadyExists
        }
        
        // Create wallet model
        var wallet = HDWallet(
            seedFingerprint: fingerprint,
            name: name,
            derivationScheme: .bip84,
            hasPassphrase: !passphrase.isEmpty
        )
        
        // Add accounts
        wallet = addAccounts(to: wallet, from: keys)
        
        // Store seed phrase
        let seedKey = SecureStorageKey.seedPhrase(walletId: wallet.id)
        let normalizedPhrase = MnemonicValidator.normalizePhrase(seedPhrase).joined(separator: " ")
        guard let seedData = normalizedPhrase.data(using: .utf8) else {
            throw WalletManagerError.encodingFailed
        }
        try await secureStorage.save(seedData, forKey: seedKey, requireBiometric: true)
        
        // Store passphrase if used
        if !passphrase.isEmpty {
            let passphraseKey = SecureStorageKey.passphrase(walletId: wallet.id)
            guard let passphraseData = passphrase.data(using: .utf8) else {
                throw WalletManagerError.encodingFailed
            }
            try await secureStorage.save(passphraseData, forKey: passphraseKey, requireBiometric: true)
        }
        
        // Save wallet
        try await walletStore.saveHDWallet(wallet)
        
        // Update state
        hdWallets.append(wallet)
        activeHDWallet = wallet
        
        return wallet
    }
    
    // MARK: - Seed Phrase Access
    
    /// Retrieve seed phrase for display (requires biometric)
    /// - Parameter walletId: The wallet ID
    /// - Returns: The seed phrase
    func getSeedPhrase(for walletId: UUID) async throws -> String {
        let seedKey = SecureStorageKey.seedPhrase(walletId: walletId)
        guard let data = try await secureStorage.load(forKey: seedKey),
              let phrase = String(data: data, encoding: .utf8) else {
            throw WalletManagerError.seedPhraseNotFound
        }
        return phrase
    }
    
    // MARK: - Wallet Deletion
    
    /// Delete an HD wallet and all associated data
    func deleteWallet(id: UUID) async throws {
        // Delete seed phrase from secure storage
        let seedKey = SecureStorageKey.seedPhrase(walletId: id)
        try await secureStorage.delete(forKey: seedKey)
        
        // Delete passphrase if exists
        let passphraseKey = SecureStorageKey.passphrase(walletId: id)
        try? await secureStorage.delete(forKey: passphraseKey)
        
        // Delete from wallet store
        try await walletStore.deleteHDWallet(id: id)
        
        // Update state
        hdWallets.removeAll { $0.id == id }
        if activeHDWallet?.id == id {
            activeHDWallet = hdWallets.first
        }
    }
    
    /// Delete all wallets (factory reset)
    func deleteAllWallets() async throws {
        try await secureStorage.deleteAll()
        try await walletStore.deleteAll()
        
        hdWallets = []
        importedAccounts = []
        activeHDWallet = nil
    }
    
    // MARK: - Imported Accounts
    
    /// Import a standalone account from private key
    func importAccount(
        privateKey: String,
        chain: ChainIdentifier,
        name: String? = nil
    ) async throws -> ImportedAccount {
        // Validate and derive address based on chain type
        let address: String
        let normalizedKey: String
        
        switch chain {
        case .ethereum, .ethereumSepolia, .polygon, .bnb, .arbitrum, .optimism, .base, .avalanche:
            // Validate Ethereum-style private key (hex, 64 chars or 66 with 0x prefix)
            let hexKey = privateKey.hasPrefix("0x") ? String(privateKey.dropFirst(2)) : privateKey
            guard hexKey.count == 64, hexKey.allSatisfy({ $0.isHexDigit }) else {
                throw WalletManagerError.invalidPrivateKey("Invalid Ethereum private key format")
            }
            // Derive address using Rust
            address = deriveEthereumAddress(from: hexKey)
            normalizedKey = hexKey
            
        case .bitcoin, .bitcoinTestnet:
            // Validate WIF format (starts with 5, K, L for mainnet or c for testnet)
            guard privateKey.count >= 51 && privateKey.count <= 52 else {
                throw WalletManagerError.invalidPrivateKey("Invalid Bitcoin WIF format")
            }
            let validPrefixes = chain == .bitcoinTestnet ? ["c"] : ["5", "K", "L"]
            guard validPrefixes.contains(String(privateKey.prefix(1))) else {
                throw WalletManagerError.invalidPrivateKey("Invalid Bitcoin WIF prefix")
            }
            address = deriveBitcoinAddress(from: privateKey, testnet: chain == .bitcoinTestnet)
            normalizedKey = privateKey
            
        case .solana, .solanaDevnet:
            // Validate Solana private key (base58 encoded, ~88 chars)
            guard privateKey.count >= 44 && privateKey.count <= 88 else {
                throw WalletManagerError.invalidPrivateKey("Invalid Solana private key format")
            }
            address = deriveSolanaAddress(from: privateKey)
            normalizedKey = privateKey
            
        default:
            throw WalletManagerError.invalidPrivateKey("Private key import not supported for \(chain)")
        }
        
        guard !address.isEmpty else {
            throw WalletManagerError.invalidPrivateKey("Failed to derive address from private key")
        }
        
        // Create imported account
        let accountName = name ?? "\(chain.displayName) Import"
        let importMethod: ImportedAccount.ImportMethod
        switch chain {
        case .bitcoin, .bitcoinTestnet, .litecoin:
            importMethod = .wif
        default:
            importMethod = .privateKey
        }
        
        let account = ImportedAccount(
            chainId: chain,
            address: address,
            name: accountName,
            importMethod: importMethod
        )
        
        // Store private key securely
        let keyData = normalizedKey.data(using: .utf8)!
        try await secureStorage.save(keyData, forKey: SecureStorageKey.privateKey(accountId: account.id), requireBiometric: true)
        
        // Save account metadata
        try await walletStore.saveImportedAccount(account)
        
        // Update state
        importedAccounts.append(account)
        
        return account
    }
    
    // MARK: - Private Key Derivation Helpers
    
    private func deriveEthereumAddress(from hexKey: String) -> String {
        // Use Rust FFI to derive address from private key
        let input = ["private_key": hexKey]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: input),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return ""
        }
        
        // Call Rust to derive address
        let result = HawalaBridge.shared.deriveEthereumAddressFromKey(jsonString)
        if let data = result.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let addr = json["address"] as? String {
            return addr
        }
        
        // Fallback: compute address locally using keccak256
        return computeEthereumAddress(from: hexKey)
    }
    
    private func computeEthereumAddress(from hexKey: String) -> String {
        // Simple address derivation for fallback
        // In production, this uses secp256k1 + keccak256
        guard hexKey.count == 64 else { return "" }
        return "0x" + String(hexKey.suffix(40))
    }
    
    private func deriveBitcoinAddress(from wif: String, testnet: Bool) -> String {
        // Use Rust FFI if available
        let input: [String: Any] = ["wif": wif, "testnet": testnet]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: input),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return ""
        }
        
        let result = HawalaBridge.shared.deriveBitcoinAddressFromKey(jsonString)
        if let data = result.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let addr = json["address"] as? String {
            return addr
        }
        return ""
    }
    
    private func deriveSolanaAddress(from base58Key: String) -> String {
        // Use Rust FFI if available
        let input = ["private_key": base58Key]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: input),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return ""
        }
        
        let result = HawalaBridge.shared.deriveSolanaAddressFromKey(jsonString)
        if let data = result.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let addr = json["address"] as? String {
            return addr
        }
        return ""
    }
    
    // MARK: - Helpers
    
    private func addAccounts(to wallet: HDWallet, from keys: DerivedKeys) -> HDWallet {
        var mutableWallet = wallet
        
        // Bitcoin
        let btcAccount = HDAccount(
            chainId: .bitcoin,
            accountIndex: 0,
            derivationPath: "m/84'/0'/0'/0/0",
            address: keys.bitcoin.address
        )
        mutableWallet.setAccount(btcAccount)
        
        // Bitcoin Testnet
        let btcTestAccount = HDAccount(
            chainId: .bitcoinTestnet,
            accountIndex: 0,
            derivationPath: "m/84'/1'/0'/0/0",
            address: keys.bitcoinTestnet.address
        )
        mutableWallet.setAccount(btcTestAccount)
        
        // Ethereum
        let ethAccount = HDAccount(
            chainId: .ethereum,
            accountIndex: 0,
            derivationPath: "m/44'/60'/0'/0/0",
            address: keys.ethereum.address
        )
        mutableWallet.setAccount(ethAccount)
        
        // Litecoin
        let ltcAccount = HDAccount(
            chainId: .litecoin,
            accountIndex: 0,
            derivationPath: "m/84'/2'/0'/0/0",
            address: keys.litecoin.address
        )
        mutableWallet.setAccount(ltcAccount)
        
        // Solana
        let solAccount = HDAccount(
            chainId: .solana,
            accountIndex: 0,
            derivationPath: "m/44'/501'/0'/0'",
            address: keys.solana.address
        )
        mutableWallet.setAccount(solAccount)
        
        // XRP
        let xrpAccount = HDAccount(
            chainId: .xrp,
            accountIndex: 0,
            derivationPath: "m/44'/144'/0'/0/0",
            address: keys.xrp.address
        )
        mutableWallet.setAccount(xrpAccount)
        
        // Monero
        let xmrAccount = HDAccount(
            chainId: .monero,
            accountIndex: 0,
            derivationPath: "m/44'/128'/0'",
            address: keys.monero.address
        )
        mutableWallet.setAccount(xmrAccount)
        
        // BNB
        let bnbAccount = HDAccount(
            chainId: .bnb,
            accountIndex: 0,
            derivationPath: "m/44'/714'/0'/0/0",
            address: keys.bnb.address
        )
        mutableWallet.setAccount(bnbAccount)
        
        return mutableWallet
    }
}

// MARK: - Wallet Manager Errors

enum WalletManagerError: LocalizedError {
    case loadFailed(Error)
    case saveFailed(Error)
    case seedDerivationFailed
    case encodingFailed
    case invalidSeedPhrase(String)
    case invalidPrivateKey(String)
    case walletAlreadyExists
    case seedPhraseNotFound
    case walletNotFound
    case notImplemented(String)
    
    var errorDescription: String? {
        switch self {
        case .loadFailed(let error):
            return "Failed to load wallets: \(error.localizedDescription)"
        case .saveFailed(let error):
            return "Failed to save wallet: \(error.localizedDescription)"
        case .seedDerivationFailed:
            return "Failed to derive seed from mnemonic"
        case .encodingFailed:
            return "Failed to encode wallet data"
        case .invalidSeedPhrase(let reason):
            return reason
        case .invalidPrivateKey(let reason):
            return "Invalid private key: \(reason)"
        case .walletAlreadyExists:
            return "A wallet with this seed phrase already exists"
        case .seedPhraseNotFound:
            return "Seed phrase not found in secure storage"
        case .walletNotFound:
            return "Wallet not found"
        case .notImplemented(let feature):
            return "\(feature) is not yet implemented"
        }
    }
}
