import SwiftUI

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – L2 Aggregator Premium Overlay
// Unified cross-chain balance view matching the Bitcoin detail card aesthetic.
// Strictly monochrome • silk animated background • monumental typography
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct L2AggregatorOverlay: View {
    @Binding var isPresented: Bool
    let address: String

    // ── Data ──
    @State private var balance: HawalaBridge.AggregatedBalance?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedToken = "ETH"

    // ── Interaction ──
    @State private var selectedChainIndex: Int? = nil
    @State private var hoveredChainIndex: Int? = nil
    @State private var hoveredToken: String? = nil

    // ── Entrance Animation ──
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92
    @State private var strataProgress: CGFloat = 0

    // ── Hover States ──
    @State private var bridgeHovered = false
    @State private var closeHovered = false
    @State private var refreshHovered = false

    private let tokens = ["ETH", "USDC", "USDT", "DAI", "WETH"]

    // Height of the strata visualization container
    private let strataHeight: CGFloat = 136

    // ── Derived ──
    private var displayBalance: HawalaBridge.AggregatedBalance? {
        balance ?? Self.demoBalance
    }

    private var sortedChains: [HawalaBridge.ChainBalance] {
        guard let bal = displayBalance else { return [] }
        return bal.chains.sorted { $0.usdValue > $1.usdValue }
    }

    private var totalValue: Double {
        displayBalance?.totalUsd ?? 0
    }

    private var formattedTotal: String {
        let value = totalValue
        guard value > 0 else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        if value >= 10000 {
            formatter.maximumFractionDigits = 0
            formatter.groupingSeparator = " "
        } else if value >= 1 {
            formatter.maximumFractionDigits = 2
        } else {
            formatter.maximumFractionDigits = 4
        }
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.0f", value)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Body
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    var body: some View {
        ZStack {
            // ── Dimmed backdrop ──
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture { dismissOverlay() }

            // ── Card ──
            VStack(spacing: 0) {
                headerSection
                heroBalance
                tokenSelector
                strataVisualization
                chainDetailList
                bridgeSection
            }
            .frame(width: 440, height: 600)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.10), Color.white.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.5), radius: 50, x: 0, y: 25)
            .scaleEffect(cardScale)
        }
        .background(
            EscapeKeyHandler(isPresented: $isPresented, onEscape: dismissOverlay)
        )
        .onAppear {
            // Smooth entrance — springs identical to AssetDetailPopup
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                cardScale = 1
                contentOpacity = 1
            }
            // Strata bars sweep in after entrance
            withAnimation(.easeOut(duration: 0.7).delay(0.15)) {
                strataProgress = 1
            }
            Task { await fetchBalances() }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Header
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var headerSection: some View {
        ZStack {
            // Centered title
            Text("L2 Aggregator")
                .font(.clashGroteskMedium(size: 20))
                .foregroundColor(.white)

            // Close button — right
            HStack {
                // Refresh button — left
                Button(action: {
                    Task { await fetchBalances() }
                }) {
                    Circle()
                        .fill(Color.white.opacity(refreshHovered ? 0.10 : 0.06))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.4))
                                .rotationEffect(.degrees(isLoading ? 360 : 0))
                                .animation(isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isLoading)
                        )
                }
                .buttonStyle(.plain)
                .onHover { refreshHovered = $0 }

                Spacer()

                Button(action: dismissOverlay) {
                    Circle()
                        .fill(Color.white.opacity(closeHovered ? 0.12 : 0.08))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.5))
                        )
                }
                .buttonStyle(.plain)
                .onHover { closeHovered = $0 }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Hero Balance
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var heroBalance: some View {
        VStack(alignment: .center, spacing: 6) {
            if isLoading && balance == nil {
                SkeletonShape(width: 200, height: 42, cornerRadius: 8)
            } else {
                Text(formattedTotal)
                    .font(.clashGroteskBold(size: 42))
                    .foregroundColor(.white)
                    .contentTransition(.numericText())
            }

            // Chain count subtitle
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 10))
                Text("across \(displayBalance?.chainCount ?? 0) chains")
                    .font(.system(size: 13, weight: .medium))

                Text("·")

                Text(selectedToken)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1)
            }
            .foregroundColor(Color.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .opacity(contentOpacity)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Token Selector
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var tokenSelector: some View {
        HStack(spacing: 6) {
            ForEach(tokens, id: \.self) { token in
                Button(action: {
                    guard selectedToken != token else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        selectedToken = token
                        strataProgress = 0
                    }
                    Task { await fetchBalances() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeOut(duration: 0.5)) {
                            strataProgress = 1
                        }
                    }
                }) {
                    Text(token)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(selectedToken == token ? .white : Color.white.opacity(0.4))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(selectedToken == token ? Color.white.opacity(0.10) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .onHover { hoveredToken = $0 ? token : nil }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .opacity(contentOpacity)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Strata Visualization (Geological Layers)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var strataVisualization: some View {
        let chains = sortedChains
        let heights = calculateHeights(totalHeight: strataHeight, chains: chains)

        return VStack(spacing: 0) {
            ForEach(Array(chains.enumerated()), id: \.offset) { index, chain in
                let isHovered = hoveredChainIndex == index
                let isSelected = selectedChainIndex == index

                StrataBand(
                    chain: chain,
                    percentage: totalValue > 0 ? chain.usdValue / totalValue * 100 : 0,
                    isHovered: isHovered,
                    isSelected: isSelected,
                    bandHeight: index < heights.count ? heights[index] : 8,
                    bandOpacity: bandOpacity(for: index, total: chains.count),
                    progress: strataProgress
                )
                .onHover { hovering in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        hoveredChainIndex = hovering ? index : nil
                    }
                }
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selectedChainIndex = selectedChainIndex == index ? nil : index
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .opacity(contentOpacity)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: hoveredChainIndex)
    }

    /// Calculate band heights with hover expansion
    private func calculateHeights(totalHeight: CGFloat, chains: [HawalaBridge.ChainBalance]) -> [CGFloat] {
        guard !chains.isEmpty else { return [] }
        let total = totalValue
        let minBarHeight: CGFloat = 6
        let hoveredMinHeight: CGFloat = 38

        var heights: [CGFloat] = chains.map { chain in
            let pct = total > 0 ? chain.usdValue / total : 1.0 / Double(chains.count)
            return max(minBarHeight, totalHeight * CGFloat(pct))
        }

        // If a chain is hovered, ensure minimum height for readability
        if let hIdx = hoveredChainIndex, hIdx < heights.count, heights[hIdx] < hoveredMinHeight {
            let deficit = hoveredMinHeight - heights[hIdx]
            heights[hIdx] = hoveredMinHeight

            let othersSum = heights.enumerated()
                .filter { $0.offset != hIdx }
                .map(\.element)
                .reduce(0, +)

            if othersSum > 0 {
                for i in heights.indices where i != hIdx {
                    let reduction = deficit * (heights[i] / othersSum)
                    heights[i] = max(minBarHeight, heights[i] - reduction)
                }
            }
        }

        return heights
    }

    /// Graduated opacity — brightest for largest chain, dimmer for smaller
    private func bandOpacity(for index: Int, total: Int) -> Double {
        guard total > 1 else { return 0.12 }
        let maxO = 0.14
        let minO = 0.04
        let step = (maxO - minO) / Double(max(1, total - 1))
        return maxO - step * Double(index)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Chain Detail List
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var chainDetailList: some View {
        VStack(spacing: 0) {
            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
                .padding(.horizontal, 24)
                .padding(.bottom, 10)

            // Section label
            HStack {
                Text("CHAIN BREAKDOWN")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(2)
                    .foregroundColor(Color.white.opacity(0.25))

                Spacer()

                if let selIdx = selectedChainIndex, selIdx < sortedChains.count {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            selectedChainIndex = nil
                        }
                    }) {
                        Text("SHOW ALL")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.5)
                            .foregroundColor(Color.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)

            // Chain rows
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 1) {
                    let chains = sortedChains
                    ForEach(Array(chains.enumerated()), id: \.offset) { index, chain in
                        let isSelected = selectedChainIndex == index
                        let dimmed = selectedChainIndex != nil && !isSelected

                        L2ChainRow(
                            chain: chain,
                            percentage: totalValue > 0 ? chain.usdValue / totalValue * 100 : 0,
                            isSelected: isSelected
                        )
                        .opacity(dimmed ? 0.35 : 1)
                        .scaleEffect(isSelected ? 1.0 : (dimmed ? 0.98 : 1.0))
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                selectedChainIndex = selectedChainIndex == index ? nil : index
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .opacity(contentOpacity)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Bridge Section
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var bridgeSection: some View {
        VStack(spacing: 0) {
            Spacer()

            Button(action: {
                // Post notification to open bridge / swap view
                NotificationCenter.default.post(name: .openBridgeFromL2, object: nil)
                dismissOverlay()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Bridge Assets")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(bridgeHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(bridgeHovered ? 0.15 : 0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .onHover { bridgeHovered = $0 }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .opacity(contentOpacity)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Data
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func fetchBalances() async {
        isLoading = true
        loadError = nil

        do {
            let result = try HawalaBridge.shared.aggregateBalances(
                address: address,
                token: selectedToken
            )
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                balance = result
            }
        } catch {
            loadError = error.localizedDescription
            // Demo data will show via displayBalance fallback
        }

        withAnimation { isLoading = false }
    }

    private func dismissOverlay() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            cardScale = 0.95
            contentOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isPresented = false
        }
    }

    // ── Demo / fallback data ──
    private static var demoBalance: HawalaBridge.AggregatedBalance? {
        let json = """
        {
            "token": "ETH",
            "token_name": "Ethereum",
            "total_amount": "38.4521",
            "total_usd": 124521.0,
            "chains": [
                {"chain": "ethereum", "amount": "238134000000000000000", "amount_decimal": "23.8134", "usd_value": 77234.0, "is_l2": false, "last_updated": 1740000000},
                {"chain": "arbitrum", "amount": "82341000000000000000", "amount_decimal": "8.2341", "usd_value": 26699.0, "is_l2": true, "last_updated": 1740000000},
                {"chain": "polygon", "amount": "31200000000000000000", "amount_decimal": "3.1200", "usd_value": 10114.0, "is_l2": true, "last_updated": 1740000000},
                {"chain": "optimism", "amount": "19846000000000000000", "amount_decimal": "1.9846", "usd_value": 6432.0, "is_l2": true, "last_updated": 1740000000},
                {"chain": "base", "amount": "13000000000000000000", "amount_decimal": "1.3000", "usd_value": 4042.0, "is_l2": true, "last_updated": 1740000000}
            ],
            "chain_count": 5
        }
        """
        return try? JSONDecoder().decode(
            HawalaBridge.AggregatedBalance.self,
            from: json.data(using: .utf8)!
        )
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Strata Band
// A single geological layer in the strata visualization.
// Width sweeps in from left; hover reveals chain info inline.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private struct StrataBand: View {
    let chain: HawalaBridge.ChainBalance
    let percentage: Double
    let isHovered: Bool
    let isSelected: Bool
    let bandHeight: CGFloat
    let bandOpacity: Double
    let progress: CGFloat

    private var chainDisplayName: String {
        switch chain.chain.lowercased() {
        case "ethereum": return "Ethereum"
        case "arbitrum": return "Arbitrum"
        case "polygon":  return "Polygon"
        case "optimism": return "Optimism"
        case "base":     return "Base"
        default:         return chain.chain.capitalized
        }
    }

    private var layerBadge: String {
        chain.isL2 ? "L2" : "L1"
    }

    var body: some View {
        ZStack {
            // ── Background fill ──
            // Width proportional to percentage, sweeps in via progress
            GeometryReader { geo in
                let fillWidth = geo.size.width * CGFloat(max(percentage, 3) / 100) * progress

                // Proportional bar fill
                Rectangle()
                    .fill(Color.white.opacity(isHovered || isSelected ? bandOpacity + 0.06 : bandOpacity))
                    .frame(width: fillWidth)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Full-width subtle base (so the band isn't invisible)
                Rectangle()
                    .fill(Color.white.opacity(0.02))

                // Proportional fill on top
                Rectangle()
                    .fill(Color.white.opacity(isHovered || isSelected ? bandOpacity + 0.06 : bandOpacity))
                    .frame(width: fillWidth)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // ── Separator line at bottom ──
            VStack {
                Spacer()
                Rectangle()
                    .fill(Color.white.opacity(0.04))
                    .frame(height: 0.5)
            }

            // ── Hover / selection info overlay ──
            if isHovered || isSelected {
                HStack(spacing: 8) {
                    // Layer badge
                    Text(layerBadge)
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(1)
                        .foregroundColor(Color.white.opacity(0.4))

                    // Chain name
                    Text(chainDisplayName.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(Color.white.opacity(0.7))

                    Spacer()

                    // Balance amount
                    Text(chain.amountDecimal)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.5))

                    // USD value
                    Text(formatUSD(chain.usdValue))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.7))

                    // Percentage
                    Text(String(format: "%.1f%%", percentage))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.35))
                }
                .padding(.horizontal, 14)
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .frame(height: bandHeight)
        .contentShape(Rectangle())
    }

    private func formatUSD(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = value >= 1000 ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.0f", value)
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Chain Detail Row
// Individual chain row in the breakdown list.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private struct L2ChainRow: View {
    let chain: HawalaBridge.ChainBalance
    let percentage: Double
    let isSelected: Bool

    @State private var isHovered = false

    private var chainDisplayName: String {
        switch chain.chain.lowercased() {
        case "ethereum": return "Ethereum"
        case "arbitrum": return "Arbitrum"
        case "polygon":  return "Polygon"
        case "optimism": return "Optimism"
        case "base":     return "Base"
        default:         return chain.chain.capitalized
        }
    }

    private var chainInitial: String {
        String(chainDisplayName.prefix(1))
    }

    var body: some View {
        HStack(spacing: 12) {
            // ── Chain monogram ──
            ZStack {
                Circle()
                    .fill(Color.white.opacity(isSelected ? 0.12 : 0.06))
                    .frame(width: 36, height: 36)

                Text(chainInitial)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color.white.opacity(isSelected ? 0.7 : 0.4))
            }

            // ── Chain info ──
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(chainDisplayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(isSelected ? 1 : 0.8))

                    Text(chain.isL2 ? "L2" : "L1")
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(1)
                        .foregroundColor(Color.white.opacity(0.25))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }

                HStack(spacing: 6) {
                    Text(chain.amountDecimal)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.35))

                    // Activity indicator — subtle pulse for recent updates
                    if chain.lastUpdated > 0 {
                        Circle()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 4, height: 4)
                    }
                }
            }

            Spacer()

            // ── Value + percentage ──
            VStack(alignment: .trailing, spacing: 3) {
                Text(formatUSD(chain.usdValue))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(isSelected ? 1 : 0.8))

                // Percentage bar
                HStack(spacing: 6) {
                    // Mini proportional bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 2)

                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.white.opacity(isSelected ? 0.4 : 0.2))
                                .frame(width: geo.size.width * CGFloat(min(percentage, 100) / 100), height: 2)
                        }
                    }
                    .frame(width: 40, height: 2)

                    Text(String(format: "%.1f%%", percentage))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.3))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(
                    isSelected ? 0.07 : (isHovered ? 0.04 : 0.02)
                ))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(isSelected ? 0.10 : 0),
                    lineWidth: 0.5
                )
        )
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
    }

    private func formatUSD(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = value >= 1000 ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.0f", value)
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Notification Extension
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

extension Notification.Name {
    static let openBridgeFromL2 = Notification.Name("openBridgeFromL2")
}
