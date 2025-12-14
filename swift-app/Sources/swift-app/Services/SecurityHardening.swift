import SwiftUI
import LocalAuthentication
import CryptoKit
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Security Hardening Module
// Comprehensive security features for enterprise-grade wallet protection

// MARK: - Transaction Security Manager

/// Manages security requirements for transactions
@MainActor
class TransactionSecurityManager: ObservableObject {
    static let shared = TransactionSecurityManager()
    
    // Configuration
    @Published var highValueThresholdUSD: Double = 1000.0
    @Published var requireBiometricForHighValue: Bool = true
    @Published var requireAddressVerificationForNewAddresses: Bool = true
    @Published var enableAddressPoisoningDetection: Bool = true
    @Published var clipboardClearTimeoutSeconds: TimeInterval = 30
    
    // Known addresses for poisoning detection
    private var knownAddresses: Set<String> = []
    private var recentlyCopiedAddresses: [String: Date] = [:]
    
    private init() {
        loadSettings()
    }
    
    // MARK: - High Value Transaction Check
    
    /// Determines if a transaction requires additional authentication
    func requiresAdditionalAuth(amountUSD: Double) -> Bool {
        return amountUSD >= highValueThresholdUSD && requireBiometricForHighValue
    }
    
    /// Checks if biometric authentication is available
    func canUseBiometric() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    /// Requests biometric authentication
    func requestBiometricAuth(reason: String) async -> Bool {
        let context = LAContext()
        
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
        } catch {
            print("Biometric auth failed: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Address Poisoning Detection
    
    /// Registers an address as known/trusted
    func registerKnownAddress(_ address: String) {
        knownAddresses.insert(normalizeAddress(address))
    }
    
    /// Checks if an address might be a poisoning attempt
    func checkForPoisoning(_ address: String, against knownAddress: String) -> PoisoningCheckResult {
        let normalized = normalizeAddress(address)
        let normalizedKnown = normalizeAddress(knownAddress)
        
        // Exact match is safe
        if normalized == normalizedKnown {
            return .safe
        }
        
        // Check for similar prefix/suffix (common poisoning technique)
        if hasSimilarPrefixSuffix(normalized, normalizedKnown) {
            return .suspicious(reason: "Address has similar prefix/suffix to a known address - possible poisoning attempt")
        }
        
        // Check if this address was recently copied (clipboard hijacking)
        if let lastCopied = recentlyCopiedAddresses[normalized] {
            let timeSinceCopy = Date().timeIntervalSince(lastCopied)
            if timeSinceCopy < 300 { // Within 5 minutes
                return .recentlyCopied(timestamp: lastCopied)
            }
        }
        
        return .unknown
    }
    
    /// Records an address that was copied to clipboard
    func recordCopiedAddress(_ address: String) {
        let normalized = normalizeAddress(address)
        recentlyCopiedAddresses[normalized] = Date()
        
        // Clean up old entries
        let cutoff = Date().addingTimeInterval(-3600) // 1 hour
        recentlyCopiedAddresses = recentlyCopiedAddresses.filter { $0.value > cutoff }
    }
    
    /// Validates an address for common attacks
    func validateAddress(_ address: String, chain: String) -> SecurityAddressValidation {
        // Check length
        guard !address.isEmpty else {
            return .invalid(reason: "Address is empty")
        }
        
        // Chain-specific validation
        switch chain.lowercased() {
        case "bitcoin", "bitcoin-testnet":
            return validateBitcoinAddress(address, isTestnet: chain.contains("testnet"))
        case "ethereum", "ethereum-sepolia":
            return validateEthereumAddress(address)
        case "litecoin":
            return validateLitecoinAddress(address)
        case "solana":
            return validateSolanaAddress(address)
        default:
            return .valid
        }
    }
    
    // MARK: - Private Helpers
    
    private func normalizeAddress(_ address: String) -> String {
        address.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func hasSimilarPrefixSuffix(_ addr1: String, _ addr2: String) -> Bool {
        guard addr1.count >= 8, addr2.count >= 8 else { return false }
        
        let prefix1 = String(addr1.prefix(4))
        let prefix2 = String(addr2.prefix(4))
        let suffix1 = String(addr1.suffix(4))
        let suffix2 = String(addr2.suffix(4))
        
        // If both prefix AND suffix match but middle is different, suspicious
        if prefix1 == prefix2 && suffix1 == suffix2 && addr1 != addr2 {
            return true
        }
        
        return false
    }
    
    private func validateBitcoinAddress(_ address: String, isTestnet: Bool) -> SecurityAddressValidation {
        // Length check
        if address.count < 26 || address.count > 62 {
            return .invalid(reason: "Invalid Bitcoin address length")
        }
        
        // Prefix check
        if isTestnet {
            let validPrefixes = ["m", "n", "2", "tb1"]
            if !validPrefixes.contains(where: { address.hasPrefix($0) }) {
                return .invalid(reason: "Invalid testnet address prefix")
            }
        } else {
            let validPrefixes = ["1", "3", "bc1"]
            if !validPrefixes.contains(where: { address.hasPrefix($0) }) {
                return .invalid(reason: "Invalid mainnet address prefix")
            }
        }
        
        return .valid
    }
    
    private func validateEthereumAddress(_ address: String) -> SecurityAddressValidation {
        // Must start with 0x
        guard address.hasPrefix("0x") else {
            return .invalid(reason: "Ethereum address must start with 0x")
        }
        
        // Must be 42 characters (0x + 40 hex)
        guard address.count == 42 else {
            return .invalid(reason: "Ethereum address must be 42 characters")
        }
        
        // Check if all characters after 0x are valid hex
        let hexPart = address.dropFirst(2)
        let hexChars = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        guard hexPart.unicodeScalars.allSatisfy({ hexChars.contains($0) }) else {
            return .invalid(reason: "Invalid characters in Ethereum address")
        }
        
        return .valid
    }
    
    private func validateLitecoinAddress(_ address: String) -> SecurityAddressValidation {
        // Length check
        if address.count < 26 || address.count > 62 {
            return .invalid(reason: "Invalid Litecoin address length")
        }
        
        // Prefix check
        let validPrefixes = ["L", "M", "ltc1"]
        if !validPrefixes.contains(where: { address.hasPrefix($0) }) {
            return .invalid(reason: "Invalid Litecoin address prefix")
        }
        
        return .valid
    }
    
    private func validateSolanaAddress(_ address: String) -> SecurityAddressValidation {
        // Solana addresses are base58 encoded, 32-44 characters
        if address.count < 32 || address.count > 44 {
            return .invalid(reason: "Invalid Solana address length")
        }
        
        // Check for valid base58 characters (no 0, O, I, l)
        let invalidChars = CharacterSet(charactersIn: "0OIl")
        if address.unicodeScalars.contains(where: { invalidChars.contains($0) }) {
            return .invalid(reason: "Invalid characters in Solana address")
        }
        
        return .valid
    }
    
    private func loadSettings() {
        // Load from UserDefaults
        let defaults = UserDefaults.standard
        if let threshold = defaults.object(forKey: "security.highValueThreshold") as? Double {
            highValueThresholdUSD = threshold
        }
        requireBiometricForHighValue = defaults.bool(forKey: "security.requireBiometricForHighValue")
        requireAddressVerificationForNewAddresses = defaults.bool(forKey: "security.requireAddressVerification")
        enableAddressPoisoningDetection = defaults.bool(forKey: "security.enablePoisoningDetection")
        if let timeout = defaults.object(forKey: "security.clipboardTimeout") as? Double {
            clipboardClearTimeoutSeconds = timeout
        }
    }
    
    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(highValueThresholdUSD, forKey: "security.highValueThreshold")
        defaults.set(requireBiometricForHighValue, forKey: "security.requireBiometricForHighValue")
        defaults.set(requireAddressVerificationForNewAddresses, forKey: "security.requireAddressVerification")
        defaults.set(enableAddressPoisoningDetection, forKey: "security.enablePoisoningDetection")
        defaults.set(clipboardClearTimeoutSeconds, forKey: "security.clipboardTimeout")
    }
}

// MARK: - Security Check Results

enum PoisoningCheckResult {
    case safe
    case suspicious(reason: String)
    case recentlyCopied(timestamp: Date)
    case unknown
    
    var isWarning: Bool {
        switch self {
        case .suspicious, .recentlyCopied: return true
        default: return false
        }
    }
}

enum SecurityAddressValidation {
    case valid
    case invalid(reason: String)
    case warning(reason: String)
    
    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }
}

// MARK: - Secure Clipboard Manager

/// Enhanced clipboard manager with security features
@MainActor
class SecureClipboardManager: ObservableObject {
    static let shared = SecureClipboardManager()
    
    @Published var hasSecureContent = false
    @Published var timeUntilClear: TimeInterval = 0
    
    private var clearTask: Task<Void, Never>?
    private var lastContent: String?
    private var timer: Timer?
    
    private init() {}
    
    /// Copies content with auto-clear and monitoring
    func copySecure(_ text: String, timeout: TimeInterval = 30) {
        // Cancel existing clear task
        clearTask?.cancel()
        timer?.invalidate()
        
        // Copy to clipboard
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif
        
        lastContent = text
        hasSecureContent = true
        timeUntilClear = timeout
        
        // Record for poisoning detection
        TransactionSecurityManager.shared.recordCopiedAddress(text)
        
        // Start countdown timer
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.timeUntilClear -= 1
                if self.timeUntilClear <= 0 {
                    self.timer?.invalidate()
                }
            }
        }
        
        // Schedule auto-clear
        clearTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                
                guard let self = self else { return }
                
                // Only clear if content hasn't changed
                #if canImport(AppKit)
                if NSPasteboard.general.string(forType: .string) == self.lastContent {
                    NSPasteboard.general.clearContents()
                }
                #endif
                
                self.hasSecureContent = false
                self.lastContent = nil
                self.timeUntilClear = 0
            } catch {
                // Task cancelled
            }
        }
    }
    
    /// Immediately clears the clipboard
    func clearNow() {
        clearTask?.cancel()
        timer?.invalidate()
        
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        #endif
        
        hasSecureContent = false
        lastContent = nil
        timeUntilClear = 0
    }
    
    /// Checks if clipboard might have been hijacked
    func checkForHijacking() -> Bool {
        guard let expected = lastContent else { return false }
        
        #if canImport(AppKit)
        let current = NSPasteboard.general.string(forType: .string)
        return current != nil && current != expected && hasSecureContent
        #else
        return false
        #endif
    }
}

// MARK: - Security Warning Views

/// Warning banner for address poisoning
struct AddressPoisoningWarningBanner: View {
    let result: PoisoningCheckResult
    let onDismiss: () -> Void
    
    var body: some View {
        if result.isWarning {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundColor(.red)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Security Warning")
                        .font(.headline)
                        .foregroundColor(.red)
                    
                    Text(warningMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }
    
    private var warningMessage: String {
        switch result {
        case .suspicious(let reason):
            return reason
        case .recentlyCopied(let timestamp):
            let formatter = RelativeDateTimeFormatter()
            let relative = formatter.localizedString(for: timestamp, relativeTo: Date())
            return "This address was copied \(relative). Verify it matches the original."
        default:
            return ""
        }
    }
}

/// Biometric authentication sheet
struct BiometricAuthSheet: View {
    let reason: String
    let amountUSD: Double
    let onSuccess: () -> Void
    let onCancel: () -> Void
    
    @State private var isAuthenticating = false
    @State private var authError: String?
    
    var body: some View {
        VStack(spacing: 24) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "faceid")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
            }
            
            // Title
            Text("Authentication Required")
                .font(.title2.bold())
            
            // Reason
            VStack(spacing: 8) {
                Text(reason)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                if amountUSD > 0 {
                    Text("Amount: $\(amountUSD, specifier: "%.2f")")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
            }
            
            // Error message
            if let error = authError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            // Buttons
            HStack(spacing: 16) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                
                Button(action: authenticate) {
                    if isAuthenticating {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Label("Authenticate", systemImage: "faceid")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAuthenticating)
            }
        }
        .padding(32)
        .frame(width: 400)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
        .onAppear {
            authenticate()
        }
    }
    
    private func authenticate() {
        isAuthenticating = true
        authError = nil
        
        Task {
            let success = await TransactionSecurityManager.shared.requestBiometricAuth(reason: reason)
            
            await MainActor.run {
                isAuthenticating = false
                
                if success {
                    onSuccess()
                } else {
                    authError = "Authentication failed. Please try again."
                }
            }
        }
    }
}

/// Clipboard security indicator
struct ClipboardSecurityIndicator: View {
    @ObservedObject private var clipboard = SecureClipboardManager.shared
    
    var body: some View {
        if clipboard.hasSecureContent {
            HStack(spacing: 8) {
                Image(systemName: "clipboard.fill")
                    .foregroundColor(.orange)
                
                Text("Secure clipboard: \(Int(clipboard.timeUntilClear))s")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button(action: clipboard.clearNow) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.orange.opacity(0.1))
            )
        }
    }
}

// MARK: - Security Settings View

struct AdvancedSecuritySettingsView: View {
    @ObservedObject private var security = TransactionSecurityManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Security Settings")
                    .font(.title2.bold())
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Settings
            Form {
                Section("High-Value Transaction Protection") {
                    Toggle("Require biometric for high-value transactions", isOn: $security.requireBiometricForHighValue)
                    
                    HStack {
                        Text("High-value threshold")
                        Spacer()
                        TextField("Amount", value: $security.highValueThresholdUSD, format: .currency(code: "USD"))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                }
                
                Section("Address Security") {
                    Toggle("Verify new addresses before sending", isOn: $security.requireAddressVerificationForNewAddresses)
                    Toggle("Enable address poisoning detection", isOn: $security.enableAddressPoisoningDetection)
                }
                
                Section("Clipboard Security") {
                    HStack {
                        Text("Auto-clear timeout")
                        Spacer()
                        Picker("", selection: $security.clipboardClearTimeoutSeconds) {
                            Text("15 seconds").tag(TimeInterval(15))
                            Text("30 seconds").tag(TimeInterval(30))
                            Text("60 seconds").tag(TimeInterval(60))
                            Text("2 minutes").tag(TimeInterval(120))
                        }
                        .frame(width: 150)
                    }
                }
            }
            .formStyle(.grouped)
            
            // Save button
            Button(action: {
                security.saveSettings()
                dismiss()
            }) {
                Text("Save Settings")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .frame(width: 500, height: 500)
    }
}

// MARK: - Transaction Signing Confirmation

struct TransactionSigningConfirmation: View {
    let chain: String
    let amount: String
    let recipient: String
    let feeEstimate: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    @State private var hasVerifiedAmount = false
    @State private var hasVerifiedRecipient = false
    @State private var confirmationText = ""
    
    private let expectedConfirmation = "SEND"
    
    var body: some View {
        VStack(spacing: 24) {
            // Warning header
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.largeTitle)
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Confirm Transaction")
                        .font(.title2.bold())
                    Text("Review all details carefully before signing")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            // Transaction details
            VStack(spacing: 16) {
                SecurityDetailRow(label: "Network", value: chain, icon: "network")
                SecurityDetailRow(label: "Amount", value: amount, icon: "bitcoinsign.circle.fill")
                SecurityDetailRow(label: "Recipient", value: String(recipient.prefix(12)) + "..." + String(recipient.suffix(8)), icon: "person.circle.fill")
                SecurityDetailRow(label: "Network Fee", value: feeEstimate, icon: "flame.fill")
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.05))
            )
            
            // Verification checkboxes
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $hasVerifiedAmount) {
                    Text("I have verified the amount is correct")
                        .font(.subheadline)
                }
                
                Toggle(isOn: $hasVerifiedRecipient) {
                    Text("I have verified the recipient address")
                        .font(.subheadline)
                }
            }
            
            // Type to confirm
            VStack(alignment: .leading, spacing: 8) {
                Text("Type \"\(expectedConfirmation)\" to confirm:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextField("", text: $confirmationText)
                    .textFieldStyle(.roundedBorder)
                    .textCase(.uppercase)
            }
            
            // Action buttons
            HStack(spacing: 16) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                
                Button(action: onConfirm) {
                    Label("Sign & Send", systemImage: "signature")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(!canConfirm)
            }
        }
        .padding(24)
        .frame(width: 450)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }
    
    private var canConfirm: Bool {
        hasVerifiedAmount && hasVerifiedRecipient && confirmationText.uppercased() == expectedConfirmation
    }
}

private struct SecurityDetailRow: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 24)
            
            Text(label)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SecurityHardening_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AdvancedSecuritySettingsView()
            
            BiometricAuthSheet(
                reason: "Confirm high-value transaction",
                amountUSD: 5000,
                onSuccess: {},
                onCancel: {}
            )
            
            TransactionSigningConfirmation(
                chain: "Bitcoin",
                amount: "0.5 BTC",
                recipient: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
                feeEstimate: "0.0001 BTC",
                onConfirm: {},
                onCancel: {}
            )
            
            AddressPoisoningWarningBanner(
                result: .suspicious(reason: "Address matches prefix/suffix of known address"),
                onDismiss: {}
            )
        }
    }
}
#endif
