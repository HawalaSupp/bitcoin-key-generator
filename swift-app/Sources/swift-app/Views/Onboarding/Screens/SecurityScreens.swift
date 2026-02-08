import SwiftUI
import LocalAuthentication
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Security Setup Screen
/// Combined PIN, biometric, and backup setup
struct SecuritySetupScreen: View {
    @Binding var passcode: String
    @Binding var confirmPasscode: String
    @Binding var isConfirmingPasscode: Bool
    @Binding var biometricsEnabled: Bool
    @Binding var iCloudBackupEnabled: Bool
    @Binding var showError: Bool
    @Binding var errorMessage: String
    
    let onComplete: () -> Void
    let onBack: () -> Void
    
    @State private var animateContent = false
    @State private var isKeyboardActive = true
    // ROADMAP-02: Track passcode mismatch attempts for better UX
    @State private var mismatchAttempts: Int = 0
    private let maxMismatchAttempts = 3
    
    private var currentPasscode: String {
        isConfirmingPasscode ? confirmPasscode : passcode
    }
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Title
            VStack(spacing: 12) {
                Text(isConfirmingPasscode ? "Confirm Passcode" : "Create Passcode")
                    .font(.custom("ClashGrotesk-Bold", size: 28))
                    .foregroundColor(.white)
                
                Text(isConfirmingPasscode ? "Enter your passcode again" : "Type 6 digits on your keyboard")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
            }
            .opacity(animateContent ? 1 : 0)
            
            // PIN dots
            HStack(spacing: 16) {
                ForEach(0..<6, id: \.self) { index in
                    PasscodeDot(
                        isFilled: index < currentPasscode.count,
                        hasError: showError
                    )
                }
            }
            .modifier(ShakeEffect(shakes: showError ? 3.0 : 0.0))
            .padding(.vertical, 32)
            .coachmarkAnchor(.passcodeEntry)
            .onChange(of: currentPasscode.count) { newCount in
                // Provide feedback for each digit
                if newCount > 0 && newCount <= 6 {
                    FeedbackManager.shared.trigger(.keyPress)
                }
            }
            
            // Error message
            if showError {
                VStack(spacing: 8) {
                    Text(errorMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                        .transition(.opacity)
                    
                    // ROADMAP-02: After N mismatches, offer to start passcode over
                    if mismatchAttempts >= maxMismatchAttempts {
                        Button(action: resetPasscodeEntry) {
                            Text("Start Over — Create New Passcode")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.orange)
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            
            Spacer()
            
            // Keyboard hint
            OnboardingCard(padding: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.6))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Press number keys 0-9 to enter PIN")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                        
                        Text("Backspace to delete")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            }
            .frame(maxWidth: 400)
            .opacity(animateContent ? 1 : 0)
            
            // Toggles (only show after passcode is set, before biometrics)
            if !isConfirmingPasscode && passcode.isEmpty {
                VStack(spacing: 8) {
                    OnboardingToggleRow(
                        title: "Back up to iCloud",
                        description: "Encrypted with your Apple ID",
                        isOn: $iCloudBackupEnabled,
                        icon: "icloud.fill"
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .opacity(animateContent ? 1 : 0)
            }
            
            Spacer()
            
            // Keyboard input handler
            #if os(macOS)
            OnboardingKeyboardHandler(isActive: isKeyboardActive) { event in
                handleKeyEvent(event)
            }
            .frame(width: 1, height: 1)
            .opacity(0)
            #endif
            
            // Navigation buttons
            HStack(spacing: 16) {
                OnboardingSecondaryButton(title: "Back", icon: "chevron.left", action: handleBack)
                
                OnboardingSecondaryButton(title: "Clear", icon: "xmark", action: handleClear)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 50)
            .opacity(animateContent ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                animateContent = true
            }
        }
    }
    
    #if os(macOS)
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let chars = event.charactersIgnoringModifiers ?? ""
        
        // Handle backspace/delete
        if event.keyCode == 51 {
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
                showError = false
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
                            validateAndComplete()
                        }
                    }
                } else {
                    if passcode.count < 6 {
                        passcode.append(char)
                        if passcode.count == 6 {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                withAnimation(.spring(response: 0.4)) {
                                    isConfirmingPasscode = true
                                }
                            }
                        }
                    }
                }
            }
            return true
        }
        
        return false
    }
    #endif
    
    private func validateAndComplete() {
        if confirmPasscode == passcode {
            FeedbackManager.shared.trigger(.success)
            mismatchAttempts = 0
            onComplete()
        } else {
            FeedbackManager.shared.trigger(.error)
            mismatchAttempts += 1
            withAnimation {
                showError = true
                if mismatchAttempts >= maxMismatchAttempts {
                    errorMessage = "Passcodes don't match — \(mismatchAttempts) failed attempts"
                } else {
                    let remaining = maxMismatchAttempts - mismatchAttempts
                    errorMessage = "Passcodes don't match — \(remaining) attempt\(remaining == 1 ? "" : "s") left"
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation {
                    confirmPasscode = ""
                    if mismatchAttempts < maxMismatchAttempts {
                        showError = false
                    }
                    // Keep error visible when max attempts reached so user sees "Start Over"
                }
            }
        }
    }
    
    /// ROADMAP-02: Reset entire passcode entry after too many mismatches
    private func resetPasscodeEntry() {
        withAnimation(.spring(response: 0.4)) {
            passcode = ""
            confirmPasscode = ""
            isConfirmingPasscode = false
            mismatchAttempts = 0
            showError = false
            errorMessage = ""
        }
    }
    
    private func handleBack() {
        withAnimation(.spring(response: 0.4)) {
            if isConfirmingPasscode {
                isConfirmingPasscode = false
                confirmPasscode = ""
            } else {
                onBack()
            }
        }
    }
    
    private func handleClear() {
        withAnimation {
            if isConfirmingPasscode {
                confirmPasscode = ""
            } else {
                passcode = ""
            }
            showError = false
        }
    }
}

struct PasscodeDot: View {
    let isFilled: Bool
    let hasError: Bool
    
    var body: some View {
        ZStack {
            // Glow effect when filled
            if isFilled && !hasError {
                Circle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 28, height: 28)
                    .blur(radius: 6)
            }
            
            Circle()
                .stroke(hasError ? Color.red.opacity(0.5) : Color.white.opacity(0.3), lineWidth: 2)
                .frame(width: 18, height: 18)
            
            if isFilled {
                Circle()
                    .fill(hasError ? Color.red : Color.white)
                    .frame(width: 18, height: 18)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 28, height: 28)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isFilled)
    }
}

// MARK: - Biometrics Setup Screen
/// Touch ID setup screen
struct BiometricsSetupScreen: View {
    @Binding var biometricsEnabled: Bool
    let onEnable: () -> Void
    let onSkip: () -> Void
    
    @State private var animateContent = false
    @State private var animateIcon = false
    
    private var biometricType: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }
    
    private var biometricName: String {
        biometricType == .touchID ? "Touch ID" : "Biometric"
    }
    
    private var biometricIcon: String {
        biometricType == .touchID ? "touchid" : "faceid"
    }
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Icon
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 120, height: 120)
                
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    .frame(width: 120, height: 120)
                    .scaleEffect(animateIcon ? 1.1 : 1.0)
                    .opacity(animateIcon ? 0 : 1)
                    .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: animateIcon)
                
                Image(systemName: biometricIcon)
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(.white)
            }
            .opacity(animateContent ? 1 : 0)
            .scaleEffect(animateContent ? 1 : 0.9)
            
            // Title
            VStack(spacing: 12) {
                Text("Enable \(biometricName)")
                    .font(.custom("ClashGrotesk-Bold", size: 28))
                    .foregroundColor(.white)
                
                Text("Quickly access your wallet with biometric authentication")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .opacity(animateContent ? 1 : 0)
            
            Spacer()
            
            // Benefits
            OnboardingCard(padding: 20) {
                VStack(spacing: 16) {
                    BiometricBenefitRow(
                        icon: "lock.open.fill",
                        text: "Faster access to your wallet"
                    )
                    
                    BiometricBenefitRow(
                        icon: "hand.raised.fill",
                        text: "Passcode remains as backup"
                    )
                    
                    BiometricBenefitRow(
                        icon: "checkmark.shield.fill",
                        text: "Secure device-level authentication"
                    )
                }
            }
            .frame(maxWidth: 400)
            .padding(.horizontal, 24)
            .opacity(animateContent ? 1 : 0)
            
            Spacer()
            
            // Buttons
            VStack(spacing: 12) {
                OnboardingPrimaryButton(
                    title: "Enable \(biometricName)",
                    action: {
                        FeedbackManager.shared.trigger(.success)
                        biometricsEnabled = true
                        onEnable()
                    },
                    style: .filled
                )
                
                OnboardingSecondaryButton(title: "Skip for now", action: onSkip)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 50)
            .opacity(animateContent ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                animateContent = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                animateIcon = true
            }
        }
    }
}

struct BiometricBenefitRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 24)
            
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
            
            Spacer()
        }
    }
}

// MARK: - Power Settings Screen
/// Advanced settings for power users (Quick path)
struct PowerSettingsScreen: View {
    @Binding var selectedChains: Set<String>
    @Binding var developerModeEnabled: Bool
    
    var enableTestnet: Binding<Bool>?
    var enableTransactionSimulation: Binding<Bool>?
    var enableMEVProtection: Binding<Bool>?
    var enableGasSponsorship: Binding<Bool>?
    var enableWalletConnectAutoAccept: Binding<Bool>?
    
    let onContinue: () -> Void
    var onSkip: (() -> Void)?
    var onBack: (() -> Void)?
    
    @State private var animateContent = false
    @State private var _enableTestnet = false
    @State private var _enableTransactionSimulation = true
    @State private var _enableMEVProtection = true
    @State private var _enableGasSponsorship = true
    @State private var _enableWalletConnectAutoAccept = false
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 40)
            
            // Header
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 72, height: 72)
                    
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.white)
                }
                .opacity(animateContent ? 1 : 0)
                .scaleEffect(animateContent ? 1 : 0.8)
                
                Text("Customize Your Wallet")
                    .font(.custom("ClashGrotesk-Bold", size: 26))
                    .foregroundColor(.white)
                
                Text("Fine-tune your experience. All settings can be changed later.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .opacity(animateContent ? 1 : 0)
            
            Spacer()
                .frame(height: 32)
            
            // Settings cards in a scrollable area
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Networks Section
                    SettingsSectionCard(title: "Networks", icon: "network") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Select which blockchains to enable")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.5))
                            
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                                ForEach(OnboardingChain.all, id: \.id) { chain in
                                    ChainChip(
                                        chain: chain,
                                        isSelected: selectedChains.contains(chain.id),
                                        onTap: {
                                            if selectedChains.contains(chain.id) {
                                                selectedChains.remove(chain.id)
                                            } else {
                                                selectedChains.insert(chain.id)
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .staggeredFadeIn(index: 0, isVisible: animateContent)
                    
                    // Security Section
                    SettingsSectionCard(title: "Security", icon: "shield.lefthalf.filled") {
                        VStack(spacing: 0) {
                            CompactToggleRow(
                                title: "Transaction Simulation",
                                description: "Preview outcomes before signing",
                                icon: "eye",
                                isOn: enableTransactionSimulation ?? $_enableTransactionSimulation
                            )
                            
                            Divider().background(Color.white.opacity(0.06))
                            
                            CompactToggleRow(
                                title: "MEV Protection",
                                description: "Protect against front-running",
                                icon: "shield.checkered",
                                isOn: enableMEVProtection ?? $_enableMEVProtection
                            )
                        }
                    }
                    .staggeredFadeIn(index: 1, isVisible: animateContent)
                    
                    // Advanced Section
                    SettingsSectionCard(title: "Advanced", icon: "wrench.and.screwdriver") {
                        VStack(spacing: 0) {
                            CompactToggleRow(
                                title: "Testnet Mode",
                                description: "Access test networks",
                                icon: "flask",
                                isOn: enableTestnet ?? $_enableTestnet
                            )
                            
                            Divider().background(Color.white.opacity(0.06))
                            
                            CompactToggleRow(
                                title: "Gas Sponsorship",
                                description: "Use sponsored transactions",
                                icon: "dollarsign.circle",
                                isOn: enableGasSponsorship ?? $_enableGasSponsorship
                            )
                            
                            Divider().background(Color.white.opacity(0.06))
                            
                            CompactToggleRow(
                                title: "Auto-accept Trusted dApps",
                                description: "Skip prompts for known dApps",
                                icon: "link",
                                isOn: enableWalletConnectAutoAccept ?? $_enableWalletConnectAutoAccept
                            )
                        }
                    }
                    .staggeredFadeIn(index: 2, isVisible: animateContent)
                }
                .padding(.horizontal, 24)
            }
            
            Spacer()
            
            // Buttons
            VStack(spacing: 12) {
                OnboardingPrimaryButton(title: "Continue", action: onContinue, style: .filled)
                
                if let skip = onSkip {
                    OnboardingSecondaryButton(title: "Use defaults", action: skip)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .opacity(animateContent ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                animateContent = true
            }
        }
    }
}

// MARK: - Settings Section Card
struct SettingsSectionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            
            content
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

// MARK: - Compact Toggle Row
struct CompactToggleRow: View {
    let title: String
    let description: String
    let icon: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: Color(hex: "#32D74B")))
                .labelsHidden()
                .scaleEffect(0.85)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Chain Chip
struct ChainChip: View {
    let chain: OnboardingChain
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: chain.icon)
                    .font(.system(size: 12, weight: .medium))
                
                Text(chain.name)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.white.opacity(0.15) : Color.white.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.white.opacity(0.3) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ready Screen
/// Final screen showing success and wallet address
struct ReadyScreen: View {
    let walletAddress: String
    let securityScore: SecurityScore
    let onEnterWallet: () -> Void
    
    @State private var animateContent = false
    @State private var showConfetti = false
    @State private var showCheckmark = false
    @State private var isLoading = false
    @State private var loadingProgress: CGFloat = 0
    
    var body: some View {
        ZStack {
            // Main content
            if !isLoading {
                mainContent
            } else {
                // Loading state
                loadingContent
            }
            
            // Confetti overlay
            if showConfetti && !isLoading {
                OnboardingConfettiView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Trigger confetti and checkmark
            showConfetti = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showCheckmark = true
            }
            
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.4)) {
                animateContent = true
            }
        }
    }
    
    private var mainContent: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Animated success state
            VStack(spacing: 24) {
                // Animated checkmark
                if showCheckmark {
                    OnboardingAnimatedCheckmark(size: 80)
                }
                
                VStack(spacing: 8) {
                    Text("You're all set")
                        .font(.custom("ClashGrotesk-Bold", size: 32))
                        .foregroundColor(.white)
                    
                    Text("Your wallet is ready. Welcome to Hawala.")
                        .font(.custom("ClashGrotesk-Regular", size: 16))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .opacity(animateContent ? 1 : 0)
            .scaleEffect(animateContent ? 1 : 0.9)
            
            // Address display
            AddressDisplayCard(
                address: walletAddress,
                onCopy: {
                    // Haptic feedback
                    #if canImport(AppKit)
                    OnboardingHaptics.success()
                    #endif
                }
            )
            .frame(maxWidth: 400)
            .padding(.horizontal, 24)
            .opacity(animateContent ? 1 : 0)
            .offset(y: animateContent ? 0 : 10)
            
            Spacer()
            
            // Security score teaser
            OnboardingCard(padding: 16) {
                HStack(spacing: 16) {
                    SecurityScoreRing(score: securityScore.score, maxScore: securityScore.maxScore, size: 60, lineWidth: 4)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Security Score: \(securityScore.score)/\(securityScore.maxScore)")
                            .font(.custom("ClashGrotesk-Semibold", size: 14))
                            .foregroundColor(.white)
                        
                        if let pending = securityScore.pendingItems.first {
                            Text("\(pending.title) to reach \(securityScore.score + pending.points) →")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    
                    Spacer()
                }
            }
            .frame(maxWidth: 400)
            .padding(.horizontal, 24)
            .opacity(animateContent ? 1 : 0)
            .staggeredFadeIn(index: 2, isVisible: animateContent)
            
            Spacer()
            
            // Enter wallet button
            VStack(spacing: 12) {
                OnboardingPrimaryButton(title: "Start Using Hawala", action: {
                    startLoading()
                }, style: .filled)
                
                HStack(spacing: 6) {
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    Text("to continue")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 50)
            .opacity(animateContent ? 1 : 0)
        }
    }
    
    private var loadingContent: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Loading animation
            VStack(spacing: 24) {
                ZStack {
                    // Outer ring
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 4)
                        .frame(width: 80, height: 80)
                    
                    // Progress ring
                    Circle()
                        .trim(from: 0, to: loadingProgress)
                        .stroke(
                            LinearGradient(
                                colors: [Color(hex: "#00D4FF"), Color(hex: "#32D74B")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                    
                    // Inner icon
                    Image(systemName: "wallet.pass.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.white)
                        .opacity(loadingProgress > 0.5 ? 1 : 0.5)
                }
                
                VStack(spacing: 8) {
                    Text("Setting up your wallet...")
                        .font(.custom("ClashGrotesk-Semibold", size: 20))
                        .foregroundColor(.white)
                    
                    Text(loadingStageText)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.5))
                        .animation(.easeInOut(duration: 0.2), value: loadingProgress)
                }
            }
            
            Spacer()
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
    
    private var loadingStageText: String {
        if loadingProgress < 0.3 {
            return "Generating keys..."
        } else if loadingProgress < 0.6 {
            return "Securing your wallet..."
        } else if loadingProgress < 0.9 {
            return "Syncing with networks..."
        } else {
            return "Almost ready..."
        }
    }
    
    private func startLoading() {
        withAnimation(.easeOut(duration: 0.3)) {
            isLoading = true
        }
        
        // Animate progress
        let totalDuration: Double = 2.0
        let steps = 20
        let stepDuration = totalDuration / Double(steps)
        
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(i)) {
                withAnimation(.easeInOut(duration: stepDuration)) {
                    loadingProgress = CGFloat(i) / CGFloat(steps)
                }
                
                if i == steps {
                    // Complete after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        #if canImport(AppKit)
                        OnboardingHaptics.success()
                        #endif
                        FeedbackManager.shared.trigger(.success)
                        onEnterWallet()
                    }
                }
            }
        }
    }
}

// MARK: - Onboarding Shake Effect
struct OnboardingShakeEffect: GeometryEffect {
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
#if DEBUG
struct SecurityScreens_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ReadyScreen(
                walletAddress: "0x7a3B8c9D2E4f5A6b7C8d9E0f1A2B3C4D5E6F7890",
                securityScore: SecurityScore(
                    biometricEnabled: true,
                    pinCreated: true,
                    backupCompleted: true,
                    backupVerified: false,
                    guardiansAdded: false,
                    twoFactorEnabled: false
                ),
                onEnterWallet: {}
            )
        }
        .preferredColorScheme(.dark)
    }
}
#endif
