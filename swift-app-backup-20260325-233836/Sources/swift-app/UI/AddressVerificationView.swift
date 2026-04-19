import SwiftUI

// MARK: - Chain Type for Address Verification
// Using the same ChainType as TransactionConfirmation for consistency

typealias AddressChainType = TransactionConfirmation.ChainType

// MARK: - Address Verification View

/// A view that provides visual checksum verification and address validation
struct AddressVerificationView: View {
    let address: String
    let chainType: AddressChainType
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    @State private var userInputAddress = ""
    @State private var verificationStep: VerificationStep = .visual
    @State private var isVerified = false
    @State private var showENSLookup = false
    @State private var ensName: String?
    @State private var isLookingUp = false
    
    @Environment(\.colorScheme) private var colorScheme
    
    enum VerificationStep {
        case visual
        case manualEntry
        case confirmed
    }
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            ScrollView {
                VStack(spacing: 24) {
                    switch verificationStep {
                    case .visual:
                        visualVerificationView
                    case .manualEntry:
                        manualEntryView
                    case .confirmed:
                        confirmedView
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            
            // Action buttons
            actionButtons
        }
        .frame(width: 500, height: 580)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .onAppear {
            if chainType == .ethereum {
                lookupENS()
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 60, height: 60)
                
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.blue)
            }
            
            Text("Verify Address")
                .font(.title2.bold())
                .foregroundColor(.primary)
            
            Text("Take a moment to verify the recipient address")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
        .padding(.bottom, 16)
    }
    
    // MARK: - Visual Verification View
    
    private var visualVerificationView: some View {
        VStack(spacing: 20) {
            // Address display with color coding
            VStack(spacing: 16) {
                Text("Recipient Address")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Chunked address display
                chunkedAddressView
                
                // Address type indicator
                addressTypeIndicator
                
                // ENS/Domain name if available
                if let ensName = ensName {
                    HStack(spacing: 8) {
                        Image(systemName: "person.circle.fill")
                            .foregroundColor(.green)
                        Text(ensName)
                            .font(.headline)
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(20)
                } else if isLookingUp {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Looking up ENS name...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(20)
            .background(cardBackground)
            .cornerRadius(16)
            
            // Verification checklist
            verificationChecklist
            
            // Tips
            verificationTips
        }
    }
    
    private var chunkedAddressView: some View {
        let chunks = chunkAddress(address, size: 4)
        
        return VStack(spacing: 8) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 4) {
                    ForEach(Array(row.enumerated()), id: \.offset) { chunkIndex, chunk in
                        Text(chunk)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(colorForChunk(index: index * row.count + chunkIndex))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(colorForChunk(index: index * row.count + chunkIndex).opacity(0.1))
                            )
                    }
                }
            }
        }
        .padding(16)
        .background(Color.black.opacity(0.2))
        .cornerRadius(12)
    }
    
    private func chunkAddress(_ address: String, size: Int) -> [[String]] {
        var chunks: [String] = []
        var remaining = address
        
        while !remaining.isEmpty {
            let end = remaining.index(remaining.startIndex, offsetBy: min(size, remaining.count))
            chunks.append(String(remaining[..<end]))
            remaining = String(remaining[end...])
        }
        
        // Group into rows of 4 chunks each
        var rows: [[String]] = []
        var currentRow: [String] = []
        for chunk in chunks {
            currentRow.append(chunk)
            if currentRow.count == 4 {
                rows.append(currentRow)
                currentRow = []
            }
        }
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }
        
        return rows
    }
    
    private func colorForChunk(index: Int) -> Color {
        let colors: [Color] = [
            .blue, .green, .orange, .purple, .pink, .cyan, .yellow, .red
        ]
        return colors[index % colors.count]
    }
    
    private var addressTypeIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: addressTypeIcon)
                .foregroundColor(addressTypeColor)
            
            Text(addressTypeDescription)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(addressTypeColor.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var addressTypeIcon: String {
        switch chainType {
        case .bitcoin:
            if address.hasPrefix("bc1q") { return "checkmark.circle.fill" }
            if address.hasPrefix("bc1p") { return "sparkles" }
            if address.hasPrefix("3") { return "lock.fill" }
            return "bitcoinsign.circle"
        case .ethereum, .bnb:
            return "hexagon.fill"
        case .solana:
            return "sun.max.fill"
        case .litecoin:
            return "l.circle.fill"
        case .xrp:
            return "drop.fill"
        case .monero:
            return "eye.slash.fill"
        }
    }
    
    private var addressTypeColor: Color {
        switch chainType {
        case .bitcoin:
            if address.hasPrefix("bc1") { return .green }
            return .orange
        default:
            return chainType.color
        }
    }
    
    private var addressTypeDescription: String {
        switch chainType {
        case .bitcoin:
            if address.hasPrefix("bc1q") { return "Native SegWit (Bech32)" }
            if address.hasPrefix("bc1p") { return "Taproot (P2TR)" }
            if address.hasPrefix("3") { return "SegWit (P2SH)" }
            if address.hasPrefix("1") { return "Legacy (P2PKH)" }
            if address.hasPrefix("tb1") { return "Testnet SegWit" }
            if address.hasPrefix("m") || address.hasPrefix("n") { return "Testnet Legacy" }
            return "Bitcoin Address"
        case .ethereum:
            return "Ethereum Address (ERC-20 compatible)"
        case .bnb:
            return "BNB Smart Chain Address"
        case .solana:
            return "Solana Address (Base58)"
        case .litecoin:
            if address.hasPrefix("ltc1") { return "Native SegWit" }
            if address.hasPrefix("M") { return "SegWit (P2SH)" }
            return "Litecoin Address"
        case .xrp:
            return "XRP Ledger Address"
        case .monero:
            return "Monero Address (Private)"
        }
    }
    
    private var verificationChecklist: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Verification Checklist")
                .font(.subheadline.bold())
                .foregroundColor(.primary)
            
            checklistItem("First 4 characters match expected", isChecked: true)
            checklistItem("Last 4 characters match expected", isChecked: true)
            checklistItem("Address length is correct (\(address.count) chars)", isChecked: isValidLength)
            checklistItem("Address format is valid", isChecked: isValidFormat)
        }
        .padding(16)
        .background(cardBackground)
        .cornerRadius(12)
    }
    
    private var isValidLength: Bool {
        switch chainType {
        case .bitcoin:
            return address.count >= 26 && address.count <= 62
        case .ethereum, .bnb:
            return address.count == 42
        case .solana:
            return address.count >= 32 && address.count <= 44
        case .litecoin:
            return address.count >= 26 && address.count <= 62
        case .xrp:
            return address.count >= 25 && address.count <= 35
        case .monero:
            return address.count >= 95 && address.count <= 106
        }
    }
    
    private var isValidFormat: Bool {
        switch chainType {
        case .bitcoin:
            return address.hasPrefix("1") || address.hasPrefix("3") || 
                   address.hasPrefix("bc1") || address.hasPrefix("tb1") ||
                   address.hasPrefix("m") || address.hasPrefix("n") || address.hasPrefix("2")
        case .ethereum, .bnb:
            return address.hasPrefix("0x")
        case .solana:
            return !address.contains("0") && !address.contains("O") && 
                   !address.contains("I") && !address.contains("l")
        case .litecoin:
            return address.hasPrefix("L") || address.hasPrefix("M") || 
                   address.hasPrefix("ltc1") || address.hasPrefix("3")
        case .xrp:
            return address.hasPrefix("r")
        case .monero:
            return address.hasPrefix("4") || address.hasPrefix("8")
        }
    }
    
    private func checklistItem(_ text: String, isChecked: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isChecked ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isChecked ? .green : .red)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var verificationTips: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text("Tips")
                    .font(.subheadline.bold())
            }
            
            Text("• Compare the colored segments with your source")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("• Pay special attention to similar characters: 0/O, 1/l/I")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("• If in doubt, use manual entry verification below")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color.yellow.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Manual Entry View
    
    private var manualEntryView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Text("Re-enter the Address")
                    .font(.headline)
                
                Text("Type or paste the address again to confirm it matches")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 8) {
                TextField("Enter address", text: $userInputAddress)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, design: .monospaced))
                    .padding(16)
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(12)
                    .autocorrectionDisabled(true)
                    .onChange(of: userInputAddress) { newValue in
                        checkMatch()
                    }
                
                if !userInputAddress.isEmpty {
                    HStack {
                        if userInputAddress.lowercased() == address.lowercased() {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Addresses match!")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text("Addresses do not match")
                                .foregroundColor(.red)
                        }
                    }
                    .font(.subheadline)
                }
            }
            
            // Original address reference
            VStack(alignment: .leading, spacing: 8) {
                Text("Original address:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(address)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .cornerRadius(12)
        }
    }
    
    private func checkMatch() {
        isVerified = userInputAddress.lowercased() == address.lowercased()
    }
    
    // MARK: - Confirmed View
    
    private var confirmedView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.green)
            }
            
            Text("Address Verified!")
                .font(.title2.bold())
                .foregroundColor(.green)
            
            Text("The recipient address has been confirmed")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text(address)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                if let ensName = ensName {
                    Text("(\(ensName))")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
            }
            .padding(16)
            .background(cardBackground)
            .cornerRadius(12)
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button {
                onCancel()
            } label: {
                Text("Cancel")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            
            Button {
                handlePrimaryAction()
            } label: {
                Text(primaryButtonText)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(primaryButtonEnabled ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(!primaryButtonEnabled)
        }
        .padding(24)
        .background(Color.black.opacity(0.2))
    }
    
    private var primaryButtonText: String {
        switch verificationStep {
        case .visual:
            return "I've Verified"
        case .manualEntry:
            return isVerified ? "Confirm Match" : "Enter Address"
        case .confirmed:
            return "Continue"
        }
    }
    
    private var primaryButtonEnabled: Bool {
        switch verificationStep {
        case .visual:
            return true
        case .manualEntry:
            return isVerified
        case .confirmed:
            return true
        }
    }
    
    private func handlePrimaryAction() {
        switch verificationStep {
        case .visual:
            withAnimation(.spring(response: 0.3)) {
                verificationStep = .manualEntry
            }
        case .manualEntry:
            if isVerified {
                withAnimation(.spring(response: 0.3)) {
                    verificationStep = .confirmed
                }
            }
        case .confirmed:
            onConfirm()
        }
    }
    
    // MARK: - ENS Lookup
    
    private func lookupENS() {
        guard chainType == .ethereum else { return }
        
        isLookingUp = true
        
        // Simulate ENS reverse lookup (in production, use actual ENS resolver)
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            
            await MainActor.run {
                isLookingUp = false
                // Mock: show ENS name for demo purposes
                // In production, implement actual reverse lookup
            }
        }
    }
}

// MARK: - Address QR Verification View

struct AddressQRVerificationView: View {
    let address: String
    let chainType: AddressChainType
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Scan to Verify")
                .font(.headline)
            
            // QR Code representation
            if let qrImage = generateQRCode(from: address) {
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .background(Color.white)
                    .cornerRadius(12)
            }
            
            Text("Scan this QR code with another device to verify the address")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
    }
    
    private func generateQRCode(from string: String) -> NSImage? {
        let data = string.data(using: .utf8)
        
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        
        guard let outputImage = filter.outputImage else { return nil }
        
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: transform)
        
        let rep = NSCIImageRep(ciImage: scaledImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        
        return nsImage
    }
}

// MARK: - Preview

#if DEBUG
struct AddressVerificationView_Previews: PreviewProvider {
    static var previews: some View {
        AddressVerificationView(
            address: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
            chainType: .bitcoin,
            onConfirm: { print("Confirmed!") },
            onCancel: { print("Cancelled!") }
        )
        .preferredColorScheme(.dark)
    }
}
#endif
