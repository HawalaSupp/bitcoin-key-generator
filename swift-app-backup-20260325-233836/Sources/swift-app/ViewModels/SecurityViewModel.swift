import SwiftUI
import CryptoKit
import LocalAuthentication

/// ViewModel handling all security-related state and logic
/// - Passcode management
/// - Biometric authentication
/// - Auto-lock functionality
/// - Privacy blur
@MainActor
final class SecurityViewModel: ObservableObject {
    // MARK: - Published State
    @Published var isUnlocked = false
    @Published var showUnlockSheet = false
    @Published var showSecurityNotice = false
    @Published var showSecuritySettings = false
    @Published var showPrivacyBlur = false
    @Published var biometricState: BiometricState = .unknown
    
    // MARK: - AppStorage (persisted)
    @AppStorage("hawala.securityAcknowledged") var hasAcknowledgedSecurityNotice = false
    @AppStorage("hawala.passcodeHash") var storedPasscodeHash: String?
    @AppStorage("hawala.biometricUnlockEnabled") var biometricUnlockEnabled = false
    @AppStorage("hawala.biometricForSends") var biometricForSends = true
    @AppStorage("hawala.biometricForKeyReveal") var biometricForKeyReveal = true
    @AppStorage("hawala.autoLockInterval") var storedAutoLockInterval: Double = AutoLockIntervalOption.fiveMinutes.rawValue
    
    // MARK: - Internal State (accessible to ContentView during migration)
    var lastActivityTimestamp = Date()
    var autoLockTask: Task<Void, Never>?
    
    // MARK: - Public Methods for Auto-Lock Control
    func cancelAutoLock() {
        autoLockTask?.cancel()
    }
    
    #if canImport(AppKit)
    private var activityMonitor: UserActivityMonitor?
    #endif
    
    // MARK: - Computed Properties
    var canAccessSensitiveData: Bool {
        storedPasscodeHash == nil || isUnlocked
    }
    
    var hasPasscode: Bool {
        storedPasscodeHash != nil
    }
    
    var autoLockSelectionBinding: Binding<AutoLockIntervalOption> {
        Binding(
            get: { [weak self] in
                AutoLockIntervalOption(rawValue: self?.storedAutoLockInterval ?? AutoLockIntervalOption.fiveMinutes.rawValue) ?? .fiveMinutes
            },
            set: { [weak self] newValue in
                self?.storedAutoLockInterval = newValue.rawValue
                self?.recordActivity()
            }
        )
    }
    
    var biometricToggleBinding: Binding<Bool> {
        Binding(
            get: { [weak self] in
                guard let self = self else { return false }
                return self.biometricUnlockEnabled && self.storedPasscodeHash != nil
            },
            set: { [weak self] newValue in
                guard let self = self, self.storedPasscodeHash != nil else {
                    self?.biometricUnlockEnabled = false
                    return
                }
                self.biometricUnlockEnabled = newValue
                if newValue {
                    self.attemptBiometricUnlock(reason: "Unlock Hawala")
                }
            }
        )
    }
    
    var biometricDisplayInfo: (label: String, icon: String) {
        if case .available(let kind) = biometricState {
            return (kind.displayName, kind.iconName)
        }
        return ("Biometrics", "lock.circle")
    }
    
    // MARK: - Initialization
    init() {
        refreshBiometricAvailability()
    }
    
    // MARK: - Passcode Management
    func setPasscode(_ passcode: String) {
        storedPasscodeHash = hashPasscode(passcode)
        isUnlocked = true
        scheduleAutoLockCountdown()
    }
    
    func removePasscode() {
        storedPasscodeHash = nil
        isUnlocked = true
        biometricUnlockEnabled = false
        autoLockTask?.cancel()
    }
    
    func validatePasscode(_ passcode: String) -> Bool {
        guard let stored = storedPasscodeHash else { return true }
        return hashPasscode(passcode) == stored
    }
    
    func handlePasscodeChange() {
        if storedPasscodeHash != nil {
            lock()
        } else {
            isUnlocked = true
            biometricUnlockEnabled = false
            autoLockTask?.cancel()
        }
    }
    
    // MARK: - Lock/Unlock
    func lock() {
        isUnlocked = false
        showUnlockSheet = true
        autoLockTask?.cancel()
        if biometricUnlockEnabled {
            attemptBiometricUnlock(reason: "Unlock Hawala")
        }
    }
    
    func unlock() {
        isUnlocked = true
        showUnlockSheet = false
        recordActivity()
    }
    
    // MARK: - Activity Tracking
    func recordActivity() {
        lastActivityTimestamp = Date()
        scheduleAutoLockCountdown()
    }
    
    func scheduleAutoLockCountdown() {
        autoLockTask?.cancel()
        guard storedPasscodeHash != nil else { return }
        guard let interval = (AutoLockIntervalOption(rawValue: storedAutoLockInterval) ?? .fiveMinutes).duration,
              interval > 0 else { return }
        
        let deadline = lastActivityTimestamp.addingTimeInterval(interval)
        autoLockTask = Task { [weak self, deadline] in
            let delay = max(0, deadline.timeIntervalSinceNow)
            let nanos = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                if Date() >= deadline && self.storedPasscodeHash != nil {
                    self.lock()
                }
            }
        }
    }
    
    // MARK: - Activity Monitoring
    func startActivityMonitoringIfNeeded() {
        #if canImport(AppKit)
        guard activityMonitor == nil else { return }
        activityMonitor = UserActivityMonitor { [weak self] in
            Task { @MainActor [weak self] in
                self?.recordActivity()
            }
        }
        #endif
    }
    
    func stopActivityMonitoring() {
        #if canImport(AppKit)
        activityMonitor?.stop()
        activityMonitor = nil
        #endif
    }
    
    // MARK: - Biometric Authentication
    func refreshBiometricAvailability() {
        #if canImport(LocalAuthentication)
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            if #available(macOS 11.0, iOS 11.0, *) {
                switch context.biometryType {
                case .touchID:
                    biometricState = .available(.touchID)
                case .faceID:
                    biometricState = .available(.faceID)
                default:
                    biometricState = .available(.generic)
                }
            } else {
                biometricState = .available(.generic)
            }
        } else {
            let reason = error?.localizedDescription ?? "Biometrics are not available on this device."
            biometricState = .unavailable(reason)
            biometricUnlockEnabled = false
        }
        #else
        biometricState = .unavailable("Biometrics are not supported on this platform.")
        biometricUnlockEnabled = false
        #endif
    }
    
    func attemptBiometricUnlock(reason: String) {
        #if canImport(LocalAuthentication)
        guard biometricUnlockEnabled else { return }
        let context = LAContext()
        context.localizedFallbackTitle = "Enter Passcode"
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] success, evalError in
                guard success else {
                    if let evalError = evalError as? LAError, evalError.code == .biometryNotAvailable {
                        Task { @MainActor [weak self] in
                            self?.biometricUnlockEnabled = false
                            self?.biometricState = .unavailable(evalError.localizedDescription)
                        }
                    }
                    return
                }
                Task { @MainActor [weak self] in
                    self?.unlock()
                }
            }
        } else {
            biometricUnlockEnabled = false
            biometricState = .unavailable(error?.localizedDescription ?? "Biometrics are unavailable.")
        }
        #else
        _ = reason
        #endif
    }
    
    /// Authenticate with biometrics for sensitive actions (key reveal, sends, etc.)
    func authenticateForSensitiveAction(reason: String) async -> BiometricAuthHelper.AuthResult {
        return await BiometricAuthHelper.authenticate(reason: reason)
    }
    
    // MARK: - Privacy Blur
    func showBlur() {
        withAnimation(.easeIn(duration: 0.1)) {
            showPrivacyBlur = true
        }
    }
    
    func hideBlur() {
        withAnimation(.easeOut(duration: 0.2)) {
            showPrivacyBlur = false
        }
    }
    
    // MARK: - Scene Phase Handling
    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            hideBlur()
            refreshBiometricAvailability()
            startActivityMonitoringIfNeeded()
            recordActivity()
            if storedPasscodeHash != nil && !isUnlocked {
                if biometricUnlockEnabled {
                    attemptBiometricUnlock(reason: "Unlock Hawala")
                }
                showUnlockSheet = true
            }
        case .inactive:
            showBlur()
        case .background:
            showPrivacyBlur = true
            if storedPasscodeHash != nil {
                isUnlocked = false
            }
            autoLockTask?.cancel()
            stopActivityMonitoring()
        @unknown default:
            break
        }
    }
    
    // MARK: - Passcode Helpers
    func hashPasscode(_ passcode: String) -> String {
        let data = Data(passcode.utf8)
        let digest = CryptoKit.SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - UserActivityMonitor (macOS)
#if canImport(AppKit)
private final class UserActivityMonitor {
    private var tokens: [Any] = []

    init(handler: @escaping () -> Void) {
        let mask: NSEvent.EventTypeMask = [
            .keyDown,
            .flagsChanged,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .mouseMoved,
            .scrollWheel
        ]

        if let localToken = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            handler()
            return event
        }) {
            tokens.append(localToken)
        }

        if let globalToken = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { _ in
            handler()
        }) {
            tokens.append(globalToken)
        }
    }

    func stop() {
        for token in tokens {
            NSEvent.removeMonitor(token)
        }
        tokens.removeAll()
    }

    deinit {
        stop()
    }
}
#else
private final class UserActivityMonitor {
    init(handler: @escaping () -> Void) {}
    func stop() {}
}
#endif
