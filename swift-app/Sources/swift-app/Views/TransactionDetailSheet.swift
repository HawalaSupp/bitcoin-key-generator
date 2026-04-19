import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Transaction Detail Sheet

/// A detailed view for displaying all information about a single transaction — Hawala glass design
struct TransactionDetailSheet: View {
    let transaction: HawalaTransactionEntry
    var onRetryTransaction: ((HawalaTransactionEntry) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showCopiedToast = false

    var body: some View {
        HawalaSheetShell(title: "Transaction Details", width: 480, height: 600) {
            transactionHeader
            statusSection
            detailsCard

            if transaction.status.lowercased() == "failed" {
                failedExplanationSection
            }

            actionsSection
        }
        .overlay(alignment: .bottom) {
            if showCopiedToast {
                copiedToastView
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Header

    private var transactionHeader: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(typeColor.opacity(0.12))
                    .frame(width: 64, height: 64)

                Image(systemName: typeIcon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(typeColor)
            }

            VStack(spacing: 4) {
                Text(transaction.amountDisplay)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(amountColor)

                Text(transaction.asset)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
            }

            Text(transaction.type)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(typeColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(typeColor.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.bottom, 4)
    }

    // MARK: - Status Section

    private var statusSection: some View {
        HStack(spacing: 8) {
            Image(systemName: statusIcon)
                .font(.system(size: 12))
                .foregroundColor(statusColor)

            Text(transaction.status)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(statusColor)

            if let confirmations = transaction.confirmationsDisplay {
                Circle()
                    .fill(.white.opacity(0.15))
                    .frame(width: 3, height: 3)
                Text(confirmations)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(statusColor.opacity(0.1))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(statusColor.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Details Card

    private var detailsCard: some View {
        VStack(spacing: 0) {
            if let hash = transaction.txHash {
                TxDetailRow(label: "Transaction Hash", value: hash, isMonospace: true, canCopy: true, onCopy: { copyToClipboard(hash) })
                rowDivider
            }

            TxDetailRow(label: "Date", value: transaction.timestamp, isMonospace: false, canCopy: false)
            rowDivider

            if let chainId = transaction.chainId {
                TxDetailRow(label: "Network", value: networkName(for: chainId), isMonospace: false, canCopy: false)
                rowDivider
            }

            if let providerName = transaction.providerName {
                TxDetailRow(label: "Provider", value: providerName, isMonospace: false, canCopy: false)
                rowDivider
            }

            if let blockNumber = transaction.blockNumber {
                TxDetailRow(label: "Block Number", value: "\(blockNumber)", isMonospace: true, canCopy: true, onCopy: { copyToClipboard("\(blockNumber)") })
                rowDivider
            }

            if let fee = transaction.fee {
                TxDetailRow(label: "Transaction Fee", value: fee, isMonospace: false, canCopy: false)
                rowDivider
            }

            if let confirmations = transaction.confirmations {
                TxDetailRow(label: "Confirmations", value: confirmations >= 6 ? "6+ (Final)" : "\(confirmations)", isMonospace: false, canCopy: false)
            }

            if let counterparty = transaction.counterparty, !counterparty.isEmpty {
                rowDivider
                TxDetailRow(label: transaction.type == "Send" ? "Recipient" : (transaction.type == "Bridge" ? "Route" : "Sender"), value: counterparty, isMonospace: true, canCopy: true, onCopy: { copyToClipboard(counterparty) })
            }

            if let destinationTxHash = transaction.secondaryTxHash {
                rowDivider
                TxDetailRow(label: "Destination Hash", value: destinationTxHash, isMonospace: true, canCopy: true, onCopy: { copyToClipboard(destinationTxHash) })
            }

            if let note = transaction.detailNote, !note.isEmpty {
                rowDivider
                TxDetailRow(label: "Bridge Notes", value: note, isMonospace: false, canCopy: false)
            }
        }
        .hawalaSectionCard()
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.04))
            .frame(height: 1)
            .padding(.horizontal, 12)
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 10) {
            if let explorerURL = transaction.explorerURL {
                actionRow(icon: "safari", label: "View on \(explorerName)", trailing: "arrow.up.right.square", tint: Color.white.opacity(0.5)) {
                    openInBrowser(explorerURL)
                }
            }

            if let destinationURL = transaction.secondaryExplorerURL {
                actionRow(icon: "point.3.connected.trianglepath.dotted", label: "View Destination on \(secondaryExplorerName)", trailing: "arrow.up.right.square", tint: .blue) {
                    openInBrowser(destinationURL)
                }
            }

            if let title = transaction.externalActionTitle, let url = transaction.externalActionURL {
                actionRow(icon: "link", label: title, trailing: "arrow.up.right.square", tint: .purple) {
                    openInBrowser(url)
                }
            }

            if let hash = transaction.txHash {
                actionRow(icon: "doc.on.doc", label: "Copy Transaction Hash", tint: .white.opacity(0.6)) {
                    copyToClipboard(hash)
                }
            }

            if transaction.status.lowercased() == "failed", let onRetry = onRetryTransaction {
                actionRow(icon: "arrow.counterclockwise", label: "Retry Transaction", trailing: "arrow.right", tint: Color(red: 1, green: 0.84, blue: 0.04)) {
                    dismiss()
                    onRetry(transaction)
                }
                .accessibilityIdentifier("retry_transaction_button")
            }
        }
    }

    private func actionRow(icon: String, label: String, trailing: String? = nil, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                if let trailing {
                    Image(systemName: trailing)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.25))
                }
            }
            .foregroundColor(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(tint.opacity(0.08))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(tint.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: explanation.icon)
                            .font(.system(size: 16))
                            .foregroundColor(Color(red: 1, green: 0.27, blue: 0.23))
                        Text(explanation.reason)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                    }

                    Text(explanation.explanation)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Color(red: 1, green: 0.84, blue: 0.04))
                        Text(explanation.suggestion)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.top, 2)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 1, green: 0.27, blue: 0.23).opacity(0.08))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color(red: 1, green: 0.27, blue: 0.23).opacity(0.15), lineWidth: 1)
                )
                .accessibilityIdentifier("failed_transaction_explanation")
            }
        }
    }

    // MARK: - Toast View

    private var copiedToastView: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color(red: 0.20, green: 0.84, blue: 0.29))
            Text("Copied to clipboard")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 0.10, green: 0.10, blue: 0.12).opacity(0.95))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        .padding(.bottom, 16)
    }
    
    // MARK: - Helpers
    
    private var typeIcon: String {
        switch transaction.type.lowercased() {
        case "receive": return "arrow.down.left"
        case "send": return "arrow.up.right"
        case "swap": return "arrow.triangle.2.circlepath"
        case "bridge": return "point.3.connected.trianglepath.dotted"
        default: return "arrow.left.arrow.right"
        }
    }
    
    private var typeColor: Color {
        switch transaction.type.lowercased() {
        case "receive": return Color(red: 0.20, green: 0.84, blue: 0.29)
        case "send": return Color(red: 1, green: 0.27, blue: 0.23)
        case "swap": return Color.white.opacity(0.5)
        case "bridge": return Color.white.opacity(0.5)
        default: return .white.opacity(0.5)
        }
    }
    
    private var amountColor: Color {
        transaction.amountDisplay.hasPrefix("+") ? Color(red: 0.20, green: 0.84, blue: 0.29) :
        transaction.amountDisplay.hasPrefix("-") ? .white.opacity(0.85) : .white.opacity(0.85)
    }
    
    private var statusIcon: String {
        switch transaction.status.lowercased() {
        case "confirmed": return "checkmark.circle.fill"
        case "pending": return "clock"
        case "processing": return "arrow.triangle.2.circlepath"
        case "failed": return "xmark.circle.fill"
        case "refunded": return "arrow.uturn.backward.circle.fill"
        default: return "questionmark.circle"
        }
    }
    
    private var statusColor: Color {
        switch transaction.status.lowercased() {
        case "confirmed": return Color(red: 0.20, green: 0.84, blue: 0.29)
        case "pending": return Color(red: 1, green: 0.84, blue: 0.04)
        case "processing": return Color.white.opacity(0.5)
        case "failed": return Color(red: 1, green: 0.27, blue: 0.23)
        case "refunded": return .purple
        default: return .white.opacity(0.5)
        }
    }
    
    private var explorerName: String {
        guard let chainId = transaction.chainId else { return "Explorer" }
        
        switch chainId {
        case "bitcoin", "bitcoin-testnet": return "Mempool"
        case "litecoin": return "Blockchair"
        case "ethereum", "ethereum-sepolia": return "Etherscan"
        case "bnb", "bsc": return "BscScan"
        case "polygon": return "PolygonScan"
        case "arbitrum": return "Arbiscan"
        case "optimism": return "Optimism Explorer"
        case "avalanche": return "Snowtrace"
        case "base": return "BaseScan"
        case "fantom": return "FTMScan"
        case "solana": return "Solscan"
        case "xrp", "xrp-testnet": return "XRPScan"
        default: return "Explorer"
        }
    }

    private var secondaryExplorerName: String {
        guard let chainId = transaction.secondaryChainId else { return "Explorer" }
        return explorerName(for: chainId)
    }

    private func explorerName(for chainId: String) -> String {
        switch chainId {
        case "bitcoin", "bitcoin-testnet": return "Mempool"
        case "litecoin": return "Blockchair"
        case "ethereum", "ethereum-sepolia": return "Etherscan"
        case "bnb", "bsc": return "BscScan"
        case "polygon": return "PolygonScan"
        case "arbitrum": return "Arbiscan"
        case "optimism": return "Optimism Explorer"
        case "avalanche": return "Snowtrace"
        case "base": return "BaseScan"
        case "fantom": return "FTMScan"
        case "solana", "solana-devnet": return "Solscan"
        case "xrp", "xrp-testnet": return "XRPScan"
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
        case "bnb", "bsc": return "BNB Chain"
        case "polygon": return "Polygon"
        case "arbitrum": return "Arbitrum"
        case "optimism": return "Optimism"
        case "avalanche": return "Avalanche"
        case "base": return "Base"
        case "fantom": return "Fantom"
        case "solana", "solana-devnet": return "Solana"
        case "xrp", "xrp-testnet": return "XRP Ledger"
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
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 120, alignment: .leading)

            Spacer()

            HStack(spacing: 8) {
                Text(displayValue)
                    .font(isMonospace ? .system(size: 12, weight: .regular, design: .monospaced) : .system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if canCopy {
                    Button {
                        onCopy?()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(isHovered ? 0.5 : 0.2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isHovered ? Color.white.opacity(0.02) : Color.clear)
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
