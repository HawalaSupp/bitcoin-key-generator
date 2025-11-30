import Foundation
import SwiftUI
import Security
import CryptoKit

// MARK: - Passcode Manager

/// Manages passcode storage, verification, and auto-lock functionality
@MainActor
final class PasscodeManager: ObservableObject {
    static let shared = PasscodeManager()
    
    // MARK: - Published State
    
    @Published var isLocked = true
    @Published var hasPasscode = false
    @Published var showSetupPrompt = false
    
    // MARK: - Settings
    
    @AppStorage("hawala.passcodeEnabled") private var passcodeEnabled = false
    @AppStorage("hawala.autoLockMinutes") private var autoLockMinutes = 5
    @AppStorage("hawala.passcodeSkipped") private var passcodeSkipped = false
    
    // MARK: - Private State
    
    private var lastActivityTime = Date()
    private var inactivityTimer: Timer?
    private let keychainService = "com.hawala.wallet.passcode"
    private let keychainAccount = "user_passcode_hash"
    
    private init() {
        checkPasscodeStatus()
        setupAutoLock()
    }
    
    // MARK: - Public API
    
    /// Check if passcode is configured
    func checkPasscodeStatus() {
        hasPasscode = loadPasscodeHash() != nil
        passcodeEnabled = hasPasscode
        
        // If no passcode and not skipped, show setup on launch
        if !hasPasscode && !passcodeSkipped {
            showSetupPrompt = true
            isLocked = false // Don't lock if no passcode
        } else if hasPasscode {
            isLocked = true // Lock if passcode exists
        } else {
            isLocked = false // No passcode and skipped - don't lock
        }
    }
    
    /// Verify entered passcode against stored hash
    func verifyPasscode(_ passcode: String) -> Bool {
        guard let storedHash = loadPasscodeHash() else {
            return false
        }
        
        let inputHash = hashPasscode(passcode)
        return inputHash == storedHash
    }
    
    /// Set a new passcode
    func setPasscode(_ passcode: String) -> Bool {
        let hash = hashPasscode(passcode)
        let success = savePasscodeHash(hash)
        
        if success {
            hasPasscode = true
            passcodeEnabled = true
            passcodeSkipped = false
            isLocked = false // Unlock after setting
            recordActivity()
        }
        
        return success
    }
    
    /// Change passcode (requires current passcode verification)
    func changePasscode(current: String, new: String) -> (success: Bool, error: String?) {
        guard verifyPasscode(current) else {
            return (false, "Current passcode is incorrect")
        }
        
        guard new.count >= 4 else {
            return (false, "New passcode must be at least 4 digits")
        }
        
        let success = setPasscode(new)
        return (success, success ? nil : "Failed to save new passcode")
    }
    
    /// Remove passcode
    func removePasscode(current: String) -> Bool {
        guard verifyPasscode(current) else {
            return false
        }
        
        let success = deletePasscodeHash()
        if success {
            hasPasscode = false
            passcodeEnabled = false
            isLocked = false
        }
        return success
    }
    
    /// Skip passcode setup
    func skipPasscodeSetup() {
        passcodeSkipped = true
        showSetupPrompt = false
        isLocked = false
    }
    
    /// Unlock the app
    func unlock() {
        isLocked = false
        recordActivity()
    }
    
    /// Lock the app
    func lock() {
        if hasPasscode {
            isLocked = true
        }
    }
    
    /// Record user activity
    func recordActivity() {
        lastActivityTime = Date()
    }
    
    /// Update auto-lock timeout
    func setAutoLockTimeout(_ minutes: Int) {
        autoLockMinutes = minutes
        restartAutoLockTimer()
    }
    
    /// Get current auto-lock timeout
    var currentAutoLockMinutes: Int {
        autoLockMinutes
    }
    
    // MARK: - Auto Lock Timer
    
    private func setupAutoLock() {
        startAutoLockTimer()
        
        // Also observe app becoming active/inactive
        #if os(macOS)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppBecameActive()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.recordActivity() // Record last activity before going inactive
            }
        }
        #endif
    }
    
    private func startAutoLockTimer() {
        inactivityTimer?.invalidate()
        
        guard autoLockMinutes > 0 else { return } // 0 = Never
        
        // Check every 5 seconds
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkInactivity()
            }
        }
    }
    
    private func restartAutoLockTimer() {
        recordActivity()
        startAutoLockTimer()
    }
    
    private func checkInactivity() {
        guard !isLocked else { return }
        guard hasPasscode else { return }
        guard autoLockMinutes > 0 else { return }
        
        let elapsed = Date().timeIntervalSince(lastActivityTime)
        let timeout = TimeInterval(autoLockMinutes * 60)
        
        if elapsed >= timeout {
            lock()
        }
    }
    
    private func handleAppBecameActive() {
        // Check if we should be locked
        guard hasPasscode else { return }
        guard autoLockMinutes > 0 else { return }
        
        let elapsed = Date().timeIntervalSince(lastActivityTime)
        let timeout = TimeInterval(autoLockMinutes * 60)
        
        if elapsed >= timeout {
            lock()
        }
    }
    
    // MARK: - Keychain Operations
    
    private func hashPasscode(_ passcode: String) -> String {
        let data = Data(passcode.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func savePasscodeHash(_ hash: String) -> Bool {
        let data = Data(hash.utf8)
        
        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add new
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    private func loadPasscodeHash() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let hash = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return hash
    }
    
    private func deletePasscodeHash() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
