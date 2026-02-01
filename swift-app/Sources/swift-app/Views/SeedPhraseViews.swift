import SwiftUI

// MARK: - Seed Phrase Display View

/// View for displaying the seed phrase to the user with security warnings
struct SeedPhraseDisplayView: View {
    let seedPhrase: String
    let onConfirm: () -> Void
    let onDismiss: () -> Void
    
    @State private var isRevealed = false
    @State private var hasCopied = false
    @State private var confirmationStep = 0
    
    private var words: [String] {
        seedPhrase.split(separator: " ").map(String.init)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            ScrollView {
                VStack(spacing: HawalaTheme.Spacing.xl) {
                    // Warning banner
                    warningBanner
                    
                    // Seed phrase grid
                    seedPhraseGrid
                    
                    // Instructions
                    instructionsView
                    
                    // Actions
                    actionButtons
                }
                .padding(HawalaTheme.Spacing.xl)
            }
        }
        .frame(width: 600, height: 700)
        .background(HawalaTheme.Colors.background)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your Recovery Phrase")
                    .font(HawalaTheme.Typography.h2)
                    .foregroundStyle(HawalaTheme.Colors.textPrimary)
                
                Text("\(words.count) words")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundStyle(HawalaTheme.Colors.textSecondary)
            }
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(HawalaTheme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(HawalaTheme.Spacing.lg)
    }
    
    // MARK: - Warning Banner
    
    private var warningBanner: some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(HawalaTheme.Colors.warning)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Write This Down!")
                    .font(HawalaTheme.Typography.captionBold)
                    .foregroundStyle(HawalaTheme.Colors.textPrimary)
                
                Text("This is the ONLY way to recover your wallet. Store it safely offline.")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundStyle(HawalaTheme.Colors.textSecondary)
            }
            
            Spacer()
        }
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.warning.opacity(0.1))
        .cornerRadius(HawalaTheme.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                .stroke(HawalaTheme.Colors.warning.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Seed Phrase Grid
    
    private var seedPhraseGrid: some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            if isRevealed {
                // Show words in a grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: HawalaTheme.Spacing.sm) {
                    ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                        seedWordCell(index: index + 1, word: word)
                    }
                }
            } else {
                // Hidden state
                VStack(spacing: HawalaTheme.Spacing.lg) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(HawalaTheme.Colors.textSecondary)
                    
                    Text("Seed phrase hidden for security")
                        .font(HawalaTheme.Typography.body)
                        .foregroundStyle(HawalaTheme.Colors.textSecondary)
                    
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isRevealed = true
                        }
                    } label: {
                        HStack(spacing: HawalaTheme.Spacing.sm) {
                            Image(systemName: "eye.fill")
                            Text("Reveal Seed Phrase")
                        }
                        .font(HawalaTheme.Typography.captionBold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, HawalaTheme.Spacing.xl)
                        .padding(.vertical, HawalaTheme.Spacing.md)
                        .background(HawalaTheme.Colors.accent)
                        .cornerRadius(HawalaTheme.Radius.md)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, HawalaTheme.Spacing.xxl)
            }
        }
        .padding(HawalaTheme.Spacing.lg)
        .background(HawalaTheme.Colors.backgroundSecondary)
        .cornerRadius(HawalaTheme.Radius.lg)
    }
    
    private func seedWordCell(index: Int, word: String) -> some View {
        HStack(spacing: HawalaTheme.Spacing.sm) {
            Text("\(index).")
                .font(HawalaTheme.Typography.caption)
                .foregroundStyle(HawalaTheme.Colors.textSecondary)
                .frame(width: 24, alignment: .trailing)
            
            Text(word)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(HawalaTheme.Colors.textPrimary)
            
            Spacer()
        }
        .padding(.horizontal, HawalaTheme.Spacing.md)
        .padding(.vertical, HawalaTheme.Spacing.sm)
        .background(HawalaTheme.Colors.background)
        .cornerRadius(HawalaTheme.Radius.sm)
    }
    
    // MARK: - Instructions
    
    private var instructionsView: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            Text("Security Tips")
                .font(HawalaTheme.Typography.h4)
                .foregroundStyle(HawalaTheme.Colors.textPrimary)
            
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                instructionRow(icon: "pencil", text: "Write down these words in order on paper")
                instructionRow(icon: "lock.shield", text: "Store in a safe, secure location")
                instructionRow(icon: "xmark.shield", text: "Never share with anyone or store digitally")
                instructionRow(icon: "arrow.counterclockwise", text: "You'll need these words to recover your wallet")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func instructionRow(icon: String, text: String) -> some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(HawalaTheme.Colors.accent)
                .frame(width: 20)
            
            Text(text)
                .font(HawalaTheme.Typography.body)
                .foregroundStyle(HawalaTheme.Colors.textSecondary)
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            if isRevealed {
                // Copy button
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(seedPhrase, forType: .string)
                    hasCopied = true
                    
                    // Clear clipboard after 60 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                        if NSPasteboard.general.string(forType: .string) == seedPhrase {
                            NSPasteboard.general.clearContents()
                        }
                    }
                } label: {
                    HStack(spacing: HawalaTheme.Spacing.sm) {
                        Image(systemName: hasCopied ? "checkmark" : "doc.on.doc")
                        Text(hasCopied ? "Copied! (Clears in 60s)" : "Copy to Clipboard")
                    }
                    .font(HawalaTheme.Typography.body)
                    .foregroundStyle(HawalaTheme.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, HawalaTheme.Spacing.md)
                    .background(HawalaTheme.Colors.backgroundSecondary)
                    .cornerRadius(HawalaTheme.Radius.md)
                }
                .buttonStyle(.plain)
                
                // Confirm button
                Button {
                    confirmationStep = 1
                } label: {
                    Text("I've Written It Down")
                        .font(HawalaTheme.Typography.captionBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, HawalaTheme.Spacing.md)
                        .background(HawalaTheme.Colors.accent)
                        .cornerRadius(HawalaTheme.Radius.md)
                }
                .buttonStyle(.plain)
            }
        }
        .alert("Confirm Backup", isPresented: .constant(confirmationStep == 1)) {
            Button("Cancel", role: .cancel) {
                confirmationStep = 0
            }
            Button("Yes, I've Backed It Up") {
                confirmationStep = 0
                onConfirm()
            }
        } message: {
            Text("Are you sure you've written down your seed phrase and stored it safely? You cannot view it again without biometric authentication.")
        }
    }
}

// MARK: - Seed Phrase Verification View

/// View for verifying the user has written down their seed phrase
struct SeedPhraseVerificationView: View {
    let seedPhrase: String
    let onVerified: () -> Void
    let onDismiss: () -> Void
    
    @State private var selectedIndices: [Int] = []
    @State private var userAnswers: [String] = ["", "", ""]
    @State private var verificationFailed = false
    
    private var words: [String] {
        seedPhrase.split(separator: " ").map(String.init)
    }
    
    private var randomIndices: [Int] {
        if selectedIndices.isEmpty {
            return Array(0..<words.count).shuffled().prefix(3).sorted()
        }
        return selectedIndices
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Verify Your Backup")
                        .font(HawalaTheme.Typography.h2)
                        .foregroundStyle(HawalaTheme.Colors.textPrimary)
                    
                    Text("Enter the requested words to confirm")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundStyle(HawalaTheme.Colors.textSecondary)
                }
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(HawalaTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(HawalaTheme.Spacing.lg)
            
            Divider()
            
            VStack(spacing: HawalaTheme.Spacing.xl) {
                // Verification fields
                ForEach(0..<3, id: \.self) { i in
                    let wordIndex = randomIndices[i]
                    VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                        Text("Word #\(wordIndex + 1)")
                            .font(HawalaTheme.Typography.caption)
                            .foregroundStyle(HawalaTheme.Colors.textSecondary)
                        
                        TextField("Enter word \(wordIndex + 1)", text: $userAnswers[i])
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                    }
                }
                
                if verificationFailed {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(HawalaTheme.Colors.error)
                        Text("Incorrect words. Please try again.")
                            .foregroundStyle(HawalaTheme.Colors.error)
                    }
                    .font(HawalaTheme.Typography.body)
                }
                
                Spacer()
                
                Button {
                    verifyAnswers()
                } label: {
                    Text("Verify")
                        .font(HawalaTheme.Typography.captionBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, HawalaTheme.Spacing.md)
                        .background(HawalaTheme.Colors.accent)
                        .cornerRadius(HawalaTheme.Radius.md)
                }
                .buttonStyle(.plain)
            }
            .padding(HawalaTheme.Spacing.xl)
        }
        .frame(width: 500, height: 500)
        .background(HawalaTheme.Colors.background)
        .onAppear {
            // Generate random indices on appear
            if selectedIndices.isEmpty {
                selectedIndices = Array(0..<words.count).shuffled().prefix(3).sorted()
            }
        }
    }
    
    private func verifyAnswers() {
        let correct = zip(randomIndices, userAnswers).allSatisfy { index, answer in
            words[index].lowercased() == answer.lowercased().trimmingCharacters(in: .whitespaces)
        }
        
        if correct {
            onVerified()
        } else {
            verificationFailed = true
        }
    }
}

// MARK: - Preview

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview("Display") {
    SeedPhraseDisplayView(
        seedPhrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
        onConfirm: {},
        onDismiss: {}
    )
}
#endif
#endif
#endif

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview("Verify") {
    SeedPhraseVerificationView(
        seedPhrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
        onVerified: {},
        onDismiss: {}
    )
}
#endif
#endif
#endif
