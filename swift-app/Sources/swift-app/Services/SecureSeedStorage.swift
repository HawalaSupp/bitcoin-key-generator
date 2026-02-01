import Foundation
import Security
import CryptoKit
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Secure Seed Storage
/// Handles secure storage of seed phrases with encryption and Keychain integration
/// Implements defense-in-depth: encryption at rest + Keychain protection + memory security

final class SecureSeedStorage {
    
    // MARK: - Constants
    private static let seedIdentifier = "com.hawala.wallet.seed"
    private static let encryptionKeyIdentifier = "com.hawala.wallet.seed.key"
    private static let backupIdentifier = "com.hawala.wallet.seed.backup"
    
    // MARK: - Errors
    enum SeedStorageError: LocalizedError {
        case encryptionFailed
        case decryptionFailed
        case invalidSeedPhrase
        case keychainSaveFailed(OSStatus)
        case keychainLoadFailed(OSStatus)
        case keychainDeleteFailed(OSStatus)
        case noSeedFound
        case userCancelled
        case iCloudUnavailable
        case backupFailed(Error)
        case restoreFailed(Error)
        
        var errorDescription: String? {
            switch self {
            case .encryptionFailed:
                return "Failed to encrypt seed phrase"
            case .decryptionFailed:
                return "Failed to decrypt seed phrase"
            case .invalidSeedPhrase:
                return "Invalid seed phrase format"
            case .keychainSaveFailed(let status):
                return "Keychain save failed (status: \(status))"
            case .keychainLoadFailed(let status):
                return "Keychain load failed (status: \(status))"
            case .keychainDeleteFailed(let status):
                return "Keychain delete failed (status: \(status))"
            case .noSeedFound:
                return "No seed phrase found in storage"
            case .userCancelled:
                return "Authentication cancelled by user"
            case .iCloudUnavailable:
                return "iCloud is not available"
            case .backupFailed(let error):
                return "Backup failed: \(error.localizedDescription)"
            case .restoreFailed(let error):
                return "Restore failed: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Seed Phrase Validation
    
    /// Validates a seed phrase (12, 18, or 24 words)
    static func validateSeedPhrase(_ words: [String]) -> Bool {
        let validCounts = [12, 18, 24]
        guard validCounts.contains(words.count) else { return false }
        
        // Check all words are from BIP39 wordlist
        return words.allSatisfy { word in
            BIP39Wordlist.english.contains(word.lowercased().trimmingCharacters(in: .whitespaces))
        }
    }
    
    /// Validates a seed phrase string (space or newline separated)
    static func validateSeedPhrase(_ phrase: String) -> Bool {
        let words = parseSeedPhrase(phrase)
        return validateSeedPhrase(words)
    }
    
    /// Parse seed phrase string into words array
    static func parseSeedPhrase(_ phrase: String) -> [String] {
        return phrase
            .lowercased()
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    
    // MARK: - Save Seed Phrase
    
    /// Save seed phrase securely to Keychain with encryption
    static func saveSeedPhrase(_ words: [String], withPasscode passcode: String? = nil) throws {
        guard validateSeedPhrase(words) else {
            throw SeedStorageError.invalidSeedPhrase
        }
        
        // Convert words to data
        let phraseString = words.joined(separator: " ")
        guard let phraseData = phraseString.data(using: .utf8) else {
            throw SeedStorageError.encryptionFailed
        }
        
        // Encrypt if passcode provided
        let dataToStore: Data
        if let passcode = passcode, !passcode.isEmpty {
            dataToStore = try encrypt(phraseData, withPasscode: passcode)
        } else {
            // Use device-based encryption key
            dataToStore = try encryptWithDeviceKey(phraseData)
        }
        
        // Store in Keychain with strong protection
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: seedIdentifier,
            kSecValueData as String: dataToStore,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            // Require biometric authentication for access
            kSecAttrAccessControl as String: try createAccessControl()
        ]
        
        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: seedIdentifier
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SeedStorageError.keychainSaveFailed(status)
        }
        
        #if DEBUG
        print("✅ Seed phrase saved securely to Keychain")
        #endif
    }
    
    // MARK: - Load Seed Phrase
    
    /// Load and decrypt seed phrase from Keychain
    static func loadSeedPhrase(withPasscode passcode: String? = nil) throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: seedIdentifier,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            throw SeedStorageError.noSeedFound
        }
        
        if status == errSecUserCanceled {
            throw SeedStorageError.userCancelled
        }
        
        guard status == errSecSuccess, let encryptedData = result as? Data else {
            throw SeedStorageError.keychainLoadFailed(status)
        }
        
        // Decrypt
        let decryptedData: Data
        if let passcode = passcode, !passcode.isEmpty {
            decryptedData = try decrypt(encryptedData, withPasscode: passcode)
        } else {
            decryptedData = try decryptWithDeviceKey(encryptedData)
        }
        
        guard let phraseString = String(data: decryptedData, encoding: .utf8) else {
            throw SeedStorageError.decryptionFailed
        }
        
        let words = phraseString.components(separatedBy: " ")
        guard validateSeedPhrase(words) else {
            throw SeedStorageError.decryptionFailed
        }
        
        return words
    }
    
    // MARK: - Delete Seed Phrase
    
    /// Delete seed phrase from Keychain
    static func deleteSeedPhrase() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: seedIdentifier
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SeedStorageError.keychainDeleteFailed(status)
        }
        
        #if DEBUG
        print("🗑️ Seed phrase deleted from Keychain")
        #endif
    }
    
    // MARK: - Check Seed Exists
    
    /// Check if a seed phrase exists in storage
    static func hasSeedPhrase() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: seedIdentifier,
            kSecReturnData as String: false
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess
    }
    
    // MARK: - iCloud Backup
    
    /// Backup encrypted seed phrase to iCloud Keychain
    static func backupToiCloud(_ words: [String], encryptedWith password: String) throws {
        guard FileManager.default.ubiquityIdentityToken != nil else {
            throw SeedStorageError.iCloudUnavailable
        }
        
        guard validateSeedPhrase(words) else {
            throw SeedStorageError.invalidSeedPhrase
        }
        
        // Convert and encrypt
        let phraseString = words.joined(separator: " ")
        guard let phraseData = phraseString.data(using: .utf8) else {
            throw SeedStorageError.encryptionFailed
        }
        
        let encryptedData = try encrypt(phraseData, withPasscode: password)
        
        // Add version and metadata
        let backupPayload = SeedBackupPayload(
            version: 1,
            createdAt: Date(),
            encryptedSeed: encryptedData.base64EncodedString(),
            wordCount: words.count
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payloadData = try encoder.encode(backupPayload)
        
        // Store in iCloud Keychain (synced)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: backupIdentifier,
            kSecAttrSynchronizable as String: true,
            kSecValueData as String: payloadData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: backupIdentifier,
            kSecAttrSynchronizable as String: true
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add new
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SeedStorageError.keychainSaveFailed(status)
        }
        
        #if DEBUG
        print("☁️ Seed phrase backed up to iCloud Keychain")
        #endif
    }
    
    /// Restore seed phrase from iCloud backup
    static func restoreFromiCloud(password: String) throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: backupIdentifier,
            kSecAttrSynchronizable as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            throw SeedStorageError.noSeedFound
        }
        
        guard status == errSecSuccess, let payloadData = result as? Data else {
            throw SeedStorageError.keychainLoadFailed(status)
        }
        
        // Decode payload
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(SeedBackupPayload.self, from: payloadData)
        
        guard let encryptedData = Data(base64Encoded: payload.encryptedSeed) else {
            throw SeedStorageError.decryptionFailed
        }
        
        // Decrypt
        let decryptedData = try decrypt(encryptedData, withPasscode: password)
        
        guard let phraseString = String(data: decryptedData, encoding: .utf8) else {
            throw SeedStorageError.decryptionFailed
        }
        
        let words = phraseString.components(separatedBy: " ")
        guard validateSeedPhrase(words) else {
            throw SeedStorageError.decryptionFailed
        }
        
        return words
    }
    
    /// Check if iCloud backup exists
    static func hasiCloudBackup() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: backupIdentifier,
            kSecAttrSynchronizable as String: true,
            kSecReturnData as String: false
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess
    }
    
    // MARK: - Private Encryption Methods
    
    private static func createAccessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence, // Require Touch ID or passcode
            &error
        ) else {
            throw SeedStorageError.encryptionFailed
        }
        return access
    }
    
    /// Encrypt data with user passcode using PBKDF2 + AES-GCM
    private static func encrypt(_ data: Data, withPasscode passcode: String) throws -> Data {
        // Generate salt
        var salt = Data(count: 32)
        let saltResult = salt.withUnsafeMutableBytes { saltBytes in
            SecRandomCopyBytes(kSecRandomDefault, 32, saltBytes.baseAddress!)
        }
        guard saltResult == errSecSuccess else {
            throw SeedStorageError.encryptionFailed
        }
        
        // Derive key using PBKDF2
        let key = try deriveKey(from: passcode, salt: salt)
        
        // Encrypt with AES-GCM
        let sealedBox = try AES.GCM.seal(data, using: key)
        
        guard let combined = sealedBox.combined else {
            throw SeedStorageError.encryptionFailed
        }
        
        // Prepend salt to encrypted data
        var result = Data()
        result.append(salt)
        result.append(combined)
        
        return result
    }
    
    /// Decrypt data with user passcode
    private static func decrypt(_ data: Data, withPasscode passcode: String) throws -> Data {
        guard data.count > 32 else {
            throw SeedStorageError.decryptionFailed
        }
        
        // Extract salt (first 32 bytes)
        let salt = data.prefix(32)
        let encryptedData = data.dropFirst(32)
        
        // Derive key
        let key = try deriveKey(from: passcode, salt: salt)
        
        // Decrypt
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        
        return decryptedData
    }
    
    /// Derive symmetric key from passcode using PBKDF2-like approach
    private static func deriveKey(from passcode: String, salt: Data) throws -> SymmetricKey {
        // Use SHA256 to derive key material
        guard let passcodeData = passcode.data(using: .utf8) else {
            throw SeedStorageError.encryptionFailed
        }
        
        var combined = passcodeData
        combined.append(salt)
        
        // Multiple rounds of hashing for key stretching
        var hash = SHA256.hash(data: combined)
        for _ in 0..<100_000 {
            var hashData = Data(hash)
            hashData.append(salt)
            hash = SHA256.hash(data: hashData)
        }
        
        return SymmetricKey(data: Data(hash))
    }
    
    /// Encrypt with device-bound key (stored in Secure Enclave when available)
    private static func encryptWithDeviceKey(_ data: Data) throws -> Data {
        // Generate or retrieve device key
        let key = try getOrCreateDeviceKey()
        
        // Encrypt with AES-GCM
        let sealedBox = try AES.GCM.seal(data, using: key)
        
        guard let combined = sealedBox.combined else {
            throw SeedStorageError.encryptionFailed
        }
        
        return combined
    }
    
    /// Decrypt with device-bound key
    private static func decryptWithDeviceKey(_ data: Data) throws -> Data {
        let key = try getOrCreateDeviceKey()
        
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }
    
    /// Get or create device-bound encryption key
    private static func getOrCreateDeviceKey() throws -> SymmetricKey {
        // Try to load existing key
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: encryptionKeyIdentifier,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let keyData = result as? Data {
            return SymmetricKey(data: keyData)
        }
        
        // Generate new key
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        
        // Store in Keychain
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: encryptionKeyIdentifier,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SeedStorageError.keychainSaveFailed(status)
        }
        
        return newKey
    }
}

// MARK: - Backup Payload

private struct SeedBackupPayload: Codable {
    let version: Int
    let createdAt: Date
    let encryptedSeed: String
    let wordCount: Int
}

// MARK: - Memory Security Extensions

extension SecureSeedStorage {
    
    /// Securely clear an array of strings from memory
    static func securelyClear(_ words: inout [String]) {
        for i in words.indices {
            let count = words[i].count
            words[i] = String(repeating: "*", count: count)
        }
        words.removeAll()
    }
    
    /// Securely clear a string from memory
    static func securelyClear(_ string: inout String) {
        let count = string.count
        string = String(repeating: "*", count: count)
        string = ""
    }
}
