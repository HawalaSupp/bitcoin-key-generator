import SwiftUI

// MARK: - Transaction Preview Sheet

struct TransactionPreviewSheet: View {
    let preview: TransactionPreview
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var showRawData = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            ScrollView {
                VStack(spacing: HawalaTheme.Spacing.lg) {
                    // Risk Summary
                    if !preview.risks.isEmpty {
                        riskSummarySection
                    }
                    
                    // Transaction Details
                    transactionDetailsSection
                    
                    // Decoded Call
                    if let call = preview.decodedCall {
                        decodedCallSection(call)
                    }
                    
                    // Simulation Result
                    if let simulation = preview.simulation {
                        simulationSection(simulation)
                    }
                    
                    // Individual Risks
                    if !preview.risks.isEmpty {
                        risksSection
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(HawalaTheme.Spacing.lg)
            }
            
            // Action Buttons
            actionButtons
        }
        .background(HawalaTheme.Colors.background)
        .frame(minWidth: 500, minHeight: 600)
    }
    
    // MARK: - Header
    
    private var header: some View {
        VStack(spacing: HawalaTheme.Spacing.sm) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                riskBadge
            }
            .padding(.horizontal, HawalaTheme.Spacing.lg)
            .padding(.top, HawalaTheme.Spacing.md)
            
            Text("Transaction Preview")
                .font(HawalaTheme.Typography.h2)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
            
            if let contract = preview.recipientContract {
                HStack(spacing: 6) {
                    Image(systemName: categoryIcon(contract.category))
                        .font(.caption)
                    Text(contract.name)
                        .font(HawalaTheme.Typography.caption)
                }
                .foregroundColor(HawalaTheme.Colors.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(HawalaTheme.Colors.accent.opacity(0.1))
                .clipShape(Capsule())
            }
        }
        .padding(.bottom, HawalaTheme.Spacing.md)
    }
    
    private var riskBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: preview.overallRiskLevel.icon)
                .font(.caption)
            Text(riskLevelText)
                .font(HawalaTheme.Typography.label)
        }
        .foregroundColor(riskColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(riskColor.opacity(0.15))
        .clipShape(Capsule())
    }
    
    private var riskLevelText: String {
        switch preview.overallRiskLevel {
        case .none: return "Safe"
        case .low: return "Low Risk"
        case .medium: return "Medium Risk"
        case .high: return "High Risk"
        case .critical: return "Critical Risk"
        }
    }
    
    private var riskColor: Color {
        switch preview.overallRiskLevel {
        case .none: return HawalaTheme.Colors.success
        case .low: return HawalaTheme.Colors.info
        case .medium: return .yellow
        case .high: return .orange
        case .critical: return HawalaTheme.Colors.error
        }
    }
    
    // MARK: - Risk Summary
    
    private var riskSummarySection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
            if preview.overallRiskLevel >= .medium {
                HStack(spacing: HawalaTheme.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundColor(riskColor)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(preview.risks.count) Warning\(preview.risks.count > 1 ? "s" : "") Detected")
                            .font(HawalaTheme.Typography.h4)
                            .foregroundColor(HawalaTheme.Colors.textPrimary)
                        
                        Text("Review carefully before proceeding")
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                    }
                    
                    Spacer()
                }
                .padding(HawalaTheme.Spacing.md)
                .background(riskColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
            }
        }
    }
    
    // MARK: - Transaction Details
    
    private var transactionDetailsSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            Text("TRANSACTION DETAILS")
                .font(HawalaTheme.Typography.label)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
                .tracking(1)
            
            VStack(spacing: 0) {
                if let to = preview.transaction.to {
                    PreviewDetailRow(label: "To", value: formatAddress(to))
                    Divider()
                }
                
                if let value = preview.transaction.value, value > 0 {
                    PreviewDetailRow(label: "Value", value: formatEthValue(value))
                    Divider()
                }
                
                if let gas = preview.estimatedGasCost {
                    PreviewDetailRow(label: "Est. Gas Cost", value: String(format: "%.6f ETH", gas))
                    Divider()
                }
                
                PreviewDetailRow(label: "Network", value: chainName(preview.transaction.chainId))
            }
            .background(HawalaTheme.Colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
        }
    }
    
    // MARK: - Decoded Call
    
    private func decodedCallSection(_ call: DecodedCall) -> some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            HStack {
                Text("FUNCTION CALL")
                    .font(HawalaTheme.Typography.label)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                    .tracking(1)
                
                Spacer()
                
                Button(action: { showRawData.toggle() }) {
                    Text(showRawData ? "Hide Raw" : "Show Raw")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.accent)
                }
                .buttonStyle(.plain)
            }
            
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                // Function name
                HStack {
                    Text(call.functionName)
                        .font(HawalaTheme.Typography.mono)
                        .foregroundColor(HawalaTheme.Colors.accent)
                    
                    Text("(\(call.selector))")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
                
                Text(call.description)
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                
                // Parameters
                if !call.parameters.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(call.parameters, id: \.index) { param in
                            HStack(alignment: .top) {
                                Text("\(param.type):")
                                    .font(HawalaTheme.Typography.caption)
                                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                                    .frame(width: 80, alignment: .leading)
                                
                                Text(formatParamValue(param))
                                    .font(HawalaTheme.Typography.mono)
                                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                    .padding(HawalaTheme.Spacing.sm)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm))
                }
                
                // Raw data
                if showRawData {
                    Text("Raw Data:")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text("0x\(call.selector)\(call.rawParams)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                    }
                    .padding(HawalaTheme.Spacing.sm)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm))
                }
            }
            .padding(HawalaTheme.Spacing.md)
            .background(HawalaTheme.Colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
        }
    }
    
    // MARK: - Simulation
    
    private func simulationSection(_ simulation: TransactionSimulation) -> some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            Text("SIMULATION")
                .font(HawalaTheme.Typography.label)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
                .tracking(1)
            
            HStack(spacing: HawalaTheme.Spacing.sm) {
                Image(systemName: simulation.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(simulation.success ? HawalaTheme.Colors.success : HawalaTheme.Colors.error)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(simulation.success ? "Transaction will succeed" : "Transaction may fail")
                        .font(HawalaTheme.Typography.h4)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    
                    if let reason = simulation.revertReason {
                        Text(reason)
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                    }
                }
                
                Spacer()
            }
            .padding(HawalaTheme.Spacing.md)
            .background(simulation.success ? HawalaTheme.Colors.success.opacity(0.1) : HawalaTheme.Colors.error.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
        }
    }
    
    // MARK: - Risks Section
    
    private var risksSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            Text("WARNINGS")
                .font(HawalaTheme.Typography.label)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
                .tracking(1)
            
            VStack(spacing: HawalaTheme.Spacing.sm) {
                ForEach(preview.risks) { risk in
                    RiskWarningCard(risk: risk)
                }
            }
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: HawalaTheme.Spacing.md) {
                Button(action: {
                    onCancel()
                    dismiss()
                }) {
                    Text("Cancel")
                        .font(HawalaTheme.Typography.h4)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, HawalaTheme.Spacing.md)
                        .background(HawalaTheme.Colors.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    onConfirm()
                    dismiss()
                }) {
                    Text(preview.overallRiskLevel >= .high ? "Proceed Anyway" : "Confirm")
                        .font(HawalaTheme.Typography.h4)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, HawalaTheme.Spacing.md)
                        .background(
                            preview.overallRiskLevel >= .high
                                ? HawalaTheme.Colors.error
                                : HawalaTheme.Colors.accent
                        )
                        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                }
                .buttonStyle(.plain)
            }
            .padding(HawalaTheme.Spacing.lg)
            .background(HawalaTheme.Colors.background)
        }
    }
    
    // MARK: - Helpers
    
    private func formatAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
    
    private func formatEthValue(_ wei: UInt64) -> String {
        let eth = Double(wei) / 1e18
        return String(format: "%.6f ETH", eth)
    }
    
    private func chainName(_ chainId: Int) -> String {
        switch chainId {
        case 1: return "Ethereum Mainnet"
        case 11155111: return "Sepolia Testnet"
        case 56: return "BNB Chain"
        case 137: return "Polygon"
        default: return "Chain \(chainId)"
        }
    }
    
    private func categoryIcon(_ category: ContractCategory) -> String {
        switch category {
        case .dex: return "arrow.left.arrow.right"
        case .lending: return "percent"
        case .bridge: return "arrow.triangle.branch"
        case .unknown: return "questionmark.circle"
        }
    }
    
    private func formatParamValue(_ param: DecodedParameter) -> String {
        if param.type == "address" && param.value.count > 12 {
            return "\(param.value.prefix(10))...\(param.value.suffix(4))"
        }
        return param.value
    }
}

// MARK: - Detail Row

private struct PreviewDetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(HawalaTheme.Typography.body)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
            
            Spacer()
            
            Text(value)
                .font(HawalaTheme.Typography.mono)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, HawalaTheme.Spacing.md)
        .padding(.vertical, HawalaTheme.Spacing.sm)
    }
}

// MARK: - Risk Warning Card

private struct RiskWarningCard: View {
    let risk: TransactionRisk
    
    private var riskColor: Color {
        switch risk.level {
        case .none: return HawalaTheme.Colors.success
        case .low: return HawalaTheme.Colors.info
        case .medium: return .yellow
        case .high: return .orange
        case .critical: return HawalaTheme.Colors.error
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: HawalaTheme.Spacing.sm) {
            Image(systemName: risk.level.icon)
                .font(.body)
                .foregroundColor(riskColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(risk.title)
                    .font(HawalaTheme.Typography.h4)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text(risk.description)
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                
                HStack(spacing: 4) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption2)
                    Text(risk.recommendation)
                        .font(HawalaTheme.Typography.caption)
                }
                .foregroundColor(HawalaTheme.Colors.accent)
            }
            
            Spacer()
        }
        .padding(HawalaTheme.Spacing.md)
        .background(riskColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                .stroke(riskColor.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Preview

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    TransactionPreviewSheet(
        preview: TransactionPreview(
            transaction: PreviewTransaction(
                from: "0x742d35Cc6634C0532925a3b844Bc9e7595f2b4F6",
                to: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
                value: 1_000_000_000_000_000_000, // 1 ETH
                data: "0x38ed17390000000000000000000000000000000000000000000000000de0b6b3a7640000",
                gasLimit: 150000,
                gasPrice: 50_000_000_000, // 50 Gwei
                chainId: 1
            ),
            decodedCall: DecodedCall(
                selector: "38ed1739",
                functionName: "swapExactTokensForTokens",
                description: "Swap exact tokens",
                parameters: [
                    DecodedParameter(index: 0, type: "uint256", value: "1000000000000000000"),
                    DecodedParameter(index: 1, type: "uint256", value: "950000000000000000"),
                ],
                rawParams: "test"
            ),
            recipientContract: KnownContract(
                name: "Uniswap V2 Router",
                category: .dex,
                riskLevel: .low
            ),
            risks: [
                TransactionRisk(
                    level: .medium,
                    title: "Large Value Transfer",
                    description: "This transaction involves 1.0000 ETH.",
                    recommendation: "Double-check the recipient address"
                )
            ],
            estimatedGasCost: 0.0075,
            simulation: TransactionSimulation(success: true, revertReason: nil, gasUsed: 120000)
        ),
        onConfirm: {},
        onCancel: {}
    )
}
#endif
#endif
#endif
