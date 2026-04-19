import SwiftUI

// MARK: - Wallet Picker View

/// A dropdown picker for selecting the active wallet
struct WalletPicker: View {
    @ObservedObject var repository: WalletRepository
    @State private var isExpanded = false
    @State private var showCreateWallet = false
    @State private var showImportWallet = false
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Current wallet button
            currentWalletButton
            
            // Expanded wallet list
            if isExpanded {
                walletListDropdown
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
        .sheet(isPresented: $showCreateWallet) {
            CreateWalletSheet(repository: repository)
        }
        .sheet(isPresented: $showImportWallet) {
            ImportWalletSheet(repository: repository)
        }
    }
    
    // MARK: - Current Wallet Button
    
    private var currentWalletButton: some View {
        Button {
            withAnimation {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                // Wallet color indicator
                if let wallet = repository.activeWallet {
                    walletColorDot(for: wallet)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(repository.activeWallet?.name ?? "No Wallet")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if let wallet = repository.activeWallet {
                        Text(wallet.subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(cardBackground)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Wallet List Dropdown
    
    private var walletListDropdown: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(repository.wallets) { wallet in
                        walletRow(wallet)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 200)
            
            Divider()
            
            // Action buttons
            HStack(spacing: 16) {
                Button {
                    showCreateWallet = true
                    isExpanded = false
                } label: {
                    Label("Create New", systemImage: "plus.circle.fill")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
                
                Spacer()
                
                Button {
                    showImportWallet = true
                    isExpanded = false
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundColor(.green)
            }
            .padding(12)
        }
        .background(cardBackground)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
    }
    
    // MARK: - Wallet Row
    
    private func walletRow(_ wallet: WalletProfile) -> some View {
        let isActive = wallet.id == repository.activeWalletId
        
        return Button {
            repository.setActiveWallet(wallet.id)
            withAnimation {
                isExpanded = false
            }
        } label: {
            HStack(spacing: 12) {
                walletColorDot(for: wallet)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(wallet.name)
                        .font(.subheadline.weight(isActive ? .semibold : .regular))
                        .foregroundColor(.primary)
                    
                    Text(wallet.subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isActive ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Wallet Color Dot
    
    private func walletColorDot(for wallet: WalletProfile) -> some View {
        ZStack {
            Circle()
                .fill(walletColor(for: wallet).opacity(0.3))
                .frame(width: 36, height: 36)
            
            Image(systemName: wallet.icon)
                .font(.system(size: 16))
                .foregroundColor(walletColor(for: wallet))
        }
    }
    
    private func walletColor(for wallet: WalletProfile) -> Color {
        switch wallet.colorName {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "pink": return .pink
        case "cyan": return .cyan
        case "yellow": return .yellow
        case "red": return .red
        case "indigo": return .indigo
        case "mint": return .mint
        default: return .blue
        }
    }
}

// MARK: - Create Wallet Sheet

struct CreateWalletSheet: View {
    @ObservedObject var repository: WalletRepository
    @Environment(\.dismiss) private var dismiss
    
    @State private var walletName = ""
    @State private var usePassphrase = false
    @State private var passphrase = ""
    @State private var confirmPassphrase = ""
    @State private var generatedPhrase: [String] = []
    @State private var showPhrase = false
    @State private var phraseConfirmed = false
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var selectedColorIndex = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Create New Wallet")
                    .font(.title2.bold())
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Wallet name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Wallet Name")
                            .font(.subheadline.bold())
                        
                        TextField("My Wallet", text: $walletName)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(8)
                    }
                    
                    // Color picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Wallet Color")
                            .font(.subheadline.bold())
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                            ForEach(0..<WalletProfile.availableColors.count, id: \.self) { index in
                                colorOption(index: index)
                            }
                        }
                    }
                    
                    // Passphrase option
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $usePassphrase) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Add Passphrase (25th word)")
                                    .font(.subheadline.bold())
                                Text("Extra security layer for advanced users")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        
                        if usePassphrase {
                            SecureField("Passphrase", text: $passphrase)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(8)
                            
                            SecureField("Confirm Passphrase", text: $confirmPassphrase)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(8)
                            
                            if !passphrase.isEmpty && passphrase != confirmPassphrase {
                                Text("Passphrases don't match")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Seed phrase section
                    if !showPhrase {
                        Button {
                            generateSeedPhrase()
                        } label: {
                            Label("Generate Seed Phrase", systemImage: "key.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    } else {
                        seedPhraseDisplay
                    }
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding(20)
            }
            
            Divider()
            
            // Action buttons
            HStack(spacing: 16) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                
                Spacer()
                
                Button {
                    createWallet()
                } label: {
                    if isCreating {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text("Create Wallet")
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(canCreate ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(8)
                .disabled(!canCreate)
            }
            .padding(20)
        }
        .frame(width: 480, height: 640)
    }
    
    private var canCreate: Bool {
        !walletName.isEmpty &&
        phraseConfirmed &&
        (!usePassphrase || (passphrase == confirmPassphrase && !passphrase.isEmpty))
    }
    
    private func colorOption(index: Int) -> some View {
        let colorName = WalletProfile.availableColors[index]
        let color = colorFromName(colorName)
        
        return Button {
            selectedColorIndex = index
        } label: {
            Circle()
                .fill(color)
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .stroke(selectedColorIndex == index ? Color.white : Color.clear, lineWidth: 3)
                )
                .overlay(
                    selectedColorIndex == index ?
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                    : nil
                )
        }
        .buttonStyle(.plain)
    }
    
    private func colorFromName(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "pink": return .pink
        case "cyan": return .cyan
        case "yellow": return .yellow
        case "red": return .red
        case "indigo": return .indigo
        case "mint": return .mint
        default: return .blue
        }
    }
    
    private var seedPhraseDisplay: some View {
        VStack(spacing: 16) {
            Text("Your Recovery Phrase")
                .font(.headline)
            
            Text("Write down these 12 words in order. Never share them with anyone!")
                .font(.caption)
                .foregroundColor(.orange)
                .multilineTextAlignment(.center)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Array(generatedPhrase.enumerated()), id: \.offset) { index, word in
                    HStack(spacing: 4) {
                        Text("\(index + 1).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 20, alignment: .trailing)
                        Text(word)
                            .font(.system(.body, design: .monospaced))
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(6)
                }
            }
            
            Toggle(isOn: $phraseConfirmed) {
                Text("I have written down my recovery phrase")
                    .font(.subheadline)
            }
            .toggleStyle(.checkbox)
        }
        .padding(16)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func generateSeedPhrase() {
        // Demo: generate placeholder words
        // In production, use proper BIP39 word generation
        let bip39Sample = [
            "abandon", "ability", "able", "about", "above", "absent",
            "absorb", "abstract", "absurd", "abuse", "access", "accident"
        ]
        generatedPhrase = bip39Sample
        showPhrase = true
    }
    
    private func createWallet() {
        isCreating = true
        errorMessage = nil
        
        Task {
            do {
                let _ = try await repository.createWallet(
                    name: walletName,
                    seedPhrase: generatedPhrase,
                    passphrase: usePassphrase ? passphrase : nil
                )
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isCreating = false
                }
            }
        }
    }
}

// MARK: - Import Wallet Sheet

struct ImportWalletSheet: View {
    @ObservedObject var repository: WalletRepository
    @Environment(\.dismiss) private var dismiss
    
    @State private var walletName = ""
    @State private var seedPhraseText = ""
    @State private var passphrase = ""
    @State private var importType: ImportType = .seedPhrase
    @State private var watchOnlyAddress = ""
    @State private var selectedChain = "bitcoin"
    @State private var isImporting = false
    @State private var errorMessage: String?
    
    enum ImportType: String, CaseIterable {
        case seedPhrase = "Seed Phrase"
        case watchOnly = "Watch-Only Address"
    }
    
    let chains = ["bitcoin", "ethereum", "litecoin", "solana", "xrp", "bnb"]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Import Wallet")
                    .font(.title2.bold())
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Import type picker
                    Picker("Import Type", selection: $importType) {
                        ForEach(ImportType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    // Wallet name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Wallet Name")
                            .font(.subheadline.bold())
                        
                        TextField("Imported Wallet", text: $walletName)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(8)
                    }
                    
                    if importType == .seedPhrase {
                        seedPhraseImportView
                    } else {
                        watchOnlyImportView
                    }
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding(20)
            }
            
            Divider()
            
            // Action buttons
            HStack(spacing: 16) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                
                Spacer()
                
                Button {
                    importWallet()
                } label: {
                    if isImporting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text("Import")
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(canImport ? Color.green : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(8)
                .disabled(!canImport)
            }
            .padding(20)
        }
        .frame(width: 480, height: 560)
    }
    
    private var canImport: Bool {
        if walletName.isEmpty { return false }
        
        switch importType {
        case .seedPhrase:
            let words = seedPhraseText.split(separator: " ").map(String.init)
            return [12, 15, 18, 21, 24].contains(words.count)
        case .watchOnly:
            return !watchOnlyAddress.isEmpty
        }
    }
    
    private var seedPhraseImportView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recovery Phrase")
                    .font(.subheadline.bold())
                
                TextEditor(text: $seedPhraseText)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(height: 100)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
                
                let wordCount = seedPhraseText.split(separator: " ").count
                Text("\(wordCount) words")
                    .font(.caption)
                    .foregroundColor(wordCount == 12 || wordCount == 24 ? .green : .secondary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Passphrase (optional)")
                    .font(.subheadline.bold())
                
                SecureField("Enter if wallet was created with passphrase", text: $passphrase)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
            }
            
            // Warning
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Never enter your seed phrase on suspicious websites or apps")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            .padding(12)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    private var watchOnlyImportView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Chain selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Blockchain")
                    .font(.subheadline.bold())
                
                Picker("Chain", selection: $selectedChain) {
                    ForEach(chains, id: \.self) { chain in
                        Text(chain.capitalized).tag(chain)
                    }
                }
                .pickerStyle(.menu)
            }
            
            // Address input
            VStack(alignment: .leading, spacing: 8) {
                Text("Address")
                    .font(.subheadline.bold())
                
                TextField("Enter address to watch", text: $watchOnlyAddress)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
            }
            
            // Info
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                Text("Watch-only wallets let you monitor balances without access to private keys")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    private func importWallet() {
        isImporting = true
        errorMessage = nil
        
        Task {
            do {
                switch importType {
                case .seedPhrase:
                    let words = seedPhraseText.split(separator: " ").map(String.init)
                    let _ = try await repository.createWallet(
                        name: walletName,
                        seedPhrase: words,
                        passphrase: passphrase.isEmpty ? nil : passphrase
                    )
                case .watchOnly:
                    let address = WatchOnlyAddress(
                        chain: selectedChain,
                        address: watchOnlyAddress,
                        label: nil
                    )
                    let _ = try repository.importWatchOnlyWallet(
                        name: walletName,
                        addresses: [address]
                    )
                }
                
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isImporting = false
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct WalletPicker_Previews: PreviewProvider {
    static var previews: some View {
        WalletPicker(repository: WalletRepository.shared)
            .padding()
            .frame(width: 300)
            .preferredColorScheme(.dark)
    }
}
#endif
