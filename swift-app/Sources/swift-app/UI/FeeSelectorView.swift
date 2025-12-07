import SwiftUI

// MARK: - Fee Selector View

/// A reusable fee selector with Slow/Average/Fast options
struct FeeSelectorView: View {
    let chain: FeeChain
    @Binding var selectedPriority: FeePriority
    let estimates: [FeeEstimate]
    let isLoading: Bool
    let onRefresh: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    enum FeeChain {
        case bitcoin
        case ethereum
        
        var unit: String {
            switch self {
            case .bitcoin: return "sat/vB"
            case .ethereum: return "Gwei"
            }
        }
        
        var nativeSymbol: String {
            switch self {
            case .bitcoin: return "BTC"
            case .ethereum: return "ETH"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with refresh
            HStack {
                Text("Network Fee")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: onRefresh) {
                    HStack(spacing: 4) {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                        }
                        Text("Refresh")
                            .font(.caption)
                    }
                }
                .disabled(isLoading)
                .foregroundColor(.blue)
            }
            
            // Fee options
            HStack(spacing: 8) {
                ForEach(FeePriority.allCases) { priority in
                    FeeOptionCard(
                        priority: priority,
                        estimate: estimates.first { $0.priority == priority },
                        chain: chain,
                        isSelected: selectedPriority == priority,
                        isLoading: isLoading
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            selectedPriority = priority
                        }
                    }
                }
            }
            
            // Selected fee details
            if let selectedEstimate = estimates.first(where: { $0.priority == selectedPriority }) {
                selectedFeeDetails(selectedEstimate)
            }
        }
    }
    
    @ViewBuilder
    private func selectedFeeDetails(_ estimate: FeeEstimate) -> some View {
        VStack(spacing: 8) {
            Divider()
                .padding(.vertical, 4)
            
            HStack {
                Text("Estimated Fee")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatFee(estimate.estimatedFee))
                        .font(.subheadline.weight(.medium))
                    
                    if let fiat = estimate.fiatValue {
                        Text("≈ $\(String(format: "%.2f", fiat))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            HStack {
                Text("Confirmation Time")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(estimate.estimatedTime)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 4)
    }
    
    private func formatFee(_ fee: Double) -> String {
        if fee < 0.0001 {
            return String(format: "%.8f %@", fee, chain.nativeSymbol)
        } else if fee < 0.01 {
            return String(format: "%.6f %@", fee, chain.nativeSymbol)
        } else {
            return String(format: "%.4f %@", fee, chain.nativeSymbol)
        }
    }
}

// MARK: - Fee Option Card

struct FeeOptionCard: View {
    let priority: FeePriority
    let estimate: FeeEstimate?
    let chain: FeeSelectorView.FeeChain
    let isSelected: Bool
    let isLoading: Bool
    let onSelect: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                // Icon
                Image(systemName: priority.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isSelected ? .white : iconColor)
                
                // Label
                Text(priority.rawValue)
                    .font(.caption.weight(.medium))
                    .foregroundColor(isSelected ? .white : .primary)
                
                // Fee rate
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(height: 14)
                } else if let estimate = estimate {
                    Text("\(estimate.formattedFeeRate)")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
                    
                    Text(chain.unit)
                        .font(.system(size: 8))
                        .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                } else {
                    Text("--")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // Time estimate
                Text(chain == .bitcoin ? priority.description : priority.ethDescription)
                    .font(.system(size: 9))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? selectedBackground : cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.clear : borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var iconColor: Color {
        switch priority {
        case .slow: return .green
        case .average: return .orange
        case .fast: return .red
        }
    }
    
    private var selectedBackground: Color {
        switch priority {
        case .slow: return .green
        case .average: return .orange
        case .fast: return .red
        }
    }
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
    }
    
    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)
    }
}

// MARK: - Custom Fee Input View

struct CustomFeeInputView: View {
    let chain: FeeSelectorView.FeeChain
    @Binding var customFeeRate: String
    @Binding var useCustomFee: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $useCustomFee) {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.secondary)
                    Text("Custom Fee")
                        .font(.subheadline)
                }
            }
            .toggleStyle(.switch)
            
            if useCustomFee {
                HStack {
                    TextField("Fee Rate", text: $customFeeRate)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    
                    Text(chain.unit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: useCustomFee)
    }
}

// MARK: - Preview

#if DEBUG
struct FeeSelectorView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 32) {
            FeeSelectorView(
                chain: .bitcoin,
                selectedPriority: .constant(.average),
                estimates: [
                    FeeEstimate(priority: .slow, feeRate: 2, estimatedFee: 0.00000280, estimatedTime: "~60 min", fiatValue: 0.12),
                    FeeEstimate(priority: .average, feeRate: 5, estimatedFee: 0.00000700, estimatedTime: "~30 min", fiatValue: 0.30),
                    FeeEstimate(priority: .fast, feeRate: 12, estimatedFee: 0.00001680, estimatedTime: "~10 min", fiatValue: 0.72)
                ],
                isLoading: false,
                onRefresh: {}
            )
            
            FeeSelectorView(
                chain: .ethereum,
                selectedPriority: .constant(.fast),
                estimates: [
                    FeeEstimate(priority: .slow, feeRate: 12, estimatedFee: 0.000252, estimatedTime: "~5 min", fiatValue: 0.65),
                    FeeEstimate(priority: .average, feeRate: 20, estimatedFee: 0.00042, estimatedTime: "~2 min", fiatValue: 1.08),
                    FeeEstimate(priority: .fast, feeRate: 35, estimatedFee: 0.000735, estimatedTime: "~30 sec", fiatValue: 1.89)
                ],
                isLoading: false,
                onRefresh: {}
            )
        }
        .padding()
    }
}
#endif
