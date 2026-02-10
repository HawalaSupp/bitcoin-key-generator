import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Onboarding Component Library
// Premium, reusable components for the Hawala onboarding experience

// MARK: - Onboarding Progress Indicator
/// Subtle progress bar showing onboarding completion
struct OnboardingProgressIndicator: View {
    let currentStep: Int
    let totalSteps: Int
    
    private var progress: CGFloat {
        guard totalSteps > 0 else { return 0 }
        return CGFloat(currentStep) / CGFloat(totalSteps)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 3)
                    
                    // Progress fill
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.5), Color.white.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress, height: 3)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)
                }
            }
            .frame(height: 3)
            
            // Step indicator text
            HStack {
                Text("Step \(currentStep) of \(totalSteps)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                
                Spacer()
            }
        }
        .frame(maxWidth: 400)
    }
}

// MARK: - Glass Card Component
/// A frosted glass-effect container for content (onboarding-specific)
struct OnboardingCard<Content: View>: View {
    let content: Content
    var isSelected: Bool = false
    var padding: CGFloat = 24
    
    init(isSelected: Bool = false, padding: CGFloat = 24, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.isSelected = isSelected
        self.padding = padding
    }
    
    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg)
                    .fill(Color.white.opacity(isSelected ? 0.12 : 0.05))
            }
            .overlay {
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg)
                    .stroke(
                        isSelected ? Color.white.opacity(0.4) : Color.white.opacity(0.1),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
    }
}

// MARK: - Onboarding Primary Button
/// Full-width, high-emphasis button for main actions
struct OnboardingPrimaryButton: View {
    let title: String
    let action: () -> Void
    var isLoading: Bool = false
    var isDisabled: Bool = false
    var style: ButtonStyle = .filled
    
    enum ButtonStyle {
        case filled      // White background, dark text
        case glass       // Glass background, white text
        case accent      // Accent color background
    }
    
    var body: some View {
        Button(action: {
            // Trigger premium feedback
            FeedbackManager.shared.trigger(.buttonTap)
            action()
        }) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(style == .filled ? .black : .white)
                }
                Text(title)
                    .font(.custom("ClashGrotesk-Semibold", size: 16))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(backgroundView)
            .foregroundColor(foregroundColor)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isLoading ? "Loading" : "")
        .scaleEffect(isLoading ? 0.98 : 1.0)
        .animation(HawalaTheme.Animation.fast, value: isLoading)
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        switch style {
        case .filled:
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg)
                .fill(isDisabled ? Color.white.opacity(0.3) : Color.white)
        case .glass:
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg)
                .fill(Color.white.opacity(0.15))
                .overlay {
                    RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                }
        case .accent:
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg)
                .fill(Color(hex: "#32D74B").opacity(isDisabled ? 0.3 : 1.0))
        }
    }
    
    private var foregroundColor: Color {
        switch style {
        case .filled:
            return isDisabled ? .white.opacity(0.5) : .black
        case .glass, .accent:
            return isDisabled ? .white.opacity(0.5) : .white
        }
    }
}

// MARK: - Secondary Button (Ghost)
/// Low-emphasis button for secondary actions
struct OnboardingSecondaryButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void
    
    init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.icon = nil
        self.action = action
    }
    
    init(title: String, icon: String, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            FeedbackManager.shared.trigger(.buttonTap)
            action()
        }) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                }
                Text(title)
                    .font(.custom("ClashGrotesk-Medium", size: 14))
            }
            .foregroundColor(.white.opacity(isHovered ? 0.9 : 0.7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .onHover { hovering in
            withAnimation(HawalaTheme.Animation.fast) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Info Card
/// Card with icon, title, and description for feature highlights
struct OnboardingInfoCard: View {
    let icon: String
    let title: String
    let description: String
    var iconColor: Color = .white
    var useSystemIcon: Bool = true
    
    var body: some View {
        GlassCard(padding: 20) {
            HStack(alignment: .top, spacing: 16) {
                if useSystemIcon {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(iconColor.opacity(0.8))
                        .frame(width: 28)
                } else {
                    Text(icon)
                        .font(.system(size: 24))
                        .frame(width: 28)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.custom("ClashGrotesk-Semibold", size: 15))
                        .foregroundColor(.white)
                    
                    Text(description)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.white.opacity(0.6))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Toggle Row
/// Settings-style row with label, description, and toggle
struct OnboardingToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    var icon: String? = nil
    
    var body: some View {
        HStack(spacing: 16) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 24)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("ClashGrotesk-Medium", size: 14))
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .tint(Color(hex: "#32D74B"))
                .scaleEffect(0.85)
        }
        .padding(.vertical, HawalaTheme.Spacing.md)
    }
}

// MARK: - Chip Selector
/// Horizontal scrolling multi-select chips
struct OnboardingChipSelector: View {
    let options: [ChipOption]
    @Binding var selected: Set<String>
    
    struct ChipOption: Identifiable {
        let id: String
        let label: String
        var icon: String? = nil
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(options) { option in
                    ChipView(
                        label: option.label,
                        icon: option.icon,
                        isSelected: selected.contains(option.id)
                    ) {
                        if selected.contains(option.id) {
                            selected.remove(option.id)
                        } else {
                            selected.insert(option.id)
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

struct ChipView: View {
    let label: String
    var icon: String?
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Text(icon)
                        .font(.system(size: 14))
                }
                Text(label)
                    .font(.custom("ClashGrotesk-Medium", size: 13))
            }
            .padding(.horizontal, HawalaTheme.Spacing.lg)
            .padding(.vertical, HawalaTheme.Spacing.sm)
            .background {
                Capsule()
                    .fill(isSelected ? Color.white.opacity(0.2) : Color.white.opacity(isHovered ? 0.08 : 0.05))
            }
            .overlay {
                Capsule()
                    .stroke(isSelected ? Color.white.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1)
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.7))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(HawalaTheme.Animation.fast) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Progress Indicator (Dots)
/// Step indicator dots for onboarding flow
struct OnboardingDotsIndicator: View {
    let totalSteps: Int
    let currentStep: Int
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index <= currentStep ? Color.white : Color.white.opacity(0.3))
                    .frame(width: index == currentStep ? 10 : 6, height: index == currentStep ? 10 : 6)
            }
        }
        .animation(HawalaTheme.Animation.spring, value: currentStep)
    }
}

// MARK: - Security Score Ring
/// Circular progress indicator showing security completion
struct SecurityScoreRing: View {
    let score: Int
    let maxScore: Int
    var size: CGFloat = 120
    var lineWidth: CGFloat = 8
    
    private var progress: Double {
        Double(score) / Double(maxScore)
    }
    
    private var scoreColor: Color {
        switch score {
        case 0..<40: return .red
        case 40..<70: return .orange
        case 70..<90: return .yellow
        default: return Color(hex: "#32D74B")
        }
    }
    
    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: lineWidth)
            
            // Progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(scoreColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            
            // Score text
            VStack(spacing: 2) {
                Text("\(score)")
                    .font(.custom("ClashGrotesk-Bold", size: size * 0.28))
                    .foregroundColor(.white)
                
                Text("/ \(maxScore)")
                    .font(.system(size: size * 0.1, weight: .regular))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(width: size, height: size)
        .animation(HawalaTheme.Animation.slow, value: score)
    }
}

// MARK: - Word Grid (Seed Phrase Display)
/// 3-column grid for displaying recovery phrase words
struct WordGrid: View {
    let words: [String]
    var onCopy: (() -> Void)?
    @State private var showCopied = false
    
    var body: some View {
        VStack(spacing: 16) {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    WordCell(index: index + 1, word: word)
                }
            }
            
            Button(action: {
                onCopy?()
                showCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showCopied = false
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                    Text(showCopied ? "Copied!" : "Copy All")
                }
                .font(.custom("ClashGrotesk-Medium", size: 13))
                .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .animation(.easeInOut, value: showCopied)
        }
    }
}

struct WordCell: View {
    let index: Int
    let word: String
    
    var body: some View {
        HStack(spacing: 8) {
            Text("\(index).")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 22, alignment: .trailing)
            
            Text(word)
                .font(.custom("ClashGrotesk-Medium", size: 14))
                .foregroundColor(.white)
            
            Spacer()
        }
        .padding(.horizontal, HawalaTheme.Spacing.md)
        .padding(.vertical, HawalaTheme.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm)
                .fill(Color.white.opacity(0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        }
    }
}

// MARK: - Word Selector (Verification)
/// Word selection for backup verification
struct WordSelector: View {
    let wordNumber: Int
    let options: [String]
    let correctWord: String
    @Binding var selectedWord: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Word #\(wordNumber)")
                .font(.custom("ClashGrotesk-Medium", size: 13))
                .foregroundColor(.white.opacity(0.6))
            
            HStack(spacing: 10) {
                ForEach(options, id: \.self) { option in
                    WordOptionButton(
                        word: option,
                        isSelected: selectedWord == option,
                        isCorrect: selectedWord == option && option == correctWord,
                        isWrong: selectedWord == option && option != correctWord
                    ) {
                        withAnimation(.spring(response: 0.2)) {
                            selectedWord = option
                        }
                    }
                }
            }
        }
    }
}

struct WordOptionButton: View {
    let word: String
    let isSelected: Bool
    let isCorrect: Bool
    let isWrong: Bool
    let action: () -> Void
    
    private var backgroundColor: Color {
        if isCorrect { return Color(hex: "#32D74B").opacity(0.3) }
        if isWrong { return Color.red.opacity(0.3) }
        if isSelected { return Color.white.opacity(0.2) }
        return Color.white.opacity(0.05)
    }
    
    private var borderColor: Color {
        if isCorrect { return Color(hex: "#32D74B") }
        if isWrong { return Color.red }
        if isSelected { return Color.white.opacity(0.4) }
        return Color.white.opacity(0.1)
    }
    
    var body: some View {
        Button(action: action) {
            Text(word)
                .font(.custom("ClashGrotesk-Medium", size: 14))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(backgroundColor)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(borderColor, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Success State View
/// Animated success state with checkmark
struct SuccessStateView: View {
    let title: String
    var subtitle: String? = nil
    @State private var showCheckmark = false
    @State private var showText = false
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#32D74B").opacity(0.2))
                    .frame(width: 100, height: 100)
                
                Circle()
                    .stroke(Color(hex: "#32D74B").opacity(0.5), lineWidth: 2)
                    .frame(width: 100, height: 100)
                    .scaleEffect(showCheckmark ? 1 : 0.8)
                    .opacity(showCheckmark ? 1 : 0)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(Color(hex: "#32D74B"))
                    .scaleEffect(showCheckmark ? 1 : 0)
                    .opacity(showCheckmark ? 1 : 0)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: showCheckmark)
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.custom("ClashGrotesk-Bold", size: 28))
                    .foregroundColor(.white)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
            }
            .opacity(showText ? 1 : 0)
            .offset(y: showText ? 0 : 10)
            .animation(.easeOut(duration: 0.4).delay(0.2), value: showText)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showCheckmark = true
                showText = true
            }
        }
    }
}

// MARK: - Warning Banner
/// Alert banner for important messages
struct WarningBanner: View {
    let level: Level
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    
    enum Level {
        case info, warning, critical
        
        var color: Color {
            switch self {
            case .info: return .blue
            case .warning: return .orange
            case .critical: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .critical: return "xmark.octagon.fill"
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: level.icon)
                .foregroundColor(level.color)
            
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
            
            Spacer()
            
            if let actionTitle = actionTitle, let action = action {
                Button(actionTitle, action: action)
                    .font(.custom("ClashGrotesk-Medium", size: 13))
                    .foregroundColor(level.color)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(level.color.opacity(0.15))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(level.color.opacity(0.3), lineWidth: 1)
        }
    }
}

// MARK: - Address Display
/// Wallet address with copy/share/QR actions
struct AddressDisplayCard: View {
    let address: String
    var onCopy: (() -> Void)?
    var onShare: (() -> Void)?
    var onShowQR: (() -> Void)?
    
    @State private var isHovering = false
    @State private var copied = false
    
    private var displayAddress: String {
        if isHovering && address.count > 12 {
            return address
        }
        return truncateAddress(address)
    }
    
    private func truncateAddress(_ addr: String) -> String {
        guard addr.count > 14 else { return addr }
        return "\(addr.prefix(8))...\(addr.suffix(6))"
    }
    
    var body: some View {
        GlassCard(padding: 16) {
            HStack(spacing: 16) {
                Text(displayAddress)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                
                Spacer()
                
                HStack(spacing: 12) {
                    AddressActionButton(icon: copied ? "checkmark" : "doc.on.doc") {
                        copyToClipboard()
                    }
                    
                    AddressActionButton(icon: "square.and.arrow.up") {
                        onShare?()
                    }
                    
                    AddressActionButton(icon: "qrcode") {
                        onShowQR?()
                    }
                }
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
    
    private func copyToClipboard() {
        ClipboardHelper.copySensitive(address, timeout: 60)
        copied = true
        onCopy?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}

struct AddressActionButton: View {
    let icon: String
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(isHovered ? 0.9 : 0.7))
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(isHovered ? 0.15 : 0.1))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Persona Card
/// Selection card for user persona in guided onboarding
struct PersonaCard: View {
    let icon: String
    let title: String
    let tagline: String
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Text(icon)
                    .font(.system(size: 32))
                
                VStack(spacing: 4) {
                    Text(title)
                        .font(.custom("ClashGrotesk-Semibold", size: 16))
                        .foregroundColor(.white)
                    
                    Text(tagline)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.white.opacity(0.15) : Color.white.opacity(isHovered ? 0.08 : 0.05))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? Color.white.opacity(0.4) : Color.white.opacity(0.1),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isSelected)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Inline Toast
/// Slide-in notification for confirmations
struct InlineToast: View {
    let message: String
    let type: ToastType
    
    enum ToastType {
        case success, error, info
        
        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .success: return Color(hex: "#32D74B")
            case .error: return .red
            case .info: return .blue
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: type.icon)
                .foregroundColor(type.color)
            
            Text(message)
                .font(.custom("ClashGrotesk-Medium", size: 13))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            Capsule()
                .fill(type.color.opacity(0.2))
        }
        .overlay {
            Capsule()
                .stroke(type.color.opacity(0.3), lineWidth: 1)
        }
    }
}

// MARK: - Skeleton Loader
/// Shimmer loading placeholder
struct SkeletonLoader: View {
    var width: CGFloat? = nil
    var height: CGFloat = 20
    var cornerRadius: CGFloat = 8
    
    @State private var isAnimating = false
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.white.opacity(0.05))
            .frame(width: width, height: height)
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.1),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.5)
                    .offset(x: isAnimating ? geo.size.width : -geo.size.width * 0.5)
                }
                .mask(RoundedRectangle(cornerRadius: cornerRadius))
            }
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Selection Card
/// Large tappable card for path selection
struct SelectionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    var isSelected: Bool = false
    var useSystemIcon: Bool = true
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 48, height: 48)
                    
                    if useSystemIcon {
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                    } else {
                        Text(icon)
                            .font(.system(size: 22))
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.custom("ClashGrotesk-Semibold", size: 16))
                        .foregroundColor(.white)
                    
                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(2)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(20)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(isHovered ? 0.08 : 0.05))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? Color.white.opacity(0.4) : Color.white.opacity(0.1),
                        lineWidth: isSelected ? 1.5 : 1
                    )
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

// MARK: - Security Checklist Item
/// Checkable item for security setup tracking
struct SecurityChecklistItem: View {
    let title: String
    let description: String
    let isCompleted: Bool
    var points: Int = 0
    var action: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(isCompleted ? Color(hex: "#32D74B").opacity(0.2) : Color.white.opacity(0.05))
                    .frame(width: 32, height: 32)
                
                Image(systemName: isCompleted ? "checkmark" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isCompleted ? Color(hex: "#32D74B") : .white.opacity(0.3))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("ClashGrotesk-Medium", size: 14))
                    .foregroundColor(isCompleted ? .white.opacity(0.6) : .white)
                    .strikethrough(isCompleted, color: .white.opacity(0.4))
                
                Text(description)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            if points > 0 && !isCompleted {
                Text("+\(points)")
                    .font(.custom("ClashGrotesk-Medium", size: 12))
                    .foregroundColor(Color(hex: "#32D74B"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule()
                            .fill(Color(hex: "#32D74B").opacity(0.15))
                    }
            }
            
            if let action = action, !isCompleted {
                Button(action: action) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Keyboard Input Handler (macOS)
#if os(macOS)
struct OnboardingKeyboardHandler: NSViewRepresentable {
    var isActive: Bool
    var onKeyPress: (NSEvent) -> Bool
    
    func makeNSView(context: Context) -> OnboardingKeyInputNSView {
        let view = OnboardingKeyInputNSView()
        view.onKeyPress = onKeyPress
        view.isActive = isActive
        return view
    }
    
    func updateNSView(_ nsView: OnboardingKeyInputNSView, context: Context) {
        nsView.onKeyPress = onKeyPress
        nsView.isActive = isActive
        nsView.becomeFirstResponderIfNeeded()
    }
}

class OnboardingKeyInputNSView: NSView {
    var onKeyPress: ((NSEvent) -> Bool)?
    var isActive: Bool = false {
        didSet {
            if isActive {
                becomeFirstResponderIfNeeded()
            }
        }
    }
    
    override var acceptsFirstResponder: Bool { isActive }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        becomeFirstResponderIfNeeded()
    }
    
    func becomeFirstResponderIfNeeded() {
        guard isActive, let window = window else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if window.firstResponder !== self {
                window.makeFirstResponder(self)
            }
        }
    }
    
    override func keyDown(with event: NSEvent) {
        guard isActive else {
            super.keyDown(with: event)
            return
        }
        if let onKeyPress = onKeyPress, onKeyPress(event) {
            return
        }
        super.keyDown(with: event)
    }
}
#endif

// MARK: - Animation Extensions & Modifiers

/// Staggered fade-in animation for list items
struct StaggeredFadeIn: ViewModifier {
    let index: Int
    let isVisible: Bool
    let baseDelay: Double
    let staggerDelay: Double
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 20)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.8)
                    .delay(baseDelay + Double(index) * staggerDelay),
                value: isVisible
            )
    }
}

extension View {
    /// Apply staggered fade-in animation
    func staggeredFadeIn(index: Int, isVisible: Bool, baseDelay: Double = 0.1, staggerDelay: Double = 0.05) -> some View {
        self.modifier(StaggeredFadeIn(index: index, isVisible: isVisible, baseDelay: baseDelay, staggerDelay: staggerDelay))
    }
}

/// Floating animation for subtle motion
struct FloatingAnimation: ViewModifier {
    @State private var isFloating = false
    let amplitude: CGFloat
    let duration: Double
    
    func body(content: Content) -> some View {
        content
            .offset(y: isFloating ? amplitude : -amplitude)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: duration)
                        .repeatForever(autoreverses: true)
                ) {
                    isFloating = true
                }
            }
    }
}

extension View {
    /// Apply gentle floating animation
    func floating(amplitude: CGFloat = 5, duration: Double = 2) -> some View {
        self.modifier(FloatingAnimation(amplitude: amplitude, duration: duration))
    }
}

/// Pulsing glow effect for emphasis
struct PulsingGlow: ViewModifier {
    @State private var isPulsing = false
    let color: Color
    let radius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(isPulsing ? 0.6 : 0.2), radius: isPulsing ? radius : radius / 2)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.5)
                        .repeatForever(autoreverses: true)
                ) {
                    isPulsing = true
                }
            }
    }
}

extension View {
    /// Apply pulsing glow effect
    func pulsingGlow(color: Color = .white, radius: CGFloat = 15) -> some View {
        self.modifier(PulsingGlow(color: color, radius: radius))
    }
}

/// Shimmer effect for loading states (onboarding-specific)
struct OnboardingShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0
    let isActive: Bool
    
    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [
                                .clear,
                                .white.opacity(0.3),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 2)
                        .offset(x: -geo.size.width + (geo.size.width * 2 * phase))
                    }
                    .mask(content)
                }
            }
            .onAppear {
                if isActive {
                    withAnimation(
                        .linear(duration: 1.5)
                            .repeatForever(autoreverses: false)
                    ) {
                        phase = 1
                    }
                }
            }
    }
}

extension View {
    /// Apply shimmer loading effect for onboarding
    func onboardingShimmer(isActive: Bool = true) -> some View {
        self.modifier(OnboardingShimmerEffect(isActive: isActive))
    }
}

/// Confetti celebration particle (onboarding-specific)
struct OnboardingConfettiParticle: Identifiable {
    let id = UUID()
    var position: CGPoint
    var color: Color
    var rotation: Double
    var scale: CGFloat
    var velocity: CGPoint
}

/// Confetti celebration view (onboarding-specific)
struct OnboardingConfettiView: View {
    @State private var particles: [OnboardingConfettiParticle] = []
    @State private var animationProgress: CGFloat = 0
    let colors: [Color] = [
        Color(hex: "#FF6B6B"),
        Color(hex: "#4ECDC4"),
        Color(hex: "#45B7D1"),
        Color(hex: "#96E6A1"),
        Color(hex: "#DDA0DD"),
        Color(hex: "#F7DC6F"),
        Color(hex: "#BB8FCE"),
        Color(hex: "#85C1E9")
    ]
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { particle in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(particle.color)
                        .frame(width: 8 * particle.scale, height: 12 * particle.scale)
                        .rotationEffect(.degrees(particle.rotation + animationProgress * 720))
                        .position(
                            x: particle.position.x + particle.velocity.x * animationProgress * 100,
                            y: particle.position.y + particle.velocity.y * animationProgress * 300 + animationProgress * 200
                        )
                        .opacity(1 - animationProgress)
                }
            }
            .onAppear {
                generateParticles(in: geo.size)
                withAnimation(.easeOut(duration: 2.0)) {
                    animationProgress = 1
                }
            }
        }
        .allowsHitTesting(false)
    }
    
    private func generateParticles(in size: CGSize) {
        particles = (0..<50).map { _ in
            OnboardingConfettiParticle(
                position: CGPoint(x: size.width / 2, y: size.height * 0.3),
                color: colors.randomElement() ?? .white,
                rotation: Double.random(in: 0...360),
                scale: CGFloat.random(in: 0.5...1.5),
                velocity: CGPoint(
                    x: CGFloat.random(in: -3...3),
                    y: CGFloat.random(in: -2...1)
                )
            )
        }
    }
}

/// Success checkmark animation (onboarding-specific)
struct OnboardingAnimatedCheckmark: View {
    @State private var trimEnd: CGFloat = 0
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0
    let size: CGFloat
    let color: Color
    
    init(size: CGFloat = 60, color: Color = Color(hex: "#32D74B")) {
        self.size = size
        self.color = color
    }
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: size, height: size)
            
            // Checkmark
            Path { path in
                let width = size * 0.4
                let height = size * 0.3
                let xOffset = size * 0.3
                let yOffset = size * 0.4
                
                path.move(to: CGPoint(x: xOffset, y: yOffset))
                path.addLine(to: CGPoint(x: xOffset + width * 0.35, y: yOffset + height * 0.7))
                path.addLine(to: CGPoint(x: xOffset + width, y: yOffset - height * 0.3))
            }
            .trim(from: 0, to: trimEnd)
            .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                scale = 1
                opacity = 1
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.2)) {
                trimEnd = 1
            }
        }
    }
}

/// Haptic feedback helper for macOS
struct OnboardingHaptics {
    #if canImport(AppKit)
    static func light() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
    
    static func medium() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
    
    static func success() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
    
    static func warning() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
    
    static func error() {
        // Double haptic for error
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }
    #endif
}

/// Bounce animation modifier
struct BounceAnimation: ViewModifier {
    @State private var isBouncing = false
    let trigger: Bool
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isBouncing ? 1.05 : 1.0)
            .onChange(of: trigger) { newValue in
                if newValue {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                        isBouncing = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isBouncing = false
                        }
                    }
                }
            }
    }
}

extension View {
    /// Apply bounce animation on trigger
    func bounceOnTrigger(_ trigger: Bool) -> some View {
        self.modifier(BounceAnimation(trigger: trigger))
    }
}

/// Typing text animation
struct TypingText: View {
    let fullText: String
    let typingSpeed: Double
    @State private var displayedText: String = ""
    @State private var currentIndex: Int = 0
    
    init(_ text: String, speed: Double = 0.05) {
        self.fullText = text
        self.typingSpeed = speed
    }
    
    var body: some View {
        Text(displayedText)
            .onAppear {
                startTyping()
            }
    }
    
    private func startTyping() {
        displayedText = ""
        currentIndex = 0
        typeNextCharacter()
    }
    
    private func typeNextCharacter() {
        guard currentIndex < fullText.count else { return }
        
        let index = fullText.index(fullText.startIndex, offsetBy: currentIndex)
        displayedText.append(fullText[index])
        currentIndex += 1
        
        DispatchQueue.main.asyncAfter(deadline: .now() + typingSpeed) {
            typeNextCharacter()
        }
    }
}

// Note: Color(hex:) extension is defined in HawalaTheme.swift
