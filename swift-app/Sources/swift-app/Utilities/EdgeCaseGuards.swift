import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - ROADMAP-19: QA & Edge Case Guards

/// Centralized edge-case guard utilities for hardening across flows.
enum EdgeCaseGuards {
    
    // MARK: - #5: Key Generation State Persistence
    
    private static let keygenInProgressKey = "hawala.keygen.inProgress"
    private static let keygenTimestampKey = "hawala.keygen.timestamp"
    
    /// Mark that key generation has started (persists across crashes).
    static func markKeyGenerationStarted() {
        UserDefaults.standard.set(true, forKey: keygenInProgressKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: keygenTimestampKey)
    }
    
    /// Mark that key generation completed (success or handled failure).
    static func markKeyGenerationFinished() {
        UserDefaults.standard.removeObject(forKey: keygenInProgressKey)
        UserDefaults.standard.removeObject(forKey: keygenTimestampKey)
    }
    
    /// Returns true if a previous key generation was interrupted (e.g. crash/kill).
    static var wasKeyGenerationInterrupted: Bool {
        guard UserDefaults.standard.bool(forKey: keygenInProgressKey) else { return false }
        // If the flag is still set, keygen was interrupted
        // Safety: if it's been > 5 minutes, treat as stale
        let ts = UserDefaults.standard.double(forKey: keygenTimestampKey)
        guard ts > 0 else { return true }
        let elapsed = Date().timeIntervalSince1970 - ts
        return elapsed < 300 // 5 minutes
    }
    
    // MARK: - #9: Locale-Aware Amount Parsing
    
    /// Normalises a user-typed amount string into a machine-parseable decimal string.
    /// Handles both comma and dot decimal separators based on the user's locale.
    static func normaliseAmountInput(_ raw: String, locale: Locale = .current) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        
        // Determine the user's decimal separator
        let decimalSep = locale.decimalSeparator ?? "."
        
        // Replace locale-specific decimal separator with canonical "."
        if decimalSep == "," {
            // European style: 1.000,50 → 1000.50
            var cleaned = trimmed.replacingOccurrences(of: ".", with: "")  // remove grouping
            cleaned = cleaned.replacingOccurrences(of: ",", with: ".")    // decimal comma → dot
            return cleaned
        } else {
            // US/UK style: 1,000.50 → 1000.50
            return trimmed.replacingOccurrences(of: ",", with: "")  // remove grouping
        }
    }
    
    // MARK: - #12: Price Feed $0 Guard
    
    /// Returns true if a price is valid for display/conversion (> 0).
    static func isPriceValid(_ price: Double) -> Bool {
        price.isFinite && price > 0
    }
    
    /// Returns true if a price is valid for display/conversion (Decimal > 0).
    static func isPriceValid(_ price: Decimal) -> Bool {
        price > .zero && !price.isNaN
    }
    
    // MARK: - #18: Network Switch During Send Guard
    
    /// Returns true if the chain can be changed right now.
    /// Should return false while a transaction is in-flight.
    static func canSwitchNetwork(isTransactionInFlight: Bool) -> Bool {
        !isTransactionInFlight
    }
    
    // MARK: - #30: Repeated Send Detection
    
    private static let recentSendsKey = "hawala.recentSends"
    private static let recentSendWindowSeconds: TimeInterval = 120 // 2 minutes
    
    /// Record a send to the given address on the given chain.
    static func recordSend(to address: String, chain: String) {
        var recents = loadRecentSends()
        recents.append(RecentSend(address: address, chain: chain, timestamp: Date().timeIntervalSince1970))
        // Keep only last 20
        if recents.count > 20 { recents = Array(recents.suffix(20)) }
        saveRecentSends(recents)
    }
    
    /// Check if a send to this address+chain was recently made.
    /// Returns true if a duplicate is detected within the time window.
    static func isDuplicateSend(to address: String, chain: String) -> Bool {
        let recents = loadRecentSends()
        let cutoff = Date().timeIntervalSince1970 - recentSendWindowSeconds
        return recents.contains { $0.address == address && $0.chain == chain && $0.timestamp > cutoff }
    }
    
    private struct RecentSend: Codable {
        let address: String
        let chain: String
        let timestamp: TimeInterval
    }
    
    private static func loadRecentSends() -> [RecentSend] {
        guard let data = UserDefaults.standard.data(forKey: recentSendsKey) else { return [] }
        return (try? JSONDecoder().decode([RecentSend].self, from: data)) ?? []
    }
    
    private static func saveRecentSends(_ sends: [RecentSend]) {
        if let data = try? JSONEncoder().encode(sends) {
            UserDefaults.standard.set(data, forKey: recentSendsKey)
        }
    }
    
    // MARK: - #44: Remote / Factory Wipe
    
    /// Performs a complete factory wipe — deletes all keys, settings, and cached data.
    @MainActor
    static func performFactoryWipe() {
        // 1. Delete Keychain items
        do {
            try KeychainHelper.deleteKeys()
        } catch {
            #if DEBUG
            print("⚠️ Keychain wipe error: \(error)")
            #endif
        }
        
        // 2. Clear UserDefaults
        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
            UserDefaults.standard.synchronize()
        }
        
        // 3. Clear caches
        URLCache.shared.removeAllCachedResponses()
        
        #if DEBUG
        print("🗑️ Factory wipe completed")
        #endif
    }
    
    // MARK: - #48: Biometric Failure Counter
    
    private static let biometricFailCountKey = "hawala.biometric.failCount"
    private static let biometricMaxAttempts = 3
    
    /// Record a biometric failure. Returns true if max attempts reached.
    static func recordBiometricFailure() -> Bool {
        let count = UserDefaults.standard.integer(forKey: biometricFailCountKey) + 1
        UserDefaults.standard.set(count, forKey: biometricFailCountKey)
        return count >= biometricMaxAttempts
    }
    
    /// Reset the biometric failure counter (call on successful auth or passcode fallback).
    static func resetBiometricFailureCount() {
        UserDefaults.standard.set(0, forKey: biometricFailCountKey)
    }
    
    /// Current biometric failure count.
    static var biometricFailureCount: Int {
        UserDefaults.standard.integer(forKey: biometricFailCountKey)
    }
    
    /// Whether we should fall back to passcode (3+ failures).
    static var shouldFallbackToPasscode: Bool {
        biometricFailureCount >= biometricMaxAttempts
    }
    
    // MARK: - #49: Backup State Persistence
    
    private static let backupInProgressKey = "hawala.backup.inProgress"
    private static let backupStepKey = "hawala.backup.step"
    
    /// Mark backup flow started.
    static func markBackupStarted(step: String = "init") {
        UserDefaults.standard.set(true, forKey: backupInProgressKey)
        UserDefaults.standard.set(step, forKey: backupStepKey)
    }
    
    /// Mark backup flow completed.
    static func markBackupFinished() {
        UserDefaults.standard.removeObject(forKey: backupInProgressKey)
        UserDefaults.standard.removeObject(forKey: backupStepKey)
    }
    
    /// Returns the step where the backup was interrupted, or nil if no interrupted backup.
    static var interruptedBackupStep: String? {
        guard UserDefaults.standard.bool(forKey: backupInProgressKey) else { return nil }
        return UserDefaults.standard.string(forKey: backupStepKey) ?? "init"
    }
    
    // MARK: - #52: Multiple Windows Guard
    
    #if canImport(AppKit)
    /// Returns true if the app already has a key window open.
    @MainActor
    static var hasExistingWindow: Bool {
        NSApplication.shared.windows.contains { $0.isVisible }
    }
    #endif
    
    // MARK: - #56: Spam NFT Filter
    
    /// Basic heuristic to detect spam/scam NFT names.
    static func isLikelySpamNFT(name: String, description: String = "") -> Bool {
        let combined = (name + " " + description).lowercased()
        let spamPatterns = [
            "airdrop", "free mint", "claim your", "visit http",
            "click here", "congratulations", "you won", "reward",
            ".xyz", ".ru", "t.co/", "bit.ly/"
        ]
        return spamPatterns.contains { combined.contains($0) }
    }
    
    // MARK: - #57: NFT Metadata Fallback
    
    /// Returns a safe fallback name when NFT metadata fails to load.
    static func nftFallbackName(tokenId: String, contractAddress: String) -> String {
        let shortContract = contractAddress.prefix(6) + "…" + contractAddress.suffix(4)
        return "NFT #\(tokenId) (\(shortContract))"
    }
    
    // MARK: - #59: Locked During Receive
    
    private static let pendingReceiveNotificationsKey = "hawala.pendingReceiveNotifications"
    
    /// Queue an incoming receive notification while the app is locked.
    static func queueReceiveNotification(chain: String, amount: String, from: String) {
        var pending = loadPendingReceiveNotifications()
        pending.append(PendingReceiveNotification(chain: chain, amount: amount, from: from, timestamp: Date().timeIntervalSince1970))
        savePendingReceiveNotifications(pending)
    }
    
    /// Drain and return all queued receive notifications.
    static func drainPendingReceiveNotifications() -> [PendingReceiveNotification] {
        let pending = loadPendingReceiveNotifications()
        UserDefaults.standard.removeObject(forKey: pendingReceiveNotificationsKey)
        return pending
    }
    
    struct PendingReceiveNotification: Codable {
        let chain: String
        let amount: String
        let from: String
        let timestamp: TimeInterval
    }
    
    private static func loadPendingReceiveNotifications() -> [PendingReceiveNotification] {
        guard let data = UserDefaults.standard.data(forKey: pendingReceiveNotificationsKey) else { return [] }
        return (try? JSONDecoder().decode([PendingReceiveNotification].self, from: data)) ?? []
    }
    
    private static func savePendingReceiveNotifications(_ notifs: [PendingReceiveNotification]) {
        if let data = try? JSONEncoder().encode(notifs) {
            UserDefaults.standard.set(data, forKey: pendingReceiveNotificationsKey)
        }
    }
    
    // MARK: - #19: QR Code Payload Validation
    
    /// Validates a scanned QR code payload for common attack vectors.
    /// Returns nil if safe, or a warning string if suspicious.
    static func validateQRPayload(_ payload: String) -> String? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Reject empty
        guard !trimmed.isEmpty else {
            return "Empty QR code"
        }
        
        // Reject extremely long payloads (potential buffer overflow)
        guard trimmed.count < 4096 else {
            return "QR code payload too large"
        }
        
        // Reject javascript: URLs
        if trimmed.lowercased().hasPrefix("javascript:") {
            return "Malicious QR code detected"
        }
        
        // Reject data: URLs (potential phishing)
        if trimmed.lowercased().hasPrefix("data:") {
            return "Suspicious QR code format"
        }
        
        // Warn on http:// (non-HTTPS links)
        if trimmed.lowercased().hasPrefix("http://") {
            return "Insecure link detected — use HTTPS"
        }
        
        return nil // safe
    }
}
