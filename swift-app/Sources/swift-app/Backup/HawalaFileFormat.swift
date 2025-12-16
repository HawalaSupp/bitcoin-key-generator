import Foundation
import CryptoKit

// MARK: - Hawala File Format v1.0
//
// Binary structure:
// ┌──────────────────────────────────────────────────────────┐
// │ Magic Number (8 bytes): "HAWALA\x00\x01"                 │
// │ Version (2 bytes): UInt16 big-endian                     │
// │ Flags (2 bytes): UInt16 big-endian                       │
// │ Salt (32 bytes): Random salt for key derivation          │
// │ Nonce (12 bytes): AES-GCM nonce                          │
// │ Encrypted Payload (variable): AES-256-GCM encrypted JSON │
// │ Auth Tag (16 bytes): GCM authentication tag              │
// └──────────────────────────────────────────────────────────┘
//
// Password → Argon2id → 256-bit key → AES-256-GCM
// (Falls back to PBKDF2 if Argon2 unavailable)

// MARK: - File Format Constants

public enum HawalaFileConstants {
    /// File extension for Hawala backup files
    public static let fileExtension = "hawala"
    
    /// MIME type for Hawala backup files
    public static let mimeType = "application/x-hawala-backup"
    
    /// Magic bytes identifying a Hawala backup file
    public static let magicBytes: [UInt8] = [
        0x48, 0x41, 0x57, 0x41, 0x4C, 0x41, // "HAWALA"
        0x00, 0x01                           // Null + version marker
    ]
    
    /// Current file format version
    public static let currentVersion: UInt16 = 1
    
    /// Minimum supported version for import
    public static let minimumVersion: UInt16 = 1
    
    /// Salt length in bytes
    public static let saltLength = 32
    
    /// Nonce length in bytes (AES-GCM standard)
    public static let nonceLength = 12
    
    /// Authentication tag length (AES-GCM standard)
    public static let tagLength = 16
    
    /// Header size (magic + version + flags + salt + nonce)
    public static let headerSize = magicBytes.count + 2 + 2 + saltLength + nonceLength
    
    /// PBKDF2 iterations for key derivation
    public static let pbkdf2Iterations = 600_000
}

// MARK: - File Flags

public struct HawalaFileFlags: OptionSet, Sendable {
    public let rawValue: UInt16
    
    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }
    
    /// Backup includes HD wallets
    public static let includesHDWallets = HawalaFileFlags(rawValue: 1 << 0)
    
    /// Backup includes imported accounts
    public static let includesImportedAccounts = HawalaFileFlags(rawValue: 1 << 1)
    
    /// Backup includes settings
    public static let includesSettings = HawalaFileFlags(rawValue: 1 << 2)
    
    /// Backup includes transaction history
    public static let includesHistory = HawalaFileFlags(rawValue: 1 << 3)
    
    /// All data included
    public static let all: HawalaFileFlags = [
        .includesHDWallets,
        .includesImportedAccounts,
        .includesSettings,
        .includesHistory
    ]
}

// MARK: - Backup Payload

/// The decrypted payload structure stored in the .hawala file
public struct HawalaBackupPayload: Codable {
    /// Payload format version (for JSON structure migrations)
    public let payloadVersion: Int
    
    /// Creation timestamp
    public let createdAt: Date
    
    /// App version that created this backup
    public let appVersion: String
    
    /// HD wallets with their seed phrases
    public var hdWallets: [HDWalletBackup]
    
    /// Imported accounts with private keys
    public var importedAccounts: [ImportedAccountBackup]
    
    /// User settings (optional)
    public var settings: SettingsBackup?
    
    /// Checksum for integrity verification
    public let checksum: String
    
    public init(
        hdWallets: [HDWalletBackup] = [],
        importedAccounts: [ImportedAccountBackup] = [],
        settings: SettingsBackup? = nil
    ) {
        self.payloadVersion = 1
        self.createdAt = Date()
        self.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        self.hdWallets = hdWallets
        self.importedAccounts = importedAccounts
        self.settings = settings
        
        // Calculate checksum over wallet data
        let walletData = hdWallets.map { $0.seedFingerprint }.joined()
        let accountData = importedAccounts.map { $0.address }.joined()
        let checksumInput = walletData + accountData + createdAt.description
        self.checksum = SHA256.hash(data: Data(checksumInput.utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

// MARK: - Wallet Backup Models

/// HD wallet backup including seed phrase
public struct HDWalletBackup: Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let seedFingerprint: String
    public let seedPhrase: String
    public let passphrase: String?
    public let derivationScheme: String
    public let accounts: [HDAccountBackup]
    public let createdAt: Date
    
    public init(
        id: UUID,
        name: String,
        seedFingerprint: String,
        seedPhrase: String,
        passphrase: String?,
        derivationScheme: String,
        accounts: [HDAccountBackup],
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.seedFingerprint = seedFingerprint
        self.seedPhrase = seedPhrase
        self.passphrase = passphrase
        self.derivationScheme = derivationScheme
        self.accounts = accounts
        self.createdAt = createdAt
    }
}

/// HD account backup
public struct HDAccountBackup: Codable {
    public let chainId: String
    public let accountIndex: Int
    public let derivationPath: String
    public let address: String
    
    public init(chainId: String, accountIndex: Int, derivationPath: String, address: String) {
        self.chainId = chainId
        self.accountIndex = accountIndex
        self.derivationPath = derivationPath
        self.address = address
    }
}

/// Imported account backup including private key
public struct ImportedAccountBackup: Codable, Identifiable {
    public let id: UUID
    public let name: String?
    public let chainId: String
    public let address: String
    public let privateKey: String
    public let importedAt: Date
    
    public init(
        id: UUID,
        name: String?,
        chainId: String,
        address: String,
        privateKey: String,
        importedAt: Date
    ) {
        self.id = id
        self.name = name
        self.chainId = chainId
        self.address = address
        self.privateKey = privateKey
        self.importedAt = importedAt
    }
}

/// Settings backup
public struct SettingsBackup: Codable {
    public let currency: String?
    public let theme: String?
    public let biometricEnabled: Bool?
    public let autoLockMinutes: Int?
    public let hideBalances: Bool?
    
    public init(
        currency: String? = nil,
        theme: String? = nil,
        biometricEnabled: Bool? = nil,
        autoLockMinutes: Int? = nil,
        hideBalances: Bool? = nil
    ) {
        self.currency = currency
        self.theme = theme
        self.biometricEnabled = biometricEnabled
        self.autoLockMinutes = autoLockMinutes
        self.hideBalances = hideBalances
    }
}

// MARK: - File Header

/// Parsed header from a .hawala file
public struct HawalaFileHeader {
    public let version: UInt16
    public let flags: HawalaFileFlags
    public let salt: Data
    public let nonce: Data
    
    public var isVersionSupported: Bool {
        version >= HawalaFileConstants.minimumVersion &&
        version <= HawalaFileConstants.currentVersion
    }
}

// MARK: - Errors

public enum HawalaFileError: LocalizedError {
    case invalidMagicBytes
    case unsupportedVersion(UInt16)
    case fileTooSmall
    case invalidHeader
    case decryptionFailed
    case encryptionFailed
    case invalidPassword
    case checksumMismatch
    case payloadDecodingFailed(Error)
    case payloadEncodingFailed(Error)
    case keyDerivationFailed
    case fileWriteFailed(Error)
    case fileReadFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .invalidMagicBytes:
            return "This file is not a valid Hawala backup."
        case .unsupportedVersion(let version):
            return "Backup version \(version) is not supported. Please update the app."
        case .fileTooSmall:
            return "The backup file appears to be corrupted (too small)."
        case .invalidHeader:
            return "The backup file header is invalid."
        case .decryptionFailed:
            return "Failed to decrypt the backup. The file may be corrupted."
        case .encryptionFailed:
            return "Failed to encrypt the backup data."
        case .invalidPassword:
            return "Incorrect password. Please try again."
        case .checksumMismatch:
            return "Backup integrity check failed. The file may be corrupted."
        case .payloadDecodingFailed(let error):
            return "Failed to read backup data: \(error.localizedDescription)"
        case .payloadEncodingFailed(let error):
            return "Failed to prepare backup data: \(error.localizedDescription)"
        case .keyDerivationFailed:
            return "Failed to derive encryption key."
        case .fileWriteFailed(let error):
            return "Failed to write backup file: \(error.localizedDescription)"
        case .fileReadFailed(let error):
            return "Failed to read backup file: \(error.localizedDescription)"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .invalidPassword:
            return "Make sure you're using the same password you set when creating the backup."
        case .checksumMismatch, .decryptionFailed, .fileTooSmall, .invalidHeader:
            return "Try using a different backup file or restore from your seed phrase."
        case .unsupportedVersion:
            return "Update Hawala to the latest version and try again."
        default:
            return nil
        }
    }
}
