import SwiftUI
import CryptoKit
#if canImport(AVFoundation)
import AVFoundation
#endif

// MARK: - Import Method

enum WalletImportMethod: String, CaseIterable, Identifiable {
    case seedPhrase = "seed_phrase"
    case privateKey = "private_key"
    case qrCode = "qr_code"
    case hardwareWallet = "hardware_wallet"
    case iCloudBackup = "icloud_backup"
    case hawalaFile = "hawala_file"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .seedPhrase: return "text.word.spacing"
        case .privateKey: return "key.fill"
        case .qrCode: return "qrcode.viewfinder"
        case .hardwareWallet: return "cpu"
        case .iCloudBackup: return "icloud.fill"
        case .hawalaFile: return "doc.fill"
        }
    }
    
    var title: String {
        switch self {
        case .seedPhrase: return "Recovery Phrase"
        case .privateKey: return "Private Key"
        case .qrCode: return "Scan QR Code"
        case .hardwareWallet: return "Hardware Wallet"
        case .iCloudBackup: return "iCloud Backup"
        case .hawalaFile: return "Hawala Backup File"
        }
    }
    
    var description: String {
        switch self {
        case .seedPhrase: return "12, 18, or 24 word phrase"
        case .privateKey: return "Hex or WIF format"
        case .qrCode: return "Scan from another device"
        case .hardwareWallet: return "Ledger or Trezor"
        case .iCloudBackup: return "Restore from Apple iCloud"
        case .hawalaFile: return "Import .hawala backup"
        }
    }
    
    var isAvailable: Bool {
        switch self {
        case .seedPhrase, .privateKey, .hawalaFile:
            return true
        case .qrCode:
            #if os(macOS)
            return true // macOS can use camera
            #else
            return true
            #endif
        case .hardwareWallet:
            return true // USB/Bluetooth available
        case .iCloudBackup:
            return SecureSeedStorage.hasiCloudBackup()
        }
    }
}

// MARK: - Import State

enum ImportState: Equatable {
    case idle
    case validating
    case deriving
    case importing
    case success(String) // wallet name
    case error(ImportError)
    
    static func == (lhs: ImportState, rhs: ImportState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.validating, .validating), (.deriving, .deriving), (.importing, .importing):
            return true
        case (.success(let a), .success(let b)):
            return a == b
        case (.error(let a), .error(let b)):
            return a.localizedDescription == b.localizedDescription
        default:
            return false
        }
    }
}

// MARK: - Import Error

enum ImportError: Error, LocalizedError {
    case invalidSeedPhrase(reason: String)
    case invalidPrivateKey
    case invalidQRCode
    case hardwareNotConnected
    case hardwareRejected
    case iCloudNotAvailable
    case iCloudDecryptionFailed
    case fileCorrupted
    case fileWrongPassword
    case walletAlreadyExists
    case derivationFailed
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidSeedPhrase(let reason):
            return "Invalid recovery phrase: \(reason)"
        case .invalidPrivateKey:
            return "Invalid private key format"
        case .invalidQRCode:
            return "QR code doesn't contain valid wallet data"
        case .hardwareNotConnected:
            return "Hardware wallet not detected"
        case .hardwareRejected:
            return "Operation rejected on hardware wallet"
        case .iCloudNotAvailable:
            return "iCloud backup not available"
        case .iCloudDecryptionFailed:
            return "Could not decrypt iCloud backup"
        case .fileCorrupted:
            return "Backup file is corrupted"
        case .fileWrongPassword:
            return "Incorrect backup password"
        case .walletAlreadyExists:
            return "This wallet is already imported"
        case .derivationFailed:
            return "Could not derive wallet keys"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .invalidSeedPhrase:
            return "Check for typos and ensure all words are from the BIP39 wordlist"
        case .invalidPrivateKey:
            return "Ensure the key is in hexadecimal (64 chars) or WIF format"
        case .invalidQRCode:
            return "Try scanning again or use manual entry"
        case .hardwareNotConnected:
            return "Connect your hardware wallet and unlock it"
        case .hardwareRejected:
            return "Try again and approve the request on your device"
        case .iCloudNotAvailable:
            return "Sign in to iCloud and enable Keychain sync"
        case .iCloudDecryptionFailed:
            return "The backup may be from a different Apple ID"
        case .fileCorrupted:
            return "Try a different backup file"
        case .fileWrongPassword:
            return "Check your password and try again"
        case .walletAlreadyExists:
            return "This wallet has already been imported"
        case .derivationFailed:
            return "Try reimporting with a different derivation path"
        case .unknown:
            return nil
        }
    }
}

// MARK: - Wallet Import Manager

@MainActor
final class WalletImportManager: ObservableObject {
    
    // MARK: - Published State
    @Published var state: ImportState = .idle
    @Published var selectedMethod: WalletImportMethod?
    @Published var progress: Double = 0
    @Published var progressMessage: String = ""
    
    // Seed phrase input
    @Published var seedWords: [String] = Array(repeating: "", count: 24)
    @Published var wordCount: Int = 12
    @Published var passphrase: String = ""
    @Published var usePassphrase: Bool = false
    
    // Private key input
    @Published var privateKey: String = ""
    @Published var selectedChain: String = "ethereum"
    
    // Wallet naming
    @Published var walletName: String = "Imported Wallet"
    
    // QR scanning
    @Published var isScanning: Bool = false
    @Published var scannedData: String = ""
    
    // iCloud backup
    @Published var availableBackups: [CloudBackupInfo] = []
    @Published var selectedBackup: CloudBackupInfo?
    @Published var backupPassword: String = ""
    
    // Hardware wallet
    @Published var detectedDevices: [HardwareDevice] = []
    @Published var selectedDevice: HardwareDevice?
    
    // MARK: - Dependencies
    private let walletManager: WalletManager
    private let keyDerivation: KeyDerivationService
    
    // MARK: - Singleton
    static let shared = WalletImportManager()
    
    private init() {
        self.walletManager = WalletManager.shared
        self.keyDerivation = KeyDerivationService.shared
    }
    
    // MARK: - Reset
    
    func reset() {
        state = .idle
        selectedMethod = nil
        progress = 0
        progressMessage = ""
        seedWords = Array(repeating: "", count: 24)
        wordCount = 12
        passphrase = ""
        usePassphrase = false
        privateKey = ""
        selectedChain = "ethereum"
        walletName = "Imported Wallet"
        isScanning = false
        scannedData = ""
        availableBackups = []
        selectedBackup = nil
        backupPassword = ""
        detectedDevices = []
        selectedDevice = nil
    }
    
    // MARK: - Seed Phrase Import
    
    var currentSeedPhrase: String {
        seedWords.prefix(wordCount).joined(separator: " ")
    }
    
    var seedPhraseValidation: SeedPhraseValidation {
        validateSeedPhrase()
    }
    
    struct SeedPhraseValidation {
        let isValid: Bool
        let enteredCount: Int
        let requiredCount: Int
        let invalidWords: [Int] // indices of invalid words
        let duplicateWarning: Bool
        let checksumValid: Bool
        
        var errorMessage: String? {
            if enteredCount < requiredCount {
                return "Enter \(requiredCount - enteredCount) more words"
            }
            if !invalidWords.isEmpty {
                return "Word \(invalidWords.first! + 1) is not valid"
            }
            if !checksumValid && enteredCount == requiredCount {
                return "Checksum verification failed"
            }
            return nil
        }
    }
    
    private func validateSeedPhrase() -> SeedPhraseValidation {
        let words = seedWords.prefix(wordCount).map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        let enteredCount = words.filter { !$0.isEmpty }.count
        
        // Find invalid words
        var invalidIndices: [Int] = []
        for (index, word) in words.enumerated() {
            if !word.isEmpty && !BIP39Wordlist.english.contains(word) {
                invalidIndices.append(index)
            }
        }
        
        // Check for duplicates (suspicious but not invalid)
        let nonEmptyWords = words.filter { !$0.isEmpty }
        let duplicateWarning = Set(nonEmptyWords).count != nonEmptyWords.count
        
        // Validate checksum if complete
        var checksumValid = false
        if enteredCount == wordCount && invalidIndices.isEmpty {
            let phrase = words.joined(separator: " ")
            let result = MnemonicValidator.validate(phrase)
            checksumValid = result.isValid
        }
        
        return SeedPhraseValidation(
            isValid: enteredCount == wordCount && invalidIndices.isEmpty && checksumValid,
            enteredCount: enteredCount,
            requiredCount: wordCount,
            invalidWords: invalidIndices,
            duplicateWarning: duplicateWarning,
            checksumValid: checksumValid
        )
    }
    
    func setWordCount(_ count: Int) {
        guard [12, 18, 24].contains(count) else { return }
        wordCount = count
        // Resize array if needed
        if seedWords.count < count {
            seedWords.append(contentsOf: Array(repeating: "", count: count - seedWords.count))
        }
    }
    
    func importFromSeedPhrase() async {
        guard seedPhraseValidation.isValid else {
            state = .error(.invalidSeedPhrase(reason: seedPhraseValidation.errorMessage ?? "Invalid phrase"))
            return
        }
        
        state = .deriving
        progress = 0.2
        progressMessage = "Deriving wallet keys..."
        
        do {
            let phrase = currentSeedPhrase
            let pass = usePassphrase ? passphrase : ""
            
            progress = 0.4
            progressMessage = "Generating addresses..."
            
            let keys = try await keyDerivation.restoreWallet(from: phrase, passphrase: pass)
            
            progress = 0.6
            progressMessage = "Securing wallet..."
            
            // Store securely - parse phrase into words array
            let words = SecureSeedStorage.parseSeedPhrase(phrase)
            try SecureSeedStorage.saveSeedPhrase(words, withPasscode: nil)
            
            progress = 0.8
            progressMessage = "Finalizing..."
            
            // Create wallet in manager
            let wallet = try await walletManager.restoreWallet(
                from: phrase,
                name: walletName,
                passphrase: pass
            )
            
            progress = 1.0
            state = .success(wallet.name)
            
            // Track in security score
            SecurityScoreManager.shared.complete(.backupVerified)
            
            #if DEBUG
            print("✅ Wallet imported: \(wallet.name)")
            #endif
            
        } catch {
            state = .error(.derivationFailed)
            #if DEBUG
            print("❌ Import failed: \(error)")
            #endif
        }
    }
    
    // MARK: - Private Key Import
    
    var privateKeyValidation: PrivateKeyValidation {
        validatePrivateKey()
    }
    
    struct PrivateKeyValidation {
        let isValid: Bool
        let format: PrivateKeyFormat?
        let errorMessage: String?
        
        enum PrivateKeyFormat {
            case hex
            case wif
            case wifCompressed
        }
    }
    
    private func validatePrivateKey() -> PrivateKeyValidation {
        let key = privateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Empty
        if key.isEmpty {
            return PrivateKeyValidation(isValid: false, format: nil, errorMessage: nil)
        }
        
        // Hex format (64 characters, 0-9 a-f)
        if key.count == 64 || (key.hasPrefix("0x") && key.count == 66) {
            let hexKey = key.hasPrefix("0x") ? String(key.dropFirst(2)) : key
            let isHex = hexKey.allSatisfy { $0.isHexDigit }
            if isHex {
                return PrivateKeyValidation(isValid: true, format: .hex, errorMessage: nil)
            }
        }
        
        // WIF format (starts with 5, K, or L for mainnet)
        if key.count >= 51 && key.count <= 52 {
            if key.hasPrefix("5") && key.count == 51 {
                // Uncompressed WIF
                return PrivateKeyValidation(isValid: true, format: .wif, errorMessage: nil)
            }
            if (key.hasPrefix("K") || key.hasPrefix("L")) && key.count == 52 {
                // Compressed WIF
                return PrivateKeyValidation(isValid: true, format: .wifCompressed, errorMessage: nil)
            }
        }
        
        return PrivateKeyValidation(isValid: false, format: nil, errorMessage: "Not a valid private key format")
    }
    
    func importFromPrivateKey() async {
        guard privateKeyValidation.isValid else {
            state = .error(.invalidPrivateKey)
            return
        }
        
        state = .importing
        progress = 0.3
        progressMessage = "Deriving address from key..."
        
        // Note: Private key import requires additional implementation
        // For now, we show a not-yet-implemented message
        
        progress = 0.6
        progressMessage = "Importing to \(selectedChain)..."
        
        // Simulate import delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        // TODO: Implement actual private key import when WalletManager supports it
        // For now, show error that this feature is coming soon
        state = .error(.derivationFailed)
        
        #if DEBUG
        print("⚠️ Private key import not yet fully implemented")
        #endif
    }
    
    // MARK: - QR Code Import
    
    func handleScannedQR(_ data: String) {
        scannedData = data
        isScanning = false
        
        // Try to parse as seed phrase
        let words = data.lowercased().components(separatedBy: CharacterSet.whitespacesAndNewlines)
        if [12, 18, 24].contains(words.count) {
            // Looks like a seed phrase
            for (index, word) in words.enumerated() where index < seedWords.count {
                seedWords[index] = word
            }
            wordCount = words.count
            selectedMethod = .seedPhrase
            return
        }
        
        // Try to parse as private key
        if data.count == 64 || data.count == 66 || data.count == 51 || data.count == 52 {
            privateKey = data
            selectedMethod = .privateKey
            return
        }
        
        // Try to parse as Hawala QR format
        if let parsed = parseHawalaQR(data) {
            switch parsed {
            case .seed(let phrase):
                for (index, word) in phrase.components(separatedBy: " ").enumerated() where index < seedWords.count {
                    seedWords[index] = word
                }
                wordCount = phrase.components(separatedBy: " ").count
                selectedMethod = .seedPhrase
            case .key(let key, let chain):
                privateKey = key
                selectedChain = chain
                selectedMethod = .privateKey
            }
            return
        }
        
        state = .error(.invalidQRCode)
    }
    
    private enum ParsedQR {
        case seed(String)
        case key(String, String)
    }
    
    private func parseHawalaQR(_ data: String) -> ParsedQR? {
        // Format: hawala://import?type=seed&data=...
        guard let url = URL(string: data),
              url.scheme == "hawala",
              url.host == "import" else {
            return nil
        }
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let type = components.queryItems?.first(where: { $0.name == "type" })?.value,
              let encodedData = components.queryItems?.first(where: { $0.name == "data" })?.value else {
            return nil
        }
        
        guard let decodedData = Data(base64Encoded: encodedData),
              let decoded = String(data: decodedData, encoding: .utf8) else {
            return nil
        }
        
        switch type {
        case "seed":
            return .seed(decoded)
        case "key":
            let chain = components.queryItems?.first(where: { $0.name == "chain" })?.value ?? "ethereum"
            return .key(decoded, chain)
        default:
            return nil
        }
    }
    
    // MARK: - iCloud Backup
    
    struct CloudBackupInfo: Identifiable {
        let id: String
        let name: String
        let date: Date
        let walletCount: Int
    }
    
    func fetchiCloudBackups() async {
        state = .validating
        progressMessage = "Checking iCloud..."
        
        // Check if iCloud backup exists
        if SecureSeedStorage.hasiCloudBackup() {
            // For now, we show a single backup option
            availableBackups = [
                CloudBackupInfo(
                    id: "main",
                    name: "Hawala Backup",
                    date: Date(),
                    walletCount: 1
                )
            ]
        } else {
            availableBackups = []
        }
        
        state = .idle
    }
    
    func importFromiCloud(backup: CloudBackupInfo, password: String) async {
        state = .importing
        progress = 0.2
        progressMessage = "Decrypting backup..."
        
        do {
            // Restore from iCloud
            let words = try SecureSeedStorage.restoreFromiCloud(password: password)
            let seed = words.joined(separator: " ")
            
            progress = 0.5
            progressMessage = "Restoring wallet..."
            
            // Restore wallet from seed
            let wallet = try await walletManager.restoreWallet(
                from: seed,
                name: walletName,
                passphrase: ""
            )
            
            progress = 1.0
            state = .success(wallet.name)
            
            // Track that user restored from cloud
            SecurityScoreManager.shared.complete(.iCloudBackupEnabled)
            
        } catch {
            if let importError = error as? ImportError {
                state = .error(importError)
            } else {
                state = .error(.iCloudDecryptionFailed)
            }
        }
    }
    
    // MARK: - Hardware Wallet
    
    struct HardwareDevice: Identifiable {
        let id: String
        let name: String
        let type: DeviceType
        let isConnected: Bool
        
        enum DeviceType {
            case ledger
            case trezor
            case keystone
        }
    }
    
    func scanForHardwareDevices() async {
        state = .validating
        progressMessage = "Scanning for devices..."
        
        // Simulate device discovery
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        
        // In production, this would use USB/Bluetooth to find devices
        detectedDevices = []
        state = .idle
        
        if detectedDevices.isEmpty {
            state = .error(.hardwareNotConnected)
        }
    }
    
    func importFromHardwareWallet(device: HardwareDevice) async {
        state = .importing
        progress = 0.2
        progressMessage = "Connecting to \(device.name)..."
        
        // This would integrate with Ledger/Trezor SDKs
        // For now, show not connected error
        state = .error(.hardwareNotConnected)
    }
    
    // MARK: - Hawala File Import
    
    func importFromHawalaFile(url: URL, password: String) async {
        state = .importing
        progress = 0.2
        progressMessage = "Reading backup file..."
        
        do {
            let data = try Data(contentsOf: url)
            
            progress = 0.4
            progressMessage = "Decrypting..."
            
            // Use HawalaFileDecoder to decrypt and parse
            guard let decoded = try? decryptHawalaFile(data, password: password) else {
                throw ImportError.fileWrongPassword
            }
            
            progress = 0.6
            progressMessage = "Restoring wallet..."
            
            let wallet = try await walletManager.restoreWallet(
                from: decoded.seed,
                name: decoded.name ?? walletName,
                passphrase: ""
            )
            
            progress = 1.0
            state = .success(wallet.name)
            
        } catch let error as ImportError {
            state = .error(error)
        } catch {
            state = .error(.fileCorrupted)
        }
    }
    
    private struct DecodedHawalaFile {
        let seed: String
        let name: String?
    }
    
    private func decryptHawalaFile(_ data: Data, password: String) throws -> DecodedHawalaFile {
        // Header check
        let header = "HAWALA_V1"
        guard data.count > header.count,
              String(data: data.prefix(header.count), encoding: .utf8) == header else {
            throw ImportError.fileCorrupted
        }
        
        let encryptedData = data.dropFirst(header.count)
        
        // Derive key from password
        let salt = Data(encryptedData.prefix(16))
        let key = deriveKey(password: password, salt: salt)
        
        // Decrypt
        let ciphertext = encryptedData.dropFirst(16)
        guard let decrypted = decrypt(data: Data(ciphertext), key: key) else {
            throw ImportError.fileWrongPassword
        }
        
        // Parse JSON
        guard let json = try? JSONSerialization.jsonObject(with: decrypted) as? [String: Any],
              let seed = json["seed"] as? String else {
            throw ImportError.fileCorrupted
        }
        
        let name = json["name"] as? String
        return DecodedHawalaFile(seed: seed, name: name)
    }
    
    private func deriveKey(password: String, salt: Data) -> SymmetricKey {
        let passwordData = password.data(using: .utf8)!
        var key = Data(count: 32)
        key.withUnsafeMutableBytes { keyPtr in
            salt.withUnsafeBytes { saltPtr in
                passwordData.withUnsafeBytes { passPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passPtr.baseAddress, passwordData.count,
                        saltPtr.baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        100_000,
                        keyPtr.baseAddress, 32
                    )
                }
            }
        }
        return SymmetricKey(data: key)
    }
    
    private func decrypt(data: Data, key: SymmetricKey) -> Data? {
        guard data.count > 12 else { return nil }
        let nonce = data.prefix(12)
        let ciphertext = data.dropFirst(12)
        
        do {
            let sealedBox = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: ciphertext.dropLast(16), tag: ciphertext.suffix(16))
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            return nil
        }
    }
}

// MARK: - CCKeyDerivationPBKDF import

import CommonCrypto
