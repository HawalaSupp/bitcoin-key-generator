import SwiftUI

// MARK: - Transaction Preview View
/// Displays decoded transaction with warnings and risk assessment

struct TransactionPreviewView: View {
    let decoded: DecodedTransaction
    let onApprove: () -> Void
    let onReject: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with risk indicator
            headerView
            
            Divider()
            
            ScrollView {
                VStack(spacing: 16) {
                    // Human-readable summary
                    summaryCard
                    
                    // Warnings section
                    if !decoded.warnings.isEmpty {
                        warningsSection
                    }
                    
                    // Contract info
                    contractInfoCard
                    
                    // Technical details (collapsible)
                    technicalDetailsCard
                }
                .padding()
            }
            
            Divider()
            
            // Action buttons
            actionButtons
        }
        .frame(minWidth: 400, minHeight: 500)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Transaction Preview")
                    .font(.headline)
                Text(decoded.methodName.isEmpty ? "Unknown" : decoded.methodName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            riskBadge
        }
        .padding()
        .background(headerBackground)
    }
    
    private var headerBackground: Color {
        switch decoded.riskLevel {
        case .low: return Color.green.opacity(0.1)
        case .medium: return Color.yellow.opacity(0.1)
        case .high: return Color.orange.opacity(0.1)
        case .critical: return Color.red.opacity(0.1)
        }
    }
    
    private var riskBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: riskIcon)
            Text(decoded.riskLevel.rawValue)
                .font(.caption.bold())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(riskColor.opacity(0.2))
        .foregroundColor(riskColor)
        .cornerRadius(12)
    }
    
    private var riskIcon: String {
        switch decoded.riskLevel {
        case .low: return "checkmark.shield"
        case .medium: return "exclamationmark.shield"
        case .high: return "exclamationmark.triangle"
        case .critical: return "xmark.shield"
        }
    }
    
    private var riskColor: Color {
        switch decoded.riskLevel {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }
    
    // MARK: - Summary Card
    
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("What This Transaction Does", systemImage: "doc.text.magnifyingglass")
                .font(.headline)
            
            Text(decoded.humanReadable.isEmpty ? "Unable to decode transaction" : decoded.humanReadable)
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            
            if let value = decoded.nativeValue, Double(value) ?? 0 > 0 {
                HStack {
                    Image(systemName: "arrow.up.right")
                        .foregroundColor(.red)
                    Text("Sending: \(value) ETH")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.red)
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(12)
    }
    
    // MARK: - Warnings Section
    
    private var warningsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("⚠️ Warnings", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundColor(.orange)
            
            ForEach(decoded.warnings, id: \.rawValue) { warning in
                WarningRow(warning: warning)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Contract Info Card
    
    private var contractInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Contract Information", systemImage: "doc.badge.gearshape")
                .font(.headline)
            
            HStack {
                Text("Name:")
                    .foregroundColor(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Text(decoded.contractName ?? "Unknown")
                        .fontWeight(.medium)
                    if decoded.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.blue)
                    }
                }
            }
            
            if let contractType = decoded.contractType {
                HStack {
                    Text("Type:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(contractType.rawValue)
                        .fontWeight(.medium)
                }
            }
            
            HStack {
                Text("Verified:")
                    .foregroundColor(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: decoded.isVerified ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(decoded.isVerified ? .green : .red)
                    Text(decoded.isVerified ? "Yes" : "No")
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(12)
    }
    
    // MARK: - Technical Details
    
    @State private var showTechnicalDetails = false
    
    private var technicalDetailsCard: some View {
        DisclosureGroup(isExpanded: $showTechnicalDetails) {
            VStack(alignment: .leading, spacing: 8) {
                if !decoded.methodDescription.isEmpty {
                    TxDetailRow(label: "Method", value: decoded.methodDescription)
                }
                
                ForEach(Array(decoded.decodedParams.keys.sorted()), id: \.self) { key in
                    if let value = decoded.decodedParams[key] {
                        TxDetailRow(label: key.capitalized, value: "\(value)")
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Label("Technical Details", systemImage: "chevron.left.forwardslash.chevron.right")
                .font(.headline)
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(12)
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: onReject) {
                Label("Reject", systemImage: "xmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            
            Button(action: onApprove) {
                Label(approveButtonText, systemImage: approveButtonIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(approveButtonColor)
        }
        .padding()
    }
    
    private var approveButtonText: String {
        switch decoded.riskLevel {
        case .low: return "Approve"
        case .medium: return "Approve"
        case .high: return "Approve Anyway"
        case .critical: return "I Understand the Risk"
        }
    }
    
    private var approveButtonIcon: String {
        switch decoded.riskLevel {
        case .low: return "checkmark"
        case .medium: return "checkmark"
        case .high: return "exclamationmark.triangle"
        case .critical: return "exclamationmark.octagon"
        }
    }
    
    private var approveButtonColor: Color {
        switch decoded.riskLevel {
        case .low: return .green
        case .medium: return .blue
        case .high: return .orange
        case .critical: return .red
        }
    }
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(.windowBackgroundColor).opacity(0.5) : Color.white
    }
}

// MARK: - Warning Row

struct WarningRow: View {
    let warning: TransactionWarning
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(warning.icon)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(warning.rawValue)
                    .fontWeight(.medium)
                
                Text(warningExplanation)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            severityBadge
        }
        .padding(10)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(8)
    }
    
    private var warningExplanation: String {
        switch warning {
        case .unlimitedApproval:
            return "This contract can spend unlimited tokens from your wallet. Consider setting a specific limit."
        case .unverifiedContract:
            return "This contract's source code has not been verified. Proceed with caution."
        case .unknownMethod:
            return "We couldn't decode what this transaction does. Review carefully."
        case .highValue:
            return "This transaction involves a significant amount. Double-check the details."
        case .newContract:
            return "This contract was recently deployed. New contracts carry higher risk."
        }
    }
    
    private var severityBadge: some View {
        Text(warning.severity.rawValue)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(severityColor.opacity(0.2))
            .foregroundColor(severityColor)
            .cornerRadius(4)
    }
    
    private var severityColor: Color {
        switch warning.severity {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }
}

// MARK: - Detail Row

struct TxDetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Balance Change Row

struct BalanceChangeRow: View {
    let change: BalanceChange
    
    var body: some View {
        HStack {
            Image(systemName: change.isPositive ? "arrow.down.left" : "arrow.up.right")
                .foregroundColor(change.isPositive ? .green : .red)
            
            Text(change.asset)
                .fontWeight(.medium)
            
            Spacer()
            
            Text(change.amount)
                .fontWeight(.semibold)
                .foregroundColor(change.isPositive ? .green : .red)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    let decoded = DecodedTransaction(
        methodName: "approve",
        methodDescription: "Approve token spending",
        humanReadable: "⚠️ UNLIMITED approval to Uniswap V3 Router",
        contractName: "USDC",
        contractType: .token,
        isVerified: true,
        nativeValue: nil,
        decodedParams: [
            "spender": "0x68b3465833fb72a70ecdf485e0e4c7bd8665fc45",
            "amount": "unlimited"
        ],
        warnings: [.unlimitedApproval, .unverifiedContract],
        riskLevel: .high
    )
    
    return TransactionPreviewView(
        decoded: decoded,
        onApprove: { print("Approved") },
        onReject: { print("Rejected") }
    )
}
