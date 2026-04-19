import Testing
import Foundation
import CryptoKit
@testable import swift_app

// MARK: - Wallet Model Tests

@Suite
struct WalletModelTests {
    
    // MARK: - HDWallet Tests
    
    @Test func testHDWalletDeterministicID() {
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
        
        #expect(wallet1.id == wallet2.id, "Same fingerprint should produce same wallet ID")
    }
    
    @Test func testHDWalletDifferentFingerprints() {
        let fingerprint1 = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        let fingerprint2 = Data([0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18])
        
        let wallet1 = HDWallet(seedFingerprint: fingerprint1, name: "Wallet 1")
        let wallet2 = HDWallet(seedFingerprint: fingerprint2, name: "Wallet 2")
        
        #expect(wallet1.id != wallet2.id, "Different fingerprints should produce different IDs")
    }
    
    @Test func testHDWalletAccountManagement() {
        let fingerprint = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        var wallet = HDWallet(seedFingerprint: fingerprint, name: "Test")
        
        let btcAccount = HDAccount(
            chainId: .bitcoin,
            accountIndex: 0,
            derivationPath: "m/84'/0'/0'/0/0",
            address: "bc1qtest123"
        )
        
        wallet.setAccount(btcAccount)
        
        #expect(wallet.accounts.count == 1)
        #expect(wallet.account(for: .bitcoin)?.address == "bc1qtest123")
        #expect(wallet.account(for: .ethereum) == nil)
    }
    
    @Test func testHDWalletCodable() throws {
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
        
        #expect(decoded.id == wallet.id)
        #expect(decoded.name == wallet.name)
        #expect(decoded.accounts.count == 1)
    }
    
    // MARK: - ImportedAccount Tests
    
    @Test func testImportedAccountCreation() {
        let account = ImportedAccount(
            chainId: .ethereum,
            address: "0x1234567890abcdef",
            name: "My ETH Account"
        )
        
        #expect(account.chainId == .ethereum)
        #expect(account.address == "0x1234567890abcdef")
        #expect(account.name == "My ETH Account")
        #expect(account.importMethod == .privateKey)
    }
    
    @Test func testImportedAccountShortAddress() {
        let account = ImportedAccount(
            chainId: .ethereum,
            address: "0x1234567890abcdef1234567890abcdef12345678"
        )
        
        #expect(account.shortAddress == "0x1234…5678")
    }
    
    @Test func testImportedAccountCodable() throws {
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
        
        #expect(decoded.id == account.id)
        #expect(decoded.chainId == .bitcoin)
        #expect(decoded.importMethod == .wif)
    }
    
    // MARK: - ChainIdentifier Tests
    
    @Test func testChainIdentifierCoinTypes() {
        #expect(ChainIdentifier.bitcoin.coinType == 0)
        #expect(ChainIdentifier.ethereum.coinType == 60)
        #expect(ChainIdentifier.litecoin.coinType == 2)
        #expect(ChainIdentifier.solana.coinType == 501)
        #expect(ChainIdentifier.xrp.coinType == 144)
    }
    
    @Test func testChainIdentifierHDSupport() {
        #expect(ChainIdentifier.bitcoin.supportsHD)
        #expect(ChainIdentifier.ethereum.supportsHD)
        #expect(!(ChainIdentifier.monero.supportsHD))
    }
    
    // MARK: - DerivationScheme Tests
    
    @Test func testDerivationSchemePurpose() {
        #expect(DerivationScheme.bip44.purpose == 44)
        #expect(DerivationScheme.bip49.purpose == 49)
        #expect(DerivationScheme.bip84.purpose == 84)
    }
    
    @Test func testDerivationPath() {
        let fingerprint = Data(repeating: 0x01, count: 8)
        let wallet = HDWallet(
            seedFingerprint: fingerprint,
            name: "Test",
            derivationScheme: .bip84
        )
        
        let path = wallet.derivationPath(for: .bitcoin)
        #expect(path == "m/84'/0'/0'/0/0")
        
        let ethPath = wallet.derivationPath(for: .ethereum)
        #expect(ethPath == "m/84'/60'/0'/0/0")
    }
}

// MARK: - Mnemonic Validator Tests

@Suite
struct MnemonicValidatorTests {
    
    @Test func testValidMnemonic12Words() {
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        let result = MnemonicValidator.validate(phrase)
        #expect(result.isValid, "Standard 12-word test vector should be valid")
    }
    
    @Test func testInvalidWordCount() {
        let phrase = "abandon abandon abandon"
        let result = MnemonicValidator.validate(phrase)
        
        if case .invalidWordCount(let count) = result {
            #expect(count == 3)
        } else {
            #expect(Bool(false), "Expected invalidWordCount error")
        }
    }
    
    @Test func testInvalidWord() {
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon notaword"
        let result = MnemonicValidator.validate(phrase)
        
        if case .invalidWord(let word, let index) = result {
            #expect(word == "notaword")
            #expect(index == 11)
        } else {
            #expect(Bool(false), "Expected invalidWord error")
        }
    }
    
    @Test func testNormalizePhrase() {
        let phrase = "  ABANDON   Abandon\nAbandon  "
        let words = MnemonicValidator.normalizePhrase(phrase)
        
        #expect(words == ["abandon", "abandon", "abandon"])
    }
    
    @Test func testQuickValidation() {
        // Valid phrase structure (ignores checksum)
        let validStructure = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon zoo"
        #expect(MnemonicValidator.quickValidate(validStructure))
        
        // Invalid word
        let invalidWord = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon xyz"
        #expect(!(MnemonicValidator.quickValidate(invalidWord)))
    }
    
    @Test func testWordSuggestions() {
        let suggestions = MnemonicValidator.suggestions(for: "aban")
        #expect(suggestions.contains("abandon"))
        #expect(suggestions.count == 1) // Only "abandon" starts with "aban"
    }
    
    @Test func testValidWordCounts() {
        // 12 words
        let phrase12 = Array(repeating: "abandon", count: 11).joined(separator: " ") + " about"
        #expect(MnemonicValidator.quickValidate(phrase12))
        
        // 24 words
        let phrase24 = Array(repeating: "abandon", count: 23).joined(separator: " ") + " art"
        #expect(MnemonicValidator.quickValidate(phrase24))
        
        // Invalid counts
        let phrase10 = Array(repeating: "abandon", count: 10).joined(separator: " ")
        #expect(!(MnemonicValidator.quickValidate(phrase10)))
    }
}

// MARK: - Secure Memory Buffer Tests

@Suite
struct SecureMemoryBufferTests {
    
    @Test func testBufferCreation() {
        let data = Data([0x01, 0x02, 0x03, 0x04])
        let buffer = SecureMemoryBuffer(data: data)
        
        #expect(buffer.count == 4)
        #expect(!(buffer.isCleared))
    }
    
    @Test func testBufferFromString() {
        let buffer = SecureMemoryBuffer(string: "test secret")
        #expect(buffer != nil)
        #expect(buffer?.asString() == "test secret")
    }
    
    @Test func testBufferZeroMemory() {
        let buffer = SecureMemoryBuffer(string: "secret")!
        #expect(!(buffer.isCleared))
        
        buffer.zeroMemory()
        
        #expect(buffer.isCleared)
        #expect(buffer.count == 0)
    }
    
    @Test func testSecureStringRedaction() {
        let secure = SecureString("my secret password")
        
        #expect(secure.description == "[REDACTED]")
        #expect(secure.debugDescription == "[REDACTED SecureString]")
        #expect(secure.value == "my secret password")
    }
    
    @Test func testSecureStringClear() {
        let secure = SecureString("secret")
        #expect(!(secure.isCleared))
        
        secure.clear()
        
        #expect(secure.isCleared)
    }
}

// MARK: - Encrypted File Storage Tests

@Suite
struct EncryptedFileStorageTests {
    
    @Test func testEncryptDecryptRoundTrip() throws {
        let plaintext = "This is my secret seed phrase data"
        let password = "StrongPassword123!"
        
        let plaintextData = plaintext.data(using: .utf8)!
        
        let encrypted = try EncryptedFileStorage.encrypt(plaintextData, password: password)
        let decrypted = try EncryptedFileStorage.decrypt(encrypted, password: password)
        
        let decryptedString = String(data: decrypted, encoding: .utf8)
        #expect(decryptedString == plaintext)
    }
    
    @Test func testWrongPasswordFails() throws {
        let plaintext = Data("secret".utf8)
        let password = "correct"
        
        let encrypted = try EncryptedFileStorage.encrypt(plaintext, password: password)
        
        #expect(throws: (any Error).self) {
            try EncryptedFileStorage.decrypt(encrypted, password: "wrong")
        }
    }
    
    @Test func testValidBackupFileCheck() throws {
        let plaintext = Data("test".utf8)
        let encrypted = try EncryptedFileStorage.encrypt(plaintext, password: "test")
        
        // Write to temp file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.hawala")
        try encrypted.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        #expect(EncryptedFileStorage.isValidBackupFile(at: tempURL))
    }
    
    @Test func testInvalidBackupFile() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("fake.hawala")
        try Data("not encrypted".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        #expect(!(EncryptedFileStorage.isValidBackupFile(at: tempURL)))
    }
}

// MARK: - Wallet Store Tests

@Suite
struct WalletStoreTests {
    
    // Helper to create fresh test store for each test
    private func createTestStore() -> (store: UserDefaultsWalletStore, defaults: UserDefaults) {
        let suiteName = "WalletStoreTests-\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        testDefaults.removePersistentDomain(forName: suiteName)
        let store = UserDefaultsWalletStore(userDefaults: testDefaults)
        return (store, testDefaults)
    }
    
    @Test func testSaveAndLoadHDWallet() async throws {
        let (store, testDefaults) = createTestStore()
        defer { testDefaults.removePersistentDomain(forName: testDefaults.description) }
        
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
        #expect(loaded != nil)
        #expect(loaded?.name == "Test Wallet")
        #expect(loaded?.accounts.count == 1)
    }
    
    @Test func testLoadAllHDWallets() async throws {
        let (store, testDefaults) = createTestStore()
        defer { testDefaults.removePersistentDomain(forName: testDefaults.description) }
        
        let wallet1 = HDWallet(seedFingerprint: Data(repeating: 0x01, count: 8), name: "Wallet 1")
        let wallet2 = HDWallet(seedFingerprint: Data(repeating: 0x02, count: 8), name: "Wallet 2")
        
        try await store.saveHDWallet(wallet1)
        try await store.saveHDWallet(wallet2)
        
        let all = try await store.loadAllHDWallets()
        #expect(all.count == 2)
    }
    
    @Test func testDeleteHDWallet() async throws {
        let (store, testDefaults) = createTestStore()
        defer { testDefaults.removePersistentDomain(forName: testDefaults.description) }
        
        let wallet = HDWallet(seedFingerprint: Data(repeating: 0x03, count: 8), name: "To Delete")
        try await store.saveHDWallet(wallet)
        
        var hasWallets = try await store.hasWallets()
        #expect(hasWallets)
        
        try await store.deleteHDWallet(id: wallet.id)
        
        hasWallets = try await store.hasWallets()
        #expect(!hasWallets)
    }
    
    @Test func testSaveAndLoadImportedAccount() async throws {
        let (store, testDefaults) = createTestStore()
        defer { testDefaults.removePersistentDomain(forName: testDefaults.description) }
        
        let account = ImportedAccount(
            chainId: .ethereum,
            address: "0x123456",
            name: "Imported ETH"
        )
        
        try await store.saveImportedAccount(account)
        
        let loaded = try await store.loadImportedAccount(id: account.id)
        #expect(loaded != nil)
        #expect(loaded?.chainId == .ethereum)
        #expect(loaded?.address == "0x123456")
    }
    
    @Test func testDeleteAll() async throws {
        let (store, testDefaults) = createTestStore()
        defer { testDefaults.removePersistentDomain(forName: testDefaults.description) }
        
        let wallet = HDWallet(seedFingerprint: Data(repeating: 0x04, count: 8), name: "Wallet")
        let account = ImportedAccount(chainId: .bitcoin, address: "bc1q...")
        
        try await store.saveHDWallet(wallet)
        try await store.saveImportedAccount(account)
        
        var hasWallets = try await store.hasWallets()
        #expect(hasWallets)
        
        try await store.deleteAll()
        
        hasWallets = try await store.hasWallets()
        #expect(!hasWallets)
    }
}
