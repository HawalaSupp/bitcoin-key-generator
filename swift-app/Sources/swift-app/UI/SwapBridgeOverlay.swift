import SwiftUI

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Swap & Bridge Premium Overlay
// The crown jewel of HAWALA.
// Orbital token mechanics, wormhole bridge visualization,
// geometric route selection, hold-to-confirm execution.
// Matches Bitcoin detail card: monumental, monochrome, mechanical.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct SwapBridgeOverlay: View {
    @Binding var isPresented: Bool
    let keys: AllKeys?

    // ── Mode ──
    @State private var mode: SwapBridgeMode = .swap

    // ── Token selection ──
    @State private var fromAsset: SwapAsset = .bitcoin
    @State private var toAsset: SwapAsset = .ethereum
    @State private var showFromPicker: Bool = false
    @State private var showToPicker: Bool = false

    // ── Amount ──
    @State private var inputAmount: String = ""

    // ── Provider/Route ──
    @State private var selectedProvider: SwapProviderInfo? = nil
    @State private var showRoutes: Bool = false

    // ── Settings ──
    @State private var slippageTolerance: Double = 0.5
    @State private var showSlippage: Bool = false

    // ── Confirm ──
    @State private var holdProgress: CGFloat = 0
    @State private var isHolding: Bool = false
    @State private var showSuccess: Bool = false

    // ── Rate ──
    @StateObject private var priceService = CoinGeckoPriceService()

    // ── Entrance animation ──
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92

    // ── Orbital animation ──
    @State private var orbitalPhase: CGFloat = 0
    @State private var wormholePhase: CGFloat = 0

    // ── Hover ──
    @State private var closeHovered: Bool = false
    @State private var swapArrowHovered: Bool = false

    // ── Derived ──
    private var inputDouble: Double { Double(inputAmount) ?? 0 }
    private var hasAmount: Bool { inputDouble > 0 }
    private var exchangeRate: Double { priceService.exchangeRate ?? 1.0 }
    private var estimatedOutput: Double {
        guard hasAmount else { return 0 }
        let fee = selectedProvider?.feePercent ?? 0
        return inputDouble * exchangeRate * (1.0 - fee / 100.0)
    }

    private var providers: [SwapProviderInfo] {
        mode == .swap ? SwapProviderInfo.dexProviders : SwapProviderInfo.crossChainProviders
    }

    private var activeProvider: SwapProviderInfo {
        selectedProvider ?? providers.first!
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Body
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    var body: some View {
        ZStack {
            backdrop
            mainCard
            if showFromPicker { tokenPickerOverlay(binding: $fromAsset, excluding: toAsset, isPresented: $showFromPicker) }
            if showToPicker { tokenPickerOverlay(binding: $toAsset, excluding: fromAsset, isPresented: $showToPicker) }
            if showRoutes { routeSelectionOverlay }
            if showSuccess { successOverlay }
        }
        .background(
            EscapeKeyHandler(isPresented: $isPresented, onEscape: dismissOverlay)
        )
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                cardScale = 1
                contentOpacity = 1
            }
            priceService.startFetching(from: fromAsset.coinGeckoID, to: toAsset.coinGeckoID)
            startOrbitalAnimation()
        }
        .onChange(of: fromAsset) { _ in
            priceService.startFetching(from: fromAsset.coinGeckoID, to: toAsset.coinGeckoID)
        }
        .onChange(of: toAsset) { _ in
            priceService.startFetching(from: fromAsset.coinGeckoID, to: toAsset.coinGeckoID)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Backdrop
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var backdrop: some View {
        Color.black.opacity(0.75)
            .ignoresSafeArea()
            .onTapGesture { dismissOverlay() }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Main Card
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var mainCard: some View {
        VStack(spacing: 0) {
            headerSection
            modeToggle
            orbitalExchange
            routePreview
            if showSlippage { slippageBar }
            Spacer(minLength: 0)
            confirmSection
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
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Header
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var headerSection: some View {
        ZStack {
            Text(mode == .swap ? "Swap" : "Bridge")
                .font(.clashGroteskMedium(size: 20))
                .foregroundColor(.white)

            HStack {
                // Slippage toggle
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        showSlippage.toggle()
                    }
                }) {
                    slippageButton
                }
                .buttonStyle(.plain)

                Spacer()

                // Close
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
        .opacity(contentOpacity)
    }

    private var slippageButton: some View {
        HStack(spacing: 4) {
            Image(systemName: "gearshape")
                .font(.system(size: 10, weight: .semibold))
            Text("\(slippageTolerance, specifier: slippageTolerance < 1 ? "%.1f" : "%.0f")%")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
        }
        .foregroundColor(.white.opacity(showSlippage ? 0.65 : 0.45))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(showSlippage ? 0.12 : 0.07))
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Mode Toggle (Morphing)
    // A single element that shifts form between Swap and Bridge.
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var modeToggle: some View {
        HStack(spacing: 2) {
            modeTab(label: "SWAP", icon: "arrow.triangle.2.circlepath", isActive: mode == .swap) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { mode = .swap }
            }
            modeTab(label: "BRIDGE", icon: "point.3.connected.trianglepath.dotted", isActive: mode == .bridge) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { mode = .bridge }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
        .opacity(contentOpacity)
    }

    private func modeTab(label: String, icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 10, weight: isActive ? .bold : .medium))
                    .tracking(1.5)
            }
            .foregroundColor(.white.opacity(isActive ? 0.75 : 0.35))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(isActive ? 0.10 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(isActive ? 0.14 : 0), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Orbital Exchange
    // Two token bodies orbiting a central exchange point.
    // In bridge mode, a wormhole arc connects them.
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var orbitalExchange: some View {
        VStack(spacing: 0) {
            // ── FROM token ──
            tokenInputCard(
                side: .from,
                asset: fromAsset,
                amount: $inputAmount,
                label: mode == .bridge ? "FROM CHAIN" : "YOU PAY",
                onSelectToken: { showFromPicker = true }
            )

            // ── Central nexus: swap direction + orbital visualization ──
            centralNexus

            // ── TO token ──
            tokenOutputCard(
                side: .to,
                asset: toAsset,
                estimatedAmount: estimatedOutput,
                label: mode == .bridge ? "TO CHAIN" : "YOU RECEIVE",
                onSelectToken: { showToPicker = true }
            )
        }
        .padding(.horizontal, 24)
        .opacity(contentOpacity)
    }

    // ── Token Input Card ──
    private func tokenInputCard(side: TokenSide, asset: SwapAsset, amount: Binding<String>, label: String, onSelectToken: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(2)
                .foregroundColor(.white.opacity(0.40))

            HStack(spacing: 12) {
                // Amount input
                TextField("0", text: amount)
                    .textFieldStyle(.plain)
                    .font(.clashGroteskBold(size: 32))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Token selector button
                tokenButton(asset: asset, action: onSelectToken)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    }

    // ── Token Output Card ──
    private func tokenOutputCard(side: TokenSide, asset: SwapAsset, estimatedAmount: Double, label: String, onSelectToken: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(2)
                .foregroundColor(.white.opacity(0.40))

            HStack(spacing: 12) {
                // Estimated output
                Text(estimatedAmount > 0 ? formatOutput(estimatedAmount) : "0")
                    .font(.clashGroteskBold(size: 32))
                    .foregroundColor(.white.opacity(estimatedAmount > 0 ? 0.75 : 0.25))
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Token selector button
                tokenButton(asset: asset, action: onSelectToken)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    }

    private func tokenButton(asset: SwapAsset, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: asset.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                Text(asset.symbol)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.75))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.10))
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // ── Central Nexus ──
    // The swap arrow with orbital rings. In bridge mode, a wormhole arc connects two orbital systems.
    private var centralNexus: some View {
        ZStack {
            // Orbital rings
            if mode == .bridge {
                wormholeVisualization
            } else {
                orbitalRings
            }

            // Swap direction button
            Button(action: swapTokens) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
                        .frame(width: 44, height: 44)

                    Circle()
                        .fill(Color.white.opacity(swapArrowHovered ? 0.14 : 0.10))
                        .frame(width: 38, height: 38)

                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(swapArrowHovered ? 0.7 : 0.50))
                        .rotationEffect(.degrees(swapArrowHovered ? 180 : 0))
                }
            }
            .buttonStyle(.plain)
            .onHover { swapArrowHovered = $0 }
        }
        .frame(height: 52)
        .zIndex(1)
        .padding(.vertical, -8)
    }

    // ── Orbital rings (Swap mode) ──
    private var orbitalRings: some View {
        ZStack {
            // Outer ring
            Circle()
                .strokeBorder(Color.white.opacity(0.03), lineWidth: 0.5)
                .frame(width: 120, height: 120)
                .rotationEffect(.degrees(Double(orbitalPhase) * 360))

            // Inner ring
            Circle()
                .strokeBorder(Color.white.opacity(0.04), lineWidth: 0.5)
                .frame(width: 80, height: 80)
                .rotationEffect(.degrees(Double(orbitalPhase) * -360))

            // Orbiting particles
            ForEach(0..<3, id: \.self) { i in
                let angle = (Double(orbitalPhase) + Double(i) * 0.333) * .pi * 2
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 3, height: 3)
                    .offset(
                        x: cos(angle) * 55,
                        y: sin(angle) * 18
                    )
            }
        }
    }

    // ── Wormhole (Bridge mode) ──
    private var wormholeVisualization: some View {
        ZStack {
            // Left orbital system
            Circle()
                .strokeBorder(Color.white.opacity(0.04), lineWidth: 0.5)
                .frame(width: 60, height: 60)
                .offset(x: -80)

            // Right orbital system
            Circle()
                .strokeBorder(Color.white.opacity(0.04), lineWidth: 0.5)
                .frame(width: 60, height: 60)
                .offset(x: 80)

            // Wormhole connecting arc
            WormholeArc(phase: wormholePhase)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.05),
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1
                )
                .frame(width: 160, height: 40)

            // Traveling particle along wormhole
            if hasAmount {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 4, height: 4)
                    .offset(x: travelingParticleX, y: travelingParticleY)
            }
        }
    }

    private var travelingParticleX: CGFloat {
        let t = wormholePhase
        return -80 + 160 * t
    }

    private var travelingParticleY: CGFloat {
        let t = wormholePhase
        return sin(t * .pi) * -15
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Route Preview
    // Shows the selected route with rate and fee.
    // Clicking opens the full route selector.
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var routePreview: some View {
        VStack(spacing: 6) {
            // Rate display
            rateDisplay

            // Provider preview — tap for full list
            providerPreview
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .opacity(contentOpacity)
    }

    private var rateDisplay: some View {
        HStack(spacing: 8) {
            Text("RATE")
                .font(.system(size: 8, weight: .bold))
                .tracking(2)
                .foregroundColor(.white.opacity(0.40))

            Spacer()

            if priceService.isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
            } else {
                Text("1 \(fromAsset.symbol) = \(formatRate(exchangeRate)) \(toAsset.symbol)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.50))
            }

            // Price impact ripple
            if hasAmount {
                priceImpactIndicator
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var priceImpactIndicator: some View {
        let impact = computePriceImpact()
        let rippleCount = impact < 0.5 ? 1 : (impact < 2.0 ? 2 : 3)
        return HStack(spacing: 2) {
            ForEach(0..<rippleCount, id: \.self) { i in
                Circle()
                    .strokeBorder(Color.white.opacity(0.08 + Double(i) * 0.04), lineWidth: 0.5)
                    .frame(width: CGFloat(6 + i * 4), height: CGFloat(6 + i * 4))
            }
        }
    }

    private var providerPreview: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                showRoutes = true
            }
        }) {
            HStack(spacing: 10) {
                // Provider icon
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 30, height: 30)
                    Image(systemName: activeProvider.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.50))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(activeProvider.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.70))
                    Text(activeProvider.estimatedTime)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.35))
                }

                Spacer()

                // Fee
                Text(activeProvider.feePercent == 0 ? "No fee" : "\(activeProvider.feePercent, specifier: "%.2f")%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.30))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Slippage Bar
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var slippageBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SLIPPAGE TOLERANCE")
                .font(.system(size: 8, weight: .bold))
                .tracking(2)
                .foregroundColor(.white.opacity(0.40))

            HStack(spacing: 4) {
                ForEach([0.1, 0.5, 1.0, 3.0], id: \.self) { val in
                    SwapSlippageChip(
                        value: val,
                        isSelected: slippageTolerance == val,
                        action: { slippageTolerance = val }
                    )
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Confirm Section
    // Hold-to-confirm button with animated progress ring.
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var confirmSection: some View {
        VStack(spacing: 10) {
            // Summary line
            if hasAmount {
                confirmSummary
            }

            // Hold-to-confirm button
            holdToConfirmButton
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .opacity(contentOpacity)
    }

    private var confirmSummary: some View {
        HStack {
            Text("\(inputAmount) \(fromAsset.symbol)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.55))

            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white.opacity(0.30))

            Text("\(formatOutput(estimatedOutput)) \(toAsset.symbol)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.55))

            Spacer()

            Text("via \(activeProvider.shortName)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.30))
        }
    }

    private var holdToConfirmButton: some View {
        let isReady = hasAmount
        return ZStack {
            // Track
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(isReady ? 0.07 : 0.04))
                .frame(height: 52)

            // Progress fill
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .frame(width: geo.size.width * holdProgress, height: 52)
            }
            .frame(height: 52)
            .clipped()

            // Border
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(isReady ? 0.14 : 0.06), lineWidth: 0.5)
                .frame(height: 52)

            // Label
            HStack(spacing: 8) {
                if holdProgress > 0 && holdProgress < 1 {
                    // Progress ring
                    Circle()
                        .trim(from: 0, to: holdProgress)
                        .stroke(Color.white.opacity(0.45), lineWidth: 2)
                        .frame(width: 16, height: 16)
                        .rotationEffect(.degrees(-90))
                } else {
                    Image(systemName: mode == .swap ? "arrow.triangle.2.circlepath" : "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(isReady ? 0.50 : 0.25))
                }

                Text(holdProgress > 0 ? "HOLD TO CONFIRM" : (mode == .swap ? "HOLD TO SWAP" : "HOLD TO BRIDGE"))
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(isReady ? 0.65 : 0.30))
            }
        }
        .frame(height: 52)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard isReady else { return }
                    if !isHolding {
                        isHolding = true
                        startHoldTimer()
                    }
                }
                .onEnded { _ in
                    isHolding = false
                    if holdProgress < 1 {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            holdProgress = 0
                        }
                    }
                }
        )
        .opacity(isReady ? 1 : 0.6)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Route Selection Overlay
    // Branching geometric lines — optimal route glows brighter.
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var routeSelectionOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        showRoutes = false
                    }
                }

            routeSelectionCard
        }
        .transition(.opacity)
        .zIndex(3)
    }

    private var routeSelectionCard: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(mode == .swap ? "DEX ROUTES" : "BRIDGE ROUTES")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        showRoutes = false
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.3))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            // Route topology visualization
            routeTopology
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            // Provider list
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 4) {
                    ForEach(providers, id: \.id) { provider in
                        SwapProviderRow(
                            provider: provider,
                            fromAmount: inputDouble,
                            fromSymbol: fromAsset.symbol,
                            toSymbol: toAsset.symbol,
                            exchangeRate: exchangeRate,
                            isSelected: selectedProvider?.id == provider.id || (selectedProvider == nil && provider.id == providers.first?.id),
                            isBest: provider.isBestRate,
                            action: {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                    selectedProvider = provider
                                    showRoutes = false
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .frame(width: 400, height: 500)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.12, opacity: 0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.6), radius: 30, x: 0, y: 15)
    }

    // ── Route Topology — branching geometric visualization ──
    private var routeTopology: some View {
        ZStack {
            // Source node
            HStack {
                routeNode(label: fromAsset.symbol)
                Spacer()
                routeNode(label: toAsset.symbol)
            }

            // Branching lines
            GeometryReader { geo in
                let w = geo.size.width
                let centerY: CGFloat = 14
                let routeCount = min(providers.count, 5)

                ForEach(0..<routeCount, id: \.self) { i in
                    let yOffset = CGFloat(i - routeCount / 2) * 6
                    let isBest = providers[i].isBestRate
                    let isSelected = selectedProvider?.id == providers[i].id || (selectedProvider == nil && i == 0)

                    Path { path in
                        path.move(to: CGPoint(x: 40, y: centerY))
                        path.addCurve(
                            to: CGPoint(x: w - 40, y: centerY),
                            control1: CGPoint(x: w * 0.35, y: centerY + yOffset),
                            control2: CGPoint(x: w * 0.65, y: centerY + yOffset)
                        )
                    }
                    .stroke(
                        Color.white.opacity(isSelected ? 0.15 : (isBest ? 0.08 : 0.03)),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
                }
            }
            .frame(height: 28)
        }
        .frame(height: 28)
    }

    private func routeNode(label: String) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 28, height: 28)
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.50))
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Token Picker Overlay
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func tokenPickerOverlay(binding: Binding<SwapAsset>, excluding: SwapAsset, isPresented: Binding<Bool>) -> some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        isPresented.wrappedValue = false
                    }
                }

            tokenPickerCard(binding: binding, excluding: excluding, isPresented: isPresented)
        }
        .transition(.opacity)
        .zIndex(3)
    }

    private func tokenPickerCard(binding: Binding<SwapAsset>, excluding: SwapAsset, isPresented: Binding<Bool>) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("SELECT TOKEN")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        isPresented.wrappedValue = false
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.3))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(SwapAsset.allCases.filter { $0 != excluding }, id: \.id) { asset in
                        TokenPickerRow(
                            asset: asset,
                            isSelected: binding.wrappedValue == asset,
                            action: {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                    binding.wrappedValue = asset
                                    isPresented.wrappedValue = false
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .frame(width: 320, height: 420)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.12, opacity: 0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.6), radius: 30, x: 0, y: 15)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Success Overlay
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Concentric success rings
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .strokeBorder(Color.white.opacity(0.08 + Double(i) * 0.04), lineWidth: 0.5)
                            .frame(width: CGFloat(60 + i * 20), height: CGFloat(60 + i * 20))
                    }
                    Image(systemName: "checkmark")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white.opacity(0.65))
                }

                Text(mode == .swap ? "Swap Initiated" : "Bridge Transfer Started")
                    .font(.clashGroteskMedium(size: 20))
                    .foregroundColor(.white.opacity(0.8))

                Text("\(inputAmount) \(fromAsset.symbol) → \(formatOutput(estimatedOutput)) \(toAsset.symbol)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.50))

                Text("via \(activeProvider.name) · \(activeProvider.estimatedTime)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.35))

                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        showSuccess = false
                        inputAmount = ""
                        holdProgress = 0
                    }
                }) {
                    Text("DONE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.65))
                        .padding(.horizontal, 28)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .transition(.opacity)
        .zIndex(4)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Actions
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func swapTokens() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            let temp = fromAsset
            fromAsset = toAsset
            toAsset = temp
        }
    }

    private func startHoldTimer() {
        // Animate holdProgress from 0 to 1 over 1.5 seconds
        withAnimation(.linear(duration: 1.5)) {
            holdProgress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if isHolding && holdProgress >= 0.99 {
                executeTransaction()
            } else if !isHolding {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    holdProgress = 0
                }
            }
        }
    }

    private func executeTransaction() {
        // Open provider widget
        if let url = URL(string: activeProvider.widgetURL) {
            NSWorkspace.shared.open(url)
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showSuccess = true
        }
    }

    private func startOrbitalAnimation() {
        withAnimation(
            .linear(duration: 8)
            .repeatForever(autoreverses: false)
        ) {
            orbitalPhase = 1
        }
        withAnimation(
            .linear(duration: 3)
            .repeatForever(autoreverses: false)
        ) {
            wormholePhase = 1
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

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Helpers
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func formatOutput(_ value: Double) -> String {
        if value >= 1000 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            formatter.groupingSeparator = " "
            return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
        } else if value >= 1 {
            return String(format: "%.4f", value)
        } else if value >= 0.0001 {
            return String(format: "%.6f", value)
        } else {
            return String(format: "%.8f", value)
        }
    }

    private func formatRate(_ rate: Double) -> String {
        if rate >= 1000 {
            return String(format: "%.0f", rate)
        } else if rate >= 1 {
            return String(format: "%.4f", rate)
        } else {
            return String(format: "%.8f", rate)
        }
    }

    private func computePriceImpact() -> Double {
        guard inputDouble > 0 else { return 0 }
        // Simulated impact: larger amounts = higher impact
        return min(5.0, inputDouble * 0.001)
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Supporting Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private enum SwapBridgeMode {
    case swap, bridge
}

private enum TokenSide {
    case from, to
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Wormhole Arc Shape
// Connecting arc between two chain orbital systems.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private struct WormholeArc: Shape {
    var phase: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        let step: CGFloat = 2

        for x in stride(from: 0, through: rect.width, by: step) {
            let normalX = x / rect.width
            let compression = sin(normalX * .pi)
            let wave = sin((normalX * 4 + phase * 2) * .pi) * compression * 8
            let y = midY + wave

            if x == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        return path
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Token Picker Row
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private struct TokenPickerRow: View {
    let asset: SwapAsset
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Token icon
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(isSelected ? 0.12 : 0.07))
                        .frame(width: 36, height: 36)
                    Image(systemName: asset.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(isSelected ? 0.60 : 0.40))
                }

                // Name & symbol
                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(isSelected ? 0.85 : 0.65))
                    Text(asset.symbol)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.40))
                }

                Spacer()

                // Selection indicator
                if isSelected {
                    Circle()
                        .fill(Color.white.opacity(0.45))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(bgOpacity))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var bgOpacity: Double {
        if isSelected { return 0.10 }
        if isHovered { return 0.05 }
        return 0.03
    }
}
