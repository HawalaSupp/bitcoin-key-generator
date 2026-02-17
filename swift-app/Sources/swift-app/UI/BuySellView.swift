import SwiftUI

// MARK: - Width Tracking (BuySell)

private struct BuySellWidthKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 600
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Buy & Sell View (HAWALA Design Language)
// Monochrome · Monumental · No traditional form patterns
// Transparent over global silk background → floating content → hold-to-confirm

struct BuySellView: View {
    let keys: AllKeys?
    
    @StateObject private var onRampService = OnRampService.shared
    
    // Funnel state
    @State private var currentStep: Int = 0
    @State private var mode: TransactionMode = .buy
    @State private var selectedCrypto: CryptoAsset = .bitcoin
    @State private var fiatAmount: String = ""
    @State private var selectedFiat: OnRampService.FiatCurrency = .usd
    @State private var selectedPaymentMethod: OnRampService.PaymentMethod = .creditCard
    @State private var selectedProvider: OnRampProvider? = nil
    
    // Animation & interaction
    @State private var direction: BuySellSlideDirection = .forward
    @State private var showSuccess = false
    @State private var pulseRing = false
    @State private var isHoveringBack = false
    @State private var isHoveringNext = false
    
    // Responsive layout
    @State private var containerWidth: CGFloat = 600
    
    private var rs: CGFloat {
        min(1.0, max(0.55, containerWidth / 700))
    }
    
    enum TransactionMode: String, CaseIterable {
        case buy = "Buy"
        case sell = "Sell"
    }
    
    enum BuySellSlideDirection { case forward, backward }
    
    private let totalSteps = 4
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // ── No local background — global silk shows through ──
            
            // ── Floating content ──
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: max(16, 36 * rs))
                    
                    // Minimal step indicator
                    stepIndicator
                        .padding(.horizontal, max(16, 40 * rs))
                    
                    Spacer().frame(height: max(20, 48 * rs))
                    
                    // Step content
                    ZStack {
                        Group {
                            switch currentStep {
                            case 0: step0_CryptoSelect
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
                Color.clear.preference(key: BuySellWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(BuySellWidthKey.self) { containerWidth = $0 }
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
    
    // MARK: - Step 0: Crypto Selection
    
    private var step0_CryptoSelect: some View {
        VStack(spacing: 0) {
            // Monumental mode display
            Text(mode == .buy ? "BUY" : "SELL")
                .font(.clashGroteskBold(size: max(28, 56 * rs)))
                .foregroundColor(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.bottom, 12)
            
            // Mode toggle — minimal
            modeToggle
                .padding(.bottom, max(16, 40 * rs))
            
            // Token label
            Text("SELECT ASSET")
                .font(.system(size: 10, weight: .bold))
                .tracking(3)
                .foregroundColor(.white.opacity(0.22))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
            
            // Token grid (replaces dropdown list)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], spacing: 6) {
                ForEach(CryptoAsset.allCases) { crypto in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedCrypto = crypto
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(crypto.symbol)
                                .font(.system(size: 13, weight: selectedCrypto == crypto ? .bold : .medium, design: .monospaced))
                                .foregroundColor(selectedCrypto == crypto ? .white : .white.opacity(0.30))
                            
                            Text(crypto.name)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(selectedCrypto == crypto ? 0.40 : 0.12))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selectedCrypto == crypto
                                      ? Color.white.opacity(0.10)
                                      : Color.white.opacity(0.02))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    selectedCrypto == crypto
                                        ? Color.white.opacity(0.18)
                                        : Color.white.opacity(0.04),
                                    lineWidth: 1
                                )
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var modeToggle: some View {
        HStack(spacing: 20) {
            ForEach(TransactionMode.allCases, id: \.self) { txMode in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        mode = txMode
                    }
                } label: {
                    Text(txMode.rawValue.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundColor(mode == txMode
                                         ? .white.opacity(0.55)
                                         : .white.opacity(0.12))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Step 1: Amount
    
    private var step1_Amount: some View {
        VStack(spacing: 0) {
            // Context badge
            HStack(spacing: 6) {
                Text(mode == .buy ? "BUYING" : "SELLING")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.22))
                Text(selectedCrypto.symbol)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.40))
            }
            .padding(.bottom, max(16, 40 * rs))
            
            // Monumental amount
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(selectedFiat.symbol)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white.opacity(0.22))
                
                TextField("0", text: $fiatAmount)
                    .font(.clashGroteskBold(size: max(36, 72 * rs)))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.plain)
                    .minimumScaleFactor(0.5)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 20)
            
            // Quick amount chips
            HStack(spacing: 8) {
                ForEach(["50", "100", "250", "500", "1000"], id: \.self) { amount in
                    BuySellQuickChip(
                        label: "\(selectedFiat.symbol)\(amount)",
                        isSelected: fiatAmount == amount
                    ) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            fiatAmount = amount
                        }
                    }
                }
            }
            .padding(.bottom, max(16, 32 * rs))
            
            // Currency & payment — inline strips (not dropdowns)
            VStack(alignment: .leading, spacing: 16) {
                // Currency selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("CURRENCY")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.22))
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(OnRampService.FiatCurrency.allCases) { currency in
                                Button {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                        selectedFiat = currency
                                    }
                                } label: {
                                    Text("\(currency.symbol) \(currency.rawValue)")
                                        .font(.system(size: 12, weight: selectedFiat == currency ? .bold : .medium))
                                        .foregroundColor(selectedFiat == currency ? .white : .white.opacity(0.25))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule()
                                                .fill(selectedFiat == currency
                                                      ? Color.white.opacity(0.10)
                                                      : Color.white.opacity(0.02))
                                        )
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(
                                                    selectedFiat == currency
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
                
                // Payment method selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("PAY WITH")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.22))
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(OnRampService.PaymentMethod.allCases) { method in
                                Button {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                        selectedPaymentMethod = method
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: method.iconName)
                                            .font(.system(size: 10, weight: .medium))
                                        Text(method.rawValue)
                                            .font(.system(size: 12, weight: selectedPaymentMethod == method ? .bold : .medium))
                                    }
                                    .foregroundColor(selectedPaymentMethod == method ? .white : .white.opacity(0.25))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(selectedPaymentMethod == method
                                                  ? Color.white.opacity(0.10)
                                                  : Color.white.opacity(0.02))
                                    )
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(
                                                selectedPaymentMethod == method
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
        }
    }
    
    // MARK: - Step 2: Provider
    
    private var step2_Provider: some View {
        VStack(spacing: 0) {
            // Monumental label
            Text("PROVIDER")
                .font(.clashGroteskBold(size: max(24, 42 * rs)))
                .foregroundColor(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.bottom, 8)
            
            // Context
            HStack(spacing: 6) {
                Text(mode == .buy ? "Buying" : "Selling")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.30))
                Text(selectedCrypto.symbol)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.40))
                Text("for")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.18))
                Text("\(selectedFiat.symbol)\(fiatAmount)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.40))
            }
            .padding(.bottom, max(14, 28 * rs))
            
            // Provider list
            let providers = OnRampProvider.allProviders.filter { mode == .buy ? $0.supportsBuy : $0.supportsSell }
            let best = providers.min(by: { $0.feePercent < $1.feePercent })
            
            VStack(spacing: 4) {
                ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                    BuySellProviderRow(
                        provider: provider,
                        fiatAmount: Double(fiatAmount) ?? 0,
                        fiatSymbol: selectedFiat.symbol,
                        cryptoSymbol: selectedCrypto.symbol,
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
            if mode == .buy {
                // YOU PAY
                VStack(spacing: 4) {
                    Text("YOU PAY")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.18))
                    
                    Text("\(selectedFiat.symbol)\(fiatAmount)")
                        .font(.clashGroteskBold(size: max(28, 48 * rs)))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                .padding(.bottom, max(10, 20 * rs))
                
                Image(systemName: "arrow.down")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.10))
                    .padding(.bottom, max(10, 20 * rs))
                
                // YOU RECEIVE
                VStack(spacing: 4) {
                    Text("YOU RECEIVE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.18))
                    
                    Text(selectedCrypto.symbol)
                        .font(.clashGroteskBold(size: max(24, 42 * rs)))
                        .foregroundColor(.white.opacity(0.60))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
            } else {
                // YOU SELL
                VStack(spacing: 4) {
                    Text("YOU SELL")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.18))
                    
                    Text(selectedCrypto.symbol)
                        .font(.clashGroteskBold(size: max(28, 48 * rs)))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                .padding(.bottom, max(10, 20 * rs))
                
                Image(systemName: "arrow.down")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.10))
                    .padding(.bottom, max(10, 20 * rs))
                
                // YOU RECEIVE
                VStack(spacing: 4) {
                    Text("YOU RECEIVE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.18))
                    
                    Text("\(selectedFiat.symbol)\(fiatAmount)")
                        .font(.clashGroteskBold(size: max(24, 42 * rs)))
                        .foregroundColor(.white.opacity(0.60))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
            }
            
            Spacer().frame(height: max(16, 36 * rs))
            
            // Detail rows
            VStack(spacing: 8) {
                if let provider = selectedProvider {
                    detailRow(label: "PROVIDER", value: provider.name)
                    detailRow(label: "FEE", value: "\(String(format: "%.1f", provider.feePercent))%")
                    if let amount = Double(fiatAmount) {
                        let fee = amount * (provider.feePercent / 100.0)
                        detailRow(label: "FEE AMOUNT", value: "\(selectedFiat.symbol)\(String(format: "%.2f", fee))")
                    }
                    detailRow(label: "PAYMENT", value: selectedPaymentMethod.rawValue)
                    detailRow(label: "ASSET", value: "\(selectedCrypto.name) (\(selectedCrypto.symbol))")
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
            HoldToConfirmButton(
                label: mode == .buy ? "HOLD TO BUY" : "HOLD TO SELL",
                duration: 1.5
            ) {
                proceedWithTransaction()
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
        case 1: return fiatAmount.isEmpty ? "ENTER AMOUNT" : "CONTINUE"
        case 2: return selectedProvider == nil ? "SELECT PROVIDER" : "CONTINUE"
        default: return "CONTINUE"
        }
    }
    
    private var ctaEnabled: Bool {
        switch currentStep {
        case 0: return true
        case 1: return !fiatAmount.isEmpty && (Double(fiatAmount) ?? 0) > 0
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
                    Text("ORDER PLACED")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.40))
                    
                    Text("\(mode == .buy ? "Buying" : "Selling") \(selectedCrypto.symbol) for \(selectedFiat.symbol)\(fiatAmount)")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.60))
                }
                
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showSuccess = false
                        currentStep = 0
                        fiatAmount = ""
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
    
    private func proceedWithTransaction() {
        guard let provider = selectedProvider,
              let amount = Double(fiatAmount),
              amount > 0 else { return }
        
        let walletAddress = walletAddressForCrypto(selectedCrypto)
        
        let request = OnRampService.OnRampRequest(
            fiatAmount: amount,
            fiatCurrency: selectedFiat,
            cryptoSymbol: selectedCrypto.symbol,
            walletAddress: walletAddress
        )
        
        if let url = onRampService.buildWidgetURL(provider: provider.serviceProvider, request: request) {
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
    
    private func walletAddressForCrypto(_ crypto: CryptoAsset) -> String {
        guard let keys = keys else { return "" }
        switch crypto {
        case .bitcoin:   return keys.bitcoin.address
        case .ethereum:  return keys.ethereum.address
        case .solana:    return keys.solana.publicKeyBase58
        case .usdc, .usdt: return keys.ethereum.address
        case .bnb:       return keys.bnb.address
        case .xrp:       return keys.xrp.classicAddress
        case .cardano:   return keys.cardano.address
        case .polygon:   return keys.ethereum.address
        case .avalanche: return keys.ethereum.address
        case .litecoin:  return keys.litecoin.address
        case .dogecoin:  return keys.dogecoin.address
        }
    }
}

// MARK: - Quick Amount Chip (Monochrome)

struct BuySellQuickChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(isSelected ? .white.opacity(0.70) : .white.opacity(0.25))
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

// MARK: - Crypto Row (Monochrome — kept for potential list view)

struct BuySellCryptoRow: View {
    let crypto: CryptoAsset
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(isSelected ? 0.08 : 0.03))
                        .frame(width: 36, height: 36)
                    Image(systemName: crypto.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(isSelected ? 0.60 : 0.30))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(crypto.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(isSelected ? 0.85 : 0.55))
                    Text(crypto.symbol)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.22))
                }
                
                Spacer()
                
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

// MARK: - Provider Row (Monochrome)

struct BuySellProviderRow: View {
    let provider: OnRampProvider
    let fiatAmount: Double
    let fiatSymbol: String
    let cryptoSymbol: String
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
                    Text("\(provider.supportedCryptos)+ cryptos · \(provider.supportedCountries)+ countries")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.22))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(provider.feePercent, specifier: "%.1f")% fee")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.50))
                    if fiatAmount > 0 {
                        let fee = fiatAmount * (provider.feePercent / 100.0)
                        Text("\(fiatSymbol)\(fee, specifier: "%.2f")")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.22))
                    }
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

// MARK: - Crypto Asset Model

enum CryptoAsset: String, CaseIterable, Identifiable {
    case bitcoin = "BTC"
    case ethereum = "ETH"
    case solana = "SOL"
    case usdc = "USDC"
    case usdt = "USDT"
    case bnb = "BNB"
    case xrp = "XRP"
    case cardano = "ADA"
    case polygon = "MATIC"
    case avalanche = "AVAX"
    case litecoin = "LTC"
    case dogecoin = "DOGE"
    
    var id: String { rawValue }
    var symbol: String { rawValue }
    
    var name: String {
        switch self {
        case .bitcoin: return "Bitcoin"
        case .ethereum: return "Ethereum"
        case .solana: return "Solana"
        case .usdc: return "USD Coin"
        case .usdt: return "Tether"
        case .bnb: return "BNB"
        case .xrp: return "XRP"
        case .cardano: return "Cardano"
        case .polygon: return "Polygon"
        case .avalanche: return "Avalanche"
        case .litecoin: return "Litecoin"
        case .dogecoin: return "Dogecoin"
        }
    }
    
    var icon: String {
        switch self {
        case .bitcoin: return "bitcoinsign.circle.fill"
        case .ethereum: return "e.circle.fill"
        case .solana: return "s.circle.fill"
        case .usdc, .usdt: return "dollarsign.circle.fill"
        case .bnb: return "b.circle.fill"
        case .xrp: return "x.circle.fill"
        case .cardano: return "a.circle.fill"
        case .polygon: return "p.circle.fill"
        case .avalanche: return "a.circle.fill"
        case .litecoin: return "l.circle.fill"
        case .dogecoin: return "d.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .bitcoin: return HawalaTheme.Colors.bitcoin
        case .ethereum: return HawalaTheme.Colors.ethereum
        case .solana: return HawalaTheme.Colors.solana
        case .usdc: return Color(hex: "2775CA")
        case .usdt: return Color(hex: "50AF95")
        case .bnb: return HawalaTheme.Colors.bnb
        case .xrp: return Color(hex: "00AAE4")
        case .cardano: return Color(hex: "0033AD")
        case .polygon: return Color(hex: "8247E5")
        case .avalanche: return Color(hex: "E84142")
        case .litecoin: return HawalaTheme.Colors.litecoin
        case .dogecoin: return Color(hex: "C2A633")
        }
    }
}

// MARK: - On-Ramp Provider Model

struct OnRampProvider: Identifiable {
    let id: String
    let name: String
    let shortName: String
    let tagline: String
    let icon: String
    let brandColor: Color
    let feePercent: Double
    let supportedCryptos: Int
    let supportedCountries: Int
    let paymentMethods: [String]
    let affiliateModel: String
    let signupURL: String
    let isBestRate: Bool
    let supportsBuy: Bool
    let supportsSell: Bool
    
    var serviceProvider: OnRampService.Provider {
        switch id {
        case "moonpay": return .moonpay
        case "transak": return .transak
        case "ramp": return .ramp
        default: return .moonpay
        }
    }
    
    static let allProviders: [OnRampProvider] = [
        OnRampProvider(id: "moonpay", name: "MoonPay", shortName: "MoonPay", tagline: "Trusted by 20M+ users worldwide.", icon: "moon.fill", brandColor: Color(hex: "7B61FF"), feePercent: 4.5, supportedCryptos: 100, supportedCountries: 160, paymentMethods: ["creditcard.fill", "building.columns", "apple.logo", "banknote"], affiliateModel: "Revenue share up to 50%", signupURL: "https://dashboard.moonpay.com/register", isBestRate: false, supportsBuy: true, supportsSell: true),
        
        OnRampProvider(id: "transak", name: "Transak", shortName: "Transak", tagline: "Global coverage with local payment methods.", icon: "arrow.triangle.swap", brandColor: Color(hex: "0064FF"), feePercent: 5.0, supportedCryptos: 170, supportedCountries: 170, paymentMethods: ["creditcard.fill", "building.columns", "eurosign.circle", "banknote"], affiliateModel: "Revenue share 10-50%", signupURL: "https://transak.com/partner", isBestRate: false, supportsBuy: true, supportsSell: true),
        
        OnRampProvider(id: "ramp", name: "Ramp Network", shortName: "Ramp", tagline: "Lowest fees with Apple Pay support.", icon: "bolt.fill", brandColor: Color(hex: "21BF73"), feePercent: 2.5, supportedCryptos: 90, supportedCountries: 150, paymentMethods: ["apple.logo", "building.columns", "creditcard.fill", "banknote"], affiliateModel: "Revenue share up to 70%", signupURL: "https://ramp.network/partner", isBestRate: true, supportsBuy: true, supportsSell: true),
        
        OnRampProvider(id: "banxa", name: "Banxa", shortName: "Banxa", tagline: "Regulated on/off-ramp with competitive spreads.", icon: "shield.lefthalf.filled", brandColor: Color(hex: "00D2FF"), feePercent: 2.0, supportedCryptos: 50, supportedCountries: 180, paymentMethods: ["creditcard.fill", "building.columns", "apple.logo", "banknote"], affiliateModel: "Revenue share per transaction", signupURL: "https://banxa.com/partner", isBestRate: false, supportsBuy: true, supportsSell: true),
        
        OnRampProvider(id: "simplex", name: "Simplex (Nuvei)", shortName: "Simplex", tagline: "Fraud-free payments. Zero chargebacks.", icon: "lock.shield.fill", brandColor: Color(hex: "4C6EF5"), feePercent: 5.0, supportedCryptos: 50, supportedCountries: 180, paymentMethods: ["creditcard.fill", "apple.logo", "building.columns", "banknote"], affiliateModel: "Revenue share on fees", signupURL: "https://dashboard.simplex.com/register", isBestRate: false, supportsBuy: true, supportsSell: false),
        
        OnRampProvider(id: "sardine", name: "Sardine", shortName: "Sardine", tagline: "Instant ACH & fraud prevention.", icon: "shield.checkered", brandColor: Color(hex: "FF6B35"), feePercent: 1.5, supportedCryptos: 40, supportedCountries: 50, paymentMethods: ["dollarsign.circle", "building.columns", "creditcard.fill"], affiliateModel: "Customizable revenue share", signupURL: "https://sardine.ai/contact", isBestRate: false, supportsBuy: true, supportsSell: true),
        
        OnRampProvider(id: "mercuryo", name: "Mercuryo", shortName: "Mercuryo", tagline: "Fast Visa/Mastercard checkout.", icon: "creditcard.trianglebadge.exclamationmark", brandColor: Color(hex: "6C5CE7"), feePercent: 3.95, supportedCryptos: 30, supportedCountries: 100, paymentMethods: ["creditcard.fill", "building.columns", "apple.logo"], affiliateModel: "Revenue share 25-50%", signupURL: "https://mercuryo.io/partners", isBestRate: false, supportsBuy: true, supportsSell: true),
        
        OnRampProvider(id: "onramper", name: "Onramper", shortName: "Onramper", tagline: "Aggregator — compares 15+ providers.", icon: "arrow.triangle.merge", brandColor: Color(hex: "00C48C"), feePercent: 1.0, supportedCryptos: 200, supportedCountries: 180, paymentMethods: ["creditcard.fill", "building.columns", "apple.logo", "banknote", "eurosign.circle"], affiliateModel: "Revenue share on volume", signupURL: "https://onramper.com/partner", isBestRate: false, supportsBuy: true, supportsSell: true),
        
        OnRampProvider(id: "alchemy_pay", name: "Alchemy Pay", shortName: "AlchemyPay", tagline: "Fiat-crypto bridge for 173 countries.", icon: "wand.and.stars", brandColor: Color(hex: "2D5BFF"), feePercent: 3.5, supportedCryptos: 300, supportedCountries: 173, paymentMethods: ["creditcard.fill", "building.columns", "apple.logo", "banknote"], affiliateModel: "Commission per transaction", signupURL: "https://alchemypay.org/partner", isBestRate: false, supportsBuy: true, supportsSell: true),
        
        OnRampProvider(id: "topper", name: "Topper (Uphold)", shortName: "Topper", tagline: "White-label widget by Uphold.", icon: "arrow.up.right.circle.fill", brandColor: Color(hex: "49CC68"), feePercent: 3.0, supportedCryptos: 70, supportedCountries: 130, paymentMethods: ["creditcard.fill", "building.columns", "apple.logo"], affiliateModel: "Revenue share per transaction", signupURL: "https://topper.dev", isBestRate: false, supportsBuy: true, supportsSell: true),
        
        OnRampProvider(id: "guardarian", name: "Guardarian", shortName: "Guardarian", tagline: "Non-custodial on-ramp with instant delivery.", icon: "shield.fill", brandColor: Color(hex: "1A73E8"), feePercent: 3.5, supportedCryptos: 400, supportedCountries: 170, paymentMethods: ["creditcard.fill", "eurosign.circle", "building.columns", "banknote"], affiliateModel: "Revenue share on fees", signupURL: "https://guardarian.com/for-partners", isBestRate: false, supportsBuy: true, supportsSell: true),
        
        OnRampProvider(id: "paybis", name: "Paybis", shortName: "Paybis", tagline: "Licensed exchange with widget API.", icon: "dollarsign.arrow.circlepath", brandColor: Color(hex: "FF4081"), feePercent: 2.49, supportedCryptos: 100, supportedCountries: 180, paymentMethods: ["creditcard.fill", "building.columns", "apple.logo", "banknote"], affiliateModel: "Revenue share up to 25%", signupURL: "https://paybis.com/affiliate-program", isBestRate: false, supportsBuy: true, supportsSell: true),
        
        OnRampProvider(id: "utorg", name: "Utorg", shortName: "Utorg", tagline: "EU-licensed widget and API.", icon: "u.circle.fill", brandColor: Color(hex: "5856D6"), feePercent: 4.0, supportedCryptos: 200, supportedCountries: 187, paymentMethods: ["creditcard.fill", "building.columns", "apple.logo", "eurosign.circle"], affiliateModel: "Revenue share per trade", signupURL: "https://utorg.pro/partners", isBestRate: false, supportsBuy: true, supportsSell: true),
        
        OnRampProvider(id: "swipelux", name: "Swipelux", shortName: "Swipelux", tagline: "White-label customizable checkout.", icon: "rectangle.and.hand.point.up.left.fill", brandColor: Color(hex: "00B4D8"), feePercent: 3.5, supportedCryptos: 300, supportedCountries: 150, paymentMethods: ["creditcard.fill", "building.columns", "apple.logo"], affiliateModel: "Revenue share per transaction", signupURL: "https://swipelux.com/for-business", isBestRate: false, supportsBuy: true, supportsSell: true),
        
        OnRampProvider(id: "kado", name: "Kado", shortName: "Kado", tagline: "On/off-ramp for DeFi. No KYC under $300.", icon: "k.circle.fill", brandColor: Color(hex: "6366F1"), feePercent: 1.5, supportedCryptos: 20, supportedCountries: 50, paymentMethods: ["dollarsign.circle", "building.columns", "creditcard.fill"], affiliateModel: "Revenue share on volume", signupURL: "https://kado.money/partners", isBestRate: false, supportsBuy: true, supportsSell: true),
        
        OnRampProvider(id: "robinhood_connect", name: "Robinhood Connect", shortName: "RH Connect", tagline: "Embedded crypto purchasing.", icon: "leaf.fill", brandColor: Color(hex: "00C805"), feePercent: 1.5, supportedCryptos: 15, supportedCountries: 1, paymentMethods: ["building.columns", "dollarsign.circle"], affiliateModel: "Per-transaction referral fee", signupURL: "https://robinhood.com/connect", isBestRate: false, supportsBuy: true, supportsSell: false),
        
        OnRampProvider(id: "coinbase_onramp", name: "Coinbase Onramp", shortName: "CB Onramp", tagline: "Leverage Coinbase accounts.", icon: "c.circle.fill", brandColor: Color(hex: "0052FF"), feePercent: 1.0, supportedCryptos: 100, supportedCountries: 100, paymentMethods: ["building.columns", "dollarsign.circle", "creditcard.fill"], affiliateModel: "Revenue share via Commerce", signupURL: "https://www.coinbase.com/cloud/products/onramp", isBestRate: false, supportsBuy: true, supportsSell: true),
    ]
}
