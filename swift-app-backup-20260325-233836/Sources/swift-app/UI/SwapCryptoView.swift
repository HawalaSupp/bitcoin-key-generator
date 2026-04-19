import SwiftUI

// MARK: - CoinGecko Live Price Service

class CoinGeckoPriceService: ObservableObject {
    @Published var exchangeRate: Double?
    @Published var isLoading = false
    @Published var lastUpdated: Date?
    
    private var refreshTimer: Timer?
    private var currentTask: URLSessionDataTask?
    private var fromId: String = ""
    private var toId: String = ""
    
    func startFetching(from: String, to: String) {
        fromId = from
        toId = to
        exchangeRate = nil
        fetchRate()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.fetchRate()
        }
    }
    
    func stopFetching() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        currentTask?.cancel()
        currentTask = nil
    }
    
    private func fetchRate() {
        guard !fromId.isEmpty, !toId.isEmpty else { return }
        
        let from = fromId
        let to = toId
        isLoading = exchangeRate == nil
        
        let urlStr = "https://api.coingecko.com/api/v3/simple/price?ids=\(from),\(to)&vs_currencies=usd"
        guard let url = URL(string: urlStr) else { return }
        
        currentTask?.cancel()
        currentTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                defer { self.isLoading = false }
                guard let data = data, error == nil else { return }
                
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Double]],
                   let fromPrice = json[from]?["usd"],
                   let toPrice = json[to]?["usd"],
                   toPrice > 0 {
                    self.exchangeRate = fromPrice / toPrice
                    self.lastUpdated = Date()
                }
            }
        }
        currentTask?.resume()
    }
    
    deinit {
        refreshTimer?.invalidate()
        currentTask?.cancel()
    }
}

// MARK: - Width Tracking

private struct SwapWidthKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 600
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Swap Crypto View (HAWALA Design Language)
// Monochrome · Monumental · No traditional form patterns
// Transparent over global silk background → floating content → hold-to-confirm

struct SwapCryptoView: View {
    let keys: AllKeys?
    
    @StateObject private var swapService = SwapService.shared
    @StateObject private var dexService = DEXAggregatorService.shared
    @StateObject private var priceService = CoinGeckoPriceService()
    
    // Funnel state
    @State private var currentStep: Int = 0
    @State private var swapMode: SwapMode = .crossChain
    @State private var fromAsset: SwapAsset = .bitcoin
    @State private var toAsset: SwapAsset = .ethereum
    @State private var fromAmount: String = ""
    @State private var selectedProvider: SwapProviderInfo? = nil
    @State private var slippageTolerance: Double = 0.5
    
    // Animation & interaction
    @State private var direction: SlideDirection = .forward
    @State private var showSuccess = false
    @State private var pulseRing = false
    @State private var isHoveringBack = false
    @State private var isHoveringNext = false
    
    // Responsive layout
    @State private var containerWidth: CGFloat = 600
    
    private var rs: CGFloat {
        min(1.0, max(0.55, containerWidth / 700))
    }
    
    enum SwapMode: String, CaseIterable {
        case crossChain = "Cross-Chain"
        case dex = "DEX"
    }
    
    enum SlideDirection { case forward, backward }
    
    private let totalSteps = 4
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // ── No local background — global silk shows through ──
            
            // ── Floating content ──
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: max(16, 36 * rs))
                    
                    // Minimal step indicator — hairlines
                    stepIndicator
                        .padding(.horizontal, max(16, 40 * rs))
                    
                    Spacer().frame(height: max(20, 48 * rs))
                    
                    // Step content (animated, no container)
                    ZStack {
                        Group {
                            switch currentStep {
                            case 0: step0_Assets
                            case 1: step1_Amount
                            case 2: step2_Provider
                            case 3: step3_Review
                            default: EmptyView()
                            }
                        }
                        .transition(slideTransition)
                    }
                    .animation(.spring(response: 0.45, dampingFraction: 0.85), value: currentStep)
                    .padding(.horizontal, max(16, 40 * rs))
                    
                    Spacer().frame(height: max(16, 40 * rs))
                    
                    // Navigation
                    navigationControls
                        .padding(.horizontal, max(16, 40 * rs))
                    
                    Spacer().frame(height: max(24, 60 * rs))
                }
                .frame(maxWidth: max(300, min(700, containerWidth * 0.88)))
                .frame(maxWidth: .infinity)
            }
            
            // Success overlay
            if showSuccess {
                successOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .overlay(
            GeometryReader { geo in
                Color.clear.preference(key: SwapWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(SwapWidthKey.self) { containerWidth = $0 }
        .onAppear {
            priceService.startFetching(from: fromAsset.coinGeckoID, to: toAsset.coinGeckoID)
        }
        .onDisappear {
            priceService.stopFetching()
        }
        .onChange(of: fromAsset) { newValue in
            priceService.startFetching(from: newValue.coinGeckoID, to: toAsset.coinGeckoID)
        }
        .onChange(of: toAsset) { newValue in
            priceService.startFetching(from: fromAsset.coinGeckoID, to: newValue.coinGeckoID)
        }
    }
    
    // MARK: - Step Indicator
    
    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { step in
                Rectangle()
                    .fill(step <= currentStep
                          ? Color.white.opacity(0.45)
                          : Color.white.opacity(0.06))
                    .frame(height: 1.5)
                    .animation(.easeOut(duration: 0.3), value: currentStep)
            }
        }
    }
    
    private var slideTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: direction == .forward ? .trailing : .leading)
                .combined(with: .opacity),
            removal: .move(edge: direction == .forward ? .leading : .trailing)
                .combined(with: .opacity)
        )
    }
    
    // MARK: - Step 0: Asset Selection
    
    private var step0_Assets: some View {
        VStack(spacing: 0) {
            // Monumental pair display
            HStack(spacing: max(8, 16 * rs)) {
                Text(fromAsset.symbol)
                    .font(.clashGroteskBold(size: max(28, 56 * rs)))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.18))
                
                Text(toAsset.symbol)
                    .font(.clashGroteskBold(size: max(28, 56 * rs)))
                    .foregroundColor(.white.opacity(0.40))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 12)
            
            // Mode — minimal text toggle
            modeToggle
                .padding(.bottom, max(16, 40 * rs))
            
            // FROM token strip
            VStack(alignment: .leading, spacing: 10) {
                Text("FROM")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(3)
                    .foregroundColor(.white.opacity(0.22))
                
                tokenStrip(selected: fromAsset, exclude: toAsset) { asset in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        fromAsset = asset
                    }
                }
            }
            .padding(.bottom, max(12, 24 * rs))
            
            // Swap direction
            swapDirectionButton
                .padding(.bottom, max(12, 24 * rs))
            
            // TO token strip
            VStack(alignment: .leading, spacing: 10) {
                Text("TO")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(3)
                    .foregroundColor(.white.opacity(0.22))
                
                tokenStrip(selected: toAsset, exclude: fromAsset) { asset in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        toAsset = asset
                    }
                }
            }
        }
    }
    
    private var modeToggle: some View {
        HStack(spacing: 20) {
            ForEach(SwapMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        swapMode = mode
                        selectedProvider = nil
                    }
                } label: {
                    Text(mode.rawValue.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundColor(swapMode == mode
                                         ? .white.opacity(0.55)
                                         : .white.opacity(0.12))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func tokenStrip(
        selected: SwapAsset,
        exclude: SwapAsset,
        onSelect: @escaping (SwapAsset) -> Void
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SwapAsset.allCases) { asset in
                    if asset != exclude {
                        Button {
                            onSelect(asset)
                        } label: {
                            Text(asset.symbol)
                                .font(.system(size: 12, weight: asset == selected ? .bold : .medium, design: .monospaced))
                                .foregroundColor(asset == selected ? .white : .white.opacity(0.25))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(
                                    Capsule()
                                        .fill(asset == selected
                                              ? Color.white.opacity(0.10)
                                              : Color.white.opacity(0.02))
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(
                                            asset == selected
                                                ? Color.white.opacity(0.18)
                                                : Color.white.opacity(0.04),
                                            lineWidth: 1
                                        )
                                )
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private var swapDirectionButton: some View {
        HStack {
            Spacer()
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
                    let t = fromAsset
                    fromAsset = toAsset
                    toAsset = t
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.04))
                        .frame(width: 40, height: 40)
                    Circle()
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        .frame(width: 40, height: 40)
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.35))
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }
    
    // MARK: - Step 1: Amount
    
    private var step1_Amount: some View {
        VStack(spacing: 0) {
            // Pair context
            HStack(spacing: 8) {
                Text(fromAsset.symbol)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.10))
                Text(toAsset.symbol)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
            }
            .padding(.bottom, max(16, 40 * rs))
            
            // Monumental amount
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                TextField("0", text: $fromAmount)
                    .font(.clashGroteskBold(size: max(36, 72 * rs)))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.plain)
                    .minimumScaleFactor(0.5)
                
                Text(fromAsset.symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white.opacity(0.18))
                    .padding(.leading, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)
            
            // Live conversion estimate (FIX 3)
            if let amount = Double(fromAmount), amount > 0 {
                if priceService.isLoading && priceService.exchangeRate == nil {
                    // Loading state — first fetch
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .colorScheme(.dark)
                        Text("Fetching rate…")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.22))
                    }
                    .padding(.bottom, max(16, 32 * rs))
                } else if let rate = priceService.exchangeRate {
                    let converted = amount * rate
                    VStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Text("≈")
                                .foregroundColor(.white.opacity(0.12))
                            Text(converted >= 1
                                 ? String(format: "%.6f", converted)
                                 : String(format: "%.8f", converted))
                                .foregroundColor(.white.opacity(0.30))
                            Text(toAsset.symbol)
                                .foregroundColor(.white.opacity(0.12))
                        }
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        
                        // Live rate info
                        VStack(spacing: 2) {
                            let rateStr = rate >= 1
                                ? String(format: "%.2f", rate)
                                : String(format: "%.6f", rate)
                            Text("1 \(fromAsset.symbol) = \(rateStr) \(toAsset.symbol)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.18))
                            
                            if let lastUpdated = priceService.lastUpdated {
                                Text("Updated \(lastUpdated.formatted(date: .omitted, time: .standard))")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.white.opacity(0.10))
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .padding(.bottom, max(16, 32 * rs))
                } else {
                    // Fallback — no rate yet, show input amount
                    HStack(spacing: 4) {
                        Text("≈")
                            .foregroundColor(.white.opacity(0.12))
                        Text("\(amount, specifier: "%.6f")")
                            .foregroundColor(.white.opacity(0.30))
                        Text(toAsset.symbol)
                            .foregroundColor(.white.opacity(0.12))
                    }
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .padding(.bottom, max(16, 32 * rs))
                }
            } else {
                Spacer().frame(height: max(16, 32 * rs))
            }
            
            // Slippage (DEX only)
            if swapMode == .dex {
                slippageControl
            }
        }
    }
    
    private var slippageControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SLIPPAGE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.22))
                Spacer()
                Text("\(slippageTolerance, specifier: "%.1f")%")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
            }
            
            HStack(spacing: 8) {
                ForEach([0.1, 0.5, 1.0, 3.0], id: \.self) { value in
                    SwapSlippageChip(value: value, isSelected: slippageTolerance == value) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            slippageTolerance = value
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Step 2: Provider
    
    private var step2_Provider: some View {
        VStack(spacing: 0) {
            // Monumental label
            Text("ROUTE")
                .font(.clashGroteskBold(size: max(24, 42 * rs)))
                .foregroundColor(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.bottom, 8)
            
            // Context
            HStack(spacing: 6) {
                Text(fromAmount.isEmpty ? "—" : fromAmount)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                Text(fromAsset.symbol)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.18))
                Image(systemName: "arrow.right")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.10))
                Text(toAsset.symbol)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.18))
            }
            .padding(.bottom, max(14, 28 * rs))
            
            // Provider list
            let providers = swapMode == .crossChain
                ? SwapProviderInfo.crossChainProviders
                : SwapProviderInfo.dexProviders
            let best = providers.min(by: { $0.feePercent < $1.feePercent })
            
            VStack(spacing: 4) {
                ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                    SwapProviderRow(
                        provider: provider,
                        fromAmount: Double(fromAmount) ?? 0,
                        fromSymbol: fromAsset.symbol,
                        toSymbol: toAsset.symbol,
                        exchangeRate: priceService.exchangeRate,
                        isSelected: selectedProvider?.id == provider.id,
                        isBest: provider.id == best?.id
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedProvider = provider
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .animation(
                        .spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.025),
                        value: currentStep
                    )
                }
            }
        }
    }
    
    // MARK: - Step 3: Review
    
    private var step3_Review: some View {
        VStack(spacing: 0) {
            // Monumental send amount
            VStack(spacing: 4) {
                Text("SEND")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(3)
                    .foregroundColor(.white.opacity(0.18))
                
                Text("\(fromAmount) \(fromAsset.symbol)")
                    .font(.clashGroteskBold(size: max(28, 48 * rs)))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            .padding(.bottom, max(10, 20 * rs))
            
            // Arrow
            Image(systemName: "arrow.down")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.10))
                .padding(.bottom, max(10, 20 * rs))
            
            // Receive estimate (using live rate)
            if let amount = Double(fromAmount), let provider = selectedProvider {
                let rate = priceService.exchangeRate ?? 1.0
                let estimated = amount * rate * (1.0 - provider.feePercent / 100.0)
                VStack(spacing: 4) {
                    Text("RECEIVE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.18))
                    
                    Text("≈ \(estimated >= 1 ? String(format: "%.6f", estimated) : String(format: "%.8f", estimated))")
                        .font(.clashGroteskBold(size: max(24, 42 * rs)))
                        .foregroundColor(.white.opacity(0.60))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    
                    Text(toAsset.symbol)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.22))
                }
            }
            
            Spacer().frame(height: max(16, 36 * rs))
            
            // Detail rows
            VStack(spacing: 8) {
                if let provider = selectedProvider {
                    detailRow(label: "PROVIDER", value: provider.name)
                    detailRow(label: "FEE", value: provider.feePercent == 0 ? "None" : "\(String(format: "%.2f", provider.feePercent))%")
                    detailRow(label: "TIME", value: provider.estimatedTime)
                    if swapMode == .dex {
                        detailRow(label: "SLIPPAGE", value: "\(String(format: "%.1f", slippageTolerance))%")
                    }
                    detailRow(label: "TYPE", value: provider.isNonCustodial ? "Non-custodial" : "Custodial")
                    if let rate = priceService.exchangeRate {
                        let rateStr = rate >= 1
                            ? String(format: "%.2f", rate)
                            : String(format: "%.6f", rate)
                        detailRow(label: "RATE", value: "1 \(fromAsset.symbol) = \(rateStr) \(toAsset.symbol)")
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.04), lineWidth: 1)
            )
            
            Spacer().frame(height: max(16, 32 * rs))
            
            // Hold to confirm
            HoldToConfirmButton(label: "HOLD TO SWAP", duration: 1.5) {
                executeSwap()
            }
        }
    }
    
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.18))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.50))
        }
    }
    
    // MARK: - Navigation
    
    private var navigationControls: some View {
        HStack(spacing: 12) {
            // Back button (hidden on step 0)
            if currentStep > 0 {
                Button {
                    direction = .backward
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        currentStep -= 1
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                        Text("BACK")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.5)
                    }
                    .foregroundColor(.white.opacity(isHoveringBack ? 0.50 : 0.22))
                    .frame(height: 48)
                    .padding(.horizontal, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(isHoveringBack ? 0.06 : 0.02))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.04), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { h in withAnimation(.easeOut(duration: 0.12)) { isHoveringBack = h } }
            }
            
            Spacer()
            
            // Forward button (hidden on review step — hold-to-confirm replaces it)
            if currentStep < totalSteps - 1 {
                Button {
                    guard ctaEnabled else { return }
                    direction = .forward
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        currentStep += 1
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(ctaLabel)
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.5)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(ctaEnabled
                                     ? .white.opacity(isHoveringNext ? 0.80 : 0.55)
                                     : .white.opacity(0.10))
                    .frame(maxWidth: currentStep == 0 ? .infinity : nil)
                    .frame(height: 48)
                    .padding(.horizontal, 24)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(ctaEnabled
                                  ? Color.white.opacity(isHoveringNext ? 0.10 : 0.06)
                                  : Color.white.opacity(0.02))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                ctaEnabled
                                    ? Color.white.opacity(0.10)
                                    : Color.white.opacity(0.03),
                                lineWidth: 1
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!ctaEnabled)
                .onHover { h in withAnimation(.easeOut(duration: 0.12)) { isHoveringNext = h } }
            }
        }
    }
    
    // MARK: - Helpers
    
    private var ctaLabel: String {
        switch currentStep {
        case 0: return "CONTINUE"
        case 1: return fromAmount.isEmpty ? "ENTER AMOUNT" : "CONTINUE"
        case 2: return selectedProvider == nil ? "SELECT PROVIDER" : "CONTINUE"
        default: return "CONTINUE"
        }
    }
    
    private var ctaEnabled: Bool {
        switch currentStep {
        case 0: return true
        case 1: return !fromAmount.isEmpty && (Double(fromAmount) ?? 0) > 0
        case 2: return selectedProvider != nil
        case 3: return true
        default: return false
        }
    }
    
    // MARK: - Success Overlay
    
    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { }
            
            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        .frame(width: 90, height: 90)
                        .scaleEffect(pulseRing ? 1.8 : 1.0)
                        .opacity(pulseRing ? 0 : 0.3)
                    
                    Circle()
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 64, height: 64)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white.opacity(0.75))
                }
                
                VStack(spacing: 8) {
                    Text("SWAP INITIATED")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.40))
                    
                    Text("\(fromAmount) \(fromAsset.symbol) → \(toAsset.symbol)")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.60))
                }
                
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showSuccess = false
                        currentStep = 0
                        fromAmount = ""
                        selectedProvider = nil
                        pulseRing = false
                    }
                } label: {
                    Text("DONE")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.60))
                        .frame(width: 140, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(48)
        }
    }
    
    // MARK: - Actions
    
    private func executeSwap() {
        guard let provider = selectedProvider,
              let amount = Double(fromAmount),
              amount > 0 else { return }
        
        if swapMode == .crossChain, let url = URL(string: provider.widgetURL) {
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #endif
        }
        
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            showSuccess = true
        }
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
            pulseRing = true
        }
    }
}

// MARK: - Hold To Confirm Button (FIX 4: Clipped, offset-based fill)
// Physical interaction: press and hold to fill, release to cancel
// Progress bar strictly clipped to button boundary at all times

struct HoldToConfirmButton: View {
    let label: String
    let duration: TimeInterval
    let action: () -> Void
    
    @State private var progress: CGFloat = 0
    @State private var isHolding = false
    @State private var holdWorkItem: DispatchWorkItem?
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Track
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.03))
            
            // Progress fill — offset-based translateX approach (FIX 4)
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: geo.size.width)
                    .offset(x: geo.size.width * (progress - 1))
            }
            
            // Border
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(progress > 0.05 ? 0.18 : 0.06),
                    lineWidth: 1
                )
            
            // Label
            Text(progress > 0.05 ? "HOLD…" : label)
                .font(.system(size: 12, weight: .bold))
                .tracking(2.5)
                .foregroundColor(.white.opacity(progress > 0.05 ? 0.85 : 0.45))
                .frame(maxWidth: .infinity)
        }
        .frame(height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isHolding else { return }
                    isHolding = true
                    withAnimation(.linear(duration: duration)) {
                        progress = 1.0
                    }
                    let work = DispatchWorkItem {
                        if isHolding {
                            action()
                            isHolding = false
                            withAnimation(.spring(response: 0.3)) {
                                progress = 0
                            }
                        }
                    }
                    holdWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
                }
                .onEnded { _ in
                    isHolding = false
                    holdWorkItem?.cancel()
                    holdWorkItem = nil
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        progress = 0
                    }
                }
        )
    }
}

// MARK: - Swap Asset

enum SwapAsset: String, CaseIterable, Identifiable {
    case bitcoin = "BTC"
    case ethereum = "ETH"
    case litecoin = "LTC"
    case solana = "SOL"
    case bnb = "BNB"
    case xrp = "XRP"
    case dogecoin = "DOGE"
    case avalanche = "AVAX"
    case polygon = "MATIC"
    case cardano = "ADA"
    case usdc = "USDC"
    case usdt = "USDT"
    
    var id: String { rawValue }
    var symbol: String { rawValue }
    
    var name: String {
        switch self {
        case .bitcoin: return "Bitcoin"
        case .ethereum: return "Ethereum"
        case .litecoin: return "Litecoin"
        case .solana: return "Solana"
        case .bnb: return "BNB"
        case .xrp: return "XRP"
        case .dogecoin: return "Dogecoin"
        case .avalanche: return "Avalanche"
        case .polygon: return "Polygon"
        case .cardano: return "Cardano"
        case .usdc: return "USD Coin"
        case .usdt: return "Tether"
        }
    }
    
    var icon: String {
        switch self {
        case .bitcoin: return "bitcoinsign.circle.fill"
        case .ethereum: return "e.circle.fill"
        case .litecoin: return "l.circle.fill"
        case .solana: return "s.circle.fill"
        case .bnb: return "b.circle.fill"
        case .xrp: return "x.circle.fill"
        case .dogecoin: return "d.circle.fill"
        case .avalanche: return "a.circle.fill"
        case .polygon: return "p.circle.fill"
        case .cardano: return "a.circle.fill"
        case .usdc, .usdt: return "dollarsign.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .bitcoin: return HawalaTheme.Colors.bitcoin
        case .ethereum: return HawalaTheme.Colors.ethereum
        case .litecoin: return HawalaTheme.Colors.litecoin
        case .solana: return HawalaTheme.Colors.solana
        case .bnb: return HawalaTheme.Colors.bnb
        case .xrp: return Color(hex: "00AAE4")
        case .dogecoin: return Color(hex: "C2A633")
        case .avalanche: return Color(hex: "E84142")
        case .polygon: return Color(hex: "8247E5")
        case .cardano: return Color(hex: "0033AD")
        case .usdc: return Color(hex: "2775CA")
        case .usdt: return Color(hex: "50AF95")
        }
    }
    
    var coinGeckoID: String {
        switch self {
        case .bitcoin: return "bitcoin"
        case .ethereum: return "ethereum"
        case .litecoin: return "litecoin"
        case .solana: return "solana"
        case .bnb: return "binancecoin"
        case .xrp: return "ripple"
        case .dogecoin: return "dogecoin"
        case .avalanche: return "avalanche-2"
        case .polygon: return "matic-network"
        case .cardano: return "cardano"
        case .usdc: return "usd-coin"
        case .usdt: return "tether"
        }
    }
}

// MARK: - Swap Provider Info

struct SwapProviderInfo: Identifiable {
    let id: String
    let name: String
    let shortName: String
    let tagline: String
    let icon: String
    let brandColor: Color
    let feePercent: Double
    let estimatedTime: String
    let supportedPairs: Int
    let isNonCustodial: Bool
    let features: [String]
    let affiliateModel: String
    let signupURL: String
    let widgetURL: String
    let isBestRate: Bool
    
    static let crossChainProviders: [SwapProviderInfo] = [
        SwapProviderInfo(id: "changelly", name: "Changelly", shortName: "Changelly", tagline: "Instant swaps with fixed and floating rates.", icon: "arrow.triangle.2.circlepath.circle.fill", brandColor: Color(hex: "47B85F"), feePercent: 0.25, estimatedTime: "5–30 min", supportedPairs: 500, isNonCustodial: true, features: ["creditcard.fill", "lock.shield.fill", "clock.fill"], affiliateModel: "Revenue share 50% of fees", signupURL: "https://changelly.com/for-partners", widgetURL: "https://widget.changelly.com", isBestRate: false),
        SwapProviderInfo(id: "changenow", name: "ChangeNOW", shortName: "ChangeNOW", tagline: "No registration, no limits. 900+ crypto assets.", icon: "bolt.circle.fill", brandColor: Color(hex: "00C26F"), feePercent: 0.50, estimatedTime: "5–30 min", supportedPairs: 900, isNonCustodial: true, features: ["lock.shield.fill", "infinity", "clock.fill"], affiliateModel: "Revenue share 50% of fees", signupURL: "https://changenow.io/affiliate", widgetURL: "https://changenow.io/embeds/exchange-widget", isBestRate: false),
        SwapProviderInfo(id: "simpleswap", name: "SimpleSwap", shortName: "SimpleSwap", tagline: "No registration. 1500+ cryptos. Fixed & floating rates.", icon: "arrow.left.arrow.right.circle.fill", brandColor: Color(hex: "5271FF"), feePercent: 0.50, estimatedTime: "10–40 min", supportedPairs: 1500, isNonCustodial: true, features: ["lock.shield.fill", "infinity", "clock.fill"], affiliateModel: "Revenue share 50% of swaps", signupURL: "https://simpleswap.io/affiliate", widgetURL: "https://simpleswap.io/widget", isBestRate: false),
        SwapProviderInfo(id: "exolix", name: "Exolix", shortName: "Exolix", tagline: "Fixed-rate swaps with no hidden fees.", icon: "arrow.2.squarepath", brandColor: Color(hex: "3B82F6"), feePercent: 0.30, estimatedTime: "5–20 min", supportedPairs: 500, isNonCustodial: true, features: ["lock.shield.fill", "checkmark.shield.fill", "clock.fill"], affiliateModel: "Revenue share per swap", signupURL: "https://exolix.com/affiliate", widgetURL: "https://exolix.com/widget", isBestRate: false),
        SwapProviderInfo(id: "sideshift", name: "SideShift.ai", shortName: "SideShift", tagline: "No sign-up swaps with auto-shifting. Privacy-first.", icon: "arrow.right.arrow.left", brandColor: Color(hex: "8B5CF6"), feePercent: 0.50, estimatedTime: "5–15 min", supportedPairs: 100, isNonCustodial: true, features: ["eye.slash.fill", "lock.shield.fill", "bolt.fill"], affiliateModel: "Revenue share per swap via affiliate ID", signupURL: "https://sideshift.ai/affiliate", widgetURL: "https://sideshift.ai", isBestRate: false),
        SwapProviderInfo(id: "thorswap", name: "THORSwap", shortName: "THORSwap", tagline: "Native cross-chain DEX powered by THORChain.", icon: "bolt.horizontal.circle.fill", brandColor: Color(hex: "00D1A0"), feePercent: 0.30, estimatedTime: "10–60 min", supportedPairs: 5000, isNonCustodial: true, features: ["network", "lock.shield.fill", "link"], affiliateModel: "Affiliate fee embedded in swap TX", signupURL: "https://docs.thorswap.net/aggregation-api", widgetURL: "https://app.thorswap.finance", isBestRate: false),
        SwapProviderInfo(id: "stealthex", name: "StealthEX", shortName: "StealthEX", tagline: "No limits, no registration. 1400+ assets.", icon: "eye.slash.circle.fill", brandColor: Color(hex: "2DD282"), feePercent: 0.40, estimatedTime: "10–30 min", supportedPairs: 1400, isNonCustodial: true, features: ["eye.slash.fill", "infinity", "clock.fill"], affiliateModel: "Revenue share up to 50%", signupURL: "https://stealthex.io/affiliate", widgetURL: "https://stealthex.io/widget", isBestRate: false),
        SwapProviderInfo(id: "letsexchange", name: "LetsExchange", shortName: "LetsExch", tagline: "Fast, limitless swaps for 4800+ coins.", icon: "arrow.triangle.swap", brandColor: Color(hex: "FF6B2D"), feePercent: 0.35, estimatedTime: "5–30 min", supportedPairs: 4800, isNonCustodial: true, features: ["infinity", "bolt.fill", "lock.shield.fill"], affiliateModel: "Revenue share 50% of fees", signupURL: "https://letsexchange.io/affiliate-program", widgetURL: "https://letsexchange.io/widget", isBestRate: false),
        SwapProviderInfo(id: "swapzone", name: "Swapzone", shortName: "Swapzone", tagline: "Aggregator — compares 20+ providers for best rates.", icon: "arrow.triangle.merge", brandColor: Color(hex: "FF9F43"), feePercent: 0.0, estimatedTime: "5–30 min", supportedPairs: 1600, isNonCustodial: true, features: ["arrow.triangle.merge", "chart.bar.fill", "lock.shield.fill"], affiliateModel: "Revenue share on aggregated swaps", signupURL: "https://swapzone.io/partnership", widgetURL: "https://swapzone.io/widget", isBestRate: true),
    ]
    
    static let dexProviders: [SwapProviderInfo] = [
        SwapProviderInfo(id: "1inch", name: "1inch Fusion", shortName: "1inch", tagline: "Multi-chain DEX aggregator. 400+ DEXs.", icon: "1.circle.fill", brandColor: Color(hex: "2AABEE"), feePercent: 0.0, estimatedTime: "< 1 min", supportedPairs: 10000, isNonCustodial: true, features: ["network", "chart.bar.fill", "bolt.fill"], affiliateModel: "Referral fee via swap surplus", signupURL: "https://portal.1inch.dev", widgetURL: "https://app.1inch.io", isBestRate: false),
        SwapProviderInfo(id: "0x", name: "0x Protocol", shortName: "0x", tagline: "Professional-grade API for DEX swaps.", icon: "0.circle.fill", brandColor: Color(hex: "333333"), feePercent: 0.0, estimatedTime: "< 1 min", supportedPairs: 5000, isNonCustodial: true, features: ["network", "lock.shield.fill", "gearshape.fill"], affiliateModel: "Affiliate fee (configurable bps)", signupURL: "https://0x.org/docs/developer-resources/signup", widgetURL: "https://matcha.xyz", isBestRate: false),
        SwapProviderInfo(id: "paraswap", name: "ParaSwap", shortName: "ParaSwap", tagline: "Multi-chain aggregator with MEV protection.", icon: "p.circle.fill", brandColor: Color(hex: "0058FF"), feePercent: 0.0, estimatedTime: "< 1 min", supportedPairs: 8000, isNonCustodial: true, features: ["shield.checkered", "bolt.fill", "chart.bar.fill"], affiliateModel: "Revenue share via partner fee", signupURL: "https://developers.paraswap.network", widgetURL: "https://app.paraswap.io", isBestRate: false),
        SwapProviderInfo(id: "jupiter", name: "Jupiter", shortName: "Jupiter", tagline: "Solana's #1 DEX aggregator. Limit orders & DCA.", icon: "j.circle.fill", brandColor: Color(hex: "C7F284"), feePercent: 0.0, estimatedTime: "< 10 sec", supportedPairs: 3000, isNonCustodial: true, features: ["bolt.fill", "chart.bar.fill", "timer"], affiliateModel: "Referral fee via platform fee", signupURL: "https://station.jup.ag/docs/apis", widgetURL: "https://jup.ag", isBestRate: true),
        SwapProviderInfo(id: "uniswap", name: "Uniswap", shortName: "Uniswap", tagline: "The original DEX. Deepest EVM liquidity.", icon: "u.circle.fill", brandColor: Color(hex: "FF007A"), feePercent: 0.30, estimatedTime: "< 1 min", supportedPairs: 15000, isNonCustodial: true, features: ["drop.fill", "network", "lock.shield.fill"], affiliateModel: "Interface fee (front-end referral)", signupURL: "https://docs.uniswap.org/sdk/v3/overview", widgetURL: "https://app.uniswap.org", isBestRate: false),
        SwapProviderInfo(id: "kyberswap", name: "KyberSwap", shortName: "KyberSwap", tagline: "Multi-chain aggregator with dynamic routing.", icon: "k.circle.fill", brandColor: Color(hex: "31CB9E"), feePercent: 0.0, estimatedTime: "< 1 min", supportedPairs: 6000, isNonCustodial: true, features: ["chart.bar.fill", "bolt.fill", "network"], affiliateModel: "Partner commission via referral", signupURL: "https://docs.kyberswap.com/kyberswap-solutions/kyberswap-aggregator", widgetURL: "https://kyberswap.com", isBestRate: false),
        SwapProviderInfo(id: "odos", name: "Odos", shortName: "Odos", tagline: "Smart order routing with multi-input swaps.", icon: "o.circle.fill", brandColor: Color(hex: "6A5ACD"), feePercent: 0.0, estimatedTime: "< 1 min", supportedPairs: 4000, isNonCustodial: true, features: ["point.3.connected.trianglepath.dotted", "bolt.fill", "chart.bar.fill"], affiliateModel: "Referral fee (configurable bps)", signupURL: "https://docs.odos.xyz", widgetURL: "https://app.odos.xyz", isBestRate: false),
        SwapProviderInfo(id: "lifi", name: "LI.FI", shortName: "LI.FI", tagline: "Cross-chain DEX aggregator — bridges + swaps.", icon: "link.circle.fill", brandColor: Color(hex: "BF5AF2"), feePercent: 0.0, estimatedTime: "1–10 min", supportedPairs: 10000, isNonCustodial: true, features: ["link", "arrow.triangle.merge", "bolt.fill"], affiliateModel: "Integrator fee (configurable bps)", signupURL: "https://docs.li.fi/integrate-li.fi-sdk", widgetURL: "https://transferto.xyz", isBestRate: false),
    ]
}

// MARK: - Provider Row (Monochrome)

struct SwapProviderRow: View {
    let provider: SwapProviderInfo
    let fromAmount: Double
    let fromSymbol: String
    let toSymbol: String
    let exchangeRate: Double?
    let isSelected: Bool
    let isBest: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Monochrome icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(isSelected ? 0.08 : 0.03))
                        .frame(width: 36, height: 36)
                    Image(systemName: provider.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(isSelected ? 0.60 : 0.30))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(provider.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(isSelected ? 0.85 : 0.55))
                        if isBest {
                            Text("BEST")
                                .font(.system(size: 8, weight: .bold))
                                .tracking(1)
                                .foregroundColor(.white.opacity(0.50))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.white.opacity(0.08))
                                )
                        }
                    }
                    Text(provider.estimatedTime)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.22))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    if fromAmount > 0 {
                        let rate = exchangeRate ?? 1.0
                        let receive = fromAmount * rate * (1.0 - provider.feePercent / 100.0)
                        Text("≈ \(receive >= 1 ? String(format: "%.4f", receive) : String(format: "%.6f", receive)) \(toSymbol)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.50))
                            .lineLimit(1)
                    }
                    Text(provider.feePercent == 0 ? "No fee" : "\(provider.feePercent, specifier: "%.2f")% fee")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(provider.feePercent == 0 ? 0.40 : 0.22))
                }
                
                // Radio indicator
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? Color.white.opacity(0.50) : Color.white.opacity(0.08),
                            lineWidth: isSelected ? 2 : 1
                        )
                        .frame(width: 20, height: 20)
                    if isSelected {
                        Circle()
                            .fill(Color.white.opacity(0.60))
                            .frame(width: 10, height: 10)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected
                          ? Color.white.opacity(0.06)
                          : (isHovered ? Color.white.opacity(0.03) : Color.white.opacity(0.015)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color.white.opacity(0.15)
                            : Color.white.opacity(isHovered ? 0.06 : 0.03),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { isHovered = h } }
    }
}

// MARK: - Slippage Chip (Monochrome)

struct SwapSlippageChip: View {
    let value: Double
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Text("\(value, specifier: value < 1 ? "%.1f" : "%.0f")%")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(isSelected ? .white.opacity(0.70) : .white.opacity(0.30))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected
                              ? Color.white.opacity(0.10)
                              : (isHovered ? Color.white.opacity(0.05) : Color.white.opacity(0.02)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.white.opacity(0.18) : Color.white.opacity(0.04),
                            lineWidth: 1
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { isHovered = h } }
    }
}
