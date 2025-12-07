import SwiftUI
import Foundation

// MARK: - Batch Transaction Models

/// A single recipient in a batch transaction
struct BatchRecipient: Identifiable, Codable, Equatable {
    let id: UUID
    var address: String
    var amount: String
    var label: String?
    var isValid: Bool
    var validationError: String?
    
    init(id: UUID = UUID(), address: String = "", amount: String = "", label: String? = nil) {
        self.id = id
        self.address = address
        self.amount = amount
        self.label = label
        self.isValid = false
        self.validationError = nil
    }
    
    var amountDouble: Double {
        Double(amount) ?? 0
    }
}

/// Supported chains for batch transactions
enum BatchChain: String, CaseIterable, Identifiable {
    case bitcoin = "bitcoin"
    case ethereum = "ethereum"
    case bnb = "bnb"
    case solana = "solana"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .bitcoin: return "Bitcoin"
        case .ethereum: return "Ethereum"
        case .bnb: return "BNB Chain"
        case .solana: return "Solana"
        }
    }
    
    var symbol: String {
        switch self {
        case .bitcoin: return "BTC"
        case .ethereum: return "ETH"
        case .bnb: return "BNB"
        case .solana: return "SOL"
        }
    }
    
    var color: Color {
        switch self {
        case .bitcoin: return HawalaTheme.Colors.bitcoin
        case .ethereum: return HawalaTheme.Colors.ethereum
        case .bnb: return HawalaTheme.Colors.bnb
        case .solana: return HawalaTheme.Colors.solana
        }
    }
    
    var icon: String {
        switch self {
        case .bitcoin: return "bitcoinsign.circle.fill"
        case .ethereum: return "diamond.fill"
        case .bnb: return "b.circle.fill"
        case .solana: return "sun.max.fill"
        }
    }
    
    var supportsBatching: Bool {
        switch self {
        case .ethereum, .bnb: return true // Native batching via smart contract or multiple txs
        case .bitcoin, .solana: return true // Can send to multiple outputs/accounts
        }
    }
}

// MARK: - Batch Transaction Manager

@MainActor
final class BatchTransactionManager: ObservableObject {
    static let shared = BatchTransactionManager()
    
    @Published var recipients: [BatchRecipient] = [BatchRecipient()]
    @Published var selectedChain: BatchChain = .ethereum
    @Published var isProcessing = false
    @Published var error: String?
    @Published var successCount = 0
    @Published var failedCount = 0
    
    private init() {}
    
    // MARK: - Recipient Management
    
    func addRecipient() {
        recipients.append(BatchRecipient())
    }
    
    func removeRecipient(_ recipient: BatchRecipient) {
        recipients.removeAll { $0.id == recipient.id }
        if recipients.isEmpty {
            recipients.append(BatchRecipient())
        }
    }
    
    func updateRecipient(_ recipient: BatchRecipient) {
        if let index = recipients.firstIndex(where: { $0.id == recipient.id }) {
            var updated = recipient
            updated.isValid = validateRecipient(updated)
            recipients[index] = updated
        }
    }
    
    func clearAll() {
        recipients = [BatchRecipient()]
        error = nil
        successCount = 0
        failedCount = 0
    }
    
    // MARK: - Validation
    
    func validateRecipient(_ recipient: BatchRecipient) -> Bool {
        guard !recipient.address.isEmpty else { return false }
        guard recipient.amountDouble > 0 else { return false }
        return validateAddress(recipient.address, chain: selectedChain)
    }
    
    func validateAddress(_ address: String, chain: BatchChain) -> Bool {
        switch chain {
        case .bitcoin:
            // Basic Bitcoin address validation
            return address.hasPrefix("1") || address.hasPrefix("3") || address.hasPrefix("bc1") || address.hasPrefix("tb1")
        case .ethereum, .bnb:
            // Ethereum/BNB address validation
            let pattern = "^0x[a-fA-F0-9]{40}$"
            return address.range(of: pattern, options: .regularExpression) != nil
        case .solana:
            // Solana address validation (base58, 32-44 chars)
            let base58Chars = CharacterSet(charactersIn: "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
            return address.count >= 32 && address.count <= 44 && address.unicodeScalars.allSatisfy { base58Chars.contains($0) }
        }
    }
    
    var totalAmount: Double {
        recipients.reduce(0) { $0 + $1.amountDouble }
    }
    
    var validRecipientsCount: Int {
        recipients.filter { $0.isValid }.count
    }
    
    var canExecute: Bool {
        validRecipientsCount > 0 && !isProcessing
    }
    
    // MARK: - CSV Import
    
    func importFromCSV(_ csvContent: String) {
        let lines = csvContent.components(separatedBy: .newlines)
        var imported: [BatchRecipient] = []
        
        for line in lines {
            let parts = line.components(separatedBy: ",")
            guard parts.count >= 2 else { continue }
            
            let address = parts[0].trimmingCharacters(in: .whitespaces)
            let amount = parts[1].trimmingCharacters(in: .whitespaces)
            let label = parts.count > 2 ? parts[2].trimmingCharacters(in: .whitespaces) : nil
            
            guard !address.isEmpty, !amount.isEmpty else { continue }
            
            var recipient = BatchRecipient(address: address, amount: amount, label: label)
            recipient.isValid = validateRecipient(recipient)
            imported.append(recipient)
        }
        
        if !imported.isEmpty {
            recipients = imported
        }
    }
    
    // MARK: - Export Template
    
    func exportTemplate() -> String {
        """
        # Batch Transaction CSV Template
        # Format: address,amount,label (optional)
        # Example:
        0x1234567890abcdef1234567890abcdef12345678,0.1,Payment 1
        0xabcdef1234567890abcdef1234567890abcdef12,0.25,Payment 2
        """
    }
}

// MARK: - Batch Transaction View

struct BatchTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = BatchTransactionManager.shared
    @State private var showImportSheet = false
    @State private var showConfirmation = false
    @State private var csvContent = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
                .background(HawalaTheme.Colors.border)
            
            // Chain selector
            chainSelector
                .padding(HawalaTheme.Spacing.lg)
            
            // Recipients list
            ScrollView {
                VStack(spacing: HawalaTheme.Spacing.md) {
                    ForEach(manager.recipients) { recipient in
                        RecipientRow(recipient: recipient, chain: manager.selectedChain)
                    }
                    
                    // Add recipient button
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            manager.addRecipient()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Recipient")
                        }
                        .font(HawalaTheme.Typography.body)
                        .foregroundColor(HawalaTheme.Colors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(HawalaTheme.Spacing.md)
                        .background(HawalaTheme.Colors.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                                .strokeBorder(HawalaTheme.Colors.accent.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5]))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(HawalaTheme.Spacing.lg)
            }
            
            Divider()
                .background(HawalaTheme.Colors.border)
            
            // Summary & Actions
            summary
        }
        .frame(width: 600, height: 700)
        .background(HawalaTheme.Colors.background)
        .sheet(isPresented: $showImportSheet) {
            CSVImportSheet(csvContent: $csvContent) {
                manager.importFromCSV(csvContent)
                showImportSheet = false
            }
        }
        .alert("Confirm Batch Transaction", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Send") {
                // Execute batch transaction
                ToastManager.shared.info("Batch transaction feature coming soon")
            }
        } message: {
            Text("Send \(String(format: "%.6f", manager.totalAmount)) \(manager.selectedChain.symbol) to \(manager.validRecipientsCount) recipients?")
        }
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Batch Transaction")
                    .font(HawalaTheme.Typography.h3)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text("Send to multiple addresses at once")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            
            Spacer()
            
            // Import CSV
            Button {
                showImportSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                    Text("Import CSV")
                }
                .font(HawalaTheme.Typography.caption)
                .padding(.horizontal, HawalaTheme.Spacing.md)
                .padding(.vertical, HawalaTheme.Spacing.sm)
                .background(HawalaTheme.Colors.backgroundTertiary)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm))
            }
            .buttonStyle(.plain)
            
            // Clear all
            Button {
                manager.clearAll()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundColor(HawalaTheme.Colors.error)
                    .frame(width: 32, height: 32)
                    .background(HawalaTheme.Colors.error.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Clear all recipients")
            
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(HawalaTheme.Spacing.lg)
    }
    
    private var chainSelector: some View {
        HStack(spacing: HawalaTheme.Spacing.sm) {
            ForEach(BatchChain.allCases) { chain in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        manager.selectedChain = chain
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: chain.icon)
                            .font(.system(size: 14))
                        Text(chain.symbol)
                            .font(HawalaTheme.Typography.captionBold)
                    }
                    .padding(.horizontal, HawalaTheme.Spacing.md)
                    .padding(.vertical, HawalaTheme.Spacing.sm)
                    .background(manager.selectedChain == chain ? chain.color.opacity(0.2) : HawalaTheme.Colors.backgroundTertiary)
                    .foregroundColor(manager.selectedChain == chain ? chain.color : HawalaTheme.Colors.textSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm)
                            .strokeBorder(manager.selectedChain == chain ? chain.color : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
    }
    
    private var summary: some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            // Stats
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recipients")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                    Text("\(manager.validRecipientsCount) of \(manager.recipients.count)")
                        .font(HawalaTheme.Typography.h4)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Total Amount")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                    Text("\(String(format: "%.6f", manager.totalAmount)) \(manager.selectedChain.symbol)")
                        .font(HawalaTheme.Typography.h4)
                        .foregroundColor(manager.selectedChain.color)
                }
            }
            
            // Send button
            Button {
                showConfirmation = true
            } label: {
                HStack {
                    if manager.isProcessing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                    Text(manager.isProcessing ? "Processing..." : "Send Batch Transaction")
                }
                .font(HawalaTheme.Typography.body)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(HawalaTheme.Spacing.md)
                .background(manager.canExecute ? manager.selectedChain.color : HawalaTheme.Colors.textTertiary)
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
            }
            .buttonStyle(.plain)
            .disabled(!manager.canExecute)
        }
        .padding(HawalaTheme.Spacing.lg)
        .background(HawalaTheme.Colors.backgroundSecondary)
    }
}

// MARK: - Recipient Row

struct RecipientRow: View {
    let recipient: BatchRecipient
    let chain: BatchChain
    @ObservedObject private var manager = BatchTransactionManager.shared
    
    @State private var address: String
    @State private var amount: String
    @State private var label: String
    @State private var isHovered = false
    
    init(recipient: BatchRecipient, chain: BatchChain) {
        self.recipient = recipient
        self.chain = chain
        _address = State(initialValue: recipient.address)
        _amount = State(initialValue: recipient.amount)
        _label = State(initialValue: recipient.label ?? "")
    }
    
    var body: some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            // Validation indicator
            Circle()
                .fill(recipient.isValid ? HawalaTheme.Colors.success : HawalaTheme.Colors.error.opacity(0.5))
                .frame(width: 8, height: 8)
            
            VStack(spacing: HawalaTheme.Spacing.sm) {
                // Address field
                HStack {
                    Image(systemName: "location.fill")
                        .font(.system(size: 12))
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                    
                    TextField("Recipient address", text: $address)
                        .textFieldStyle(.plain)
                        .font(HawalaTheme.Typography.mono)
                        .onChange(of: address) { newValue in
                            var updated = recipient
                            updated.address = newValue
                            manager.updateRecipient(updated)
                        }
                }
                .padding(HawalaTheme.Spacing.sm)
                .background(HawalaTheme.Colors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm))
                
                HStack(spacing: HawalaTheme.Spacing.sm) {
                    // Amount field
                    HStack {
                        TextField("0.0", text: $amount)
                            .textFieldStyle(.plain)
                            .font(HawalaTheme.Typography.body)
                            .onChange(of: amount) { newValue in
                                var updated = recipient
                                updated.amount = newValue
                                manager.updateRecipient(updated)
                            }
                        
                        Text(chain.symbol)
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                    }
                    .padding(HawalaTheme.Spacing.sm)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm))
                    .frame(width: 150)
                    
                    // Label field (optional)
                    HStack {
                        Image(systemName: "tag")
                            .font(.system(size: 10))
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                        
                        TextField("Label (optional)", text: $label)
                            .textFieldStyle(.plain)
                            .font(HawalaTheme.Typography.caption)
                            .onChange(of: label) { newValue in
                                var updated = recipient
                                updated.label = newValue.isEmpty ? nil : newValue
                                manager.updateRecipient(updated)
                            }
                    }
                    .padding(HawalaTheme.Spacing.sm)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm))
                }
            }
            
            // Delete button
            if isHovered && manager.recipients.count > 1 {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        manager.removeRecipient(recipient)
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(HawalaTheme.Colors.error)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(HawalaTheme.Spacing.md)
        .background(isHovered ? HawalaTheme.Colors.backgroundHover : HawalaTheme.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                .strokeBorder(recipient.isValid ? Color.clear : HawalaTheme.Colors.error.opacity(0.3), lineWidth: 1)
        )
        .onHover { isHovered = $0 }
    }
}

// MARK: - CSV Import Sheet

struct CSVImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var csvContent: String
    let onImport: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Import from CSV")
                    .font(HawalaTheme.Typography.h3)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(HawalaTheme.Colors.backgroundTertiary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(HawalaTheme.Spacing.lg)
            
            Divider()
                .background(HawalaTheme.Colors.border)
            
            // Instructions
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                Text("CSV Format")
                    .font(HawalaTheme.Typography.captionBold)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                
                Text("Each line: address,amount,label (optional)")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                
                Text("Example:")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                    .padding(.top, 4)
                
                Text("0x1234...5678,0.1,Payment 1\n0xabcd...ef12,0.25,Payment 2")
                    .font(HawalaTheme.Typography.mono)
                    .foregroundColor(HawalaTheme.Colors.accent)
                    .padding(HawalaTheme.Spacing.sm)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HawalaTheme.Spacing.lg)
            
            // Text editor
            TextEditor(text: $csvContent)
                .font(HawalaTheme.Typography.mono)
                .padding(HawalaTheme.Spacing.sm)
                .background(HawalaTheme.Colors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                .padding(.horizontal, HawalaTheme.Spacing.lg)
                .frame(minHeight: 200)
            
            Divider()
                .background(HawalaTheme.Colors.border)
                .padding(.top, HawalaTheme.Spacing.lg)
            
            // Actions
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
                
                Spacer()
                
                Button {
                    onImport()
                } label: {
                    Text("Import")
                        .padding(.horizontal, HawalaTheme.Spacing.xl)
                }
                .buttonStyle(.borderedProminent)
                .tint(HawalaTheme.Colors.accent)
                .disabled(csvContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(HawalaTheme.Spacing.lg)
        }
        .frame(width: 450, height: 500)
        .background(HawalaTheme.Colors.background)
    }
}

// MARK: - Preview

#if DEBUG
struct BatchTransactionView_Previews: PreviewProvider {
    static var previews: some View {
        BatchTransactionView()
            .preferredColorScheme(.dark)
    }
}
#endif
