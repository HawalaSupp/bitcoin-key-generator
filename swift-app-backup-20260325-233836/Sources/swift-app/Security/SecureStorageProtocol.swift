import Foundation

// MARK: - Secure Storage Protocol

/// Contract for secure storage of sensitive data (seeds, private keys).
/// All implementations must encrypt data at rest and support access control.
protocol SecureStorageProtocol: Sendable {
    /// Save encrypted data with a key identifier
    /// - Parameters:
    ///   - data: The sensitive data to store (will be encrypted)
    ///   - key: Unique identifier for this data
    ///   - requireBiometric: Whether biometric/passcode is required to access
    func save(_ data: Data, forKey key: String, requireBiometric: Bool) async throws
    
    /// Load and decrypt data for a key
    /// - Parameter key: The identifier used when saving
    /// - Returns: Decrypted data, or nil if not found
    func load(forKey key: String) async throws -> Data?
    
    /// Delete data for a key
    /// - Parameter key: The identifier to delete
    func delete(forKey key: String) async throws
    
    /// Check if data exists for a key
    /// - Parameter key: The identifier to check
    func exists(forKey key: String) async -> Bool
    
    /// Delete all stored data (for wallet reset)
    func deleteAll() async throws
}

// MARK: - Secure Storage Keys

/// Standardized keys for different types of secure data
enum SecureStorageKey {
    /// HD wallet seed phrase (uses wallet ID as suffix)
    static func seedPhrase(walletId: UUID) -> String {
        "com.hawala.seed.\(walletId.uuidString)"
    }
    
    /// BIP39 passphrase if used (uses wallet ID as suffix)
    static func passphrase(walletId: UUID) -> String {
        "com.hawala.passphrase.\(walletId.uuidString)"
    }
    
    /// Imported account private key (uses account ID as suffix)
    static func privateKey(accountId: UUID) -> String {
        "com.hawala.privatekey.\(accountId.uuidString)"
    }
    
    /// Master encryption key for file exports
    static let exportKey = "com.hawala.export.masterkey"
}

// MARK: - Secure Storage Errors

enum SecureStorageError: LocalizedError {
    case saveFailed(underlying: Error?)
    case loadFailed(underlying: Error?)
    case deleteFailed(underlying: Error?)
    case biometricFailed
    case accessDenied
    case dataCorrupted
    case keychainError(OSStatus)
    case encryptionFailed(Error)
    case decryptionFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .saveFailed(let error):
            if let error = error {
                return "Failed to save secure data: \(error.localizedDescription)"
            }
            return "Failed to save secure data"
        case .loadFailed(let error):
            if let error = error {
                return "Failed to load secure data: \(error.localizedDescription)"
            }
            return "Failed to load secure data"
        case .deleteFailed(let error):
            if let error = error {
                return "Failed to delete secure data: \(error.localizedDescription)"
            }
            return "Failed to delete secure data"
        case .biometricFailed:
            return "Biometric authentication failed"
        case .accessDenied:
            return "Access denied - authentication required"
        case .dataCorrupted:
            return "Stored data is corrupted"
        case .keychainError(let status):
            return "Keychain error (status: \(status))"
        case .encryptionFailed(let error):
            return "Encryption failed: \(error.localizedDescription)"
        case .decryptionFailed(let error):
            return "Decryption failed: \(error.localizedDescription)"
        }
    }
}
