import SwiftUI

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Hawala PIN Pad
// Custom 3×4 numeric keypad for passcode and duress PIN entry.
// Fully hand-coded — no system keyboard, no text fields.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct HawalaPinPad: View {
    @Binding var pin: String
    let maxDigits: Int
    let onComplete: (String) -> Void
    
    @State private var pressedKey: String?
    
    private let keys: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["delete", "0", "confirm"]
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            // Dot indicators
            dotRow
            
            // Keypad grid
            VStack(spacing: 12) {
                ForEach(keys, id: \.self) { row in
                    HStack(spacing: 12) {
                        ForEach(row, id: \.self) { key in
                            pinKey(key)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Dot Indicators
    private var dotRow: some View {
        HStack(spacing: 14) {
            ForEach(0..<maxDigits, id: \.self) { index in
                Circle()
                    .fill(index < pin.count ? Color.white : Color.white.opacity(0.12))
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .scaleEffect(index < pin.count ? 1.0 : 0.85)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: pin.count)
            }
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - Key Button
    @ViewBuilder
    private func pinKey(_ key: String) -> some View {
        let isPressed = pressedKey == key
        
        Button {
            handleKeyPress(key)
        } label: {
            ZStack {
                Circle()
                    .fill(keyBackground(key, isPressed: isPressed))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Circle()
                            .strokeBorder(keyBorder(key, isPressed: isPressed), lineWidth: 1)
                    )
                
                keyContent(key)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressedKey = key }
                .onEnded { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        pressedKey = nil
                    }
                }
        )
        .disabled(key == "confirm" && pin.count < maxDigits)
        .opacity(key == "confirm" && pin.count < maxDigits ? 0.3 : 1.0)
    }
    
    @ViewBuilder
    private func keyContent(_ key: String) -> some View {
        switch key {
        case "delete":
            Image(systemName: "delete.backward")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
        case "confirm":
            Image(systemName: "checkmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
        default:
            Text(key)
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundColor(.white)
        }
    }
    
    private func keyBackground(_ key: String, isPressed: Bool) -> Color {
        switch key {
        case "delete":
            return isPressed ? Color.white.opacity(0.12) : Color.white.opacity(0.04)
        case "confirm":
            return isPressed ? Color.white.opacity(0.25) : Color.white.opacity(0.15)
        default:
            return isPressed ? Color.white.opacity(0.15) : Color.white.opacity(0.06)
        }
    }
    
    private func keyBorder(_ key: String, isPressed: Bool) -> Color {
        switch key {
        case "confirm":
            return isPressed ? Color.white.opacity(0.4) : Color.white.opacity(0.2)
        default:
            return isPressed ? Color.white.opacity(0.2) : Color.white.opacity(0.08)
        }
    }
    
    // MARK: - Key Handler
    private func handleKeyPress(_ key: String) {
        switch key {
        case "delete":
            if !pin.isEmpty {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                    pin.removeLast()
                }
            }
        case "confirm":
            if pin.count >= maxDigits {
                onComplete(pin)
            }
        default:
            if pin.count < maxDigits {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                    pin.append(key)
                }
                // Auto-confirm when all digits entered
                if pin.count == maxDigits {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onComplete(pin)
                    }
                }
            }
        }
        
        // Haptic feedback
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .default
        )
        #endif
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – PIN Entry View
// Full-screen PIN entry with title, subtitle, dot indicators, and keypad.
// Used for passcode setup, change, duress PIN, and unlock.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct HawalaPinEntryView: View {
    let title: String
    let subtitle: String
    let maxDigits: Int
    let icon: String
    let onComplete: (String) -> Void
    var errorMessage: String? = nil
    var onBack: (() -> Void)? = nil
    
    @Binding var pin: String
    @State private var shakeOffset: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Back button (if applicable)
            if let onBack {
                HStack {
                    Button(action: onBack) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }
            
            Spacer()
            
            // Icon
            Image(systemName: icon)
                .font(.system(size: 36, weight: .thin))
                .foregroundColor(.white.opacity(0.6))
                .padding(.bottom, 16)
            
            // Title
            Text(title)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .padding(.bottom, 4)
            
            // Subtitle
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 24)
            
            // Error message
            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                    Text(error)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(Color(red: 1, green: 0.27, blue: 0.23))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // PIN pad
            HawalaPinPad(pin: $pin, maxDigits: maxDigits, onComplete: onComplete)
                .offset(x: shakeOffset)
            
            Spacer()
        }
        .background(Color(red: 0.05, green: 0.05, blue: 0.06))
    }
    
    /// Trigger a shake animation for wrong PIN
    func triggerShake() {
        withAnimation(.default) {
            shakeOffset = -12
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.default) { shakeOffset = 12 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.default) { shakeOffset = -8 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { shakeOffset = 0 }
        }
    }
}
