import XCTest
import CryptoKit
@testable import swift_app

// MARK: - Wallet Model Tests

final class WalletModelTests: XCTestCase {
    
    // MARK: - HDWallet Tests
    
    func testHDWalletDeterministicID() {
        // Same seed fingerprint should produce same wallet ID
        let fingerprint = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        
        let wallet1 = HDWallet(
            seedFingerprint: fingerprint,
            name: "Test Wallet 1"
        )
        
        let wallet2 = HDWallet(
            seedFingerprint: fingerprint,
            name: "Test Wallet 2"
        )
        
        XCTAssertEqual(wallet1.id, wallet2.id, "Same fingerprint should produce same wallet ID")
    }
    
    func testHDWalletDifferentFingerprints() {
        let fingerprint1 = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        let fingerprint2 = Data([0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18])
        
        let wallet1 = HDWallet(seedFingerprint: fingerprint1, name: "Wallet 1")
        let wallet2 = HDWallet(seedFingerprint: fingerprint2, name: "Wallet 2")
        
        XCTAssertNotEqual(wallet1.id, wallet2.id, "Different fingerprints should produce different IDs")
    }
    
    func testHDWalletAccountManagement() {
        let fingerprint = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        var wallet = HDWallet(seedFingerprint: fingerprint, name: "Test")
        
        let btcAccount = HDAccount(
            chainId: .bitcoin,
            accountIndex: 0,
            derivationPath: "m/84'/0'/0'/0/0",
            address: "bc1qtest123"
        )
        
        wallet.setAccount(btcAccount)
        
        XCTAssertEqual(wallet.accounts.count, 1)
        XCTAssertEqual(wallet.account(for: .bitcoin)?.address, "bc1qtest123")
        XCTAssertNil(wallet.account(for: .ethereum))
    }
    
    func testHDWalletCodable() throws {
        let fingerprint = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        var wallet = HDWallet(seedFingerprint: fingerprint, name: "Test Wallet")
        
        let account = HDAccount(
            chainId: .bitcoin,
            accountIndex: 0,
            derivationPath: "m/84'/0'/0'/0/0",
            address: "bc1qtest"
        )
        wallet.setAccount(account)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(wallet)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HDWallet.self, from: data)
        
        XCTAssertEqual(decoded.id, wallet.id)
        XCTAssertEqual(decoded.name, wallet.name)
        XCTAssertEqual(decoded.accounts.count, 1)
    }
    
    // MARK: - ImportedAccount Tests
    
    func testImportedAccountCreation() {
        let account = ImportedAccount(
            chainId: .ethereum,
            address: "0x1234567890abcdef",
            name: "My ETH Account"
        )
        
        XCTAssertEqual(account.chainId, .ethereum)
        XCTAssertEqual(account.address, "0x1234567890abcdef")
        XCTAssertEqual(account.name, "My ETH Account")
        XCTAssertEqual(account.importMethod, .privateKey)
    }
    
    func testImportedAccountShortAddress() {
        let account = ImportedAccount(
            chainId: .ethereum,
            address: "0x1234567890abcdef1234567890abcdef12345678"
        )
        
        XCTAssertEqual(account.shortAddress, "0x1234…5678")
    }
    
    func testImportedAccountCodable() throws {
        let account = ImportedAccount(
            chainId: .bitcoin,
            address: "bc1qtest123456789",
            name: "BTC Import",
            importMethod: .wif
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(account)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ImportedAccount.self, from: data)
        
        XCTAssertEqual(decoded.id, account.id)
        XCTAssertEqual(decoded.chainId, .bitcoin)
        XCTAssertEqual(decoded.importMethod, .wif)
    }
    
    // MARK: - ChainIdentifier Tests
    
    func testChainIdentifierCoinTypes() {
        XCTAssertEqual(ChainIdentifier.bitcoin.coinType, 0)
        XCTAssertEqual(ChainIdentifier.ethereum.coinType, 60)
        XCTAssertEqual(ChainIdentifier.litecoin.coinType, 2)
        XCTAssertEqual(ChainIdentifier.solana.coinType, 501)
        XCTAssertEqual(ChainIdentifier.xrp.coinType, 144)
    }
    
    func testChainIdentifierHDSupport() {
        XCTAssertTrue(ChainIdentifier.bitcoin.supportsHD)
        XCTAssertTrue(ChainIdentifier.ethereum.supportsHD)
        XCTAssertFalse(ChainIdentifier.monero.supportsHD)
    }
    
    // MARK: - DerivationScheme Tests
    
    func testDerivationSchemePurpose() {
        XCTAssertEqual(DerivationScheme.bip44.purpose, 44)
        XCTAssertEqual(DerivationScheme.bip49.purpose, 49)
        XCTAssertEqual(DerivationScheme.bip84.purpose, 84)
    }
    
    func testDerivationPath() {
        let fingerprint = Data(repeating: 0x01, count: 8)
        let wallet = HDWallet(
            seedFingerprint: fingerprint,
            name: "Test",
            derivationScheme: .bip84
        )
        
        let path = wallet.derivationPath(for: .bitcoin)
        XCTAssertEqual(path, "m/84'/0'/0'/0/0")
        
        let ethPath = wallet.derivationPath(for: .ethereum)
        XCTAssertEqual(ethPath, "m/84'/60'/0'/0/0")
    }
}

// MARK: - Mnemonic Validator Tests

final class MnemonicValidatorTests: XCTestCase {
    
    func testValidMnemonic12Words() {
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        let result = MnemonicValidator.validate(phrase)
        XCTAssertTrue(result.isValid, "Standard 12-word test vector should be valid")
    }
    
    func testInvalidWordCount() {
        let phrase = "abandon abandon abandon"
        let result = MnemonicValidator.validate(phrase)
        
        if case .invalidWordCount(let count) = result {
            XCTAssertEqual(count, 3)
        } else {
            XCTFail("Expected invalidWordCount error")
        }
    }
    
    func testInvalidWord() {
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon notaword"
        let result = MnemonicValidator.validate(phrase)
        
        if case .invalidWord(let word, let index) = result {
            XCTAssertEqual(word, "notaword")
            XCTAssertEqual(index, 11)
        } else {
            XCTFail("Expected invalidWord error")
        }
    }
    
    func testNormalizePhrase() {
        let phrase = "  ABANDON   Abandon\nAbandon  "
        let words = MnemonicValidator.normalizePhrase(phrase)
        
        XCTAssertEqual(words, ["abandon", "abandon", "abandon"])
    }
    
    func testQuickValidation() {
        // Valid phrase structure (ignores checksum)
        let validStructure = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon zoo"
        XCTAssertTrue(MnemonicValidator.quickValidate(validStructure))
        
        // Invalid word
        let invalidWord = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon xyz"
        XCTAssertFalse(MnemonicValidator.quickValidate(invalidWord))
    }
    
    func testWordSuggestions() {
        let suggestions = MnemonicValidator.suggestions(for: "aban")
        XCTAssertTrue(suggestions.contains("abandon"))
        XCTAssertEqual(suggestions.count, 1) // Only "abandon" starts with "aban"
    }
    
    func testValidWordCounts() {
        // 12 words
        let phrase12 = Array(repeating: "abandon", count: 11).joined(separator: " ") + " about"
        XCTAssertTrue(MnemonicValidator.quickValidate(phrase12))
        
        // 24 words
        let phrase24 = Array(repeating: "abandon", count: 23).joined(separator: " ") + " art"
        XCTAssertTrue(MnemonicValidator.quickValidate(phrase24))
        
        // Invalid counts
        let phrase10 = Array(repeating: "abandon", count: 10).joined(separator: " ")
        XCTAssertFalse(MnemonicValidator.quickValidate(phrase10))
    }
}

// MARK: - Secure Memory Buffer Tests

final class SecureMemoryBufferTests: XCTestCase {
    
    func testBufferCreation() {
        let data = Data([0x01, 0x02, 0x03, 0x04])
        let buffer = SecureMemoryBuffer(data: data)
        
        XCTAssertEqual(buffer.count, 4)
        XCTAssertFalse(buffer.isCleared)
    }
    
    func testBufferFromString() {
        let buffer = SecureMemoryBuffer(string: "test secret")
        XCTAssertNotNil(buffer)
        XCTAssertEqual(buffer?.asString(), "test secret")
    }
    
    func testBufferZeroMemory() {
        let buffer = SecureMemoryBuffer(string: "secret")!
        XCTAssertFalse(buffer.isCleared)
        
        buffer.zeroMemory()
        
        XCTAssertTrue(buffer.isCleared)
        XCTAssertEqual(buffer.count, 0)
    }
    
    func testSecureStringRedaction() {
        let secure = SecureString("my secret password")
        
        XCTAssertEqual(secure.description, "[REDACTED]")
        XCTAssertEqual(secure.debugDescription, "[REDACTED SecureString]")
        XCTAssertEqual(secure.value, "my secret password")
    }
    
    func testSecureStringClear() {
        let secure = SecureString("secret")
        XCTAssertFalse(secure.isCleared)
        
        secure.clear()
        
        XCTAssertTrue(secure.isCleared)
    }
}

// MARK: - Encrypted File Storage Tests

final class EncryptedFileStorageTests: XCTestCase {
    
    func testEncryptDecryptRoundTrip() throws {
        let plaintext = "This is my secret seed phrase data"
        let password = "StrongPassword123!"
        
        let plaintextData = plaintext.data(using: .utf8)!
        
        let encrypted = try EncryptedFileStorage.encrypt(plaintextData, password: password)
        let decrypted = try EncryptedFileStorage.decrypt(encrypted, password: password)
        
        let decryptedString = String(data: decrypted, encoding: .utf8)
        XCTAssertEqual(decryptedString, plaintext)
    }
    
    func testWrongPasswordFails() throws {
        let plaintext = Data("secret".utf8)
        let password = "correct"
        
        let encrypted = try EncryptedFileStorage.encrypt(plaintext, password: password)
        
        XCTAssertThrowsError(try EncryptedFileStorage.decrypt(encrypted, password: "wrong")) { error in
            // Should fail to decrypt with wrong password
            XCTAssertTrue(error is SecureStorageError || error is CryptoKit.CryptoKitError)
        }
    }
    
    func testValidBackupFileCheck() throws {
        let plaintext = Data("test".utf8)
        let encrypted = try EncryptedFileStorage.encrypt(plaintext, password: "test")
        
        // Write to temp file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.hawala")
        try encrypted.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        XCTAssertTrue(EncryptedFileStorage.isValidBackupFile(at: tempURL))
    }
    
    func testInvalidBackupFile() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("fake.hawala")
        try Data("not encrypted".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        XCTAssertFalse(EncryptedFileStorage.isValidBackupFile(at: tempURL))
    }
}

// MARK: - Wallet Store Tests

final class WalletStoreTests: XCTestCase {
    
    var store: UserDefaultsWalletStore!
    var testDefaults: UserDefaults!
    
    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: "WalletStoreTests")!
        testDefaults.removePersistentDomain(forName: "WalletStoreTests")
        store = UserDefaultsWalletStore(userDefaults: testDefaults)
    }
    
    override func tearDown() {
        testDefaults.removePersistentDomain(forName: "WalletStoreTests")
        super.tearDown()
    }
    
    func testSaveAndLoadHDWallet() async throws {
        let fingerprint = Data(repeating: 0x42, count: 8)
        var wallet = HDWallet(seedFingerprint: fingerprint, name: "Test Wallet")
        
        let account = HDAccount(
            chainId: .bitcoin,
            accountIndex: 0,
            derivationPath: "m/84'/0'/0'/0/0",
            address: "bc1qtest"
        )
        wallet.setAccount(account)
        
        try await store.saveHDWallet(wallet)
        
        let loaded = try await store.loadHDWallet(id: wallet.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.name, "Test Wallet")
        XCTAssertEqual(loaded?.accounts.count, 1)
    }
    
    func testLoadAllHDWallets() async throws {
        let wallet1 = HDWallet(seedFingerprint: Data(repeating: 0x01, count: 8), name: "Wallet 1")
        let wallet2 = HDWallet(seedFingerprint: Data(repeating: 0x02, count: 8), name: "Wallet 2")
        
        try await store.saveHDWallet(wallet1)
        try await store.saveHDWallet(wallet2)
        
        let all = try await store.loadAllHDWallets()
        XCTAssertEqual(all.count, 2)
    }
    
    func testDeleteHDWallet() async throws {
        let wallet = HDWallet(seedFingerprint: Data(repeating: 0x03, count: 8), name: "To Delete")
        try await store.saveHDWallet(wallet)
        
        var hasWallets = try await store.hasWallets()
        XCTAssertTrue(hasWallets)
        
        try await store.deleteHDWallet(id: wallet.id)
        
        hasWallets = try await store.hasWallets()
        XCTAssertFalse(hasWallets)
    }
    
    func testSaveAndLoadImportedAccount() async throws {
        let account = ImportedAccount(
            chainId: .ethereum,
            address: "0x123456",
            name: "Imported ETH"
        )
        
        try await store.saveImportedAccount(account)
        
        let loaded = try await store.loadImportedAccount(id: account.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.chainId, .ethereum)
        XCTAssertEqual(loaded?.address, "0x123456")
    }
    
    func testDeleteAll() async throws {
        let wallet = HDWallet(seedFingerprint: Data(repeating: 0x04, count: 8), name: "Wallet")
        let account = ImportedAccount(chainId: .bitcoin, address: "bc1q...")
        
        try await store.saveHDWallet(wallet)
        try await store.saveImportedAccount(account)
        
        var hasWallets = try await store.hasWallets()
        XCTAssertTrue(hasWallets)
        
        try await store.deleteAll()
        
        hasWallets = try await store.hasWallets()
        XCTAssertFalse(hasWallets)
    }
}
