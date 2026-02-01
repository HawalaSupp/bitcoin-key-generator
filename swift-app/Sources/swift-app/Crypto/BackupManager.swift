import Foundation

// MARK: - Backup Manager

/// Manages wallet backup export and import operations.
/// Handles `.hawala` encrypted backup files.
final class BackupManager: @unchecked Sendable {
    
    /// Shared instance
    static let shared = BackupManager()
    
    private init() {}
    
    // MARK: - Backup Format
    
    /// Structure for backup file contents
    struct BackupContents: Codable {
        let version: Int
        let createdAt: Date
        let appVersion: String
        let hdWallets: [HDWalletBackup]
        let importedAccounts: [ImportedAccountBackup]
        
        static let currentVersion = 1
    }
    
    struct HDWalletBackup: Codable {
        let id: UUID
        let name: String
        let createdAt: Date
        let derivationScheme: DerivationScheme
        let seedPhrase: String  // Encrypted at the file level
        let passphrase: String? // Optional BIP39 passphrase
        let accounts: [HDAccount]
    }
    
    struct ImportedAccountBackup: Codable {
        let id: UUID
        let name: String
        let chainId: ChainIdentifier
        let address: String
        let privateKey: String  // Encrypted at the file level
        let importMethod: ImportedAccount.ImportMethod
        let createdAt: Date
    }
    
    // MARK: - Export
    
    /// Export all wallets to an encrypted backup file
    /// - Parameters:
    ///   - password: User-provided encryption password
    ///   - walletManager: WalletManager to export from
    /// - Returns: Encrypted backup data
    @MainActor
    func exportBackup(
        password: String,
        walletManager: WalletManager
    ) async throws -> Data {
        var hdWalletBackups: [HDWalletBackup] = []
        
        // Export each HD wallet with its seed phrase
        for wallet in walletManager.hdWallets {
            let seedPhrase = try await walletManager.getSeedPhrase(for: wallet.id)
            
            // Get passphrase if exists
            var passphrase: String? = nil
            if wallet.hasPassphrase {
                let passphraseKey = SecureStorageKey.passphrase(walletId: wallet.id)
                if let data = try? await KeychainSecureStorage.shared.load(forKey: passphraseKey),
                   let pp = String(data: data, encoding: .utf8) {
                    passphrase = pp
                }
            }
            
            let backup = HDWalletBackup(
                id: wallet.id,
                name: wallet.name,
                createdAt: wallet.createdAt,
                derivationScheme: wallet.derivationScheme,
                seedPhrase: seedPhrase,
                passphrase: passphrase,
                accounts: wallet.accounts
            )
            hdWalletBackups.append(backup)
        }
        
        // Export imported accounts (placeholder - needs private key retrieval)
        let importedAccountBackups: [ImportedAccountBackup] = []
        
        // Create backup contents
        let contents = BackupContents(
            version: BackupContents.currentVersion,
            createdAt: Date(),
            appVersion: AppVersion.version,
            hdWallets: hdWalletBackups,
            importedAccounts: importedAccountBackups
        )
        
        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(contents)
        
        // Encrypt with password
        let encryptedData = try EncryptedFileStorage.encrypt(jsonData, password: password)
        
        return encryptedData
    }
    
    /// Export backup to a file
    /// - Parameters:
    ///   - url: Destination file URL
    ///   - password: Encryption password
    ///   - walletManager: WalletManager to export from
    @MainActor
    func exportToFile(
        at url: URL,
        password: String,
        walletManager: WalletManager
    ) async throws {
        let data = try await exportBackup(password: password, walletManager: walletManager)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }
    
    // MARK: - Import
    
    /// Import wallets from an encrypted backup file
    /// - Parameters:
    ///   - data: Encrypted backup data
    ///   - password: Decryption password
    /// - Returns: Parsed backup contents
    func parseBackup(data: Data, password: String) throws -> BackupContents {
        // Decrypt
        let jsonData = try EncryptedFileStorage.decrypt(data, password: password)
        
        // Decode
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let contents = try decoder.decode(BackupContents.self, from: jsonData)
        
        // Version check
        if contents.version > BackupContents.currentVersion {
            throw BackupError.newerVersion(contents.version)
        }
        
        return contents
    }
    
    /// Import wallets from backup contents
    /// - Parameters:
    ///   - contents: Parsed backup contents
    ///   - walletManager: WalletManager to import into
    /// - Returns: Number of wallets imported
    @MainActor
    func importBackup(
        contents: BackupContents,
        walletManager: WalletManager
    ) async throws -> ImportResult {
        var imported = 0
        var skipped = 0
        var errors: [String] = []
        
        for hdBackup in contents.hdWallets {
            do {
                // Check if wallet already exists
                if walletManager.hdWallets.contains(where: { $0.id == hdBackup.id }) {
                    skipped += 1
                    continue
                }
                
                // Restore the wallet
                _ = try await walletManager.restoreWallet(
                    from: hdBackup.seedPhrase,
                    name: hdBackup.name,
                    passphrase: hdBackup.passphrase ?? ""
                )
                imported += 1
            } catch {
                errors.append("Failed to import '\(hdBackup.name)': \(error.localizedDescription)")
            }
        }
        
        // Import imported accounts
        for accountBackup in contents.importedAccounts {
            do {
                // Check if account already exists
                if walletManager.importedAccounts.contains(where: { $0.id == accountBackup.id }) {
                    skipped += 1
                    continue
                }
                
                // Create the account from backup
                let account = ImportedAccount(
                    id: accountBackup.id,
                    chainId: accountBackup.chainId,
                    address: accountBackup.address,
                    name: accountBackup.name,
                    createdAt: accountBackup.createdAt,
                    importMethod: accountBackup.importMethod
                )
                
                // Restore account with private key
                try await walletManager.restoreImportedAccount(account, privateKey: accountBackup.privateKey)
                imported += 1
            } catch {
                errors.append("Failed to import account '\(accountBackup.name)': \(error.localizedDescription)")
            }
        }
        
        return ImportResult(
            imported: imported,
            skipped: skipped,
            errors: errors
        )
    }
    
    /// Import from a file URL
    @MainActor
    func importFromFile(
        at url: URL,
        password: String,
        walletManager: WalletManager
    ) async throws -> ImportResult {
        let data = try Data(contentsOf: url)
        let contents = try parseBackup(data: data, password: password)
        return try await importBackup(contents: contents, walletManager: walletManager)
    }
    
    // MARK: - Validation
    
    /// Validate a backup file without decrypting
    static func isValidBackupFile(at url: URL) -> Bool {
        EncryptedFileStorage.isValidBackupFile(at: url)
    }
    
    /// Validate password by attempting to decrypt
    func validatePassword(for data: Data, password: String) -> Bool {
        do {
            _ = try parseBackup(data: data, password: password)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Import Result

struct ImportResult: Sendable {
    let imported: Int
    let skipped: Int
    let errors: [String]
    
    var hasErrors: Bool { !errors.isEmpty }
    var total: Int { imported + skipped }
    
    var summary: String {
        var parts: [String] = []
        if imported > 0 {
            parts.append("\(imported) imported")
        }
        if skipped > 0 {
            parts.append("\(skipped) skipped (already exist)")
        }
        if hasErrors {
            parts.append("\(errors.count) failed")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Backup Errors

enum BackupError: LocalizedError {
    case encryptionFailed(Error)
    case decryptionFailed(Error)
    case invalidFormat
    case newerVersion(Int)
    case emptyBackup
    case readFailed(Error)
    case writeFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .encryptionFailed(let error):
            return "Failed to encrypt backup: \(error.localizedDescription)"
        case .decryptionFailed(let error):
            return "Failed to decrypt backup. Check your password."
        case .invalidFormat:
            return "Invalid backup file format"
        case .newerVersion(let version):
            return "This backup requires a newer app version (v\(version))"
        case .emptyBackup:
            return "No wallets to backup"
        case .readFailed(let error):
            return "Failed to read backup file: \(error.localizedDescription)"
        case .writeFailed(let error):
            return "Failed to write backup file: \(error.localizedDescription)"
        }
    }
}
