import SwiftUI

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Gas Account Overlay
// Multi-chain unified gas balance.
// Fuel gauge depletion, chain flame bars, mechanical ticker deposit,
// circular auto-refill charging indicator.
// Monumental. Monochrome. Mechanical.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct GasAccountOverlay: View {
    @Binding var isPresented: Bool

    // ── Balance ──
    @State private var totalBalanceUSD: Double = 0
    @State private var displayedBalance: Double = 0
    @State private var chainBalances: [ChainGasEntry] = []

    // ── Deposit ──
    @State private var showDeposit: Bool = false
    @State private var depositAmount: String = ""
    @State private var depositChain: String = "Ethereum"

    // ── Settings ──
    @State private var autoRefill: Bool = false
    @State private var refillThreshold: Double = 5.0

    // ── Animation ──
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92
    @State private var gaugeLevel: CGFloat = 0
    @State private var refillPulse: CGFloat = 0
    @State private var flamePhase: CGFloat = 0

    // ── Hover ──
    @State private var closeHovered: Bool = false
    @State private var depositHovered: Bool = false

    private let supportedChains = ["Ethereum", "Polygon", "Arbitrum", "Optimism", "Base", "Avalanche", "BNB"]

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Body
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    var body: some View {
        ZStack {
            backdrop
            mainCard
        }
        .background(
            EscapeKeyHandler(isPresented: $isPresented, onEscape: dismissOverlay)
        )
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                cardScale = 1
                contentOpacity = 1
            }
            loadGasData()
            startAnimations()
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Backdrop
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var backdrop: some View {
        Color.black.opacity(0.75)
            .ignoresSafeArea()
            .onTapGesture { dismissOverlay() }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Main Card
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var mainCard: some View {
        VStack(spacing: 0) {
            headerSection
            balanceSection
            if showDeposit { depositSection } else { chainUsageSection }
            Spacer(minLength: 0)
            bottomControls
        }
        .frame(width: 440, height: 660)
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
        .opacity(contentOpacity)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Header
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var headerSection: some View {
        ZStack {
            Text("Gas Account")
                .font(.clashGroteskMedium(size: 20))
                .foregroundColor(.white)

            HStack {
                Spacer()
                Button(action: dismissOverlay) {
                    Circle()
                        .fill(Color.white.opacity(closeHovered ? 0.12 : 0.08))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.5))
                        )
                }
                .buttonStyle(.plain)
                .onHover { closeHovered = $0 }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 4)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Balance Section
    // Fuel gauge + monumental balance + auto-refill ring.
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var balanceSection: some View {
        VStack(spacing: 6) {
            ZStack {
                // Auto-refill charging ring
                if autoRefill {
                    refillRing
                }

                // Fuel gauge arc
                fuelGauge

                // Balance in centre
                VStack(spacing: 2) {
                    Text("$")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.2))

                    // Mechanical ticker — counts up/down
                    Text(tickerString(displayedBalance))
                        .font(.clashGroteskBold(size: 42))
                        .foregroundColor(.white.opacity(0.9))

                    Text("AVAILABLE GAS CREDIT")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.15))
                }
            }
            .frame(height: 170)

            // Status line
            gasStatusLine
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    // ── Fuel gauge: semi-circular arc that depletes ──
    private var fuelGauge: some View {
        ZStack {
            gaugeTrack
            gaugeFill
            gaugeTicks
            gaugeNeedle
        }
    }

    private var gaugeTrack: some View {
        Circle()
            .trim(from: 0.15, to: 0.85)
            .rotation(.degrees(90))
            .stroke(Color.white.opacity(0.03), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .frame(width: 150, height: 150)
    }

    private var gaugeFill: some View {
        Circle()
            .trim(from: 0.15, to: 0.15 + gaugeLevel * 0.7)
            .rotation(.degrees(90))
            .stroke(
                Color.white.opacity(gaugeOpacity),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
            .frame(width: 150, height: 150)
    }

    private var gaugeTicks: some View {
        ForEach(0..<7, id: \.self) { i in
            let angle = (Double(i) / 6.0) * 0.7 + 0.15
            let radians = (angle * 2 * .pi) + (.pi / 2)
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1, height: 5)
                .offset(y: -80)
                .rotationEffect(.radians(radians))
        }
    }

    private var gaugeNeedle: some View {
        let needleAngle = (0.15 + Double(gaugeLevel) * 0.7) * 2 * .pi + (.pi / 2)
        return Circle()
            .fill(Color.white.opacity(0.2))
            .frame(width: 5, height: 5)
            .offset(y: -75)
            .rotationEffect(.radians(needleAngle))
    }

    private var gaugeOpacity: Double {
        if gaugeLevel > 0.5 { return 0.12 }
        if gaugeLevel > 0.2 { return 0.08 }
        return 0.05
    }

    // ── Auto-refill charging ring ──
    private var refillRing: some View {
        ZStack {
            // Outer pulsing ring
            Circle()
                .strokeBorder(
                    Color.white.opacity(0.03 + Double(refillPulse) * 0.02),
                    lineWidth: 1
                )
                .frame(width: 168, height: 168)

            // Charging segments
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .trim(from: CGFloat(i) * 0.25 + 0.02, to: CGFloat(i) * 0.25 + 0.18)
                    .stroke(
                        Color.white.opacity(0.04 + Double(refillPulse) * 0.02),
                        lineWidth: 1.5
                    )
                    .frame(width: 168, height: 168)
            }

            // "AUTO" label
            Text("AUTO")
                .font(.system(size: 6, weight: .bold))
                .tracking(2)
                .foregroundColor(.white.opacity(0.08))
                .offset(y: 92)
        }
    }

    private var gasStatusLine: some View {
        HStack(spacing: 8) {
            // Status dot
            Circle()
                .fill(Color.white.opacity(totalBalanceUSD > refillThreshold ? 0.2 : 0.06))
                .frame(width: 5, height: 5)

            Text(statusText)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.2))

            Spacer()

            Text("\(chainBalances.count) CHAINS")
                .font(.system(size: 8, weight: .bold))
                .tracking(1)
                .foregroundColor(.white.opacity(0.12))
        }
        .padding(.horizontal, 4)
    }

    private var statusText: String {
        if totalBalanceUSD <= 0 { return "No gas credit — deposit to start" }
        if totalBalanceUSD < refillThreshold { return "Low balance" }
        return "Ready across all chains"
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Chain Usage (Flame Bars)
    // Taller flames = more gas consumed on that chain.
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var chainUsageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("USAGE BY CHAIN")
                .font(.system(size: 8, weight: .bold))
                .tracking(2)
                .foregroundColor(.white.opacity(0.15))

            if chainBalances.isEmpty {
                emptyUsage
            } else {
                flameChart
                chainList
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private var emptyUsage: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar")
                .font(.system(size: 20, weight: .thin))
                .foregroundColor(.white.opacity(0.08))
            Text("No usage data yet")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.12))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // ── Flame chart: vertical bars with flickering tops ──
    private var flameChart: some View {
        let maxVal = chainBalances.map(\.usdValue).max() ?? 1
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(chainBalances, id: \.id) { entry in
                let normalised = CGFloat(entry.usdValue / max(maxVal, 0.01))
                flameBar(entry: entry, normalised: normalised)
            }
        }
        .frame(height: 80)
        .padding(.horizontal, 4)
    }

    private func flameBar(entry: ChainGasEntry, normalised: CGFloat) -> some View {
        let barHeight = max(8, normalised * 60)
        let flickerExtra = CGFloat(sin(Double(flamePhase) * .pi * 2 + Double(entry.id.hashValue))) * 4
        return VStack(spacing: 3) {
            // Flame tip — flickering
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .frame(width: 4, height: max(2, abs(flickerExtra)))

            // Bar body
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.08), Color.white.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 24, height: barHeight + abs(flickerExtra))

            // Chain label
            Text(entry.symbol)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.15))
        }
        .frame(maxWidth: .infinity)
    }

    // ── Chain list with balances ──
    private var chainList: some View {
        VStack(spacing: 2) {
            ForEach(chainBalances, id: \.id) { entry in
                HStack(spacing: 10) {
                    // Chain icon
                    Circle()
                        .fill(Color.white.opacity(0.04))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Text(entry.symbol.prefix(1))
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.2))
                        )

                    Text(entry.chain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))

                    Spacer()

                    VStack(alignment: .trailing, spacing: 1) {
                        Text("$\(entry.usdValue, specifier: "%.2f")")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                        Text("\(entry.amount) \(entry.symbol)")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.12))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.015))
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Deposit Section
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var depositSection: some View {
        VStack(spacing: 14) {
            Text("DEPOSIT GAS CREDIT")
                .font(.system(size: 8, weight: .bold))
                .tracking(2)
                .foregroundColor(.white.opacity(0.15))

            // Amount input
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text("$")
                        .font(.clashGroteskBold(size: 28))
                        .foregroundColor(.white.opacity(0.2))

                    TextField("0", text: $depositAmount)
                        .textFieldStyle(.plain)
                        .font(.clashGroteskBold(size: 28))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Quick amounts
                HStack(spacing: 6) {
                    ForEach([5, 10, 25, 50], id: \.self) { amt in
                        quickAmountChip(amt)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.04), lineWidth: 0.5)
            )

            // Chain selector
            VStack(alignment: .leading, spacing: 6) {
                Text("DEPOSIT ON")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.12))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(supportedChains, id: \.self) { chain in
                            depositChainChip(chain)
                        }
                    }
                }
            }

            // Confirm deposit
            Button(action: executeDeposit) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 12, weight: .semibold))
                    Text("CONFIRM DEPOSIT")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                }
                .foregroundColor(.white.opacity(hasDepositAmount ? 0.5 : 0.15))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(hasDepositAmount ? 0.05 : 0.02))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(hasDepositAmount ? 0.08 : 0.03), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .disabled(!hasDepositAmount)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    private func quickAmountChip(_ amount: Int) -> some View {
        let isSelected = depositAmount == "\(amount)"
        return Button(action: { depositAmount = "\(amount)" }) {
            Text("$\(amount)")
                .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .monospaced))
                .foregroundColor(.white.opacity(isSelected ? 0.5 : 0.2))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(isSelected ? 0.06 : 0.02))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(isSelected ? 0.08 : 0.03), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func depositChainChip(_ chain: String) -> some View {
        let isSelected = depositChain == chain
        return Button(action: { depositChain = chain }) {
            Text(chain)
                .font(.system(size: 9, weight: isSelected ? .bold : .medium))
                .foregroundColor(.white.opacity(isSelected ? 0.5 : 0.18))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(isSelected ? 0.06 : 0.015))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(isSelected ? 0.08 : 0.02), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    private var hasDepositAmount: Bool {
        guard let val = Double(depositAmount) else { return false }
        return val > 0
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Bottom Controls
    // Deposit toggle + auto-refill + supported chains.
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var bottomControls: some View {
        VStack(spacing: 8) {
            // Auto-refill toggle
            autoRefillRow

            // Deposit / Back toggle
            depositToggleButton

            // Supported chains ticker
            supportedChainsTicker
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    private var autoRefillRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.clockwise.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.2))

            VStack(alignment: .leading, spacing: 1) {
                Text("Auto-Refill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
                Text(autoRefill ? "Refills when below $\(Int(refillThreshold))" : "Off")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.15))
            }

            Spacer()

            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    autoRefill.toggle()
                }
            }) {
                refillToggle
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.03), lineWidth: 0.5)
        )
    }

    private var refillToggle: some View {
        ZStack {
            Capsule()
                .fill(Color.white.opacity(autoRefill ? 0.08 : 0.03))
                .frame(width: 40, height: 22)
            Capsule()
                .strokeBorder(Color.white.opacity(autoRefill ? 0.1 : 0.05), lineWidth: 0.5)
                .frame(width: 40, height: 22)
            Circle()
                .fill(Color.white.opacity(autoRefill ? 0.35 : 0.1))
                .frame(width: 16, height: 16)
                .offset(x: autoRefill ? 9 : -9)
        }
    }

    private var depositToggleButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                showDeposit.toggle()
                if !showDeposit { depositAmount = "" }
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: showDeposit ? "chevron.left" : "arrow.down.circle")
                    .font(.system(size: 12, weight: .semibold))
                Text(showDeposit ? "BACK TO OVERVIEW" : "DEPOSIT")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
            }
            .foregroundColor(.white.opacity(depositHovered ? 0.5 : 0.35))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(depositHovered ? 0.05 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { depositHovered = $0 }
    }

    private var supportedChainsTicker: some View {
        HStack(spacing: 6) {
            ForEach(supportedChains, id: \.self) { chain in
                Text(chain.prefix(3).uppercased())
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.08))

                if chain != supportedChains.last {
                    Circle()
                        .fill(Color.white.opacity(0.04))
                        .frame(width: 2, height: 2)
                }
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Actions
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func loadGasData() {
        // Demo data — in production calls HawalaBridge
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            chainBalances = [
                ChainGasEntry(id: "eth", chain: "Ethereum", symbol: "ETH", amount: "0.005", usdValue: 12.50),
                ChainGasEntry(id: "poly", chain: "Polygon", symbol: "MATIC", amount: "10.0", usdValue: 8.50),
                ChainGasEntry(id: "base", chain: "Base", symbol: "ETH", amount: "0.002", usdValue: 5.00),
                ChainGasEntry(id: "arb", chain: "Arbitrum", symbol: "ETH", amount: "0.001", usdValue: 2.50),
                ChainGasEntry(id: "opt", chain: "Optimism", symbol: "ETH", amount: "0.0008", usdValue: 1.80),
            ]
            totalBalanceUSD = chainBalances.reduce(0) { $0 + $1.usdValue }

            // Animate gauge and ticker
            withAnimation(.easeOut(duration: 1.2)) {
                gaugeLevel = CGFloat(min(1.0, totalBalanceUSD / 50.0))
            }
            animateTicker(to: totalBalanceUSD)
        }
    }

    private func executeDeposit() {
        guard let amount = Double(depositAmount), amount > 0 else { return }
        let oldBalance = totalBalanceUSD
        totalBalanceUSD += amount
        let newBalance = totalBalanceUSD

        // Add to chain balance or create
        if let idx = chainBalances.firstIndex(where: { $0.chain == depositChain }) {
            chainBalances[idx] = ChainGasEntry(
                id: chainBalances[idx].id,
                chain: chainBalances[idx].chain,
                symbol: chainBalances[idx].symbol,
                amount: chainBalances[idx].amount,
                usdValue: chainBalances[idx].usdValue + amount
            )
        } else {
            chainBalances.append(ChainGasEntry(
                id: depositChain.lowercased(),
                chain: depositChain,
                symbol: symbolFor(depositChain),
                amount: String(format: "%.4f", amount / 3000),
                usdValue: amount
            ))
        }

        // Animate gauge
        withAnimation(.easeOut(duration: 0.8)) {
            gaugeLevel = CGFloat(min(1.0, newBalance / 50.0))
        }

        // Ticker animation
        animateTicker(to: newBalance)

        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            showDeposit = false
            depositAmount = ""
        }
    }

    private func animateTicker(to target: Double) {
        let start = displayedBalance
        let steps = 20
        let duration = 0.8
        for i in 0...steps {
            let frac = Double(i) / Double(steps)
            let val = start + (target - start) * frac
            DispatchQueue.main.asyncAfter(deadline: .now() + duration * frac) {
                displayedBalance = val
            }
        }
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

    private func startAnimations() {
        withAnimation(
            .easeInOut(duration: 2)
            .repeatForever(autoreverses: true)
        ) {
            refillPulse = 1
        }
        withAnimation(
            .linear(duration: 3)
            .repeatForever(autoreverses: false)
        ) {
            flamePhase = 1
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Helpers
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func tickerString(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func symbolFor(_ chain: String) -> String {
        switch chain {
        case "Ethereum", "Arbitrum", "Optimism", "Base": return "ETH"
        case "Polygon": return "MATIC"
        case "BNB": return "BNB"
        case "Avalanche": return "AVAX"
        default: return "ETH"
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Data Model
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private struct ChainGasEntry: Identifiable {
    let id: String
    let chain: String
    let symbol: String
    let amount: String
    let usdValue: Double
}
