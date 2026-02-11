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
    
    // MARK: - #7: Wrong Network Address Paste
    
    /// Detects if an address is pasted for the wrong network.
    /// Returns a warning message if mismatch detected, nil if OK.
    static func checkAddressNetworkMismatch(address: String, expectedChain: String) -> String? {
        let addr = address.trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch expectedChain.lowercased() {
        case "bitcoin":
            // Bitcoin addresses start with 1, 3, or bc1
            if addr.hasPrefix("0x") { return "This looks like an Ethereum address, not Bitcoin." }
            if !addr.hasPrefix("1") && !addr.hasPrefix("3") && !addr.hasPrefix("bc1") {
                return "This doesn't look like a valid Bitcoin address."
            }
        case "ethereum", "bnb", "polygon", "arbitrum", "optimism", "avalanche", "base":
            // EVM addresses start with 0x and are 42 chars
            if addr.hasPrefix("bc1") || addr.hasPrefix("1") || addr.hasPrefix("3") {
                return "This looks like a Bitcoin address, not an EVM address."
            }
            if !addr.hasPrefix("0x") || addr.count != 42 {
                return "Invalid Ethereum-style address format."
            }
        case "solana":
            if addr.hasPrefix("0x") { return "This looks like an Ethereum address, not Solana." }
            if addr.hasPrefix("bc1") { return "This looks like a Bitcoin address, not Solana." }
        default:
            break
        }
        return nil
    }
    
    // MARK: - #8: Whitespace in Pasted Address
    
    /// Strips extraneous whitespace/newlines from a pasted address.
    static func sanitizePastedAddress(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
           .replacingOccurrences(of: " ", with: "")
           .replacingOccurrences(of: "\n", with: "")
           .replacingOccurrences(of: "\t", with: "")
    }
    
    // MARK: - #11: Zero or Negative Amount
    
    /// Returns a user-facing error if the amount is zero or negative.
    static func validatePositiveAmount(_ amount: String) -> String? {
        let normalized = normaliseAmountInput(amount)
        guard let value = Double(normalized) else {
            return "Invalid amount."
        }
        if value <= 0 {
            return "Amount must be greater than zero."
        }
        return nil
    }
    
    // MARK: - #10: Amount Exceeds Balance
    
    /// Returns a warning if amount exceeds balance.
    static func checkBalanceSufficiency(amount: Double, balance: Double, symbol: String) -> String? {
        if amount > balance {
            return "Insufficient \(symbol) balance. You have \(String(format: "%.6f", balance)) but need \(String(format: "%.6f", amount))."
        }
        return nil
    }
    
    // MARK: - #17: Double-Tap Guard
    
    private static let lastConfirmTapKey = "hawala.lastConfirmTap"
    
    /// Returns true if a confirm button tap is too fast (< 1 second since last tap).
    /// Use to prevent accidental double-submissions.
    static func isDoubleTap(cooldown: TimeInterval = 1.0) -> Bool {
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: lastConfirmTapKey)
        UserDefaults.standard.set(now, forKey: lastConfirmTapKey)
        guard last > 0 else { return false }
        return (now - last) < cooldown
    }
    
    // MARK: - #47: Clipboard Expiry
    
    private static let clipboardTimestampKey = "hawala.clipboard.timestamp"
    private static let clipboardExpirySeconds: TimeInterval = 60 // 1 minute
    
    /// Mark that a sensitive value was copied to clipboard.
    static func markClipboardCopied() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: clipboardTimestampKey)
    }
    
    /// Clear the clipboard if the copied value has expired.
    static func clearClipboardIfExpired() {
        #if canImport(AppKit)
        let ts = UserDefaults.standard.double(forKey: clipboardTimestampKey)
        guard ts > 0 else { return }
        let elapsed = Date().timeIntervalSince1970 - ts
        if elapsed > clipboardExpirySeconds {
            NSPasteboard.general.clearContents()
            UserDefaults.standard.removeObject(forKey: clipboardTimestampKey)
        }
        #endif
    }
    
    /// Whether the clipboard has sensitive data that hasn't expired yet.
    static var isClipboardSensitive: Bool {
        let ts = UserDefaults.standard.double(forKey: clipboardTimestampKey)
        guard ts > 0 else { return false }
        return Date().timeIntervalSince1970 - ts < clipboardExpirySeconds
    }
    
    // MARK: - #60: Hardcoded Path Safety
    
    /// Returns true if a file path exists on disk.
    static func fileExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
    
    // MARK: - #20: Slippage Zero Guard
    
    /// Returns a warning if slippage is effectively zero.
    static func checkSlippage(_ slippage: Double) -> String? {
        if slippage < 0.01 {
            return "Slippage is set to 0%. Most transactions will fail due to price movement."
        }
        if slippage > 10 {
            return "Slippage is very high (\(String(format: "%.1f", slippage))%). You may receive significantly less than expected."
        }
        return nil
    }
    
    // MARK: - #29: Incomplete Address (0x only)
    
    /// Returns a warning if the address is clearly incomplete.
    static func checkIncompleteAddress(_ address: String) -> String? {
        let addr = sanitizePastedAddress(address)
        if addr == "0x" || addr == "0X" {
            return "Address is incomplete — only the '0x' prefix was entered."
        }
        if addr.hasPrefix("0x") && addr.count < 10 {
            return "Address appears truncated."
        }
        if addr.isEmpty {
            return "No address entered."
        }
        return nil
    }
    
    // MARK: - #53: High Contrast Mode Check
    
    #if canImport(AppKit)
    /// Returns true if the user has enabled increased contrast in System Preferences.
    @MainActor
    static var isHighContrastEnabled: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }
    #endif
    
    // MARK: - #58: VoiceOver Check
    
    /// Returns true if VoiceOver is running.
    static var isVoiceOverRunning: Bool {
        #if canImport(AppKit)
        NSWorkspace.shared.isVoiceOverEnabled
        #else
        false
        #endif
    }
}
