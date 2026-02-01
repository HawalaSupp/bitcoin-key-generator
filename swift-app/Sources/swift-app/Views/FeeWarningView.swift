import SwiftUI

// MARK: - Fee Warning View

/// Displays contextual fee warnings to prevent common mistakes
struct FeeWarningView: View {
    let warning: FeeWarning
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: warning.icon)
                .font(.title3)
                .foregroundStyle(warning.severity.color)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(warning.title)
                    .font(.headline)
                    .foregroundStyle(warning.severity.color)
                
                Text(warning.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(warning.severity.backgroundColor)
        )
    }
}

// MARK: - Fee Warning Model

struct FeeWarning: Identifiable {
    let id = UUID()
    let type: WarningType
    let title: String
    let message: String
    let severity: Severity
    
    var icon: String {
        switch severity {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }
    
    enum WarningType {
        case highFeePercentage      // Fee > 10% of send amount
        case lowFeeRate             // Below minimum relay fee
        case veryHighFee            // Above 99th percentile
        case slowConfirmation       // Expected wait > 2 hours
        case mempoolCongestion      // Mempool size above threshold
        case gasLimitLow            // EVM: gas limit seems too low
        case insufficientForFee     // Can't cover amount + fee
    }
    
    enum Severity {
        case info
        case warning
        case critical
        
        var color: Color {
            switch self {
            case .info: return .blue
            case .warning: return .orange
            case .critical: return .red
            }
        }
        
        var backgroundColor: Color {
            switch self {
            case .info: return .blue.opacity(0.1)
            case .warning: return .orange.opacity(0.1)
            case .critical: return .red.opacity(0.1)
            }
        }
    }
}

// MARK: - Fee Warning Service

/// Analyzes transaction parameters and generates appropriate warnings
@MainActor
final class FeeWarningService: ObservableObject {
    static let shared = FeeWarningService()
    
    @Published var warnings: [FeeWarning] = []
    
    private init() {}
    
    // MARK: - Bitcoin Fee Analysis
    
    /// Analyze Bitcoin transaction and generate warnings
    func analyzeBitcoinFee(
        amount: Int64,          // satoshis
        fee: Int64,             // satoshis
        feeRate: Int64,         // sat/vB
        currentFeeEstimates: BitcoinFeeEstimate?
    ) -> [FeeWarning] {
        var warnings: [FeeWarning] = []
        
        // Check if fee is a high percentage of send amount
        if amount > 0 {
            let feePercentage = Double(fee) / Double(amount) * 100
            if feePercentage > 10 {
                warnings.append(FeeWarning(
                    type: .highFeePercentage,
                    title: "High Fee Percentage",
                    message: String(format: "Fee is %.1f%% of the amount you're sending. Consider waiting for lower fees or sending a larger amount.", feePercentage),
                    severity: feePercentage > 25 ? .critical : .warning
                ))
            }
        }
        
        if let estimates = currentFeeEstimates {
            // Check if fee rate is below minimum
            if feeRate < Int64(estimates.minimum.satPerByte) {
                warnings.append(FeeWarning(
                    type: .lowFeeRate,
                    title: "Fee Too Low",
                    message: "Your fee rate (\(feeRate) sat/vB) is below the minimum relay fee (\(estimates.minimum.satPerByte) sat/vB). This transaction may never confirm.",
                    severity: .critical
                ))
            }
            
            // Check for very high fee (likely a mistake)
            if feeRate > Int64(estimates.fastest.satPerByte * 3) {
                warnings.append(FeeWarning(
                    type: .veryHighFee,
                    title: "Unusually High Fee",
                    message: "Your fee rate is much higher than needed. Current fast rate is \(estimates.fastest.satPerByte) sat/vB.",
                    severity: .warning
                ))
            }
            
            // Check for slow confirmation
            if feeRate < Int64(estimates.slow.satPerByte) {
                warnings.append(FeeWarning(
                    type: .slowConfirmation,
                    title: "Slow Confirmation Expected",
                    message: "At \(feeRate) sat/vB, your transaction may take 2+ hours to confirm. Current economy rate is \(estimates.slow.satPerByte) sat/vB.",
                    severity: .info
                ))
            }
        }
        
        self.warnings = warnings
        return warnings
    }
    
    // MARK: - Ethereum Fee Analysis
    
    /// Analyze EVM transaction and generate warnings
    func analyzeEVMFee(
        amount: UInt64,         // wei
        gasPrice: UInt64,       // wei
        gasLimit: UInt64,
        chainId: String,
        currentFeeEstimates: EthereumFeeEstimate?
    ) -> [FeeWarning] {
        var warnings: [FeeWarning] = []
        
        let maxFee = gasPrice * gasLimit
        let gasPriceGwei = Double(gasPrice) / 1_000_000_000
        
        // Check if fee is a high percentage of send amount
        if amount > 0 {
            let feePercentage = Double(maxFee) / Double(amount) * 100
            if feePercentage > 10 {
                warnings.append(FeeWarning(
                    type: .highFeePercentage,
                    title: "High Gas Cost",
                    message: String(format: "Gas cost is %.1f%% of the amount you're sending.", feePercentage),
                    severity: feePercentage > 25 ? .critical : .warning
                ))
            }
        }
        
        // Check gas limit for simple transfers
        if gasLimit < 21000 {
            warnings.append(FeeWarning(
                type: .gasLimitLow,
                title: "Gas Limit Too Low",
                message: "Gas limit must be at least 21,000 for simple transfers. Your transaction will fail.",
                severity: .critical
            ))
        }
        
        if let estimates = currentFeeEstimates {
            // Check for very high gas price
            if gasPriceGwei > estimates.fast.gasPrice * 3 {
                warnings.append(FeeWarning(
                    type: .veryHighFee,
                    title: "Very High Gas Price",
                    message: String(format: "Your gas price (%.0f gwei) is much higher than needed. Current fast rate is %.0f gwei.", gasPriceGwei, estimates.fast.gasPrice),
                    severity: .warning
                ))
            }
            
            // Check for slow confirmation
            if gasPriceGwei < estimates.slow.gasPrice {
                warnings.append(FeeWarning(
                    type: .slowConfirmation,
                    title: "May Take Longer",
                    message: String(format: "Your gas price is below standard. Expected wait time: 3+ minutes."),
                    severity: .info
                ))
            }
        }
        
        self.warnings = warnings
        return warnings
    }
    
    /// Clear all warnings
    func clearWarnings() {
        warnings = []
    }
}

// MARK: - Fee Warning Banner

/// Compact banner showing most severe warning
struct FeeWarningBanner: View {
    let warnings: [FeeWarning]
    @State private var showAll = false
    
    private var mostSevere: FeeWarning? {
        warnings.sorted { w1, w2 in
            let severity1 = severityOrder(w1.severity)
            let severity2 = severityOrder(w2.severity)
            return severity1 > severity2
        }.first
    }
    
    private func severityOrder(_ severity: FeeWarning.Severity) -> Int {
        switch severity {
        case .critical: return 2
        case .warning: return 1
        case .info: return 0
        }
    }
    
    var body: some View {
        if let warning = mostSevere {
            VStack(spacing: 8) {
                Button {
                    withAnimation { showAll.toggle() }
                } label: {
                    HStack {
                        Image(systemName: warning.icon)
                            .foregroundStyle(warning.severity.color)
                        
                        Text(warning.title)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(warning.severity.color)
                        
                        Spacer()
                        
                        if warnings.count > 1 {
                            Text("+\(warnings.count - 1) more")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        
                        Image(systemName: showAll ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(warning.severity.backgroundColor)
                    )
                }
                .buttonStyle(.plain)
                
                if showAll {
                    VStack(spacing: 8) {
                        ForEach(warnings) { w in
                            FeeWarningView(warning: w)
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
        }
    }
}

// NOTE: Fee estimate models (BitcoinFeeEstimate, EthereumFeeEstimate, LitecoinFeeEstimate, 
// FeeLevel, GasLevel) are defined in FeeEstimationService.swift

// MARK: - Preview

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    VStack(spacing: 20) {
        FeeWarningView(warning: FeeWarning(
            type: .highFeePercentage,
            title: "High Fee Percentage",
            message: "Fee is 15% of the amount you're sending.",
            severity: .warning
        ))
        
        FeeWarningView(warning: FeeWarning(
            type: .lowFeeRate,
            title: "Fee Too Low",
            message: "Your transaction may never confirm.",
            severity: .critical
        ))
        
        FeeWarningView(warning: FeeWarning(
            type: .slowConfirmation,
            title: "Slow Confirmation",
            message: "Expected wait: 2+ hours",
            severity: .info
        ))
    }
    .padding()
}
#endif
#endif
#endif
