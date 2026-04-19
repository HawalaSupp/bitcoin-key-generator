import Foundation
import Security

// MARK: - Multi-Wallet Keychain Helper (ROADMAP-21 E11)
/// Per-wallet key storage using namespaced Keychain entries.
/// Each wallet gets its own `AllKeys` blob stored under a wallet-scoped identifier.
enum MultiWalletKeychainHelper {
    
    /// Keychain service prefix for wallet-scoped keys
    private static let servicePrefix = "com.hawala.wallet.keys."
    
    /// Legacy single-wallet identifier (for migration)
    private static let legacyIdentifier = KeychainHelper.keysIdentifier
    
    // MARK: - Per-Wallet Key Storage
    
    /// Save keys for a specific wallet
    static func saveKeys(_ keys: AllKeys, for walletId: UUID) throws {
        let data = try JSONEncoder().encode(keys)
        let identifier = servicePrefix + walletId.uuidString
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identifier,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
        
        #if DEBUG
        print("🔐 Saved keys for wallet \(walletId.uuidString.prefix(8))")
        #endif
    }
    
    /// Load keys for a specific wallet
    static func loadKeys(for walletId: UUID) -> AllKeys? {
        let identifier = servicePrefix + walletId.uuidString
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identifier,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound || status == errSecUserCanceled {
            return nil
        }
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let keys = try? JSONDecoder().decode(AllKeys.self, from: data) else {
            return nil
        }
        
        return keys
    }
    
    /// Delete keys for a specific wallet
    static func deleteKeys(for walletId: UUID) {
        let identifier = servicePrefix + walletId.uuidString
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identifier
        ]
        
        SecItemDelete(query as CFDictionary)
        
        #if DEBUG
        print("🗑️ Deleted keys for wallet \(walletId.uuidString.prefix(8))")
        #endif
    }
    
    /// Check if keys exist for a wallet (without loading them)
    static func hasKeys(for walletId: UUID) -> Bool {
        let identifier = servicePrefix + walletId.uuidString
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identifier,
            kSecReturnData as String: false
        ]
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    // MARK: - Migration
    
    /// Migrate the legacy single-wallet keys to a specific wallet ID.
    /// This copies (not moves) the legacy keys to the new wallet-scoped entry.
    static func migrateFromLegacy(to walletId: UUID) -> Bool {
        // Load from legacy
        guard let legacyKeys = try? KeychainHelper.loadKeys() else {
            return false
        }
        
        // Save to new wallet-scoped entry
        do {
            try saveKeys(legacyKeys, for: walletId)
            #if DEBUG
            print("🔄 Migrated legacy keys to wallet \(walletId.uuidString.prefix(8))")
            #endif
            return true
        } catch {
            #if DEBUG
            print("❌ Failed to migrate legacy keys: \(error)")
            #endif
            return false
        }
    }
    
    // MARK: - Aggregate
    
    /// Load keys from all wallets that have stored keys
    static func loadAllWalletKeys(walletIds: [UUID]) -> [(UUID, AllKeys)] {
        var results: [(UUID, AllKeys)] = []
        for id in walletIds {
            if let keys = loadKeys(for: id) {
                results.append((id, keys))
            }
        }
        return results
    }
}
