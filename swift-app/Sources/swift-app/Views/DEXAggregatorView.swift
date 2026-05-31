import SwiftUI

// MARK: - DEX Aggregator View

/// View for comparing and executing swaps across multiple DEX providers
struct DEXAggregatorView: View {
    @StateObject private var service = DEXAggregatorService.shared
    @State private var selectedChain: DEXAggregatorService.SupportedChain = .ethereum
    @State private var fromToken = ""
    @State private var toToken = ""
    @State private var amount = ""
    @State private var slippage = 0.5
    @State private var showSlippageSettings = false
    @State private var showQuoteComparison = false
    @State private var selectedQuote: DEXAggregatorService.SwapQuote?
    @State private var isExecutingSwap = false
    @State private var isCheckingApproval = false
    @State private var isExecutingApproval = false
    @State private var approvalStatus: DEXAggregatorService.TokenApproval?
    @State private var approvalCompletedForQuoteID: UUID?
    @State private var txHash: String?
    @State private var showTxSuccess = false
    /// ROADMAP-07 E9/E10: Quote expiry countdown
    @State private var quoteTimeRemaining: Int = 0
    @State private var quoteExpiryTimer: Timer?
    
    @AppStorage("hawala.biometricForSends") private var biometricForSends = true
    
    /// Optional wallet keys for executing swaps
    var keys: AllKeys?
    
    /// Get the wallet address for the selected chain
    private var walletAddress: String? {
        guard let keys = keys else { return nil }
        switch selectedChain {
        // All EVM chains use the same Ethereum address
        case .ethereum, .bsc, .polygon, .arbitrum, .optimism, .avalanche, .base:
            return keys.ethereum.address
        default: return nil
        }
    }
    
    /// Get the private key for the selected chain
    private var privateKey: String? {
        guard let keys = keys else { return nil }
        switch selectedChain {
        // All EVM chains use the same Ethereum private key
        case .ethereum, .bsc, .polygon, .arbitrum, .optimism, .avalanche, .base:
            return keys.ethereum.privateHex
        default: return nil
        }
    }
    
    // Sample tokens for demo
    private let sampleTokens: [(String, String)] = [
        ("0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE", "ETH"),
        ("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", "USDC"),
        ("0xdAC17F958D2ee523a2206206994597C13D831ec7", "USDT"),
        ("0x6B175474E89094C44Da98b954EescddeB131e232", "DAI"),
        ("0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599", "WBTC"),
    ]
    
    @StateObject private var honeypotDetector = HoneypotDetector.shared
    
    @State private var hoveringChain: String?
    @State private var hoveringGetQuotes = false
    @State private var hoveringQuoteRow: UUID?
    @State private var hoveringSwapDirection = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: HawalaTheme.Spacing.xl) {
                headerSection
                chainSelector
                swapInputSection
                
                // Transfer tax warning (ROADMAP-07 E11)
                transferTaxWarning
                
                // Honeypot warning (ROADMAP-08 E9)
                honeypotWarning
                
                slippageSection
                
                if service.isLoading {
                    loadingSection
                } else if let quotes = service.currentQuotes {
                    quotesSection(quotes)
                }

                if let quote = selectedQuote {
                    approvalSection(for: quote)
                }
                
                if let error = service.error {
                    errorSection(error)
                }
                
                actionButtons
            }
            .padding(HawalaTheme.Spacing.xl)
        }
        .background(HawalaTheme.Colors.background)
        .navigationTitle("DEX Aggregator")
        .onChange(of: fromToken) { newToken in
            // ROADMAP-08 E9: Check token for honeypot when selected
            if !newToken.isEmpty && newToken.hasPrefix("0x") {
                Task { await honeypotDetector.checkToken(newToken, chainId: String(selectedChain.chainId)) }
            }
        }
        .onChange(of: toToken) { newToken in
            if !newToken.isEmpty && newToken.hasPrefix("0x") {
                Task { await honeypotDetector.checkToken(newToken, chainId: String(selectedChain.chainId)) }
            }
        }
        .sheet(isPresented: $showQuoteComparison) {
            if let quotes = service.currentQuotes {
                QuoteComparisonSheet(quotes: quotes, selectedQuote: $selectedQuote)
            }
        }
        .onChange(of: selectedQuote?.id) { _ in
            Task {
                await refreshApprovalStatus()
            }
        }
        .alert("Swap Complete!", isPresented: $showTxSuccess) {
            Button("Done") {
                txHash = nil
                service.clearCache()
            }
        } message: {
            Text("Your swap was submitted successfully. It may take a few moments to confirm on-chain.")
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            // Beta warning banner
            HStack(spacing: HawalaTheme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(HawalaTheme.Colors.warning)
                Text("Preview Feature")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(HawalaTheme.Colors.warning)
                Spacer()
            }
            .padding(.horizontal, HawalaTheme.Spacing.md)
            .padding(.vertical, HawalaTheme.Spacing.sm)
            .background(HawalaTheme.Colors.warning.opacity(0.08))
            .cornerRadius(HawalaTheme.Radius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm)
                    .stroke(HawalaTheme.Colors.warning.opacity(0.2), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Warning: Preview Feature. DEX aggregation is in preview and only shows live quotes when the routing backend is available.")
            
            Text("DEX aggregation is in preview. Hawala now requires live routing responses and will show no quotes when the quote backend or provider configuration is unavailable.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.35))
                .padding(.bottom, HawalaTheme.Spacing.sm)
            
            Text("Compare prices across DEX providers")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))
        }
    }
    
    // MARK: - Chain Selector
    
    private var chainSelector: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            HawalaOverlaySectionHeader(icon: "network", title: "Network")
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HawalaTheme.Spacing.sm) {
                    ForEach(DEXAggregatorService.SupportedChain.allCases.filter { chain in
                        service.getProviders(for: chain).count > 0
                    }) { chain in
                        chainButton(chain)
                    }
                }
            }
        }
    }
    
    private func chainButton(_ chain: DEXAggregatorService.SupportedChain) -> some View {
        let isSelected = selectedChain == chain
        let isHover = hoveringChain == chain.rawValue
        let bgColor: Color = isSelected ? Color.white.opacity(0.10) : (isHover ? Color.white.opacity(0.06) : Color.white.opacity(0.03))
        let borderColor: Color = isSelected ? Color.white.opacity(0.15) : Color.white.opacity(0.06)
        
        return Button {
            withAnimation(HawalaTheme.Animation.fast) {
                selectedChain = chain
                service.clearCache()
            }
        } label: {
            chainButtonLabel(chain: chain, isSelected: isSelected)
                .frame(width: 72, height: 62)
                .background(bgColor)
                .cornerRadius(HawalaTheme.Radius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                        .stroke(borderColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { h in hoveringChain = h ? chain.rawValue : nil }
        .animation(HawalaTheme.Animation.fast, value: isHover)
        .accessibilityLabel("\(chain.displayName) network")
        .accessibilityHint(isSelected ? "Currently selected" : "Tap to select \(chain.displayName)")
        .accessibilityIdentifier("swap_chain_\(chain.rawValue)")
    }
    
    private func chainButtonLabel(chain: DEXAggregatorService.SupportedChain, isSelected: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: chain.icon)
                .font(.system(size: 18))
                .foregroundColor(isSelected ? .white : .white.opacity(0.5))
            Text(chain.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isSelected ? .white : .white.opacity(0.4))
        }
    }
    
    // MARK: - Swap Input
    
    private var swapInputSection: some View {
        VStack(spacing: HawalaTheme.Spacing.lg) {
            // From Token
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                HawalaOverlaySectionHeader(icon: "arrow.down.circle", title: "From")
                
                HStack {
                    Menu {
                        ForEach(sampleTokens, id: \.0) { token in
                            Button(token.1) {
                                fromToken = token.0
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(getTokenSymbol(fromToken))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.3))
                        }
                        .padding(.horizontal, HawalaTheme.Spacing.md)
                        .padding(.vertical, HawalaTheme.Spacing.sm)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(HawalaTheme.Radius.sm)
                        .overlay(
                            RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    TextField("0.0", text: $amount)
                        .textFieldStyle(.plain)
                        .font(.clashGroteskMedium(size: 28))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .accessibilityLabel("Amount to swap")
                        .accessibilityHint("Enter amount of tokens to swap")
                        .accessibilityIdentifier("swap_amount_input")
                }
                .padding(HawalaTheme.Spacing.lg)
                .background(HawalaTheme.Colors.backgroundSecondary)
                .cornerRadius(HawalaTheme.Radius.lg)
                .overlay(
                    RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
            }
            
            // Swap direction button
            Button {
                swap(&fromToken, &toToken)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(hoveringSwapDirection ? .white : .white.opacity(0.4))
                    .frame(width: 36, height: 36)
                    .background(hoveringSwapDirection ? Color.white.opacity(0.10) : Color.white.opacity(0.06))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .onHover { h in hoveringSwapDirection = h }
            .animation(HawalaTheme.Animation.fast, value: hoveringSwapDirection)
            .accessibilityLabel("Swap token direction")
            .accessibilityHint("Swap from and to tokens")
            .accessibilityIdentifier("swap_direction_button")
            
            // To Token
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                HawalaOverlaySectionHeader(icon: "arrow.up.circle", title: "To")
                
                HStack {
                    Menu {
                        ForEach(sampleTokens, id: \.0) { token in
                            Button(token.1) {
                                toToken = token.0
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(getTokenSymbol(toToken))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.3))
                        }
                        .padding(.horizontal, HawalaTheme.Spacing.md)
                        .padding(.vertical, HawalaTheme.Spacing.sm)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(HawalaTheme.Radius.sm)
                        .overlay(
                            RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    if let best = service.currentQuotes?.bestQuote {
                        Text(best.formattedToAmount)
                            .font(.clashGroteskMedium(size: 28))
                            .foregroundColor(HawalaTheme.Colors.success)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    } else {
                        Text("0.0")
                            .font(.clashGroteskMedium(size: 28))
                            .foregroundColor(.white.opacity(0.15))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(HawalaTheme.Spacing.lg)
                .background(HawalaTheme.Colors.backgroundSecondary)
                .cornerRadius(HawalaTheme.Radius.lg)
                .overlay(
                    RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
            }
        }
    }
    
    private func getTokenSymbol(_ address: String) -> String {
        sampleTokens.first { $0.0 == address }?.1 ?? "Select"
    }
    
    // MARK: - Slippage
    
    private var slippageSection: some View {
        DisclosureGroup("Slippage: \(String(format: "%.1f", slippage))%", isExpanded: $showSlippageSettings) {
            VStack(spacing: HawalaTheme.Spacing.md) {
                HStack {
                    ForEach([0.1, 0.5, 1.0, 3.0], id: \.self) { value in
                        Button {
                            slippage = value
                        } label: {
                            Text("\(String(format: "%.1f", value))%")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, HawalaTheme.Spacing.md)
                                .padding(.vertical, HawalaTheme.Spacing.sm)
                                .background(slippage == value ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
                                .foregroundColor(slippage == value ? .white : .white.opacity(0.5))
                                .cornerRadius(HawalaTheme.Radius.sm)
                                .overlay(
                                    RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm)
                                        .stroke(slippage == value ? Color.white.opacity(0.15) : Color.white.opacity(0.06), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Slider(value: $slippage, in: 0.1...50.0, step: 0.1)
                    .help("Higher slippage increases success rate but may result in a worse price")
                
                HStack {
                    Text("Custom: \(String(format: "%.1f", slippage))%")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                    if slippage > 5.0 {
                        Text("\u{26a0}\u{fe0f} High slippage")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(HawalaTheme.Colors.warning)
                    }
                }
                
                // ROADMAP-07 E12: Zero-slippage warning
                if slippage < 0.1 {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(HawalaTheme.Colors.warning)
                        Text("Very low slippage will cause most swaps to fail. Consider at least 0.5%.")
                            .font(.system(size: 11))
                            .foregroundColor(HawalaTheme.Colors.warning)
                    }
                    .padding(HawalaTheme.Spacing.sm)
                    .background(HawalaTheme.Colors.warning.opacity(0.08))
                    .cornerRadius(HawalaTheme.Radius.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm)
                            .stroke(HawalaTheme.Colors.warning.opacity(0.2), lineWidth: 1)
                    )
                }
            }
            .padding(.top, 8)
        }
        .help("Maximum price impact you're willing to accept on this swap")
        .padding(HawalaTheme.Spacing.lg)
        .background(HawalaTheme.Colors.backgroundSecondary)
        .cornerRadius(HawalaTheme.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
    
    // MARK: - Transfer Tax Warning (ROADMAP-07 E11)
    
    @ViewBuilder
    private var transferTaxWarning: some View {
        let chainId = selectedChain.rawValue
        let fromTax = TransferTaxDetector.detectTax(address: fromToken, chainId: chainId)
        let toTax = TransferTaxDetector.detectTax(address: toToken, chainId: chainId)
        let fromSymbol = getTokenSymbol(fromToken)
        let fromTaxBySymbol = fromTax == nil ? TransferTaxDetector.detectTaxBySymbol(fromSymbol) : nil
        let toSymbol = getTokenSymbol(toToken)
        let toTaxBySymbol = toTax == nil ? TransferTaxDetector.detectTaxBySymbol(toSymbol) : nil
        
        let detectedFrom = fromTax ?? fromTaxBySymbol
        let detectedTo = toTax ?? toTaxBySymbol
        
        if let tax = detectedFrom ?? detectedTo {
            HStack(alignment: .top, spacing: HawalaTheme.Spacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(HawalaTheme.Colors.error)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Transfer Tax Detected")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(HawalaTheme.Colors.error)
                    
                    Text(TransferTaxDetector.warningMessage(for: tax))
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                    
                    if detectedFrom != nil && detectedTo != nil {
                        Text("Both tokens have transfer taxes — expect significant slippage.")
                            .font(.system(size: 11))
                            .foregroundColor(HawalaTheme.Colors.error.opacity(0.8))
                    }
                }
            }
            .padding(HawalaTheme.Spacing.lg)
            .background(HawalaTheme.Colors.error.opacity(0.08))
            .cornerRadius(HawalaTheme.Radius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg)
                    .stroke(HawalaTheme.Colors.error.opacity(0.25), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Warning: \(TransferTaxDetector.warningMessage(for: tax))")
        }
    }
    
    // MARK: - Honeypot Warning (ROADMAP-08 E9)
    
    @ViewBuilder
    private var honeypotWarning: some View {
        // Check both from and to tokens for honeypot risks
        let fromResult = honeypotDetector.cachedResult(for: fromToken, chainId: String(selectedChain.chainId))
        let toResult = honeypotDetector.cachedResult(for: toToken, chainId: String(selectedChain.chainId))
        
        let riskyResult = toResult?.riskLevel == .critical ? toResult :
                          (fromResult?.riskLevel == .critical ? fromResult :
                          (toResult?.riskLevel == .high ? toResult :
                          (fromResult?.riskLevel == .high ? fromResult : nil)))
        
        if let result = riskyResult, result.riskLevel >= .medium {
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
                HStack(alignment: .top, spacing: HawalaTheme.Spacing.md) {
                    Image(systemName: result.riskLevel >= .high ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(result.riskLevel >= .high ? HawalaTheme.Colors.error : HawalaTheme.Colors.warning)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.riskLevel >= .high ? "Honeypot Risk Detected" : "Token Risk Warning")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(result.riskLevel >= .high ? HawalaTheme.Colors.error : HawalaTheme.Colors.warning)
                        
                        if !result.warningMessage.isEmpty {
                            Text(result.warningMessage)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        
                        ForEach(result.warnings.prefix(3), id: \.self) { warning in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(HawalaTheme.Colors.error.opacity(0.6))
                                    .frame(width: 4, height: 4)
                                Text(warning)
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                        
                        if result.sellTax > 0 || result.buyTax > 0 {
                            HStack(spacing: HawalaTheme.Spacing.md) {
                                if result.buyTax > 0 {
                                    Text("Buy tax: \(String(format: "%.1f", result.buyTax))%")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(HawalaTheme.Colors.warning)
                                }
                                if result.sellTax > 0 {
                                    Text("Sell tax: \(String(format: "%.1f", result.sellTax))%")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(HawalaTheme.Colors.error)
                                }
                            }
                            .padding(.top, 2)
                        }
                    }
                }
            }
            .padding(HawalaTheme.Spacing.lg)
            .background((result.riskLevel >= .high ? HawalaTheme.Colors.error : HawalaTheme.Colors.warning).opacity(0.08))
            .cornerRadius(HawalaTheme.Radius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg)
                    .stroke((result.riskLevel >= .high ? HawalaTheme.Colors.error : HawalaTheme.Colors.warning).opacity(0.25), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Warning: \(result.warningMessage)")
        } else if honeypotDetector.isChecking {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Checking token security...")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Loading
    
    private var loadingSection: some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            ProgressView()
                .scaleEffect(0.9)
            Text("Fetching quotes from providers...")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(HawalaTheme.Spacing.xl)
        .background(HawalaTheme.Colors.backgroundSecondary)
        .cornerRadius(HawalaTheme.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
    
    // MARK: - Quotes
    
    private func quotesSection(_ quotes: DEXAggregatorService.AggregatedQuotes) -> some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            HStack {
                HawalaOverlaySectionHeader(icon: "list.bullet.rectangle", title: "Quotes (\(quotes.quotes.count))")
                
                Spacer()
                
                // ROADMAP-07 E9: Quote expiry countdown
                if quoteTimeRemaining > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text(formatDEXCountdown(quoteTimeRemaining))
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .foregroundColor(quoteTimeRemaining < 60 ? HawalaTheme.Colors.error : .white.opacity(0.4))
                } else if quoteTimeRemaining <= 0 && !service.isLoading {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                        Text("Expired")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(HawalaTheme.Colors.warning)
                }
                
                Button("Compare All") {
                    showQuoteComparison = true
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .buttonStyle(.plain)
            }
            
            ForEach(quotes.sortedByOutput.prefix(3)) { quote in
                quoteRow(quote, isBest: quote.id == quotes.bestQuote?.id)
            }
            
            if quotes.quotes.count > 3 {
                Button {
                    showQuoteComparison = true
                } label: {
                    Text("See \(quotes.quotes.count - 3) more quotes...")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func quoteRow(_ quote: DEXAggregatorService.SwapQuote, isBest: Bool) -> some View {
        let isSelected = selectedQuote?.id == quote.id
        let isHovering = hoveringQuoteRow == quote.id
        
        return Button {
            selectedQuote = quote
        } label: {
            HStack {
                Image(systemName: quote.provider.icon)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm, style: .continuous))
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: HawalaTheme.Spacing.sm) {
                        Text(quote.provider.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        if isBest {
                            Text("BEST")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.8)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(HawalaTheme.Colors.success.opacity(0.15))
                                .foregroundColor(HawalaTheme.Colors.success)
                                .cornerRadius(4)
                        }

                        Text(quote.riskLabel)
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(quote.riskColor.opacity(0.12))
                            .foregroundColor(quote.riskColor)
                            .cornerRadius(4)
                    }

                    Text(quote.provenanceSummary)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.35))

                    Text("Min receive: \(quote.formattedMinimumReceive)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.35))
                    
                    if let impact = quote.priceImpact {
                        let absImpact = abs(impact)
                        let impactColor: Color = absImpact > 5.0 ? HawalaTheme.Colors.error : (absImpact > 2.0 ? HawalaTheme.Colors.warning : .white.opacity(0.4))
                        HStack(spacing: 4) {
                            if absImpact > 2.0 {
                                Image(systemName: absImpact > 5.0 ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                                    .font(.system(size: 9))
                            }
                            Text("Impact: \(String(format: "%.2f", impact))%")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(impactColor)
                        .fontWeight(absImpact > 5.0 ? .bold : .regular)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(quote.formattedToAmount)
                        .font(.clashGroteskMedium(size: 15))
                        .foregroundColor(isBest ? HawalaTheme.Colors.success : .white)
                    
                    Text(quote.routeCountSummary)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.35))

                    if let gas = quote.gasCostUSD {
                        Text("Gas: $\(String(format: "%.2f", gas))")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.35))
                    }
                }
            }
            .padding(HawalaTheme.Spacing.lg)
            .background(isSelected ? Color.white.opacity(0.08) : (isHovering ? Color.white.opacity(0.04) : HawalaTheme.Colors.backgroundSecondary))
            .cornerRadius(HawalaTheme.Radius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg)
                    .stroke(isSelected ? Color.white.opacity(0.15) : Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in hoveringQuoteRow = h ? quote.id : nil }
        .animation(HawalaTheme.Animation.fast, value: isHovering)
    }
    
    // MARK: - Error
    
    private func errorSection(_ error: String) -> some View {
        HStack(spacing: HawalaTheme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(HawalaTheme.Colors.error)
            Text(error)
                .font(.system(size: 12))
                .foregroundColor(HawalaTheme.Colors.error)
        }
        .padding(HawalaTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HawalaTheme.Colors.error.opacity(0.08))
        .cornerRadius(HawalaTheme.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                .stroke(HawalaTheme.Colors.error.opacity(0.2), lineWidth: 1)
        )
    }

    private func approvalSection(for quote: DEXAggregatorService.SwapQuote) -> some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            HStack {
                HawalaOverlaySectionHeader(icon: "checkmark.shield", title: "Approval Review")

                Spacer()

                if approvalCompletedForQuoteID == quote.id {
                    Text("APPROVED")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(HawalaTheme.Colors.success.opacity(0.15))
                        .foregroundColor(HawalaTheme.Colors.success)
                        .cornerRadius(4)
                }
            }

            if isCheckingApproval {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Checking approval requirements...")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
            } else if let approvalStatus {
                if approvalStatus.needsApproval && approvalCompletedForQuoteID != quote.id {
                    VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                        approvalRow(label: "Spender", value: shortAddress(approvalStatus.spender))
                        approvalRow(label: "Approval Type", value: "Exact amount")
                        approvalRow(label: "Approval Amount", value: formatQuoteAmount(quote.fromAmount, decimals: quote.fromTokenDecimals, symbol: quote.fromTokenSymbol))
                        approvalRow(label: "Current Allowance", value: "Live allowance lookup pending")

                        Text("Hawala assumes an exact ERC-20 approval is required before this swap until live allowance reads are integrated for this flow.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.35))
                    }
                } else {
                    VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                        approvalRow(label: "Approval Status", value: "Ready to swap")
                        Text("This route can proceed without a separate token approval, or the approval was already completed in this session.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.35))
                    }
                }
            } else {
                Text("Select a quote to review token approval requirements.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
        .padding(HawalaTheme.Spacing.lg)
        .background(HawalaTheme.Colors.backgroundSecondary)
        .cornerRadius(HawalaTheme.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func approvalRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
            Spacer()
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.trailing)
        }
    }
    
    // MARK: - Actions
    
    private var actionButtons: some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            Button {
                Task {
                    await fetchQuotes()
                }
            } label: {
                HStack(spacing: HawalaTheme.Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Get Live Quotes")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canGetQuotes ? (hoveringGetQuotes ? Color.white.opacity(0.18) : Color.white.opacity(0.12)) : Color.white.opacity(0.04))
                .foregroundColor(canGetQuotes ? .white : .white.opacity(0.3))
                .cornerRadius(HawalaTheme.Radius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                        .stroke(Color.white.opacity(canGetQuotes ? 0.1 : 0.04), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canGetQuotes || service.isLoading)
            .onHover { h in hoveringGetQuotes = h }
            .animation(HawalaTheme.Animation.fast, value: hoveringGetQuotes)
            
            if let quote = selectedQuote, requiresApproval(for: quote) {
                Button {
                    Task {
                        await executeApprovalIfNeeded(for: quote)
                    }
                } label: {
                    HStack(spacing: HawalaTheme.Spacing.sm) {
                        if isExecutingApproval || isCheckingApproval {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "checkmark.shield")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        Text(isExecutingApproval ? "Approving..." : (isCheckingApproval ? "Checking Approval..." : "Approve Token First"))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(HawalaTheme.Colors.warning.opacity(0.15))
                    .foregroundColor(HawalaTheme.Colors.warning)
                    .cornerRadius(HawalaTheme.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                            .stroke(HawalaTheme.Colors.warning.opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isExecutingApproval || isCheckingApproval)
            }

            if selectedQuote != nil {
                Button {
                    Task {
                        await executeSwap()
                    }
                } label: {
                    HStack(spacing: HawalaTheme.Spacing.sm) {
                        if isExecutingSwap {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "arrow.right.arrow.left")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        Text(isExecutingSwap ? "Executing..." : "Execute Swap")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(HawalaTheme.Colors.success.opacity(0.15))
                    .foregroundColor(HawalaTheme.Colors.success)
                    .cornerRadius(HawalaTheme.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                            .stroke(HawalaTheme.Colors.success.opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isExecutingSwap || isCheckingApproval || isExecutingApproval || !canExecuteSelectedQuote)
            }
        }
    }
    
    private var canGetQuotes: Bool {
        !fromToken.isEmpty && !toToken.isEmpty && !amount.isEmpty && fromToken != toToken
    }
    
    // MARK: - Actions
    
    private func fetchQuotes() async {
        selectedQuote = nil
        approvalStatus = nil
        approvalCompletedForQuoteID = nil

        do {
            _ = try await service.getQuotes(
                chain: selectedChain,
                fromToken: fromToken,
                toToken: toToken,
                amount: convertToWei(amount),
                slippage: slippage,
                fromAddress: walletAddress ?? "0x0000000000000000000000000000000000000000"
            )
            
            // ROADMAP-07 E9: Start countdown timer from quote expiry
            if let expiresAt = service.currentQuotes?.bestQuote?.expiresAt {
                startDEXQuoteTimer(expiresAt: expiresAt)
            }
        } catch {
            service.error = error.localizedDescription
        }
    }
    
    // MARK: - ROADMAP-07 E9/E10: Quote Expiry Timer
    
    private func startDEXQuoteTimer(expiresAt: Date) {
        stopDEXQuoteTimer()
        let remaining = Int(expiresAt.timeIntervalSinceNow)
        quoteTimeRemaining = max(0, remaining)
        
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor [self] in
                let r = quoteTimeRemaining - 1
                if r <= 0 {
                    quoteTimeRemaining = 0
                    stopDEXQuoteTimer()
                    // ROADMAP-07 E10: Auto-refresh when timer hits 0
                    await fetchQuotes()
                } else {
                    quoteTimeRemaining = r
                }
            }
        }
        quoteExpiryTimer = timer
    }
    
    private func stopDEXQuoteTimer() {
        quoteExpiryTimer?.invalidate()
        quoteExpiryTimer = nil
    }
    
    private func formatDEXCountdown(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
    
    private func executeSwap() async {
        guard let quote = selectedQuote else { return }

        guard canExecuteSelectedQuote else {
            service.error = "Complete the token approval step before executing this swap."
            return
        }
        
        // ROADMAP-20: Track swap initiated
        AnalyticsService.shared.track(AnalyticsService.EventName.swapInitiated, properties: [
            "from": fromToken, "to": toToken
        ])
        
        // Check biometric authentication if enabled
        if BiometricAuthHelper.shouldRequireBiometric(settingEnabled: biometricForSends) {
            let result = await BiometricAuthHelper.authenticate(
                reason: "Authenticate to execute swap"
            )
            switch result {
            case .success:
                await performSwapExecution(quote: quote)
            case .cancelled:
                #if DEBUG
                print("[DEXAggregator] Biometric cancelled by user")
                #endif
                return
            case .failed(let message):
                service.error = "Authentication failed: \(message)"
                return
            case .notAvailable:
                // Biometric not available, proceed anyway
                await performSwapExecution(quote: quote)
            }
        } else {
            await performSwapExecution(quote: quote)
        }
    }
    
    private func performSwapExecution(quote: DEXAggregatorService.SwapQuote) async {
        isExecutingSwap = true
        defer { isExecutingSwap = false }
        
        // Ensure we have wallet credentials
        guard let privateKey = privateKey, let fromAddress = walletAddress else {
            service.error = "No wallet connected. Please connect your wallet first."
            return
        }
        
        do {
            let hash = try await service.executeSwap(
                quote: quote,
                privateKey: privateKey,
                fromAddress: fromAddress
            )
            txHash = hash
            showTxSuccess = true
            
            // ROADMAP-20: Track swap completed
            AnalyticsService.shared.track(AnalyticsService.EventName.swapCompleted, properties: [
                "from": fromToken, "to": toToken
            ])
        } catch {
            // ROADMAP-20: Track swap failed
            AnalyticsService.shared.track(AnalyticsService.EventName.swapFailed, properties: [
                "error": error.localizedDescription.prefix(100).description
            ])
            service.error = error.localizedDescription
        }
    }

    private func refreshApprovalStatus() async {
        approvalStatus = nil
        approvalCompletedForQuoteID = nil

        guard let quote = selectedQuote,
              let fromAddress = walletAddress else {
            return
        }

        isCheckingApproval = true
        defer { isCheckingApproval = false }

        do {
            approvalStatus = try await service.checkApproval(
                chain: quote.chain,
                token: quote.fromToken,
                wallet: fromAddress,
                provider: quote.provider,
                amount: quote.fromAmount
            )
        } catch {
            service.error = error.localizedDescription
        }
    }

    private func executeApprovalIfNeeded(for quote: DEXAggregatorService.SwapQuote) async {
        guard let approvalStatus,
              approvalStatus.needsApproval,
              let privateKey = privateKey,
              let fromAddress = walletAddress else {
            return
        }

        if BiometricAuthHelper.shouldRequireBiometric(settingEnabled: biometricForSends) {
            let result = await BiometricAuthHelper.authenticate(reason: "Authenticate to approve token spending")
            switch result {
            case .success, .notAvailable:
                break
            case .cancelled:
                return
            case .failed(let message):
                service.error = "Authentication failed: \(message)"
                return
            }
        }

        isExecutingApproval = true
        defer { isExecutingApproval = false }

        do {
            _ = try await service.executeApproval(
                approval: approvalStatus,
                chain: quote.chain,
                privateKey: privateKey,
                fromAddress: fromAddress,
                mode: .exact(approvalStatus.requiredAllowance)
            )
            approvalCompletedForQuoteID = quote.id
            service.error = nil
        } catch {
            service.error = error.localizedDescription
        }
    }

    private func requiresApproval(for quote: DEXAggregatorService.SwapQuote) -> Bool {
        approvalStatus?.needsApproval == true && approvalCompletedForQuoteID != quote.id
    }

    private var canExecuteSelectedQuote: Bool {
        guard let quote = selectedQuote else { return false }
        return !requiresApproval(for: quote)
    }

    private func shortAddress(_ address: String) -> String {
        guard address.count > 10 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }

    private func formatQuoteAmount(_ rawAmount: String, decimals: Int, symbol: String) -> String {
        guard let value = Decimal(string: rawAmount) else { return "0 \(symbol)" }
        let divisor = pow(Decimal(10), decimals)
        let formatted = value / divisor
        return "\(String(format: "%.6f", NSDecimalNumber(decimal: formatted).doubleValue)) \(symbol)"
    }
    
    private func convertToWei(_ amount: String) -> String {
        guard let value = Decimal(string: amount) else { return "0" }
        let wei = value * Decimal(1_000_000_000_000_000_000)
        return "\(wei)"
    }
}

// MARK: - Quote Comparison Sheet

struct QuoteComparisonSheet: View {
    let quotes: DEXAggregatorService.AggregatedQuotes
    @Binding var selectedQuote: DEXAggregatorService.SwapQuote?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        Text("Spread")
                        Spacer()
                        Text("\(String(format: "%.2f", quotes.spreadPercent))%")
                            .foregroundStyle(quotes.spreadPercent > 1 ? .red : .green)
                    }
                    
                    HStack {
                        Text("Quotes")
                        Spacer()
                        Text("\(quotes.quotes.count) providers")
                    }
                } header: {
                    Text("Summary")
                }
                
                Section {
                    ForEach(quotes.sortedByOutput) { quote in
                        Button {
                            selectedQuote = quote
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: quote.provider.icon)
                                    .foregroundStyle(quote.provider.color)
                                
                                VStack(alignment: .leading) {
                                    Text(quote.provider.displayName)
                                        .fontWeight(.medium)

                                    Text(quote.provenanceSummary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Text("Min receive: \(quote.formattedMinimumReceive)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing) {
                                    Text(quote.formattedToAmount)
                                        .fontWeight(.semibold)

                                    Text(quote.riskLabel)
                                        .font(.caption2)
                                        .foregroundStyle(quote.riskColor)
                                    
                                    if let gas = quote.gasCostUSD {
                                        Text("$\(String(format: "%.2f", gas)) gas")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                if selectedQuote?.id == quote.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("All Quotes")
                }
            }
            .navigationTitle("Compare Quotes")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private extension DEXAggregatorService.SwapQuote {
    var formattedMinimumReceive: String {
        formatAmount(toAmountMin, decimals: toTokenDecimals, symbol: toTokenSymbol)
    }

    var routeCountSummary: String {
        let count = routes.count
        if count == 0 {
            return "route data missing"
        }
        return count == 1 ? "1 route" : "\(count) routes"
    }

    var provenanceSummary: String {
        guard let firstRoute = routes.first else {
            return "Route source unavailable"
        }

        let percentage = Int(firstRoute.percentage.rounded())
        let protocolName = firstRoute.protocol_.isEmpty ? provider.displayName : firstRoute.protocol_
        let hopCount = max(firstRoute.path.count - 1, 1)
        return "\(percentage)% via \(protocolName) • \(hopCount) hop\(hopCount == 1 ? "" : "s")"
    }

    var riskLabel: String {
        switch riskLevel {
        case .low:
            return "Low Risk"
        case .medium:
            return "Review"
        case .high:
            return "High Risk"
        }
    }

    var riskColor: Color {
        switch riskLevel {
        case .low:
            return .green
        case .medium:
            return .orange
        case .high:
            return .red
        }
    }

    private var riskLevel: QuoteRiskLevel {
        let absoluteImpact = abs(priceImpact ?? 0)

        if transaction == nil || routes.isEmpty || absoluteImpact > 5 {
            return .high
        }

        if routes.count > 1 || absoluteImpact > 2 {
            return .medium
        }

        return .low
    }

    private func formatAmount(_ amount: String, decimals: Int, symbol: String) -> String {
        guard let value = Decimal(string: amount) else {
            return "0 \(symbol)"
        }

        let divisor = pow(Decimal(10), decimals)
        let formatted = value / divisor
        return "\(String(format: "%.6f", NSDecimalNumber(decimal: formatted).doubleValue)) \(symbol)"
    }

    private enum QuoteRiskLevel {
        case low
        case medium
        case high
    }
}

// MARK: - Preview

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    NavigationView {
        DEXAggregatorView()
    }
}
#endif
#endif
#endif
