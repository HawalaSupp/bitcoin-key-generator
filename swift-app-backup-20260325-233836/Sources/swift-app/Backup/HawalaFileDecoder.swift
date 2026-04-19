import Foundation
import CryptoKit
import CommonCrypto

// MARK: - Hawala File Decoder

/// Decodes encrypted .hawala backup files
public final class HawalaFileDecoder: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = HawalaFileDecoder()
    
    private init() {}
    
    // MARK: - Public API
    
    /// Validate a .hawala file without decrypting
    /// - Parameter data: File data to validate
    /// - Returns: File header if valid
    public func validateHeader(_ data: Data) throws -> HawalaFileHeader {
        // Check minimum size
        guard data.count >= HawalaFileConstants.headerSize + HawalaFileConstants.tagLength else {
            throw HawalaFileError.fileTooSmall
        }
        
        // Check magic bytes
        let magicBytes = Array(data.prefix(HawalaFileConstants.magicBytes.count))
        guard magicBytes == HawalaFileConstants.magicBytes else {
            throw HawalaFileError.invalidMagicBytes
        }
        
        // Parse version (big-endian)
        let versionOffset = HawalaFileConstants.magicBytes.count
        let versionData = data.subdata(in: versionOffset..<(versionOffset + 2))
        let version = versionData.withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        
        guard version >= HawalaFileConstants.minimumVersion,
              version <= HawalaFileConstants.currentVersion else {
            throw HawalaFileError.unsupportedVersion(version)
        }
        
        // Parse flags (big-endian)
        let flagsOffset = versionOffset + 2
        let flagsData = data.subdata(in: flagsOffset..<(flagsOffset + 2))
        let flagsRaw = flagsData.withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        let flags = HawalaFileFlags(rawValue: flagsRaw)
        
        // Extract salt
        let saltOffset = flagsOffset + 2
        let salt = data.subdata(in: saltOffset..<(saltOffset + HawalaFileConstants.saltLength))
        
        // Extract nonce
        let nonceOffset = saltOffset + HawalaFileConstants.saltLength
        let nonce = data.subdata(in: nonceOffset..<(nonceOffset + HawalaFileConstants.nonceLength))
        
        return HawalaFileHeader(
            version: version,
            flags: flags,
            salt: salt,
            nonce: nonce
        )
    }
    
    /// Decode and decrypt a .hawala backup file
    /// - Parameters:
    ///   - data: Encrypted file data
    ///   - password: User-provided password
    /// - Returns: Decrypted backup payload
    public func decode(data: Data, password: String) throws -> HawalaBackupPayload {
        // 1. Validate and parse header
        let header = try validateHeader(data)
        
        // 2. Extract encrypted payload
        let payloadStart = HawalaFileConstants.headerSize
        let payloadEnd = data.count - HawalaFileConstants.tagLength
        let ciphertext = data.subdata(in: payloadStart..<payloadEnd)
        let tag = data.subdata(in: payloadEnd..<data.count)
        
        // 3. Derive decryption key
        let key = try deriveKey(from: password, salt: header.salt)
        
        // 4. Decrypt with AES-256-GCM
        let plaintext: Data
        do {
            let nonce = try AES.GCM.Nonce(data: header.nonce)
            let sealedBox = try AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: ciphertext,
                tag: tag
            )
            plaintext = try AES.GCM.open(sealedBox, using: key)
        } catch {
            // Decryption failure most likely means wrong password
            throw HawalaFileError.invalidPassword
        }
        
        // 5. Decode JSON payload
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let payload: HawalaBackupPayload
        do {
            payload = try decoder.decode(HawalaBackupPayload.self, from: plaintext)
        } catch {
            throw HawalaFileError.payloadDecodingFailed(error)
        }
        
        // 6. Verify checksum
        try verifyChecksum(payload)
        
        return payload
    }
    
    /// Restore wallets from a backup payload
    /// - Parameters:
    ///   - payload: Decrypted backup payload
    ///   - walletManager: Wallet manager to restore into
    ///   - overwriteExisting: Whether to overwrite existing wallets with same fingerprint
    /// - Returns: Summary of restoration
    @MainActor
    func restore(
        payload: HawalaBackupPayload,
        into walletManager: WalletManager,
        overwriteExisting: Bool = false
    ) async throws -> RestorationSummary {
        var summary = RestorationSummary()
        
        for walletBackup in payload.hdWallets {
            // Check if wallet already exists by ID (since fingerprint isn't stored)
            let existingWallet = walletManager.hdWallets.first(where: { $0.id == walletBackup.id })
            
            if existingWallet != nil {
                if overwriteExisting {
                    // Delete existing and restore
                    try await walletManager.deleteWallet(id: existingWallet!.id)
                    summary.overwritten += 1
                } else {
                    summary.skipped += 1
                    summary.skippedWallets.append(walletBackup.name)
                    continue
                }
            }
            
            // Restore wallet
            do {
                _ = try await walletManager.restoreWallet(
                    from: walletBackup.seedPhrase,
                    name: walletBackup.name,
                    passphrase: walletBackup.passphrase ?? ""
                )
                summary.restored += 1
                summary.restoredWallets.append(walletBackup.name)
            } catch {
                summary.failed += 1
                summary.failedWallets.append((walletBackup.name, error.localizedDescription))
            }
        }
        
        // Restore settings if present
        if let settings = payload.settings {
            restoreSettings(settings)
            summary.settingsRestored = true
        }
        
        return summary
    }
    
    /// Get a preview of backup contents without full restoration
    /// - Parameters:
    ///   - data: Encrypted file data
    ///   - password: User password
    /// - Returns: Preview information
    public func preview(data: Data, password: String) throws -> BackupPreview {
        let payload = try decode(data: data, password: password)
        
        return BackupPreview(
            createdAt: payload.createdAt,
            appVersion: payload.appVersion,
            walletCount: payload.hdWallets.count,
            walletNames: payload.hdWallets.map { $0.name },
            importedAccountCount: payload.importedAccounts.count,
            hasSettings: payload.settings != nil,
            checksum: payload.checksum
        )
    }
    
    // MARK: - Private Helpers
    
    private func deriveKey(from password: String, salt: Data) throws -> SymmetricKey {
        guard let passwordData = password.data(using: .utf8) else {
            throw HawalaFileError.keyDerivationFailed
        }
        
        var derivedKey = Data(count: 32)
        
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
    
    private func verifyChecksum(_ payload: HawalaBackupPayload) throws {
        let walletData = payload.hdWallets.map { $0.seedFingerprint }.joined()
        let accountData = payload.importedAccounts.map { $0.address }.joined()
        let checksumInput = walletData + accountData + payload.createdAt.description
        let expectedChecksum = SHA256.hash(data: Data(checksumInput.utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
        
        guard payload.checksum == expectedChecksum else {
            throw HawalaFileError.checksumMismatch
        }
    }
    
    private func restoreSettings(_ settings: SettingsBackup) {
        if let currency = settings.currency {
            UserDefaults.standard.set(currency, forKey: "selectedCurrency")
        }
        if let theme = settings.theme {
            UserDefaults.standard.set(theme, forKey: "appTheme")
        }
        if let biometricEnabled = settings.biometricEnabled {
            UserDefaults.standard.set(biometricEnabled, forKey: "biometricEnabled")
        }
        if let autoLockMinutes = settings.autoLockMinutes {
            UserDefaults.standard.set(autoLockMinutes, forKey: "autoLockMinutes")
        }
        if let hideBalances = settings.hideBalances {
            UserDefaults.standard.set(hideBalances, forKey: "hideBalances")
        }
    }
}

// MARK: - Supporting Types

/// Summary of a restoration operation
public struct RestorationSummary {
    public var restored: Int = 0
    public var skipped: Int = 0
    public var overwritten: Int = 0
    public var failed: Int = 0
    public var restoredWallets: [String] = []
    public var skippedWallets: [String] = []
    public var failedWallets: [(name: String, error: String)] = []
    public var settingsRestored: Bool = false
    
    public var isSuccess: Bool {
        failed == 0 && (restored > 0 || skipped > 0)
    }
    
    public var summary: String {
        var parts: [String] = []
        if restored > 0 { parts.append("\(restored) restored") }
        if skipped > 0 { parts.append("\(skipped) skipped (already exist)") }
        if overwritten > 0 { parts.append("\(overwritten) overwritten") }
        if failed > 0 { parts.append("\(failed) failed") }
        if settingsRestored { parts.append("settings restored") }
        return parts.joined(separator: ", ")
    }
}

/// Preview of backup contents
public struct BackupPreview {
    public let createdAt: Date
    public let appVersion: String
    public let walletCount: Int
    public let walletNames: [String]
    public let importedAccountCount: Int
    public let hasSettings: Bool
    public let checksum: String
    
    public var createdAtFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
}

// MARK: - File URL Extension

public extension URL {
    /// Check if URL points to a .hawala file
    var isHawalaFile: Bool {
        pathExtension.lowercased() == HawalaFileConstants.fileExtension
    }
}
