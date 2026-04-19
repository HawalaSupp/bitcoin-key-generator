import SwiftUI

// MARK: - L2 Balance Aggregator View
/// Shows aggregated ETH balances across Ethereum L1 and L2 chains
/// with smart chain suggestions for optimal transactions
struct L2BalanceAggregatorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var aggregatedBalance: HawalaBridge.AggregatedBalance?
    @State private var suggestion: HawalaBridge.SuggestionResult?
    @State private var selectedToken = "ETH"
    @State private var sendAmount = ""
    @State private var error: String?
    @State private var appearAnimation = false
    
    let address: String
    
    private let supportedTokens = ["ETH", "USDC", "USDT", "DAI", "WETH"]
    
    var body: some View {
        ZStack {
            HawalaTheme.Colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                Divider()
                    .background(HawalaTheme.Colors.divider)
                
                // Content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: HawalaTheme.Spacing.lg) {
                        // Token selector
                        tokenSelectorSection
                        
                        // Total balance card
                        if let balance = aggregatedBalance {
                            totalBalanceCard(balance: balance)
                        }
                        
                        // Chain breakdown
                        if let balance = aggregatedBalance {
                            chainBreakdownSection(balance: balance)
                        }
                        
                        // Smart send section
                        smartSendSection
                        
                        // Chain suggestion
                        if let suggestion = suggestion {
                            chainSuggestionCard(suggestion: suggestion)
                        }
                    }
                    .padding(.horizontal, HawalaTheme.Spacing.lg)
                    .padding(.vertical, HawalaTheme.Spacing.md)
                }
                
                if isLoading {
                    ProgressView()
                        .padding()
                }
            }
            
            // Error toast
            if let error = error {
                VStack {
                    Spacer()
                    errorToast(message: error)
                        .padding(.bottom, 40)
                }
            }
        }
        .frame(minWidth: 500, idealWidth: 600, minHeight: 500, idealHeight: 650)
        .onAppear {
            withAnimation(HawalaTheme.Animation.spring) {
                appearAnimation = true
            }
            Task { await fetchBalances() }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
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
                Text("L2 Balance Aggregator")
                    .font(HawalaTheme.Typography.h3)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text("View balances across all EVM chains")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
            }
            
            Spacer()
            
            Button(action: { Task { await fetchBalances() } }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
        .padding()
    }
    
    // MARK: - Token Selector
    
    private var tokenSelectorSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
            Text("TOKEN")
                .font(HawalaTheme.Typography.label)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
            
            HStack(spacing: HawalaTheme.Spacing.sm) {
                ForEach(supportedTokens, id: \.self) { token in
                    Button(action: {
                        selectedToken = token
                        Task { await fetchBalances() }
                    }) {
                        Text(token)
                            .font(HawalaTheme.Typography.captionBold)
                            .foregroundColor(selectedToken == token ? .white : HawalaTheme.Colors.textSecondary)
                            .padding(.horizontal, HawalaTheme.Spacing.md)
                            .padding(.vertical, HawalaTheme.Spacing.sm)
                            .background(
                                selectedToken == token
                                    ? HawalaTheme.Colors.accent
                                    : HawalaTheme.Colors.backgroundTertiary
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Total Balance Card
    
    private func totalBalanceCard(balance: HawalaBridge.AggregatedBalance) -> some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            HStack {
                Image(systemName: "wallet.pass.fill")
                    .font(.system(size: 24))
                    .foregroundColor(HawalaTheme.Colors.ethereum)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total \(selectedToken) Balance")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                    
                    Text(balance.totalAmount)
                        .font(HawalaTheme.Typography.display(32))
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("USD Value")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                    
                    Text("$\(String(format: "%.2f", balance.totalUsd))")
                        .font(HawalaTheme.Typography.h2)
                        .foregroundColor(HawalaTheme.Colors.success)
                }
            }
            
            HStack {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                
                Text("\(balance.chainCount) chains")
                    .font(HawalaTheme.Typography.bodySmall)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                
                Spacer()
                
                Text(selectedToken)
                    .font(HawalaTheme.Typography.captionBold)
                    .foregroundColor(HawalaTheme.Colors.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(HawalaTheme.Colors.accentSubtle)
                    .clipShape(Capsule())
            }
        }
        .padding(HawalaTheme.Spacing.lg)
        .background(HawalaTheme.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg)
                .strokeBorder(HawalaTheme.Colors.border, lineWidth: 1)
        )
    }
    
    // MARK: - Chain Breakdown
    
    private func chainBreakdownSection(balance: HawalaBridge.AggregatedBalance) -> some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            Text("CHAIN BREAKDOWN")
                .font(HawalaTheme.Typography.label)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
            
            ForEach(balance.chains, id: \.chain) { chainBalance in
                chainBalanceRow(chainBalance: chainBalance, total: balance.totalUsd)
            }
        }
    }
    
    private func chainBalanceRow(chainBalance: HawalaBridge.ChainBalance, total: Double) -> some View {
        let percentage = total > 0 ? (chainBalance.usdValue / total) * 100 : 0
        
        return HStack(spacing: HawalaTheme.Spacing.md) {
            // Chain icon
            chainIcon(chain: chainBalance.chain, isL2: chainBalance.isL2)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(chainBalance.chain.capitalized)
                        .font(HawalaTheme.Typography.body)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    
                    if chainBalance.isL2 {
                        Text("L2")
                            .font(HawalaTheme.Typography.label)
                            .foregroundColor(HawalaTheme.Colors.info)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(HawalaTheme.Colors.info.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                
                Text(chainBalance.amountDecimal)
                    .font(HawalaTheme.Typography.mono)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("$\(String(format: "%.2f", chainBalance.usdValue))")
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text("\(String(format: "%.1f", percentage))%")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
        }
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
    }
    
    private func chainIcon(chain: String, isL2: Bool) -> some View {
        let color: Color = {
            switch chain.lowercased() {
            case "ethereum": return HawalaTheme.Colors.ethereum
            case "arbitrum": return Color(hex: "28A0F0")
            case "optimism": return Color(hex: "FF0420")
            case "base": return Color(hex: "0052FF")
            case "polygon": return Color(hex: "8247E5")
            case "bsc", "bnb": return HawalaTheme.Colors.bnb
            case "avalanche": return Color(hex: "E84142")
            default: return HawalaTheme.Colors.textSecondary
            }
        }()
        
        return ZStack {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: 40, height: 40)
            
            Image(systemName: isL2 ? "square.stack.3d.up" : "circle.hexagonpath")
                .font(.system(size: 16))
                .foregroundColor(color)
        }
    }
    
    // MARK: - Smart Send Section
    
    private var smartSendSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
            Text("SMART SEND")
                .font(HawalaTheme.Typography.label)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
            
            HStack(spacing: HawalaTheme.Spacing.md) {
                TextField("Amount to send", text: $sendAmount)
                    .textFieldStyle(.plain)
                    .font(HawalaTheme.Typography.body)
                    .padding(HawalaTheme.Spacing.md)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                
                Button(action: { Task { await getSuggestion() } }) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Suggest Chain")
                    }
                    .font(HawalaTheme.Typography.captionBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, HawalaTheme.Spacing.md)
                    .padding(.vertical, HawalaTheme.Spacing.md)
                    .background(HawalaTheme.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                }
                .buttonStyle(.plain)
                .disabled(sendAmount.isEmpty)
            }
            
            Text("Enter an amount to get the optimal chain suggestion based on fees and balance")
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
        }
    }
    
    // MARK: - Chain Suggestion Card
    
    private func chainSuggestionCard(suggestion: HawalaBridge.SuggestionResult) -> some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(HawalaTheme.Colors.warning)
                
                Text("RECOMMENDED")
                    .font(HawalaTheme.Typography.label)
                    .foregroundColor(HawalaTheme.Colors.warning)
                
                Spacer()
            }
            
            // Recommended chain
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                HStack {
                    chainIcon(chain: suggestion.recommended.chain, isL2: true)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.recommended.chain.capitalized)
                            .font(HawalaTheme.Typography.h4)
                            .foregroundColor(HawalaTheme.Colors.textPrimary)
                        
                        Text(suggestion.recommended.reason)
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("~$\(String(format: "%.2f", suggestion.recommended.estimatedFeeUsd))")
                            .font(HawalaTheme.Typography.body)
                            .foregroundColor(HawalaTheme.Colors.success)
                        
                        Text("est. fee")
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                    }
                }
                .padding(HawalaTheme.Spacing.md)
                .background(HawalaTheme.Colors.success.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                        .strokeBorder(HawalaTheme.Colors.success.opacity(0.3), lineWidth: 1)
                )
            }
            
            // Alternatives
            if !suggestion.alternatives.isEmpty {
                Text("ALTERNATIVES")
                    .font(HawalaTheme.Typography.label)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                    .padding(.top, HawalaTheme.Spacing.sm)
                
                ForEach(suggestion.alternatives, id: \.chain) { alt in
                    HStack {
                        Text(alt.chain.capitalized)
                            .font(HawalaTheme.Typography.body)
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                        
                        Spacer()
                        
                        Text("~$\(String(format: "%.2f", alt.estimatedFeeUsd))")
                            .font(HawalaTheme.Typography.bodySmall)
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                    }
                    .padding(HawalaTheme.Spacing.sm)
                }
            }
        }
        .padding(HawalaTheme.Spacing.lg)
        .background(HawalaTheme.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg))
    }
    
    // MARK: - Error Toast
    
    private func errorToast(message: String) -> some View {
        HStack(spacing: HawalaTheme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(HawalaTheme.Colors.error)
            
            Text(message)
                .font(HawalaTheme.Typography.bodySmall)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
        }
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.error.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
    }
    
    // MARK: - Data Fetching
    
    private func fetchBalances() async {
        isLoading = true
        error = nil
        
        do {
            aggregatedBalance = try HawalaBridge.shared.aggregateBalances(
                address: address,
                token: selectedToken
            )
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func getSuggestion() async {
        guard !sendAmount.isEmpty else { return }
        
        isLoading = true
        error = nil
        
        do {
            suggestion = try HawalaBridge.shared.suggestChain(
                address: address,
                token: selectedToken,
                amount: sendAmount
            )
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
}

// MARK: - Preview

#if DEBUG
struct L2BalanceAggregatorView_Previews: PreviewProvider {
    static var previews: some View {
        L2BalanceAggregatorView(address: "0x742d35Cc6634C0532925a3b844Bc9e7595f1dE3E")
            .preferredColorScheme(.dark)
    }
}
#endif
