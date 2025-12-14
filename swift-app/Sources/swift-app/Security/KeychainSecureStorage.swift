import Foundation
import Security
import LocalAuthentication

// MARK: - Keychain Secure Storage

/// Production-ready secure storage using macOS Keychain.
/// - Stores data with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
/// - Supports biometric authentication via LocalAuthentication
/// - Data is encrypted by the Keychain automatically
final class KeychainSecureStorage: SecureStorageProtocol, @unchecked Sendable {
    
    /// Service identifier for Keychain items
    private let service: String
    
    /// Access group for sharing between app extensions (nil = no sharing)
    private let accessGroup: String?
    
    init(service: String = "com.hawala.wallet", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }
    
    // MARK: - SecureStorageProtocol Implementation
    
    func save(_ data: Data, forKey key: String, requireBiometric: Bool) async throws {
        // First delete any existing item
        try? await delete(forKey: key)
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        // Add access group if specified
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        // Set accessibility and authentication requirements
        if requireBiometric {
            // Require biometric or passcode each time
            let access = SecAccessControlCreateWithFlags(
                kCFAllocatorDefault,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .userPresence,
                nil
            )
            query[kSecAttrAccessControl as String] = access as Any
        } else {
            // Accessible when device is unlocked, not backed up to iCloud
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw SecureStorageError.keychainError(status)
        }
    }
    
    func load(forKey key: String) async throws -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw SecureStorageError.dataCorrupted
            }
            return data
            
        case errSecItemNotFound:
            return nil
            
        case errSecUserCanceled, errSecAuthFailed:
            throw SecureStorageError.biometricFailed
            
        case errSecInteractionNotAllowed:
            throw SecureStorageError.accessDenied
            
        default:
            throw SecureStorageError.keychainError(status)
        }
    }
    
    func delete(forKey key: String) async throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStorageError.keychainError(status)
        }
    }
    
    func exists(forKey key: String) async -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: false
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    func deleteAll() async throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStorageError.keychainError(status)
        }
    }
    
    // MARK: - Biometric Availability
    
    /// Check if biometric authentication is available
    static func isBiometricAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    /// Get the type of biometric available
    static var biometricType: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }
}

// MARK: - Keychain Secure Storage Singleton

extension KeychainSecureStorage {
    /// Shared instance for wallet secrets
    static let shared = KeychainSecureStorage()
    
    /// Instance for high-security items requiring biometric
    static let biometric = KeychainSecureStorage(service: "com.hawala.wallet.biometric")
}
