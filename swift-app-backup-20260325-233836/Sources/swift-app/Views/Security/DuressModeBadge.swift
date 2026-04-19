import SwiftUI

// MARK: - ROADMAP-23 E6: Duress Mode Indicator

/// Subtle sidebar badge indicating the current wallet mode
/// Shows a small visual cue so the user knows if they're in real or decoy mode
/// Intentionally designed to be non-obvious to onlookers
struct DuressModeBadge: View {
    @ObservedObject var duressManager: DuressManager
    var onTap: (() -> Void)?
    
    var body: some View {
        if duressManager.isDuressEnabled {
            Button(action: { onTap?() }) {
                HStack(spacing: 8) {
                    // Subtle mode indicator dot
                    Circle()
                        .fill(modeColor)
                        .frame(width: 8, height: 8)
                    
                    // Ambiguous label — doesn't reveal duress feature to observers
                    Text(modeLabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if duressManager.isInDecoyMode {
                        Image(systemName: "shield.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(modeColor.opacity(0.08))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .accessibilityLabel(duressManager.isInDecoyMode ? "Secondary mode active" : "Primary mode active")
            .accessibilityHint("Double-tap to view security audit log")
        }
    }
    
    /// Green for real mode, subtle gray-blue for decoy — intentionally vague
    private var modeColor: Color {
        duressManager.isInDecoyMode ? Color.blue.opacity(0.5) : Color.green
    }
    
    /// Labels are intentionally non-descriptive
    private var modeLabel: String {
        duressManager.isInDecoyMode ? "Secondary" : "Primary"
    }
}

// MARK: - Panic Wipe Gesture Overlay

/// Hidden gesture area for panic wipe — ROADMAP-23 E9
/// Activated by triple-tapping a specific area (configurable)
struct PanicWipeGesture: ViewModifier {
    @ObservedObject var duressManager: DuressManager
    @State private var showPanicConfirmation = false
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                // Invisible tap target in bottom-right corner
                Color.clear
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 5) {
                        // 5 taps = panic wipe trigger (hard to trigger accidentally)
                        if duressManager.isInDecoyMode {
                            showPanicConfirmation = true
                        }
                    }
                    .accessibilityHidden(true)
            }
            .alert("⚠️ Emergency Wipe", isPresented: $showPanicConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("DESTROY WALLET", role: .destructive) {
                    duressManager.panicWipeRealWallet()
                }
            } message: {
                Text("This will permanently and irreversibly destroy the primary wallet data. This action CANNOT be undone.\n\nAre you absolutely sure?")
            }
    }
}

extension View {
    /// Attach the hidden panic wipe gesture — ROADMAP-23 E9
    func panicWipeGesture(duressManager: DuressManager) -> some View {
        modifier(PanicWipeGesture(duressManager: duressManager))
    }
}
