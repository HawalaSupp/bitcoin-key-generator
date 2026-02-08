import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
import LocalAuthentication

// MARK: - New Onboarding Flow View
/// Main coordinator view that orchestrates the complete onboarding experience
struct NewOnboardingFlowView: View {
    @StateObject private var state = OnboardingState()
    @StateObject private var importManager = WalletImportManager.shared
    @StateObject private var coachmarkManager = CoachmarkManager.shared
    @State private var isAppearing = false
    
    /// Callback when onboarding completes
    var onComplete: ((WalletCreationResult) -> Void)?
    
    var body: some View {
        ZStack {
            // Background gradient
            backgroundGradient
            
            // Current screen
            VStack(spacing: 0) {
                // Progress indicator (except for welcome and ready screens)
                if shouldShowProgress {
                    OnboardingProgressIndicator(
                        currentStep: progressStep,
                        totalSteps: totalSteps
                    )
                    .padding(.top, 20)
                    .padding(.horizontal, 24)
                }
                
                currentScreen
                    .id(state.currentStep)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .animation(.easeInOut(duration: 0.4), value: state.currentStep)
            }
        }
        .frame(minWidth: 700, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)
        .opacity(isAppearing ? 1 : 0)
        .coachmarkOverlay()
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                isAppearing = true
            }
            // Show welcome coachmark on first launch
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                coachmarkManager.showIfNeeded(.welcomeSwipe)
            }
        }
    }
    
    // MARK: - Progress Indicator Logic
    
    private var shouldShowProgress: Bool {
        switch state.currentStep {
        case .welcome, .ready:
            return false
        default:
            return true
        }
    }
    
    private var totalSteps: Int {
        state.selectedPath == .quick ? 4 : 6
    }
    
    private var progressStep: Int {
        switch state.currentStep {
        case .welcome: return 0
        case .pathSelection: return 1
        case .selfCustodyEducation: return 1
        case .personaSelection: return 2
        case .createOrImport: return 2
        case .recoveryPhraseDisplay, .recoveryPhraseInput: return 3
        case .verifyBackup: return 4
        case .guardianSetup: return 5
        case .securitySetup, .biometricsSetup: return state.selectedPath == .quick ? 3 : 5
        case .powerSettings: return state.selectedPath == .quick ? 4 : 6
        case .practiceMode: return 6
        case .ready: return totalSteps
        default: return 2
        }
    }
    
    // MARK: - Background
    private var backgroundGradient: some View {
        ZStack {
            // Base dark background (fallback)
            Color(hex: "#0D0D0D")
            
            // Silk background - consistent with main app
            SilkBackground(
                speed: 5.0,
                scale: 1.0,
                color: "#7B7481",
                noiseIntensity: 1.5,
                rotation: 0.0
            )
            
            // Dark overlay for readability
            Color.black.opacity(0.35)
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Screen Router
    @ViewBuilder
    private var currentScreen: some View {
        switch state.currentStep {
        case .welcome:
            WelcomeScreen(
                onContinue: { state.navigateTo(.pathSelection) }
            )
            
        case .pathSelection:
            PathSelectionScreen(
                useQuickSetup: Binding(
                    get: { state.selectedPath == .quick },
                    set: { state.selectedPath = $0 ? .quick : .guided }
                ),
                onCreateNew: {
                    state.selectedCreationMethod = .create
                    if state.selectedPath == .quick {
                        generateAndNavigateToRecoveryPhrase()
                    } else {
                        state.navigateTo(.selfCustodyEducation)
                    }
                },
                onImport: {
                    state.selectedCreationMethod = .importSeed
                    // Navigate to import method selection for full import options
                    state.navigateTo(.importMethodSelection)
                },
                onHardware: {
                    state.selectedCreationMethod = .ledger
                    if state.selectedPath == .quick {
                        state.navigateTo(.hardwareWalletConnect)
                    } else {
                        state.navigateTo(.selfCustodyEducation)
                    }
                }
            )
            
        case .selfCustodyEducation:
            SelfCustodyEducationScreen(
                onContinue: { state.navigateTo(.personaSelection) },
                onLearnMore: { /* Show learn more sheet */ }
            )
            
        case .personaSelection:
            PersonaSelectionScreen(
                selectedPersona: Binding(
                    get: { state.selectedPersona },
                    set: { state.selectedPersona = $0 }
                ),
                onContinue: { state.navigateTo(.createOrImport) },
                onSkip: { state.navigateTo(.createOrImport) }
            )
            
        case .createOrImport:
            CreateImportScreen(
                selectedMethod: Binding(
                    get: { state.selectedCreationMethod ?? .create },
                    set: { state.selectedCreationMethod = $0 }
                ),
                onContinue: {
                    switch state.selectedCreationMethod {
                    case .create:
                        generateAndNavigateToRecoveryPhrase()
                    case .importSeed:
                        state.navigateTo(.recoveryPhraseInput)
                    case .ledger, .trezor, .keystone:
                        state.navigateTo(.hardwareWalletConnect)
                    case .watchOnly:
                        state.navigateTo(.watchAddressInput)
                    case .none:
                        break
                    }
                },
                onBack: { state.goBack() }
            )
            
        case .recoveryPhraseDisplay:
            RecoveryPhraseScreen(
                words: state.generatedRecoveryPhrase,
                iCloudBackupEnabled: $state.iCloudBackupEnabled,
                onContinue: {
                    if state.selectedPath == .quick {
                        // Quick path: Go to 2-word verification (ROADMAP-02)
                        state.navigateTo(.quickVerifyBackup)
                    } else {
                        state.navigateTo(.verifyBackup)
                    }
                },
                onSaveToiCloud: {
                    // ROADMAP-02: iCloud backup is only allowed post-verification
                    // During onboarding, the phrase is being displayed for the first time
                    // so we flag intent but defer actual backup until after verification
                    state.iCloudBackupEnabled = true
                    // Navigate to verification — actual iCloud save happens in completeOnboarding()
                    // only if BackupVerificationManager.shared.isVerified is true
                    if state.selectedPath == .quick {
                        state.navigateTo(.quickVerifyBackup)
                    } else {
                        state.navigateTo(.verifyBackup)
                    }
                },
                onBack: { state.goBack() }
            )
        
        case .quickVerifyBackup:
            // Quick path 2-word verification (ROADMAP-02)
            QuickVerifyBackupScreen(
                words: state.generatedRecoveryPhrase,
                onVerify: {
                    state.securityScore.complete(.backupVerified)
                    state.navigateTo(.securitySetup)
                },
                onDoLater: {
                    // Mark as skipped with limits
                    BackupVerificationManager.shared.markSkipped()
                    state.navigateTo(.securitySetup)
                },
                onBack: { state.goBack() }
            )
            
        case .verifyBackup:
            VerifyBackupScreen(
                words: state.generatedRecoveryPhrase,
                verificationIndices: [3, 7, 11],
                selections: $state.verificationSelections,
                onVerify: {
                    state.securityScore.complete(.backupVerified)
                    state.navigateTo(.guardianSetup)
                },
                onSkip: {
                    state.navigateTo(.guardianSetup)
                },
                onBack: { state.goBack() }
            )
            
        case .guardianSetup:
            GuardianSetupScreen(
                guardians: $state.guardians,
                onContinue: {
                    state.securityScore.complete(.guardianAdded)
                    state.navigateTo(.practiceMode)
                },
                onSkip: {
                    state.navigateTo(.practiceMode)
                },
                onBack: { state.goBack() }
            )
            
        case .practiceMode:
            PracticeModeScreen(
                onComplete: {
                    state.navigateTo(.securitySetup)
                },
                onSkip: {
                    state.navigateTo(.securitySetup)
                }
            )
            
        case .securitySetup:
            SecuritySetupScreen(
                passcode: $state.passcode,
                confirmPasscode: $state.confirmPasscode,
                isConfirmingPasscode: $state.isConfirmingPasscode,
                biometricsEnabled: $state.biometricsEnabled,
                iCloudBackupEnabled: $state.iCloudBackupEnabled,
                showError: $state.showPasscodeError,
                errorMessage: $state.errorMessage,
                onComplete: {
                    state.securityScore.complete(.pinSet)
                    state.navigateTo(.biometricsSetup)
                },
                onBack: { state.goBack() }
            )
            
        case .biometricsSetup:
            BiometricsSetupScreen(
                biometricsEnabled: $state.biometricsEnabled,
                onEnable: {
                    state.biometricsEnabled = true
                    state.securityScore.complete(.biometricsEnabled)
                    
                    if state.selectedPath == .quick {
                        state.navigateTo(.ready)
                    } else {
                        state.navigateTo(.powerSettings)
                    }
                },
                onSkip: {
                    if state.selectedPath == .quick {
                        state.navigateTo(.ready)
                    } else {
                        state.navigateTo(.powerSettings)
                    }
                }
            )
            
        case .powerSettings:
            PowerSettingsScreen(
                selectedChains: $state.selectedChains,
                developerModeEnabled: $state.developerModeEnabled,
                onContinue: {
                    state.navigateTo(.securityScore)
                },
                onBack: { state.goBack() }
            )
            
        case .securityScore:
            SecurityScoreScreen(
                securityScore: state.securityScore,
                onContinue: {
                    state.navigateTo(.ready)
                },
                onImprove: { item in
                    // Navigate to appropriate improvement screen
                    print("Improve: \(item)")
                }
            )
            
        case .ready:
            ReadyScreen(
                walletAddress: state.generatedAddress,
                securityScore: state.securityScore,
                onEnterWallet: {
                    completeOnboarding()
                }
            )
            
        // Additional screens for import flow
        case .recoveryPhraseInput:
            ImportPhraseScreen(
                words: $state.importedRecoveryPhrase,
                onContinue: {
                    // Validate and import phrase
                    state.navigateTo(.securitySetup)
                },
                onBack: { state.goBack() }
            )
            
        case .hardwareWalletConnect:
            HardwareConnectScreen(
                walletType: state.selectedCreationMethod ?? .ledger,
                onConnected: {
                    state.navigateTo(.securitySetup)
                },
                onBack: { state.goBack() }
            )
            
        case .watchAddressInput:
            WatchAddressScreen(
                address: $state.watchAddress,
                onContinue: {
                    state.navigateTo(.ready)
                },
                onBack: { state.goBack() }
            )
            
        // MARK: - Import Flow Screens (Phase 4)
            
        case .importMethodSelection:
            ImportMethodSelectionScreen(
                onSelectMethod: { method in
                    state.selectedImportMethod = method
                    switch method {
                    case .seedPhrase:
                        state.navigateTo(.importSeedPhrase)
                    case .privateKey:
                        state.navigateTo(.importPrivateKey)
                    case .qrCode:
                        state.navigateTo(.importQRCode)
                    case .hardwareWallet:
                        state.navigateTo(.importHardwareWallet)
                    case .iCloudBackup:
                        state.navigateTo(.importiCloudBackup)
                    case .hawalaFile:
                        state.navigateTo(.importHawalaFile)
                    }
                },
                onBack: { state.goBack() },
                onLostBackup: { state.navigateTo(.lostBackupRecovery) }
            )
            
        case .importSeedPhrase:
            SeedPhraseImportScreen(
                importManager: importManager,
                onComplete: {
                    state.isWalletCreated = true
                    state.navigateTo(.importSuccess)
                },
                onBack: { state.goBack() }
            )
            
        case .importPrivateKey:
            PrivateKeyImportScreen(
                importManager: importManager,
                onComplete: {
                    state.isWalletCreated = true
                    state.navigateTo(.importSuccess)
                },
                onBack: { state.goBack() }
            )
            
        case .importQRCode:
            QRImportScreen(
                importManager: importManager,
                onComplete: {
                    state.isWalletCreated = true
                    state.navigateTo(.importSuccess)
                },
                onBack: { state.goBack() }
            )
            
        case .importHardwareWallet:
            HardwareConnectScreen(
                walletType: .ledger,
                onConnected: {
                    state.isWalletCreated = true
                    state.navigateTo(.securitySetup)
                },
                onBack: { state.goBack() }
            )
            
        case .importiCloudBackup:
            iCloudRestoreScreen(
                importManager: importManager,
                onComplete: {
                    state.isWalletCreated = true
                    state.navigateTo(.importSuccess)
                },
                onBack: { state.goBack() }
            )
            
        case .importHawalaFile:
            HawalaFileImportScreen(
                onComplete: {
                    state.isWalletCreated = true
                    state.navigateTo(.importSuccess)
                },
                onBack: { state.goBack() }
            )
            
        case .importSuccess:
            ImportSuccessScreen(
                walletName: state.importedWalletName.isEmpty ? "Imported Wallet" : state.importedWalletName,
                onContinue: {
                    state.navigateTo(.securitySetup)
                }
            )
            
        case .lostBackupRecovery:
            LostBackupRecoveryScreen(
                onComplete: {
                    state.isWalletCreated = true
                    state.navigateTo(.importSuccess)
                },
                onBack: { state.goBack() }
            )
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateAndNavigateToRecoveryPhrase() {
        // Generate recovery phrase using MnemonicGenerator
        let wordCount: MnemonicGenerator.WordCount = state.selectedPersona == .builder ? .twentyFour : .twelve
        state.generatedRecoveryPhrase = MnemonicGenerator.generate(wordCount: wordCount)
        state.generatedAddress = generateAddress()
        state.navigateTo(.recoveryPhraseDisplay)
    }
    
    private func generateAddress() -> String {
        // Generate a sample address (in production, derive from phrase)
        let chars = "0123456789abcdef"
        let address = (0..<40).map { _ in chars.randomElement()! }
        return "0x" + String(address)
    }
    
    private func saveSeedPhraseSecurely() {
        // Save the seed phrase using SecureSeedStorage
        guard !state.generatedRecoveryPhrase.isEmpty else { return }
        
        do {
            // Save with passcode if set, otherwise use device key
            let passcode = state.passcode.isEmpty ? nil : state.passcode
            try SecureSeedStorage.saveSeedPhrase(state.generatedRecoveryPhrase, withPasscode: passcode)
            
            // Update security score
            SecurityScoreManager.shared.complete(.backupCreated)
            
            #if DEBUG
            print("✅ Seed phrase saved securely")
            #endif
        } catch {
            #if DEBUG
            print("❌ Failed to save seed phrase: \(error)")
            #endif
        }
    }
    
    /// ROADMAP-02: Perform iCloud backup only after verification is confirmed
    private func performiCloudBackup() {
        guard BackupVerificationManager.shared.isVerified else {
            #if DEBUG
            print("⚠️ iCloud backup blocked — backup not verified")
            #endif
            return
        }
        guard !state.generatedRecoveryPhrase.isEmpty else { return }
        
        do {
            let password = state.passcode.isEmpty ? UUID().uuidString : state.passcode
            try SecureSeedStorage.backupToiCloud(state.generatedRecoveryPhrase, encryptedWith: password)
            SecurityScoreManager.shared.complete(.iCloudBackupEnabled)
            #if DEBUG
            print("✅ iCloud backup completed (post-verification)")
            #endif
        } catch {
            #if DEBUG
            print("❌ iCloud backup failed: \(error)")
            #endif
        }
    }
    
    private func updateSecurityScoreFromState() {
        // Update security score based on completed steps
        let scoreManager = SecurityScoreManager.shared
        
        if !state.passcode.isEmpty {
            scoreManager.complete(.passcodeCreated)
        }
        
        if state.biometricsEnabled {
            scoreManager.complete(.biometricsEnabled)
        }
        
        // ROADMAP-02: Only award iCloud score if backup is verified
        if state.iCloudBackupEnabled && BackupVerificationManager.shared.isVerified {
            scoreManager.complete(.iCloudBackupEnabled)
        }
        
        if !state.guardians.isEmpty {
            scoreManager.complete(.guardiansAdded)
        }
        
        // Update the state's security score from the manager
        state.securityScore = SecurityScore(
            biometricEnabled: state.biometricsEnabled,
            pinCreated: !state.passcode.isEmpty,
            backupCompleted: !state.generatedRecoveryPhrase.isEmpty,
            backupVerified: !state.verificationSelections.isEmpty,
            guardiansAdded: !state.guardians.isEmpty,
            twoFactorEnabled: false
        )
    }
    
    private func completeOnboarding() {
        // Save seed phrase securely
        saveSeedPhraseSecurely()
        
        // Update security score
        updateSecurityScoreFromState()
        
        // Mark backup verified if verification was completed
        if !state.verificationSelections.isEmpty {
            SecurityScoreManager.shared.complete(.backupVerified)
        }
        
        // ROADMAP-02: iCloud backup is ONLY performed after backup verification
        if state.iCloudBackupEnabled && BackupVerificationManager.shared.isVerified {
            performiCloudBackup()
        } else if state.iCloudBackupEnabled && !BackupVerificationManager.shared.isVerified {
            #if DEBUG
            print("⚠️ iCloud backup requested but deferred — backup not yet verified")
            #endif
            // Clear the flag; user must verify first, then enable iCloud from Settings
            state.iCloudBackupEnabled = false
        }
        
        let result = WalletCreationResult(
            method: state.selectedCreationMethod ?? .create,
            recoveryPhrase: state.generatedRecoveryPhrase,
            address: state.generatedAddress,
            hasPasscode: !state.passcode.isEmpty,
            hasBiometrics: state.biometricsEnabled,
            selectedChains: state.selectedChains,
            guardians: state.guardians,
            persona: state.selectedPersona,
            securityScore: state.securityScore.score
        )
        
        // Trigger celebration feedback for wallet creation success
        FeedbackManager.shared.trigger(.success)
        
        onComplete?(result)
        
        // ROADMAP-02: Clear force-quit checkpoint AFTER result delivered — onboarding complete
        OnboardingCheckpoint.clear()
    }
}

// MARK: - Wallet Creation Result
struct WalletCreationResult {
    let method: WalletCreationMethod
    let recoveryPhrase: [String]
    let address: String
    let hasPasscode: Bool
    let hasBiometrics: Bool
    let selectedChains: Set<String>
    let guardians: [OnboardingGuardian]
    let persona: UserPersona?
    let securityScore: Int
}

// MARK: - Import Phrase Screen
struct ImportPhraseScreen: View {
    @Binding var words: [String]
    let onContinue: () -> Void
    let onBack: () -> Void
    
    @State private var animateContent = false
    @State private var phraseText: String = ""
    @State private var isValid = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 8) {
                Text("Import your wallet")
                    .font(.custom("ClashGrotesk-Bold", size: 28))
                    .foregroundColor(.white)
                
                Text("Enter your 12 or 24 word recovery phrase")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
            }
            .opacity(animateContent ? 1 : 0)
            
            OnboardingCard(padding: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recovery Phrase")
                        .font(.custom("ClashGrotesk-Medium", size: 13))
                        .foregroundColor(.white.opacity(0.6))
                    
                    TextEditor(text: $phraseText)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.white)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .frame(height: 120)
                        .onChange(of: phraseText) { newValue in
                            validatePhrase(newValue)
                        }
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.red)
                    }
                    
                    HStack {
                        Text("\(phraseText.split(separator: " ").count) words")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.white.opacity(0.4))
                        
                        Spacer()
                        
                        Button("Paste") {
                            #if os(macOS)
                            if let string = NSPasteboard.general.string(forType: .string) {
                                phraseText = string
                                validatePhrase(string)
                            }
                            #endif
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: 500)
            .padding(.horizontal, 24)
            .opacity(animateContent ? 1 : 0)
            
            WarningBanner(
                level: .info,
                message: "Make sure no one is watching. Never share your phrase with anyone."
            )
            .frame(maxWidth: 500)
            .padding(.horizontal, 24)
            .opacity(animateContent ? 1 : 0)
            
            Spacer()
            
            VStack(spacing: 12) {
                OnboardingPrimaryButton(
                    title: "Import Wallet",
                    action: {
                        words = phraseText.split(separator: " ").map(String.init)
                        onContinue()
                    },
                    isDisabled: !isValid,
                    style: .glass
                )
                
                OnboardingSecondaryButton(title: "Back", icon: "chevron.left", action: onBack)
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
    
    private func validatePhrase(_ phrase: String) {
        let words = phrase.lowercased().split(separator: " ").map(String.init)
        
        if words.count != 12 && words.count != 24 {
            isValid = false
            errorMessage = words.count > 0 ? "Enter 12 or 24 words" : nil
        } else {
            // In production, validate against BIP39 word list
            isValid = true
            errorMessage = nil
        }
    }
}

// MARK: - Hardware Connect Screen
struct HardwareConnectScreen: View {
    let walletType: WalletCreationMethod
    let onConnected: () -> Void
    let onBack: () -> Void
    
    @State private var animateContent = false
    @State private var isScanning = false
    @State private var isConnected = false
    
    private var walletName: String {
        switch walletType {
        case .ledger: return "Ledger"
        case .trezor: return "Trezor"
        case .keystone: return "Keystone"
        default: return "Hardware Wallet"
        }
    }
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 8) {
                Text("Connect \(walletName)")
                    .font(.custom("ClashGrotesk-Bold", size: 28))
                    .foregroundColor(.white)
                
                Text("Make sure your device is unlocked and ready")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
            }
            .opacity(animateContent ? 1 : 0)
            
            Spacer()
                .frame(height: 20)
            
            // Connection visual
            OnboardingCard(padding: 40) {
                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 3)
                            .frame(width: 100, height: 100)
                        
                        if isScanning {
                            Circle()
                                .trim(from: 0, to: 0.3)
                                .stroke(Color(hex: "#00D4FF"), lineWidth: 3)
                                .frame(width: 100, height: 100)
                                .rotationEffect(.degrees(isScanning ? 360 : 0))
                                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isScanning)
                        }
                        
                        Image(systemName: isConnected ? "checkmark.circle.fill" : "cable.connector.horizontal")
                            .font(.system(size: isConnected ? 40 : 32))
                            .foregroundColor(isConnected ? Color(hex: "#32D74B") : .white)
                    }
                    
                    VStack(spacing: 4) {
                        Text(isConnected ? "Connected!" : (isScanning ? "Scanning..." : "Ready to connect"))
                            .font(.custom("ClashGrotesk-Semibold", size: 16))
                            .foregroundColor(.white)
                        
                        if !isConnected {
                            Text("Connect via USB or Bluetooth")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
            }
            .frame(maxWidth: 350)
            .padding(.horizontal, 24)
            .opacity(animateContent ? 1 : 0)
            
            // Instructions
            if !isConnected {
                VStack(alignment: .leading, spacing: 12) {
                    OnboardingInstructionRow(number: "1", text: "Unlock your \(walletName)")
                    OnboardingInstructionRow(number: "2", text: "Open the Ethereum app")
                    OnboardingInstructionRow(number: "3", text: "Enable blind signing if prompted")
                }
                .frame(maxWidth: 350)
                .padding(.horizontal, 24)
                .opacity(animateContent ? 1 : 0)
            }
            
            Spacer()
            
            VStack(spacing: 12) {
                OnboardingPrimaryButton(
                    title: isConnected ? "Continue" : "Scan for Device",
                    action: {
                        if isConnected {
                            onConnected()
                        } else {
                            startScanning()
                        }
                    },
                    style: .glass
                )
                
                OnboardingSecondaryButton(title: "Back", icon: "chevron.left", action: onBack)
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
    
    private func startScanning() {
        isScanning = true
        
        // Simulate connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isScanning = false
                isConnected = true
            }
        }
    }
}

struct OnboardingInstructionRow: View {
    let number: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.custom("ClashGrotesk-Bold", size: 12))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.1))
                .clipShape(Circle())
            
            Text(text)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.white.opacity(0.8))
        }
    }
}

// MARK: - Watch Address Screen
struct WatchAddressScreen: View {
    @Binding var address: String
    let onContinue: () -> Void
    let onBack: () -> Void
    
    @State private var animateContent = false
    @State private var isValid = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 8) {
                Text("Watch an address")
                    .font(.custom("ClashGrotesk-Bold", size: 28))
                    .foregroundColor(.white)
                
                Text("Track any wallet without controlling it")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
            }
            .opacity(animateContent ? 1 : 0)
            
            OnboardingCard(padding: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Wallet Address or ENS")
                        .font(.custom("ClashGrotesk-Medium", size: 13))
                        .foregroundColor(.white.opacity(0.6))
                    
                    TextField("0x... or vitalik.eth", text: $address)
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundColor(.white)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(8)
                        .onChange(of: address) { newValue in
                            isValid = newValue.count > 5
                        }
                    
                    HStack {
                        Button("Paste") {
                            #if os(macOS)
                            if let string = NSPasteboard.general.string(forType: .string) {
                                address = string
                                isValid = string.count > 5
                            }
                            #endif
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        Button("Scan QR") {
                            // QR scanning not typical on macOS
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: 500)
            .padding(.horizontal, 24)
            .opacity(animateContent ? 1 : 0)
            
            OnboardingInfoCard(
                icon: "eye.fill",
                title: "Watch-only mode",
                description: "You can view balances and history, but cannot send transactions"
            )
            .frame(maxWidth: 500)
            .padding(.horizontal, 24)
            .opacity(animateContent ? 1 : 0)
            
            Spacer()
            
            VStack(spacing: 12) {
                OnboardingPrimaryButton(
                    title: "Watch Address",
                    action: onContinue,
                    isDisabled: !isValid,
                    style: .glass
                )
                
                OnboardingSecondaryButton(title: "Back", icon: "chevron.left", action: onBack)
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
}

// MARK: - Preview
#if DEBUG
struct NewOnboardingFlowView_Previews: PreviewProvider {
    static var previews: some View {
        NewOnboardingFlowView()
            .frame(width: 900, height: 650)
            .preferredColorScheme(.dark)
    }
}
#endif
