import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Recovery Phrase Screen
/// Displays the generated recovery phrase for backup (Guided path)
struct RecoveryPhraseScreen: View {
    let words: [String]
    @Binding var iCloudBackupEnabled: Bool
    
    let onContinue: () -> Void
    let onSaveToiCloud: () -> Void
    let onBack: () -> Void
    
    @State private var animateContent = false
    @State private var hasAcknowledged = false
    @State private var showCopiedToast = false
    @ObservedObject private var screenshotDetector = ScreenshotDetectionManager.shared
    
    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                Spacer()
                    .frame(height: 20)
                
                // Title
                VStack(spacing: 8) {
                    Text("Your recovery phrase")
                        .font(.custom("ClashGrotesk-Bold", size: 28))
                        .foregroundColor(.white)
                    
                    Text("Write these \(words.count) words in order. This is the ONLY way to recover your wallet.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .opacity(animateContent ? 1 : 0)
                
                // Screenshot/Recording warning banner
                if screenshotDetector.isScreenBeingCaptured {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Screen recording detected! Hide your recovery phrase.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(12)
                    .background(Color.red.opacity(0.2))
                    .cornerRadius(10)
                    .padding(.horizontal, 24)
                }
                
                // Word grid - blur if screen is being recorded
                OnboardingCard(padding: 20) {
                    WordGrid(words: words) {
                        copyWordsToClipboard()
                    }
                }
                .frame(maxWidth: 500)
                .padding(.horizontal, 24)
                .opacity(animateContent ? 1 : 0)
                .offset(y: animateContent ? 0 : 10)
                .sensitiveContent() // Hide during screen recording
                
                // Warning
                WarningBanner(
                    level: .warning,
                    message: "Never share these words. Hawala will never ask for them."
                )
                .frame(maxWidth: 500)
                .padding(.horizontal, 24)
                .opacity(animateContent ? 1 : 0)
            
            Spacer()
            
            // Acknowledgment checkbox
            Button(action: {
                withAnimation(.spring(response: 0.2)) {
                    hasAcknowledged.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                            .frame(width: 20, height: 20)
                        
                        if hasAcknowledged {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color(hex: "#32D74B"))
                        }
                    }
                    
                    Text("I have written down my recovery phrase")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .opacity(animateContent ? 1 : 0)
            
            // Buttons
            VStack(spacing: 12) {
                OnboardingPrimaryButton(
                    title: "I've Saved It",
                    action: onContinue,
                    isDisabled: !hasAcknowledged,
                    style: .glass
                )
                
                // iCloud backup option
                Button(action: onSaveToiCloud) {
                    HStack(spacing: 10) {
                        Image(systemName: "icloud.fill")
                            .font(.system(size: 16))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Save to iCloud after verification")
                                .font(.custom("ClashGrotesk-Medium", size: 14))
                            
                            Text("Encrypted backup — requires word verification first")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(HawalaTheme.Spacing.lg)
                    .background {
                        RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                            .fill(Color.white.opacity(0.05))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    }
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                
                OnboardingSecondaryButton(title: "Back", icon: "chevron.left", action: onBack)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .opacity(animateContent ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            if showCopiedToast {
                InlineToast(message: "Copied to clipboard", type: .success)
                    .padding(.top, 100)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            // Screenshot warning banner
            ScreenshotWarningBanner()
                .padding(.top, 20)
        }
        .contentShape(Rectangle())
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                animateContent = true
            }
        }
        } // End ZStack
    }
    
    private func copyWordsToClipboard() {
        ClipboardHelper.copySensitive(words.joined(separator: " "), timeout: 30)
        
        withAnimation {
            showCopiedToast = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopiedToast = false
            }
        }
    }
}

// MARK: - Verify Backup Screen
/// Gamified backup verification (Guided path)
struct VerifyBackupScreen: View {
    let words: [String]
    let verificationIndices: [Int] // e.g., [3, 7, 11] for words #3, #7, #11
    @Binding var selections: [Int: String]
    
    let onVerify: () -> Void
    let onSkip: () -> Void
    let onBack: () -> Void
    
    @State private var animateContent = false
    @State private var verificationComplete = false
    @State private var showError = false
    
    private var allCorrect: Bool {
        for index in verificationIndices {
            guard let selected = selections[index],
                  index > 0 && index <= words.count,
                  selected == words[index - 1] else {
                return false
            }
        }
        return true
    }
    
    private var allSelected: Bool {
        verificationIndices.allSatisfy { selections[$0] != nil }
    }
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Title
            VStack(spacing: 8) {
                Text("Let's verify your backup")
                    .font(.custom("ClashGrotesk-Bold", size: 28))
                    .foregroundColor(.white)
                
                Text("Select word #\(verificationIndices.map { String($0) }.joined(separator: ", #"))")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
            }
            .opacity(animateContent ? 1 : 0)
            
            Spacer()
                .frame(height: 20)
            
            // Word selectors
            VStack(spacing: 24) {
                ForEach(Array(verificationIndices.enumerated()), id: \.offset) { index, wordIndex in
                    WordSelector(
                        wordNumber: wordIndex,
                        options: generateOptions(for: wordIndex),
                        correctWord: words[wordIndex - 1],
                        selectedWord: Binding(
                            get: { selections[wordIndex] },
                            set: { selections[wordIndex] = $0 }
                        )
                    )
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 10)
                    .animation(.easeOut(duration: 0.4).delay(Double(index) * 0.1), value: animateContent)
                }
            }
            .padding(.horizontal, 24)
            
            // Success or error indicator
            if allSelected {
                if allCorrect {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(hex: "#32D74B"))
                        Text("Perfect! All words correct.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(hex: "#32D74B"))
                    }
                    .transition(.opacity)
                } else if showError {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text("Some words are incorrect. Try again.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.red)
                    }
                    .transition(.opacity)
                }
            }
            
            Spacer()
            
            // Buttons
            VStack(spacing: 12) {
                OnboardingPrimaryButton(
                    title: "Verify",
                    action: handleVerify,
                    isDisabled: !allSelected,
                    style: .glass
                )
                
                HStack(spacing: 16) {
                    OnboardingSecondaryButton(title: "Back", icon: "chevron.left", action: onBack)
                    
                    OnboardingSecondaryButton(title: "Skip for now (risky)", action: onSkip)
                        .foregroundColor(.orange.opacity(0.8))
                }
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
    
    private func generateOptions(for wordIndex: Int) -> [String] {
        // Get the correct word
        let correctWord = words[wordIndex - 1]
        
        // Get 2 random wrong words from the phrase
        var wrongWords = words.filter { $0 != correctWord }.shuffled().prefix(2)
        
        // Create options array and shuffle
        var options = [correctWord] + Array(wrongWords)
        options.shuffle()
        
        return options
    }
    
    private func handleVerify() {
        if allCorrect {
            onVerify()
        } else {
            withAnimation {
                showError = true
            }
            
            // Reset selections after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showError = false
                    selections = [:]
                }
            }
        }
    }
}

// MARK: - Guardian Setup Screen
/// Social recovery guardian setup (Guided path)
struct GuardianSetupScreen: View {
    @Binding var guardians: [OnboardingGuardian]
    
    let onContinue: () -> Void
    let onSkip: () -> Void
    let onBack: () -> Void
    
    @State private var animateContent = false
    @State private var showAddGuardianSheet = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Title
            VStack(spacing: 8) {
                Text("Add recovery guardians")
                    .font(.custom("ClashGrotesk-Bold", size: 28))
                    .foregroundColor(.white)
                
                Text("If you ever lose access, they can help you recover your wallet.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .opacity(animateContent ? 1 : 0)
            
            Spacer()
                .frame(height: 20)
            
            // How it works
            OnboardingCard(padding: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("✦ How it works")
                        .font(.custom("ClashGrotesk-Semibold", size: 15))
                        .foregroundColor(.white)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        GuardianInfoRow(text: "Choose 2-3 trusted people")
                        GuardianInfoRow(text: "They can't access your funds")
                        GuardianInfoRow(text: "2 of 3 needed to recover")
                    }
                }
            }
            .frame(maxWidth: 400)
            .padding(.horizontal, 24)
            .opacity(animateContent ? 1 : 0)
            
            // Added guardians list
            if !guardians.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Added Guardians")
                        .font(.custom("ClashGrotesk-Medium", size: 14))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 24)
                    
                    VStack(spacing: 8) {
                        ForEach(guardians) { guardian in
                            GuardianRow(guardian: guardian) {
                                guardians.removeAll { $0.id == guardian.id }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .opacity(animateContent ? 1 : 0)
            }
            
            // Add guardian button
            Button(action: { showAddGuardianSheet = true }) {
                HStack(spacing: 12) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 18))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add Guardian")
                            .font(.custom("ClashGrotesk-Medium", size: 14))
                        
                        Text("via email, phone, or wallet address")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    Spacer()
                    
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(16)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 400)
            .padding(.horizontal, 24)
            .opacity(animateContent ? 1 : 0)
            
            Spacer()
            
            // Buttons
            VStack(spacing: 12) {
                OnboardingPrimaryButton(
                    title: guardians.count >= 2 ? "Continue" : "Add Guardians",
                    action: {
                        if guardians.count >= 2 {
                            onContinue()
                        } else {
                            showAddGuardianSheet = true
                        }
                    },
                    style: .glass
                )
                
                VStack(spacing: 8) {
                    OnboardingSecondaryButton(title: "Skip for now", action: onSkip)
                    
                    Text("You can add guardians later in Settings → Security → Recovery")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                }
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

struct GuardianInfoRow: View {
    let text: String
    
    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 4, height: 4)
            
            Text(text)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

struct GuardianRow: View {
    let guardian: OnboardingGuardian
    let onRemove: () -> Void
    
    var body: some View {
        let initial = String(guardian.name.prefix(1)).uppercased()
        let methodIcon = guardian.contactMethod.icon
        let contactVal = guardian.contactValue
        let isConfirmed = guardian.isConfirmed
        let guardianName = guardian.name
        let guardianId = guardian.id
        
        return HStack(spacing: 12) {
            Circle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 40, height: 40)
                .overlay {
                    Text(initial)
                        .font(.custom("ClashGrotesk-Semibold", size: 16))
                        .foregroundColor(.white)
                }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(guardianName)
                    .font(.custom("ClashGrotesk-Medium", size: 14))
                    .foregroundColor(.white)
                
                HStack(spacing: 4) {
                    Image(systemName: methodIcon)
                        .font(.system(size: 10))
                    Text(contactVal)
                        .font(.system(size: 11, weight: .regular))
                }
                .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            if isConfirmed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(hex: "32D74B"))
            } else {
                Text("Pending")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.orange)
            }
            
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        }
    }
}

// MARK: - Practice Mode Screen
/// Simulated transaction for learning (Guided path)
struct PracticeModeScreen: View {
    let onComplete: () -> Void
    let onSkip: () -> Void
    
    @StateObject private var practiceManager = PracticeModeManager.shared
    @State private var animateContent = false
    @State private var practiceStep: PracticeStep = .intro
    @State private var simulatedBalance: Decimal = 0
    @State private var showFullPractice = false
    
    enum PracticeStep {
        case intro
        case receiving
        case received
        case complete
    }
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Title
            VStack(spacing: 8) {
                Text("Try a practice transaction")
                    .font(.custom("ClashGrotesk-Bold", size: 28))
                    .foregroundColor(.white)
                
                Text("No real money. Just learning.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
            }
            .opacity(animateContent ? 1 : 0)
            
            Spacer()
                .frame(height: 20)
            
            // Practice content
            Group {
                switch practiceStep {
                case .intro:
                    practiceIntroView
                case .receiving:
                    practiceReceivingView
                case .received:
                    practiceReceivedView
                case .complete:
                    practiceCompleteView
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .animation(.easeInOut(duration: 0.3), value: practiceStep)
            
            Spacer()
            
            // Buttons
            VStack(spacing: 12) {
                OnboardingPrimaryButton(
                    title: practiceStep == .complete ? "Continue" : "Try It",
                    action: handlePracticeAction,
                    style: .glass
                )
                
                if practiceStep == .intro {
                    Button {
                        showFullPractice = true
                        practiceManager.startPractice()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "gamecontroller.fill")
                                .font(.system(size: 12))
                            Text("Enter Full Practice Mode")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    
                    OnboardingSecondaryButton(title: "Skip to wallet", action: onSkip)
                }
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
        .sheet(isPresented: $showFullPractice) {
            PracticeModeView()
                .onDisappear {
                    // Mark security item complete if they completed any scenario
                    if practiceManager.allScenariosCompleted {
                        SecurityScoreManager.shared.complete(.practiceCompleted)
                    }
                }
        }
    }
    
    private var practiceIntroView: some View {
        VStack(spacing: 20) {
            OnboardingCard(padding: 24) {
                VStack(spacing: 16) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(Color(hex: "#32D74B"))
                    
                    VStack(spacing: 4) {
                        Text("You're receiving 1 ETH (fake)")
                            .font(.custom("ClashGrotesk-Semibold", size: 16))
                            .foregroundColor(.white)
                        
                        Text("from practice.hawala.eth")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            .frame(maxWidth: 350)
            
            OnboardingInfoCard(
                icon: "bolt.fill",
                title: "This is a simulation",
                description: "See how transactions look before doing it for real"
            )
            .frame(maxWidth: 350)
        }
        .padding(.horizontal, 24)
    }
    
    private var practiceReceivingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
            
            Text("Receiving ETH...")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
        }
    }
    
    private var practiceReceivedView: some View {
        VStack(spacing: 20) {
            // Success animation
            ZStack {
                Circle()
                    .fill(Color(hex: "#32D74B").opacity(0.2))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(Color(hex: "#32D74B"))
            }
            
            // Balance update
            OnboardingCard(padding: 24) {
                VStack(spacing: 12) {
                    Text("Your Balance")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    
                    Text("1.00 ETH")
                        .font(.custom("ClashGrotesk-Bold", size: 36))
                        .foregroundColor(.white)
                    
                    Text("≈ $2,500 (simulated)")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .frame(maxWidth: 300)
        }
        .padding(.horizontal, 24)
    }
    
    private var practiceCompleteView: some View {
        VStack(spacing: 20) {
            SuccessStateView(
                title: "You got it!",
                subtitle: "That's how receiving crypto works in Hawala."
            )
            
            // Show completed scenarios count
            if !practiceManager.completedScenarios.isEmpty {
                Text("\(practiceManager.completedScenarios.count) scenarios completed")
                    .font(.system(size: 13))
                    .foregroundColor(.green)
            }
        }
    }
    
    private func handlePracticeAction() {
        switch practiceStep {
        case .intro:
            withAnimation {
                practiceStep = .receiving
            }
            
            // Mark practice as started
            practiceManager.startPractice()
            
            // Simulate receiving
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation {
                    practiceStep = .received
                    practiceManager.simulateIncomingTransaction()
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation {
                    practiceStep = .complete
                    practiceManager.completeScenario("receive-101")
                }
            }
            
        case .complete:
            onComplete()
            
        default:
            break
        }
    }
}

// MARK: - Security Score Screen
/// Shows security completion status (Guided path)
struct SecurityScoreScreen: View {
    let securityScore: SecurityScore
    let onContinue: () -> Void
    let onImprove: (String) -> Void
    
    @State private var animateContent = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Title
            Text("Security Score")
                .font(.custom("ClashGrotesk-Bold", size: 28))
                .foregroundColor(.white)
                .opacity(animateContent ? 1 : 0)
            
            // Score ring
            SecurityScoreRing(
                score: securityScore.score,
                maxScore: securityScore.maxScore,
                size: 150,
                lineWidth: 10
            )
            .opacity(animateContent ? 1 : 0)
            .scaleEffect(animateContent ? 1 : 0.8)
            
            // Completed items
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(securityScore.completedItems.enumerated()), id: \.offset) { index, item in
                    SecurityChecklistItem(
                        title: item.title,
                        description: item.description,
                        isCompleted: true
                    )
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 10)
                    .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.05 + 0.2), value: animateContent)
                }
            }
            .frame(maxWidth: 400)
            .padding(.horizontal, 24)
            
            // Pending items
            if !securityScore.pendingItems.isEmpty {
                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.horizontal, 24)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Complete to improve")
                        .font(.custom("ClashGrotesk-Medium", size: 13))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 24)
                    
                    ForEach(Array(securityScore.pendingItems.enumerated()), id: \.offset) { index, item in
                        SecurityChecklistItem(
                            title: item.title,
                            description: item.description,
                            isCompleted: false,
                            points: item.points
                        ) {
                            onImprove(item.title)
                        }
                        .opacity(animateContent ? 1 : 0)
                    }
                }
                .frame(maxWidth: 400)
                .padding(.horizontal, 24)
            }
            
            Spacer()
            
            // Continue button
            VStack(spacing: 12) {
                OnboardingPrimaryButton(title: "Continue", action: onContinue, style: .glass)
                
                Text("You can improve your score later in Settings")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white.opacity(0.4))
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
        }
    }
}

// MARK: - Quick Verify Backup Screen
/// Lightweight 2-word verification for Quick path (ROADMAP-02)
struct QuickVerifyBackupScreen: View {
    let words: [String]
    
    let onVerify: () -> Void
    let onDoLater: () -> Void
    let onBack: () -> Void
    
    @State private var animateContent = false
    @State private var verificationIndices: [Int] = []
    @State private var selections: [Int: String] = [:]
    @State private var showError = false
    @State private var attemptCount = 0
    @State private var showDoLaterWarning = false
    
    private var allCorrect: Bool {
        for index in verificationIndices {
            guard let selected = selections[index],
                  index > 0 && index <= words.count,
                  selected == words[index - 1] else {
                return false
            }
        }
        return verificationIndices.count == 2
    }
    
    private var allSelected: Bool {
        verificationIndices.count == 2 && verificationIndices.allSatisfy { selections[$0] != nil }
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Title
            VStack(spacing: 8) {
                Text("Quick backup check")
                    .font(.custom("ClashGrotesk-Bold", size: 28))
                    .foregroundColor(.white)
                
                Text("Verify 2 words to confirm you saved your phrase")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .opacity(animateContent ? 1 : 0)
            
            Spacer()
                .frame(height: 10)
            
            // Word selectors
            VStack(spacing: 20) {
                ForEach(Array(verificationIndices.enumerated()), id: \.offset) { index, wordIndex in
                    WordSelector(
                        wordNumber: wordIndex,
                        options: generateOptions(for: wordIndex),
                        correctWord: words[wordIndex - 1],
                        selectedWord: Binding(
                            get: { selections[wordIndex] },
                            set: { selections[wordIndex] = $0 }
                        )
                    )
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 10)
                    .animation(.easeOut(duration: 0.4).delay(Double(index) * 0.1), value: animateContent)
                }
            }
            .frame(maxWidth: 400)
            .padding(.horizontal, 24)
            
            // Success or error indicator
            if allSelected {
                if allCorrect {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(hex: "#32D74B"))
                        Text("Perfect! Backup verified.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(hex: "#32D74B"))
                    }
                    .transition(.opacity)
                } else if showError {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text("Incorrect. Check your backup and try again.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.red)
                    }
                    .transition(.opacity)
                }
            }
            
            Spacer()
            
            // Buttons
            VStack(spacing: 12) {
                OnboardingPrimaryButton(
                    title: "Verify",
                    action: handleVerify,
                    isDisabled: !allSelected,
                    style: .glass
                )
                
                HStack(spacing: 16) {
                    OnboardingSecondaryButton(title: "Back", icon: "chevron.left", action: onBack)
                    
                    Button(action: { showDoLaterWarning = true }) {
                        Text("Do later")
                            .font(.custom("ClashGrotesk-Medium", size: 14))
                            .foregroundColor(.orange.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 50)
            .opacity(animateContent ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            generateRandomIndices()
            withAnimation(.easeOut(duration: 0.5)) {
                animateContent = true
            }
        }
        .sheet(isPresented: $showDoLaterWarning) {
            DoLaterWarningSheet(
                onConfirm: {
                    showDoLaterWarning = false
                    onDoLater()
                },
                onCancel: {
                    showDoLaterWarning = false
                }
            )
        }
    }
    
    private func generateRandomIndices() {
        // Generate 2 random unique indices (1-based, within word count)
        var indices = Set<Int>()
        while indices.count < 2 {
            let randomIndex = Int.random(in: 1...words.count)
            indices.insert(randomIndex)
        }
        verificationIndices = Array(indices).sorted()
    }
    
    private func generateOptions(for wordIndex: Int) -> [String] {
        guard wordIndex > 0 && wordIndex <= words.count else { return [] }
        let correctWord = words[wordIndex - 1]
        
        // Get 2 random wrong words from the phrase
        let wrongWords = words.filter { $0 != correctWord }.shuffled().prefix(2)
        
        // Create options array and shuffle
        var options = [correctWord] + Array(wrongWords)
        options.shuffle()
        
        return options
    }
    
    private func handleVerify() {
        attemptCount += 1
        
        if allCorrect {
            // Mark backup as verified
            BackupVerificationManager.shared.markVerified()
            onVerify()
        } else {
            withAnimation {
                showError = true
            }
            
            // Reset selections after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showError = false
                    selections = [:]
                }
                
                // After 3 failed attempts, offer to show phrase again
                if attemptCount >= 3 {
                    // Could navigate back to phrase display
                }
            }
        }
    }
}

// MARK: - Do Later Warning Sheet
/// Modal warning when user tries to skip verification
struct DoLaterWarningSheet: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Warning icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
                .padding(.top, 32)
            
            // Title
            Text("Skip backup verification?")
                .font(.custom("ClashGrotesk-Bold", size: 24))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            // Consequences
            VStack(alignment: .leading, spacing: 16) {
                Text("If you skip, these limits apply:")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                
                VStack(alignment: .leading, spacing: 12) {
                    LimitRow(icon: "dollarsign.circle", text: "Send limit: $100 per transaction")
                    LimitRow(icon: "bell.badge", text: "Reminder banner on home screen")
                    LimitRow(icon: "shield.slash", text: "Lower security score")
                }
            }
            .padding(20)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            .padding(.horizontal, 24)
            
            Text("You can verify your backup anytime in Settings → Security")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
            Spacer()
            
            // Buttons
            VStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Go back and verify")
                        .font(.custom("ClashGrotesk-Semibold", size: 16))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                
                Button(action: onConfirm) {
                    Text("Skip anyway")
                        .font(.custom("ClashGrotesk-Medium", size: 14))
                        .foregroundColor(.orange.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: 450, maxHeight: 550)
        .background(Color(hex: "#1A1A1A"))
        .cornerRadius(20)
    }
}

struct LimitRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.orange)
                .frame(width: 24)
            
            Text(text)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.white.opacity(0.8))
        }
    }
}

// MARK: - Backup Verification Manager
/// Persists backup verification status and enforces limits (ROADMAP-02)
@MainActor
final class BackupVerificationManager: ObservableObject {
    static let shared = BackupVerificationManager()
    
    private let verifiedKey = "hawala.backup.verified"
    private let skippedKey = "hawala.backup.skipped"
    private let skippedDateKey = "hawala.backup.skippedDate"
    
    @Published private(set) var isVerified: Bool = false
    @Published private(set) var wasSkipped: Bool = false
    @Published private(set) var skippedDate: Date? = nil
    
    /// Maximum send amount in USD when backup is not verified
    let unverifiedSendLimitUSD: Double = 100.0
    
    private init() {
        loadState()
    }
    
    private func loadState() {
        isVerified = UserDefaults.standard.bool(forKey: verifiedKey)
        wasSkipped = UserDefaults.standard.bool(forKey: skippedKey)
        if let timestamp = UserDefaults.standard.object(forKey: skippedDateKey) as? Date {
            skippedDate = timestamp
        }
    }
    
    func markVerified() {
        isVerified = true
        wasSkipped = false
        UserDefaults.standard.set(true, forKey: verifiedKey)
        UserDefaults.standard.set(false, forKey: skippedKey)
        
        // Update security score
        SecurityScoreManager.shared.complete(.backupVerified)
    }
    
    func markSkipped() {
        wasSkipped = true
        skippedDate = Date()
        UserDefaults.standard.set(true, forKey: skippedKey)
        UserDefaults.standard.set(Date(), forKey: skippedDateKey)
    }
    
    /// Check if a send amount is allowed given verification status
    func canSend(amountUSD: Double) -> Bool {
        if isVerified {
            return true
        }
        return amountUSD <= unverifiedSendLimitUSD
    }
    
    /// Returns whether to show the "backup required" banner
    var shouldShowBanner: Bool {
        return !isVerified && wasSkipped
    }
    
    /// Days since user skipped verification
    var daysSinceSkipped: Int? {
        guard let date = skippedDate else { return nil }
        return Calendar.current.dateComponents([.day], from: date, to: Date()).day
    }
    
    func reset() {
        isVerified = false
        wasSkipped = false
        skippedDate = nil
        UserDefaults.standard.removeObject(forKey: verifiedKey)
        UserDefaults.standard.removeObject(forKey: skippedKey)
        UserDefaults.standard.removeObject(forKey: skippedDateKey)
    }
}

// MARK: - Backup Verification Banner (ROADMAP-02)
/// Persistent orange banner shown when backup is not verified
struct BackupVerificationBanner: View {
    let onDismiss: () -> Void
    let onVerify: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 16))
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Backup not verified")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Sends limited to $100. Verify to unlock full access.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            Spacer()
            
            Button(action: onVerify) {
                Text("Verify")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.9), Color.orange.opacity(0.7)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(8)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

// MARK: - Preview
#if DEBUG
struct BackupScreens_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            RecoveryPhraseScreen(
                words: ["apple", "brave", "coral", "delta", "eagle", "frost", "grape", "honey", "ivory", "joker", "karma", "lemon"],
                iCloudBackupEnabled: .constant(true),
                onContinue: {},
                onSaveToiCloud: {},
                onBack: {}
            )
        }
        .preferredColorScheme(.dark)
    }
}
#endif
