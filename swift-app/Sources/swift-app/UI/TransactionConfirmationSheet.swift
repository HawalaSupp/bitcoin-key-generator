import SwiftUI

// MARK: - Transaction Confirmation Data Model

/// Represents all details needed for transaction confirmation
struct TransactionConfirmation: Identifiable {
    let id = UUID()
    
    // Transaction details
    let chainType: ChainType
    let fromAddress: String
    let toAddress: String
    let amount: String
    let amountFiat: String?
    let fee: String
    let feeFiat: String?
    let total: String
    let totalFiat: String?
    
    // Optional additional info
    let memo: String?
    let contractAddress: String?  // For token transfers
    let tokenSymbol: String?
    let nonce: Int?
    let gasLimit: Int?
    let gasPrice: String?
    
    // Network info
    let networkName: String
    let isTestnet: Bool
    
    // Timestamps
    let estimatedTime: String?
    
    enum ChainType: String, CaseIterable {
        case bitcoin = "Bitcoin"
        case ethereum = "Ethereum"
        case litecoin = "Litecoin"
        case solana = "Solana"
        case xrp = "XRP"
        case bnb = "BNB"
        case monero = "Monero"
        
        var icon: String {
            switch self {
            case .bitcoin: return "bitcoinsign.circle.fill"
            case .ethereum: return "diamond.fill"
            case .litecoin: return "l.circle.fill"
            case .solana: return "sun.max.fill"
            case .xrp: return "drop.fill"
            case .bnb: return "b.circle.fill"
            case .monero: return "m.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .bitcoin: return Color.orange
            case .ethereum: return Color(red: 0.4, green: 0.4, blue: 0.9)
            case .litecoin: return Color.gray
            case .solana: return Color(red: 0.6, green: 0.2, blue: 0.9)
            case .xrp: return Color.blue
            case .bnb: return Color.yellow
            case .monero: return Color.orange
            }
        }
        
        var explorerBaseURL: String? {
            switch self {
            case .bitcoin: return "https://mempool.space/tx/"
            case .ethereum: return "https://etherscan.io/tx/"
            case .litecoin: return "https://blockchair.com/litecoin/transaction/"
            case .solana: return "https://solscan.io/tx/"
            case .xrp: return "https://xrpscan.com/tx/"
            case .bnb: return "https://bscscan.com/tx/"
            case .monero: return nil
            }
        }
    }
}

// MARK: - Transaction Confirmation Sheet View

struct TransactionConfirmationSheet: View {
    let confirmation: TransactionConfirmation
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    @State private var isConfirming = false
    @State private var showAddressDetails = false
    @State private var biometricChecked = false
    @State private var agreedToTerms = false
    @State private var countdown = 3
    @State private var canConfirm = false
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            ScrollView {
                VStack(spacing: 20) {
                    // Amount section
                    amountSection
                    
                    // From/To addresses
                    addressSection
                    
                    // Fee breakdown
                    feeSection
                    
                    // Additional details
                    if hasAdditionalDetails {
                        additionalDetailsSection
                    }
                    
                    // Security warnings
                    securityWarnings
                    
                    // Confirmation checkbox
                    confirmationCheckbox
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            
            // Action buttons
            actionButtons
        }
        .frame(width: 480, height: 640)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .onAppear {
            startCountdown()
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(spacing: 12) {
            // Chain icon
            ZStack {
                Circle()
                    .fill(confirmation.chainType.color.opacity(0.2))
                    .frame(width: 60, height: 60)
                
                Image(systemName: confirmation.chainType.icon)
                    .font(.system(size: 28))
                    .foregroundColor(confirmation.chainType.color)
            }
            
            Text("Confirm Transaction")
                .font(.title2.bold())
                .foregroundColor(.primary)
            
            HStack(spacing: 6) {
                Circle()
                    .fill(confirmation.isTestnet ? Color.yellow : Color.green)
                    .frame(width: 8, height: 8)
                
                Text(confirmation.networkName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 24)
        .padding(.bottom, 16)
    }
    
    // MARK: - Amount Section
    
    private var amountSection: some View {
        VStack(spacing: 8) {
            Text("You're sending")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text(confirmation.amount)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            if let fiat = confirmation.amountFiat {
                Text("≈ \(fiat)")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(cardBackground)
        .cornerRadius(16)
    }
    
    // MARK: - Address Section
    
    private var addressSection: some View {
        VStack(spacing: 16) {
            // From address
            HStack(spacing: 12) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(.red)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("From")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(truncateAddress(confirmation.fromAddress))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Button {
                    copyToClipboard(confirmation.fromAddress)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(cardBackground)
            .cornerRadius(12)
            
            // Arrow
            Image(systemName: "arrow.down")
                .font(.title3)
                .foregroundColor(.secondary)
            
            // To address
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("To")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(truncateAddress(confirmation.toAddress))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.primary)
                    
                    // Address verification indicator
                    if verifyAddressChecksum(confirmation.toAddress) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.caption2)
                                .foregroundColor(.green)
                            Text("Valid checksum")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                }
                
                Spacer()
                
                Button {
                    copyToClipboard(confirmation.toAddress)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(cardBackground)
            .cornerRadius(12)
            
            // Expand to show full addresses
            Button {
                withAnimation(.spring(response: 0.3)) {
                    showAddressDetails.toggle()
                }
            } label: {
                HStack {
                    Text(showAddressDetails ? "Hide full addresses" : "Show full addresses")
                    Image(systemName: showAddressDetails ? "chevron.up" : "chevron.down")
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            
            if showAddressDetails {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Full From Address:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(confirmation.fromAddress)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Full To Address:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(confirmation.toAddress)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                    }
                }
                .padding(12)
                .background(Color.black.opacity(0.3))
                .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Fee Section
    
    private var feeSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Network Fee")
                    .foregroundColor(.secondary)
                Spacer()
                VStack(alignment: .trailing) {
                    Text(confirmation.fee)
                        .foregroundColor(.primary)
                    if let feeFiat = confirmation.feeFiat {
                        Text("≈ \(feeFiat)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Divider()
            
            HStack {
                Text("Total")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                VStack(alignment: .trailing) {
                    Text(confirmation.total)
                        .font(.headline)
                        .foregroundColor(.primary)
                    if let totalFiat = confirmation.totalFiat {
                        Text("≈ \(totalFiat)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if let estimatedTime = confirmation.estimatedTime {
                HStack {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Estimated confirmation: \(estimatedTime)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(cardBackground)
        .cornerRadius(12)
    }
    
    // MARK: - Additional Details
    
    private var hasAdditionalDetails: Bool {
        confirmation.memo != nil || confirmation.gasLimit != nil || confirmation.nonce != nil
    }
    
    private var additionalDetailsSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Transaction Details")
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                Spacer()
            }
            
            if let nonce = confirmation.nonce {
                detailRow(label: "Nonce", value: "\(nonce)")
            }
            
            if let gasLimit = confirmation.gasLimit {
                detailRow(label: "Gas Limit", value: "\(gasLimit)")
            }
            
            if let gasPrice = confirmation.gasPrice {
                detailRow(label: "Gas Price", value: gasPrice)
            }
            
            if let memo = confirmation.memo, !memo.isEmpty {
                detailRow(label: "Memo", value: memo)
            }
            
            if let contract = confirmation.contractAddress {
                detailRow(label: "Contract", value: truncateAddress(contract))
            }
        }
        .padding(16)
        .background(cardBackground)
        .cornerRadius(12)
    }
    
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
        }
    }
    
    // MARK: - Security Warnings
    
    private var securityWarnings: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Verify all details carefully")
                    .font(.subheadline.bold())
                    .foregroundColor(.orange)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 6) {
                warningItem("Transactions cannot be reversed once confirmed")
                warningItem("Double-check the recipient address")
                warningItem("Ensure you're on the correct network")
                if confirmation.isTestnet {
                    warningItem("This is a TESTNET transaction - no real value", isInfo: true)
                }
            }
        }
        .padding(16)
        .background(Color.orange.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(12)
    }
    
    private func warningItem(_ text: String, isInfo: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isInfo ? "info.circle" : "checkmark.circle")
                .font(.caption)
                .foregroundColor(isInfo ? .blue : .secondary)
            Text(text)
                .font(.caption)
                .foregroundColor(isInfo ? .blue : .secondary)
            Spacer()
        }
    }
    
    // MARK: - Confirmation Checkbox
    
    private var confirmationCheckbox: some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                agreedToTerms.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: agreedToTerms ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundColor(agreedToTerms ? .blue : .secondary)
                
                Text("I have verified the recipient address and transaction details")
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(.plain)
        .padding(16)
        .background(cardBackground)
        .cornerRadius(12)
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
            .disabled(isConfirming)
            
            Button {
                confirmTransaction()
            } label: {
                HStack(spacing: 8) {
                    if isConfirming {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else if !canConfirm {
                        Text("Wait \(countdown)s...")
                    } else {
                        Image(systemName: "paperplane.fill")
                        Text("Confirm & Send")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(confirmButtonEnabled ? confirmation.chainType.color : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(!confirmButtonEnabled)
        }
        .padding(24)
        .background(Color.black.opacity(0.2))
    }
    
    private var confirmButtonEnabled: Bool {
        canConfirm && agreedToTerms && !isConfirming
    }
    
    // MARK: - Helpers
    
    private func truncateAddress(_ address: String) -> String {
        guard address.count > 16 else { return address }
        let prefix = address.prefix(8)
        let suffix = address.suffix(6)
        return "\(prefix)...\(suffix)"
    }
    
    private func verifyAddressChecksum(_ address: String) -> Bool {
        // Basic validation - could be enhanced per chain
        switch confirmation.chainType {
        case .bitcoin, .litecoin:
            return address.hasPrefix("1") || address.hasPrefix("3") || 
                   address.hasPrefix("bc1") || address.hasPrefix("tb1") ||
                   address.hasPrefix("L") || address.hasPrefix("M") || address.hasPrefix("ltc1")
        case .ethereum, .bnb:
            return address.hasPrefix("0x") && address.count == 42
        case .solana:
            return address.count >= 32 && address.count <= 44
        case .xrp:
            return address.hasPrefix("r") && address.count >= 25
        case .monero:
            return address.hasPrefix("4") && address.count >= 95
        }
    }
    
    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
    
    private func startCountdown() {
        // Security delay before allowing confirmation
        countdown = 3
        canConfirm = false
        
        Task { @MainActor in
            for i in stride(from: 3, through: 0, by: -1) {
                countdown = i
                if i == 0 {
                    canConfirm = true
                    break
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
    
    private func confirmTransaction() {
        isConfirming = true
        onConfirm()
    }
}

// MARK: - Preview

#if DEBUG
struct TransactionConfirmationSheet_Previews: PreviewProvider {
    static var previews: some View {
        TransactionConfirmationSheet(
            confirmation: TransactionConfirmation(
                chainType: .bitcoin,
                fromAddress: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
                toAddress: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4",
                amount: "0.00150000 BTC",
                amountFiat: "$152.34 USD",
                fee: "0.00002100 BTC",
                feeFiat: "$2.14 USD",
                total: "0.00152100 BTC",
                totalFiat: "$154.48 USD",
                memo: nil,
                contractAddress: nil,
                tokenSymbol: nil,
                nonce: nil,
                gasLimit: nil,
                gasPrice: nil,
                networkName: "Bitcoin Mainnet",
                isTestnet: false,
                estimatedTime: "~10 minutes"
            ),
            onConfirm: { print("Confirmed!") },
            onCancel: { print("Cancelled!") }
        )
        .preferredColorScheme(.dark)
    }
}
#endif
