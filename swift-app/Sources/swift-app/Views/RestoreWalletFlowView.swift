import SwiftUI

// MARK: - Restore Wallet View

/// Full restore wallet flow with validation and progress
struct RestoreWalletFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var walletManager: WalletManager
    
    var onRestoreComplete: ((HDWallet) -> Void)?
    
    @State private var currentStep = 0
    @State private var seedPhrase = ""
    @State private var walletName = "My Wallet"
    @State private var passphrase = ""
    @State private var usePassphrase = false
    @State private var isRestoring = false
    @State private var restoreError: String?
    @State private var restoredWallet: HDWallet?
    
    private var normalizedWords: [String] {
        MnemonicValidator.normalizePhrase(seedPhrase)
    }
    
    private var wordCount: Int {
        normalizedWords.count
    }
    
    private var validationResult: MnemonicValidator.ValidationResult {
        guard wordCount >= 12 else { return .invalidWordCount(wordCount) }
        return MnemonicValidator.validate(seedPhrase)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            stepContent
        }
        .frame(width: 600, height: 650)
        .background(HawalaTheme.Colors.background)
    }
    
    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 0: seedPhraseEntryView
        case 1: passphraseView
        case 2: nameView
        case 3: confirmationView
        case 4: restoringView
        case 5: successView
        default: EmptyView()
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            HStack {
                backButton
                Spacer()
                Text(stepTitle)
                    .font(HawalaTheme.Typography.h3)
                    .foregroundStyle(HawalaTheme.Colors.textPrimary)
                Spacer()
                closeButton
            }
            if currentStep < 4 {
                progressIndicator
            }
        }
        .padding(HawalaTheme.Spacing.lg)
    }
    
    @ViewBuilder
    private var backButton: some View {
        if currentStep > 0 && currentStep < 4 {
            Button {
                withAnimation { currentStep -= 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundStyle(HawalaTheme.Colors.textPrimary)
            }
            .buttonStyle(.plain)
        }
    }
    
    private var closeButton: some View {
        Button(action: { dismiss() }) {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(HawalaTheme.Colors.textSecondary)
        }
        .buttonStyle(.plain)
    }
    
    private var progressIndicator: some View {
        HStack(spacing: HawalaTheme.Spacing.sm) {
            ForEach(0..<4, id: \.self) { step in
                Circle()
                    .fill(step <= currentStep ? HawalaTheme.Colors.accent : HawalaTheme.Colors.backgroundSecondary)
                    .frame(width: 8, height: 8)
            }
        }
    }
    
    private var stepTitle: String {
        switch currentStep {
        case 0: return "Enter Seed Phrase"
        case 1: return "Optional Passphrase"
        case 2: return "Name Your Wallet"
        case 3: return "Confirm Restore"
        case 4: return "Restoring..."
        case 5: return "Wallet Restored!"
        default: return ""
        }
    }
    
    // MARK: - Step 0: Seed Phrase Entry
    
    private var seedPhraseEntryView: some View {
        VStack(spacing: HawalaTheme.Spacing.xl) {
            Text("Enter your 12 or 24-word recovery phrase")
                .font(HawalaTheme.Typography.body)
                .foregroundStyle(HawalaTheme.Colors.textSecondary)
            
            TextEditor(text: $seedPhrase)
                .font(.system(.body, design: .monospaced))
                .frame(height: 150)
                .padding(HawalaTheme.Spacing.md)
                .background(HawalaTheme.Colors.backgroundSecondary)
                .cornerRadius(HawalaTheme.Radius.md)
                .autocorrectionDisabled()
            
            wordCountRow
            
            if wordCount > 0 {
                wordPreviewGrid
            }
            
            Spacer()
            
            continueButton(enabled: validationResult.isValid) {
                withAnimation { currentStep = 1 }
            }
        }
        .padding(HawalaTheme.Spacing.xl)
    }
    
    private var wordCountRow: some View {
        HStack {
            Text("\(wordCount) words")
                .font(HawalaTheme.Typography.caption)
                .foregroundStyle(
                    wordCount == 12 || wordCount == 24
                        ? HawalaTheme.Colors.success
                        : HawalaTheme.Colors.textSecondary
                )
            Spacer()
            if wordCount >= 12 {
                validationIndicator
            }
        }
    }
    
    private var validationIndicator: some View {
        HStack(spacing: HawalaTheme.Spacing.xs) {
            Image(systemName: validationResult.isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
            Text(validationResult.isValid ? "Valid" : (validationResult.errorMessage ?? "Invalid"))
        }
        .font(HawalaTheme.Typography.caption)
        .foregroundStyle(validationResult.isValid ? HawalaTheme.Colors.success : HawalaTheme.Colors.error)
    }
    
    private var wordPreviewGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: HawalaTheme.Spacing.xs) {
            ForEach(Array(normalizedWords.prefix(24).enumerated()), id: \.offset) { index, word in
                wordPreviewCell(index: index, word: word)
            }
        }
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.backgroundSecondary)
        .cornerRadius(HawalaTheme.Radius.md)
    }
    
    private func wordPreviewCell(index: Int, word: String) -> some View {
        HStack(spacing: 4) {
            Text("\(index + 1).")
                .font(.caption2)
                .foregroundStyle(HawalaTheme.Colors.textSecondary)
                .frame(width: 20, alignment: .trailing)
            Text(word)
                .font(.caption)
                .foregroundStyle(
                    BIP39Wordlist.english.contains(word)
                        ? HawalaTheme.Colors.textPrimary
                        : HawalaTheme.Colors.error
                )
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(HawalaTheme.Colors.background)
        .cornerRadius(4)
    }
    
    // MARK: - Step 1: Passphrase
    
    private var passphraseView: some View {
        VStack(spacing: HawalaTheme.Spacing.xl) {
            passphraseHeader
            passphraseToggle
            if usePassphrase {
                passphraseInput
            }
            Spacer()
            continueButton(enabled: true) {
                withAnimation { currentStep = 2 }
            }
        }
        .padding(HawalaTheme.Spacing.xl)
    }
    
    private var passphraseHeader: some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(HawalaTheme.Colors.accent)
            Text("BIP39 Passphrase (Optional)")
                .font(HawalaTheme.Typography.h4)
                .foregroundStyle(HawalaTheme.Colors.textPrimary)
            Text("If you used a passphrase when creating your wallet, enter it below.")
                .font(HawalaTheme.Typography.body)
                .foregroundStyle(HawalaTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var passphraseToggle: some View {
        Toggle("I used a passphrase", isOn: $usePassphrase)
            .toggleStyle(.switch)
            .padding(HawalaTheme.Spacing.md)
            .background(HawalaTheme.Colors.backgroundSecondary)
            .cornerRadius(HawalaTheme.Radius.md)
    }
    
    private var passphraseInput: some View {
        VStack(spacing: HawalaTheme.Spacing.sm) {
            SecureField("Enter your passphrase", text: $passphrase)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: HawalaTheme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(HawalaTheme.Colors.warning)
                Text("Wrong passphrase = different wallet addresses")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundStyle(HawalaTheme.Colors.warning)
            }
        }
    }
    
    // MARK: - Step 2: Name
    
    private var nameView: some View {
        VStack(spacing: HawalaTheme.Spacing.xl) {
            nameHeader
            TextField("Wallet name", text: $walletName)
                .textFieldStyle(.roundedBorder)
            Spacer()
            continueButton(enabled: !walletName.isEmpty) {
                withAnimation { currentStep = 3 }
            }
        }
        .padding(HawalaTheme.Spacing.xl)
    }
    
    private var nameHeader: some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            Image(systemName: "wallet.pass.fill")
                .font(.system(size: 48))
                .foregroundStyle(HawalaTheme.Colors.accent)
            Text("Name Your Wallet")
                .font(HawalaTheme.Typography.h4)
                .foregroundStyle(HawalaTheme.Colors.textPrimary)
            Text("Give your wallet a name to help you identify it")
                .font(HawalaTheme.Typography.body)
                .foregroundStyle(HawalaTheme.Colors.textSecondary)
        }
    }
    
    // MARK: - Step 3: Confirmation
    
    private var confirmationView: some View {
        VStack(spacing: HawalaTheme.Spacing.xl) {
            Text("Review your settings before restoring")
                .font(HawalaTheme.Typography.body)
                .foregroundStyle(HawalaTheme.Colors.textSecondary)
            
            confirmationDetails
            
            if let error = restoreError {
                errorBanner(error)
            }
            
            Spacer()
            
            restoreButton
        }
        .padding(HawalaTheme.Spacing.xl)
    }
    
    private var confirmationDetails: some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            confirmationRow(label: "Wallet Name", value: walletName)
            confirmationRow(label: "Seed Phrase", value: "\(wordCount) words")
            confirmationRow(label: "Passphrase", value: usePassphrase ? "Yes" : "No")
        }
        .padding(HawalaTheme.Spacing.lg)
        .background(HawalaTheme.Colors.backgroundSecondary)
        .cornerRadius(HawalaTheme.Radius.md)
    }
    
    private func confirmationRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(HawalaTheme.Typography.body)
                .foregroundStyle(HawalaTheme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(HawalaTheme.Typography.captionBold)
                .foregroundStyle(HawalaTheme.Colors.textPrimary)
        }
    }
    
    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(HawalaTheme.Colors.error)
            Text(message)
                .foregroundStyle(HawalaTheme.Colors.error)
        }
        .font(HawalaTheme.Typography.body)
        .padding(HawalaTheme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(HawalaTheme.Colors.error.opacity(0.1))
        .cornerRadius(HawalaTheme.Radius.md)
    }
    
    private var restoreButton: some View {
        Button {
            Task { await performRestore() }
        } label: {
            Text("Restore Wallet")
                .font(HawalaTheme.Typography.captionBold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, HawalaTheme.Spacing.md)
                .background(HawalaTheme.Colors.accent)
                .cornerRadius(HawalaTheme.Radius.md)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Step 4: Restoring
    
    private var restoringView: some View {
        VStack(spacing: HawalaTheme.Spacing.xl) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Restoring your wallet...")
                .font(HawalaTheme.Typography.body)
                .foregroundStyle(HawalaTheme.Colors.textSecondary)
            Text("Deriving keys for all chains")
                .font(HawalaTheme.Typography.caption)
                .foregroundStyle(HawalaTheme.Colors.textSecondary)
            Spacer()
        }
        .padding(HawalaTheme.Spacing.xl)
    }
    
    // MARK: - Step 5: Success
    
    private var successView: some View {
        VStack(spacing: HawalaTheme.Spacing.xl) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(HawalaTheme.Colors.success)
            Text("Wallet Restored!")
                .font(HawalaTheme.Typography.h2)
                .foregroundStyle(HawalaTheme.Colors.textPrimary)
            if let wallet = restoredWallet {
                Text(wallet.name)
                    .font(HawalaTheme.Typography.body)
                    .foregroundStyle(HawalaTheme.Colors.textSecondary)
            }
            Spacer()
            doneButton
        }
        .padding(HawalaTheme.Spacing.xl)
    }
    
    private var doneButton: some View {
        Button {
            if let wallet = restoredWallet {
                onRestoreComplete?(wallet)
            }
            dismiss()
        } label: {
            Text("Done")
                .font(HawalaTheme.Typography.captionBold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, HawalaTheme.Spacing.md)
                .background(HawalaTheme.Colors.accent)
                .cornerRadius(HawalaTheme.Radius.md)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Helper Views
    
    private func continueButton(enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Continue")
                .font(HawalaTheme.Typography.captionBold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, HawalaTheme.Spacing.md)
                .background(enabled ? HawalaTheme.Colors.accent : HawalaTheme.Colors.textSecondary)
                .cornerRadius(HawalaTheme.Radius.md)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
    
    // MARK: - Actions
    
    private func performRestore() async {
        withAnimation { currentStep = 4 }
        restoreError = nil
        
        do {
            let wallet = try await walletManager.restoreWallet(
                from: seedPhrase,
                name: walletName,
                passphrase: usePassphrase ? passphrase : ""
            )
            restoredWallet = wallet
            withAnimation { currentStep = 5 }
        } catch {
            restoreError = error.localizedDescription
            withAnimation { currentStep = 3 }
        }
    }
}

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    RestoreWalletFlowView(walletManager: WalletManager.shared)
}
#endif
#endif
#endif
