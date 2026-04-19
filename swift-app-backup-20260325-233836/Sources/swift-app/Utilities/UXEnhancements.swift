import SwiftUI
import AppKit
import AVFoundation
import Combine

// Note: OptimizedAnimations is defined in PerformanceOptimizations.swift

// MARK: - 1. Haptic Feedback System

/// Centralized haptic feedback manager for macOS
@MainActor
final class HapticManager {
    static let shared = HapticManager()
    
    private init() {}
    
    /// Light tap for buttons and toggles
    func lightTap() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange,
            performanceTime: .now
        )
    }
    
    /// Medium impact for confirmations
    func mediumImpact() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .now
        )
    }
    
    /// Success feedback
    func success() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .now
        )
    }
    
    /// Error/warning feedback
    func error() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange,
            performanceTime: .now
        )
        // Double tap for error emphasis
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSHapticFeedbackManager.defaultPerformer.perform(
                .levelChange,
                performanceTime: .now
            )
        }
    }
    
    /// Selection change feedback
    func selection() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange,
            performanceTime: .now
        )
    }
    
    /// Drag/drop feedback
    func drag() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .now
        )
    }
}

// MARK: - Haptic View Modifiers

struct HapticButtonStyle: ButtonStyle {
    let hapticType: HapticType
    
    enum HapticType {
        case light, medium, success, error
    }
    
    func makeBody(configuration: Configuration) -> some View {
        HapticButtonContent(
            configuration: configuration,
            hapticType: hapticType
        )
    }
}

private struct HapticButtonContent: View {
    let configuration: ButtonStyleConfiguration
    let hapticType: HapticButtonStyle.HapticType
    
    @State private var wasPressed = false
    
    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onAppear {
                wasPressed = configuration.isPressed
            }
            .onChange(of: configuration.isPressed) { newValue in
                if newValue && !wasPressed {
                    triggerHaptic()
                }
                wasPressed = newValue
            }
    }
    
    private func triggerHaptic() {
        switch hapticType {
        case .light: HapticManager.shared.lightTap()
        case .medium: HapticManager.shared.mediumImpact()
        case .success: HapticManager.shared.success()
        case .error: HapticManager.shared.error()
        }
    }
}

extension View {
    /// Add haptic feedback on tap
    func hapticOnTap(_ type: HapticButtonStyle.HapticType = .light) -> some View {
        self.onTapGesture {
            switch type {
            case .light: HapticManager.shared.lightTap()
            case .medium: HapticManager.shared.mediumImpact()
            case .success: HapticManager.shared.success()
            case .error: HapticManager.shared.error()
            }
        }
    }
    
    /// Button style with haptic feedback
    func hapticButton(_ type: HapticButtonStyle.HapticType = .light) -> some View {
        self.buttonStyle(HapticButtonStyle(hapticType: type))
    }
}

// MARK: - 2. Sound Effects System

/// Sound effect manager for transaction feedback
@MainActor
final class SoundManager: ObservableObject {
    static let shared = SoundManager()
    
    @Published var soundEnabled: Bool {
        didSet {
            UserDefaults.standard.set(soundEnabled, forKey: "hawala_sound_enabled")
        }
    }
    
    @Published var volume: Float = 0.5 {
        didSet {
            UserDefaults.standard.set(volume, forKey: "hawala_sound_volume")
        }
    }
    
    private var audioPlayers: [String: AVAudioPlayer] = [:]
    
    private init() {
        soundEnabled = UserDefaults.standard.bool(forKey: "hawala_sound_enabled")
        volume = UserDefaults.standard.float(forKey: "hawala_sound_volume")
        if volume == 0 { volume = 0.5 } // Default
        
        preloadSounds()
    }
    
    private func preloadSounds() {
        // These would be actual sound files in a real app
        // For now, we'll use system sounds
    }
    
    /// Play send transaction sound
    func playSend() {
        guard soundEnabled else { return }
        NSSound(named: "Blow")?.play()
    }
    
    /// Play receive transaction sound
    func playReceive() {
        guard soundEnabled else { return }
        NSSound(named: "Glass")?.play()
    }
    
    /// Play success sound
    func playSuccess() {
        guard soundEnabled else { return }
        NSSound(named: "Hero")?.play()
    }
    
    /// Play error sound
    func playError() {
        guard soundEnabled else { return }
        NSSound(named: "Basso")?.play()
    }
    
    /// Play notification sound
    func playNotification() {
        guard soundEnabled else { return }
        NSSound(named: "Pop")?.play()
    }
    
    /// Play button click
    func playClick() {
        guard soundEnabled else { return }
        NSSound(named: "Tink")?.play()
    }
}

// MARK: - 3. Animated Success/Failure States

/// Animated checkmark for success states
struct AnimatedCheckmark: View {
    @State private var drawProgress: CGFloat = 0
    @State private var circleProgress: CGFloat = 0
    @State private var scale: CGFloat = 0.8
    
    let size: CGFloat
    let color: Color
    let onComplete: (() -> Void)?
    
    init(size: CGFloat = 80, color: Color = .green, onComplete: (() -> Void)? = nil) {
        self.size = size
        self.color = color
        self.onComplete = onComplete
    }
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 4)
                .frame(width: size, height: size)
            
            // Animated circle
            Circle()
                .trim(from: 0, to: circleProgress)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
            
            // Checkmark
            CheckmarkShape()
                .trim(from: 0, to: drawProgress)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.4, height: size * 0.4)
        }
        .scaleEffect(scale)
        .onAppear {
            // Circle animation
            withAnimation(.easeOut(duration: 0.4)) {
                circleProgress = 1.0
                scale = 1.0
            }
            
            // Checkmark animation (delayed)
            withAnimation(.easeOut(duration: 0.3).delay(0.3)) {
                drawProgress = 1.0
            }
            
            // Haptic feedback
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                HapticManager.shared.success()
                SoundManager.shared.playSuccess()
            }
            
            // Completion callback
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                onComplete?()
            }
        }
    }
}

struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        path.move(to: CGPoint(x: w * 0.1, y: h * 0.5))
        path.addLine(to: CGPoint(x: w * 0.4, y: h * 0.8))
        path.addLine(to: CGPoint(x: w * 0.9, y: h * 0.2))
        
        return path
    }
}

/// Animated X mark for failure states
struct AnimatedXMark: View {
    @State private var drawProgress: CGFloat = 0
    @State private var circleProgress: CGFloat = 0
    @State private var scale: CGFloat = 0.8
    @State private var shake: CGFloat = 0
    
    let size: CGFloat
    let color: Color
    let onComplete: (() -> Void)?
    
    init(size: CGFloat = 80, color: Color = .red, onComplete: (() -> Void)? = nil) {
        self.size = size
        self.color = color
        self.onComplete = onComplete
    }
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 4)
                .frame(width: size, height: size)
            
            // Animated circle
            Circle()
                .trim(from: 0, to: circleProgress)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
            
            // X mark
            XMarkShape()
                .trim(from: 0, to: drawProgress)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.35, height: size * 0.35)
        }
        .scaleEffect(scale)
        .offset(x: shake)
        .onAppear {
            // Circle animation
            withAnimation(.easeOut(duration: 0.4)) {
                circleProgress = 1.0
                scale = 1.0
            }
            
            // X mark animation (delayed)
            withAnimation(.easeOut(duration: 0.3).delay(0.3)) {
                drawProgress = 1.0
            }
            
            // Shake animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.default.repeatCount(3, autoreverses: true).speed(6)) {
                    shake = 8
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    shake = 0
                }
            }
            
            // Haptic feedback
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                HapticManager.shared.error()
                SoundManager.shared.playError()
            }
            
            // Completion callback
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                onComplete?()
            }
        }
    }
}

struct XMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // First line of X
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: w, y: h))
        
        // Second line of X
        path.move(to: CGPoint(x: w, y: 0))
        path.addLine(to: CGPoint(x: 0, y: h))
        
        return path
    }
}

/// Transaction result overlay
struct TransactionResultOverlay: View {
    let isSuccess: Bool
    let message: String
    let onDismiss: () -> Void
    
    @State private var opacity: Double = 0
    
    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                if isSuccess {
                    AnimatedCheckmark(size: 100, color: .green)
                } else {
                    AnimatedXMark(size: 100, color: .red)
                }
                
                Text(message)
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Button("Done") {
                    withAnimation {
                        opacity = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onDismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(isSuccess ? .green : .red)
                .padding(.top, 8)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
            )
        }
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                opacity = 1
            }
        }
    }
}

// Note: Skeleton loading components (ShimmerEffect, SkeletonRect, SkeletonCircle, 
// SkeletonWalletRow, SkeletonTransactionRow, SkeletonLoadingList, LoadingStateView)
// are defined in HawalaComponents.swift to avoid duplication
