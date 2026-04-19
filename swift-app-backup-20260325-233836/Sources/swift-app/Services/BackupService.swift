import Foundation
import CryptoKit
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

/// Service responsible for encrypted wallet backup export and import
/// Extracted from ContentView to improve separation of concerns
@MainActor
final class BackupService: ObservableObject {
    // MARK: - Singleton
    static let shared = BackupService()
    private init() {}

    // MARK: - Status Callback
    /// Called when the service needs to display a status message.
    /// Parameters: (message: String, tone: StatusTone, autoClear: Bool)
    var onStatus: ((String, StatusTone, Bool) -> Void)?

    // MARK: - Encrypted Export

    func performEncryptedExport(keys: AllKeys?) {
        guard let keys else {
            onStatus?("Nothing to export yet.", .info, true)
            return
        }

        do {
            let archive = try buildEncryptedArchive(from: keys, password: "")
            // This is a placeholder – the real flow prompts for a password first
            // and the caller passes it through `performEncryptedExport(keys:password:)`
            _ = archive
        } catch {
            onStatus?("Export failed: \(error.localizedDescription)", .error, false)
        }
    }

    func performEncryptedExport(keys: AllKeys?, password: String) {
        guard let keys else {
            onStatus?("Nothing to export yet.", .info, true)
            return
        }

        do {
            let archive = try buildEncryptedArchive(from: keys, password: password)
#if canImport(AppKit)
            DispatchQueue.main.async { [self] in
                let panel = NSSavePanel()
                var contentTypes: [UTType] = [.json]
                let customTypes = ["hawala", "hawbackup"].compactMap { UTType(filenameExtension: $0) }
                contentTypes.append(contentsOf: customTypes)
                panel.allowedContentTypes = contentTypes
                panel.nameFieldStringValue = defaultExportFileName()
                panel.title = "Save Encrypted Hawala Backup"
                panel.canCreateDirectories = true

                panel.begin { response in
                    if response == .OK, let url = panel.url {
                        do {
                            try archive.write(to: url)
                            self.onStatus?("Encrypted backup saved to \(url.lastPathComponent)", .success, true)
                        } catch {
                            self.onStatus?("Failed to write file: \(error.localizedDescription)", .error, false)
                        }
                    }
                }
            }
#else
            onStatus?("Encrypted export is only supported on macOS.", .error, false)
#endif
        } catch {
            onStatus?("Export failed: \(error.localizedDescription)", .error, false)
        }
    }

    // MARK: - Encrypted Import

    /// Opens a file picker and returns the selected backup data, or nil if cancelled.
    func beginEncryptedImport(completion: @escaping (Data?) -> Void) {
#if canImport(AppKit)
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            var contentTypes: [UTType] = [.json]
            let customTypes = ["hawala", "hawbackup"].compactMap { UTType(filenameExtension: $0) }
            contentTypes.append(contentsOf: customTypes)
            panel.allowedContentTypes = contentTypes
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.title = "Open Encrypted Hawala Backup"

            panel.begin { response in
                if response == .OK, let url = panel.url {
                    do {
                        let data = try Data(contentsOf: url)
                        completion(data)
                    } catch {
                        self.onStatus?("Failed to read file: \(error.localizedDescription)", .error, false)
                        completion(nil)
                    }
                } else {
                    completion(nil)
                }
            }
        }
#else
        onStatus?("Encrypted import is only supported on macOS.", .error, false)
        completion(nil)
#endif
    }

    /// Decrypts an encrypted archive and returns decoded AllKeys.
    func decryptAndDecode(archiveData: Data, password: String) throws -> AllKeys {
        let plaintext = try decryptArchive(archiveData, password: password)
        let decoder = JSONDecoder()
        return try decoder.decode(AllKeys.self, from: plaintext)
    }

    /// Returns the pretty-printed JSON string for decrypted archive data.
    func decryptToJSON(archiveData: Data, password: String) throws -> String {
        let plaintext = try decryptArchive(archiveData, password: password)
        return prettyPrintedJSON(from: plaintext)
    }

    // MARK: - Encryption Primitives

    func buildEncryptedArchive(from keys: AllKeys, password: String) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let plaintext = try encoder.encode(keys)
        let envelope = try encryptPayload(plaintext, password: password)
        let archiveEncoder = JSONEncoder()
        archiveEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        archiveEncoder.dateEncodingStrategy = .iso8601
        return try archiveEncoder.encode(envelope)
    }

    func decryptArchive(_ data: Data, password: String) throws -> Data {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(EncryptedPackage.self, from: data)
        return try decryptPayload(envelope, password: password)
    }

    func encryptPayload(_ plaintext: Data, password: String) throws -> EncryptedPackage {
        let salt = randomData(count: 16)
        let key = deriveSymmetricKey(password: password, salt: salt)
        let nonce = try AES.GCM.Nonce(data: randomData(count: 12))
        let sealedBox = try AES.GCM.seal(plaintext, using: key, nonce: nonce)

        return EncryptedPackage(
            formatVersion: 1,
            createdAt: Date(),
            salt: salt.base64EncodedString(),
            nonce: Data(nonce).base64EncodedString(),
            ciphertext: sealedBox.ciphertext.base64EncodedString(),
            tag: sealedBox.tag.base64EncodedString()
        )
    }

    func decryptPayload(_ envelope: EncryptedPackage, password: String) throws -> Data {
        guard
            let salt = Data(base64Encoded: envelope.salt),
            let nonceData = Data(base64Encoded: envelope.nonce),
            let ciphertext = Data(base64Encoded: envelope.ciphertext),
            let tag = Data(base64Encoded: envelope.tag)
        else {
            throw SecureArchiveError.invalidEnvelope
        }

        let key = deriveSymmetricKey(password: password, salt: salt)
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        return try AES.GCM.open(sealedBox, using: key)
    }

    func deriveSymmetricKey(password: String, salt: Data) -> SymmetricKey {
        let passwordKey = SymmetricKey(data: Data(password.utf8))
        return HKDF<CryptoKit.SHA256>.deriveKey(
            inputKeyMaterial: passwordKey,
            salt: salt,
            info: Data("hawala-key-backup".utf8),
            outputByteCount: 32
        )
    }

    func randomData(count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: 0...255) })
    }

    // MARK: - Helpers

    func defaultExportFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "hawala-backup-\(formatter.string(from: Date())).hawala"
    }

    func prettyPrintedJSON(from data: Data) -> String {
        guard
            let jsonObject = try? JSONSerialization.jsonObject(with: data),
            let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
            let prettyString = String(data: prettyData, encoding: .utf8)
        else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        return prettyString
    }
}
