import SwiftUI
import LocalAuthentication

// MARK: - Passcode Lock Screen

/// Full-screen passcode entry view
struct PasscodeLockScreen: View {
    @ObservedObject var passcodeManager = PasscodeManager.shared
    
    @State private var enteredPasscode = ""
    @State private var errorMessage: String?
    @State private var isShaking = false
    @State private var attempts = 0
    @State private var isLockedOut = false
    @State private var lockoutEndTime: Date?
    @State private var lockoutTimeRemaining = 0
    @State private var biometricAvailable = false
    @State private var biometricType: LABiometryType = .none
    
    let maxDigits = 6
    let onUnlock: () -> Void
    
    private let lockoutTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // Background
            HawalaTheme.Colors.background
                .ignoresSafeArea()
            
            VStack(spacing: HawalaTheme.Spacing.xxl) {
                Spacer()
                
                // Logo
                VStack(spacing: HawalaTheme.Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        HawalaTheme.Colors.accent,
                                        HawalaTheme.Colors.accentHover
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundColor(.white)
                    }
                    
                    Text("Enter Passcode")
                        .font(HawalaTheme.Typography.h2)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    
                    Text("Enter your passcode to unlock Hawala")
                        .font(HawalaTheme.Typography.body)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
                
                // Passcode dots
                HStack(spacing: HawalaTheme.Spacing.md) {
                    ForEach(0..<maxDigits, id: \.self) { index in
                        Circle()
                            .fill(index < enteredPasscode.count ? HawalaTheme.Colors.accent : HawalaTheme.Colors.border)
                            .frame(width: 16, height: 16)
                    }
                }
                .modifier(ShakeEffect(shakes: isShaking ? 2 : 0))
                .animation(.easeInOut(duration: 0.4), value: isShaking)
                
                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(HawalaTheme.Typography.bodySmall)
                        .foregroundColor(HawalaTheme.Colors.error)
                        .padding(.top, HawalaTheme.Spacing.sm)
                }
                
                Spacer()
                
                // Number pad
                VStack(spacing: HawalaTheme.Spacing.md) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: HawalaTheme.Spacing.lg) {
                            ForEach(1...3, id: \.self) { col in
                                let number = row * 3 + col
                                PasscodeButton(number: "\(number)") {
                                    appendDigit("\(number)")
                                }
                            }
                        }
                    }
                    
                    // Bottom row: biometric, 0, delete
                    HStack(spacing: HawalaTheme.Spacing.lg) {
                        // Biometric button
                        PasscodeButton(number: "", icon: biometricIcon) {
                            attemptBiometricUnlock()
                        }
                        .opacity(biometricAvailable && !isLockedOut ? 1.0 : 0.3)
                        .disabled(!biometricAvailable || isLockedOut)
                        
                        PasscodeButton(number: "0") {
                            appendDigit("0")
                        }
                        
                        PasscodeButton(number: "", icon: "delete.left.fill") {
                            deleteDigit()
                        }
                    }
                }
                .padding(.horizontal, HawalaTheme.Spacing.xxl)
                
                Spacer()
            }
            .padding(HawalaTheme.Spacing.xl)
            .onAppear {
                checkBiometricAvailability()
                checkLockoutStatus()
            }
            .onReceive(lockoutTimer) { _ in
                updateLockoutTimer()
            }
        }
    }
    
    // MARK: - Biometric Authentication
    
    private var biometricIcon: String {
        switch biometricType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        default:
            return "faceid"
        }
    }
    
    private func checkBiometricAvailability() {
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            biometricAvailable = true
            biometricType = context.biometryType
        } else {
            biometricAvailable = false
            biometricType = .none
        }
    }
    
    private func attemptBiometricUnlock() {
        guard biometricAvailable, !isLockedOut else { return }
        
        let context = LAContext()
        context.localizedFallbackTitle = "Enter Passcode"
        
        let reason = "Unlock Hawala wallet"
        
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
            DispatchQueue.main.async {
                if success {
                    passcodeManager.unlock()
                    onUnlock()
                } else if let error = error as? LAError {
                    switch error.code {
                    case .biometryLockout:
                        errorMessage = "Biometrics locked. Use passcode."
                        biometricAvailable = false
                    case .userCancel, .userFallback:
                        break // User cancelled, do nothing
                    default:
                        errorMessage = "Authentication failed"
                    }
                }
            }
        }
    }
    
    // MARK: - Lockout Management
    
    private func checkLockoutStatus() {
        if let endTime = UserDefaults.standard.object(forKey: "hawala.lockoutEndTime") as? Date {
            if endTime > Date() {
                isLockedOut = true
                lockoutEndTime = endTime
                updateLockoutTimer()
            } else {
                clearLockout()
            }
        }
    }
    
    private func updateLockoutTimer() {
        guard let endTime = lockoutEndTime else { return }
        
        let remaining = Int(endTime.timeIntervalSinceNow)
        if remaining > 0 {
            lockoutTimeRemaining = remaining
            errorMessage = "Too many attempts. Try again in \(formatTime(remaining))"
        } else {
            clearLockout()
        }
    }
    
    private func startLockout(duration: TimeInterval) {
        let endTime = Date().addingTimeInterval(duration)
        lockoutEndTime = endTime
        isLockedOut = true
        UserDefaults.standard.set(endTime, forKey: "hawala.lockoutEndTime")
    }
    
    private func clearLockout() {
        isLockedOut = false
        lockoutEndTime = nil
        lockoutTimeRemaining = 0
        attempts = 0
        errorMessage = nil
        UserDefaults.standard.removeObject(forKey: "hawala.lockoutEndTime")
    }
    
    private func formatTime(_ seconds: Int) -> String {
        if seconds >= 60 {
            let minutes = seconds / 60
            let secs = seconds % 60
            return String(format: "%d:%02d", minutes, secs)
        }
        return "\(seconds)s"
    }
    
    private func appendDigit(_ digit: String) {
        guard !isLockedOut else { return }
        guard enteredPasscode.count < maxDigits else { return }
        
        enteredPasscode += digit
        errorMessage = nil
        
        // Check passcode when we have enough digits (4-6)
        if enteredPasscode.count >= 4 && enteredPasscode.count <= maxDigits {
            // Small delay for visual feedback
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                checkPasscode()
            }
        }
    }
    
    private func deleteDigit() {
        guard !enteredPasscode.isEmpty else { return }
        enteredPasscode.removeLast()
        errorMessage = nil
    }
    
    private func checkPasscode() {
        guard !isLockedOut else {
            errorMessage = "Account locked. Please wait."
            return
        }
        
        if passcodeManager.verifyPasscode(enteredPasscode) {
            clearLockout()
            passcodeManager.unlock()
            onUnlock()
        } else if enteredPasscode.count == maxDigits {
            // Wrong passcode
            attempts += 1
            errorMessage = "Incorrect passcode"
            
            // Shake animation
            isShaking = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                isShaking = false
                enteredPasscode = ""
            }
            
            // Progressive lockout after failed attempts
            switch attempts {
            case 5:
                startLockout(duration: 30)  // 30 seconds
            case 6:
                startLockout(duration: 60)  // 1 minute
            case 7:
                startLockout(duration: 300) // 5 minutes
            case 8:
                startLockout(duration: 900) // 15 minutes
            case 9...Int.max:
                startLockout(duration: 3600) // 1 hour
            default:
                break
            }
        }
    }
}

// MARK: - Passcode Setup Screen

struct PasscodeSetupScreen: View {
    @ObservedObject var passcodeManager = PasscodeManager.shared
    
    @State private var step: SetupStep = .create
    @State private var passcode = ""
    @State private var confirmPasscode = ""
    @State private var errorMessage: String?
    @State private var isShaking = false
    
    let maxDigits = 6
    let onComplete: () -> Void
    let onSkip: () -> Void
    
    enum SetupStep {
        case create
        case confirm
    }
    
    var body: some View {
        ZStack {
            HawalaTheme.Colors.background
                .ignoresSafeArea()
            
            VStack(spacing: HawalaTheme.Spacing.xxl) {
                Spacer()
                
                // Header
                VStack(spacing: HawalaTheme.Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        HawalaTheme.Colors.accent,
                                        HawalaTheme.Colors.accentHover
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: step == .create ? "lock.fill" : "checkmark.shield.fill")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundColor(.white)
                    }
                    
                    Text(step == .create ? "Create Passcode" : "Confirm Passcode")
                        .font(HawalaTheme.Typography.h2)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    
                    Text(step == .create ? "Choose a 4-6 digit passcode" : "Enter your passcode again")
                        .font(HawalaTheme.Typography.body)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
                
                // Passcode dots
                HStack(spacing: HawalaTheme.Spacing.md) {
                    ForEach(0..<maxDigits, id: \.self) { index in
                        Circle()
                            .fill(index < currentPasscode.count ? HawalaTheme.Colors.accent : HawalaTheme.Colors.border)
                            .frame(width: 16, height: 16)
                    }
                }
                .modifier(ShakeEffect(shakes: isShaking ? 2 : 0))
                .animation(.easeInOut(duration: 0.4), value: isShaking)
                
                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(HawalaTheme.Typography.bodySmall)
                        .foregroundColor(HawalaTheme.Colors.error)
                        .padding(.top, HawalaTheme.Spacing.sm)
                }
                
                Spacer()
                
                // Number pad
                VStack(spacing: HawalaTheme.Spacing.md) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: HawalaTheme.Spacing.lg) {
                            ForEach(1...3, id: \.self) { col in
                                let number = row * 3 + col
                                PasscodeButton(number: "\(number)") {
                                    appendDigit("\(number)")
                                }
                            }
                        }
                    }
                    
                    HStack(spacing: HawalaTheme.Spacing.lg) {
                        // Skip button (only on create step)
                        if step == .create {
                            PasscodeButton(number: "", icon: "xmark") {
                                onSkip()
                            }
                            .opacity(0.7)
                        } else {
                            // Back button
                            PasscodeButton(number: "", icon: "arrow.left") {
                                step = .create
                                confirmPasscode = ""
                                errorMessage = nil
                            }
                        }
                        
                        PasscodeButton(number: "0") {
                            appendDigit("0")
                        }
                        
                        PasscodeButton(number: "", icon: "delete.left.fill") {
                            deleteDigit()
                        }
                    }
                }
                .padding(.horizontal, HawalaTheme.Spacing.xxl)
                
                // Skip text (only on create step)
                if step == .create {
                    Button(action: onSkip) {
                        Text("Skip for now")
                            .font(HawalaTheme.Typography.body)
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, HawalaTheme.Spacing.md)
                }
                
                Spacer()
            }
            .padding(HawalaTheme.Spacing.xl)
        }
    }
    
    private var currentPasscode: String {
        step == .create ? passcode : confirmPasscode
    }
    
    private func appendDigit(_ digit: String) {
        guard currentPasscode.count < maxDigits else { return }
        
        errorMessage = nil
        
        if step == .create {
            passcode += digit
            
            // Move to confirm when we have at least 4 digits
            if passcode.count >= 4 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    step = .confirm
                }
            }
        } else {
            confirmPasscode += digit
            
            // Check match when we have same length as original
            if confirmPasscode.count == passcode.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    verifyAndSave()
                }
            }
        }
    }
    
    private func deleteDigit() {
        if step == .create && !passcode.isEmpty {
            passcode.removeLast()
        } else if step == .confirm && !confirmPasscode.isEmpty {
            confirmPasscode.removeLast()
        }
        errorMessage = nil
    }
    
    private func verifyAndSave() {
        if confirmPasscode == passcode {
            // Save passcode
            if passcodeManager.setPasscode(passcode) {
                onComplete()
            } else {
                errorMessage = "Failed to save passcode"
                confirmPasscode = ""
            }
        } else {
            errorMessage = "Passcodes don't match"
            isShaking = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                isShaking = false
                confirmPasscode = ""
            }
        }
    }
}

// MARK: - Passcode Button

struct PasscodeButton: View {
    let number: String
    var icon: String? = nil
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            withAnimation(.easeOut(duration: 0.1)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
                action()
            }
        }) {
            ZStack {
                Circle()
                    .fill(isPressed ? HawalaTheme.Colors.accent.opacity(0.3) : HawalaTheme.Colors.backgroundSecondary)
                    .frame(width: 72, height: 72)
                
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                } else if !number.isEmpty {
                    Text(number)
                        .font(.system(size: 32, weight: .medium, design: .rounded))
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(number.isEmpty && icon == nil)
        .opacity(number.isEmpty && icon == nil ? 0 : 1)
    }
}

// MARK: - Shake Effect

struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }
    
    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = sin(shakes * .pi * 2) * 10
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

// MARK: - Preview

#Preview("Lock Screen") {
    PasscodeLockScreen(onUnlock: {})
}

#Preview("Setup Screen") {
    PasscodeSetupScreen(onComplete: {}, onSkip: {})
}
