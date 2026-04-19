import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Feedback Manager
/// Manages sound and haptic feedback for premium UX
/// Supports macOS trackpad haptics and system sounds

@MainActor
final class FeedbackManager: ObservableObject {
    static let shared = FeedbackManager()
    
    // MARK: - Settings
    @AppStorage("hawala.soundFeedbackEnabled") private var soundEnabled = true
    @AppStorage("hawala.hapticFeedbackEnabled") private var hapticEnabled = true
    
    private init() {}
    
    // MARK: - Feedback Types
    
    enum FeedbackType {
        // Positive outcomes
        case success          // Task completed successfully
        case walletCreated    // New wallet generated
        case transactionSent  // Transaction broadcast
        case backupComplete   // Backup saved successfully
        
        // Interactions
        case buttonTap        // Standard button press
        case toggle           // Toggle switch changed
        case selection        // Item selected from list
        case tabSwitch        // Tab navigation
        
        // Input feedback
        case keyPress         // Keyboard input (PIN entry)
        case wordValidated    // Seed word validated
        case wordInvalid      // Invalid seed word
        
        // Navigation
        case screenTransition // Moving between screens
        case sheetPresented   // Modal sheet appeared
        case sheetDismissed   // Modal sheet closed
        
        // Warnings/Errors
        case warning          // Non-critical warning
        case error            // Error occurred
        case criticalAlert    // Critical security alert
        
        // Progress
        case progressStep     // Step completed in multi-step flow
        case loading          // Loading started
        case loadingComplete  // Loading finished
    }
    
    // MARK: - Public API
    
    func trigger(_ type: FeedbackType) {
        if hapticEnabled {
            triggerHaptic(for: type)
        }
        if soundEnabled {
            playSound(for: type)
        }
    }
    
    func triggerHapticOnly(_ type: FeedbackType) {
        guard hapticEnabled else { return }
        triggerHaptic(for: type)
    }
    
    func playSoundOnly(_ type: FeedbackType) {
        guard soundEnabled else { return }
        playSound(for: type)
    }
    
    // MARK: - Haptic Feedback (macOS)
    
    private func triggerHaptic(for type: FeedbackType) {
        #if os(macOS)
        let performer = NSHapticFeedbackManager.defaultPerformer
        
        switch type {
        case .success, .walletCreated, .transactionSent, .backupComplete:
            // Strong generic haptic for success
            performer.perform(.generic, performanceTime: .now)
            // Double tap for emphasis
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                performer.perform(.generic, performanceTime: .now)
            }
            
        case .buttonTap, .selection, .toggle:
            // Light tap for interactions
            performer.perform(.alignment, performanceTime: .now)
            
        case .keyPress:
            // Subtle tap for each key
            performer.perform(.alignment, performanceTime: .now)
            
        case .wordValidated, .progressStep:
            // Generic confirmation
            performer.perform(.generic, performanceTime: .now)
            
        case .wordInvalid, .error:
            // Level change for errors (more noticeable)
            performer.perform(.levelChange, performanceTime: .now)
            
        case .warning, .criticalAlert:
            // Strong level change for alerts
            performer.perform(.levelChange, performanceTime: .now)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                performer.perform(.levelChange, performanceTime: .now)
            }
            
        case .screenTransition, .tabSwitch:
            // Subtle haptic for navigation
            performer.perform(.alignment, performanceTime: .now)
            
        case .sheetPresented, .sheetDismissed:
            performer.perform(.generic, performanceTime: .now)
            
        case .loading, .loadingComplete:
            // No haptic for loading states
            break
        }
        #endif
    }
    
    // MARK: - Sound Feedback (macOS)
    
    private func playSound(for type: FeedbackType) {
        #if os(macOS)
        let soundName: String?
        
        switch type {
        case .success, .walletCreated, .transactionSent, .backupComplete:
            soundName = "Glass" // Positive chime
            
        case .buttonTap, .selection:
            soundName = "Tink" // Subtle click
            
        case .toggle:
            soundName = "Pop" // Toggle sound
            
        case .keyPress:
            soundName = nil // Keyboard clicks handled by system
            
        case .wordValidated, .progressStep:
            soundName = "Morse" // Subtle confirmation
            
        case .wordInvalid:
            soundName = "Basso" // Error tone
            
        case .error:
            soundName = "Sosumi" // Error sound
            
        case .warning:
            soundName = "Purr" // Warning sound
            
        case .criticalAlert:
            soundName = "Ping" // Alert sound
            
        case .screenTransition, .tabSwitch:
            soundName = nil // Silent navigation
            
        case .sheetPresented:
            soundName = "Pop" // Sheet appear
            
        case .sheetDismissed:
            soundName = nil // Silent dismiss
            
        case .loading:
            soundName = nil // No sound for loading start
            
        case .loadingComplete:
            soundName = "Blow" // Subtle completion
        }
        
        if let name = soundName {
            NSSound(named: NSSound.Name(name))?.play()
        }
        #endif
    }
    
    // MARK: - Settings
    
    var isSoundEnabled: Bool {
        get { soundEnabled }
        set { soundEnabled = newValue }
    }
    
    var isHapticEnabled: Bool {
        get { hapticEnabled }
        set { hapticEnabled = newValue }
    }
}

// MARK: - View Modifier for Feedback

struct FeedbackModifier: ViewModifier {
    let type: FeedbackManager.FeedbackType
    let trigger: Bool
    
    func body(content: Content) -> some View {
        content
            .onChange(of: trigger) { newValue in
                if newValue {
                    Task { @MainActor in
                        FeedbackManager.shared.trigger(type)
                    }
                }
            }
    }
}

extension View {
    /// Triggers feedback when the condition becomes true
    func feedback(_ type: FeedbackManager.FeedbackType, when trigger: Bool) -> some View {
        modifier(FeedbackModifier(type: type, trigger: trigger))
    }
    
    /// Triggers feedback on tap
    func feedbackOnTap(_ type: FeedbackManager.FeedbackType = .buttonTap, action: @escaping () -> Void) -> some View {
        self.onTapGesture {
            Task { @MainActor in
                FeedbackManager.shared.trigger(type)
            }
            action()
        }
    }
}

// MARK: - Button Style with Feedback

struct FeedbackButtonStyle: ButtonStyle {
    let feedbackType: FeedbackManager.FeedbackType
    
    init(_ type: FeedbackManager.FeedbackType = .buttonTap) {
        self.feedbackType = type
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { isPressed in
                if isPressed {
                    Task { @MainActor in
                        FeedbackManager.shared.triggerHapticOnly(feedbackType)
                    }
                }
            }
    }
}

// MARK: - Onboarding Sound Effects

extension FeedbackManager {
    /// Play a custom onboarding sound sequence
    func playOnboardingWelcome() {
        #if os(macOS)
        guard soundEnabled else { return }
        // Play a welcoming chime
        NSSound(named: NSSound.Name("Glass"))?.play()
        #endif
    }
    
    /// Play success fanfare for wallet creation
    func playWalletCreatedFanfare() {
        #if os(macOS)
        guard soundEnabled else { return }
        // Play success sequence
        NSSound(named: NSSound.Name("Glass"))?.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSSound(named: NSSound.Name("Hero"))?.play()
        }
        #endif
    }
    
    /// Play completion sound for onboarding finish
    func playOnboardingComplete() {
        #if os(macOS)
        guard soundEnabled else { return }
        NSSound(named: NSSound.Name("Funk"))?.play()
        #endif
    }
}

// MARK: - Preview Helpers

#if DEBUG
struct FeedbackTestView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Feedback Test")
                .font(.headline)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                feedbackButton("Success", .success)
                feedbackButton("Button Tap", .buttonTap)
                feedbackButton("Toggle", .toggle)
                feedbackButton("Selection", .selection)
                feedbackButton("Word Valid", .wordValidated)
                feedbackButton("Word Invalid", .wordInvalid)
                feedbackButton("Error", .error)
                feedbackButton("Warning", .warning)
                feedbackButton("Alert", .criticalAlert)
                feedbackButton("Progress", .progressStep)
            }
            .padding()
        }
        .frame(width: 400, height: 300)
    }
    
    private func feedbackButton(_ title: String, _ type: FeedbackManager.FeedbackType) -> some View {
        Button(title) {
            FeedbackManager.shared.trigger(type)
        }
        .buttonStyle(.borderedProminent)
    }
}

struct FeedbackTestView_Previews: PreviewProvider {
    static var previews: some View {
        FeedbackTestView()
    }
}
#endif
