import SwiftUI

/// Sheet for generating new seed phrases or displaying an existing saved recovery phrase.
/// When displaying a saved phrase, biometric authentication is required first.
struct SeedPhraseSheet: View {
    @Environment(\.dismiss) private var dismiss

    let savedPhrase: [String]?
    let onCopy: (String) -> Void

    @State private var selectedCount: MnemonicGenerator.WordCount = .twelve
    @State private var words: [String] = []

    @State private var isAuthenticated = false
    @State private var authError: String?
    @State private var isAuthenticating = false

    init(onCopy: @escaping (String) -> Void) {
        self.savedPhrase = nil
        self.onCopy = onCopy
    }

    init(savedPhrase: [String], onCopy: @escaping (String) -> Void) {
        self.savedPhrase = savedPhrase
        self.onCopy = onCopy
    }

    private var isGenerateMode: Bool { savedPhrase == nil }
    private var displayWords: [String] { savedPhrase ?? words }

    var body: some View {
        HawalaSheetShell(title: isGenerateMode ? "Seed Phrase" : "Recovery Phrase", width: 520, height: 580) {
            if !isGenerateMode && !isAuthenticated {
                biometricGateContent
            } else {
                phraseContent
            }
        }
        .onAppear {
            if isGenerateMode {
                words = MnemonicGenerator.generate(wordCount: selectedCount)
            }
        }
    }

    // MARK: - Biometric Gate

    private var biometricGateContent: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 44, weight: .thin))
                .foregroundColor(.white.opacity(0.25))

            Text("Authenticate to View")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))

            Text("Your recovery phrase is protected.\nAuthenticate to reveal it.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            if let authError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 11))
                    Text(authError)
                        .font(.system(size: 12))
                }
                .foregroundColor(Color(red: 1, green: 0.27, blue: 0.23))
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }

            HawalaActionButton(icon: "faceid", label: isAuthenticating ? "Authenticating..." : "Authenticate", style: .primary) {
                Task { await authenticate() }
            }

            Spacer().frame(height: 40)
        }
    }

    @MainActor
    private func authenticate() async {
        isAuthenticating = true
        authError = nil
        defer { isAuthenticating = false }

        let result = await BiometricAuthHelper.authenticate(
            reason: "Authenticate to view your recovery phrase"
        )
        switch result {
        case .success:
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isAuthenticated = true }
        case .cancelled:
            break
        case .failed(let message):
            authError = "Authentication failed: \(message)"
        case .notAvailable:
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isAuthenticated = true }
        }
    }

    // MARK: - Phrase Content

    private var phraseContent: some View {
        VStack(spacing: 16) {
            if isGenerateMode {
                // Word count picker
                HStack(spacing: 8) {
                    ForEach(MnemonicGenerator.WordCount.allCases) { count in
                        Button(action: {
                            selectedCount = count
                            words = MnemonicGenerator.generate(wordCount: count)
                        }) {
                            Text(count.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(selectedCount == count
                                    ? Color.white.opacity(0.5)
                                    : .white.opacity(0.4))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(selectedCount == count
                                    ? Color.white.opacity(0.15)
                                    : Color.white.opacity(0.04))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(selectedCount == count
                                            ? Color.white.opacity(0.3)
                                            : Color.white.opacity(0.06), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.20, green: 0.84, blue: 0.29))
                    Text("Authenticated — phrase revealed")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.35))
                }
            }

            // Word grid
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                ForEach(Array(displayWords.enumerated()), id: \.offset) { index, word in
                    HStack(spacing: 6) {
                        Text(String(format: "%02d", index + 1))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.25))
                        Text(word)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    )
                }
            }

            // Actions
            HStack(spacing: 12) {
                if isGenerateMode {
                    HawalaActionButton(icon: "arrow.clockwise", label: "Regenerate", style: .secondary) {
                        words = MnemonicGenerator.generate(wordCount: selectedCount)
                    }
                }
                HawalaActionButton(icon: "doc.on.doc", label: "Copy", style: .primary) {
                    let phrase = displayWords.joined(separator: " ")
                    onCopy(phrase)
                }
            }

            // Warning
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11))
                Text(isGenerateMode
                     ? "Back up this phrase securely. Anyone with access can control your wallets."
                     : "Never share your recovery phrase. Anyone with access can steal your funds.")
                    .font(.system(size: 11))
            }
            .foregroundColor(Color(red: 1, green: 0.84, blue: 0.04).opacity(0.6))
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color(red: 1, green: 0.84, blue: 0.04).opacity(0.06))
            .cornerRadius(8)
        }
    }
}
