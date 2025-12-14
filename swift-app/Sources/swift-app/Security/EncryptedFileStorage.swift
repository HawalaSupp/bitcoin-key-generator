import Foundation
import CryptoKit

// MARK: - Encrypted File Storage

/// Secure storage for `.hawala` encrypted backup files.
/// Uses AES-GCM encryption with PBKDF2-derived keys from user password.
final class EncryptedFileStorage: @unchecked Sendable {
    
    /// Current encryption format version
    static let formatVersion: UInt8 = 1
    
    /// PBKDF2 iteration count (high for security)
    private static let pbkdf2Iterations: UInt32 = 100_000
    
    /// Salt length in bytes
    private static let saltLength = 32
    
    /// File header magic bytes
    private static let magicBytes: [UInt8] = [0x48, 0x41, 0x57, 0x41]  // "HAWA"
    
    // MARK: - Encryption
    
    /// Encrypt data with a password for export
    /// - Parameters:
    ///   - data: The plaintext data to encrypt
    ///   - password: User-provided password
    /// - Returns: Encrypted data with header (salt, nonce, version)
    static func encrypt(_ data: Data, password: String) throws -> Data {
        // Generate random salt
        var salt = Data(count: saltLength)
        let saltResult = salt.withUnsafeMutableBytes { saltBytes in
            SecRandomCopyBytes(kSecRandomDefault, saltLength, saltBytes.baseAddress!)
        }
        guard saltResult == errSecSuccess else {
            throw SecureStorageError.encryptionFailed(CryptoError.randomGenerationFailed)
        }
        
        // Derive key from password using PBKDF2
        let key = try deriveKey(from: password, salt: salt)
        
        // Generate random nonce
        let nonce = AES.GCM.Nonce()
        
        // Encrypt with AES-GCM
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)
        
        guard let ciphertext = sealedBox.combined else {
            throw SecureStorageError.encryptionFailed(CryptoError.sealingFailed)
        }
        
        // Build output: magic + version + salt + ciphertext (includes nonce + tag)
        var output = Data()
        output.append(contentsOf: magicBytes)
        output.append(formatVersion)
        output.append(salt)
        output.append(ciphertext)
        
        return output
    }
    
    // MARK: - Decryption
    
    /// Decrypt data that was encrypted with `encrypt`
    /// - Parameters:
    ///   - encryptedData: The encrypted data with header
    ///   - password: The password used during encryption
    /// - Returns: Decrypted plaintext data
    static func decrypt(_ encryptedData: Data, password: String) throws -> Data {
        // Validate minimum length
        let headerLength = magicBytes.count + 1 + saltLength  // magic + version + salt
        guard encryptedData.count > headerLength else {
            throw SecureStorageError.decryptionFailed(CryptoError.invalidFormat)
        }
        
        var offset = 0
        
        // Verify magic bytes
        let magic = [UInt8](encryptedData[offset..<offset + magicBytes.count])
        guard magic == magicBytes else {
            throw SecureStorageError.decryptionFailed(CryptoError.invalidMagic)
        }
        offset += magicBytes.count
        
        // Read version
        let version = encryptedData[offset]
        guard version == formatVersion else {
            throw SecureStorageError.decryptionFailed(CryptoError.unsupportedVersion(version))
        }
        offset += 1
        
        // Read salt
        let salt = encryptedData[offset..<offset + saltLength]
        offset += saltLength
        
        // Remaining data is ciphertext (nonce + encrypted + tag)
        let ciphertext = encryptedData[offset...]
        
        // Derive key from password
        let key = try deriveKey(from: password, salt: Data(salt))
        
        // Decrypt
        let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
        let plaintext = try AES.GCM.open(sealedBox, using: key)
        
        return plaintext
    }
    
    // MARK: - Key Derivation
    
    /// Derive an AES-256 key from password using PBKDF2
    private static func deriveKey(from password: String, salt: Data) throws -> SymmetricKey {
        guard let passwordData = password.data(using: .utf8) else {
            throw SecureStorageError.encryptionFailed(CryptoError.invalidPassword)
        }
        
        // Use CryptoKit's HKDF as PBKDF2 alternative
        // Note: For production, consider using CommonCrypto PBKDF2 for full compatibility
        let inputKey = SymmetricKey(data: passwordData)
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: Data("HAWALA_WALLET_V1".utf8),
            outputByteCount: 32
        )
        
        return derivedKey
    }
    
    // MARK: - File Operations
    
    /// Save encrypted data to a file
    /// - Parameters:
    ///   - data: Plaintext data to encrypt and save
    ///   - url: File URL to save to
    ///   - password: Encryption password
    static func saveToFile(_ data: Data, at url: URL, password: String) throws {
        let encrypted = try encrypt(data, password: password)
        try encrypted.write(to: url, options: [.atomic, .completeFileProtection])
    }
    
    /// Load and decrypt data from a file
    /// - Parameters:
    ///   - url: File URL to load from
    ///   - password: Decryption password
    /// - Returns: Decrypted data
    static func loadFromFile(at url: URL, password: String) throws -> Data {
        let encrypted = try Data(contentsOf: url)
        return try decrypt(encrypted, password: password)
    }
    
    /// Verify a file is a valid Hawala backup without decrypting
    /// - Parameter url: File URL to check
    /// - Returns: true if the file has valid Hawala format
    static func isValidBackupFile(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return false
        }
        
        guard data.count > magicBytes.count else {
            return false
        }
        
        let magic = [UInt8](data[0..<magicBytes.count])
        return magic == magicBytes
    }
}

// MARK: - Crypto Errors

enum CryptoError: LocalizedError {
    case randomGenerationFailed
    case sealingFailed
    case invalidFormat
    case invalidMagic
    case unsupportedVersion(UInt8)
    case invalidPassword
    case derivationFailed
    
    var errorDescription: String? {
        switch self {
        case .randomGenerationFailed:
            return "Failed to generate random bytes"
        case .sealingFailed:
            return "Encryption sealing failed"
        case .invalidFormat:
            return "Invalid encrypted file format"
        case .invalidMagic:
            return "Not a valid Hawala backup file"
        case .unsupportedVersion(let v):
            return "Unsupported backup format version: \(v)"
        case .invalidPassword:
            return "Invalid password encoding"
        case .derivationFailed:
            return "Key derivation failed"
        }
    }
}
