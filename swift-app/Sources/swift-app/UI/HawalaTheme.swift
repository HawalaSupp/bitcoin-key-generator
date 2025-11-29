import SwiftUI

// MARK: - Hawala Design System
// Inspired by Ledger Live - Dark, minimal, professional

struct HawalaTheme {
    // MARK: - Colors
    struct Colors {
        // Background hierarchy (darkest to lightest)
        static let background = Color(hex: "0D0D0D")           // Pure black-ish
        static let backgroundSecondary = Color(hex: "1A1A1A")  // Sidebar, cards
        static let backgroundTertiary = Color(hex: "252525")   // Elevated cards, inputs
        static let backgroundHover = Color(hex: "2D2D2D")      // Hover states
        
        // Text hierarchy
        static let textPrimary = Color.white
        static let textSecondary = Color(hex: "A0A0A0")        // Muted text
        static let textTertiary = Color(hex: "666666")         // Very muted
        
        // Accent colors
        static let accent = Color(hex: "835EF8")               // Purple accent (Ledger-like)
        static let accentHover = Color(hex: "9B7BFA")
        static let accentSubtle = Color(hex: "835EF8").opacity(0.15)
        
        // Status colors
        static let success = Color(hex: "28A745")
        static let warning = Color(hex: "FFC107")
        static let error = Color(hex: "DC3545")
        static let info = Color(hex: "17A2B8")
        
        // Chain colors
        static let bitcoin = Color(hex: "F7931A")
        static let ethereum = Color(hex: "627EEA")
        static let litecoin = Color(hex: "345D9D")
        static let solana = Color(hex: "9945FF")
        static let xrp = Color(hex: "23292F")
        static let bnb = Color(hex: "F3BA2F")
        static let monero = Color(hex: "FF6600")
        
        // Borders and dividers
        static let border = Color.white.opacity(0.08)
        static let borderHover = Color.white.opacity(0.15)
        static let divider = Color.white.opacity(0.06)
    }
    
    // MARK: - Typography
    struct Typography {
        // Display - Large hero numbers
        static func display(_ size: CGFloat = 48) -> Font {
            .system(size: size, weight: .semibold, design: .rounded)
        }
        
        // Headings
        static let h1 = Font.system(size: 28, weight: .semibold, design: .default)
        static let h2 = Font.system(size: 22, weight: .semibold, design: .default)
        static let h3 = Font.system(size: 18, weight: .medium, design: .default)
        static let h4 = Font.system(size: 16, weight: .medium, design: .default)
        
        // Body text
        static let bodyLarge = Font.system(size: 16, weight: .regular, design: .default)
        static let body = Font.system(size: 14, weight: .regular, design: .default)
        static let bodySmall = Font.system(size: 13, weight: .regular, design: .default)
        
        // Mono for addresses/keys
        static let mono = Font.system(size: 13, weight: .regular, design: .monospaced)
        static let monoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
        
        // Captions and labels
        static let caption = Font.system(size: 12, weight: .regular, design: .default)
        static let captionBold = Font.system(size: 12, weight: .semibold, design: .default)
        static let label = Font.system(size: 11, weight: .medium, design: .default)
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
        default:
            return accent
        }
    }
}

// MARK: - Glassmorphism Modifier
extension View {
    func glassCard(
        cornerRadius: CGFloat = HawalaTheme.Radius.lg,
        opacity: Double = 0.08,
        blurRadius: CGFloat = 20
    ) -> some View {
        self
            .background(
                ZStack {
                    // Base blur layer
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(0.5)
                    
                    // Gradient overlay for depth
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(opacity * 1.5),
                                    Color.white.opacity(opacity * 0.5)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Inner glow
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
    
    func frostedGlass(
        cornerRadius: CGFloat = HawalaTheme.Radius.lg,
        intensity: Double = 0.15
    ) -> some View {
        self
            .background(
                ZStack {
                    // Frosted material
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    
                    // Subtle color tint
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(HawalaTheme.Colors.backgroundSecondary.opacity(intensity))
                    
                    // Border highlight
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(0.1),
                            lineWidth: 0.5
                        )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Particle Background View
struct ParticleBackgroundView: View {
    let particleCount: Int
    let colors: [Color]
    
    @State private var particles: [Particle] = []
    
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
    
    struct Particle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var size: CGFloat
        var opacity: Double
        var color: Color
        var speed: CGFloat
        var angle: CGFloat
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        HawalaTheme.Colors.background,
                        HawalaTheme.Colors.backgroundSecondary.opacity(0.5),
                        HawalaTheme.Colors.background
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Floating particles
                ForEach(particles) { particle in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    particle.color,
                                    particle.color.opacity(0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: particle.size / 2
                            )
                        )
                        .frame(width: particle.size, height: particle.size)
                        .position(x: particle.x, y: particle.y)
                        .blur(radius: particle.size * 0.3)
                }
                
                // Gradient orbs (larger, slower moving)
                GradientOrb(
                    color: HawalaTheme.Colors.accent,
                    size: 300,
                    position: CGPoint(x: geometry.size.width * 0.2, y: geometry.size.height * 0.3)
                )
                
                GradientOrb(
                    color: HawalaTheme.Colors.solana,
                    size: 250,
                    position: CGPoint(x: geometry.size.width * 0.8, y: geometry.size.height * 0.7)
                )
            }
            .onAppear {
                initializeParticles(in: geometry.size)
                startAnimation(in: geometry.size)
            }
        }
        .ignoresSafeArea()
    }
    
    private func initializeParticles(in size: CGSize) {
        particles = (0..<particleCount).map { _ in
            Particle(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: 0...size.height),
                size: CGFloat.random(in: 20...80),
                opacity: Double.random(in: 0.1...0.4),
                color: colors.randomElement() ?? .white,
                speed: CGFloat.random(in: 0.2...0.8),
                angle: CGFloat.random(in: 0...(2 * .pi))
            )
        }
    }
    
    private func startAnimation(in size: CGSize) {
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [self] _ in
            Task { @MainActor in
                withAnimation(.linear(duration: 0.05)) {
                    for i in particles.indices {
                        // Move particle
                        particles[i].x += cos(particles[i].angle) * particles[i].speed
                        particles[i].y += sin(particles[i].angle) * particles[i].speed
                        
                        // Wrap around edges
                        if particles[i].x < -50 { particles[i].x = size.width + 50 }
                        if particles[i].x > size.width + 50 { particles[i].x = -50 }
                        if particles[i].y < -50 { particles[i].y = size.height + 50 }
                        if particles[i].y > size.height + 50 { particles[i].y = -50 }
                        
                        // Slight angle drift
                        particles[i].angle += CGFloat.random(in: -0.02...0.02)
                    }
                }
            }
        }
    }
}

// MARK: - Gradient Orb
struct GradientOrb: View {
    let color: Color
    let size: CGFloat
    let position: CGPoint
    
    @State private var offset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        color.opacity(0.4),
                        color.opacity(0.1),
                        color.opacity(0)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
            .blur(radius: size * 0.2)
            .position(x: position.x + offset.width, y: position.y + offset.height)
            .scaleEffect(scale)
            .onAppear {
                // Slow, organic movement
                withAnimation(
                    Animation.easeInOut(duration: Double.random(in: 8...15))
                        .repeatForever(autoreverses: true)
                ) {
                    offset = CGSize(
                        width: CGFloat.random(in: -50...50),
                        height: CGFloat.random(in: -50...50)
                    )
                }
                
                withAnimation(
                    Animation.easeInOut(duration: Double.random(in: 5...10))
                        .repeatForever(autoreverses: true)
                ) {
                    scale = CGFloat.random(in: 0.8...1.2)
                }
            }
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
