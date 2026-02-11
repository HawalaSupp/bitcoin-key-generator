import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Transaction Detail Sheet

/// A detailed view for displaying all information about a single transaction
struct TransactionDetailSheet: View {
    let transaction: HawalaTransactionEntry
    var onRetryTransaction: ((HawalaTransactionEntry) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showCopiedToast = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header with type and amount
                    transactionHeader
                    
                    // Status badge
                    statusSection
                    
                    // Details card
                    detailsCard

                    // Failed transaction explanation (E10)
                    if transaction.status.lowercased() == "failed" {
                        failedExplanationSection
                    }

                    // Actions
                    actionsSection
                    
                    Spacer(minLength: 40)
                }
                .padding(20)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle("Transaction Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 450, minHeight: 550)
        .overlay(alignment: .bottom) {
            if showCopiedToast {
                copiedToastView
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    
    // MARK: - Header
    
    private var transactionHeader: some View {
        VStack(spacing: 16) {
            // Type icon
            ZStack {
                Circle()
                    .fill(typeColor.opacity(0.15))
                    .frame(width: 72, height: 72)
                
                Image(systemName: typeIcon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(typeColor)
            }
            
            // Amount
            VStack(spacing: 4) {
                Text(transaction.amountDisplay)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(amountColor)
                
                Text(transaction.asset)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            
            // Type label
            Text(transaction.type)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(typeColor.opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Status Section
    
    private var statusSection: some View {
        HStack(spacing: 8) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
            
            Text(transaction.status)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(statusColor)
            
            if let confirmations = transaction.confirmationsDisplay {
                Text("•")
                    .foregroundStyle(.secondary)
                Text(confirmations)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(statusColor.opacity(0.1))
        .clipShape(Capsule())
    }
    
    // MARK: - Details Card
    
    private var detailsCard: some View {
        VStack(spacing: 0) {
            // Transaction Hash
            if let hash = transaction.txHash {
                TxDetailRow(
                    label: "Transaction Hash",
                    value: hash,
                    isMonospace: true,
                    canCopy: true,
                    onCopy: { copyToClipboard(hash) }
                )
                
                Divider()
                    .padding(.horizontal)
            }
            
            // Date/Time
            TxDetailRow(
                label: "Date",
                value: transaction.timestamp,
                isMonospace: false,
                canCopy: false
            )
            
            Divider()
                .padding(.horizontal)
            
            // Chain
            if let chainId = transaction.chainId {
                TxDetailRow(
                    label: "Network",
                    value: networkName(for: chainId),
                    isMonospace: false,
                    canCopy: false
                )
                
                Divider()
                    .padding(.horizontal)
            }
            
            // Block Number
            if let blockNumber = transaction.blockNumber {
                TxDetailRow(
                    label: "Block Number",
                    value: "\(blockNumber)",
                    isMonospace: true,
                    canCopy: true,
                    onCopy: { copyToClipboard("\(blockNumber)") }
                )
                
                Divider()
                    .padding(.horizontal)
            }
            
            // Fee
            if let fee = transaction.fee {
                TxDetailRow(
                    label: "Transaction Fee",
                    value: fee,
                    isMonospace: false,
                    canCopy: false
                )
                
                Divider()
                    .padding(.horizontal)
            }
            
            // Confirmations
            if let confirmations = transaction.confirmations {
                TxDetailRow(
                    label: "Confirmations",
                    value: confirmations >= 6 ? "6+ (Final)" : "\(confirmations)",
                    isMonospace: false,
                    canCopy: false
                )
            }
            
            // Counterparty
            if let counterparty = transaction.counterparty, !counterparty.isEmpty {
                Divider()
                    .padding(.horizontal)
                
                TxDetailRow(
                    label: transaction.type == "Send" ? "Recipient" : "Sender",
                    value: counterparty,
                    isMonospace: true,
                    canCopy: true,
                    onCopy: { copyToClipboard(counterparty) }
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
    
    // MARK: - Actions Section
    
    private var actionsSection: some View {
        VStack(spacing: 12) {
            // View on Explorer
            if let explorerURL = transaction.explorerURL {
                Button {
                    openInBrowser(explorerURL)
                } label: {
                    HStack {
                        Image(systemName: "safari")
                        Text("View on \(explorerName)")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            
            // Copy Transaction Hash
            if let hash = transaction.txHash {
                Button {
                    copyToClipboard(hash)
                } label: {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("Copy Transaction Hash")
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.secondary.opacity(0.1))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            // Retry Failed Transaction (E11)
            if transaction.status.lowercased() == "failed", let onRetry = onRetryTransaction {
                Button {
                    dismiss()
                    onRetry(transaction)
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Retry Transaction")
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.orange.opacity(0.15))
                    .foregroundStyle(.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("retry_transaction_button")
            }
        }
    }
    
    // MARK: - Failed Explanation Section (E10)
    
    private var failedExplanationSection: some View {
        let explanation = TransactionFailureReason.explanation(
            status: transaction.status,
            chainId: transaction.chainId,
            fee: transaction.fee
        )
        
        return Group {
            if let explanation {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: explanation.icon)
                            .font(.title3)
                            .foregroundStyle(.red)
                        Text(explanation.reason)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    
                    Text(explanation.explanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                        Text(explanation.suggestion)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.red.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.red.opacity(0.2), lineWidth: 1)
                )
                .accessibilityIdentifier("failed_transaction_explanation")
            }
        }
    }
    
    // MARK: - Toast View
    
    private var copiedToastView: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Copied to clipboard")
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .padding(.bottom, 20)
    }
    
    // MARK: - Helpers
    
    private var typeIcon: String {
        switch transaction.type.lowercased() {
        case "receive": return "arrow.down.left"
        case "send": return "arrow.up.right"
        case "swap": return "arrow.triangle.2.circlepath"
        default: return "arrow.left.arrow.right"
        }
    }
    
    private var typeColor: Color {
        switch transaction.type.lowercased() {
        case "receive": return .green
        case "send": return .red
        case "swap": return .blue
        default: return .secondary
        }
    }
    
    private var amountColor: Color {
        transaction.amountDisplay.hasPrefix("+") ? .green :
        transaction.amountDisplay.hasPrefix("-") ? .primary : .primary
    }
    
    private var statusIcon: String {
        switch transaction.status.lowercased() {
        case "confirmed": return "checkmark.circle.fill"
        case "pending": return "clock"
        case "processing": return "arrow.triangle.2.circlepath"
        case "failed": return "xmark.circle.fill"
        default: return "questionmark.circle"
        }
    }
    
    private var statusColor: Color {
        switch transaction.status.lowercased() {
        case "confirmed": return .green
        case "pending": return .orange
        case "processing": return .blue
        case "failed": return .red
        default: return .secondary
        }
    }
    
    private var explorerName: String {
        guard let chainId = transaction.chainId else { return "Explorer" }
        
        switch chainId {
        case "bitcoin", "bitcoin-testnet": return "Mempool"
        case "litecoin": return "Blockchair"
        case "ethereum", "ethereum-sepolia": return "Etherscan"
        case "bnb": return "BscScan"
        case "solana": return "Solscan"
        case "xrp": return "XRPScan"
        default: return "Explorer"
        }
    }
    
    private func networkName(for chainId: String) -> String {
        switch chainId {
        case "bitcoin": return "Bitcoin Mainnet"
        case "bitcoin-testnet": return "Bitcoin Testnet"
        case "litecoin": return "Litecoin"
        case "ethereum": return "Ethereum Mainnet"
        case "ethereum-sepolia": return "Ethereum Sepolia"
        case "bnb": return "BNB Chain"
        case "solana": return "Solana"
        case "xrp": return "XRP Ledger"
        default: return chainId.capitalized
        }
    }
    
    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        
        withAnimation(.spring(response: 0.3)) {
            showCopiedToast = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.spring(response: 0.3)) {
                showCopiedToast = false
            }
        }
    }
    
    private func openInBrowser(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }
}

// MARK: - Transaction Detail Row Component (Private to this file)

private struct TxDetailRow: View {
    let label: String
    let value: String
    var isMonospace: Bool = false
    var canCopy: Bool = false
    var onCopy: (() -> Void)? = nil
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            
            Spacer()
            
            HStack(spacing: 8) {
                Text(displayValue)
                    .font(isMonospace ? .system(.subheadline, design: .monospaced) : .subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                if canCopy {
                    Button {
                        onCopy?()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered ? 1 : 0.5)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isHovered ? Color.primary.opacity(0.03) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var displayValue: String {
        // Truncate long hashes for display
        if isMonospace && value.count > 20 {
            return "\(value.prefix(8))...\(value.suffix(8))"
        }
        return value
    }
}

// MARK: - Preview

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    TransactionDetailSheet(
        transaction: HawalaTransactionEntry(
            id: "bitcoin-testnet-abc123",
            type: "Receive",
            asset: "Bitcoin Testnet",
            amountDisplay: "+0.00123456 tBTC",
            status: "Confirmed",
            timestamp: "Dec 7, 2025 at 3:45 PM",
            sortTimestamp: Date().timeIntervalSince1970,
            txHash: "abc123def456789012345678901234567890abcdef123456789012345678901234",
            chainId: "bitcoin-testnet",
            confirmations: 12,
            fee: "0.00001234 tBTC",
            blockNumber: 2891234,
            counterparty: "tb1qv629dc9dm623hywx0wrfq3ezfm64yylhh87ty3"
        )
    )
}
#endif
#endif
#endif
