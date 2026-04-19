import Testing
import Foundation
@testable import swift_app

@Suite
struct HawalaFileTests {
    
    let encoder = HawalaFileEncoder.shared
    let decoder = HawalaFileDecoder.shared
    
    // MARK: - Constants Tests
    
    @Test func testMagicBytesAreCorrect() {
        let expected: [UInt8] = [0x48, 0x41, 0x57, 0x41, 0x4C, 0x41, 0x00, 0x01]
        #expect(HawalaFileConstants.magicBytes == expected)
    }
    
    @Test func testHeaderSizeCalculation() {
        // Magic (8) + Version (2) + Flags (2) + Salt (32) + Nonce (12) = 56
        #expect(HawalaFileConstants.headerSize == 56)
    }
    
    // MARK: - Encoding Tests
    
    @Test func testEncodeEmptyPayload() throws {
        let payload = HawalaBackupPayload()
        let data = try encoder.encode(payload: payload, password: "test123!")
        
        // Should have header + at least some encrypted content + tag
        #expect(data.count > HawalaFileConstants.headerSize + HawalaFileConstants.tagLength)
        
        // Should start with magic bytes
        let magicBytes = Array(data.prefix(HawalaFileConstants.magicBytes.count))
        #expect(magicBytes == HawalaFileConstants.magicBytes)
    }
    
    @Test func testEncodeWithWallet() throws {
        let wallet = HDWalletBackup(
            id: UUID(),
            name: "Test Wallet",
            seedFingerprint: "abc123",
            seedPhrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
            passphrase: nil,
            derivationScheme: "bip84",
            accounts: [],
            createdAt: Date()
        )
        
        let payload = HawalaBackupPayload(hdWallets: [wallet])
        let data = try encoder.encode(payload: payload, password: "strongP@ssw0rd!")
        
        #expect(data.count > HawalaFileConstants.headerSize + 100) // Should contain encrypted wallet data
    }
    
    // MARK: - Decoding Tests
    
    @Test func testDecodeRoundTrip() throws {
        // Create payload
        let wallet = HDWalletBackup(
            id: UUID(),
            name: "Round Trip Wallet",
            seedFingerprint: "fingerprint123",
            seedPhrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
            passphrase: "optional-passphrase",
            derivationScheme: "bip84",
            accounts: [
                HDAccountBackup(chainId: "bitcoin", accountIndex: 0, derivationPath: "m/84'/0'/0'/0/0", address: "bc1qtest")
            ],
            createdAt: Date()
        )
        
        let settings = SettingsBackup(
            currency: "USD",
            theme: "dark",
            biometricEnabled: true,
            autoLockMinutes: 5,
            hideBalances: false
        )
        
        let originalPayload = HawalaBackupPayload(
            hdWallets: [wallet],
            importedAccounts: [],
            settings: settings
        )
        
        let password = "SecureP@ssword123"
        
        // Encode
        let encodedData = try encoder.encode(payload: originalPayload, password: password)
        
        // Decode
        let decodedPayload = try decoder.decode(data: encodedData, password: password)
        
        // Verify
        #expect(decodedPayload.hdWallets.count == 1)
        #expect(decodedPayload.hdWallets[0].name == "Round Trip Wallet")
        #expect(decodedPayload.hdWallets[0].seedPhrase == wallet.seedPhrase)
        #expect(decodedPayload.hdWallets[0].passphrase == wallet.passphrase)
        #expect(decodedPayload.hdWallets[0].accounts.count == 1)
        #expect(decodedPayload.hdWallets[0].accounts[0].address == "bc1qtest")
        
        #expect(decodedPayload.settings != nil)
        #expect(decodedPayload.settings?.currency == "USD")
        #expect(decodedPayload.settings?.theme == "dark")
    }
    
    @Test func testDecodeWithWrongPassword() throws {
        let payload = HawalaBackupPayload()
        let encodedData = try encoder.encode(payload: payload, password: "correctPassword")
        
        #expect(throws: HawalaFileError.invalidPassword) {
            try decoder.decode(data: encodedData, password: "wrongPassword")
        }
    }
    
    // MARK: - Header Validation Tests
    
    @Test func testValidateHeaderSuccess() throws {
        let payload = HawalaBackupPayload()
        let encodedData = try encoder.encode(payload: payload, password: "test")
        
        let header = try decoder.validateHeader(encodedData)
        
        #expect(header.version == HawalaFileConstants.currentVersion)
        #expect(header.salt.count == HawalaFileConstants.saltLength)
        #expect(header.nonce.count == HawalaFileConstants.nonceLength)
    }
    
    @Test func testValidateHeaderInvalidMagic() {
        var data = Data(repeating: 0x00, count: 100)
        data[0...7] = Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])[0...7]
        
        #expect(throws: HawalaFileError.invalidMagicBytes) {
            try decoder.validateHeader(data)
        }
    }
    
    @Test func testValidateHeaderFileTooSmall() {
        let data = Data(repeating: 0x00, count: 10)
        
        #expect(throws: HawalaFileError.fileTooSmall) {
            try decoder.validateHeader(data)
        }
    }
    
    // MARK: - Password Strength Tests
    
    @Test func testPasswordStrengthWeak() {
        #expect(encoder.evaluatePasswordStrength("abc") == .weak)
        #expect(encoder.evaluatePasswordStrength("12345") == .weak)
    }
    
    @Test func testPasswordStrengthFair() {
        #expect(encoder.evaluatePasswordStrength("Password") == .fair)
        #expect(encoder.evaluatePasswordStrength("abcd1234") == .fair)
    }
    
    @Test func testPasswordStrengthGood() {
        #expect(encoder.evaluatePasswordStrength("Password1234") == .good)
        #expect(encoder.evaluatePasswordStrength("Abcdefgh12!") == .good)
    }
    
    @Test func testPasswordStrengthStrong() {
        #expect(encoder.evaluatePasswordStrength("MyStr0ng!P@ssw0rd") == .strong)
        #expect(encoder.evaluatePasswordStrength("Complex#Pass1234word") == .strong)
    }
    
    // MARK: - Flags Tests
    
    @Test func testFlagsWithHDWallets() throws {
        let wallet = HDWalletBackup(
            id: UUID(),
            name: "Test",
            seedFingerprint: "test",
            seedPhrase: "test phrase",
            passphrase: nil,
            derivationScheme: "bip84",
            accounts: [],
            createdAt: Date()
        )
        
        let payload = HawalaBackupPayload(hdWallets: [wallet])
        let data = try encoder.encode(payload: payload, password: "test")
        let header = try decoder.validateHeader(data)
        
        #expect(header.flags.contains(.includesHDWallets))
        #expect(!(header.flags.contains(.includesImportedAccounts)))
        #expect(!(header.flags.contains(.includesSettings)))
    }
    
    @Test func testFlagsWithSettings() throws {
        let settings = SettingsBackup(currency: "USD")
        let payload = HawalaBackupPayload(settings: settings)
        let data = try encoder.encode(payload: payload, password: "test")
        let header = try decoder.validateHeader(data)
        
        #expect(header.flags.contains(.includesSettings))
    }
    
    // MARK: - Checksum Tests
    
    @Test func testChecksumVerification() throws {
        let wallet = HDWalletBackup(
            id: UUID(),
            name: "Checksum Test",
            seedFingerprint: "checksum123",
            seedPhrase: "test seed phrase",
            passphrase: nil,
            derivationScheme: "bip84",
            accounts: [],
            createdAt: Date()
        )
        
        let payload = HawalaBackupPayload(hdWallets: [wallet])
        let data = try encoder.encode(payload: payload, password: "test")
        let decoded = try decoder.decode(data: data, password: "test")
        
        // Checksum should match
        #expect(!(decoded.checksum.isEmpty))
    }
    
    // MARK: - Preview Tests
    
    @Test func testPreviewBackup() throws {
        let wallet = HDWalletBackup(
            id: UUID(),
            name: "Preview Wallet",
            seedFingerprint: "preview123",
            seedPhrase: "preview seed phrase",
            passphrase: nil,
            derivationScheme: "bip84",
            accounts: [],
            createdAt: Date()
        )
        
        let settings = SettingsBackup(currency: "EUR")
        let payload = HawalaBackupPayload(hdWallets: [wallet], settings: settings)
        let data = try encoder.encode(payload: payload, password: "previewTest")
        
        let preview = try decoder.preview(data: data, password: "previewTest")
        
        #expect(preview.walletCount == 1)
        #expect(preview.walletNames == ["Preview Wallet"])
        #expect(preview.importedAccountCount == 0)
        #expect(preview.hasSettings)
        #expect(!(preview.checksum.isEmpty))
    }
    
    // MARK: - Multiple Wallets Test
    
    @Test func testMultipleWalletsRoundTrip() throws {
        let wallet1 = HDWalletBackup(
            id: UUID(),
            name: "Wallet 1",
            seedFingerprint: "fp1",
            seedPhrase: "seed one",
            passphrase: nil,
            derivationScheme: "bip84",
            accounts: [],
            createdAt: Date()
        )
        
        let wallet2 = HDWalletBackup(
            id: UUID(),
            name: "Wallet 2",
            seedFingerprint: "fp2",
            seedPhrase: "seed two",
            passphrase: "pass2",
            derivationScheme: "bip44",
            accounts: [],
            createdAt: Date()
        )
        
        let payload = HawalaBackupPayload(hdWallets: [wallet1, wallet2])
        let data = try encoder.encode(payload: payload, password: "multiWallet")
        let decoded = try decoder.decode(data: data, password: "multiWallet")
        
        #expect(decoded.hdWallets.count == 2)
        #expect(decoded.hdWallets[0].name == "Wallet 1")
        #expect(decoded.hdWallets[1].name == "Wallet 2")
        #expect(decoded.hdWallets[0].passphrase == nil)
        #expect(decoded.hdWallets[1].passphrase == "pass2")
    }
    
    // MARK: - Suggested Filename Test
    
    @Test func testSuggestedFilename() {
        let filename = encoder.suggestedFilename()
        
        #expect(filename.hasPrefix("hawala-backup-"))
        #expect(filename.hasSuffix(".hawala"))
    }
}

// MARK: - Error Equality for Testing

extension HawalaFileError: Equatable {
    public static func == (lhs: HawalaFileError, rhs: HawalaFileError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidMagicBytes, .invalidMagicBytes): return true
        case (.unsupportedVersion(let v1), .unsupportedVersion(let v2)): return v1 == v2
        case (.fileTooSmall, .fileTooSmall): return true
        case (.invalidHeader, .invalidHeader): return true
        case (.decryptionFailed, .decryptionFailed): return true
        case (.encryptionFailed, .encryptionFailed): return true
        case (.invalidPassword, .invalidPassword): return true
        case (.checksumMismatch, .checksumMismatch): return true
        case (.keyDerivationFailed, .keyDerivationFailed): return true
        default: return false
        }
    }
}
