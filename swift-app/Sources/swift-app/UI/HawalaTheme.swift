import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Hawala Design System
// Supports Dark, Light, and System theme modes

struct HawalaTheme {
    // MARK: - Dynamic Colors (Theme-Aware)
    // ROADMAP-14 E1: Removed dead Color("hawala.*") asset catalog lookups — colors are code-defined
    struct Colors {
        // Background hierarchy - adapts to color scheme
        static var background: Color {
            AdaptiveColor(dark: Color(hex: "0D0D0D"), light: Color(hex: "F5F5F7")).color
        }
        static var backgroundSecondary: Color {
            AdaptiveColor(dark: Color(hex: "1A1A1A"), light: Color(hex: "FFFFFF")).color
        }
        static var backgroundTertiary: Color {
            AdaptiveColor(dark: Color(hex: "252525"), light: Color(hex: "E8E8ED")).color
        }
        static var backgroundHover: Color {
            AdaptiveColor(dark: Color(hex: "2D2D2D"), light: Color(hex: "DEDEE3")).color
        }
        
        // Text hierarchy
        static var textPrimary: Color {
            AdaptiveColor(dark: Color.white, light: Color(hex: "1D1D1F")).color
        }
        static var textSecondary: Color {
            AdaptiveColor(dark: Color(hex: "A0A0A0"), light: Color(hex: "6E6E73")).color
        }
        // WCAG AA compliant: 4.5:1 contrast on both dark (#252525) and light (#F5F5F7) backgrounds
        static var textTertiary: Color {
            AdaptiveColor(dark: Color(hex: "8E8E8E"), light: Color(hex: "6B6B70")).color
        }
        
        // Accent colors - same across themes (used for large text/buttons, 3:1 acceptable)
        static let accent = Color(hex: "14B8A6")               // Teal accent
        static let accentHover = Color(hex: "2DD4BF")
        static let accentSubtle = Color(hex: "14B8A6").opacity(0.15)
        
        // Status colors - adaptive for WCAG AA compliance (4.5:1 contrast)
        static var success: Color {
            AdaptiveColor(dark: Color(hex: "32D74B"), light: Color(hex: "1E7E34")).color
        }
        static var warning: Color {
            AdaptiveColor(dark: Color(hex: "FFD60A"), light: Color(hex: "856404")).color
        }
        static var error: Color {
            AdaptiveColor(dark: Color(hex: "FF453A"), light: Color(hex: "C82333")).color
        }
        static var info: Color {
            AdaptiveColor(dark: Color(hex: "64D2FF"), light: Color(hex: "117A8B")).color
        }
        
        // Chain colors - consistent across themes
        static let bitcoin = Color(hex: "F7931A")
        static let ethereum = Color(hex: "627EEA")
        static let litecoin = Color(hex: "345D9D")
        static let solana = Color(hex: "9945FF")
        static let xrp = Color(hex: "23292F")
        static let bnb = Color(hex: "F3BA2F")
        static let monero = Color(hex: "FF6600")
        
        // Borders and dividers - adapts to color scheme
        static var border: Color {
            AdaptiveColor(dark: Color.white.opacity(0.08), light: Color.black.opacity(0.08)).color
        }
        static var borderHover: Color {
            AdaptiveColor(dark: Color.white.opacity(0.15), light: Color.black.opacity(0.15)).color
        }
        static var divider: Color {
            AdaptiveColor(dark: Color.white.opacity(0.06), light: Color.black.opacity(0.06)).color
        }
        
        // ROADMAP-14 E11: High Contrast alternatives — used when macOS Increase Contrast is on
        static var textTertiaryHighContrast: Color {
            AdaptiveColor(dark: Color(hex: "B0B0B0"), light: Color(hex: "505055")).color
        }
        static var borderHighContrast: Color {
            AdaptiveColor(dark: Color.white.opacity(0.20), light: Color.black.opacity(0.20)).color
        }
        static var dividerHighContrast: Color {
            AdaptiveColor(dark: Color.white.opacity(0.15), light: Color.black.opacity(0.15)).color
        }
    }
    
    // MARK: - Typography (ROADMAP-14 E5: Dynamic Type)
    // Uses SwiftUI semantic text styles that scale with user's Dynamic Type setting.
    // Legacy fixed-size API preserved via static funcs for callers that need exact control.
    struct Typography {
        // Display — Large hero numbers (scales from .largeTitle)
        static func display(_ size: CGFloat = 48) -> Font {
            .system(size: size, weight: .semibold, design: .rounded)
        }
        
        // Headings — map to semantic SwiftUI text styles for Dynamic Type
        static let h1: Font = .title.weight(.semibold)              // ~28pt, scales
        static let h2: Font = .title2.weight(.semibold)             // ~22pt, scales
        static let h3: Font = .title3.weight(.medium)               // ~20pt, scales
        static let h4: Font = .headline                              // ~17pt, scales
        
        // Body text — scales with Dynamic Type
        static let bodyLarge: Font = .body                           // ~17pt, scales
        static let body: Font = .callout                             // ~16pt, scales
        static let bodySmall: Font = .subheadline                    // ~15pt, scales
        
        // Mono for addresses/keys — scales with Dynamic Type
        static var mono: Font { .system(.callout, design: .monospaced) }
        static var monoSmall: Font { .system(.caption, design: .monospaced) }
        
        // Captions and labels — scales with Dynamic Type
        static let caption: Font = .caption                          // ~12pt, scales
        static let captionBold: Font = .caption.weight(.semibold)
        static let label: Font = .caption2.weight(.medium)           // ~11pt, scales
    }
    
    // MARK: - Spacing
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }
    
    // MARK: - Radius
    struct Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let xl: CGFloat = 20
        static let full: CGFloat = 9999
    }
    
    // MARK: - Shadows
    struct Shadows {
        static let card = Color.black.opacity(0.3)
        static let elevated = Color.black.opacity(0.5)
    }
    
    // MARK: - Animation
    struct Animation {
        static let fast = SwiftUI.Animation.easeOut(duration: 0.15)
        static let normal = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.4)
        static let spring = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.7)
    }
}

// MARK: - ROADMAP-14 E11: High Contrast View Modifier
/// Reads the system's "Increase Contrast" setting and swaps low-contrast
/// theme tokens (textTertiary, border, divider) for bolder alternatives.
struct HighContrastAwareModifier: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    
    func body(content: Content) -> some View {
        content
            .environment(\.hawalaTextTertiary, contrast == .increased
                         ? HawalaTheme.Colors.textTertiaryHighContrast
                         : HawalaTheme.Colors.textTertiary)
            .environment(\.hawalaBorder, contrast == .increased
                         ? HawalaTheme.Colors.borderHighContrast
                         : HawalaTheme.Colors.border)
            .environment(\.hawalaDivider, contrast == .increased
                         ? HawalaTheme.Colors.dividerHighContrast
                         : HawalaTheme.Colors.divider)
    }
}

// Environment keys for high-contrast-aware colors
private struct HawalaTextTertiaryKey: EnvironmentKey {
    static let defaultValue: Color = HawalaTheme.Colors.textTertiary
}
private struct HawalaBorderKey: EnvironmentKey {
    static let defaultValue: Color = HawalaTheme.Colors.border
}
private struct HawalaDividerKey: EnvironmentKey {
    static let defaultValue: Color = HawalaTheme.Colors.divider
}

extension EnvironmentValues {
    var hawalaTextTertiary: Color {
        get { self[HawalaTextTertiaryKey.self] }
        set { self[HawalaTextTertiaryKey.self] = newValue }
    }
    var hawalaBorder: Color {
        get { self[HawalaBorderKey.self] }
        set { self[HawalaBorderKey.self] = newValue }
    }
    var hawalaDivider: Color {
        get { self[HawalaDividerKey.self] }
        set { self[HawalaDividerKey.self] = newValue }
    }
}

extension View {
    /// Apply high-contrast-aware theming. Place on root view.
    func highContrastAware() -> some View {
        modifier(HighContrastAwareModifier())
    }
}

// MARK: - ROADMAP-14 E5: Scaled Metric Helpers
/// Pre-built @ScaledMetric wrappers for common fixed sizes that need to scale
struct ScaledSpacing {
    @ScaledMetric(relativeTo: .body) var iconSize: CGFloat = 40
    @ScaledMetric(relativeTo: .body) var cardMinHeight: CGFloat = 150
    @ScaledMetric(relativeTo: .caption) var smallIcon: CGFloat = 24
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    /// Provides adaptive colors that respond to dark/light mode
    /// Falls back to provided defaults if named color doesn't exist
    func orDefault(dark: Color, light: Color) -> Color {
        // Use adaptive color that SwiftUI will resolve based on current appearance
        AdaptiveColor(dark: dark, light: light).color
    }
}

// MARK: - Adaptive Color Helper
struct AdaptiveColor {
    let dark: Color
    let light: Color
    
    var color: Color {
        // This creates a dynamic color that adapts to the current color scheme
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor(dark) : NSColor(light)
        })
    }
}

// MARK: - View Extensions
extension View {
    func hawalaCard(padding: CGFloat = HawalaTheme.Spacing.lg) -> some View {
        self
            .padding(padding)
            .background(HawalaTheme.Colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous)
                    .strokeBorder(HawalaTheme.Colors.border, lineWidth: 1)
            )
    }
    
    func hawalaCardElevated(padding: CGFloat = HawalaTheme.Spacing.lg) -> some View {
        self
            .padding(padding)
            .background(HawalaTheme.Colors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous)
                    .strokeBorder(HawalaTheme.Colors.border, lineWidth: 1)
            )
    }
}

// MARK: - Chain Color Helper
extension HawalaTheme.Colors {
    static func forChain(_ chainId: String) -> Color {
        switch chainId.lowercased() {
        case "bitcoin", "bitcoin-testnet":
            return bitcoin
        case "ethereum", "ethereum-sepolia":
            return ethereum
        case "litecoin":
            return litecoin
        case "solana":
            return solana
        case "xrp":
            return Color(hex: "00AAE4") // XRP blue
        case "bnb":
            return bnb
        case "monero":
            return monero
        // New chains from wallet-core integration
        case "ton":
            return Color(hex: "0098E1") // TON blue
        case "aptos":
            return Color(hex: "00D1B0") // Aptos teal
        case "sui":
            return Color(hex: "4A90E2") // Sui blue
        case "polkadot":
            return Color(hex: "E6007A") // Polkadot pink
        case "kusama":
            return Color(hex: "000000") // Kusama black/dark
        default:
            return accent
        }
    }
}

// MARK: - Glassmorphism Modifier (Theme-Aware)
extension View {
    func glassCard(
        cornerRadius: CGFloat = HawalaTheme.Radius.lg,
        opacity: Double = 0.08,
        blurRadius: CGFloat = 20
    ) -> some View {
        self.modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }
    
    func frostedGlass(
        cornerRadius: CGFloat = HawalaTheme.Radius.lg,
        intensity: Double = 0.15
    ) -> some View {
        self.modifier(FrostedGlassModifier(cornerRadius: cornerRadius))
    }
}

// Theme-aware glass card modifier
struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(colorScheme == .dark 
                              ? Color(white: 0.15, opacity: 0.85)
                              : Color(white: 0.95, opacity: 0.9))
                    
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(colorScheme == .dark 
                                      ? Color.white.opacity(0.1) 
                                      : Color.black.opacity(0.08), lineWidth: 1)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// Theme-aware frosted glass modifier
struct FrostedGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(colorScheme == .dark 
                              ? Color(white: 0.12, opacity: 0.9)
                              : Color(white: 0.98, opacity: 0.95))
                    
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(colorScheme == .dark 
                                      ? Color.white.opacity(0.08) 
                                      : Color.black.opacity(0.06), lineWidth: 0.5)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Optimized Static Background (replaces ParticleBackgroundView)
struct ParticleBackgroundView: View {
    let particleCount: Int
    let colors: [Color]
    
    init(
        particleCount: Int = 30,
        colors: [Color] = [
            HawalaTheme.Colors.accent.opacity(0.3),
            HawalaTheme.Colors.solana.opacity(0.2),
            HawalaTheme.Colors.ethereum.opacity(0.2),
            Color.white.opacity(0.1)
        ]
    ) {
        self.particleCount = particleCount
        self.colors = colors
    }
    
    var body: some View {
        // Simple static gradient - no animations, no timers
        LinearGradient(
            colors: [
                HawalaTheme.Colors.background,
                HawalaTheme.Colors.backgroundSecondary.opacity(0.3),
                HawalaTheme.Colors.background
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

// MARK: - Static Gradient Orb (no animations)
struct GradientOrb: View {
    let color: Color
    let size: CGFloat
    let position: CGPoint
    
    var body: some View {
        // Static orb - no movement, no animations
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        color.opacity(0.15),
                        color.opacity(0.05),
                        color.opacity(0)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
            .position(position)
    }
}

// MARK: - Splash Screen View
struct HawalaSplashView: View {
    @Binding var isShowingSplash: Bool
    
    @State private var logoScale: CGFloat = 0.3
    @State private var logoOpacity: Double = 0
    @State private var ringScale: CGFloat = 0.5
    @State private var ringOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var textOffset: CGFloat = 20
    @State private var particlesVisible = false
    
    var body: some View {
        ZStack {
            // Animated background
            if particlesVisible {
                ParticleBackgroundView(particleCount: 20)
                    .transition(.opacity)
            } else {
                HawalaTheme.Colors.background
            }
            
            VStack(spacing: HawalaTheme.Spacing.xl) {
                // Logo with animated ring
                ZStack {
                    // Outer pulsing ring
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    HawalaTheme.Colors.accent,
                                    HawalaTheme.Colors.accent.opacity(0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 120, height: 120)
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity)
                    
                    // Inner glow ring
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    HawalaTheme.Colors.accent.opacity(0.3),
                                    HawalaTheme.Colors.accent.opacity(0)
                                ],
                                center: .center,
                                startRadius: 30,
                                endRadius: 60
                            )
                        )
                        .frame(width: 100, height: 100)
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                    
                    // Logo icon
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    HawalaTheme.Colors.accent,
                                    HawalaTheme.Colors.accentHover
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                }
                
                // App name
                VStack(spacing: HawalaTheme.Spacing.xs) {
                    Text("HAWALA")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .tracking(8)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    
                    Text("Multi-Chain Wallet")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
                .opacity(textOpacity)
                .offset(y: textOffset)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            runSplashAnimation()
        }
    }
    
    private func runSplashAnimation() {
        // Phase 1: Logo appears with bounce
        withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
            logoScale = 1.0
            logoOpacity = 1.0
        }
        
        // Phase 2: Ring expands
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.5)) {
                ringScale = 1.3
                ringOpacity = 0.8
            }
        }
        
        // Phase 3: Text slides up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                textOpacity = 1.0
                textOffset = 0
            }
        }
        
        // Phase 4: Particles appear
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeIn(duration: 0.5)) {
                particlesVisible = true
            }
        }
        
        // Phase 5: Ring pulses then fades
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 0.8)) {
                ringScale = 2.0
                ringOpacity = 0
            }
        }
        
        // Phase 6: Transition to main app
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.4)) {
                isShowingSplash = false
            }
        }
    }
}

// MARK: - Glassmorphism Card Component
struct GlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat
    var padding: CGFloat
    
    init(
        cornerRadius: CGFloat = HawalaTheme.Radius.lg,
        padding: CGFloat = HawalaTheme.Spacing.lg,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(padding)
            .glassCard(cornerRadius: cornerRadius)
    }
}
