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
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
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
                
                if let error = service.error {
                    errorSection(error)
                }
                
                actionButtons
            }
            .padding()
        }
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
        VStack(spacing: 8) {
            // Beta warning banner
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Preview Feature")
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.15))
            .cornerRadius(8)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Warning: Preview Feature. DEX aggregation is in preview and uses simulated transactions.")
            
            Text("DEX aggregation is in preview. Swap execution is simulated and does not use real funds.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
            
            Text("Compare prices across DEX providers")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Chain Selector
    
    private var chainSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Network")
                .font(.headline)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(DEXAggregatorService.SupportedChain.allCases.filter { chain in
                        // Only show chains with DEX support
                        service.getProviders(for: chain).count > 0
                    }) { chain in
                        chainButton(chain)
                    }
                }
            }
        }
    }
    
    private func chainButton(_ chain: DEXAggregatorService.SupportedChain) -> some View {
        Button {
            selectedChain = chain
            service.clearCache()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: chain.icon)
                    .font(.title2)
                Text(chain.displayName)
                    .font(.caption)
            }
            .frame(width: 70, height: 60)
            .background(selectedChain == chain ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selectedChain == chain ? Color.blue : Color.clear, lineWidth: 2)
            )
            .accessibilityLabel("\(chain.displayName) network")
            .accessibilityHint(selectedChain == chain ? "Currently selected" : "Tap to select \(chain.displayName)")
            .accessibilityIdentifier("swap_chain_\(chain.rawValue)")
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Swap Input
    
    private var swapInputSection: some View {
        VStack(spacing: 16) {
            // From Token
            VStack(alignment: .leading, spacing: 8) {
                Text("From")
                    .font(.headline)
                
                HStack {
                    Menu {
                        ForEach(sampleTokens, id: \.0) { token in
                            Button(token.1) {
                                fromToken = token.0
                            }
                        }
                    } label: {
                        HStack {
                            Text(getTokenSymbol(fromToken))
                                .fontWeight(.medium)
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    TextField("0.0", text: $amount)
                        .textFieldStyle(.plain)
                        .font(.title2)
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .accessibilityLabel("Amount to swap")
                        .accessibilityHint("Enter amount of tokens to swap")
                        .accessibilityIdentifier("swap_amount_input")
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
            }
            
            // Swap direction button
            Button {
                swap(&fromToken, &toToken)
            } label: {
                Image(systemName: "arrow.up.arrow.down.circle.fill")
                    .font(.title)
                    .foregroundStyle(.blue)
            }
            .accessibilityLabel("Swap token direction")
            .accessibilityHint("Swap from and to tokens")
            .accessibilityIdentifier("swap_direction_button")
            
            // To Token
            VStack(alignment: .leading, spacing: 8) {
                Text("To")
                    .font(.headline)
                
                HStack {
                    Menu {
                        ForEach(sampleTokens, id: \.0) { token in
                            Button(token.1) {
                                toToken = token.0
                            }
                        }
                    } label: {
                        HStack {
                            Text(getTokenSymbol(toToken))
                                .fontWeight(.medium)
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    if let best = service.currentQuotes?.bestQuote {
                        Text(best.formattedToAmount)
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    } else {
                        Text("0.0")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
            }
        }
    }
    
    private func getTokenSymbol(_ address: String) -> String {
        sampleTokens.first { $0.0 == address }?.1 ?? "Select"
    }
    
    // MARK: - Slippage
    
    private var slippageSection: some View {
        DisclosureGroup("Slippage: \(String(format: "%.1f", slippage))%", isExpanded: $showSlippageSettings) {
            VStack(spacing: 12) {
                HStack {
                    ForEach([0.1, 0.5, 1.0, 3.0], id: \.self) { value in
                        Button {
                            slippage = value
                        } label: {
                            Text("\(String(format: "%.1f", value))%")
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(slippage == value ? Color.blue : Color.gray.opacity(0.1))
                                .foregroundColor(slippage == value ? .white : .primary)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // ROADMAP-07: Extended slippage range up to 50% for exotic pairs
                Slider(value: $slippage, in: 0.1...50.0, step: 0.1)
                    .help("Higher slippage increases success rate but may result in a worse price")
                
                HStack {
                    Text("Custom: \(String(format: "%.1f", slippage))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if slippage > 5.0 {
                        Text("\u{26a0}\u{fe0f} High slippage")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                // ROADMAP-07 E12: Zero-slippage warning
                if slippage < 0.1 {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Very low slippage will cause most swaps to fail. Consider at least 0.5%.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding(.top, 8)
        }
        .help("Maximum price impact you're willing to accept on this swap")
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Transfer Tax Warning (ROADMAP-07 E11)
    
    @ViewBuilder
    private var transferTaxWarning: some View {
        let chainId = selectedChain.rawValue
        let fromTax = TransferTaxDetector.detectTax(address: fromToken, chainId: chainId)
        let toTax = TransferTaxDetector.detectTax(address: toToken, chainId: chainId)
        // Also check by symbol as fallback
        let fromSymbol = getTokenSymbol(fromToken)
        let fromTaxBySymbol = fromTax == nil ? TransferTaxDetector.detectTaxBySymbol(fromSymbol) : nil
        let toSymbol = getTokenSymbol(toToken)
        let toTaxBySymbol = toTax == nil ? TransferTaxDetector.detectTaxBySymbol(toSymbol) : nil
        
        let detectedFrom = fromTax ?? fromTaxBySymbol
        let detectedTo = toTax ?? toTaxBySymbol
        
        if let tax = detectedFrom ?? detectedTo {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Transfer Tax Detected")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                    
                    Text(TransferTaxDetector.warningMessage(for: tax))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if detectedFrom != nil && detectedTo != nil {
                        Text("Both tokens have transfer taxes — expect significant slippage.")
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.8))
                    }
                }
            }
            .padding()
            .background(Color.red.opacity(0.08))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
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
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: result.riskLevel >= .high ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(result.riskLevel >= .high ? .red : .orange)
                        .font(.title3)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.riskLevel >= .high ? "Honeypot Risk Detected" : "Token Risk Warning")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(result.riskLevel >= .high ? .red : .orange)
                        
                        if !result.warningMessage.isEmpty {
                            Text(result.warningMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        // Show specific warnings
                        ForEach(result.warnings.prefix(3), id: \.self) { warning in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.red.opacity(0.6))
                                    .frame(width: 4, height: 4)
                                Text(warning)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        if result.sellTax > 0 || result.buyTax > 0 {
                            HStack(spacing: 12) {
                                if result.buyTax > 0 {
                                    Text("Buy tax: \(String(format: "%.1f", result.buyTax))%")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.orange)
                                }
                                if result.sellTax > 0 {
                                    Text("Sell tax: \(String(format: "%.1f", result.sellTax))%")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.red)
                                }
                            }
                            .padding(.top, 2)
                        }
                    }
                }
            }
            .padding()
            .background(result.riskLevel >= .high ? Color.red.opacity(0.08) : Color.orange.opacity(0.08))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(result.riskLevel >= .high ? Color.red.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Warning: \(result.warningMessage)")
        } else if honeypotDetector.isChecking {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Checking token security...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Loading
    
    private var loadingSection: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Fetching quotes from providers...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Quotes
    
    private func quotesSection(_ quotes: DEXAggregatorService.AggregatedQuotes) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Available Quotes (\(quotes.quotes.count))")
                    .font(.headline)
                
                Spacer()
                
                // ROADMAP-07 E9: Quote expiry countdown
                if quoteTimeRemaining > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption)
                        Text(formatDEXCountdown(quoteTimeRemaining))
                            .font(.caption.monospacedDigit())
                    }
                    .foregroundColor(quoteTimeRemaining < 60 ? .red : .secondary)
                } else if quoteTimeRemaining <= 0 && !service.isLoading {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("Expired")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                Button("Compare All") {
                    showQuoteComparison = true
                }
                .font(.caption)
            }
            
            ForEach(quotes.sortedByOutput.prefix(3)) { quote in
                quoteRow(quote, isBest: quote.id == quotes.bestQuote?.id)
            }
            
            if quotes.quotes.count > 3 {
                Button {
                    showQuoteComparison = true
                } label: {
                    Text("See \(quotes.quotes.count - 3) more quotes...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    private func quoteRow(_ quote: DEXAggregatorService.SwapQuote, isBest: Bool) -> some View {
        Button {
            selectedQuote = quote
        } label: {
            HStack {
                Image(systemName: quote.provider.icon)
                    .foregroundStyle(quote.provider.color)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(quote.provider.displayName)
                            .fontWeight(.medium)
                        if isBest {
                            Text("BEST")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                    }
                    
                    if let impact = quote.priceImpact {
                        // ROADMAP-07 E6: Color-coded price impact thresholds
                        let absImpact = abs(impact)
                        let impactColor: Color = absImpact > 5.0 ? .red : (absImpact > 2.0 ? .orange : .secondary)
                        HStack(spacing: 4) {
                            if absImpact > 2.0 {
                                Image(systemName: absImpact > 5.0 ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                                    .font(.caption2)
                            }
                            Text("Impact: \(String(format: "%.2f", impact))%")
                                .font(.caption)
                        }
                        .foregroundStyle(impactColor)
                        .fontWeight(absImpact > 5.0 ? .bold : .regular)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(quote.formattedToAmount)
                        .fontWeight(.semibold)
                        .foregroundStyle(isBest ? .green : .primary)
                    
                    if let gas = quote.gasCostUSD {
                        Text("Gas: $\(String(format: "%.2f", gas))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(selectedQuote?.id == quote.id ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selectedQuote?.id == quote.id ? Color.blue : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Error
    
    private func errorSection(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Actions
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    await fetchQuotes()
                }
            } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text("Get Quotes")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(canGetQuotes ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(!canGetQuotes || service.isLoading)
            
            if selectedQuote != nil {
                Button {
                    Task {
                        await executeSwap()
                    }
                } label: {
                    HStack {
                        if isExecutingSwap {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.right.arrow.left")
                        }
                        Text(isExecutingSwap ? "Executing..." : "Execute Swap")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isExecutingSwap)
            }
        }
    }
    
    private var canGetQuotes: Bool {
        !fromToken.isEmpty && !toToken.isEmpty && !amount.isEmpty && fromToken != toToken
    }
    
    // MARK: - Actions
    
    private func fetchQuotes() async {
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
                                    
                                    if let routes = quote.routes.first {
                                        Text("\(Int(routes.percentage))% via \(routes.protocol_)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing) {
                                    Text(quote.formattedToAmount)
                                        .fontWeight(.semibold)
                                    
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
