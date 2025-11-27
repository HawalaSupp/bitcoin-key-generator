import Foundation
import SwiftUI
import Combine

// MARK: - Auto Lock Manager

/// Manages automatic screen locking based on inactivity and app state
@MainActor
final class AutoLockManager: ObservableObject {
    static let shared = AutoLockManager()
    
    // MARK: - Published State
    
    @Published var isLocked = false
    @Published var showBlur = false
    @Published var lockTimeout: LockTimeout = .fiveMinutes
    @Published var lockOnBackground = true
    @Published var requireBiometricOnUnlock = true
    
    // MARK: - Private State
    
    private var lastActivityTime = Date()
    private var inactivityTimer: Timer?
    private var backgroundObserver: Any?
    private var foregroundObserver: Any?
    private var didEnterBackgroundTime: Date?
    
    private let storageKey = "hawala_autolock_settings"
    
    private init() {
        loadSettings()
        setupObservers()
        startInactivityTimer()
    }
    
    // Note: deinit removed - singleton lives for app lifetime
    // Observers and timers are cleaned up when app terminates
    
    // MARK: - Public API
    
    /// Record user activity to reset the inactivity timer
    func recordActivity() {
        lastActivityTime = Date()
    }
    
    /// Manually lock the app
    func lock() {
        isLocked = true
        showBlur = true
    }
    
    /// Unlock the app (call after successful biometric/passcode)
    func unlock() {
        isLocked = false
        showBlur = false
        lastActivityTime = Date()
    }
    
    /// Update lock timeout setting
    func setLockTimeout(_ timeout: LockTimeout) {
        lockTimeout = timeout
        saveSettings()
        restartInactivityTimer()
    }
    
    /// Update background lock setting
    func setLockOnBackground(_ enabled: Bool) {
        lockOnBackground = enabled
        saveSettings()
    }
    
    /// Update biometric requirement setting
    func setRequireBiometricOnUnlock(_ enabled: Bool) {
        requireBiometricOnUnlock = enabled
        saveSettings()
    }
    
    // MARK: - Timer Management
    
    private func startInactivityTimer() {
        inactivityTimer?.invalidate()
        
        guard lockTimeout != .never else { return }
        
        // Check every 10 seconds
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkInactivity()
            }
        }
    }
    
    private func restartInactivityTimer() {
        lastActivityTime = Date()
        startInactivityTimer()
    }
    
    private func checkInactivity() {
        guard !isLocked else { return }
        guard lockTimeout != .never else { return }
        
        let elapsed = Date().timeIntervalSince(lastActivityTime)
        
        if elapsed >= lockTimeout.seconds {
            lock()
        }
    }
    
    // MARK: - App State Observers
    
    private func setupObservers() {
        #if os(macOS)
        // macOS: Use NSApplication notifications
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppWillResignActive()
            }
        }
        
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppDidBecomeActive()
            }
        }
        #endif
    }
    
    private func handleAppWillResignActive() {
        didEnterBackgroundTime = Date()
        
        if lockOnBackground {
            showBlur = true
        }
    }
    
    private func handleAppDidBecomeActive() {
        // Check if we should lock based on time in background
        if let backgroundTime = didEnterBackgroundTime {
            let elapsed = Date().timeIntervalSince(backgroundTime)
            
            // Lock if in background longer than timeout (or 30 seconds if lockOnBackground)
            let threshold = lockOnBackground ? min(30, lockTimeout.seconds) : lockTimeout.seconds
            
            if elapsed >= threshold && lockTimeout != .never {
                lock()
            } else {
                showBlur = false
            }
        } else {
            showBlur = false
        }
        
        didEnterBackgroundTime = nil
        lastActivityTime = Date()
    }
    
    // MARK: - Persistence
    
    private func loadSettings() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(AutoLockSettings.self, from: data) else {
            return
        }
        
        lockTimeout = settings.lockTimeout
        lockOnBackground = settings.lockOnBackground
        requireBiometricOnUnlock = settings.requireBiometricOnUnlock
    }
    
    private func saveSettings() {
        let settings = AutoLockSettings(
            lockTimeout: lockTimeout,
            lockOnBackground: lockOnBackground,
            requireBiometricOnUnlock: requireBiometricOnUnlock
        )
        
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

// MARK: - Lock Timeout Options

enum LockTimeout: String, CaseIterable, Codable, Identifiable {
    case immediately = "immediately"
    case thirtySeconds = "30_seconds"
    case oneMinute = "1_minute"
    case fiveMinutes = "5_minutes"
    case fifteenMinutes = "15_minutes"
    case oneHour = "1_hour"
    case never = "never"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .immediately: return "Immediately"
        case .thirtySeconds: return "30 seconds"
        case .oneMinute: return "1 minute"
        case .fiveMinutes: return "5 minutes"
        case .fifteenMinutes: return "15 minutes"
        case .oneHour: return "1 hour"
        case .never: return "Never"
        }
    }
    
    var seconds: TimeInterval {
        switch self {
        case .immediately: return 0
        case .thirtySeconds: return 30
        case .oneMinute: return 60
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        case .oneHour: return 3600
        case .never: return .infinity
        }
    }
}

// MARK: - Settings Model

private struct AutoLockSettings: Codable {
    let lockTimeout: LockTimeout
    let lockOnBackground: Bool
    let requireBiometricOnUnlock: Bool
}

// MARK: - Blur Overlay View

struct LockBlurOverlay: View {
    @ObservedObject var autoLock = AutoLockManager.shared
    let onUnlockRequested: () -> Void
    
    var body: some View {
        if autoLock.showBlur || autoLock.isLocked {
            ZStack {
                // Blur background
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                
                // Lock icon and unlock button
                if autoLock.isLocked {
                    VStack(spacing: 20) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        
                        Text("Hawala Locked")
                            .font(.title2.bold())
                        
                        Text("Tap to unlock")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Button {
                            onUnlockRequested()
                        } label: {
                            Label("Unlock", systemImage: "faceid")
                                .font(.headline)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    }
                }
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: autoLock.showBlur)
            .animation(.easeInOut(duration: 0.2), value: autoLock.isLocked)
        }
    }
}

// MARK: - Activity Tracking View Modifier

struct ActivityTrackingModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onTapGesture {
                AutoLockManager.shared.recordActivity()
            }
            .onAppear {
                AutoLockManager.shared.recordActivity()
            }
    }
}

extension View {
    /// Track user activity for auto-lock
    func trackActivity() -> some View {
        modifier(ActivityTrackingModifier())
    }
}

// MARK: - Settings View

struct AutoLockSettingsView: View {
    @ObservedObject var autoLock = AutoLockManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Auto-Lock Settings")
                    .font(.title2.bold())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            Form {
                Section {
                    Picker("Lock after inactivity", selection: $autoLock.lockTimeout) {
                        ForEach(LockTimeout.allCases) { timeout in
                            Text(timeout.displayName).tag(timeout)
                        }
                    }
                    .onChange(of: autoLock.lockTimeout) { newValue in
                        autoLock.setLockTimeout(newValue)
                    }
                } header: {
                    Text("Timeout")
                } footer: {
                    Text("Automatically lock Hawala after this period of inactivity")
                }
                
                Section {
                    Toggle("Lock when app goes to background", isOn: $autoLock.lockOnBackground)
                        .onChange(of: autoLock.lockOnBackground) { newValue in
                            autoLock.setLockOnBackground(newValue)
                        }
                    
                    Toggle("Require biometric to unlock", isOn: $autoLock.requireBiometricOnUnlock)
                        .onChange(of: autoLock.requireBiometricOnUnlock) { newValue in
                            autoLock.setRequireBiometricOnUnlock(newValue)
                        }
                } header: {
                    Text("Security")
                } footer: {
                    Text("Show blur overlay when switching apps to protect sensitive data")
                }
                
                Section {
                    Button {
                        autoLock.lock()
                        dismiss()
                    } label: {
                        Label("Lock Now", systemImage: "lock.fill")
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 400, height: 400)
    }
}
