import Foundation
import CryptoKit
import CommonCrypto

// MARK: - Hawala File Encoder

/// Encodes wallet data into an encrypted .hawala backup file
public final class HawalaFileEncoder: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = HawalaFileEncoder()
    
    private init() {}
    
    // MARK: - Public API
    
    /// Create an encrypted .hawala backup file
    /// - Parameters:
    ///   - payload: The backup data to encrypt
    ///   - password: User-provided password for encryption
    /// - Returns: Encrypted file data ready to be saved
    public func encode(payload: HawalaBackupPayload, password: String) throws -> Data {
        // 1. Encode payload to JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys] // Deterministic output
        
        let payloadData: Data
        do {
            payloadData = try encoder.encode(payload)
        } catch {
            throw HawalaFileError.payloadEncodingFailed(error)
        }
        
        // 2. Generate random salt and nonce
        var salt = Data(count: HawalaFileConstants.saltLength)
        var nonce = Data(count: HawalaFileConstants.nonceLength)
        
        let saltResult = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, HawalaFileConstants.saltLength, $0.baseAddress!) }
        let nonceResult = nonce.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, HawalaFileConstants.nonceLength, $0.baseAddress!) }
        
        guard saltResult == errSecSuccess, nonceResult == errSecSuccess else {
            throw HawalaFileError.encryptionFailed
        }
        
        // 3. Derive encryption key from password
        let key = try deriveKey(from: password, salt: salt)
        
        // 4. Encrypt with AES-256-GCM
        let sealedBox: AES.GCM.SealedBox
        do {
            let aesNonce = try AES.GCM.Nonce(data: nonce)
            sealedBox = try AES.GCM.seal(payloadData, using: key, nonce: aesNonce)
        } catch {
            throw HawalaFileError.encryptionFailed
        }
        
        // 5. Build file structure
        var fileData = Data()
        
        // Magic bytes
        fileData.append(contentsOf: HawalaFileConstants.magicBytes)
        
        // Version (big-endian)
        var version = HawalaFileConstants.currentVersion.bigEndian
        fileData.append(Data(bytes: &version, count: 2))
        
        // Flags (big-endian)
        var flags = determineFlags(from: payload).rawValue.bigEndian
        fileData.append(Data(bytes: &flags, count: 2))
        
        // Salt
        fileData.append(salt)
        
        // Nonce
        fileData.append(nonce)
        
        // Encrypted payload (ciphertext + tag combined)
        fileData.append(sealedBox.ciphertext)
        fileData.append(sealedBox.tag)
        
        return fileData
    }
    
    /// Create a backup from wallet manager data
    /// - Parameters:
    ///   - walletManager: The wallet manager containing wallets to backup
    ///   - password: Encryption password
    ///   - includeSettings: Whether to include app settings
    /// - Returns: Encrypted backup data
    @MainActor
    func createBackup(
        from walletManager: WalletManager,
        password: String,
        includeSettings: Bool = true
    ) async throws -> Data {
        var hdWalletBackups: [HDWalletBackup] = []
        
        // Backup each HD wallet
        for wallet in walletManager.hdWallets {
            // Retrieve seed phrase (requires biometric)
            let seedPhrase = try await walletManager.getSeedPhrase(for: wallet.id)
            
            // Convert accounts - accounts is an array, not a dictionary
            let accountBackups = wallet.accounts.map { account in
                HDAccountBackup(
                    chainId: account.chainId.rawValue,
                    accountIndex: Int(account.accountIndex),
                    derivationPath: account.derivationPath,
                    address: account.address
                )
            }
            
            // Use wallet ID as a proxy for fingerprint since fingerprint isn't stored
            let fingerprintProxy = wallet.id.uuidString
            
            let backup = HDWalletBackup(
                id: wallet.id,
                name: wallet.name,
                seedFingerprint: fingerprintProxy,
                seedPhrase: seedPhrase,
                passphrase: wallet.hasPassphrase ? nil : nil, // Note: passphrase not stored for security
                derivationScheme: wallet.derivationScheme.rawValue,
                accounts: accountBackups,
                createdAt: wallet.createdAt
            )
            hdWalletBackups.append(backup)
        }
        
        // Note: Imported accounts would need private key retrieval
        // For now, we only backup HD wallets
        let importedAccountBackups: [ImportedAccountBackup] = []
        
        // Settings backup
        let settingsBackup: SettingsBackup?
        if includeSettings {
            settingsBackup = SettingsBackup(
                currency: UserDefaults.standard.string(forKey: "selectedCurrency"),
                theme: UserDefaults.standard.string(forKey: "appTheme"),
                biometricEnabled: UserDefaults.standard.bool(forKey: "biometricEnabled"),
                autoLockMinutes: UserDefaults.standard.integer(forKey: "autoLockMinutes"),
                hideBalances: UserDefaults.standard.bool(forKey: "hideBalances")
            )
        } else {
            settingsBackup = nil
        }
        
        let payload = HawalaBackupPayload(
            hdWallets: hdWalletBackups,
            importedAccounts: importedAccountBackups,
            settings: settingsBackup
        )
        
        return try encode(payload: payload, password: password)
    }
    
    /// Generate a suggested filename for the backup
    public func suggestedFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "hawala-backup-\(formatter.string(from: Date())).\(HawalaFileConstants.fileExtension)"
    }
    
    // MARK: - Private Helpers
    
    private func deriveKey(from password: String, salt: Data) throws -> SymmetricKey {
        guard let passwordData = password.data(using: .utf8) else {
            throw HawalaFileError.keyDerivationFailed
        }
        
        // Use PBKDF2-HMAC-SHA256
        var derivedKey = Data(count: 32) // 256 bits
        
        let result = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(HawalaFileConstants.pbkdf2Iterations),
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }
            }
        }
        
        guard result == kCCSuccess else {
            throw HawalaFileError.keyDerivationFailed
        }
        
        return SymmetricKey(data: derivedKey)
    }
    
    private func determineFlags(from payload: HawalaBackupPayload) -> HawalaFileFlags {
        var flags: HawalaFileFlags = []
        
        if !payload.hdWallets.isEmpty {
            flags.insert(.includesHDWallets)
        }
        if !payload.importedAccounts.isEmpty {
            flags.insert(.includesImportedAccounts)
        }
        if payload.settings != nil {
            flags.insert(.includesSettings)
        }
        
        return flags
    }
}

// MARK: - Password Strength Validation

public extension HawalaFileEncoder {
    
    /// Password strength level
    enum PasswordStrength: Int, Comparable {
        case weak = 0
        case fair = 1
        case good = 2
        case strong = 3
        
        public static func < (lhs: PasswordStrength, rhs: PasswordStrength) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
        
        public var description: String {
            switch self {
            case .weak: return "Weak"
            case .fair: return "Fair"
            case .good: return "Good"
            case .strong: return "Strong"
            }
        }
        
        public var color: String {
            switch self {
            case .weak: return "red"
            case .fair: return "orange"
            case .good: return "yellow"
            case .strong: return "green"
            }
        }
    }
    
    /// Evaluate password strength
    func evaluatePasswordStrength(_ password: String) -> PasswordStrength {
        var score = 0
        
        // Length
        if password.count >= 8 { score += 1 }
        if password.count >= 12 { score += 1 }
        if password.count >= 16 { score += 1 }
        
        // Complexity
        let hasLowercase = password.rangeOfCharacter(from: .lowercaseLetters) != nil
        let hasUppercase = password.rangeOfCharacter(from: .uppercaseLetters) != nil
        let hasDigits = password.rangeOfCharacter(from: .decimalDigits) != nil
        let hasSpecial = password.rangeOfCharacter(from: CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;':\",./<>?")) != nil
        
        if hasLowercase { score += 1 }
        if hasUppercase { score += 1 }
        if hasDigits { score += 1 }
        if hasSpecial { score += 1 }
        
        // Map score to strength
        switch score {
        case 0...2: return .weak
        case 3...4: return .fair
        case 5...6: return .good
        default: return .strong
        }
    }
    
    /// Minimum recommended password strength for backups
    var minimumRecommendedStrength: PasswordStrength { .good }
}
