import SwiftUI

// MARK: - Transaction Intent View
// Phase 5.3: Smart Transaction Features - Human-Readable Transaction Preview

struct TransactionIntentView: View {
    let intent: TransactionIntent
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    @State private var showRawData = false
    @State private var agreedToWarnings = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
            
            ScrollView {
                VStack(spacing: 20) {
                    // Summary Card
                    summaryCard
                    
                    // Warnings Section
                    if !intent.warnings.isEmpty {
                        warningsSection
                    }
                    
                    // Transaction Details
                    detailsCard
                    
                    // Balance Changes
                    balanceChangesCard
                    
                    // Fee Section
                    feeCard
                    
                    // Raw Data (expandable)
                    if !intent.rawTransaction.isEmpty {
                        rawDataSection
                    }
                }
                .padding()
            }
            
            // Action Buttons
            actionButtons
        }
        .frame(width: 500, height: 700)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack {
            // Transaction Type Icon
            ZStack {
                Circle()
                    .fill(colorForType(intent.type).opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Image(systemName: intent.type.icon)
                    .font(.title2)
                    .foregroundColor(colorForType(intent.type))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(intent.type.rawValue)
                    .font(.headline)
                
                Text(intent.chain)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Risk Badge
            IntentRiskBadge(level: intent.overallRisk)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Summary Card
    
    private var summaryCard: some View {
        GroupBox {
            VStack(spacing: 16) {
                // Human-readable summary
                Text(intent.summary)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                
                Divider()
                
                // Amount Display
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Amount")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(formatDecimal(intent.amount))
                                .font(.title.bold())
                            Text(intent.token.symbol)
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        
                        if let fiat = intent.fiatValue {
                            Text("≈ $\(formatDecimal(fiat))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Token Icon
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 50, height: 50)
                        
                        Text(intent.token.symbol.prefix(2))
                            .font(.headline.bold())
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Warnings Section
    
    private var warningsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Warnings")
                        .font(.headline)
                    Spacer()
                    Text("\(intent.warnings.count)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(8)
                }
                
                ForEach(intent.warnings) { warning in
                    IntentWarningRow(warning: warning)
                }
                
                // Acknowledgment checkbox for dangerous transactions
                if intent.overallRisk == .warning || intent.overallRisk == .danger {
                    Divider()
                    
                    Toggle(isOn: $agreedToWarnings) {
                        Text("I understand the risks and want to proceed")
                            .font(.caption)
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(colorForRisk(intent.overallRisk), lineWidth: 2)
        )
    }
    
    // MARK: - Details Card
    
    private var detailsCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                HStack {
                    Text("Transaction Details")
                        .font(.headline)
                    Spacer()
                }
                
                IntentDetailRow(
                    icon: "arrow.up.circle",
                    label: "From",
                    value: shortAddress(intent.fromAddress),
                    fullValue: intent.fromAddress
                )
                
                IntentDetailRow(
                    icon: "arrow.down.circle",
                    label: "To",
                    value: intent.toAddressLabel ?? shortAddress(intent.toAddress),
                    fullValue: intent.toAddress,
                    badge: intent.toAddressLabel != nil ? "Verified" : nil
                )
                
                if let contractName = intent.contractName {
                    IntentDetailRow(
                        icon: "doc.text.fill",
                        label: "Contract",
                        value: contractName
                    )
                }
                
                if let functionName = intent.functionName {
                    IntentDetailRow(
                        icon: "function",
                        label: "Function",
                        value: functionName
                    )
                }
                
                if intent.type == .tokenApproval {
                    IntentDetailRow(
                        icon: "checkmark.seal",
                        label: "Approval",
                        value: intent.isUnlimitedApproval ? "UNLIMITED" : formatDecimal(intent.approvalAmount ?? 0),
                        isWarning: intent.isUnlimitedApproval
                    )
                    
                    if let spender = intent.spenderAddress {
                        IntentDetailRow(
                            icon: "person.fill.questionmark",
                            label: "Spender",
                            value: intent.spenderLabel ?? shortAddress(spender),
                            fullValue: spender
                        )
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Balance Changes Card
    
    private var balanceChangesCard: some View {
        let changes = TransactionIntentDecoder.shared.simulateBalanceChanges(intent: intent)
        
        return GroupBox {
            VStack(spacing: 12) {
                HStack {
                    Text("Balance Changes")
                        .font(.headline)
                    Spacer()
                    Text("Simulated")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                ForEach(changes) { change in
                    HStack {
                        Image(systemName: change.isIncoming ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                            .foregroundColor(change.isIncoming ? .green : .red)
                        
                        Text(change.token.symbol)
                            .font(.subheadline.bold())
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text(change.displayAmount)
                                .font(.subheadline.bold())
                                .foregroundColor(change.isIncoming ? .green : .red)
                            
                            if let fiat = change.fiatValue {
                                Text("≈ $\(formatDecimal(fiat))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Fee Card
    
    private var feeCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                HStack {
                    Text("Network Fee")
                        .font(.headline)
                    Spacer()
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(formatDecimal(intent.fee, maxDecimals: 8))
                                .font(.title3.bold())
                            Text(intent.feeToken.symbol)
                                .foregroundColor(.secondary)
                        }
                        
                        if let feeFiat = intent.feeFiatValue {
                            Text("≈ $\(formatDecimal(feeFiat))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Fee percentage of total
                    if intent.amount > 0 && intent.token.symbol == intent.feeToken.symbol {
                        let feePercent = (intent.fee / intent.amount) * 100
                        VStack(alignment: .trailing) {
                            Text("\(formatDecimal(feePercent, maxDecimals: 2))%")
                                .font(.caption.bold())
                                .foregroundColor(feePercent > 5 ? .orange : .secondary)
                            Text("of amount")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Raw Data Section
    
    private var rawDataSection: some View {
        GroupBox {
            VStack(spacing: 8) {
                Button(action: { showRawData.toggle() }) {
                    HStack {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(showRawData ? 90 : 0))
                            .animation(.easeInOut(duration: 0.2), value: showRawData)
                        
                        Text("Raw Transaction Data")
                            .font(.headline)
                        
                        Spacer()
                        
                        Text("\(intent.rawTransaction.count) chars")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                
                if showRawData {
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(intent.rawTransaction)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(4)
                    }
                    .frame(maxHeight: 100)
                    
                    HStack {
                        Spacer()
                        Button(action: {
                            ClipboardHelper.copySensitive(intent.rawTransaction, timeout: 60)
                        }) {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button(action: onCancel) {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.escape)
            
            Button(action: onConfirm) {
                HStack {
                    if intent.overallRisk == .danger {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    Text(confirmButtonText)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(confirmButtonColor)
            .disabled(!canConfirm)
            .keyboardShortcut(.return)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var confirmButtonText: String {
        switch intent.overallRisk {
        case .safe: return "Confirm & Sign"
        case .caution: return "Confirm & Sign"
        case .warning: return "Proceed Anyway"
        case .danger: return "I Accept the Risk"
        }
    }
    
    private var confirmButtonColor: Color {
        switch intent.overallRisk {
        case .safe: return .blue
        case .caution: return .blue
        case .warning: return .orange
        case .danger: return .red
        }
    }
    
    private var canConfirm: Bool {
        if intent.overallRisk == .warning || intent.overallRisk == .danger {
            return agreedToWarnings
        }
        return true
    }
    
    // MARK: - Helpers
    
    private func colorForType(_ type: IntentTransactionType) -> Color {
        switch type {
        case .transfer, .tokenTransfer: return .blue
        case .tokenApproval: return .orange
        case .contractCall: return .purple
        case .swap: return .green
        case .stake, .unstake: return .indigo
        case .wrap, .unwrap: return .teal
        case .bridge: return .cyan
        case .unknown: return .gray
        }
    }
    
    private func colorForRisk(_ level: IntentRiskLevel) -> Color {
        switch level {
        case .safe: return .green
        case .caution: return .yellow
        case .warning: return .orange
        case .danger: return .red
        }
    }
    
    private func formatDecimal(_ value: Decimal, maxDecimals: Int = 6) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = maxDecimals
        formatter.minimumFractionDigits = 0
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
    
    private func shortAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
}

// MARK: - Supporting Views

struct IntentRiskBadge: View {
    let level: IntentRiskLevel
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: level.icon)
            Text(level.rawValue)
                .font(.caption.bold())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(colorForLevel.opacity(0.2))
        .foregroundColor(colorForLevel)
        .cornerRadius(8)
    }
    
    private var colorForLevel: Color {
        switch level {
        case .safe: return .green
        case .caution: return .yellow
        case .warning: return .orange
        case .danger: return .red
        }
    }
}

struct IntentWarningRow: View {
    let warning: IntentWarning
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: warning.level.icon)
                .foregroundColor(colorForLevel)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(warning.title)
                    .font(.subheadline.bold())
                
                Text(warning.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let recommendation = warning.recommendation {
                    Text("→ \(recommendation)")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private var colorForLevel: Color {
        switch warning.level {
        case .safe: return .green
        case .caution: return .yellow
        case .warning: return .orange
        case .danger: return .red
        }
    }
}

struct IntentDetailRow: View {
    let icon: String
    let label: String
    let value: String
    var fullValue: String? = nil
    var badge: String? = nil
    var isWarning: Bool = false
    
    @State private var showCopied = false
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 24)
            
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            HStack(spacing: 8) {
                Text(value)
                    .font(.subheadline.bold())
                    .foregroundColor(isWarning ? .orange : .primary)
                
                if let badge = badge {
                    Text(badge)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                }
                
                if fullValue != nil {
                    Button(action: copyToClipboard) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                            .foregroundColor(showCopied ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 2)
    }
    
    private func copyToClipboard() {
        if let full = fullValue {
            ClipboardHelper.copySensitive(full, timeout: 60)
            
            withAnimation {
                showCopied = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showCopied = false
                }
            }
        }
    }
}

// MARK: - Transaction Intent Preview Sheet

struct TransactionIntentPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let intent: TransactionIntent
    let onConfirm: () -> Void
    
    var body: some View {
        TransactionIntentView(
            intent: intent,
            onConfirm: {
                onConfirm()
                dismiss()
            },
            onCancel: {
                dismiss()
            }
        )
    }
}

// MARK: - Quick Preview Builder

@MainActor
struct TransactionPreviewBuilder {
    
    /// Build a preview for an ETH transfer
    static func ethTransfer(
        from: String,
        to: String,
        amount: Decimal,
        gasPrice: Decimal,
        gasLimit: Int = 21000
    ) -> TransactionIntent {
        TransactionIntentDecoder.shared.decodeEthereumTransaction(
            from: from,
            to: to,
            value: "\(amount * Decimal(1_000_000_000_000_000_000))",
            data: "0x",
            gasPrice: "\(gasPrice * Decimal(1_000_000_000))",
            gasLimit: "\(gasLimit)"
        )
    }
    
    /// Build a preview for a BTC transfer
    static func btcTransfer(
        from: String,
        to: String,
        amountBTC: Decimal,
        feeBTC: Decimal,
        isRBF: Bool = true
    ) -> TransactionIntent {
        let amountSats = Int64((amountBTC * 100_000_000).doubleValue)
        let feeSats = Int64((feeBTC * 100_000_000).doubleValue)
        
        return TransactionIntentDecoder.shared.decodeBitcoinTransaction(
            from: from,
            to: to,
            amountSats: amountSats,
            feeSats: feeSats,
            isRBF: isRBF
        )
    }
    
    /// Build a preview for a token approval
    static func tokenApproval(
        from: String,
        tokenContract: String,
        spender: String,
        amount: Decimal,
        isUnlimited: Bool = false
    ) -> TransactionIntent {
        // Construct approve(address,uint256) call data
        let spenderPadded = spender.dropFirst(2).padding(toLength: 64, withPad: "0", startingAt: 0)
        let amountHex = isUnlimited ? 
            "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" :
            String(format: "%064llx", UInt64((amount * 1_000_000_000_000_000_000).doubleValue))
        
        let data = "0x095ea7b3" + spenderPadded + amountHex
        
        return TransactionIntentDecoder.shared.decodeEthereumTransaction(
            from: from,
            to: tokenContract,
            value: "0",
            data: data,
            gasPrice: "30000000000",  // 30 Gwei
            gasLimit: "60000"
        )
    }
}

// MARK: - Decimal Extension

extension Decimal {
    var doubleValue: Double {
        return NSDecimalNumber(decimal: self).doubleValue
    }
}

// MARK: - Preview

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    let sampleIntent = TransactionIntent(
        type: .transfer,
        chain: "Ethereum",
        fromAddress: "0x742d35Cc6634C0532925a3b844Bc9e7595f8fB12",
        toAddress: "0x8ba1f109551bD432803012645Ac136ddd64DBA72",
        toAddressLabel: nil,
        amount: 1.5,
        token: IntentTokenInfo.eth,
        fiatValue: 6000,
        fee: 0.002,
        feeToken: IntentTokenInfo.eth,
        feeFiatValue: 8,
        approvalAmount: nil,
        isUnlimitedApproval: false,
        spenderAddress: nil,
        spenderLabel: nil,
        contractName: nil,
        functionName: nil,
        functionParameters: nil,
        warnings: [
            IntentWarning(
                level: .caution,
                title: "New Address",
                description: "You haven't sent to this address before",
                recommendation: "Double-check the address is correct"
            )
        ],
        overallRisk: .caution,
        rawTransaction: "0x",
        timestamp: Date()
    )
    
    TransactionIntentView(
        intent: sampleIntent,
        onConfirm: { print("Confirmed") },
        onCancel: { print("Cancelled") }
    )
}
#endif
#endif
#endif

// MARK: - Demo View for Settings

struct TransactionIntentDemoView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedScenario = 0
    
    private let scenarios = [
        "ETH Transfer",
        "Token Approval (Unlimited)",
        "Token Transfer",
        "Contract Interaction"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Transaction Intent Preview")
                    .font(.title2.bold())
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            // Scenario Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Select Demo Scenario")
                    .font(.headline)
                
                Picker("Scenario", selection: $selectedScenario) {
                    ForEach(0..<scenarios.count, id: \.self) { index in
                        Text(scenarios[index]).tag(index)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding()
            
            // Transaction Preview
            TransactionIntentView(
                intent: sampleIntentForScenario(selectedScenario),
                onConfirm: {
                    ToastManager.shared.success("Transaction would be signed!")
                    dismiss()
                },
                onCancel: {
                    dismiss()
                }
            )
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func sampleIntentForScenario(_ index: Int) -> TransactionIntent {
        switch index {
        case 0:
            // Simple ETH transfer
            return TransactionIntent(
                type: .transfer,
                chain: "Ethereum",
                fromAddress: "0x742d35Cc6634C0532925a3b844Bc9e7595f8fB12",
                toAddress: "0x8ba1f109551bD432803012645Ac136ddd64DBA72",
                toAddressLabel: "Alice.eth",
                amount: 0.5,
                token: IntentTokenInfo.eth,
                fiatValue: 2000,
                fee: 0.001,
                feeToken: IntentTokenInfo.eth,
                feeFiatValue: 4,
                approvalAmount: nil,
                isUnlimitedApproval: false,
                spenderAddress: nil,
                spenderLabel: nil,
                contractName: nil,
                functionName: nil,
                functionParameters: nil,
                warnings: [],
                overallRisk: .safe,
                rawTransaction: "0xf86c...",
                timestamp: Date()
            )
            
        case 1:
            // Unlimited token approval (dangerous)
            return TransactionIntent(
                type: .tokenApproval,
                chain: "Ethereum",
                fromAddress: "0x742d35Cc6634C0532925a3b844Bc9e7595f8fB12",
                toAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
                toAddressLabel: "Tether USD (USDT)",
                amount: 0,
                token: IntentTokenInfo(symbol: "USDT", name: "Tether USD", decimals: 6, contractAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7", logoURL: nil, isVerified: true),
                fiatValue: nil,
                fee: 0.003,
                feeToken: IntentTokenInfo.eth,
                feeFiatValue: 12,
                approvalAmount: Decimal.greatestFiniteMagnitude,
                isUnlimitedApproval: true,
                spenderAddress: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
                spenderLabel: "Uniswap V2 Router",
                contractName: "Tether USD",
                functionName: "approve(address,uint256)",
                functionParameters: ["spender": "0x7a25...2488D", "amount": "UNLIMITED"],
                warnings: [
                    IntentWarning(
                        level: .danger,
                        title: "Unlimited Approval",
                        description: "This approves UNLIMITED tokens to be spent by the contract",
                        recommendation: "Consider setting a specific amount instead"
                    ),
                    IntentWarning(
                        level: .caution,
                        title: "Contract Interaction",
                        description: "You are interacting with a smart contract",
                        recommendation: "Verify this is the correct contract"
                    )
                ],
                overallRisk: .danger,
                rawTransaction: "0x095ea7b3...",
                timestamp: Date()
            )
            
        case 2:
            // Token transfer
            return TransactionIntent(
                type: .tokenTransfer,
                chain: "Ethereum",
                fromAddress: "0x742d35Cc6634C0532925a3b844Bc9e7595f8fB12",
                toAddress: "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC",
                toAddressLabel: nil,
                amount: 100,
                token: IntentTokenInfo(symbol: "USDC", name: "USD Coin", decimals: 6, contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", logoURL: nil, isVerified: true),
                fiatValue: 100,
                fee: 0.002,
                feeToken: IntentTokenInfo.eth,
                feeFiatValue: 8,
                approvalAmount: nil,
                isUnlimitedApproval: false,
                spenderAddress: nil,
                spenderLabel: nil,
                contractName: "USD Coin",
                functionName: "transfer(address,uint256)",
                functionParameters: nil,
                warnings: [
                    IntentWarning(
                        level: .caution,
                        title: "New Address",
                        description: "You haven't sent to this address before",
                        recommendation: "Double-check the address is correct"
                    )
                ],
                overallRisk: .caution,
                rawTransaction: "0xa9059cbb...",
                timestamp: Date()
            )
            
        default:
            // Contract interaction
            return TransactionIntent(
                type: .contractCall,
                chain: "Ethereum",
                fromAddress: "0x742d35Cc6634C0532925a3b844Bc9e7595f8fB12",
                toAddress: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
                toAddressLabel: "Uniswap V2 Router",
                amount: 0.1,
                token: IntentTokenInfo.eth,
                fiatValue: 400,
                fee: 0.01,
                feeToken: IntentTokenInfo.eth,
                feeFiatValue: 40,
                approvalAmount: nil,
                isUnlimitedApproval: false,
                spenderAddress: nil,
                spenderLabel: nil,
                contractName: "Uniswap V2 Router",
                functionName: "swapExactETHForTokens",
                functionParameters: [
                    "amountOutMin": "95.5 USDC",
                    "path": "ETH → USDC",
                    "deadline": "15 minutes"
                ],
                warnings: [
                    IntentWarning(
                        level: .warning,
                        title: "Price Impact",
                        description: "Estimated slippage: 0.5%",
                        recommendation: "Consider using a larger liquidity pool"
                    )
                ],
                overallRisk: .warning,
                rawTransaction: "0x7ff36ab5...",
                timestamp: Date()
            )
        }
    }
}
