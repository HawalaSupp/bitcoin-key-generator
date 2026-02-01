import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Accessibility Manager
/// Manages accessibility features including keyboard navigation,
/// VoiceOver support, and reduced motion preferences

@MainActor
final class AccessibilityManager: ObservableObject {
    static let shared = AccessibilityManager()
    
    // MARK: - State
    @Published var isVoiceOverEnabled: Bool = false
    @Published var isReduceMotionEnabled: Bool = false
    @Published var isReduceTransparencyEnabled: Bool = false
    @Published var isHighContrastEnabled: Bool = false
    
    // Focus state for keyboard navigation
    @Published var currentFocusID: String?
    
    private init() {
        updateAccessibilityState()
        setupObservers()
    }
    
    // MARK: - Update State
    
    private func updateAccessibilityState() {
        #if os(macOS)
        isVoiceOverEnabled = NSWorkspace.shared.isVoiceOverEnabled
        isReduceMotionEnabled = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        isReduceTransparencyEnabled = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        isHighContrastEnabled = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        #endif
    }
    
    private func setupObservers() {
        #if os(macOS)
        // Observe accessibility changes
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateAccessibilityState()
            }
        }
        #endif
    }
    
    // MARK: - Animation Duration
    
    /// Returns appropriate animation duration based on reduce motion preference
    var standardAnimationDuration: Double {
        isReduceMotionEnabled ? 0.0 : 0.3
    }
    
    /// Returns appropriate spring animation
    var springAnimation: Animation {
        isReduceMotionEnabled 
            ? .linear(duration: 0.1)
            : .spring(response: 0.35, dampingFraction: 0.7)
    }
    
    /// Returns animation or nil if reduce motion is enabled
    func animation(_ animation: Animation) -> Animation? {
        isReduceMotionEnabled ? nil : animation
    }
}

// MARK: - Keyboard Navigation Focus State

enum FocusableArea: Hashable {
    case navigation(Int)
    case portfolioAsset(String)
    case actionButton(String)
    case settingsItem(String)
    case textField(String)
    case seedWord(Int)
    case custom(String)
}

// MARK: - Focusable Container View

struct KeyboardNavigableContainer<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
    }
}

// MARK: - Focus Environment Key (simplified for macOS 13 compatibility)

// Note: Full keyboard navigation with onKeyPress requires macOS 14+
// This provides basic accessibility support for macOS 13

// MARK: - Accessibility View Modifiers

extension View {
    /// Makes view focusable for keyboard navigation with custom ID
    func keyboardFocusable(_ area: FocusableArea) -> some View {
        self
            .focusable()
            .accessibilityAddTraits(.isButton)
    }
    
    /// Adds accessibility label for VoiceOver
    func accessibleLabel(_ label: String, hint: String? = nil) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
    }
    
    /// Marks as header for VoiceOver navigation
    func accessibleHeader() -> some View {
        self.accessibilityAddTraits(.isHeader)
    }
    
    /// Applies animation respecting reduce motion preference
    func accessibleAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        self.animation(
            AccessibilityManager.shared.isReduceMotionEnabled ? nil : animation,
            value: value
        )
    }
    
    /// Reduces opacity for reduce transparency mode
    func accessibleMaterial() -> some View {
        modifier(AccessibleMaterialModifier())
    }
}

// MARK: - Accessible Material Modifier

struct AccessibleMaterialModifier: ViewModifier {
    @ObservedObject private var accessibilityManager = AccessibilityManager.shared
    
    func body(content: Content) -> some View {
        if accessibilityManager.isReduceTransparencyEnabled {
            content
                .background(Color(NSColor.windowBackgroundColor))
        } else {
            content
                .background(.ultraThinMaterial)
        }
    }
}

// MARK: - Accessible Button Style

struct AccessibleButtonStyle: ButtonStyle {
    @ObservedObject private var accessibilityManager = AccessibilityManager.shared
    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1.0) : 0.5)
            .scaleEffect(configuration.isPressed && !accessibilityManager.isReduceMotionEnabled ? 0.97 : 1.0)
            .animation(
                accessibilityManager.isReduceMotionEnabled ? nil : .easeOut(duration: 0.15),
                value: configuration.isPressed
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .opacity(0) // Focus ring handled by system
            )
    }
}

// MARK: - Skip Navigation Link (for VoiceOver)

struct SkipNavigationButton: View {
    let destination: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text("Skip to \(destination)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Skip to \(destination)")
    }
}

// MARK: - High Contrast Colors

extension Color {
    /// Returns high contrast alternative if accessibility setting is enabled
    @MainActor
    func highContrastAlternative(_ alternative: Color) -> Color {
        AccessibilityManager.shared.isHighContrastEnabled ? alternative : self
    }
}

// MARK: - Accessible Onboarding Components

struct AccessibleOnboardingStep: View {
    let stepNumber: Int
    let totalSteps: Int
    let title: String
    let isComplete: Bool
    let isCurrent: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            // Step indicator
            ZStack {
                Circle()
                    .fill(isComplete ? Color.green : (isCurrent ? Color.accentColor : Color.gray.opacity(0.3)))
                    .frame(width: 28, height: 28)
                
                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("\(stepNumber)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(isCurrent ? .white : .gray)
                }
            }
            
            Text(title)
                .font(.system(size: 14, weight: isCurrent ? .semibold : .regular))
                .foregroundColor(isCurrent ? .white : .gray)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(stepNumber) of \(totalSteps): \(title)")
        .accessibilityValue(isComplete ? "Complete" : (isCurrent ? "Current step" : "Not started"))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

// MARK: - Screen Reader Announcements

extension View {
    /// Announces text to VoiceOver when triggered
    func announceToVoiceOver(_ announcement: String, when trigger: Bool) -> some View {
        self.onChange(of: trigger) { newValue in
            if newValue {
                #if os(macOS)
                NSAccessibility.post(element: NSApp.mainWindow as Any, notification: .announcementRequested, userInfo: [
                    NSAccessibility.NotificationUserInfoKey.announcement: announcement,
                    NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue
                ])
                #endif
            }
        }
    }
}

// MARK: - Focus Ring Modifier

struct FocusRingModifier: ViewModifier {
    let isVisible: Bool
    let cornerRadius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .padding(-4)
                    .opacity(isVisible ? 1 : 0)
            )
    }
}

extension View {
    func focusRing(isVisible: Bool, cornerRadius: CGFloat = 8) -> some View {
        modifier(FocusRingModifier(isVisible: isVisible, cornerRadius: cornerRadius))
    }
}

// MARK: - Preview

#if DEBUG
struct AccessibilityPreview: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            Text("Accessibility Test")
                .font(.headline)
                .accessibleHeader()
            
            AccessibleOnboardingStep(
                stepNumber: 1,
                totalSteps: 4,
                title: "Welcome",
                isComplete: true,
                isCurrent: false
            )
            
            AccessibleOnboardingStep(
                stepNumber: 2,
                totalSteps: 4,
                title: "Security",
                isComplete: false,
                isCurrent: true
            )
            
            Button("Test Button") {}
                .buttonStyle(AccessibleButtonStyle())
                .keyboardFocusable(.actionButton("test"))
        }
        .padding()
        .frame(width: 300, height: 300)
        .background(Color.black)
    }
}
#endif
