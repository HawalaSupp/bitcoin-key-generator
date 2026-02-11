import SwiftUI

// MARK: - Transaction Review View

/// A confirmation screen showing transaction details before broadcast
struct TransactionReviewView: View {
    let transaction: TransactionReviewData
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    @State private var isConfirming = false
    @State private var showingBiometricPrompt = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            ScrollView {
                VStack(spacing: 20) {
                    // Amount being sent
                    amountSection
                    
                    Divider()
                        .padding(.horizontal)
                    
                    // Recipient details
                    recipientSection
                    
                    Divider()
                        .padding(.horizontal)
                    
                    // Fee breakdown
                    feeSection
                    
                    Divider()
                        .padding(.horizontal)
                    
                    // Total
                    totalSection
                    
                    // Warning for high fees
                    if transaction.feePercentage > 10 {
                        highFeeWarning
                    }
                }
                .padding(.vertical, 20)
            }
            
            // Action buttons
            actionButtons
        }
        .background(backgroundColor)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(spacing: 8) {
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.secondary.opacity(0.1)))
                }
                
                Spacer()
                
                Text("Review Transaction")
                    .font(.headline)
                
                Spacer()
                
                // Placeholder for symmetry
                Color.clear
                    .frame(width: 32, height: 32)
            }
            .padding(.horizontal)
            .padding(.top, 16)
            
            // Chain indicator
            HStack(spacing: 6) {
                Image(systemName: transaction.chainIcon)
                    .font(.caption)
                Text(transaction.chainName)
                    .font(.caption.weight(.medium))
            }
            .foregroundColor(.secondary)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(Capsule().fill(Color.secondary.opacity(0.1)))
        }
    }
    
    // MARK: - Amount Section
    
    private var amountSection: some View {
        VStack(spacing: 8) {
            Text("You Send")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(transaction.formattedAmount)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                
                Text(transaction.symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            
            if let fiatAmount = transaction.fiatAmount {
                Text("≈ $\(String(format: "%.2f", fiatAmount)) USD")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Recipient Section
    
    private var recipientSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("To")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 6) {
                // ROADMAP-16 E12: Show saved contact name if available
                if let contact = ContactsManager.shared.contact(forAddress: transaction.recipientAddress) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.caption)
                            .foregroundColor(HawalaTheme.Colors.accent)
                        Text(contact.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(HawalaTheme.Colors.textPrimary)
                    }
                }
                
                // Show ENS/domain name if available
                if let displayName = transaction.recipientDisplayName {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text(displayName)
                            .font(.subheadline.weight(.medium))
                    }
                }
                
                // Address with chunking for readability
                AddressDisplayView(
                    address: transaction.recipientAddress,
                    style: .chunked
                )
            }
            .padding(12)
            .background(cardBackground)
            .cornerRadius(12)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Fee Section
    
    private var feeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Network Fee")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Fee priority badge
                HStack(spacing: 4) {
                    Image(systemName: transaction.feePriority.icon)
                        .font(.caption2)
                    Text(transaction.feePriority.rawValue)
                        .font(.caption.weight(.medium))
                }
                .foregroundColor(feePriorityColor)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Capsule().fill(feePriorityColor.opacity(0.15)))
            }
            
            VStack(spacing: 8) {
                // Fee rate
                HStack {
                    Text("Fee Rate")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(transaction.formattedFeeRate)
                        .font(.subheadline.monospacedDigit())
                }
                
                // Total fee
                HStack {
                    Text("Total Fee")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(transaction.formattedFee) \(transaction.symbol)")
                            .font(.subheadline.weight(.medium).monospacedDigit())
                        if let fiatFee = transaction.fiatFee {
                            Text("≈ $\(String(format: "%.2f", fiatFee))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Estimated time
                HStack {
                    Text("Est. Confirmation")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(transaction.estimatedTime)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(cardBackground)
            .cornerRadius(12)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Total Section
    
    private var totalSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Total")
                    .font(.headline)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(transaction.formattedTotal) \(transaction.symbol)")
                        .font(.title3.weight(.bold).monospacedDigit())
                    if let fiatTotal = transaction.fiatTotal {
                        Text("≈ $\(String(format: "%.2f", fiatTotal)) USD")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Balance check
            if transaction.hasInsufficientBalance {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("Insufficient balance")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    // MARK: - High Fee Warning
    
    private var highFeeWarning: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("High Fee Warning")
                    .font(.subheadline.weight(.semibold))
                Text("Network fee is \(String(format: "%.1f", transaction.feePercentage))% of the amount")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Confirm button
            Button(action: {
                isConfirming = true
                onConfirm()
            }) {
                HStack {
                    if isConfirming {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                    Text(isConfirming ? "Sending..." : "Confirm & Send")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(transaction.hasInsufficientBalance ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(14)
            }
            .disabled(isConfirming || transaction.hasInsufficientBalance)
            
            // Cancel button
            Button(action: onCancel) {
                Text("Cancel")
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .foregroundColor(.primary)
                    .cornerRadius(14)
            }
            .disabled(isConfirming)
        }
        .padding()
        .background(backgroundColor)
    }
    
    // MARK: - Helpers
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color(NSColor.windowBackgroundColor)
    }
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
    }
    
    private var feePriorityColor: Color {
        switch transaction.feePriority {
        case .slow: return .green
        case .average: return .orange
        case .fast: return .red
        }
    }
}

// MARK: - Transaction Review Data

struct TransactionReviewData {
    let chainId: String
    let chainName: String
    let chainIcon: String
    let symbol: String
    
    let amount: Double
    let recipientAddress: String
    let recipientDisplayName: String? // ENS, etc.
    
    let feeRate: Double
    let feeRateUnit: String // sat/vB, Gwei
    let fee: Double
    let feePriority: FeePriority
    let estimatedTime: String
    
    let fiatAmount: Double?
    let fiatFee: Double?
    
    let currentBalance: Double?
    
    // Computed properties
    var total: Double { amount + fee }
    
    var fiatTotal: Double? {
        guard let fiatAmount = fiatAmount, let fiatFee = fiatFee else { return nil }
        return fiatAmount + fiatFee
    }
    
    var feePercentage: Double {
        guard amount > 0 else { return 0 }
        return (fee / amount) * 100
    }
    
    var hasInsufficientBalance: Bool {
        guard let balance = currentBalance else { return false }
        return total > balance
    }
    
    var formattedAmount: String {
        formatCrypto(amount)
    }
    
    var formattedFee: String {
        formatCrypto(fee)
    }
    
    var formattedTotal: String {
        formatCrypto(total)
    }
    
    var formattedFeeRate: String {
        if feeRate < 1 {
            return String(format: "%.2f %@", feeRate, feeRateUnit)
        } else if feeRate < 100 {
            return String(format: "%.1f %@", feeRate, feeRateUnit)
        } else {
            return String(format: "%.0f %@", feeRate, feeRateUnit)
        }
    }
    
    private func formatCrypto(_ value: Double) -> String {
        if value < 0.0001 {
            return String(format: "%.8f", value)
        } else if value < 0.01 {
            return String(format: "%.6f", value)
        } else if value < 1 {
            return String(format: "%.4f", value)
        } else {
            return String(format: "%.4f", value)
        }
    }
}

// MARK: - Address Display View

struct AddressDisplayView: View {
    let address: String
    let style: AddressStyle
    
    enum AddressStyle {
        case full
        case truncated
        case chunked
    }
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        switch style {
        case .full:
            Text(address)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        case .truncated:
            Text(truncatedAddress)
                .font(.system(.caption, design: .monospaced))
        case .chunked:
            chunkedAddressView
        }
    }
    
    private var truncatedAddress: String {
        guard address.count > 16 else { return address }
        let prefix = String(address.prefix(8))
        let suffix = String(address.suffix(6))
        return "\(prefix)...\(suffix)"
    }
    
    private var chunkedAddressView: some View {
        let chunks = chunkAddress(address, size: 8)
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { index, chunk in
                HStack(spacing: 0) {
                    // Highlight first and last chunks
                    if index == 0 {
                        Text(chunk)
                            .foregroundColor(.blue)
                    } else if index == chunks.count - 1 {
                        Text(chunk)
                            .foregroundColor(.green)
                    } else {
                        Text(chunk)
                            .foregroundColor(.primary.opacity(0.7))
                    }
                }
            }
        }
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
    }
    
    private func chunkAddress(_ address: String, size: Int) -> [String] {
        var chunks: [String] = []
        var remaining = address
        
        while !remaining.isEmpty {
            let chunk = String(remaining.prefix(size))
            chunks.append(chunk)
            remaining = String(remaining.dropFirst(size))
        }
        
        return chunks
    }
}

// MARK: - Preview

#if DEBUG
struct TransactionReviewView_Previews: PreviewProvider {
    static var previews: some View {
        TransactionReviewView(
            transaction: TransactionReviewData(
                chainId: "bitcoin-testnet",
                chainName: "Bitcoin Testnet",
                chainIcon: "bitcoinsign.circle.fill",
                symbol: "BTC",
                amount: 0.001,
                recipientAddress: "tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx",
                recipientDisplayName: nil,
                feeRate: 5,
                feeRateUnit: "sat/vB",
                fee: 0.00000700,
                feePriority: .average,
                estimatedTime: "~30 min",
                fiatAmount: 45.50,
                fiatFee: 0.32,
                currentBalance: 0.005
            ),
            onConfirm: {},
            onCancel: {}
        )
        .frame(width: 400, height: 700)
    }
}
#endif
