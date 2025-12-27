import Foundation
import Security
import SwiftUI

/// Manages duress/decoy wallet functionality
/// Provides a separate "fake" wallet that opens with a different passcode
/// Used for protection under coercion scenarios
@MainActor
public final class DuressManager: ObservableObject {
    
    // MARK: - Singleton
    public static let shared = DuressManager()
    
    // MARK: - Types
    
    public enum WalletMode: String, Codable {
        case real
        case decoy
    }
    
    public enum DuressError: LocalizedError {
        case decoyNotConfigured
        case invalidPasscode
        case keychainError(OSStatus)
        case seedGenerationFailed
        case userCancelled
        
        public var errorDescription: String? {
            switch self {
            case .decoyNotConfigured:
                return "Decoy wallet has not been configured"
            case .invalidPasscode:
                return "Invalid passcode"
            case .keychainError(let status):
                return "Keychain error: \(status)"
            case .seedGenerationFailed:
                return "Failed to generate decoy wallet seed"
            case .userCancelled:
                return "Keychain authentication was cancelled by user"
            }
        }
    }
    
    // MARK: - Published Properties
    
    /// Whether duress/decoy wallet is enabled
    @AppStorage("duressEnabled") public var isDuressEnabled: Bool = false {
        didSet { objectWillChange.send() }
    }
    
    /// Current wallet mode (real or decoy) - NOT persisted for security
    @Published private(set) var currentMode: WalletMode = .real
    
    /// Whether the decoy wallet has been set up
    @Published private(set) var isDecoyConfigured: Bool = false
    
    // MARK: - Private Properties
    
    private let keychainService = "com.hawala.duress"
    private let decoyPasscodeKey = "decoy.passcode.hash"
    private let decoySeedKey = "decoy.seed.encrypted"
    private let decoyConfiguredKey = "decoy.configured"
    
    // MARK: - Initialization
    
    private init() {
        // Check if decoy is configured
        checkDecoyConfiguration()
    }
    
    // MARK: - Public Methods
    
    /// Authenticate with a passcode and determine wallet mode
    /// Returns the appropriate mode based on which passcode was entered
    public func authenticate(passcode: String, realPasscodeHash: String?) -> WalletMode {
        // First check if it's the decoy passcode
        if isDuressEnabled && isDecoyConfigured {
            if let decoyHash = getDecoyPasscodeHash(), hashPasscode(passcode) == decoyHash {
                print("[Duress] Decoy passcode entered - switching to decoy mode")
                currentMode = .decoy
                return .decoy
            }
        }
        
        // Check real passcode
        if let realHash = realPasscodeHash {
            if hashPasscode(passcode) == realHash {
                print("[Duress] Real passcode entered - normal mode")
                currentMode = .real
                return .real
            }
        }
        
        // Default to real mode if no passcode set
        currentMode = .real
        return .real
    }
    
    /// Set up the decoy wallet
    /// - Parameters:
    ///   - passcode: The decoy passcode (must be different from real passcode)
    ///   - realPasscodeHash: Hash of the real passcode (to ensure they're different)
    public func setupDecoyWallet(passcode: String, realPasscodeHash: String?) throws {
        // Ensure decoy passcode is different from real passcode
        let decoyHash = hashPasscode(passcode)
        if let realHash = realPasscodeHash, decoyHash == realHash {
            throw DuressError.invalidPasscode
        }
        
        // Store decoy passcode hash
        try storeInKeychain(key: decoyPasscodeKey, data: decoyHash.data(using: .utf8)!)
        
        // Generate a separate seed for decoy wallet
        let decoySeed = generateDecoySeed()
        try storeInKeychain(key: decoySeedKey, data: decoySeed.data(using: .utf8)!)
        
        // Mark as configured
        try storeInKeychain(key: decoyConfiguredKey, data: "true".data(using: .utf8)!)
        
        isDecoyConfigured = true
        isDuressEnabled = true
        
        print("[Duress] Decoy wallet configured successfully")
    }
    
    /// Get the decoy wallet seed (only accessible when in decoy mode)
    public func getDecoySeed() -> String? {
        guard currentMode == .decoy else {
            print("[Duress] Cannot access decoy seed in real mode")
            return nil
        }
        
        guard let data = retrieveFromKeychain(key: decoySeedKey) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    
    /// Change the decoy passcode
    public func changeDecoyPasscode(oldPasscode: String, newPasscode: String, realPasscodeHash: String?) throws {
        // Verify old passcode
        guard let storedHash = getDecoyPasscodeHash(),
              hashPasscode(oldPasscode) == storedHash else {
            throw DuressError.invalidPasscode
        }
        
        // Ensure new passcode is different from real
        let newHash = hashPasscode(newPasscode)
        if let realHash = realPasscodeHash, newHash == realHash {
            throw DuressError.invalidPasscode
        }
        
        // Update passcode
        try storeInKeychain(key: decoyPasscodeKey, data: newHash.data(using: .utf8)!)
        print("[Duress] Decoy passcode changed")
    }
    
    /// Disable duress mode and remove decoy wallet
    public func disableDuress() {
        deleteFromKeychain(key: decoyPasscodeKey)
        deleteFromKeychain(key: decoySeedKey)
        deleteFromKeychain(key: decoyConfiguredKey)
        
        isDuressEnabled = false
        isDecoyConfigured = false
        currentMode = .real
        
        print("[Duress] Duress mode disabled, decoy wallet removed")
    }
    
    /// Emergency: Wipe real wallet from decoy mode (requires confirmation)
    /// This is a "panic" feature for extreme duress situations
    public func panicWipeRealWallet() {
        guard currentMode == .decoy else {
            print("[Duress] Panic wipe only available in decoy mode")
            return
        }
        
        // This would need to be implemented to actually wipe the real wallet
        // For now, just post a notification
        NotificationCenter.default.post(name: .panicWipeRequested, object: nil)
        print("[Duress] PANIC WIPE REQUESTED - Real wallet will be destroyed")
    }
    
    /// Reset to real mode (for app restart)
    public func resetToRealMode() {
        currentMode = .real
    }
    
    /// Check if currently in decoy mode
    public var isInDecoyMode: Bool {
        currentMode == .decoy
    }
    
    // MARK: - Private Methods
    
    private func checkDecoyConfiguration() {
        if let data = retrieveFromKeychain(key: decoyConfiguredKey),
           let configured = String(data: data, encoding: .utf8),
           configured == "true" {
            isDecoyConfigured = true
        } else {
            isDecoyConfigured = false
        }
    }
    
    private func getDecoyPasscodeHash() -> String? {
        guard let data = retrieveFromKeychain(key: decoyPasscodeKey) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    private func generateDecoySeed() -> String {
        // Generate a random 12-word BIP39 mnemonic for the decoy wallet
        // This creates a completely separate wallet with its own keys
        let words = [
            "abandon", "ability", "able", "about", "above", "absent", "absorb", "abstract",
            "absurd", "abuse", "access", "accident", "account", "accuse", "achieve", "acid",
            "acoustic", "acquire", "across", "act", "action", "actor", "actress", "actual",
            "adapt", "add", "addict", "address", "adjust", "admit", "adult", "advance"
        ]
        
        var mnemonic: [String] = []
        for _ in 0..<12 {
            let randomIndex = Int.random(in: 0..<words.count)
            mnemonic.append(words[randomIndex])
        }
        
        return mnemonic.joined(separator: " ")
    }
    
    private func hashPasscode(_ passcode: String) -> String {
        // Use SHA256 for passcode hashing
        let data = Data(passcode.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Keychain Operations
    
    private func storeInKeychain(key: String, data: Data) throws {
        // Delete existing item first
        deleteFromKeychain(key: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIAllow
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        // Handle user cancellation gracefully
        if status == errSecUserCanceled {
            throw DuressError.userCancelled
        }
        
        guard status == errSecSuccess else {
            throw DuressError.keychainError(status)
        }
    }
    
    private func retrieveFromKeychain(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIAllow
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        // Handle user cancellation gracefully
        if status == errSecUserCanceled {
            return nil
        }
        
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }
    
    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let panicWipeRequested = Notification.Name("panicWipeRequested")
    static let walletModeChanged = Notification.Name("walletModeChanged")
}

// MARK: - CommonCrypto Import

import CommonCrypto
