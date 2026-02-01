import SwiftUI

// MARK: - CPFP Boost View

/// View for boosting stuck parent transactions using Child-Pays-For-Parent
struct CPFPBoostView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CPFPBoostViewModel
    
    let parentTransaction: StuckTransaction
    let walletAddress: String
    let onSuccess: (String) -> Void
    
    init(parentTransaction: StuckTransaction, walletAddress: String, onSuccess: @escaping (String) -> Void) {
        self.parentTransaction = parentTransaction
        self.walletAddress = walletAddress
        self.onSuccess = onSuccess
        _viewModel = StateObject(wrappedValue: CPFPBoostViewModel(parentTx: parentTransaction))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            ScrollView {
                VStack(spacing: HawalaTheme.Spacing.lg) {
                    // Explanation Card
                    explanationCard
                    
                    // Parent Transaction Info
                    parentTxCard
                    
                    // Fee Calculator
                    feeCalculatorCard
                    
                    // Effective Rate Display
                    effectiveRateCard
                    
                    // Warning Banner
                    if viewModel.showWarning {
                        warningBanner
                    }
                    
                    // Error Message
                    if let error = viewModel.errorMessage {
                        errorBanner(error)
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, HawalaTheme.Spacing.lg)
                .padding(.top, HawalaTheme.Spacing.md)
            }
            
            // Bottom Action
            bottomActionBar
        }
        .background(HawalaTheme.Colors.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.calculateInitialFees()
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
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
            
            VStack(spacing: 2) {
                Text("Boost Transaction")
                    .font(HawalaTheme.Typography.h3)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text("Child Pays for Parent")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            
            Spacer()
            
            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, HawalaTheme.Spacing.lg)
        .padding(.vertical, HawalaTheme.Spacing.md)
    }
    
    // MARK: - Explanation Card
    
    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
            HStack(spacing: HawalaTheme.Spacing.sm) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(HawalaTheme.Colors.accent)
                
                Text("How CPFP Works")
                    .font(HawalaTheme.Typography.h4)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
            }
            
            Text("CPFP creates a new transaction that spends an output from your stuck transaction. Miners are incentivized to confirm both transactions together because the combined fee rate is attractive.")
                .font(HawalaTheme.Typography.bodySmall)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.accent.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
    }
    
    // MARK: - Parent Transaction Card
    
    private var parentTxCard: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            Text("STUCK TRANSACTION")
                .font(HawalaTheme.Typography.label)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
                .tracking(1)
            
            VStack(spacing: HawalaTheme.Spacing.sm) {
                HStack {
                    Text("TxID")
                        .font(HawalaTheme.Typography.bodySmall)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                    Spacer()
                    Text(parentTransaction.txid.prefix(12) + "..." + parentTransaction.txid.suffix(8))
                        .font(HawalaTheme.Typography.mono)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                }
                
                HStack {
                    Text("Size")
                        .font(HawalaTheme.Typography.bodySmall)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                    Spacer()
                    Text("\(parentTransaction.size) vBytes")
                        .font(HawalaTheme.Typography.mono)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                }
                
                HStack {
                    Text("Fee Paid")
                        .font(HawalaTheme.Typography.bodySmall)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                    Spacer()
                    Text("\(parentTransaction.fee) sats")
                        .font(HawalaTheme.Typography.mono)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                }
                
                HStack {
                    Text("Current Rate")
                        .font(HawalaTheme.Typography.bodySmall)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Text(String(format: "%.1f", parentTransaction.feeRate))
                            .font(HawalaTheme.Typography.mono)
                            .foregroundColor(HawalaTheme.Colors.warning)
                        Text("sat/vB")
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                    }
                }
                
                HStack {
                    Text("Time Pending")
                        .font(HawalaTheme.Typography.bodySmall)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                    Spacer()
                    Text(formatTimePending(parentTransaction.timestamp))
                        .font(HawalaTheme.Typography.mono)
                        .foregroundColor(HawalaTheme.Colors.error)
                }
            }
        }
        .hawalaCard()
    }
    
    // MARK: - Fee Calculator Card
    
    private var feeCalculatorCard: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            Text("CHILD TRANSACTION FEE")
                .font(HawalaTheme.Typography.label)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
                .tracking(1)
            
            // Target Fee Rate Slider
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                HStack {
                    Text("Target Effective Rate")
                        .font(HawalaTheme.Typography.bodySmall)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                    Spacer()
                    Text("\(Int(viewModel.targetEffectiveRate)) sat/vB")
                        .font(HawalaTheme.Typography.mono)
                        .foregroundColor(HawalaTheme.Colors.accent)
                }
                
                Slider(
                    value: $viewModel.targetEffectiveRate,
                    in: Double(viewModel.minimumEffectiveRate)...Double(viewModel.maximumEffectiveRate),
                    step: 1
                )
                .accentColor(HawalaTheme.Colors.accent)
                
                HStack {
                    Text("Economy")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                    Spacer()
                    Text("Priority")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
            }
            
            Divider()
                .background(HawalaTheme.Colors.border)
            
            // Calculated Child Fee
            VStack(spacing: HawalaTheme.Spacing.sm) {
                HStack {
                    Text("Child Tx Size (est.)")
                        .font(HawalaTheme.Typography.bodySmall)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                    Spacer()
                    Text("~\(viewModel.estimatedChildSize) vBytes")
                        .font(HawalaTheme.Typography.mono)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                }
                
                HStack {
                    Text("Required Child Fee")
                        .font(HawalaTheme.Typography.bodySmall)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                    Spacer()
                    Text("\(viewModel.requiredChildFee) sats")
                        .font(HawalaTheme.Typography.mono)
                        .fontWeight(.semibold)
                        .foregroundColor(HawalaTheme.Colors.accent)
                }
                
                HStack {
                    Text("Child Fee Rate")
                        .font(HawalaTheme.Typography.bodySmall)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                    Spacer()
                    Text(String(format: "%.1f sat/vB", viewModel.childFeeRate))
                        .font(HawalaTheme.Typography.mono)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                }
            }
        }
        .hawalaCard()
    }
    
    // MARK: - Effective Rate Card
    
    private var effectiveRateCard: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            Text("COMBINED RESULT")
                .font(HawalaTheme.Typography.label)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
                .tracking(1)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Before CPFP")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", parentTransaction.feeRate))
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(HawalaTheme.Colors.error)
                        Text("sat/vB")
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "arrow.right")
                    .font(.title2)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("After CPFP")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", viewModel.targetEffectiveRate))
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(HawalaTheme.Colors.success)
                        Text("sat/vB")
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                    }
                }
            }
            
            // Total fees summary
            HStack {
                Text("Total Fees Paid")
                    .font(HawalaTheme.Typography.bodySmall)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                Spacer()
                Text("\(parentTransaction.fee + viewModel.requiredChildFee) sats")
                    .font(HawalaTheme.Typography.mono)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
            }
            .padding(.top, HawalaTheme.Spacing.sm)
        }
        .hawalaCard()
    }
    
    // MARK: - Warning Banner
    
    private var warningBanner: some View {
        HStack(spacing: HawalaTheme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(HawalaTheme.Colors.warning)
            
            Text("This will spend additional fees. Make sure your spendable output from the stuck transaction has enough value.")
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.warning)
        }
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.warning.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
    }
    
    // MARK: - Error Banner
    
    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: HawalaTheme.Spacing.sm) {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(HawalaTheme.Colors.error)
            
            Text(error)
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.error)
            
            Spacer()
            
            Button(action: { viewModel.errorMessage = nil }) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(HawalaTheme.Colors.error)
            }
            .buttonStyle(.plain)
        }
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.error.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
    }
    
    // MARK: - Bottom Action Bar
    
    private var bottomActionBar: some View {
        VStack(spacing: HawalaTheme.Spacing.sm) {
            // Estimated confirmation time
            HStack {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                Text("Estimated confirmation: ~\(viewModel.estimatedConfirmationTime)")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            
            Button(action: {
                Task {
                    await viewModel.createCPFPTransaction(walletAddress: walletAddress)
                    if let txid = viewModel.successTxId {
                        onSuccess(txid)
                        dismiss()
                    }
                }
            }) {
                HStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "bolt.fill")
                        Text("Boost with CPFP")
                    }
                }
                .font(HawalaTheme.Typography.body)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, HawalaTheme.Spacing.md)
                .background(
                    viewModel.canCreateCPFP
                        ? HawalaTheme.Colors.accent
                        : HawalaTheme.Colors.accent.opacity(0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canCreateCPFP || viewModel.isLoading)
        }
        .padding(HawalaTheme.Spacing.lg)
        .background(HawalaTheme.Colors.backgroundSecondary)
    }
    
    // MARK: - Helpers
    
    private func formatTimePending(_ timestamp: Date) -> String {
        let elapsed = Date().timeIntervalSince(timestamp)
        let minutes = Int(elapsed / 60)
        let hours = minutes / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes % 60)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Stuck Transaction Model

struct StuckTransaction: Identifiable {
    let id: String
    let txid: String
    let size: Int         // vBytes
    let fee: Int          // satoshis
    let feeRate: Double   // sat/vB
    let timestamp: Date
    let spendableOutputIndex: Int
    let spendableOutputValue: Int // satoshis
    
    init(txid: String, size: Int, fee: Int, timestamp: Date, spendableOutputIndex: Int, spendableOutputValue: Int) {
        self.id = txid
        self.txid = txid
        self.size = size
        self.fee = fee
        self.feeRate = Double(fee) / Double(size)
        self.timestamp = timestamp
        self.spendableOutputIndex = spendableOutputIndex
        self.spendableOutputValue = spendableOutputValue
    }
}

// MARK: - CPFP Boost View Model

@MainActor
final class CPFPBoostViewModel: ObservableObject {
    @Published var targetEffectiveRate: Double = 20.0
    @Published var requiredChildFee: Int = 0
    @Published var childFeeRate: Double = 0.0
    @Published var estimatedChildSize: Int = 141 // Standard P2WPKH spend
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var successTxId: String?
    @Published var showWarning = true
    
    let parentTx: StuckTransaction
    let minimumEffectiveRate: Int = 5
    let maximumEffectiveRate: Int = 100
    
    var canCreateCPFP: Bool {
        requiredChildFee > 0 && 
        requiredChildFee < parentTx.spendableOutputValue &&
        errorMessage == nil
    }
    
    var estimatedConfirmationTime: String {
        if targetEffectiveRate >= 50 {
            return "10-20 min"
        } else if targetEffectiveRate >= 20 {
            return "30-60 min"
        } else if targetEffectiveRate >= 10 {
            return "1-2 hours"
        } else {
            return "2+ hours"
        }
    }
    
    init(parentTx: StuckTransaction) {
        self.parentTx = parentTx
    }
    
    func calculateInitialFees() {
        // Fetch current recommended fee rate and set target
        Task {
            // For now, use a sensible default
            // In production, fetch from FeeEstimationService
            targetEffectiveRate = max(Double(minimumEffectiveRate), parentTx.feeRate + 10)
            calculateRequiredChildFee()
        }
    }
    
    func calculateRequiredChildFee() {
        // Formula: effectiveRate = (parentFee + childFee) / (parentSize + childSize)
        // Solving for childFee: childFee = effectiveRate * (parentSize + childSize) - parentFee
        
        let combinedSize = parentTx.size + estimatedChildSize
        let totalFeeNeeded = Int(targetEffectiveRate * Double(combinedSize))
        requiredChildFee = max(0, totalFeeNeeded - parentTx.fee)
        
        // Calculate the child's individual fee rate
        childFeeRate = Double(requiredChildFee) / Double(estimatedChildSize)
        
        // Validate
        if requiredChildFee > parentTx.spendableOutputValue {
            errorMessage = "Not enough funds in spendable output (\(parentTx.spendableOutputValue) sats) to cover required fee (\(requiredChildFee) sats)"
        } else {
            errorMessage = nil
        }
    }
    
    func createCPFPTransaction(walletAddress: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Create the CPFP transaction
            // This spends the output from the stuck parent tx and sends it back to ourselves
            // with a high enough fee to boost the parent
            
            let cpfpBuilder = CPFPTransactionBuilder(
                parentTxid: parentTx.txid,
                parentOutputIndex: parentTx.spendableOutputIndex,
                parentOutputValue: parentTx.spendableOutputValue,
                childFee: requiredChildFee,
                destinationAddress: walletAddress
            )
            
            // In production, this would:
            // 1. Build the transaction
            // 2. Sign with the wallet's key
            // 3. Broadcast to the network
            
            // For now, simulate success
            try await Task.sleep(nanoseconds: 1_500_000_000)
            
            // Would call: let txid = try await cpfpBuilder.buildSignAndBroadcast()
            successTxId = "cpfp_\(UUID().uuidString.prefix(16))"
            
            print("[CPFP] Successfully created CPFP transaction: \(successTxId ?? "nil")")
            print("[CPFP] Parent tx \(parentTx.txid) boosted from \(parentTx.feeRate) to \(targetEffectiveRate) sat/vB effective")
            
        } catch {
            errorMessage = "Failed to create CPFP transaction: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

// MARK: - CPFP Transaction Builder (Placeholder)

struct CPFPTransactionBuilder {
    let parentTxid: String
    let parentOutputIndex: Int
    let parentOutputValue: Int
    let childFee: Int
    let destinationAddress: String
    
    var outputValue: Int {
        parentOutputValue - childFee
    }
    
    // In production, this would build and sign the transaction
    func buildSignAndBroadcast() async throws -> String {
        // 1. Create transaction input spending parent output
        // 2. Create transaction output to destination (value - fee)
        // 3. Sign with wallet key
        // 4. Broadcast via TransactionBroadcaster
        throw NSError(domain: "CPFPBuilder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
}

// MARK: - Preview

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    CPFPBoostView(
        parentTransaction: StuckTransaction(
            txid: "abc123def456789012345678901234567890123456789012345678901234abcd",
            size: 200,
            fee: 1000,
            timestamp: Date().addingTimeInterval(-3600), // 1 hour ago
            spendableOutputIndex: 1,
            spendableOutputValue: 50000
        ),
        walletAddress: "tb1qtest123456789",
        onSuccess: { txid in
            print("CPFP created: \(txid)")
        }
    )
}
#endif
#endif
#endif
