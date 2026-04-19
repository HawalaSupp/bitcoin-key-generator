import SwiftUI

/// Sheet for generating new seed phrases or displaying an existing saved recovery phrase.
/// When displaying a saved phrase, biometric authentication is required first.
struct SeedPhraseSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// If provided, the sheet displays this saved phrase (read-only, biometric-gated).
    /// If nil, the sheet generates a new phrase for backup/export.
    let savedPhrase: [String]?
    let onCopy: (String) -> Void

    // New-phrase generation state (only used when savedPhrase == nil)
    @State private var selectedCount: MnemonicGenerator.WordCount = .twelve
    @State private var words: [String] = []

    // Biometric gate state (only used when savedPhrase != nil)
    @State private var isAuthenticated = false
    @State private var authError: String?
    @State private var isAuthenticating = false

    // MARK: - Convenience init (generate mode)
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
        NavigationStack {
            Group {
                if !isGenerateMode && !isAuthenticated {
                    biometricGateView
                } else {
                    phraseContentView
                }
            }
            .padding(.top, 20)
            .navigationTitle(isGenerateMode ? "Seed Phrase" : "Recovery Phrase")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(width: 550, height: 600)
        .onAppear {
            if isGenerateMode {
                words = MnemonicGenerator.generate(wordCount: selectedCount)
            }
        }
    }

    // MARK: - Biometric Gate

    private var biometricGateView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("Authenticate to View")
                .font(.title2.bold())

            Text("Your recovery phrase is protected.\nAuthenticate to reveal it.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if let authError {
                Text(authError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 40)
            }

            Button {
                Task { await authenticate() }
            } label: {
                if isAuthenticating {
                    ProgressView()
                        .frame(width: 200)
                } else {
                    Label("Authenticate", systemImage: "faceid")
                        .frame(width: 200)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isAuthenticating)

            Spacer()
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
            withAnimation { isAuthenticated = true }
        case .cancelled:
            break
        case .failed(let message):
            authError = "Authentication failed: \(message)"
        case .notAvailable:
            // Biometric not available — allow access (app lock already required)
            withAnimation { isAuthenticated = true }
        }
    }

    // MARK: - Phrase Content

    private var phraseContentView: some View {
        VStack(spacing: 20) {
            if isGenerateMode {
                Picker("Length", selection: $selectedCount) {
                    ForEach(MnemonicGenerator.WordCount.allCases) { count in
                        Text(count.title).tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedCount) { newValue in
                    words = MnemonicGenerator.generate(wordCount: newValue)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                    Text("Authenticated — your recovery phrase is shown below")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    ForEach(Array(displayWords.enumerated()), id: \.offset) { index, word in
                        HStack {
                            Text(String(format: "%02d", index + 1))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(word)
                                .font(.headline)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.horizontal)
            }

            HStack(spacing: 12) {
                if isGenerateMode {
                    Button {
                        words = MnemonicGenerator.generate(wordCount: selectedCount)
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    let phrase = displayWords.joined(separator: " ")
                    onCopy(phrase)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)

            Text(isGenerateMode
                 ? "Back up this phrase securely. Anyone with access can control your wallets."
                 : "Never share your recovery phrase. Anyone with access can steal your funds.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer(minLength: 0)
        }
    }
}
