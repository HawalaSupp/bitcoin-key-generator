import SwiftUI

// MARK: - Redesigned Onboarding Flow
// Matches the main app's visual style with dark theme, glass effects, and ClashGrotesk typography

struct OnboardingFlowView: View {
    @Binding var step: OnboardingStep
    let onSecurityAcknowledged: () -> Void
    let onSetPasscode: (String) -> Void
    let onSkipPasscode: () -> Void
    let onFinish: () -> Void

    @State private var passcode = ""
    @State private var confirmPasscode = ""
    @State private var errorMessage: String?
    @FocusState private var passcodeFieldFocused: Bool
    @State private var isAnimating = false

    private var totalSteps: Int { 4 }

    var body: some View {
        ZStack {
            // Dark gradient background matching main app
            LinearGradient(
                colors: [
                    Color(hex: "0D0D0D"),
                    Color(hex: "1A1A1A"),
                    Color(hex: "0D0D0D")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Subtle animated gradient orbs (like main view)
            GeometryReader { geo in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [HawalaTheme.Colors.accent.opacity(0.15), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: geo.size.width * 0.4
                        )
                    )
                    .frame(width: geo.size.width * 0.6, height: geo.size.width * 0.6)
                    .offset(x: geo.size.width * 0.5, y: -geo.size.height * 0.1)
                    .blur(radius: 60)
                
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: "32D74B").opacity(0.08), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: geo.size.width * 0.3
                        )
                    )
                    .frame(width: geo.size.width * 0.5, height: geo.size.width * 0.5)
                    .offset(x: -geo.size.width * 0.2, y: geo.size.height * 0.6)
                    .blur(radius: 50)
            }
            
            // Main content
            VStack(spacing: 0) {
                // Header with logo and step indicator
                onboardingHeader
                    .padding(.top, 48)
                    .padding(.bottom, 32)
                
                // Content card with glass effect
                contentCard
                    .padding(.horizontal, 48)
                
                Spacer()
                
                // Bottom controls
                controlsSection
                    .padding(.horizontal, 48)
                    .padding(.bottom, 48)
            }
        }
        .frame(minWidth: 600, minHeight: 580)
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                isAnimating = true
            }
        }
    }
    
    // MARK: - Header
    private var onboardingHeader: some View {
        VStack(spacing: 20) {
            // App icon / logo
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [HawalaTheme.Colors.accent, HawalaTheme.Colors.accent.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .shadow(color: HawalaTheme.Colors.accent.opacity(0.4), radius: 20, x: 0, y: 10)
                
                Image(systemName: stepIcon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.white)
            }
            .scaleEffect(isAnimating ? 1 : 0.8)
            .opacity(isAnimating ? 1 : 0)
            
            // Title
            VStack(spacing: 8) {
                Text(stepTitle)
                    .font(.clashGroteskBold(size: 32))
                    .foregroundColor(.white)
                
                Text(stepSubtitle)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            // Step indicator
            stepIndicator
        }
    }
    
    private var stepIcon: String {
        switch step {
        case .welcome: return "sparkles"
        case .security: return "lock.shield.fill"
        case .passcode: return "key.fill"
        case .ready: return "checkmark.seal.fill"
        }
    }
    
    private var stepTitle: String {
        switch step {
        case .welcome: return "Welcome to Hawala"
        case .security: return "Security First"
        case .passcode: return "Protect Your Wallet"
        case .ready: return "You're All Set"
        }
    }
    
    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index <= step.rawValue ? HawalaTheme.Colors.accent : Color.white.opacity(0.2))
                    .frame(width: index == step.rawValue ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: step)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Content Card
    private var contentCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            contentBody
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity.combined(with: .move(edge: .leading))
        ))
    }
    
    @ViewBuilder
    private var contentBody: some View {
        switch step {
        case .welcome:
            welcomeContent
        case .security:
            securityContent
        case .passcode:
            passcodeContent
        case .ready:
            readyContent
        }
    }
    
    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Let's prepare your multi-chain vault with the right safeguards and workflows.")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(Color.white.opacity(0.8))
                .lineSpacing(4)
            
            VStack(alignment: .leading, spacing: 14) {
                onboardingFeatureRow(
                    icon: "key.horizontal.fill",
                    title: "Multi-Chain Keys",
                    description: "Generate secure keys across 40+ blockchains"
                )
                onboardingFeatureRow(
                    icon: "lock.shield.fill",
                    title: "Encrypted Backups",
                    description: "Keep your recovery data safe and portable"
                )
                onboardingFeatureRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Portfolio Tracking",
                    description: "Monitor balances, prices, and history"
                )
            }
        }
    }
    
    private var securityContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("This app handles private keys and recovery phrases. Please review these security essentials:")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(Color.white.opacity(0.8))
                .lineSpacing(4)
            
            VStack(alignment: .leading, spacing: 12) {
                securityBullet("Never screenshot or paste keys into untrusted apps", icon: "camera.fill", color: .red)
                securityBullet("Store exports encrypted and offline when possible", icon: "externaldrive.fill", color: .orange)
                securityBullet("Lock the app before leaving your device unattended", icon: "lock.fill", color: .yellow)
                securityBullet("Consider hardware wallets for long-term storage", icon: "cpu.fill", color: .green)
            }
        }
    }
    
    private var passcodeContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add a passcode to protect your wallet. You can change this anytime in Settings.")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(Color.white.opacity(0.8))
                .lineSpacing(4)
            
            VStack(spacing: 16) {
                styledSecureField("Enter passcode", text: $passcode, isFocused: true)
                styledSecureField("Confirm passcode", text: $confirmPasscode, isFocused: false)
                
                if let errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(HawalaTheme.Colors.error)
                        Text(errorMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(HawalaTheme.Colors.error)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(HawalaTheme.Colors.error.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }
    
    private var readyContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your security preferences are saved. You're ready to start using Hawala!")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(Color.white.opacity(0.8))
                .lineSpacing(4)
            
            VStack(alignment: .leading, spacing: 14) {
                readyCheckmark("Generate and manage keys for 40+ chains")
                readyCheckmark("Send and receive cryptocurrency securely")
                readyCheckmark("Export encrypted backups anytime")
                readyCheckmark("Customize security settings as needed")
            }
        }
    }
    
    // MARK: - Helper Views
    private func onboardingFeatureRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(HawalaTheme.Colors.accent.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(HawalaTheme.Colors.accent)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text(description)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.5))
            }
        }
    }
    
    private func securityBullet(_ text: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(color.opacity(0.8))
                .frame(width: 20)
            
            Text(text)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(Color.white.opacity(0.8))
                .lineSpacing(2)
        }
    }
    
    private func readyCheckmark(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(HawalaTheme.Colors.success)
            
            Text(text)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(Color.white.opacity(0.8))
        }
    }
    
    private func styledSecureField(_ placeholder: String, text: Binding<String>, isFocused: Bool) -> some View {
        HStack {
            Image(systemName: "lock.fill")
                .font(.system(size: 14))
                .foregroundColor(Color.white.opacity(0.4))
            
            SecureField(placeholder, text: text)
                .textContentType(.password)
                .font(.system(size: 15))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Controls
    private var controlsSection: some View {
        HStack(spacing: 12) {
            if step != .welcome {
                Button(action: goBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Back")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.7))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            if step == .passcode {
                Button(action: skipPasscode) {
                    Text("Skip for now")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
            
            primaryButton
        }
    }
    
    private var primaryButton: some View {
        Button(action: primaryAction) {
            HStack(spacing: 8) {
                Text(primaryButtonText)
                if step == .ready {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [HawalaTheme.Colors.accent, HawalaTheme.Colors.accent.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: HawalaTheme.Colors.accent.opacity(0.4), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
    
    private var primaryButtonText: String {
        switch step {
        case .welcome: return "Get Started"
        case .security: return "I Understand"
        case .passcode: return "Save Passcode"
        case .ready: return "Enter Hawala"
        }
    }
    
    private func primaryAction() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            switch step {
            case .welcome:
                step = .security
            case .security:
                onSecurityAcknowledged()
                step = .passcode
            case .passcode:
                handlePasscodeSave()
            case .ready:
                onFinish()
            }
        }
    }
    
    private func goBack() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            switch step {
            case .welcome: break
            case .security: step = .welcome
            case .passcode: step = .security
            case .ready: step = .passcode
            }
        }
    }
    
    private func skipPasscode() {
        passcode = ""
        confirmPasscode = ""
        errorMessage = nil
        onSkipPasscode()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            step = .ready
        }
    }

    private var stepSubtitle: String {
        switch step {
        case .welcome:
            return "Configure your secure workspace before generating keys."
        case .security:
            return "Understand the responsibilities of handling private keys."
        case .passcode:
            return "Add session protection to keep your keys secure."
        case .ready:
            return "Everything is in place—let's launch your dashboard."
        }
    }

    private func handlePasscodeSave() {
        let trimmed = passcode.trimmingCharacters(in: .whitespacesAndNewlines)
        let confirmation = confirmPasscode.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count >= 6 else {
            errorMessage = "Choose at least 6 characters."
            passcodeFieldFocused = true
            return
        }

        guard trimmed == confirmation else {
            errorMessage = "Passcodes do not match."
            confirmPasscode = ""
            passcodeFieldFocused = true
            return
        }

        errorMessage = nil
        onSetPasscode(trimmed)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            step = .ready
        }
    }
}

// MARK: - Preview
#if DEBUG
struct OnboardingFlowView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingFlowView(
            step: .constant(.welcome),
            onSecurityAcknowledged: {},
            onSetPasscode: { _ in },
            onSkipPasscode: {},
            onFinish: {}
        )
    }
}
#endif
