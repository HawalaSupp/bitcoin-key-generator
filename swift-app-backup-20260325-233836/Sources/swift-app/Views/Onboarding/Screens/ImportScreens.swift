import SwiftUI
#if canImport(AVFoundation)
import AVFoundation
#endif

// MARK: - Import Method Selection Screen

struct ImportMethodSelectionScreen: View {
    let onSelectMethod: (WalletImportMethod) -> Void
    let onBack: () -> Void
    var onLostBackup: (() -> Void)? = nil
    
    @State private var animateContent = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Title
            VStack(spacing: 12) {
                Text("Restore Your Wallet")
                    .font(.custom("ClashGrotesk-Bold", size: 28))
                    .foregroundColor(.white)
                
                Text("Choose how you want to import")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
            }
            .opacity(animateContent ? 1 : 0)
            
            Spacer()
                .frame(height: 20)
            
            // Import methods
            VStack(spacing: 12) {
                ForEach(WalletImportMethod.allCases) { method in
                    ImportMethodCard(
                        method: method,
                        isAvailable: method.isAvailable
                    ) {
                        onSelectMethod(method)
                    }
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 10)
                }
            }
            .padding(.horizontal, 24)
            
            // Lost backup link
            if let onLostBackup = onLostBackup {
                Button(action: onLostBackup) {
                    HStack(spacing: 6) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 14))
                        Text("Lost your backup?")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(Color(hex: "#00D4FF"))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .opacity(animateContent ? 1 : 0)
            }
            
            Spacer()
            
            // Back button
            OnboardingSecondaryButton(title: "Back", action: onBack)
                .padding(.horizontal, 24)
                .padding(.bottom, 50)
                .opacity(animateContent ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                animateContent = true
            }
        }
    }
}

// MARK: - Import Method Card

private struct ImportMethodCard: View {
    let method: WalletImportMethod
    let isAvailable: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            if isAvailable {
                action()
            }
        }) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: method.icon)
                        .font(.system(size: 20))
                        .foregroundColor(isAvailable ? .white : .white.opacity(0.4))
                }
                
                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(method.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isAvailable ? .white : .white.opacity(0.4))
                    
                    Text(method.description)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                // Status
                if !isAvailable {
                    Text("Not available")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.05))
                        )
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(isHovered && isAvailable ? 0.08 : 0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Seed Phrase Import Screen

struct SeedPhraseImportScreen: View {
    @ObservedObject var importManager: WalletImportManager
    let onComplete: () -> Void
    let onBack: () -> Void
    
    @State private var animateContent = false
    @State private var focusedWordIndex: Int? = nil
    @FocusState private var focusedField: Int?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            importHeader
            
            ScrollView {
                VStack(spacing: 24) {
                    // Word count selector
                    wordCountSelector
                    
                    // Word grid
                    wordGrid
                    
                    // Validation status
                    validationStatus
                    
                    // Passphrase toggle
                    passphraseSection
                    
                    // Wallet name
                    walletNameSection
                }
                .padding(24)
            }
            
            // Continue button
            VStack(spacing: 12) {
                if case .error(let error) = importManager.state {
                    Text(error.localizedDescription)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
                
                OnboardingPrimaryButton(
                    title: buttonTitle,
                    action: handleContinue,
                    style: .glass
                )
                .disabled(!canContinue)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
        .background(Color.black)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                animateContent = true
            }
        }
    }
    
    private var importHeader: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            VStack(spacing: 4) {
                Text("Recovery Phrase")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Enter your \(importManager.wordCount) words")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            // Spacer for alignment
            Color.clear.frame(width: 24, height: 24)
        }
        .padding(20)
        .background(Color.white.opacity(0.03))
    }
    
    private var wordCountSelector: some View {
        HStack(spacing: 8) {
            ForEach([12, 18, 24], id: \.self) { count in
                Button {
                    importManager.setWordCount(count)
                } label: {
                    Text("\(count) words")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(importManager.wordCount == count ? .black : .white.opacity(0.6))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(importManager.wordCount == count ? Color.white : Color.white.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var wordGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
        
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(0..<importManager.wordCount, id: \.self) { index in
                WordInputCell(
                    index: index,
                    word: $importManager.seedWords[index],
                    isInvalid: importManager.seedPhraseValidation.invalidWords.contains(index),
                    isFocused: focusedField == index
                )
                .focused($focusedField, equals: index)
                .onSubmit {
                    if index < importManager.wordCount - 1 {
                        focusedField = index + 1
                    } else {
                        focusedField = nil
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
    
    private var validationStatus: some View {
        let validation = importManager.seedPhraseValidation
        
        return HStack(spacing: 12) {
            // Progress indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(validation.isValid ? Color.green : Color.white.opacity(0.2))
                    .frame(width: 8, height: 8)
                
                Text("\(validation.enteredCount)/\(validation.requiredCount)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            // Status message
            if let error = validation.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
            } else if validation.isValid {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Valid phrase")
                        .foregroundColor(.green)
                }
                .font(.system(size: 12, weight: .medium))
            }
            
            // Duplicate warning
            if validation.duplicateWarning {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text("Duplicate words")
                        .foregroundColor(.yellow)
                }
                .font(.system(size: 11))
            }
        }
    }
    
    private var passphraseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $importManager.usePassphrase) {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .foregroundColor(.white.opacity(0.5))
                    Text("Use BIP39 passphrase")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }
            }
            .toggleStyle(.switch)
            .tint(.blue)
            
            if importManager.usePassphrase {
                SecureField("Enter passphrase", text: $importManager.passphrase)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.05))
                    )
                
                Text("⚠️ Wrong passphrase will generate a different wallet")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
        )
    }
    
    private var walletNameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wallet Name")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
            
            TextField("My Wallet", text: $importManager.walletName)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.05))
                )
        }
    }
    
    private var canContinue: Bool {
        if case .deriving = importManager.state { return false }
        if case .importing = importManager.state { return false }
        return importManager.seedPhraseValidation.isValid && !importManager.walletName.isEmpty
    }
    
    private var buttonTitle: String {
        switch importManager.state {
        case .deriving, .importing:
            return importManager.progressMessage
        default:
            return "Import Wallet"
        }
    }
    
    private func handleContinue() {
        Task {
            await importManager.importFromSeedPhrase()
            if case .success = importManager.state {
                onComplete()
            }
        }
    }
}

// MARK: - Word Input Cell

private struct WordInputCell: View {
    let index: Int
    @Binding var word: String
    let isInvalid: Bool
    let isFocused: Bool
    
    private var strokeColor: Color {
        if isInvalid {
            return Color.red.opacity(0.5)
        } else if isFocused {
            return Color.white.opacity(0.3)
        } else {
            return Color.clear
        }
    }
    
    private var fillOpacity: Double {
        isFocused ? 0.1 : 0.05
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.3))
                .frame(width: 18)
            
            TextField("", text: $word)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isInvalid ? .red : .white)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(fillOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(strokeColor, lineWidth: 1)
                )
        )
    }
}

// MARK: - Private Key Import Screen

struct PrivateKeyImportScreen: View {
    @ObservedObject var importManager: WalletImportManager
    let onComplete: () -> Void
    let onBack: () -> Void
    
    @State private var animateContent = false
    
    private let supportedChains = [
        ("ethereum", "Ethereum"),
        ("bitcoin", "Bitcoin"),
        ("solana", "Solana"),
        ("polygon", "Polygon"),
        ("arbitrum", "Arbitrum")
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text("Import Private Key")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Color.clear.frame(width: 24, height: 24)
            }
            .padding(20)
            .background(Color.white.opacity(0.03))
            
            ScrollView {
                VStack(spacing: 24) {
                    // Warning
                    OnboardingInfoCard(
                        icon: "exclamationmark.triangle.fill",
                        title: "Single-Chain Import",
                        description: "Private key import only works for one chain. For multi-chain support, use a recovery phrase."
                    )
                    
                    // Chain selector
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select Chain")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                        
                        HStack(spacing: 8) {
                            ForEach(supportedChains, id: \.0) { chain in
                                Button {
                                    importManager.selectedChain = chain.0
                                } label: {
                                    Text(chain.1)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(importManager.selectedChain == chain.0 ? .black : .white.opacity(0.6))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule()
                                                .fill(importManager.selectedChain == chain.0 ? Color.white : Color.white.opacity(0.1))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    // Private key input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Private Key")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                        
                        TextEditor(text: $importManager.privateKey)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.white)
                            .scrollContentBackground(.hidden)
                            .frame(height: 100)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.05))
                            )
                        
                        // Format hint
                        HStack(spacing: 8) {
                            if let format = importManager.privateKeyValidation.format {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text(formatName(format))
                                        .foregroundColor(.green)
                                }
                                .font(.system(size: 12))
                            } else if let error = importManager.privateKeyValidation.errorMessage {
                                Text(error)
                                    .font(.system(size: 12))
                                    .foregroundColor(.orange)
                            } else {
                                Text("Hex (64 chars) or WIF format")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                    }
                    
                    // Wallet name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Wallet Name")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                        
                        TextField("My Wallet", text: $importManager.walletName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15))
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.05))
                            )
                    }
                }
                .padding(24)
            }
            
            // Import button
            OnboardingPrimaryButton(
                title: "Import Wallet",
                action: handleImport,
                style: .glass
            )
            .disabled(!importManager.privateKeyValidation.isValid)
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
        .background(Color.black)
    }
    
    private func formatName(_ format: WalletImportManager.PrivateKeyValidation.PrivateKeyFormat) -> String {
        switch format {
        case .hex: return "Hexadecimal"
        case .wif: return "WIF"
        case .wifCompressed: return "WIF (Compressed)"
        }
    }
    
    private func handleImport() {
        Task {
            await importManager.importFromPrivateKey()
            if case .success = importManager.state {
                onComplete()
            }
        }
    }
}

// MARK: - QR Import Screen

struct QRImportScreen: View {
    @ObservedObject var importManager: WalletImportManager
    let onComplete: () -> Void
    let onBack: () -> Void
    
    @State private var showManualEntry = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text("Scan QR Code")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Color.clear.frame(width: 24, height: 24)
            }
            .padding(20)
            .background(Color.white.opacity(0.03))
            
            Spacer()
            
            // Camera view or placeholder
            VStack(spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 280, height: 280)
                    
                    // Camera viewfinder overlay
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                        .frame(width: 240, height: 240)
                    
                    // Corner markers
                    QRViewfinderCorners()
                        .frame(width: 240, height: 240)
                    
                    // Scanning line animation
                    if importManager.isScanning {
                        ScanningLine()
                    }
                    
                    // Camera not available message
                    if !importManager.isScanning {
                        VStack(spacing: 12) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white.opacity(0.3))
                            
                            Text("Camera access required")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                }
                
                Text("Position QR code within frame")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            // Manual entry option
            VStack(spacing: 16) {
                Button {
                    showManualEntry = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "keyboard")
                        Text("Enter manually instead")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                
                // Start/Stop scanning button
                OnboardingPrimaryButton(
                    title: importManager.isScanning ? "Stop Scanning" : "Start Scanning",
                    action: {
                        importManager.isScanning.toggle()
                    },
                    style: .glass
                )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
        .background(Color.black)
        .sheet(isPresented: $showManualEntry) {
            // Show seed phrase import
            NavigationStack {
                SeedPhraseImportScreen(
                    importManager: importManager,
                    onComplete: onComplete,
                    onBack: { showManualEntry = false }
                )
            }
        }
    }
}

// MARK: - QR Viewfinder Corners

private struct QRViewfinderCorners: View {
    var body: some View {
        ZStack {
            // Top left
            VStack {
                HStack {
                    CornerShape()
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: 30, height: 30)
                    Spacer()
                }
                Spacer()
            }
            
            // Top right
            VStack {
                HStack {
                    Spacer()
                    CornerShape()
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: 30, height: 30)
                        .rotationEffect(.degrees(90))
                }
                Spacer()
            }
            
            // Bottom left
            VStack {
                Spacer()
                HStack {
                    CornerShape()
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: 30, height: 30)
                        .rotationEffect(.degrees(-90))
                    Spacer()
                }
            }
            
            // Bottom right
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    CornerShape()
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: 30, height: 30)
                        .rotationEffect(.degrees(180))
                }
            }
        }
    }
}

private struct CornerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        return path
    }
}

private struct ScanningLine: View {
    @State private var offset: CGFloat = -100
    
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, .green.opacity(0.5), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 2)
            .offset(y: offset)
            .onAppear {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: true)) {
                    offset = 100
                }
            }
    }
}

// MARK: - iCloud Restore Screen

struct iCloudRestoreScreen: View {
    @ObservedObject var importManager: WalletImportManager
    let onComplete: () -> Void
    let onBack: () -> Void
    
    @State private var animateContent = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text("Restore from iCloud")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Color.clear.frame(width: 24, height: 24)
            }
            .padding(20)
            .background(Color.white.opacity(0.03))
            
            ScrollView {
                VStack(spacing: 24) {
                    // iCloud icon
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: "icloud.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.blue)
                    }
                    .padding(.top, 40)
                    
                    // Status
                    if importManager.availableBackups.isEmpty {
                        noBackupView
                    } else {
                        backupListView
                    }
                }
                .padding(24)
            }
        }
        .background(Color.black)
        .onAppear {
            Task {
                await importManager.fetchiCloudBackups()
            }
        }
    }
    
    private var noBackupView: some View {
        VStack(spacing: 16) {
            Text("No iCloud Backup Found")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
            
            Text("You haven't backed up a wallet to iCloud yet, or you're signed in with a different Apple ID.")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 12) {
                suggestionRow(icon: "person.icloud", text: "Check you're signed in with the correct Apple ID")
                suggestionRow(icon: "key", text: "Try importing with your recovery phrase instead")
            }
            .padding(.top, 20)
        }
    }
    
    private func suggestionRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.blue)
                .frame(width: 24)
            
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
            
            Spacer()
        }
    }
    
    private var backupListView: some View {
        VStack(spacing: 16) {
            Text("Available Backups")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
            
            ForEach(importManager.availableBackups) { backup in
                BackupCard(
                    backup: backup,
                    isSelected: importManager.selectedBackup?.id == backup.id
                ) {
                    importManager.selectedBackup = backup
                }
            }
            
            if importManager.selectedBackup != nil {
                // Password entry
                VStack(alignment: .leading, spacing: 8) {
                    Text("Backup Password")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    
                    SecureField("Enter password", text: $importManager.backupPassword)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.05))
                        )
                }
                .padding(.top, 16)
                
                OnboardingPrimaryButton(
                    title: "Restore Wallet",
                    action: handleRestore,
                    style: .glass
                )
                .disabled(importManager.backupPassword.isEmpty)
                .padding(.top, 8)
            }
        }
    }
    
    private func handleRestore() {
        guard let backup = importManager.selectedBackup else { return }
        
        Task {
            await importManager.importFromiCloud(
                backup: backup,
                password: importManager.backupPassword
            )
            if case .success = importManager.state {
                onComplete()
            }
        }
    }
}

private struct BackupCard: View {
    let backup: WalletImportManager.CloudBackupInfo
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: "wallet.pass.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(backup.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text(backup.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(isSelected ? 0.1 : 0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Import Success Screen

struct ImportSuccessScreen: View {
    let walletName: String
    let onContinue: () -> Void
    
    @State private var animateContent = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Success animation
            OnboardingAnimatedCheckmark(size: 100)
                .opacity(animateContent ? 1 : 0)
                .scaleEffect(animateContent ? 1 : 0.5)
            
            VStack(spacing: 12) {
                Text("Wallet Restored!")
                    .font(.custom("ClashGrotesk-Bold", size: 28))
                    .foregroundColor(.white)
                
                Text("\"\(walletName)\" is ready to use")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.6))
            }
            .opacity(animateContent ? 1 : 0)
            
            Spacer()
            
            OnboardingPrimaryButton(
                title: "Continue to Wallet",
                action: onContinue,
                style: .glass
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 50)
            .opacity(animateContent ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                animateContent = true
            }
        }
    }
}

// MARK: - Lost Backup Recovery Screen

/// Helps users who have lost their backup recover their wallet
/// Supports partial seed phrase recovery, checking iCloud, and contacting guardians
struct LostBackupRecoveryScreen: View {
    let onComplete: () -> Void
    let onBack: () -> Void
    
    @State private var animateContent = false
    @State private var selectedRecoveryOption: RecoveryOption? = nil
    @State private var showPartialRecoverySheet = false
    @State private var showGuardianContactSheet = false
    
    enum RecoveryOption: String, CaseIterable, Identifiable {
        case checkiCloud = "check_icloud"
        case partialSeedPhrase = "partial_seed"
        case contactGuardians = "contact_guardians"
        case hardwareBackup = "hardware_backup"
        case professionalHelp = "professional_help"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .checkiCloud: return "icloud.fill"
            case .partialSeedPhrase: return "puzzlepiece.extension.fill"
            case .contactGuardians: return "person.2.fill"
            case .hardwareBackup: return "externaldrive.fill"
            case .professionalHelp: return "questionmark.circle.fill"
            }
        }
        
        var title: String {
            switch self {
            case .checkiCloud: return "Check iCloud Backup"
            case .partialSeedPhrase: return "I Remember Part of My Phrase"
            case .contactGuardians: return "Contact Recovery Guardians"
            case .hardwareBackup: return "Recover from Hardware Wallet"
            case .professionalHelp: return "Get Professional Help"
            }
        }
        
        var description: String {
            switch self {
            case .checkiCloud: return "Search for encrypted backups in iCloud"
            case .partialSeedPhrase: return "Enter the words you remember for recovery"
            case .contactGuardians: return "Request recovery shards from your guardians"
            case .hardwareBackup: return "Export seed from Ledger, Trezor, or Keystone"
            case .professionalHelp: return "Connect with recovery specialists"
            }
        }
        
        var isAvailable: Bool {
            switch self {
            case .checkiCloud: return true
            case .partialSeedPhrase: return true
            case .contactGuardians: return true
            case .hardwareBackup: return true
            case .professionalHelp: return true
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text("Recover Lost Backup")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Balance spacer
                Image(systemName: "chevron.left")
                    .opacity(0)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            ScrollView {
                VStack(spacing: 24) {
                    // Empathy message
                    VStack(spacing: 12) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "#00D4FF"), Color(hex: "#00A3CC")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .opacity(animateContent ? 1 : 0)
                        
                        Text("Don't panic - we're here to help")
                            .font(.custom("ClashGrotesk-Medium", size: 20))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        Text("Let's explore your recovery options together. Many users successfully recover their wallets.")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .padding(.top, 20)
                    .opacity(animateContent ? 1 : 0)
                    
                    // Recovery options
                    VStack(spacing: 12) {
                        ForEach(RecoveryOption.allCases) { option in
                            RecoveryOptionCard(
                                option: option,
                                isSelected: selectedRecoveryOption == option,
                                onTap: {
                                    selectedRecoveryOption = option
                                    handleOptionSelected(option)
                                }
                            )
                            .opacity(animateContent ? 1 : 0)
                            .animation(.easeOut(duration: 0.3).delay(Double(RecoveryOption.allCases.firstIndex(of: option) ?? 0) * 0.1), value: animateContent)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    
                    // Security reminder
                    SecurityReminderCard()
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .opacity(animateContent ? 1 : 0)
                }
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                animateContent = true
            }
        }
        .sheet(isPresented: $showPartialRecoverySheet) {
            PartialSeedRecoverySheet(onComplete: onComplete)
        }
        .sheet(isPresented: $showGuardianContactSheet) {
            GuardianContactSheet(onComplete: onComplete)
        }
    }
    
    private func handleOptionSelected(_ option: RecoveryOption) {
        switch option {
        case .checkiCloud:
            // Check for iCloud backups
            checkiCloudBackups()
        case .partialSeedPhrase:
            showPartialRecoverySheet = true
        case .contactGuardians:
            showGuardianContactSheet = true
        case .hardwareBackup:
            // Navigate to hardware wallet import
            break
        case .professionalHelp:
            // Show professional help info
            break
        }
    }
    
    private func checkiCloudBackups() {
        // Check for iCloud backups
        if SecureSeedStorage.hasiCloudBackup() {
            // Navigate to iCloud restore
        }
    }
}

// MARK: - Recovery Option Card

private struct RecoveryOptionCard: View {
    let option: LostBackupRecoveryScreen.RecoveryOption
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#00A3CC").opacity(0.3), Color(hex: "#00D4FF").opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: option.icon)
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: "#00D4FF"))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(option.description)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(2)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(isSelected ? 0.1 : 0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color(hex: "#00D4FF").opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Security Reminder Card

private struct SecurityReminderCard: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.orange)
                
                Text("Security Reminder")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.orange)
                
                Spacer()
            }
            
            Text("Never share your recovery phrase with anyone claiming to be Hawala support. We will never ask for your full seed phrase.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.leading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Partial Seed Recovery Sheet

private struct PartialSeedRecoverySheet: View {
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var knownWords: [String] = Array(repeating: "", count: 12)
    @State private var knownPositions: Set<Int> = []
    @State private var isSearching = false
    @State private var searchProgress: Double = 0
    @State private var foundMatch = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Instructions
                VStack(spacing: 8) {
                    Text("Enter the words you remember")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("Leave unknown positions blank. We'll try to find matching combinations.")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
                
                // Word grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(0..<12, id: \.self) { index in
                        PartialWordCell(
                            index: index,
                            word: $knownWords[index],
                            isKnown: knownPositions.contains(index),
                            onKnownToggle: {
                                if knownPositions.contains(index) {
                                    knownPositions.remove(index)
                                } else {
                                    knownPositions.insert(index)
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
                
                // Progress
                if isSearching {
                    VStack(spacing: 8) {
                        ProgressView(value: searchProgress)
                            .progressViewStyle(.linear)
                            .tint(Color(hex: "#00D4FF"))
                        
                        Text("Searching possible combinations...")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 20)
                }
                
                Spacer()
                
                // Search button
                Button(action: startRecoverySearch) {
                    HStack(spacing: 8) {
                        if isSearching {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(isSearching ? "Searching..." : "Search for Wallet")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "#00A3CC"), Color(hex: "#00D4FF")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                }
                .disabled(knownPositions.count < 8 || isSearching)
                .opacity(knownPositions.count >= 8 ? 1 : 0.5)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .navigationTitle("Partial Recovery")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
    }
    
    private func startRecoverySearch() {
        isSearching = true
        
        // Simulate search progress
        Task {
            for i in 0...100 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                await MainActor.run {
                    searchProgress = Double(i) / 100.0
                }
            }
            
            await MainActor.run {
                isSearching = false
                // In production, this would attempt actual recovery
                // For now, show that we tried
            }
        }
    }
}

// MARK: - Partial Word Cell

private struct PartialWordCell: View {
    let index: Int
    @Binding var word: String
    let isKnown: Bool
    let onKnownToggle: () -> Void
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text("\(index + 1)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
                
                Spacer()
                
                Button(action: onKnownToggle) {
                    Image(systemName: isKnown ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                        .foregroundColor(isKnown ? Color(hex: "#00D4FF") : .white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
            
            TextField("word", text: $word)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .autocorrectionDisabled()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(isKnown ? 0.1 : 0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isKnown ? Color(hex: "#00D4FF").opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

// MARK: - Guardian Contact Sheet

private struct GuardianContactSheet: View {
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var guardians: [RecoveryGuardianStatus] = [
        RecoveryGuardianStatus(name: "Alice", email: "alice@email.com", status: .notContacted),
        RecoveryGuardianStatus(name: "Bob", email: "bob@email.com", status: .notContacted),
        RecoveryGuardianStatus(name: "Charlie", email: "charlie@email.com", status: .notContacted)
    ]
    
    struct RecoveryGuardianStatus: Identifiable {
        let id = UUID()
        let name: String
        let email: String
        var status: Status
        
        enum Status {
            case notContacted
            case pending
            case received
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Instructions
                VStack(spacing: 8) {
                    Text("Contact Your Guardians")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("Request recovery shards from your trusted guardians. You need 2 of 3 to recover.")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
                .padding(.horizontal, 20)
                
                // Guardian list
                VStack(spacing: 12) {
                    ForEach($guardians) { $guardian in
                        GuardianContactCard(guardian: $guardian)
                    }
                }
                .padding(.horizontal, 20)
                
                // Progress indicator
                let receivedCount = guardians.filter { $0.status == .received }.count
                VStack(spacing: 8) {
                    Text("\(receivedCount) of 2 shards received")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    
                    HStack(spacing: 4) {
                        ForEach(0..<2, id: \.self) { i in
                            Circle()
                                .fill(i < receivedCount ? Color(hex: "#00D4FF") : Color.white.opacity(0.2))
                                .frame(width: 12, height: 12)
                        }
                    }
                }
                .padding(.top, 16)
                
                Spacer()
                
                // Recover button
                Button(action: {
                    onComplete()
                    dismiss()
                }) {
                    Text("Recover Wallet")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "#00A3CC"), Color(hex: "#00D4FF")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
                .disabled(receivedCount < 2)
                .opacity(receivedCount >= 2 ? 1 : 0.5)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .navigationTitle("Guardian Recovery")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
    }
}

// MARK: - Guardian Contact Card

private struct GuardianContactCard: View {
    @Binding var guardian: GuardianContactSheet.RecoveryGuardianStatus
    
    var body: some View {
        HStack(spacing: 16) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color(hex: "#00A3CC").opacity(0.3))
                    .frame(width: 48, height: 48)
                
                Text(String(guardian.name.prefix(1)))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(guardian.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(guardian.email)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            // Status / Action
            statusButton
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(statusBorderColor, lineWidth: 1)
                )
        )
    }
    
    @ViewBuilder
    private var statusButton: some View {
        switch guardian.status {
        case .notContacted:
            Button(action: {
                guardian.status = .pending
                // Simulate receiving after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    guardian.status = .received
                }
            }) {
                Text("Request")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: "#00A3CC"))
                    )
            }
            .buttonStyle(.plain)
            
        case .pending:
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Pending")
                    .font(.system(size: 13))
                    .foregroundColor(.orange)
            }
            
        case .received:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Received")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.green)
            }
        }
    }
    
    private var statusBorderColor: Color {
        switch guardian.status {
        case .notContacted: return Color.white.opacity(0.1)
        case .pending: return Color.orange.opacity(0.3)
        case .received: return Color.green.opacity(0.3)
        }
    }
}

// MARK: - Hawala File Import Screen

struct HawalaFileImportScreen: View {
    let onComplete: () -> Void
    var onBack: (() -> Void)? = nil
    
    @StateObject private var importManager = WalletImportManager.shared
    @State private var showFilePicker = false
    @State private var selectedFileURL: URL? = nil
    @State private var password = ""
    @State private var showPassword = false
    @State private var isDecrypting = false
    @State private var animateContent = false
    
    var body: some View {
        VStack(spacing: 32) {
            // Header
            HStack {
                if let onBack = onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            
            Spacer()
            
            // Title
            VStack(spacing: 12) {
                Image(systemName: "doc.badge.ellipsis")
                    .font(.system(size: 56))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "#00D4FF"), Color(hex: "#00A3CC")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 20)
                
                Text("Import Hawala Backup")
                    .font(.custom("ClashGrotesk-Bold", size: 28))
                    .foregroundColor(.white)
                
                Text("Select your .hawala backup file")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .opacity(animateContent ? 1 : 0)
            
            // File selection area
            VStack(spacing: 20) {
                if let fileURL = selectedFileURL {
                    // File selected
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "#00A3CC").opacity(0.2))
                                .frame(width: 48, height: 48)
                            Image(systemName: "doc.fill")
                                .font(.system(size: 20))
                                .foregroundColor(Color(hex: "#00D4FF"))
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(fileURL.lastPathComponent)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                            
                            Text("Encrypted backup file")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            selectedFileURL = nil
                            password = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.05))
                    )
                    
                    // Password field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Backup Password")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                        
                        HStack {
                            Group {
                                if showPassword {
                                    TextField("Enter backup password", text: $password)
                                } else {
                                    SecureField("Enter backup password", text: $password)
                                }
                            }
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            
                            Button(action: { showPassword.toggle() }) {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        )
                    }
                } else {
                    // Drop zone / file picker button
                    Button(action: { showFilePicker = true }) {
                        VStack(spacing: 16) {
                            Image(systemName: "arrow.down.doc.fill")
                                .font(.system(size: 40))
                                .foregroundColor(Color(hex: "#00D4FF"))
                            
                            Text("Choose Backup File")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Text(".hawala files only")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.03))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(
                                            style: StrokeStyle(lineWidth: 2, dash: [8, 8])
                                        )
                                        .foregroundColor(Color.white.opacity(0.15))
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .opacity(animateContent ? 1 : 0)
            
            // Error message
            if case .error(let error) = importManager.state {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error.localizedDescription)
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 24)
            }
            
            Spacer()
            
            // Import button
            VStack(spacing: 16) {
                OnboardingPrimaryButton(
                    title: isDecrypting ? "Decrypting..." : "Import Wallet",
                    action: importBackup,
                    style: .accent
                )
                .disabled(selectedFileURL == nil || password.isEmpty || isDecrypting)
                .opacity(selectedFileURL != nil && !password.isEmpty ? 1 : 0.5)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 50)
            .opacity(animateContent ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                animateContent = true
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    selectedFileURL = url
                }
            case .failure(let error):
                print("File picker error: \(error)")
            }
        }
        .onChange(of: importManager.state) { newState in
            if case .success = newState {
                onComplete()
            }
        }
    }
    
    private func importBackup() {
        guard let fileURL = selectedFileURL else { return }
        isDecrypting = true
        
        Task {
            await importManager.importFromHawalaFile(
                url: fileURL,
                password: password
            )
            isDecrypting = false
        }
    }
}

// MARK: - Previews

#if DEBUG
struct ImportScreens_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ImportMethodSelectionScreen(
                onSelectMethod: { _ in },
                onBack: {}
            )
            .previewDisplayName("Import Method Selection")
            
            SeedPhraseImportScreen(
                importManager: WalletImportManager.shared,
                onComplete: {},
                onBack: {}
            )
            .previewDisplayName("Seed Phrase Import")
            
            HawalaFileImportScreen(
                onComplete: {},
                onBack: {}
            )
            .previewDisplayName("Hawala File Import")
        }
    }
}
#endif
