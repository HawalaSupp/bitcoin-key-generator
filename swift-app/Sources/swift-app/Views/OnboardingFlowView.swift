import SwiftUI
import LocalAuthentication
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Onboarding Flow View
/// A premium onboarding experience matching Hawala's main app design
/// Features: Silk background, glass cards, keyboard PIN entry, smooth animations

struct OnboardingFlowView: View {
    @Binding var isOnboardingComplete: Bool
    var onGenerateWallet: () async -> Void
    
    @AppStorage("hawala.onboardingCompleted") private var onboardingCompleted = false
    @AppStorage("hawala.biometricsEnabled") private var biometricsEnabled = false
    @AppStorage("hawala.passcode") private var storedPasscode = ""
    
    @State private var currentStep: OnboardingStep = .welcome
    @State private var passcode: String = ""
    @State private var confirmPasscode: String = ""
    @State private var isConfirmingPasscode = false
    @State private var showPasscodeError = false
    @State private var errorMessage = ""
    @State private var isCreatingWallet = false
    @State private var showSuccess = false
    @State private var animateContent = false
    
    enum OnboardingStep: Int, CaseIterable {
        case welcome = 0
        case security = 1
        case passcode = 2
        case biometrics = 3
        case complete = 4
    }
    
    var body: some View {
        ZStack {
            // Silk background - same as main app
            SilkBackground(
                speed: 5.0,
                scale: 1.0,
                color: "#7B7481",
                noiseIntensity: 1.5,
                rotation: 0.0
            )
            .ignoresSafeArea()
            
            // Dark overlay for readability
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Step indicator
                stepIndicator
                    .padding(.top, 60)
                    .padding(.bottom, 40)
                
                // Content
                Group {
                    switch currentStep {
                    case .welcome:
                        welcomeView
                    case .security:
                        securityView
                    case .passcode:
                        passcodeView
                    case .biometrics:
                        biometricsView
                    case .complete:
                        completeView
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .center)),
                    removal: .opacity.combined(with: .scale(scale: 1.02, anchor: .center))
                ))
                .animation(.easeInOut(duration: 0.45), value: currentStep)
                
                Spacer()
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                animateContent = true
            }
        }
    }
    
    // MARK: - Step Indicator
    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<5) { index in
                Circle()
                    .fill(index <= currentStep.rawValue ? Color.white : Color.white.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .scaleEffect(index == currentStep.rawValue ? 1.2 : 1.0)
                    .animation(.spring(response: 0.3), value: currentStep)
            }
        }
    }
    
    // MARK: - Welcome View
    private var welcomeView: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 12) {
                Text("WELCOME TO HAWALA")
                    .font(.custom("ClashGrotesk-Bold", size: 36))
                    .foregroundColor(.white)
                    .tracking(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                
                Text("Your gateway to digital assets")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
            }
            .opacity(animateContent ? 1 : 0)
            .offset(y: animateContent ? 0 : 20)
            .animation(.easeOut(duration: 0.6).delay(0.2), value: animateContent)
            
            Spacer()
            
            // Continue button
            primaryButton("Get Started") {
                withAnimation(.easeInOut(duration: 0.45)) {
                    currentStep = .security
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 50)
            .opacity(animateContent ? 1 : 0)
            .animation(.easeOut(duration: 0.6).delay(0.4), value: animateContent)
        }
    }
    
    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
        }
    }
    
    // MARK: - Security View
    private var securityView: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 10) {
                Text("Security, owned by you")
                    .font(.custom("ClashGrotesk-Bold", size: 28))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text("Your wallet is created locally and protected by device-level security. We never see or store your keys.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 24)
            }
            
            Spacer()
            
            VStack(spacing: 14) {
                securityInfoCard(
                    title: "Device-secured access",
                    detail: "Unlock with your passcode or biometrics. Your data stays on this Mac."
                )
                
                securityInfoCard(
                    title: "Private by default",
                    detail: "No accounts, no tracking, and no data shared with third parties."
                )
                
                securityInfoCard(
                    title: "Recoverability matters",
                    detail: "You control recovery. Backups are never uploaded automatically."
                )
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            primaryButton("I Understand") {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    currentStep = .passcode
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 50)
        }
    }
    
    private func securityRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 24)
            
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
            
            Spacer()
            
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color(hex: "#32D74B"))
        }
    }

    private func securityInfoCard(title: String, detail: String) -> some View {
        glassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(detail)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
    }
    
    // MARK: - Passcode View
    private var passcodeView: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 12) {
                Text(isConfirmingPasscode ? "Confirm Passcode" : "Create Passcode")
                    .font(.custom("ClashGrotesk-Bold", size: 28))
                    .foregroundColor(.white)
                
                Text(isConfirmingPasscode ? "Enter your passcode again" : "Type 6 digits on your keyboard")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            // PIN dots display
            HStack(spacing: 16) {
                ForEach(0..<6) { index in
                    let currentPasscode = isConfirmingPasscode ? confirmPasscode : passcode
                    let isFilled = index < currentPasscode.count
                    
                    ZStack {
                        Circle()
                            .stroke(showPasscodeError ? Color.red.opacity(0.5) : Color.white.opacity(0.2), lineWidth: 2)
                            .frame(width: 20, height: 20)
                        
                        if isFilled {
                            Circle()
                                .fill(showPasscodeError ? Color.red : Color.white)
                                .frame(width: 20, height: 20)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.2), value: isFilled)
                    .modifier(ShakeEffect(shakes: showPasscodeError ? 3.0 : 0.0))
                }
            }
            .padding(.vertical, 32)
            
            // Error message
            if showPasscodeError {
                Text(errorMessage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.red)
                    .transition(.opacity)
            }
            
            Spacer()
            
            // Keyboard hint
            glassCard {
                HStack(spacing: 12) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Text("Press number keys 0-9 to enter PIN")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(16)
            }
            .padding(.horizontal, 40)
            
            Spacer()
            

            // Keyboard handling - Hidden view that accepts focus
            KeyboardInputView(isActive: currentStep == .passcode) { event in
                handleKeyEvent(event)
            }
            .frame(width: 1, height: 1)
            .opacity(0)
            
            HStack(spacing: 16) {
                // Back button
                secondaryButton("Back") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        if isConfirmingPasscode {
                            isConfirmingPasscode = false
                            confirmPasscode = ""
                        } else {
                            currentStep = .security
                        }
                    }
                }
                
                // Clear button
                secondaryButton("Clear") {
                    withAnimation {
                        if isConfirmingPasscode {
                            confirmPasscode = ""
                        } else {
                            passcode = ""
                        }
                        showPasscodeError = false
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 50)
        }
    }
    
    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard currentStep == .passcode else {
            return false
        }
        let chars = event.charactersIgnoringModifiers ?? ""
        
        // Handle backspace/delete
        if event.keyCode == 51 { // Delete key
            withAnimation(.spring(response: 0.2)) {
                if isConfirmingPasscode {
                    if !confirmPasscode.isEmpty {
                        confirmPasscode.removeLast()
                    }
                } else {
                    if !passcode.isEmpty {
                        passcode.removeLast()
                    }
                }
                showPasscodeError = false
            }
            return true
        }
        
        // Handle number keys
        if let char = chars.first, char.isNumber {
            withAnimation(.spring(response: 0.2)) {
                if isConfirmingPasscode {
                    if confirmPasscode.count < 6 {
                        confirmPasscode.append(char)
                        if confirmPasscode.count == 6 {
                            validateConfirmPasscode()
                        }
                    }
                } else {
                    if passcode.count < 6 {
                        passcode.append(char)
                        if passcode.count == 6 {
                            // Move to confirm after brief delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    isConfirmingPasscode = true
                                }
                            }
                        }
                    }
                }
            }
            return true
        }
        
        // Not a key we handle
        return false
    }
    
    private func handlePasscodeChange(_ newValue: String, isConfirm: Bool) {
        // Filter to only digits
        let filtered = newValue.filter { $0.isNumber }
        
        if isConfirm {
            if filtered.count <= 6 {
                confirmPasscode = filtered
            } else {
                confirmPasscode = String(filtered.prefix(6))
            }
            
            if confirmPasscode.count == 6 {
                validateConfirmPasscode()
            }
        } else {
            if filtered.count <= 6 {
                passcode = filtered
            } else {
                passcode = String(filtered.prefix(6))
            }
            
            if passcode.count == 6 {
                // Move to confirm
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isConfirmingPasscode = true
                    }
                }
            }
        }
        
        showPasscodeError = false
    }
    
    private func validateConfirmPasscode() {
        if confirmPasscode == passcode {
            storedPasscode = passcode
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                currentStep = .biometrics
            }
        } else {
            withAnimation {
                showPasscodeError = true
                errorMessage = "Passcodes don't match"
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation {
                    confirmPasscode = ""
                    showPasscodeError = false
                }
            }
        }
    }
    
    // MARK: - Biometrics View
    private var biometricsView: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Face ID / Touch ID icon
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 100, height: 100)
                
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    .frame(width: 100, height: 100)
                
                Image(systemName: biometricType == .faceID ? "faceid" : "touchid")
                    .font(.system(size: 44, weight: .light))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 12) {
                Text("Enable \(biometricType == .faceID ? "Face ID" : "Touch ID")")
                    .font(.custom("ClashGrotesk-Bold", size: 28))
                    .foregroundColor(.white)
                
                Text("Quickly access your wallet with biometric authentication")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            Spacer()
            
            glassCard {
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "lock.open.fill")
                            .foregroundColor(.white.opacity(0.8))
                        Text("Faster access to your wallet")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                        Spacer()
                    }
                    
                    HStack {
                        Image(systemName: "hand.raised.fill")
                            .foregroundColor(.white.opacity(0.8))
                        Text("Passcode remains as backup")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                        Spacer()
                    }
                }
                .padding(20)
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            VStack(spacing: 12) {
                primaryButton("Enable \(biometricType == .faceID ? "Face ID" : "Touch ID")") {
                    biometricsEnabled = true
                    createWallet()
                }
                
                Button(action: {
                    biometricsEnabled = false
                    createWallet()
                }) {
                    Text("Skip for now")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 50)
        }
    }
    
    private var biometricType: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }
    
    // MARK: - Complete View
    private var completeView: some View {
        VStack(spacing: 32) {
            Spacer()
            
            if isCreatingWallet {
                // Loading state
                VStack(spacing: 24) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    
                    Text("Creating your wallet...")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
            } else if showSuccess {
                // Success state
                ZStack {
                    Circle()
                        .fill(Color(hex: "#32D74B").opacity(0.2))
                        .frame(width: 120, height: 120)
                    
                    Circle()
                        .stroke(Color(hex: "#32D74B").opacity(0.5), lineWidth: 2)
                        .frame(width: 120, height: 120)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundColor(Color(hex: "#32D74B"))
                }
                .transition(.scale.combined(with: .opacity))
                
                VStack(spacing: 12) {
                    Text("You're All Set!")
                        .font(.custom("ClashGrotesk-Bold", size: 32))
                        .foregroundColor(.white)
                    
                    Text("Your wallet is ready. Welcome to Hawala.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.white.opacity(0.6))
                }
                .transition(.opacity)
                
                Spacer()
                
                primaryButton("Enter Hawala") {
                    onboardingCompleted = true
                    isOnboardingComplete = true
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 50)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            Spacer()
        }
    }
    
    private func createWallet() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentStep = .complete
            isCreatingWallet = true
        }
        
        Task {
            await onGenerateWallet()
            
            await MainActor.run {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    isCreatingWallet = false
                    showSuccess = true
                }
            }
        }
    }
    
    // MARK: - UI Components
    
    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
    
    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.15))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
    
    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// Note: ShakeEffect is defined in PasscodeLockScreen.swift
// Note: Preview uses the existing ShakeEffect from there

// MARK: - Keyboard Input Helper
#if os(macOS)
struct KeyboardInputView: NSViewRepresentable {
    var isActive: Bool
    var onKeyDown: (NSEvent) -> Bool
    
    func makeNSView(context: Context) -> KeyInputNSView {
        let view = KeyInputNSView()
        view.onKeyDown = onKeyDown
        view.isActive = isActive
        view.focusIfNeeded()
        return view
    }
    
    func updateNSView(_ nsView: KeyInputNSView, context: Context) {
        nsView.onKeyDown = onKeyDown
        nsView.isActive = isActive
        nsView.focusIfNeeded()
    }
}

class KeyInputNSView: NSView {
    var onKeyDown: ((NSEvent) -> Bool)?
    var isActive: Bool = false
    
    override var acceptsFirstResponder: Bool { isActive }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusIfNeeded()
    }
    
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        focusIfNeeded()
    }
    
    func focusIfNeeded() {
        guard isActive, let window = window else { return }
        if window.firstResponder !== self {
            window.makeFirstResponder(self)
        }
    }
    
    override func keyDown(with event: NSEvent) {
        guard isActive else {
            super.keyDown(with: event)
            return
        }
        if let onKeyDown = onKeyDown, onKeyDown(event) {
            return
        }
        super.keyDown(with: event)
    }
}
#endif
