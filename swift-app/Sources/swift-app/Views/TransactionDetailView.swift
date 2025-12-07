import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Transaction Detail View Modern

struct TransactionDetailViewModern: View {
    @Environment(\.dismiss) private var dismiss
    let transaction: TransactionDisplayItem
    
    @State private var showCopiedToast = false
    @State private var copiedText = ""
    @State private var appearAnimation = false
    
    var body: some View {
        ZStack {
            // Background
            HawalaTheme.Colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                detailHeader
                
                // Content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: HawalaTheme.Spacing.lg) {
                        // Status Hero
                        statusHeroSection
                        
                        // Amount Section
                        amountSection
                        
                        // Addresses Section
                        addressesSection
                        
                        // Transaction Details
                        transactionDetailsSection
                        
                        // Actions
                        actionsSection
                    }
                    .padding(.horizontal, HawalaTheme.Spacing.lg)
                    .padding(.top, HawalaTheme.Spacing.md)
                    .padding(.bottom, HawalaTheme.Spacing.xxl)
                }
            }
            
            // Copied Toast
            if showCopiedToast {
                VStack {
                    Spacer()
                    toastView
                        .padding(.bottom, 40)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(HawalaTheme.Animation.spring) {
                appearAnimation = true
            }
        }
    }
    
    // MARK: - Header
    
    private var detailHeader: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Text("Transaction Details")
                .font(HawalaTheme.Typography.h3)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
            
            Spacer()
            
            // Share Button
            Button(action: shareTransaction) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, HawalaTheme.Spacing.lg)
        .padding(.vertical, HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.background)
    }
    
    // MARK: - Status Hero Section
    
    private var statusHeroSection: some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            // Status Icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 80, height: 80)
                
                Image(systemName: statusIcon)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(statusColor)
            }
            
            // Status Text
            Text(statusText)
                .font(HawalaTheme.Typography.h2)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
            
            // Chain Badge
            HStack(spacing: 6) {
                Circle()
                    .fill(HawalaTheme.Colors.forChain(transaction.chainId))
                    .frame(width: 8, height: 8)
                Text(transaction.chainName)
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(HawalaTheme.Colors.backgroundTertiary)
            .clipShape(Capsule())
            
            // Confirmations
            if transaction.status == .confirmed && transaction.confirmations > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.caption)
                    Text("\(transaction.confirmations) confirmations")
                        .font(HawalaTheme.Typography.caption)
                }
                .foregroundColor(HawalaTheme.Colors.success)
            } else if transaction.status == .pending {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(HawalaTheme.Colors.warning)
                    Text("Waiting for confirmation...")
                        .font(HawalaTheme.Typography.caption)
                }
                .foregroundColor(HawalaTheme.Colors.warning)
            }
        }
        .padding(.vertical, HawalaTheme.Spacing.lg)
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
    }
    
    // MARK: - Amount Section
    
    private var amountSection: some View {
        VStack(spacing: HawalaTheme.Spacing.sm) {
            // Amount
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(transaction.type == .receive ? "+" : "-")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(amountColor)
                
                Text(transaction.formattedAmount)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text(transaction.symbol)
                    .font(HawalaTheme.Typography.h3)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
            }
            
            // Fee
            if let fee = transaction.fee, fee > 0 {
                HStack(spacing: 4) {
                    Text("Network Fee:")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                    Text(String(format: "%.8f %@", fee, transaction.symbol))
                        .font(HawalaTheme.Typography.mono)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(HawalaTheme.Spacing.lg)
        .background(HawalaTheme.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous))
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
        .animation(HawalaTheme.Animation.spring.delay(0.05), value: appearAnimation)
    }
    
    // MARK: - Addresses Section
    
    private var addressesSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            // From Address
            if let from = transaction.fromAddress {
                AddressRow(
                    label: "From",
                    address: from,
                    isHighlighted: transaction.type == .receive,
                    onCopy: { copyToClipboard(from, label: "From address") }
                )
            }
            
            // Arrow
            HStack {
                Spacer()
                Image(systemName: "arrow.down")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                    .padding(.vertical, HawalaTheme.Spacing.sm)
                Spacer()
            }
            
            // To Address
            if let to = transaction.toAddress {
                AddressRow(
                    label: "To",
                    address: to,
                    isHighlighted: transaction.type == .send,
                    onCopy: { copyToClipboard(to, label: "To address") }
                )
            }
        }
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous))
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
        .animation(HawalaTheme.Animation.spring.delay(0.1), value: appearAnimation)
    }
    
    // MARK: - Transaction Details Section
    
    private var transactionDetailsSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            Text("DETAILS")
                .font(HawalaTheme.Typography.label)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
                .tracking(1)
            
            VStack(spacing: 0) {
                // Transaction Hash
                DetailRow(
                    label: "Transaction ID",
                    value: truncateHash(transaction.txHash),
                    isCopyable: true,
                    onCopy: { copyToClipboard(transaction.txHash, label: "Transaction ID") }
                )
                
                Divider()
                    .background(HawalaTheme.Colors.border)
                
                // Status
                DetailRow(label: "Status", value: statusText, valueColor: statusColor)
                
                Divider()
                    .background(HawalaTheme.Colors.border)
                
                // Timestamp
                if let timestamp = transaction.timestamp {
                    DetailRow(label: "Time", value: formatTimestamp(timestamp))
                    
                    Divider()
                        .background(HawalaTheme.Colors.border)
                }
                
                // Block Height
                if let block = transaction.blockHeight {
                    DetailRow(label: "Block", value: "#\(block.formatted())")
                    
                    Divider()
                        .background(HawalaTheme.Colors.border)
                }
                
                // Confirmations
                DetailRow(label: "Confirmations", value: "\(transaction.confirmations)")
            }
            .padding(HawalaTheme.Spacing.md)
            .background(HawalaTheme.Colors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
            
            // Note
            if let note = transaction.note, !note.isEmpty {
                VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                    Text("NOTE")
                        .font(HawalaTheme.Typography.label)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                        .tracking(1)
                    
                    Text(note)
                        .font(HawalaTheme.Typography.body)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                        .padding(HawalaTheme.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(HawalaTheme.Colors.backgroundTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
                }
            }
        }
        .hawalaCard()
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
        .animation(HawalaTheme.Animation.spring.delay(0.15), value: appearAnimation)
    }
    
    // MARK: - Actions Section
    
    private var actionsSection: some View {
        VStack(spacing: HawalaTheme.Spacing.sm) {
            // View on Explorer
            Button(action: openExplorer) {
                HStack(spacing: HawalaTheme.Spacing.sm) {
                    Image(systemName: "arrow.up.right.square")
                    Text("View on Block Explorer")
                        .font(HawalaTheme.Typography.h4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, HawalaTheme.Spacing.md)
                .background(HawalaTheme.Colors.accent)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            
            // Copy Transaction ID
            Button(action: { copyToClipboard(transaction.txHash, label: "Transaction ID") }) {
                HStack(spacing: HawalaTheme.Spacing.sm) {
                    Image(systemName: "doc.on.doc")
                    Text("Copy Transaction ID")
                        .font(HawalaTheme.Typography.body)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, HawalaTheme.Spacing.md)
                .background(HawalaTheme.Colors.backgroundTertiary)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous)
                        .strokeBorder(HawalaTheme.Colors.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
        .animation(HawalaTheme.Animation.spring.delay(0.2), value: appearAnimation)
    }
    
    // MARK: - Toast
    
    private var toastView: some View {
        HStack(spacing: HawalaTheme.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(HawalaTheme.Colors.success)
            
            Text(copiedText)
                .font(HawalaTheme.Typography.body)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
        }
        .padding(.horizontal, HawalaTheme.Spacing.lg)
        .padding(.vertical, HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.backgroundSecondary)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
    }
    
    // MARK: - Computed Properties
    
    private var statusIcon: String {
        switch transaction.status {
        case .pending: return "clock"
        case .confirmed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch transaction.status {
        case .pending: return HawalaTheme.Colors.warning
        case .confirmed: return HawalaTheme.Colors.success
        case .failed: return HawalaTheme.Colors.error
        }
    }
    
    private var statusText: String {
        switch transaction.status {
        case .pending: return "Pending"
        case .confirmed: return "Confirmed"
        case .failed: return "Failed"
        }
    }
    
    private var amountColor: Color {
        transaction.type == .receive ? HawalaTheme.Colors.success : HawalaTheme.Colors.error
    }
    
    // MARK: - Helper Functions
    
    private func truncateHash(_ hash: String) -> String {
        guard hash.count > 20 else { return hash }
        return "\(hash.prefix(10))...\(hash.suffix(8))"
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    private func copyToClipboard(_ text: String, label: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        showToast("\(label) copied!")
    }
    
    private func showToast(_ text: String) {
        copiedText = text
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showCopiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showCopiedToast = false
            }
        }
    }
    
    private func openExplorer() {
        let urlString: String
        switch transaction.chainId.lowercased() {
        case "bitcoin": urlString = "https://mempool.space/tx/\(transaction.txHash)"
        case "bitcoin-testnet": urlString = "https://mempool.space/testnet/tx/\(transaction.txHash)"
        case "ethereum": urlString = "https://etherscan.io/tx/\(transaction.txHash)"
        case "ethereum-sepolia": urlString = "https://sepolia.etherscan.io/tx/\(transaction.txHash)"
        case "litecoin": urlString = "https://litecoinspace.org/tx/\(transaction.txHash)"
        case "solana": urlString = "https://explorer.solana.com/tx/\(transaction.txHash)"
        case "xrp": urlString = "https://xrpscan.com/tx/\(transaction.txHash)"
        default: urlString = "https://blockchair.com/search?q=\(transaction.txHash)"
        }
        
        if let url = URL(string: urlString) {
            #if canImport(AppKit)
            NSWorkspace.shared.open(url)
            #endif
        }
    }
    
    private func shareTransaction() {
        #if canImport(AppKit)
        let shareText = """
        Transaction Details
        
        Type: \(transaction.type == .receive ? "Received" : "Sent")
        Amount: \(transaction.formattedAmount) \(transaction.symbol)
        Status: \(statusText)
        Chain: \(transaction.chainName)
        TX ID: \(transaction.txHash)
        """
        
        let picker = NSSharingServicePicker(items: [shareText])
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
        #endif
    }
}

// MARK: - Address Row

struct AddressRow: View {
    let label: String
    let address: String
    let isHighlighted: Bool
    let onCopy: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.xs) {
            Text(label)
                .font(HawalaTheme.Typography.label)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
            
            HStack {
                Text(address)
                    .font(HawalaTheme.Typography.mono)
                    .foregroundColor(isHighlighted ? HawalaTheme.Colors.accent : HawalaTheme.Colors.textPrimary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                
                Spacer()
                
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(HawalaTheme.Colors.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(HawalaTheme.Spacing.sm)
            .background(HawalaTheme.Colors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm, style: .continuous))
        }
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let label: String
    let value: String
    var valueColor: Color = HawalaTheme.Colors.textPrimary
    var isCopyable: Bool = false
    var onCopy: (() -> Void)? = nil
    
    var body: some View {
        HStack {
            Text(label)
                .font(HawalaTheme.Typography.bodySmall)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
            
            Spacer()
            
            HStack(spacing: HawalaTheme.Spacing.xs) {
                Text(value)
                    .font(HawalaTheme.Typography.mono)
                    .foregroundColor(valueColor)
                    .lineLimit(1)
                
                if isCopyable, let onCopy = onCopy {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundColor(HawalaTheme.Colors.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, HawalaTheme.Spacing.sm)
    }
}
