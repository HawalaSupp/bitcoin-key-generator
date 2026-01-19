import SwiftUI

// MARK: - Asset Detail View (Ledger Live Style)
struct HawalaAssetDetailView: View {
    let chain: ChainInfo
    @Binding var balanceState: ChainBalanceState?
    @Binding var priceState: ChainPriceState?
    let sparklineData: [Double]
    let onSend: () -> Void
    let onReceive: () -> Void
    let onClose: () -> Void
    let selectedFiatSymbol: String
    let fxMultiplier: Double
    
    @State private var selectedTimeframe: Timeframe = .week
    @State private var showTransactions = true
    
    enum Timeframe: String, CaseIterable {
        case day = "1D"
        case week = "1W"
        case month = "1M"
        case year = "1Y"
        case all = "All"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            ScrollView {
                VStack(spacing: HawalaTheme.Spacing.xl) {
                    // Balance section
                    balanceSection
                    
                    // Chart section
                    chartSection
                    
                    // Action buttons
                    actionButtonsRow
                    
                    // Address section
                    addressSection
                    
                    // Transactions
                    transactionsSection
                }
                .padding(HawalaTheme.Spacing.xl)
            }
        }
        .background(HawalaTheme.Colors.background)
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            Button(action: onClose) {
                HStack(spacing: HawalaTheme.Spacing.sm) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Back")
                        .font(HawalaTheme.Typography.body)
                }
                .foregroundColor(HawalaTheme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Chain icon and name
            HStack(spacing: HawalaTheme.Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(HawalaTheme.Colors.forChain(chain.id).opacity(0.15))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: chain.iconName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(HawalaTheme.Colors.forChain(chain.id))
                }
                
                Text(chain.title)
                    .font(HawalaTheme.Typography.h4)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
            }
            
            Spacer()
            
            // More options
            HawalaIconButton("ellipsis") {}
        }
        .padding(.horizontal, HawalaTheme.Spacing.xl)
        .padding(.vertical, HawalaTheme.Spacing.lg)
        .background(HawalaTheme.Colors.backgroundSecondary)
    }
    
    // MARK: - Balance Section
    private var balanceSection: some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            // Crypto balance
            VStack(spacing: HawalaTheme.Spacing.xs) {
                Text(formattedCryptoBalance)
                    .font(HawalaTheme.Typography.display(42))
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text(chainSymbol)
                    .font(HawalaTheme.Typography.h4)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
            }
            
            // Fiat value
            Text(formattedFiatValue)
                .font(HawalaTheme.Typography.h3)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
            
            // Price change
            if let change = priceChange {
                HStack(spacing: HawalaTheme.Spacing.xs) {
                    Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 12, weight: .semibold))
                    Text(String(format: "%+.2f%%", change))
                        .font(HawalaTheme.Typography.bodySmall)
                        .fontWeight(.semibold)
                    Text("24h")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
                .foregroundColor(change >= 0 ? HawalaTheme.Colors.success : HawalaTheme.Colors.error)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, HawalaTheme.Spacing.lg)
    }
    
    // MARK: - Chart Section
    private var chartSection: some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            // Timeframe selector
            HStack(spacing: HawalaTheme.Spacing.xs) {
                ForEach(Timeframe.allCases, id: \.self) { timeframe in
                    Button {
                        withAnimation(HawalaTheme.Animation.fast) {
                            selectedTimeframe = timeframe
                        }
                    } label: {
                        Text(timeframe.rawValue)
                            .font(HawalaTheme.Typography.caption)
                            .fontWeight(selectedTimeframe == timeframe ? .semibold : .regular)
                            .foregroundColor(selectedTimeframe == timeframe ? HawalaTheme.Colors.textPrimary : HawalaTheme.Colors.textTertiary)
                            .padding(.horizontal, HawalaTheme.Spacing.md)
                            .padding(.vertical, HawalaTheme.Spacing.sm)
                            .background(
                                selectedTimeframe == timeframe ? HawalaTheme.Colors.backgroundTertiary : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(HawalaTheme.Spacing.xs)
            .background(HawalaTheme.Colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
            
            // Chart
            ChartView(data: sparklineData, color: HawalaTheme.Colors.forChain(chain.id))
                .frame(height: 180)
                .hawalaCard(padding: HawalaTheme.Spacing.md)
        }
    }
    
    // MARK: - Action Buttons
    private var actionButtonsRow: some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            // Send button
            Button(action: onSend) {
                VStack(spacing: HawalaTheme.Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(HawalaTheme.Colors.accent)
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    Text("Send")
                        .font(HawalaTheme.Typography.caption)
                        .fontWeight(.medium)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                }
            }
            .buttonStyle(.plain)
            
            // Receive button
            Button(action: onReceive) {
                VStack(spacing: HawalaTheme.Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(HawalaTheme.Colors.success)
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "arrow.down")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    Text("Receive")
                        .font(HawalaTheme.Typography.caption)
                        .fontWeight(.medium)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                }
            }
            .buttonStyle(.plain)
            
            // Swap button (placeholder)
            Button {} label: {
                VStack(spacing: HawalaTheme.Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(HawalaTheme.Colors.backgroundTertiary)
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                    }
                    
                    Text("Swap")
                        .font(HawalaTheme.Typography.caption)
                        .fontWeight(.medium)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(true)
            
            // Buy button (placeholder)
            Button {} label: {
                VStack(spacing: HawalaTheme.Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(HawalaTheme.Colors.backgroundTertiary)
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "creditcard")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                    }
                    
                    Text("Buy")
                        .font(HawalaTheme.Typography.caption)
                        .fontWeight(.medium)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, HawalaTheme.Spacing.md)
    }
    
    // MARK: - Address Section
    private var addressSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
            Text("Your Address")
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
            
            HStack {
                Text(chain.receiveAddress ?? "No address")
                    .font(HawalaTheme.Typography.mono)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
                
                Button {
                    if let address = chain.receiveAddress {
                        copyToClipboard(address)
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundColor(HawalaTheme.Colors.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(HawalaTheme.Spacing.md)
            .background(HawalaTheme.Colors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
        }
        .hawalaCard()
    }
    
    // MARK: - Transactions Section
    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            HStack {
                Text("Recent Transactions")
                    .font(HawalaTheme.Typography.h4)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Spacer()
                
                Button {
                    // View all
                } label: {
                    Text("View All")
                        .font(HawalaTheme.Typography.caption)
                        .fontWeight(.medium)
                        .foregroundColor(HawalaTheme.Colors.accent)
                }
                .buttonStyle(.plain)
            }
            
            // Placeholder transactions
            VStack(spacing: 0) {
                ForEach(0..<3) { _ in
                    HawalaTransactionRow(
                        type: .receive,
                        amount: "0.001",
                        symbol: chainSymbol,
                        fiatValue: "\(selectedFiatSymbol)50.00",
                        date: "Nov 24",
                        status: .confirmed,
                        counterparty: truncateAddress(chain.receiveAddress ?? "")
                    )
                    
                    Divider()
                        .background(HawalaTheme.Colors.divider)
                        .padding(.horizontal, HawalaTheme.Spacing.md)
                }
            }
            .hawalaCard(padding: 0)
        }
    }
    
    // MARK: - Computed Properties
    
    private var chainSymbol: String {
        switch chain.id {
        case "bitcoin", "bitcoin-testnet": return "BTC"
        case "ethereum", "ethereum-sepolia": return "ETH"
        case "litecoin": return "LTC"
        case "solana": return "SOL"
        case "xrp": return "XRP"
        case "bnb": return "BNB"
        case "monero": return "XMR"
        // New chains from wallet-core integration
        case "ton": return "TON"
        case "aptos": return "APT"
        case "sui": return "SUI"
        case "polkadot": return "DOT"
        case "kusama": return "KSM"
        default: return chain.id.uppercased()
        }
    }
    
    private var formattedCryptoBalance: String {
        guard let state = balanceState, case .loaded(let balanceStr, _) = state else {
            return "0.000000"
        }
        if let balance = Double(balanceStr) {
            return String(format: "%.6f", balance)
        }
        return balanceStr
    }
    
    private var formattedFiatValue: String {
        guard let balState = balanceState, case .loaded(let balanceStr, _) = balState,
              let balance = Double(balanceStr),
              let prState = priceState, case .loaded(let priceStr, _) = prState,
              let price = Double(priceStr) else {
            return "\(selectedFiatSymbol)--"
        }
        let value = balance * price * fxMultiplier
        return "\(selectedFiatSymbol)\(String(format: "%.2f", value))"
    }
    
    private var priceChange: Double? {
        // Price change would need to be stored separately or calculated
        // For now return nil
        return nil
    }
    
    private func truncateAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        let start = address.prefix(6)
        let end = address.suffix(4)
        return "\(start)...\(end)"
    }
    
    private func copyToClipboard(_ text: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

// MARK: - Chart View
struct ChartView: View {
    let data: [Double]
    let color: Color
    
    var body: some View {
        GeometryReader { geo in
            if data.count >= 2 {
                let minVal = data.min() ?? 0
                let maxVal = data.max() ?? 1
                let range = max(maxVal - minVal, 0.0001)
                
                ZStack {
                    // Grid lines
                    VStack {
                        ForEach(0..<4) { _ in
                            Divider()
                                .background(HawalaTheme.Colors.border)
                            Spacer()
                        }
                        Divider()
                            .background(HawalaTheme.Colors.border)
                    }
                    
                    // Gradient fill
                    Path { path in
                        let stepX = geo.size.width / CGFloat(data.count - 1)
                        
                        path.move(to: CGPoint(x: 0, y: geo.size.height))
                        
                        for (index, value) in data.enumerated() {
                            let x = stepX * CGFloat(index)
                            let normalizedY = (value - minVal) / range
                            let y = geo.size.height - (normalizedY * geo.size.height)
                            
                            if index == 0 {
                                path.addLine(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                        
                        path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.3), color.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    // Line
                    Path { path in
                        let stepX = geo.size.width / CGFloat(data.count - 1)
                        
                        for (index, value) in data.enumerated() {
                            let x = stepX * CGFloat(index)
                            let normalizedY = (value - minVal) / range
                            let y = geo.size.height - (normalizedY * geo.size.height)
                            
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            } else {
                // No data placeholder
                VStack {
                    Spacer()
                    Text("No chart data available")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
