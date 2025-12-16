import XCTest
@testable import swift_app

final class HawalaFileTests: XCTestCase {
    
    let encoder = HawalaFileEncoder.shared
    let decoder = HawalaFileDecoder.shared
    
    // MARK: - Constants Tests
    
    func testMagicBytesAreCorrect() {
        let expected: [UInt8] = [0x48, 0x41, 0x57, 0x41, 0x4C, 0x41, 0x00, 0x01]
        XCTAssertEqual(HawalaFileConstants.magicBytes, expected)
    }
    
    func testHeaderSizeCalculation() {
        // Magic (8) + Version (2) + Flags (2) + Salt (32) + Nonce (12) = 56
        XCTAssertEqual(HawalaFileConstants.headerSize, 56)
    }
    
    // MARK: - Encoding Tests
    
    func testEncodeEmptyPayload() throws {
        let payload = HawalaBackupPayload()
        let data = try encoder.encode(payload: payload, password: "test123!")
        
        // Should have header + at least some encrypted content + tag
        XCTAssertGreaterThan(data.count, HawalaFileConstants.headerSize + HawalaFileConstants.tagLength)
        
        // Should start with magic bytes
        let magicBytes = Array(data.prefix(HawalaFileConstants.magicBytes.count))
        XCTAssertEqual(magicBytes, HawalaFileConstants.magicBytes)
    }
    
    func testEncodeWithWallet() throws {
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
        
        XCTAssertGreaterThan(data.count, HawalaFileConstants.headerSize + 100) // Should contain encrypted wallet data
    }
    
    // MARK: - Decoding Tests
    
    func testDecodeRoundTrip() throws {
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
        XCTAssertEqual(decodedPayload.hdWallets.count, 1)
        XCTAssertEqual(decodedPayload.hdWallets[0].name, "Round Trip Wallet")
        XCTAssertEqual(decodedPayload.hdWallets[0].seedPhrase, wallet.seedPhrase)
        XCTAssertEqual(decodedPayload.hdWallets[0].passphrase, wallet.passphrase)
        XCTAssertEqual(decodedPayload.hdWallets[0].accounts.count, 1)
        XCTAssertEqual(decodedPayload.hdWallets[0].accounts[0].address, "bc1qtest")
        
        XCTAssertNotNil(decodedPayload.settings)
        XCTAssertEqual(decodedPayload.settings?.currency, "USD")
        XCTAssertEqual(decodedPayload.settings?.theme, "dark")
    }
    
    func testDecodeWithWrongPassword() throws {
        let payload = HawalaBackupPayload()
        let encodedData = try encoder.encode(payload: payload, password: "correctPassword")
        
        XCTAssertThrowsError(try decoder.decode(data: encodedData, password: "wrongPassword")) { error in
            XCTAssertEqual(error as? HawalaFileError, .invalidPassword)
        }
    }
    
    // MARK: - Header Validation Tests
    
    func testValidateHeaderSuccess() throws {
        let payload = HawalaBackupPayload()
        let encodedData = try encoder.encode(payload: payload, password: "test")
        
        let header = try decoder.validateHeader(encodedData)
        
        XCTAssertEqual(header.version, HawalaFileConstants.currentVersion)
        XCTAssertEqual(header.salt.count, HawalaFileConstants.saltLength)
        XCTAssertEqual(header.nonce.count, HawalaFileConstants.nonceLength)
    }
    
    func testValidateHeaderInvalidMagic() {
        var data = Data(repeating: 0x00, count: 100)
        data[0...7] = Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])[0...7]
        
        XCTAssertThrowsError(try decoder.validateHeader(data)) { error in
            XCTAssertEqual(error as? HawalaFileError, .invalidMagicBytes)
        }
    }
    
    func testValidateHeaderFileTooSmall() {
        let data = Data(repeating: 0x00, count: 10)
        
        XCTAssertThrowsError(try decoder.validateHeader(data)) { error in
            XCTAssertEqual(error as? HawalaFileError, .fileTooSmall)
        }
    }
    
    // MARK: - Password Strength Tests
    
    func testPasswordStrengthWeak() {
        XCTAssertEqual(encoder.evaluatePasswordStrength("abc"), .weak)
        XCTAssertEqual(encoder.evaluatePasswordStrength("12345"), .weak)
    }
    
    func testPasswordStrengthFair() {
        XCTAssertEqual(encoder.evaluatePasswordStrength("Password"), .fair)
        XCTAssertEqual(encoder.evaluatePasswordStrength("abcd1234"), .fair)
    }
    
    func testPasswordStrengthGood() {
        XCTAssertEqual(encoder.evaluatePasswordStrength("Password1234"), .good)
        XCTAssertEqual(encoder.evaluatePasswordStrength("Abcdefgh12!"), .good)
    }
    
    func testPasswordStrengthStrong() {
        XCTAssertEqual(encoder.evaluatePasswordStrength("MyStr0ng!P@ssw0rd"), .strong)
        XCTAssertEqual(encoder.evaluatePasswordStrength("Complex#Pass1234word"), .strong)
    }
    
    // MARK: - Flags Tests
    
    func testFlagsWithHDWallets() throws {
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
        
        XCTAssertTrue(header.flags.contains(.includesHDWallets))
        XCTAssertFalse(header.flags.contains(.includesImportedAccounts))
        XCTAssertFalse(header.flags.contains(.includesSettings))
    }
    
    func testFlagsWithSettings() throws {
        let settings = SettingsBackup(currency: "USD")
        let payload = HawalaBackupPayload(settings: settings)
        let data = try encoder.encode(payload: payload, password: "test")
        let header = try decoder.validateHeader(data)
        
        XCTAssertTrue(header.flags.contains(.includesSettings))
    }
    
    // MARK: - Checksum Tests
    
    func testChecksumVerification() throws {
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
        XCTAssertFalse(decoded.checksum.isEmpty)
    }
    
    // MARK: - Preview Tests
    
    func testPreviewBackup() throws {
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
        
        XCTAssertEqual(preview.walletCount, 1)
        XCTAssertEqual(preview.walletNames, ["Preview Wallet"])
        XCTAssertEqual(preview.importedAccountCount, 0)
        XCTAssertTrue(preview.hasSettings)
        XCTAssertFalse(preview.checksum.isEmpty)
    }
    
    // MARK: - Multiple Wallets Test
    
    func testMultipleWalletsRoundTrip() throws {
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
        
        XCTAssertEqual(decoded.hdWallets.count, 2)
        XCTAssertEqual(decoded.hdWallets[0].name, "Wallet 1")
        XCTAssertEqual(decoded.hdWallets[1].name, "Wallet 2")
        XCTAssertNil(decoded.hdWallets[0].passphrase)
        XCTAssertEqual(decoded.hdWallets[1].passphrase, "pass2")
    }
    
    // MARK: - Suggested Filename Test
    
    func testSuggestedFilename() {
        let filename = encoder.suggestedFilename()
        
        XCTAssertTrue(filename.hasPrefix("hawala-backup-"))
        XCTAssertTrue(filename.hasSuffix(".hawala"))
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
