# Hawala Wallet — macOS Onboarding Implementation Roadmap

> **Platform:** macOS 13.0+  
> **Framework:** SwiftUI + AppKit integration  
> **Target:** Complete implementation of premium onboarding system

---

## Table of Contents

1. [Platform Adjustments (iOS → macOS)](#1-platform-adjustments-ios--macos)
2. [Information Architecture](#2-information-architecture)
3. [Component Library Implementation](#3-component-library-implementation)
4. [Quick Onboarding Flow (Power User)](#4-quick-onboarding-flow-power-user)
5. [Advanced Onboarding Flow (Guided)](#5-advanced-onboarding-flow-guided)
6. [Security & Trust Patterns](#6-security--trust-patterns)
7. [Animation & Interaction System](#7-animation--interaction-system)
8. [Edge Case Handling](#8-edge-case-handling)
9. [Activation Strategy](#9-activation-strategy)
10. [Implementation Phases](#10-implementation-phases)
11. [File Structure](#11-file-structure)
12. [Technical Specifications](#12-technical-specifications)

---

## 1. Platform Adjustments (iOS → macOS)

### Key Differences

| Concept | iOS | macOS (Our Implementation) |
|---------|-----|---------------------------|
| **Haptics** | UIFeedbackGenerator | Sound feedback + NSHapticFeedbackManager (trackpad) |
| **Biometrics** | Face ID / Touch ID | Touch ID / Apple Watch unlock via LAContext |
| **Navigation** | UINavigationController | NavigationStack with custom transitions |
| **Keyboard Input** | On-screen keyboard | Physical keyboard capture via NSEvent |
| **Screen Size** | Fixed sizes | Flexible window (min 900×600) |
| **Gestures** | Touch/swipe | Click/scroll/keyboard shortcuts |
| **Modals** | Full-screen sheets | Centered sheets with backdrop blur |
| **System Integration** | Keychain + iCloud | Keychain + iCloud + macOS Secure Enclave |

### macOS-Specific Enhancements

```swift
// Window configuration for onboarding
.frame(minWidth: 900, minHeight: 600)
.frame(maxWidth: 1200, maxHeight: 800)

// Keyboard navigation support
.focusable()
.onKeyPress(.return) { ... }
.onKeyPress(.escape) { ... }

// Trackpad haptics (where supported)
NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)

// Sound feedback fallback
NSSound(named: "Tink")?.play()
```

### Biometric Implementation (macOS)

```swift
import LocalAuthentication

class BiometricManager {
    let context = LAContext()
    
    var biometricType: LABiometryType {
        context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType // .touchID or .none on Mac
    }
    
    func authenticate() async throws -> Bool {
        try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Unlock Hawala Wallet"
        )
    }
}
```

---

## 2. Information Architecture

### Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     HAWALA ONBOARDING                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│                    ┌──────────────┐                             │
│                    │   WELCOME    │                             │
│                    │   Screen 1   │                             │
│                    └──────┬───────┘                             │
│                           │                                     │
│              ┌────────────┴────────────┐                        │
│              │                         │                        │
│              ▼                         ▼                        │
│       ┌──────────────┐          ┌──────────────┐                │
│       │ QUICK PATH   │          │ GUIDED PATH  │                │
│       │ Toggle ON    │          │ Toggle OFF   │                │
│       └──────┬───────┘          └──────┬───────┘                │
│              │                         │                        │
│              ▼                         ▼                        │
│       ┌──────────────┐          ┌──────────────┐                │
│       │ Create/Import│          │ Self-Custody │                │
│       │  Selection   │          │  Education   │                │
│       └──────┬───────┘          └──────┬───────┘                │
│              │                         │                        │
│              │                         ▼                        │
│              │                  ┌──────────────┐                │
│              │                  │   Persona    │                │
│              │                  │  Selection   │                │
│              │                  └──────┬───────┘                │
│              │                         │                        │
│              ▼                         ▼                        │
│       ┌──────────────┐          ┌──────────────┐                │
│       │    Auth      │          │ Create/Import│                │
│       │   Setup      │          │  Selection   │                │
│       └──────┬───────┘          └──────┬───────┘                │
│              │                         │                        │
│              │                         ▼                        │
│              │                  ┌──────────────┐                │
│              │                  │  Recovery    │                │
│              │                  │   Phrase     │                │
│              │                  └──────┬───────┘                │
│              │                         │                        │
│              │                         ▼                        │
│              │                  ┌──────────────┐                │
│              │                  │   Verify     │                │
│              │                  │   Backup     │                │
│              │                  └──────┬───────┘                │
│              │                         │                        │
│              │                         ▼                        │
│              │                  ┌──────────────┐                │
│              │                  │  Security    │                │
│              │                  │   Setup      │                │
│              │                  └──────┬───────┘                │
│              │                         │                        │
│              │                         ▼                        │
│              │                  ┌──────────────┐                │
│              │                  │  Guardian    │                │
│              │                  │   Setup      │                │
│              │                  └──────┬───────┘                │
│              │                         │                        │
│              │                         ▼                        │
│              │                  ┌──────────────┐                │
│              │                  │  Practice    │                │
│              │                  │   Mode       │                │
│              │                  └──────┬───────┘                │
│              │                         │                        │
│              ▼                         ▼                        │
│       ┌──────────────┐          ┌──────────────┐                │
│       │ Power Setup  │          │   Security   │                │
│       │  (Optional)  │          │    Score     │                │
│       └──────┬───────┘          └──────┬───────┘                │
│              │                         │                        │
│              └────────────┬────────────┘                        │
│                           │                                     │
│                           ▼                                     │
│                    ┌──────────────┐                             │
│                    │    READY     │                             │
│                    │   Screen     │                             │
│                    └──────────────┘                             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### State Machine

```swift
enum OnboardingState: String, CaseIterable {
    // Shared
    case welcome
    case pathSelection
    
    // Quick Path
    case quickCreateImport
    case quickAuth
    case quickPowerSettings
    case quickReady
    
    // Guided Path
    case guidedEducation
    case guidedPersona
    case guidedCreateImport
    case guidedRecoveryPhrase
    case guidedVerifyBackup
    case guidedSecuritySetup
    case guidedGuardians
    case guidedPractice
    case guidedSecurityScore
    case guidedReady
}

enum OnboardingPath {
    case quick
    case guided
}

enum WalletCreationMethod {
    case createNew
    case importSeedPhrase
    case importPrivateKey
    case importQRCode
    case connectHardware
    case restoreICloud
}

enum UserPersona: String, CaseIterable {
    case beginner = "Beginner"
    case collector = "Collector"
    case trader = "Trader"
    case builder = "Builder"
}
```

---

## 3. Component Library Implementation

### File: `Sources/swift-app/Components/OnboardingComponents.swift`

```swift
// MARK: - Glass Card Component
struct GlassCard<Content: View>: View {
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
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isSelected ? Color.white.opacity(0.4) : Color.white.opacity(0.1),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
            }
    }
}

// MARK: - Primary Button
struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var isLoading: Bool = false
    var isDisabled: Bool = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.black)
                }
                Text(title)
                    .font(.custom("ClashGrotesk-Semibold", size: 16))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isDisabled ? Color.white.opacity(0.3) : Color.white)
            )
            .foregroundColor(isDisabled ? .white.opacity(0.5) : .black)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
        .scaleEffect(isLoading ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isLoading)
    }
}

// MARK: - Secondary Button (Ghost)
struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom("ClashGrotesk-Medium", size: 14))
                .foregroundColor(.white.opacity(0.7))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            // Cursor change on macOS
        }
    }
}

// MARK: - Info Card
struct InfoCard: View {
    let icon: String
    let title: String
    let description: String
    var iconColor: Color = .white
    
    var body: some View {
        GlassCard(padding: 20) {
            HStack(alignment: .top, spacing: 16) {
                Text(icon)
                    .font(.system(size: 24))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.custom("ClashGrotesk-Semibold", size: 15))
                        .foregroundColor(.white)
                    
                    Text(description)
                        .font(.custom("ClashGrotesk-Regular", size: 13))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(3)
                }
                
                Spacer()
            }
        }
    }
}

// MARK: - Toggle Row
struct ToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    var icon: String? = nil
    
    var body: some View {
        HStack(spacing: 16) {
            if let icon = icon {
                Text(icon)
                    .font(.system(size: 20))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("ClashGrotesk-Medium", size: 14))
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.custom("ClashGrotesk-Regular", size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .tint(.green)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Chip Selector
struct ChipSelector: View {
    let options: [String]
    @Binding var selected: Set<String>
    var icons: [String: String] = [:]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(options, id: \.self) { option in
                    ChipView(
                        title: option,
                        icon: icons[option],
                        isSelected: selected.contains(option)
                    ) {
                        if selected.contains(option) {
                            selected.remove(option)
                        } else {
                            selected.insert(option)
                        }
                    }
                }
            }
        }
    }
}

struct ChipView: View {
    let title: String
    var icon: String?
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Text(icon)
                        .font(.system(size: 14))
                }
                Text(title)
                    .font(.custom("ClashGrotesk-Medium", size: 13))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(isSelected ? Color.white.opacity(0.2) : Color.white.opacity(0.05))
                    .overlay {
                        Capsule()
                            .stroke(isSelected ? Color.white.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1)
                    }
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Progress Indicator (Dots)
struct OnboardingProgressIndicator: View {
    let totalSteps: Int
    let currentStep: Int
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index == currentStep ? Color.white : Color.white.opacity(0.3))
                    .frame(width: index == currentStep ? 10 : 6, height: index == currentStep ? 10 : 6)
                    .animation(.easeInOut(duration: 0.2), value: currentStep)
            }
        }
    }
}

// MARK: - Security Score Ring
struct SecurityScoreRing: View {
    let score: Int
    let maxScore: Int = 100
    
    var progress: Double {
        Double(score) / Double(maxScore)
    }
    
    var scoreColor: Color {
        switch score {
        case 0..<40: return .red
        case 40..<70: return .orange
        case 70..<90: return .yellow
        default: return .green
        }
    }
    
    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 8)
            
            // Progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(scoreColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.8), value: score)
            
            // Score text
            VStack(spacing: 2) {
                Text("\(score)")
                    .font(.custom("ClashGrotesk-Bold", size: 32))
                    .foregroundColor(.white)
                
                Text("/ \(maxScore)")
                    .font(.custom("ClashGrotesk-Regular", size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(width: 120, height: 120)
    }
}

// MARK: - Word Grid (Seed Phrase Display)
struct WordGrid: View {
    let words: [String]
    @State private var revealedWords: Set<Int> = []
    var onCopy: (() -> Void)?
    
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
            
            Button(action: { onCopy?() }) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                    Text("Copy All")
                }
                .font(.custom("ClashGrotesk-Medium", size: 13))
                .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
    }
}

struct WordCell: View {
    let index: Int
    let word: String
    
    var body: some View {
        HStack(spacing: 8) {
            Text("\(index).")
                .font(.custom("ClashGrotesk-Regular", size: 12))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 20)
            
            Text(word)
                .font(.custom("ClashGrotesk-Medium", size: 14))
                .foregroundColor(.white)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
        }
    }
}

// MARK: - Word Selector (Verification)
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
                        selectedWord = option
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
    
    var backgroundColor: Color {
        if isCorrect { return .green.opacity(0.3) }
        if isWrong { return .red.opacity(0.3) }
        if isSelected { return .white.opacity(0.2) }
        return .white.opacity(0.05)
    }
    
    var borderColor: Color {
        if isCorrect { return .green }
        if isWrong { return .red }
        if isSelected { return .white.opacity(0.4) }
        return .white.opacity(0.1)
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
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(borderColor, lineWidth: 1)
                        }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Biometric Prompt View
struct BiometricPromptView: View {
    let biometricType: BiometricType
    let onEnable: () -> Void
    let onSkip: () -> Void
    
    enum BiometricType {
        case touchID
        case none
        
        var icon: String {
            switch self {
            case .touchID: return "touchid"
            case .none: return "lock.shield"
            }
        }
        
        var title: String {
            switch self {
            case .touchID: return "Touch ID"
            case .none: return "Passcode"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: biometricType.icon)
                .font(.system(size: 64, weight: .light))
                .foregroundColor(.white.opacity(0.8))
            
            VStack(spacing: 8) {
                Text("Enable \(biometricType.title)")
                    .font(.custom("ClashGrotesk-Bold", size: 24))
                    .foregroundColor(.white)
                
                Text("Quick and secure access to your wallet")
                    .font(.custom("ClashGrotesk-Regular", size: 15))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            VStack(spacing: 12) {
                PrimaryButton(title: "Enable \(biometricType.title)", action: onEnable)
                SecondaryButton(title: "Use PIN instead", action: onSkip)
            }
        }
    }
}

// MARK: - Success State View
struct SuccessStateView: View {
    let title: String
    let subtitle: String?
    @State private var showCheckmark = false
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.green)
                    .scaleEffect(showCheckmark ? 1 : 0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: showCheckmark)
            }
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.custom("ClashGrotesk-Bold", size: 28))
                    .foregroundColor(.white)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.custom("ClashGrotesk-Regular", size: 15))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showCheckmark = true
            }
        }
    }
}

// MARK: - Warning Banner
struct WarningBanner: View {
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
    
    let level: Level
    let message: String
    var action: (() -> Void)?
    var actionTitle: String?
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: level.icon)
                .foregroundColor(level.color)
            
            Text(message)
                .font(.custom("ClashGrotesk-Regular", size: 13))
                .foregroundColor(.white.opacity(0.9))
            
            Spacer()
            
            if let action = action, let title = actionTitle {
                Button(title, action: action)
                    .font(.custom("ClashGrotesk-Medium", size: 13))
                    .foregroundColor(level.color)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(level.color.opacity(0.15))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(level.color.opacity(0.3), lineWidth: 1)
                }
        }
    }
}

// MARK: - Address Display
struct AddressDisplay: View {
    let address: String
    var showFullOnHover: Bool = true
    
    @State private var isHovering = false
    @State private var copied = false
    
    var displayAddress: String {
        if isHovering && showFullOnHover {
            return address
        }
        return truncateAddress(address)
    }
    
    func truncateAddress(_ addr: String) -> String {
        guard addr.count > 12 else { return addr }
        return "\(addr.prefix(6))...\(addr.suffix(4))"
    }
    
    var body: some View {
        HStack(spacing: 16) {
            Text(displayAddress)
                .font(.custom("SF Mono", size: 14))
                .foregroundColor(.white)
                .animation(.easeInOut(duration: 0.2), value: isHovering)
            
            Spacer()
            
            HStack(spacing: 12) {
                IconButton(icon: copied ? "checkmark" : "doc.on.doc") {
                    copyToClipboard()
                }
                
                IconButton(icon: "square.and.arrow.up") {
                    // Share action
                }
                
                IconButton(icon: "qrcode") {
                    // Show QR
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(address, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}

struct IconButton: View {
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.1))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Persona Card
struct PersonaCard: View {
    let icon: String
    let title: String
    let tagline: String
    let isSelected: Bool
    let action: () -> Void
    
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
                        .font(.custom("ClashGrotesk-Regular", size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isSelected ? Color.white.opacity(0.4) : Color.white.opacity(0.1),
                                lineWidth: isSelected ? 2 : 1
                            )
                    }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Bottom Sheet (macOS)
struct BottomSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let sheetContent: () -> SheetContent
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if isPresented {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isPresented = false
                        }
                    }
                
                VStack {
                    Spacer()
                    
                    VStack(spacing: 0) {
                        // Handle
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 40, height: 4)
                            .padding(.top, 12)
                            .padding(.bottom, 20)
                        
                        sheetContent()
                            .padding(.horizontal, 24)
                            .padding(.bottom, 32)
                    }
                    .frame(maxWidth: 500)
                    .background {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(.ultraThickMaterial)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .padding(24)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isPresented)
    }
}

extension View {
    func bottomSheet<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(BottomSheetModifier(isPresented: isPresented, sheetContent: content))
    }
}

// MARK: - Inline Toast
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
            case .success: return .green
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
                .overlay {
                    Capsule()
                        .stroke(type.color.opacity(0.3), lineWidth: 1)
                }
        }
    }
}

// MARK: - Skeleton Loader
struct SkeletonLoader: View {
    @State private var isAnimating = false
    
    var body: some View {
        LinearGradient(
            colors: [
                Color.white.opacity(0.05),
                Color.white.opacity(0.1),
                Color.white.opacity(0.05)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .mask(RoundedRectangle(cornerRadius: 8))
        .offset(x: isAnimating ? 200 : -200)
        .animation(
            Animation.linear(duration: 1.5)
                .repeatForever(autoreverses: false),
            value: isAnimating
        )
        .onAppear { isAnimating = true }
    }
}

// MARK: - Keyboard Input Handler (macOS)
struct KeyboardInputHandler: NSViewRepresentable {
    let onKeyPress: (String) -> Void
    
    func makeNSView(context: Context) -> KeyboardInputNSView {
        let view = KeyboardInputNSView()
        view.onKeyPress = onKeyPress
        return view
    }
    
    func updateNSView(_ nsView: KeyboardInputNSView, context: Context) {
        nsView.onKeyPress = onKeyPress
        DispatchQueue.main.async {
            if nsView.window?.firstResponder != nsView {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

class KeyboardInputNSView: NSView {
    var onKeyPress: ((String) -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        if let chars = event.characters {
            onKeyPress?(chars)
        }
    }
}
```

---

## 4. Quick Onboarding Flow (Power User)

### File: `Sources/swift-app/Views/Onboarding/QuickOnboardingFlow.swift`

### Screen Specifications

#### Screen 1: Welcome (Shared)
```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│                                                                 │
│                                                                 │
│                                                                 │
│                           HAWALA                                │
│                                                                 │
│                    Your keys. Your future.                      │
│                                                                 │
│                                                                 │
│                                                                 │
│                    ┌─────────────────────┐                      │
│                    │      Let's Go       │                      │
│                    └─────────────────────┘                      │
│                                                                 │
│                                                                 │
│                                                                 │
│                         · · · · ·                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Implementation:**
```swift
struct WelcomeScreen: View {
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            VStack(spacing: 16) {
                Text("HAWALA")
                    .font(.custom("ClashGrotesk-Bold", size: 48))
                    .foregroundColor(.white)
                    .tracking(4)
                
                Text("Your keys. Your future.")
                    .font(.custom("ClashGrotesk-Regular", size: 18))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            VStack(spacing: 20) {
                PrimaryButton(title: "Let's Go", action: onContinue)
                    .frame(maxWidth: 280)
            }
            
            Spacer()
                .frame(height: 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

---

#### Screen 2: Path Selection
```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│                    What brings you here?                        │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  ✦  Create New Wallet                                   │   │
│   │     Start fresh with a new self-custody wallet          │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  ↓  Import Existing Wallet                              │   │
│   │     Bring your keys from another wallet                 │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  ◇  Connect Hardware Wallet                             │   │
│   │     Ledger, Trezor, and more                            │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   ─────────────────────────────────────────────────────────     │
│                                                                 │
│   ☑ Quick Setup                    ☐ Guided Setup               │
│     Skip education, fast setup       Full walkthrough           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Microcopy:**
- Title: `What brings you here?`
- Create: `Start fresh with a new self-custody wallet`
- Import: `Bring your keys from another wallet`
- Hardware: `Ledger, Trezor, and more`
- Quick toggle: `Skip education, fast setup`
- Guided toggle: `Full walkthrough`

---

#### Screen 3: Quick Auth Setup
```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│                    Secure your wallet                           │
│                 One tap. Maximum protection.                    │
│                                                                 │
│                        ┌─────────────┐                          │
│                        │             │                          │
│                        │  [Touch ID] │                          │
│                        │             │                          │
│                        └─────────────┘                          │
│                                                                 │
│                    ┌─────────────────────┐                      │
│                    │   Enable Touch ID   │                      │
│                    └─────────────────────┘                      │
│                                                                 │
│                        Use PIN instead                          │
│                                                                 │
│   ─────────────────────────────────────────────────────────     │
│                                                                 │
│   ☑ Back up to iCloud (encrypted)                               │
│     Your recovery phrase, protected by your Apple ID            │
│                                                                 │
│   ☐ Enable advanced security mode                               │
│     Transaction simulation, risk scoring, MEV protection        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

#### Screen 4: Power Settings (Optional)
```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│                    Configure your setup                         │
│                                                                 │
│   Default Networks                                              │
│   ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐              │
│   │ ETH │ │ SOL │ │ BTC │ │ ARB │ │ OP  │ │ +   │              │
│   └─────┘ └─────┘ └─────┘ └─────┘ └─────┘ └─────┘              │
│                                                                 │
│   ─────────────────────────────────────────────────────────     │
│                                                                 │
│   Power User Options                                            │
│                                                                 │
│   ☐ Enable Testnet Mode                                         │
│   ☑ Transaction Simulation                                      │
│   ☑ MEV Protection                                              │
│   ☐ WalletConnect Auto-accept                                   │
│   ☑ Gas Sponsorship (when available)                            │
│   ☐ Advanced RPC Settings                                       │
│                                                                 │
│                    ┌─────────────────────┐                      │
│                    │   Complete Setup    │                      │
│                    └─────────────────────┘                      │
│                                                                 │
│                       Customize later                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

#### Screen 5: Ready
```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│                           ✓                                     │
│                                                                 │
│                     You're all set                              │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │                                                         │   │
│   │              0x7a3B...4f2D                              │   │
│   │                                                         │   │
│   │         [Copy]    [Share]    [QR]                       │   │
│   │                                                         │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│                                                                 │
│                    ┌─────────────────────┐                      │
│                    │  Start Using Hawala │                      │
│                    └─────────────────────┘                      │
│                                                                 │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  ✦ Security Score: 85/100                               │   │
│   │    Enable recovery guardians to reach 100 →             │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 5. Advanced Onboarding Flow (Guided)

### Screen Specifications

#### Screen G1: Welcome (Shared - Same as Quick)

---

#### Screen G2: Self-Custody Education
```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│                    Your wallet. Your rules.                     │
│                                                                 │
│                        ┌───────────────┐                        │
│                        │  [Animation]  │                        │
│                        │  Key → Lock   │                        │
│                        └───────────────┘                        │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  ✦  You own your keys                                   │   │
│   │     No company can freeze your funds or lock you out    │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  ◇  You control access                                  │   │
│   │     Your recovery phrase is the only way to restore     │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  ⚡ You're protected                                    │   │
│   │     Hawala warns you before risky transactions          │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│                    ┌─────────────────────┐                      │
│                    │    I Understand     │                      │
│                    └─────────────────────┘                      │
│                                                                 │
│                         Learn more                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

#### Screen G3: Persona Selection
```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│                   How will you use Hawala?                      │
│                 We'll customize your experience                 │
│                                                                 │
│   ┌─────────────────────────┐   ┌─────────────────────────┐     │
│   │           👤            │   │           💎            │     │
│   │        Beginner         │   │        Collector        │     │
│   │                         │   │                         │     │
│   │    "Just here to HODL"  │   │   "NFTs and art lover"  │     │
│   └─────────────────────────┘   └─────────────────────────┘     │
│                                                                 │
│   ┌─────────────────────────┐   ┌─────────────────────────┐     │
│   │           📈            │   │           🔧            │     │
│   │         Trader          │   │         Builder         │     │
│   │                         │   │                         │     │
│   │    "DeFi and swaps"     │   │   "Developer mode ON"   │     │
│   └─────────────────────────┘   └─────────────────────────┘     │
│                                                                 │
│                                                                 │
│                      I'm not sure yet                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Persona Effects:**

| Persona | Default Settings |
|---------|-----------------|
| **Beginner** | Simplified UI, extra warnings ON, educational tooltips ON, basic chains only |
| **Collector** | NFT gallery prominent, OpenSea/Blur integration, IPFS preview |
| **Trader** | Charts visible, DEX quick-access, price alerts ON, advanced gas controls |
| **Builder** | Testnet toggle visible, contract tools, gas estimates, raw TX view |

---

#### Screen G4: Create/Import Selection (Same as Quick)

---

#### Screen G5: Recovery Phrase Display
```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│                    Your recovery phrase                         │
│       Write these 12 words in order. This is the ONLY way      │
│                  to recover your wallet.                        │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │                                                         │   │
│   │   1. apple     2. brave     3. coral     4. delta       │   │
│   │   5. eagle     6. frost     7. grape     8. honey       │   │
│   │   9. ivory    10. joker    11. karma    12. lemon       │   │
│   │                                                         │   │
│   │                      [Copy All]                         │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   ⚠️ Never share these words. Hawala will never ask for them.   │
│                                                                 │
│                    ┌─────────────────────┐                      │
│                    │    I've Saved It    │                      │
│                    └─────────────────────┘                      │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  ☁️ Save to iCloud instead                               │   │
│   │    Encrypted with your Apple ID. Easier recovery.       │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Security Features:**
- Screenshot detection shows warning toast
- Copy button requires confirmation
- 30-second auto-hide option
- iCloud backup encrypts with user's Keychain

---

#### Screen G6: Verify Backup (Gamified)
```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│                   Let's verify your backup                      │
│                  Select word #3, #7, and #11                    │
│                                                                 │
│   Word #3                                                       │
│   ┌─────────┐   ┌─────────┐   ┌─────────┐                       │
│   │  coral  │   │  brave  │   │  delta  │                       │
│   └─────────┘   └─────────┘   └─────────┘                       │
│                                                                 │
│   Word #7                                                       │
│   ┌─────────┐   ┌─────────┐   ┌─────────┐                       │
│   │  honey  │   │  grape  │   │  frost  │                       │
│   └─────────┘   └─────────┘   └─────────┘                       │
│                                                                 │
│   Word #11                                                      │
│   ┌─────────┐   ┌─────────┐   ┌─────────┐                       │
│   │  joker  │   │  lemon  │   │  karma  │                       │
│   └─────────┘   └─────────┘   └─────────┘                       │
│                                                                 │
│                    ┌─────────────────────┐                      │
│                    │       Verify        │                      │
│                    └─────────────────────┘                      │
│                                                                 │
│                    Skip for now (risky)                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Interaction:**
- Correct selection: Green glow + sound chime
- Wrong selection: Red shake + buzz sound
- All correct: Success animation + proceed

---

#### Screen G7: Security Setup
```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│                    Lock down your wallet                        │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  ● ● ● ● ● ●                                            │   │
│   │                                                         │   │
│   │  Create a 6-digit PIN                                   │   │
│   │  Use this when Touch ID isn't available                 │   │
│   │                                                         │   │
│   │  1  2  3  4  5  6  7  8  9  0  ⌫                        │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   ─────────────────────────────────────────────────────────     │
│                                                                 │
│   Additional Security                                           │
│                                                                 │
│   ☑ Require authentication for transactions over $100          │
│   ☑ Auto-lock after 5 minutes                                  │
│   ☐ Hide balances by default                                   │
│                                                                 │
│                    ┌─────────────────────┐                      │
│                    │      Continue       │                      │
│                    └─────────────────────┘                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

#### Screen G8: Guardian Setup (Social Recovery)
```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│                   Add recovery guardians                        │
│     If you ever lose access, they can help you recover          │
│                      your wallet.                               │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  ✦ How it works                                         │   │
│   │                                                         │   │
│   │  • Choose 2-3 trusted people                            │   │
│   │  • They can't access your funds                         │   │
│   │  • 2 of 3 needed to recover                             │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  👤 Add Guardian                                        │   │
│   │     via email, phone, or wallet address                 │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│                    ┌─────────────────────┐                      │
│                    │   Add Guardians     │                      │
│                    └─────────────────────┘                      │
│                                                                 │
│                       Skip for now                              │
│            You can add guardians later in Settings              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

#### Screen G9: Practice Mode
```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│                  Try a practice transaction                     │
│                  No real money. Just learning.                  │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │                                                         │   │
│   │        You're receiving 1 ETH (fake)                    │   │
│   │        from practice.hawala.eth                         │   │
│   │                                                         │   │
│   │              ┌─────────────────────┐                    │   │
│   │              │       Accept        │                    │   │
│   │              └─────────────────────┘                    │   │
│   │                                                         │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  ⚡ This is a simulation                                │   │
│   │    See how transactions look before doing it for real   │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│                    ┌─────────────────────┐                      │
│                    │       Try It        │                      │
│                    └─────────────────────┘                      │
│                                                                 │
│                      Skip to wallet                             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Practice Sequence:**
1. Show incoming transaction notification
2. User clicks Accept
3. Animate balance update (0 → 1 ETH)
4. Show success state
5. Prompt: "Now try sending some back"
6. Show send flow simulation
7. Complete with celebration

---

#### Screen G10: Security Score + Ready
```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│                           ✓                                     │
│                    Welcome to Hawala                            │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │                                                         │   │
│   │                  Security Score                         │   │
│   │                                                         │   │
│   │                   ████████░░                            │   │
│   │                     85/100                              │   │
│   │                                                         │   │
│   │     ✓ Biometric lock enabled                            │   │
│   │     ✓ Recovery phrase backed up                         │   │
│   │     ✓ PIN created                                       │   │
│   │     ○ Add recovery guardians (+10)                      │   │
│   │     ○ Enable 2FA on backups (+5)                        │   │
│   │                                                         │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│                    ┌─────────────────────┐                      │
│                    │    Enter Wallet     │                      │
│                    └─────────────────────┘                      │
│                                                                 │
│               Complete setup later in Settings                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 6. Security & Trust Patterns

### Visual Trust Signals

| Signal | Location | Implementation |
|--------|----------|----------------|
| Lock indicator | Top-right header | Subtle padlock icon, green when secure |
| Verification badge | Contract/address display | Green checkmark for verified |
| Risk pill | Transaction preview | Red/Yellow/Green capsule |
| Human-readable TX | Transaction sheet | Plain English summary |
| Simulation preview | Pre-sign modal | "Balance will change from X to Y" |

### Scam Prevention UI

#### Screenshot Warning
```swift
struct ScreenshotWarning: View {
    var body: some View {
        WarningBanner(
            level: .warning,
            message: "Screenshots can be stolen. Write down your phrase instead."
        )
    }
}
```

#### Phishing Detection
```swift
struct PhishingAlert: View {
    let domain: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)
            
            Text("Suspicious Site Detected")
                .font(.custom("ClashGrotesk-Bold", size: 20))
            
            Text("This site (\(domain)) is asking for your recovery phrase. Hawala will NEVER ask for it.")
                .font(.custom("ClashGrotesk-Regular", size: 14))
                .multilineTextAlignment(.center)
            
            HStack(spacing: 16) {
                PrimaryButton(title: "Block Site") { }
                SecondaryButton(title: "I understand the risk") { }
            }
        }
    }
}
```

### Transaction Simulation UI

```swift
struct TransactionPreview: View {
    let transaction: SimulatedTransaction
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Text("Transaction Preview")
                    .font(.custom("ClashGrotesk-Bold", size: 18))
                Spacer()
                RiskBadge(level: transaction.riskLevel)
            }
            
            Divider()
            
            // Action summary
            GlassCard(padding: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(transaction.humanReadableSummary)
                    }
                    
                    Text("To: \(transaction.recipient)")
                        .font(.custom("ClashGrotesk-Regular", size: 13))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            // Balance changes
            GlassCard(padding: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What changes:")
                        .font(.custom("ClashGrotesk-Medium", size: 14))
                    
                    ForEach(transaction.balanceChanges) { change in
                        HStack {
                            Text(change.token)
                            Spacer()
                            Text("\(change.before) → \(change.after)")
                                .foregroundColor(change.isDecrease ? .red : .green)
                        }
                    }
                }
            }
            
            // Risk level
            HStack {
                Text("Risk Level:")
                RiskBadge(level: transaction.riskLevel)
            }
            
            // Actions
            HStack(spacing: 16) {
                Button("Cancel") { }
                    .frame(maxWidth: .infinity)
                
                PrimaryButton(title: "Confirm") { }
            }
        }
        .padding(24)
    }
}

struct RiskBadge: View {
    let level: RiskLevel
    
    enum RiskLevel {
        case low, medium, high, critical
        
        var color: Color {
            switch self {
            case .low: return .green
            case .medium: return .yellow
            case .high: return .orange
            case .critical: return .red
            }
        }
        
        var label: String {
            switch self {
            case .low: return "LOW"
            case .medium: return "MEDIUM"
            case .high: return "HIGH"
            case .critical: return "CRITICAL"
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(level.color)
                .frame(width: 6, height: 6)
            
            Text(level.label)
                .font(.custom("ClashGrotesk-Medium", size: 11))
                .foregroundColor(level.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule()
                .fill(level.color.opacity(0.2))
        }
    }
}
```

---

## 7. Animation & Interaction System

### Animation Tokens

```swift
enum OnboardingAnimation {
    // Transitions
    static let screenTransition = Animation.easeInOut(duration: 0.35)
    static let elementAppear = Animation.easeOut(duration: 0.25)
    static let microInteraction = Animation.easeInOut(duration: 0.15)
    
    // Springs
    static let buttonPress = Animation.spring(response: 0.2, dampingFraction: 0.7)
    static let successBounce = Animation.spring(response: 0.4, dampingFraction: 0.6)
    static let cardSelection = Animation.spring(response: 0.3, dampingFraction: 0.8)
    
    // Timing
    static let loadingPulse = Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)
    static let silkWave = Animation.linear(duration: 20).repeatForever(autoreverses: false)
}
```

### Transition Effects

```swift
extension AnyTransition {
    static var onboardingSlide: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
    
    static var fadeScale: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.95))
    }
}
```

### Sound Feedback (macOS)

```swift
class SoundManager {
    static let shared = SoundManager()
    
    enum SoundType: String {
        case tap = "Tink"
        case success = "Glass"
        case error = "Basso"
        case notification = "Pop"
    }
    
    func play(_ type: SoundType) {
        NSSound(named: type.rawValue)?.play()
    }
}
```

### Haptic Feedback (Trackpad)

```swift
class HapticManager {
    static let shared = HapticManager()
    
    func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .now
        )
    }
    
    func success() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange,
            performanceTime: .now
        )
    }
}
```

---

## 8. Edge Case Handling

### Import Wallet Flow

```swift
struct ImportWalletSheet: View {
    @State private var selectedMethod: ImportMethod?
    
    enum ImportMethod: CaseIterable {
        case seedPhrase
        case privateKey
        case qrCode
        case hardware
        case iCloud
        
        var icon: String { ... }
        var title: String { ... }
        var subtitle: String { ... }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Import your wallet")
                .font(.custom("ClashGrotesk-Bold", size: 24))
            
            ForEach(ImportMethod.allCases, id: \.self) { method in
                ImportMethodCard(method: method, isSelected: selectedMethod == method) {
                    selectedMethod = method
                }
            }
        }
    }
}
```

### Lost Backup Recovery

```swift
struct LostBackupRecovery: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("Can't find your recovery phrase?")
                .font(.custom("ClashGrotesk-Bold", size: 24))
            
            VStack(spacing: 16) {
                RecoveryOption(
                    icon: "☁️",
                    title: "Check iCloud Backup",
                    description: "We'll look for a saved encrypted backup"
                )
                
                RecoveryOption(
                    icon: "👥",
                    title: "Contact Guardians",
                    description: "If you set up social recovery, they can help"
                )
                
                RecoveryOption(
                    icon: "🔧",
                    title: "Hardware Wallet",
                    description: "Your keys might be on a connected device"
                )
            }
            
            Divider()
            
            Text("Unfortunately, without one of these options, your wallet cannot be recovered. This is how self-custody works—only you control access.")
                .font(.custom("ClashGrotesk-Regular", size: 13))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
    }
}
```

### High-Risk Approval Warning

```swift
struct HighRiskApprovalSheet: View {
    let warnings: [String]
    let contractInfo: ContractInfo
    
    var body: some View {
        VStack(spacing: 20) {
            // Critical header
            HStack {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundColor(.red)
                Text("HIGH RISK DETECTED")
                    .font(.custom("ClashGrotesk-Bold", size: 18))
                    .foregroundColor(.red)
            }
            
            Divider()
            
            // Warnings list
            VStack(alignment: .leading, spacing: 12) {
                Text("This transaction may:")
                    .font(.custom("ClashGrotesk-Medium", size: 14))
                
                ForEach(warnings, id: \.self) { warning in
                    HStack(alignment: .top, spacing: 8) {
                        Text("⚠️")
                        Text(warning)
                            .font(.custom("ClashGrotesk-Regular", size: 13))
                    }
                }
            }
            
            // Contract info
            GlassCard(padding: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(label: "Contract", value: contractInfo.address)
                    InfoRow(label: "Age", value: contractInfo.age)
                    InfoRow(label: "Transactions", value: "\(contractInfo.txCount)")
                    
                    HStack {
                        Text("Risk Score:")
                        RiskBadge(level: .critical)
                        Text("\(contractInfo.riskScore)/100")
                    }
                }
            }
            
            Text("Are you absolutely sure?")
                .font(.custom("ClashGrotesk-Medium", size: 15))
            
            // Actions
            HStack(spacing: 16) {
                Button("Cancel") { }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                
                Button("I understand, proceed") { }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.3))
                    .cornerRadius(12)
            }
            
            Toggle("Don't warn me about this site again", isOn: .constant(false))
                .font(.custom("ClashGrotesk-Regular", size: 12))
        }
    }
}
```

### Wrong Network Detection

```swift
struct NetworkMismatchAlert: View {
    let currentNetwork: String
    let expectedNetwork: String
    let token: String
    let balance: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "bolt.circle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 24))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Network Mismatch")
                    .font(.custom("ClashGrotesk-Semibold", size: 14))
                
                Text("You're trying to send \(token) on \(currentNetwork) but this dApp is connected to \(expectedNetwork).")
                    .font(.custom("ClashGrotesk-Regular", size: 12))
                    .foregroundColor(.white.opacity(0.7))
                
                Text("Your \(expectedNetwork) \(token) balance: \(balance)")
                    .font(.custom("ClashGrotesk-Regular", size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            Button("Switch to \(expectedNetwork)") { }
                .font(.custom("ClashGrotesk-Medium", size: 12))
                .foregroundColor(.orange)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.15))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                }
        }
    }
}
```

---

## 9. Activation Strategy

### First 2 Minutes Goals

| Time | Goal | Implementation |
|------|------|----------------|
| 0:00-0:30 | Create/import wallet | Quick path: 4 screens max |
| 0:30-1:00 | See address + security score | Ready screen with address display |
| 1:00-1:30 | First interaction | Copy address / Show QR |
| 1:30-2:00 | Feature discovery | Coachmark for main actions |

### First Session Nudges

```swift
struct FirstSessionNudge: View {
    let type: NudgeType
    
    enum NudgeType {
        case buyFirst
        case receiveFirst
        case exploreSettings
        
        var icon: String { ... }
        var title: String { ... }
        var action: String { ... }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Text(type.icon)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Quick tip")
                    .font(.custom("ClashGrotesk-Medium", size: 12))
                    .foregroundColor(.white.opacity(0.5))
                
                Text(type.title)
                    .font(.custom("ClashGrotesk-Regular", size: 14))
            }
            
            Spacer()
            
            Button(type.action) { }
                .font(.custom("ClashGrotesk-Medium", size: 13))
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
    }
}
```

### Coachmarks

```swift
struct CoachmarkOverlay: View {
    let target: CGRect
    let message: String
    let position: Position
    
    enum Position {
        case above, below, leading, trailing
    }
    
    var body: some View {
        ZStack {
            // Dimmed background with cutout
            Color.black.opacity(0.6)
                .mask(
                    Rectangle()
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .frame(width: target.width + 8, height: target.height + 8)
                                .position(x: target.midX, y: target.midY)
                                .blendMode(.destinationOut)
                        )
                )
            
            // Tooltip
            VStack(spacing: 8) {
                Text(message)
                    .font(.custom("ClashGrotesk-Regular", size: 14))
                    .foregroundColor(.white)
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.8))
                    }
                
                // Arrow pointing to target
                Triangle()
                    .fill(Color.black.opacity(0.8))
                    .frame(width: 12, height: 8)
            }
            .position(tooltipPosition)
        }
    }
}
```

---

## 10. Implementation Phases

### Phase 1: Foundation (Week 1-2)

**Goal:** Core flow working end-to-end

**Tasks:**
- [ ] Create `OnboardingComponents.swift` with all base components
- [ ] Implement `OnboardingFlowView.swift` with state machine
- [ ] Build Welcome screen
- [ ] Build Path Selection screen (Quick/Guided toggle)
- [ ] Build Create/Import selection screen
- [ ] Implement basic wallet creation (seed phrase generation)
- [ ] Build PIN/Biometric setup screen
- [ ] Build Ready screen with address display
- [ ] Wire up navigation between screens
- [ ] Add screen transitions

**Deliverables:**
- Complete Quick Onboarding flow (5 screens)
- User can create wallet and see address
- Basic biometric/PIN authentication

---

### Phase 2: Security Layer (Week 3-4)

**Goal:** Full security infrastructure

**Tasks:**
- [ ] Implement Keychain storage for seed phrase
- [ ] Add iCloud backup option (encrypted)
- [ ] Build Recovery Phrase display screen
- [ ] Build Backup Verification game screen
- [ ] Implement Security Score calculation
- [ ] Add screenshot detection warning
- [ ] Build high-risk transaction warnings
- [ ] Implement transaction simulation preview
- [ ] Add network mismatch detection

**Deliverables:**
- Secure seed phrase storage
- Backup verification flow
- Security Score visible at completion
- Transaction simulation ready

---

### Phase 3: Guided Experience (Week 5-6)

**Goal:** Full guided onboarding path

**Tasks:**
- [ ] Build Self-Custody Education screen
- [ ] Build Persona Selection screen
- [ ] Implement persona-based defaults
- [ ] Build Guardian Setup screen
- [ ] Build Practice Mode screens (receive/send simulation)
- [ ] Add educational tooltips for Beginner persona
- [ ] Implement progressive disclosure system
- [ ] Build Security Score detail view

**Deliverables:**
- Complete Guided Onboarding flow (10 screens)
- Practice mode functional
- Persona affects default settings

---

### Phase 4: Import Flows (Week 7-8)

**Goal:** All import methods working

**Tasks:**
- [ ] Build Seed Phrase import (12/18/24 words)
- [ ] Build Private Key import
- [ ] Build QR Code import (camera integration)
- [ ] Build Hardware Wallet connection (Ledger/Trezor)
- [ ] Build iCloud Backup restore
- [ ] Implement Lost Backup Recovery flow
- [ ] Add import validation and error states
- [ ] Build multiple wallet support

**Deliverables:**
- All 5 import methods functional
- Recovery options for lost access
- Multi-wallet architecture

---

### Phase 5: Polish (Week 9-10)

**Goal:** Premium feel and edge cases

**Tasks:**
- [ ] Refine all animations (silk background, transitions)
- [ ] Add sound feedback
- [ ] Add trackpad haptics
- [ ] Implement coachmarks for first launch
- [ ] Add first-session nudges
- [ ] Build all warning/alert states
- [ ] Accessibility audit (VoiceOver, keyboard nav)
- [ ] Performance optimization
- [ ] Error state handling
- [ ] Edge case testing

**Deliverables:**
- Polished, premium experience
- Full accessibility support
- All edge cases handled

---

### Phase 6: Testing & Launch (Week 11-12)

**Goal:** Production-ready

**Tasks:**
- [ ] Unit tests for state machine
- [ ] UI tests for critical flows
- [ ] Security audit for key storage
- [ ] Beta testing with real users
- [ ] Analytics integration
- [ ] A/B test setup for Quick vs Guided
- [ ] Performance benchmarking
- [ ] Final QA pass

**Deliverables:**
- Comprehensive test coverage
- User feedback incorporated
- Production-ready onboarding

---

## 11. File Structure

```
Sources/swift-app/
├── Views/
│   └── Onboarding/
│       ├── OnboardingFlowView.swift          # Main flow coordinator
│       ├── OnboardingState.swift             # State machine
│       ├── Screens/
│       │   ├── WelcomeScreen.swift
│       │   ├── PathSelectionScreen.swift
│       │   ├── SelfCustodyEducationScreen.swift
│       │   ├── PersonaSelectionScreen.swift
│       │   ├── CreateImportScreen.swift
│       │   ├── RecoveryPhraseScreen.swift
│       │   ├── VerifyBackupScreen.swift
│       │   ├── SecuritySetupScreen.swift
│       │   ├── GuardianSetupScreen.swift
│       │   ├── PracticeScreen.swift
│       │   ├── PowerSettingsScreen.swift
│       │   └── ReadyScreen.swift
│       └── Import/
│           ├── ImportSeedPhraseView.swift
│           ├── ImportPrivateKeyView.swift
│           ├── ImportQRCodeView.swift
│           ├── ImportHardwareView.swift
│           └── ImportiCloudView.swift
│
├── Components/
│   ├── OnboardingComponents.swift            # All reusable components
│   ├── GlassCard.swift
│   ├── PrimaryButton.swift
│   ├── SecondaryButton.swift
│   ├── InfoCard.swift
│   ├── ToggleRow.swift
│   ├── ChipSelector.swift
│   ├── ProgressIndicator.swift
│   ├── SecurityScoreRing.swift
│   ├── WordGrid.swift
│   ├── WordSelector.swift
│   ├── BiometricPromptView.swift
│   ├── SuccessStateView.swift
│   ├── WarningBanner.swift
│   ├── AddressDisplay.swift
│   ├── PersonaCard.swift
│   ├── BottomSheet.swift
│   ├── InlineToast.swift
│   ├── SkeletonLoader.swift
│   └── KeyboardInputHandler.swift
│
├── Managers/
│   ├── OnboardingManager.swift               # Flow logic
│   ├── WalletCreationManager.swift           # Seed generation
│   ├── BiometricManager.swift                # Touch ID
│   ├── KeychainManager.swift                 # Secure storage
│   ├── iCloudBackupManager.swift             # Cloud backup
│   ├── GuardianManager.swift                 # Social recovery
│   ├── SecurityScoreManager.swift            # Score calculation
│   └── PersonaManager.swift                  # Persona settings
│
├── Models/
│   ├── OnboardingStep.swift
│   ├── UserPersona.swift
│   ├── SecurityScore.swift
│   ├── Guardian.swift
│   └── SimulatedTransaction.swift
│
├── Utilities/
│   ├── SoundManager.swift
│   ├── HapticManager.swift
│   └── OnboardingAnimations.swift
│
└── Resources/
    ├── Sounds/
    │   ├── success.aiff
    │   ├── tap.aiff
    │   └── error.aiff
    └── Animations/
        └── confetti.json (Lottie)
```

---

## 12. Technical Specifications

### Minimum Requirements

| Requirement | Specification |
|-------------|--------------|
| macOS Version | 13.0+ (Ventura) |
| Swift Version | 5.9+ |
| Xcode Version | 15.0+ |
| Window Size | Min 900×600, Max 1200×800 |
| Architecture | arm64 (Apple Silicon) + x86_64 (Intel) |

### Dependencies

```swift
// Package.swift additions
dependencies: [
    .package(url: "https://github.com/nicklockwood/LottieSwift", from: "4.0.0"),
    .package(url: "https://github.com/krzyzanowskim/CryptoSwift", from: "1.8.0"),
]
```

### Security Requirements

| Feature | Implementation |
|---------|---------------|
| Seed Phrase Storage | Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` |
| iCloud Backup | Encrypted with user's Keychain key |
| Biometric | LAContext with `.deviceOwnerAuthenticationWithBiometrics` |
| PIN Storage | Salted hash in Keychain |
| Memory Safety | Clear sensitive data from memory after use |
| Screenshot Prevention | Detect and warn, cannot prevent on macOS |

### Performance Targets

| Metric | Target |
|--------|--------|
| Quick flow completion | <45 seconds |
| Guided flow completion | <3 minutes |
| Screen transition | <300ms |
| Wallet generation | <500ms |
| App launch to wallet | <2 seconds |

### Analytics Events

```swift
enum OnboardingEvent: String {
    case flowStarted = "onboarding_flow_started"
    case pathSelected = "onboarding_path_selected"
    case personaSelected = "onboarding_persona_selected"
    case walletCreated = "onboarding_wallet_created"
    case walletImported = "onboarding_wallet_imported"
    case backupCompleted = "onboarding_backup_completed"
    case backupSkipped = "onboarding_backup_skipped"
    case biometricEnabled = "onboarding_biometric_enabled"
    case guardianAdded = "onboarding_guardian_added"
    case practiceCompleted = "onboarding_practice_completed"
    case flowCompleted = "onboarding_flow_completed"
    case flowAbandoned = "onboarding_flow_abandoned"
}
```

---

## Checklist Summary

### Quick Path Screens
- [ ] Welcome
- [ ] Path Selection (with Quick toggle)
- [ ] Create/Import Selection
- [ ] Auth Setup (Biometric + PIN + Backup)
- [ ] Power Settings (Optional)
- [ ] Ready

### Guided Path Screens
- [ ] Welcome (shared)
- [ ] Self-Custody Education
- [ ] Persona Selection
- [ ] Create/Import Selection
- [ ] Recovery Phrase Display
- [ ] Verify Backup
- [ ] Security Setup
- [ ] Guardian Setup
- [ ] Practice Mode
- [ ] Security Score + Ready

### Components
- [ ] GlassCard
- [ ] PrimaryButton
- [ ] SecondaryButton
- [ ] InfoCard
- [ ] ToggleRow
- [ ] ChipSelector
- [ ] ProgressIndicator
- [ ] SecurityScoreRing
- [ ] WordGrid
- [ ] WordSelector
- [ ] BiometricPromptView
- [ ] SuccessStateView
- [ ] WarningBanner
- [ ] AddressDisplay
- [ ] PersonaCard
- [ ] BottomSheet
- [ ] InlineToast
- [ ] SkeletonLoader
- [ ] KeyboardInputHandler

### Managers
- [ ] OnboardingManager
- [ ] WalletCreationManager
- [ ] BiometricManager
- [ ] KeychainManager
- [ ] iCloudBackupManager
- [ ] GuardianManager
- [ ] SecurityScoreManager
- [ ] PersonaManager
- [ ] SoundManager
- [ ] HapticManager

### Edge Cases
- [ ] Import Seed Phrase (12/18/24)
- [ ] Import Private Key
- [ ] Import QR Code
- [ ] Connect Hardware Wallet
- [ ] Restore iCloud Backup
- [ ] Lost Backup Recovery
- [ ] High-Risk Approval
- [ ] Network Mismatch
- [ ] Suspicious Token
- [ ] Bridge Risk Warning

---

**Ready to implement. Start with Phase 1: Foundation.**
