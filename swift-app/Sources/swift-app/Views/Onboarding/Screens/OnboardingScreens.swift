import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Welcome Screen
/// First screen of onboarding - sets premium tone
struct WelcomeScreen: View {
    let onContinue: () -> Void
    
    @State private var animateContent = false
    @State private var animateLogo = false
    @State private var animateGlow = false
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Logo and tagline
            VStack(spacing: 24) {
                // Animated logo with glow
                ZStack {
                    // Glow effect behind text
                    Text("HAWALA")
                        .font(.custom("ClashGrotesk-Bold", size: 56))
                        .foregroundColor(Color(hex: "#00D4FF"))
                        .blur(radius: animateGlow ? 30 : 20)
                        .opacity(animateGlow ? 0.7 : 0.4)
                        .scaleEffect(animateGlow ? 1.1 : 1.0)
                    
                    // Main text
                    Text("HAWALA")
                        .font(.custom("ClashGrotesk-Bold", size: 56))
                        .foregroundColor(.white)
                        .tracking(6)
                }
                .opacity(animateLogo ? 1 : 0)
                .scaleEffect(animateLogo ? 1 : 0.85)
                .floating(amplitude: 3, duration: 3)
                
                Text("Your keys. Your future.")
                    .font(.custom("ClashGrotesk-Regular", size: 18))
                    .foregroundColor(.white.opacity(0.6))
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 10)
            }
            
            Spacer()
            
            // CTA button
            VStack(spacing: 20) {
                OnboardingPrimaryButton(title: "Let's Go", action: {
                    #if canImport(AppKit)
                    OnboardingHaptics.light()
                    #endif
                    onContinue()
                }, style: .glass)
                    .frame(maxWidth: 300)
                
                // Keyboard hint for macOS
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
            .opacity(animateContent ? 1 : 0)
            .offset(y: animateContent ? 0 : 20)
            
            Spacer()
                .frame(height: 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Staggered animations
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                animateLogo = true
            }
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                animateGlow = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 0.6)) {
                    animateContent = true
                }
            }
        }
    }
}

// MARK: - Path Selection Screen
/// User chooses between Quick and Guided onboarding
struct PathSelectionScreen: View {
    @Binding var useQuickSetup: Bool
    let onCreateNew: () -> Void
    let onImport: () -> Void
    let onHardware: () -> Void
    
    @State private var animateContent = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Title
            VStack(spacing: 8) {
                Text("What brings you here?")
                    .font(.custom("ClashGrotesk-Bold", size: 32))
                    .foregroundColor(.white)
            }
            .opacity(animateContent ? 1 : 0)
            .offset(y: animateContent ? 0 : 10)
            
            Spacer()
                .frame(height: 20)
            
            // Selection cards
            VStack(spacing: 14) {
                SelectionCard(
                    icon: "plus.circle.fill",
                    title: "Create New Wallet",
                    subtitle: "Start fresh with a new self-custody wallet",
                    action: onCreateNew
                )
                
                SelectionCard(
                    icon: "arrow.down.doc.fill",
                    title: "Import Existing Wallet",
                    subtitle: "Bring your keys from another wallet",
                    action: onImport
                )
                
                SelectionCard(
                    icon: "cpu",
                    title: "Connect Hardware Wallet",
                    subtitle: "Ledger, Trezor, and more",
                    action: onHardware
                )
            }
            .padding(.horizontal, 24)
            .opacity(animateContent ? 1 : 0)
            .offset(y: animateContent ? 0 : 15)
            
            Spacer()
            
            // Quick/Guided toggle
            VStack(spacing: 16) {
                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.horizontal, 24)
                
                HStack(spacing: 24) {
                    SetupModeButton(
                        title: "Quick Setup",
                        subtitle: "Skip education, fast setup",
                        isSelected: useQuickSetup
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            useQuickSetup = true
                        }
                    }
                    
                    SetupModeButton(
                        title: "Guided Setup",
                        subtitle: "Full walkthrough",
                        isSelected: !useQuickSetup
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            useQuickSetup = false
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .opacity(animateContent ? 1 : 0)
            
            Spacer()
                .frame(height: 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                animateContent = true
            }
        }
    }
}

struct SetupModeButton: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isSelected ? Color.white : Color.clear)
                        .frame(width: 8, height: 8)
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.4), lineWidth: 1)
                        }
                    
                    Text(title)
                        .font(.custom("ClashGrotesk-Semibold", size: 14))
                        .foregroundColor(.white)
                }
                
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.white.opacity(0.1) : Color.white.opacity(isHovered ? 0.05 : 0.02))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.white.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Self-Custody Education Screen
/// Educates user about self-custody (Guided path only)
struct SelfCustodyEducationScreen: View {
    let onContinue: () -> Void
    let onLearnMore: () -> Void
    
    @State private var animateContent = false
    @State private var currentCardIndex = 0
    
    private let educationCards: [(icon: String, title: String, description: String)] = [
        ("key.fill", "You own your keys", "No company can freeze your funds or lock you out"),
        ("lock.shield.fill", "You control access", "Your recovery phrase is the only way to restore access"),
        ("exclamationmark.shield.fill", "You're protected", "Hawala warns you before risky transactions")
    ]
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Title
            VStack(spacing: 12) {
                Text("Your wallet. Your rules.")
                    .font(.custom("ClashGrotesk-Bold", size: 32))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .opacity(animateContent ? 1 : 0)
            .offset(y: animateContent ? 0 : 10)
            
            // Animated key icon
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "key.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(.white.opacity(0.8))
                    .rotationEffect(.degrees(animateContent ? -45 : 0))
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animateContent)
            }
            .padding(.vertical, 20)
            
            // Education cards
            VStack(spacing: 12) {
                ForEach(Array(educationCards.enumerated()), id: \.offset) { index, card in
                    OnboardingInfoCard(
                        icon: card.icon,
                        title: card.title,
                        description: card.description
                    )
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 10)
                    .animation(.easeOut(duration: 0.4).delay(Double(index) * 0.1 + 0.2), value: animateContent)
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Buttons
            VStack(spacing: 12) {
                OnboardingPrimaryButton(title: "I Understand", action: onContinue, style: .glass)
                
                OnboardingSecondaryButton(title: "Learn more", action: onLearnMore)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 50)
            .opacity(animateContent ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation {
                animateContent = true
            }
        }
    }
}

// MARK: - Persona Selection Screen
/// User selects their persona for personalized experience (Guided path only)
struct PersonaSelectionScreen: View {
    @Binding var selectedPersona: UserPersona?
    let onContinue: () -> Void
    let onSkip: () -> Void
    
    @State private var animateContent = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Title
            VStack(spacing: 8) {
                Text("How will you use Hawala?")
                    .font(.custom("ClashGrotesk-Bold", size: 28))
                    .foregroundColor(.white)
                
                Text("We'll customize your experience")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
            }
            .opacity(animateContent ? 1 : 0)
            
            Spacer()
                .frame(height: 20)
            
            // Persona grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                ForEach(UserPersona.allCases) { persona in
                    PersonaCard(
                        icon: persona.icon,
                        title: persona.title,
                        tagline: persona.tagline,
                        isSelected: selectedPersona == persona
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            selectedPersona = persona
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .opacity(animateContent ? 1 : 0)
            .offset(y: animateContent ? 0 : 15)
            
            Spacer()
            
            // Buttons
            VStack(spacing: 12) {
                OnboardingPrimaryButton(
                    title: "Continue",
                    action: onContinue,
                    isDisabled: selectedPersona == nil,
                    style: .glass
                )
                
                OnboardingSecondaryButton(title: "I'm not sure yet", action: onSkip)
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

// MARK: - Create/Import Selection Screen
/// User chooses how to create or import their wallet
struct CreateImportScreen: View {
    @Binding var selectedMethod: WalletCreationMethod
    let onContinue: () -> Void
    var isQuickPath: Bool = false
    
    init(selectedMethod: Binding<WalletCreationMethod>, onContinue: @escaping () -> Void, onBack: (() -> Void)? = nil) {
        self._selectedMethod = selectedMethod
        self.onContinue = onContinue
        self.isQuickPath = false
    }
    
    @State private var animateContent = false
    
    private var availableMethods: [WalletCreationMethod] {
        if isQuickPath {
            return [.create, .importSeed, .ledger]
        }
        return WalletCreationMethod.allCases
    }
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Title
            VStack(spacing: 8) {
                Text("Get started")
                    .font(.custom("ClashGrotesk-Bold", size: 28))
                    .foregroundColor(.white)
                
                Text("Choose how to set up your wallet")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
            }
            .opacity(animateContent ? 1 : 0)
            
            Spacer()
                .frame(height: 20)
            
            // Method cards
            VStack(spacing: 12) {
                ForEach(availableMethods) { method in
                    SelectionCard(
                        icon: method.icon,
                        title: method.title,
                        subtitle: method.subtitle,
                        isSelected: selectedMethod == method
                    ) {
                        withAnimation(.spring(response: 0.2)) {
                            selectedMethod = method
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            onContinue()
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .opacity(animateContent ? 1 : 0)
            .offset(y: animateContent ? 0 : 10)
            
            Spacer()
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
struct OnboardingScreens_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            WelcomeScreen {
                print("Continue")
            }
        }
        .preferredColorScheme(.dark)
    }
}
#endif
