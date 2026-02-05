import SwiftUI

/// ViewModel handling wallet key generation, storage, import/export
@MainActor
final class WalletViewModel: ObservableObject {
    // MARK: - Published State
    @Published var keys: AllKeys?
    @Published var rawJSON: String = ""
    @Published var isGenerating = false
    @Published var errorMessage: String?
    
    // MARK: - Status Messages
    @Published var statusMessage: String?
    @Published var statusColor: Color = .green
    private var statusTask: Task<Void, Never>?
    
    // MARK: - Import/Export State
    @Published var pendingImportData: Data?
    
    // MARK: - Constants
    private let sendEnabledChainIDs: Set<String> = [
        "bitcoin", "bitcoin-testnet", "litecoin", "ethereum", "ethereum-sepolia", "bnb", "solana"
    ]
    
    // MARK: - Computed Properties
    var hasKeys: Bool {
        keys != nil
    }
    
    var chainInfos: [ChainInfo] {
        keys?.chainInfos ?? []
    }
    
    // MARK: - Key Generation
    func generateKeys() async {
        guard !isGenerating else { return }
        isGenerating = true
        errorMessage = nil
        
        do {
            let (generatedKeys, json) = try await runRustKeyGenerator()
            keys = generatedKeys
            rawJSON = prettyPrintedJSON(from: json.data(using: .utf8) ?? Data())
            
            // Save to Keychain
            try KeychainHelper.saveKeys(generatedKeys)
            
            showStatus("Keys generated successfully", tone: .success)
            
            #if DEBUG
            print("✅ Generated and saved keys to Keychain")
            #endif
        } catch {
            errorMessage = error.localizedDescription
            showStatus("Key generation failed: \(error.localizedDescription)", tone: .error)
            
            #if DEBUG
            print("❌ Key generation failed: \(error)")
            #endif
        }
        
        isGenerating = false
    }
    
    // MARK: - Load from Keychain
    func loadKeysFromKeychain() async {
        guard keys == nil else {
            #if DEBUG
            print("ℹ️ Keys already loaded, skipping Keychain load")
            #endif
            return
        }
        
        do {
            if let loadedKeys = try KeychainHelper.loadKeys() {
                keys = loadedKeys
                if let encoded = try? JSONEncoder().encode(loadedKeys) {
                    rawJSON = prettyPrintedJSON(from: encoded)
                }
                
                #if DEBUG
                print("✅ Loaded keys from Keychain")
                print("🔑 Bitcoin Testnet Address: \(loadedKeys.bitcoinTestnet.address)")
                #endif
            } else {
                #if DEBUG
                print("ℹ️ No keys found in Keychain")
                #endif
            }
        } catch {
            #if DEBUG
            print("⚠️ Failed to load keys from Keychain: \(error)")
            #endif
        }
    }
    
    // MARK: - Chain Helpers
    func sendEligibleChains() -> [ChainInfo] {
        chainInfos.filter { chain in
            isSendSupported(chainID: chain.id)
        }
    }
    
    func isSendSupported(chainID: String) -> Bool {
        if sendEnabledChainIDs.contains(chainID) { return true }
        if chainID.contains("erc20") { return true }
        return false
    }
    
    // MARK: - Export
    func performEncryptedExport(with password: String, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let keys = keys else {
            completion(.failure(WalletViewModelError.noKeys))
            return
        }
        
        do {
            let archive = try buildEncryptedArchive(from: keys, password: password)
            completion(.success(archive))
        } catch {
            completion(.failure(error))
        }
    }
    
    func defaultExportFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "hawala-backup-\(formatter.string(from: Date())).hawala"
    }
    
    // MARK: - Import
    func beginEncryptedImport(from url: URL) -> Data? {
        do {
            let data = try Data(contentsOf: url)
            return data
        } catch {
            showStatus("Failed to read backup file: \(error.localizedDescription)", tone: .error)
            return nil
        }
    }
    
    func finalizeEncryptedImport(data: Data, password: String) async throws {
        // Decrypt and validate the archive
        let importedKeys = try decryptArchive(data: data, password: password)
        
        // Save to keychain
        try KeychainHelper.saveKeys(importedKeys)
        
        // Update state
        keys = importedKeys
        if let encoded = try? JSONEncoder().encode(importedKeys) {
            rawJSON = prettyPrintedJSON(from: encoded)
        }
        
        showStatus("Wallet restored successfully", tone: .success)
    }
    
    // MARK: - Clear Data
    func clearSensitiveData() {
        keys = nil
        rawJSON = ""
        statusTask?.cancel()
        statusTask = nil
        statusMessage = nil
        errorMessage = nil
        pendingImportData = nil
        
        do {
            try KeychainHelper.deleteKeys()
            #if DEBUG
            print("✅ Keys deleted from Keychain")
            #endif
        } catch {
            #if DEBUG
            print("⚠️ Failed to delete keys from Keychain: \(error)")
            #endif
        }
    }
    
    // MARK: - Status Messages
    func showStatus(_ message: String, tone: StatusTone, autoClear: Bool = true) {
        statusTask?.cancel()
        statusTask = nil
        statusColor = tone.color
        statusMessage = message
        
        guard autoClear else { return }
        
        statusTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                statusMessage = nil
                statusTask = nil
            }
        }
    }
    
    // MARK: - Private Helpers
    private func runRustKeyGenerator() async throws -> (AllKeys, String) {
        return try await Task.detached {
            let jsonString = RustService.shared.generateKeys()
            
            guard let jsonData = jsonString.data(using: .utf8) else {
                throw KeyGeneratorError.executionFailed("Invalid UTF-8 output from generator")
            }
            
            // Check for API response format
            if let apiResponse = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let success = apiResponse["success"] as? Bool {
                if !success {
                    if let error = apiResponse["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        throw KeyGeneratorError.executionFailed(message)
                    }
                    throw KeyGeneratorError.executionFailed("Key generation failed")
                }
                if let dataObj = apiResponse["data"],
                   let dataJson = try? JSONSerialization.data(withJSONObject: dataObj) {
                    let decoder = JSONDecoder()
                    let response = try decoder.decode(WalletResponse.self, from: dataJson)
                    let formattedJson = String(data: dataJson, encoding: .utf8) ?? jsonString
                    return (response.keys, formattedJson)
                }
            }
            
            let decoder = JSONDecoder()
            let response = try decoder.decode(WalletResponse.self, from: jsonData)
            return (response.keys, jsonString)
        }.value
    }
    
    private func prettyPrintedJSON(from data: Data) -> String {
        guard
            let jsonObject = try? JSONSerialization.jsonObject(with: data),
            let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
            let prettyString = String(data: prettyData, encoding: .utf8)
        else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        return prettyString
    }
    
    private func buildEncryptedArchive(from keys: AllKeys, password: String) throws -> Data {
        // Encode keys to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let keysData = try encoder.encode(keys)
        
        // Create encrypted archive using EncryptedFileStorage
        let archive = try EncryptedFileStorage.encrypt(keysData, password: password)
        return archive
    }
    
    private func decryptArchive(data: Data, password: String) throws -> AllKeys {
        // Decrypt using EncryptedFileStorage
        let decryptedData = try EncryptedFileStorage.decrypt(data, password: password)
        
        // Decode keys
        let decoder = JSONDecoder()
        let keys = try decoder.decode(AllKeys.self, from: decryptedData)
        return keys
    }
}

// MARK: - Supporting Types
enum StatusTone {
    case success
    case info
    case error
    
    var color: Color {
        switch self {
        case .success: return .green
        case .info: return .blue
        case .error: return .red
        }
    }
}

enum WalletViewModelError: LocalizedError {
    case noKeys
    case importFailed(String)
    case exportFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noKeys:
            return "No wallet keys available"
        case .importFailed(let message):
            return "Import failed: \(message)"
        case .exportFailed(let message):
            return "Export failed: \(message)"
        }
    }
}
