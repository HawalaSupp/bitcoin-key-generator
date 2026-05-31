import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

enum BridgeRiskLevel {
    case low
    case review
    case high

    var title: String {
        switch self {
        case .low:
            return "Low Risk"
        case .review:
            return "Review"
        case .high:
            return "High Risk"
        }
    }

    var color: Color {
        switch self {
        case .low:
            return HawalaTheme.Colors.success
        case .review:
            return HawalaTheme.Colors.warning
        case .high:
            return HawalaTheme.Colors.error
        }
    }
}

/// Cross-chain bridge view for transferring tokens between networks
struct BridgeView: View {
    @StateObject private var bridgeService = BridgeService.shared
    @State private var sourceChain: BridgeService.SupportedChain = .ethereum
    @State private var destinationChain: BridgeService.SupportedChain = .arbitrum
    @State private var selectedToken: String = "ETH"
    @State private var amount: String = ""
    @State private var slippage: Double = 0.5
    @State private var showQuotes = false
    @State private var showSettings = false
    @State private var showActiveTransfers = false
    @State private var copiedSupportSummary = false
    @State private var selectedQuote: BridgeService.BridgeQuote?
    @State private var confirmBridge = false
    /// ROADMAP-07 E7: User must confirm destination chain before bridging
    @State private var destinationConfirmed = false
    /// ROADMAP-07 E9/E10: Quote expiry countdown
    @State private var quoteTimeRemaining: Int = 0
    @State private var quoteExpiryTimer: Timer?
    
    /// Optional wallet keys for executing bridges
    var keys: AllKeys?
    
    /// Get the wallet address for the source chain
    private var walletAddress: String? {
        guard let keys = keys else { return nil }
        switch sourceChain {
        // All EVM chains use the same Ethereum address
        case .ethereum, .bsc, .polygon, .arbitrum, .optimism, .avalanche, .base, .fantom:
            return keys.ethereum.address
        case .solana:
            return keys.solana.publicKeyBase58
        }
    }
    
    /// Get the private key for the source chain
    private var privateKey: String? {
        guard let keys = keys else { return nil }
        switch sourceChain {
        // All EVM chains use the same Ethereum private key
        case .ethereum, .bsc, .polygon, .arbitrum, .optimism, .avalanche, .base, .fantom:
            return keys.ethereum.privateHex
        case .solana:
            return keys.solana.privateKeyBase58
        }
    }
    
    private let tokens = ["ETH", "USDC", "USDT", "DAI", "WBTC"]
    
    // MARK: - Beta Warning Banner
    
    private var betaWarningBanner: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
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
            .accessibilityLabel("Warning: Preview Feature. Cross-chain bridging only shows live routes when the bridge backend is available.")
            
            Text("Cross-chain bridging is in preview. Hawala now requires live bridge routes and will show no quotes when the bridge backend or provider configuration is unavailable.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Beta warning at top
                betaWarningBanner
                
                // Header with active transfers
                headerSection
                
                // Source chain selection
                sourceSection
                
                // Swap chains button
                swapChainsButton
                
                // Destination chain selection
                destinationSection
                
                // Amount input
                amountSection
                
                // ROADMAP-07 E12: Zero-slippage warning
                if slippage < 0.1 {
                    zeroSlippageWarning
                }
                
                // Quote preview or button
                if let quotes = bridgeService.currentQuotes, showQuotes {
                    quotesSection(quotes: quotes)
                } else {
                    getQuotesButton
                }

                if let error = bridgeService.error {
                    errorSection(error)
                }
                
                // Active transfers section
                if showActiveTransfers {
                    if !bridgeService.activeTransfers.isEmpty {
                        activeTransfersSection
                    }

                    if !bridgeService.recentTransfers.isEmpty {
                        recentTransfersSection
                    }
                }
            }
            .padding(HawalaTheme.Spacing.xl)
        }
        .background(HawalaTheme.Colors.background)
        .navigationTitle("Bridge")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gearshape")
                }
            }
            ToolbarItem(placement: .automatic) {
                if !bridgeService.activeTransfers.isEmpty || !bridgeService.recentTransfers.isEmpty {
                    Button(action: { showActiveTransfers.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("\(bridgeService.activeTransfers.count + bridgeService.recentTransfers.count)")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
        .alert("Confirm Bridge", isPresented: $confirmBridge) {
            Button("Cancel", role: .cancel) {}
            Button("Bridge") {
                Task { await executeBridge() }
            }
        } message: {
            if let quote = selectedQuote {
                Text("Bridge \(quote.formattedAmountIn) \(quote.tokenSymbol) from \(quote.sourceChain.displayName) to \(quote.destinationChain.displayName) via \(quote.provider.displayName)?")
            }
        }
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Cross-Chain Bridge")
                    .font(.clashGroteskBold(size: 18))
                    .foregroundColor(.white)
                Spacer()
            }
            
            Text("Transfer tokens between blockchains securely")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
            HawalaOverlaySectionHeader(icon: "arrow.down.circle", title: "From")
            
            HStack {
                chainPicker(selection: $sourceChain, label: "Source")
                
                Spacer()
                
                tokenPicker
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
    
    @State private var hoveringSwapChains = false
    
    private var swapChainsButton: some View {
        Button(action: swapChains) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 36, height: 36)
                .background(hoveringSwapChains ? Color.white.opacity(0.08) : Color.white.opacity(0.04))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { h in hoveringSwapChains = h }
        .animation(HawalaTheme.Animation.fast, value: hoveringSwapChains)
        .accessibilityLabel("Swap chains")
        .accessibilityHint("Swap source and destination chains")
        .accessibilityIdentifier("bridge_swap_chains_button")
    }
    
    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
            HawalaOverlaySectionHeader(icon: "arrow.up.circle", title: "To")
            
            chainPicker(selection: $destinationChain, label: "Destination")
                .padding(HawalaTheme.Spacing.lg)
                .background(HawalaTheme.Colors.backgroundSecondary)
                .cornerRadius(HawalaTheme.Radius.lg)
                .overlay(
                    RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        }
    }
    
    private func chainPicker(selection: Binding<BridgeService.SupportedChain>, label: String) -> some View {
        Menu {
            ForEach(BridgeService.SupportedChain.allCases) { chain in
                Button(action: { selection.wrappedValue = chain }) {
                    HStack {
                        Image(systemName: chain.icon)
                        Text(chain.displayName)
                        if selection.wrappedValue == chain {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selection.wrappedValue.icon)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.5))
                Text(selection.wrappedValue.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
    }
    
    private var tokenPicker: some View {
        Menu {
            ForEach(tokens, id: \.self) { token in
                Button(action: { selectedToken = token }) {
                    HStack {
                        Text(token)
                        if selectedToken == token {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack {
                Text(selectedToken)
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06))
            .cornerRadius(HawalaTheme.Radius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }
    
    private var amountSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
            HawalaOverlaySectionHeader(icon: "number", title: "Amount")
            
            HStack {
                TextField("0.0", text: $amount)
                    .textFieldStyle(.plain)
                    .font(.clashGroteskMedium(size: 28))
                    .foregroundColor(.white)
                    .accessibilityLabel("Bridge amount")
                    .accessibilityHint("Enter amount to bridge")
                    .accessibilityIdentifier("bridge_amount_input")
                
                Spacer()
                
                Button("MAX") {
                    Task {
                        await fetchMaxBalance()
                    }
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
                .accessibilityLabel("Use maximum balance")
                .accessibilityHint("Set amount to your full balance")
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
    
    @State private var hoveringGetQuotes = false
    
    private var getQuotesButton: some View {
        Button(action: fetchQuotes) {
            HStack(spacing: HawalaTheme.Spacing.sm) {
                if bridgeService.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                } else {
                    Text("Get Live Bridge Quotes")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isValidInput ? (hoveringGetQuotes ? Color.white.opacity(0.18) : Color.white.opacity(0.12)) : Color.white.opacity(0.04))
            .foregroundColor(isValidInput ? .white : .white.opacity(0.3))
            .cornerRadius(HawalaTheme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                    .stroke(Color.white.opacity(isValidInput ? 0.1 : 0.04), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isValidInput || bridgeService.isLoading)
        .onHover { h in hoveringGetQuotes = h }
        .animation(HawalaTheme.Animation.fast, value: hoveringGetQuotes)
        .accessibilityLabel("Get bridge quotes")
        .accessibilityHint("Fetch quotes from bridge providers")
        .accessibilityIdentifier("bridge_get_quotes_button")
    }

    private func errorSection(_ error: String) -> some View {
        HStack(alignment: .top, spacing: HawalaTheme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(HawalaTheme.Colors.error)
            Text(error)
                .font(.system(size: 12))
                .foregroundColor(HawalaTheme.Colors.error)
            Spacer()
        }
        .padding(HawalaTheme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(HawalaTheme.Colors.error.opacity(0.08))
        .cornerRadius(HawalaTheme.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                .stroke(HawalaTheme.Colors.error.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func quotesSection(quotes: BridgeService.AggregatedQuotes) -> some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            HStack {
                HawalaOverlaySectionHeader(icon: "list.bullet.rectangle", title: "Available Routes")
                Spacer()
                
                // ROADMAP-07 E9: Quote expiry countdown
                if quoteTimeRemaining > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text(formatCountdown(quoteTimeRemaining))
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .foregroundColor(quoteTimeRemaining < 60 ? HawalaTheme.Colors.error : .white.opacity(0.4))
                    .accessibilityLabel("Quote expires in \(quoteTimeRemaining) seconds")
                }
                
                Button(action: { stopQuoteTimer(); showQuotes = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }

            routeSummarySection(quotes)
            
            if let best = quotes.bestQuote {
                QuoteCard(quote: best, label: "Best Rate", isSelected: selectedQuote?.id == best.id, riskLevel: riskLevel(for: best))
                    .onTapGesture { selectedQuote = best }
            }
            
            if let fastest = quotes.fastestQuote, fastest.id != quotes.bestQuote?.id {
                QuoteCard(quote: fastest, label: "Fastest", isSelected: selectedQuote?.id == fastest.id, riskLevel: riskLevel(for: fastest))
                    .onTapGesture { selectedQuote = fastest }
            }
            
            if let cheapest = quotes.cheapestQuote,
               cheapest.id != quotes.bestQuote?.id,
               cheapest.id != quotes.fastestQuote?.id {
                QuoteCard(quote: cheapest, label: "Lowest Fee", isSelected: selectedQuote?.id == cheapest.id, riskLevel: riskLevel(for: cheapest))
                    .onTapGesture { selectedQuote = cheapest }
            }

            if let selectedQuote {
                selectedRouteReviewSection(selectedQuote)
            }
            
            // ROADMAP-07 E7: Destination chain confirmation checkbox
            Toggle(isOn: $destinationConfirmed) {
                HStack(spacing: 6) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                    Text("I confirm I am bridging to **\(destinationChain.displayName)**")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .toggleStyle(.checkbox)
            .accessibilityLabel("Confirm destination chain is \(destinationChain.displayName)")
            .accessibilityIdentifier("bridge_destination_confirm_toggle")
            
            // ROADMAP-07 E9: Expired quote warning + auto-refresh
            if quoteTimeRemaining <= 0 && showQuotes {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(HawalaTheme.Colors.warning)
                    Text("Quote expired")
                        .font(.system(size: 11))
                        .foregroundColor(HawalaTheme.Colors.warning)
                    Spacer()
                    Button("Refresh") {
                        fetchQuotes()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .buttonStyle(.plain)
                }
                .padding(HawalaTheme.Spacing.sm)
                .background(HawalaTheme.Colors.warning.opacity(0.08))
                .cornerRadius(HawalaTheme.Radius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm)
                        .stroke(HawalaTheme.Colors.warning.opacity(0.2), lineWidth: 1)
                )
            }
            
            // Bridge button
            Button(action: { confirmBridge = true }) {
                HStack(spacing: HawalaTheme.Spacing.sm) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Bridge \(selectedQuote?.tokenSymbol ?? selectedToken)")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canBridge ? HawalaTheme.Colors.success.opacity(0.15) : Color.white.opacity(0.04))
                .foregroundColor(canBridge ? HawalaTheme.Colors.success : .white.opacity(0.3))
                .cornerRadius(HawalaTheme.Radius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                        .stroke(canBridge ? HawalaTheme.Colors.success.opacity(0.25) : Color.white.opacity(0.04), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canBridge)
        }
        .padding(HawalaTheme.Spacing.lg)
        .background(HawalaTheme.Colors.backgroundSecondary)
        .cornerRadius(HawalaTheme.Radius.xl)
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.xl)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func routeSummarySection(_ quotes: BridgeService.AggregatedQuotes) -> some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
            HStack {
                Label("Live Rust bridge routing", systemImage: "checkmark.shield")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(HawalaTheme.Colors.success)
                Spacer()
                Text("\(quotes.quotes.count) routes")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }

            HStack(spacing: HawalaTheme.Spacing.sm) {
                metricChip(title: "Best Output", value: quotes.bestQuote?.provider.displayName ?? "N/A")
                metricChip(title: "Fastest", value: quotes.fastestQuote.map { "\($0.provider.displayName) ~\($0.estimatedTimeMinutes)m" } ?? "N/A")
                metricChip(title: "Lowest Fee", value: quotes.cheapestQuote.map { "$\(String(format: "%.2f", $0.totalFeeUSD ?? 0))" } ?? "N/A")
            }

            Text("Routes shown here come from live bridge backends. Hawala does not synthesize bridge quotes when providers are unavailable.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.35))
        }
        .padding(HawalaTheme.Spacing.lg)
        .background(HawalaTheme.Colors.backgroundTertiary)
        .cornerRadius(HawalaTheme.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func selectedRouteReviewSection(_ quote: BridgeService.BridgeQuote) -> some View {
        let level = riskLevel(for: quote)

        return VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
            HStack {
                Text("Selected Route Review")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text(level.title)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(level.color.opacity(0.12))
                    .foregroundColor(level.color)
                    .cornerRadius(4)
            }

            routeReviewRow(title: "Provider", value: quote.provider.displayName)
            routeReviewRow(title: "Minimum receive", value: "\(formatWeiAmount(quote.amountOutMin)) \(quote.tokenSymbol)")
            routeReviewRow(title: "Estimated time", value: "~\(quote.estimatedTimeMinutes) minutes")
            routeReviewRow(title: "Price impact", value: formattedPercent(quote.priceImpact))
            routeReviewRow(title: "Total fee", value: quote.totalFeeUSD.map { "$\(String(format: "%.2f", $0))" } ?? "Unavailable")

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.shield")
                    .font(.system(size: 11))
                    .foregroundColor(HawalaTheme.Colors.warning)
                Text(quote.provider.operationalWarning)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(HawalaTheme.Spacing.sm)
            .background(HawalaTheme.Colors.warning.opacity(0.06))
            .cornerRadius(HawalaTheme.Radius.sm)

            if let dashboardURL = quote.provider.dashboardURL {
                Button {
                    openTransferURL(dashboardURL)
                } label: {
                    HStack {
                        Image(systemName: "link")
                            .font(.system(size: 11))
                        Text("Open \(quote.provider.displayName) Dashboard")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }

            Text(riskMessage(for: quote))
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.35))
        }
        .padding(HawalaTheme.Spacing.lg)
        .background(HawalaTheme.Colors.backgroundTertiary)
        .cornerRadius(HawalaTheme.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func metricChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.35))
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HawalaTheme.Spacing.sm)
        .background(Color.white.opacity(0.04))
        .cornerRadius(HawalaTheme.Radius.sm)
    }

    private func routeReviewRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.trailing)
        }
    }
    
    /// ROADMAP-07 E7: Bridge requires destination confirmation + valid quote
    private var canBridge: Bool {
        selectedQuote != nil && destinationConfirmed && quoteTimeRemaining > 0
    }
    
    private var activeTransfersSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            HStack {
                HawalaOverlaySectionHeader(icon: "arrow.triangle.2.circlepath", title: "Active Transfers")
                Spacer()
                Button("Clear Completed") {
                    bridgeService.clearCompletedTransfers()
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .buttonStyle(.plain)
            }
            
            ForEach(bridgeService.activeTransfers) { transfer in
                BridgeTransferCard(transfer: transfer) {
                    Task { _ = try? await bridgeService.trackTransfer(id: transfer.id) }
                } onOpenSource: {
                    openTransferURL(explorerURL(for: transfer.sourceChain, txHash: transfer.sourceTxHash))
                } onOpenDestination: {
                    guard let destinationTxHash = transfer.destinationTxHash else { return }
                    openTransferURL(explorerURL(for: transfer.destinationChain, txHash: destinationTxHash))
                } onContactSupport: {
                    contactSupport(for: transfer)
                }
            }
        }
        .padding(HawalaTheme.Spacing.lg)
        .background(HawalaTheme.Colors.backgroundSecondary)
        .cornerRadius(HawalaTheme.Radius.xl)
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.xl)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var recentTransfersSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            HStack {
                HawalaOverlaySectionHeader(icon: "clock.arrow.circlepath", title: "Recent Bridge Records")
                Spacer()
                Text("\(bridgeService.recentTransfers.count)")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }

            ForEach(bridgeService.recentTransfers) { transfer in
                BridgeTransferCard(transfer: transfer, showsRefresh: false) {
                } onOpenSource: {
                    openTransferURL(explorerURL(for: transfer.sourceChain, txHash: transfer.sourceTxHash))
                } onOpenDestination: {
                    guard let destinationTxHash = transfer.destinationTxHash else { return }
                    openTransferURL(explorerURL(for: transfer.destinationChain, txHash: destinationTxHash))
                } onContactSupport: {
                    contactSupport(for: transfer)
                }
            }
        }
        .padding(HawalaTheme.Spacing.lg)
        .background(HawalaTheme.Colors.backgroundSecondary)
        .cornerRadius(HawalaTheme.Radius.xl)
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.xl)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
    
    private var settingsSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("Slippage Tolerance")) {
                    HStack {
                        ForEach([0.1, 0.5, 1.0, 3.0], id: \.self) { value in
                            Button {
                                slippage = value
                            } label: {
                                Text("\(String(format: "%.1f", value))%")
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
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
                    
                    // ROADMAP-07: Extended slippage range up to 50% for exotic pairs
                    VStack(alignment: .leading, spacing: 4) {
                        Slider(value: $slippage, in: 0.1...50.0, step: 0.1)
                        HStack {
                            Text("Custom: \(String(format: "%.1f", slippage))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            if slippage > 5.0 {
                                Text("⚠️ High slippage")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
                
                Section(header: Text("Providers")) {
                    ForEach(BridgeService.BridgeProvider.allCases) { provider in
                        HStack {
                            Image(systemName: provider.icon)
                                .foregroundColor(provider.color)
                            Text(provider.displayName)
                            Spacer()
                            if bridgeService.getProviders(from: sourceChain, to: destinationChain).contains(provider) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Text("N/A")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Section(header: Text("Cache")) {
                    Button("Clear Quote Cache") {
                        bridgeService.clearCache()
                    }
                }
            }
            .navigationTitle("Bridge Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showSettings = false }
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var isValidInput: Bool {
        !amount.isEmpty &&
        Double(amount) != nil &&
        Double(amount)! > 0 &&
        sourceChain != destinationChain
    }
    
    // MARK: - ROADMAP-07 E12: Zero-Slippage Warning
    
    private var zeroSlippageWarning: some View {
        HStack(alignment: .top, spacing: HawalaTheme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(HawalaTheme.Colors.warning)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text("Zero Slippage Warning")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(HawalaTheme.Colors.warning)
                Text("With very low slippage (< 0.1%), most bridge transactions will fail due to price movement. Consider increasing to at least 0.5%.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(HawalaTheme.Spacing.lg)
        .background(HawalaTheme.Colors.warning.opacity(0.08))
        .cornerRadius(HawalaTheme.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg)
                .stroke(HawalaTheme.Colors.warning.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning: Zero slippage will cause most bridge transactions to fail")
    }
    
    // MARK: - ROADMAP-07 E9/E10: Quote Expiry Timer
    
    private func startQuoteTimer(expiresAt: Date) {
        stopQuoteTimer()
        let remaining = Int(expiresAt.timeIntervalSinceNow)
        quoteTimeRemaining = max(0, remaining)
        
        // Use a repeating timer with nonisolated closure
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor [self] in
                let r = quoteTimeRemaining - 1
                if r <= 0 {
                    quoteTimeRemaining = 0
                    stopQuoteTimer()
                    // ROADMAP-07 E10: Auto-refresh when timer reaches 0
                    fetchQuotes()
                } else {
                    quoteTimeRemaining = r
                }
            }
        }
        quoteExpiryTimer = timer
    }
    
    private func stopQuoteTimer() {
        quoteExpiryTimer?.invalidate()
        quoteExpiryTimer = nil
    }
    
    private func formatCountdown(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
    
    // MARK: - Actions
    
    private func swapChains() {
        let temp = sourceChain
        sourceChain = destinationChain
        destinationChain = temp
        showQuotes = false
        selectedQuote = nil
        destinationConfirmed = false
        stopQuoteTimer()
    }
    
    private func fetchQuotes() {
        destinationConfirmed = false
        Task {
            do {
                let amountWei = parseAmountToWei(amount)
                _ = try await bridgeService.getQuotes(
                    sourceChain: sourceChain,
                    destinationChain: destinationChain,
                    token: selectedToken,
                    amount: amountWei,
                    slippage: slippage,
                    sender: walletAddress ?? "0x0000000000000000000000000000000000000000",
                    recipient: walletAddress ?? "0x0000000000000000000000000000000000000000"
                )
                showQuotes = true
                selectedQuote = bridgeService.currentQuotes?.bestQuote
                
                // ROADMAP-07 E9: Start countdown timer from quote expiry
                if let expiresAt = selectedQuote?.expiresAt {
                    startQuoteTimer(expiresAt: expiresAt)
                }
            } catch {
                bridgeService.error = error.localizedDescription
            }
        }
    }

    private func riskLevel(for quote: BridgeService.BridgeQuote) -> BridgeRiskLevel {
        let priceImpact = quote.priceImpact ?? 0
        let totalFee = quote.totalFeeUSD ?? 0

        if priceImpact >= 3 || quote.estimatedTimeMinutes >= 30 || totalFee >= 50 {
            return .high
        }

        if priceImpact >= 1 || quote.estimatedTimeMinutes >= 10 || totalFee >= 15 {
            return .review
        }

        return .low
    }

    private func riskMessage(for quote: BridgeService.BridgeQuote) -> String {
        switch riskLevel(for: quote) {
        case .low:
            return "This route is relatively straightforward based on current fee, timing, and price-impact signals. Recheck destination chain and quote expiry before signing."
        case .review:
            return "This route needs review before signing. Confirm the minimum receive, quoted fees, and whether the bridge time is acceptable for the destination workflow."
        case .high:
            return "This route has elevated execution risk because the quoted fee, bridge time, or price impact is materially worse than a typical bridge transfer. Consider refreshing quotes or choosing a different route."
        }
    }

    private func formattedPercent(_ value: Double?) -> String {
        guard let value else { return "Unavailable" }
        return String(format: "%.2f%%", value)
    }

    private func formatWeiAmount(_ value: String) -> String {
        guard let amount = Double(value) else { return "0" }
        return String(format: "%.6f", amount / 1e18)
    }

    private func explorerURL(for chain: BridgeService.SupportedChain, txHash: String) -> URL? {
        let base: String
        switch chain {
        case .ethereum:
            base = "https://etherscan.io/tx/"
        case .bsc:
            base = "https://bscscan.com/tx/"
        case .polygon:
            base = "https://polygonscan.com/tx/"
        case .arbitrum:
            base = "https://arbiscan.io/tx/"
        case .optimism:
            base = "https://optimistic.etherscan.io/tx/"
        case .avalanche:
            base = "https://snowtrace.io/tx/"
        case .base:
            base = "https://basescan.org/tx/"
        case .fantom:
            base = "https://ftmscan.com/tx/"
        case .solana:
            base = "https://solscan.io/tx/"
        }

        return URL(string: base + txHash)
    }

    private func openTransferURL(_ url: URL?) {
        guard let url else { return }
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }

    private func contactSupport(for transfer: BridgeService.BridgeTransfer) {
        let summary = supportSummary(for: transfer)
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        #endif

        if let email = ProcessInfo.processInfo.environment["HAWALA_SUPPORT_EMAIL"],
           let encoded = summary.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "mailto:\(email)?subject=Bridge%20Transfer%20Support&body=\(encoded)") {
            openTransferURL(url)
        }

        bridgeService.error = "Bridge support summary copied. Paste it into your support request."
        copiedSupportSummary = true
    }

    private func supportSummary(for transfer: BridgeService.BridgeTransfer) -> String {
        let destinationHash = transfer.destinationTxHash ?? "Pending"
        let lastCheck = transfer.lastStatusCheckAt?.formatted(date: .abbreviated, time: .shortened) ?? "No live check yet"
        return "Bridge transfer summary\nProvider: \(transfer.provider.displayName)\nRoute: \(transfer.sourceChain.displayName) -> \(transfer.destinationChain.displayName)\nAsset: \(transfer.tokenSymbol)\nInput amount: \(formatWeiAmount(transfer.amountIn))\nQuoted minimum receive: \(formatWeiAmount(transfer.minimumAmountOut))\nSource tx: \(transfer.sourceTxHash)\nDestination tx: \(destinationHash)\nStatus: \(transfer.status.displayName)\nLast live status check: \(lastCheck)\nTracking issue: \(transfer.lastTrackingError ?? "None")"
    }
    
    private func executeBridge() async {
        guard let quote = selectedQuote else { return }
        
        // Ensure we have wallet credentials
        guard let privateKey = privateKey, let fromAddress = walletAddress else {
            bridgeService.error = "No wallet connected. Please connect your wallet first."
            return
        }
        
        do {
            let transfer = try await bridgeService.executeBridge(
                quote: quote,
                privateKey: privateKey,
                fromAddress: fromAddress
            )
            print("Bridge initiated: \(transfer.id)")
            showQuotes = false
            showActiveTransfers = true
            amount = ""
            selectedQuote = nil
        } catch {
            bridgeService.error = error.localizedDescription
        }
    }
    
    private func parseAmountToWei(_ amount: String) -> String {
        guard let value = Double(amount) else { return "0" }
        let wei = value * 1e18
        return String(format: "%.0f", wei)
    }
    
    /// Fetch maximum balance for the selected token on source chain
    private func fetchMaxBalance() async {
        guard let address = walletAddress else {
            amount = "0"
            return
        }
        
        // Map BridgeService.SupportedChain to UnifiedBlockchainProvider.SupportedChain
        let providerChain: UnifiedBlockchainProvider.SupportedChain
        switch sourceChain {
        case .ethereum: providerChain = .ethereum
        case .bsc: providerChain = .bnb
        case .polygon: providerChain = .polygon
        case .arbitrum: providerChain = .arbitrum
        case .optimism: providerChain = .optimism
        case .avalanche: providerChain = .avalanche
        case .base: providerChain = .base
        case .fantom: providerChain = .ethereum // Fantom uses EVM, fallback to ethereum for demo
        case .solana: providerChain = .solana
        }
        
        do {
            // For native tokens (ETH, BNB, etc.), fetch native balance
            if selectedToken == "ETH" || selectedToken == sourceChain.nativeSymbol {
                let balance = try await UnifiedBlockchainProvider.shared.fetchBalance(
                    address: address,
                    chain: providerChain
                )
                // Leave a small amount for gas (0.01 native token)
                let maxAmount = max(0, balance - 0.01)
                amount = String(format: "%.6f", maxAmount)
            } else {
                // For ERC-20 tokens, we'd need token balance - for now use native
                let balance = try await UnifiedBlockchainProvider.shared.fetchBalance(
                    address: address,
                    chain: providerChain
                )
                amount = String(format: "%.6f", balance)
            }
        } catch {
            print("Failed to fetch balance: \(error)")
            amount = "0"
        }
    }
}

// MARK: - Quote Card

struct QuoteCard: View {
    let quote: BridgeService.BridgeQuote
    let label: String
    let isSelected: Bool
    let riskLevel: BridgeRiskLevel
    
    var body: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
            HStack {
                Image(systemName: quote.provider.icon)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.5))
                Text(quote.provider.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text(label)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(HawalaTheme.Colors.success.opacity(0.15))
                    .foregroundColor(HawalaTheme.Colors.success)
                    .cornerRadius(4)

                Text(riskLevel.title)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(riskLevel.color.opacity(0.12))
                    .foregroundColor(riskLevel.color)
                    .cornerRadius(4)
            }
            
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("You Receive")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                    Text("\(quote.formattedAmountOut) \(quote.tokenSymbol)")
                        .font(.clashGroteskMedium(size: 16))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Time")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                    Text("~\(quote.estimatedTimeMinutes) min")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            if let totalFee = quote.totalFeeUSD {
                HStack {
                    Text("Total Fee")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                    Text("$\(String(format: "%.2f", totalFee))")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .padding(HawalaTheme.Spacing.lg)
        .background(isSelected ? Color.white.opacity(0.08) : HawalaTheme.Colors.backgroundSecondary)
        .cornerRadius(HawalaTheme.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg)
                .stroke(isSelected ? Color.white.opacity(0.15) : Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Transfer Card

struct BridgeTransferCard: View {
    let transfer: BridgeService.BridgeTransfer
    var showsRefresh: Bool = true
    let onRefresh: () -> Void
    let onOpenSource: () -> Void
    let onOpenDestination: () -> Void
    let onContactSupport: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: transfer.provider.icon)
                    .foregroundColor(transfer.provider.color)
                Text("\(transfer.sourceChain.displayName) → \(transfer.destinationChain.displayName)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                BridgeStatusBadge(status: transfer.status)
            }
            
            HStack {
                Text("\(formatAmount(transfer.amountIn)) \(transfer.tokenSymbol)")
                    .font(.headline)
                
                Spacer()
                
                if showsRefresh && !transfer.status.isFinal {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                }
            }
            
            if !transfer.status.isFinal {
                ProgressView(value: transferProgress)
                    .progressViewStyle(.linear)
            }

            HStack(spacing: 10) {
                Button("Source Tx", action: onOpenSource)
                    .font(.caption)
                if transfer.destinationTxHash != nil {
                    Button("Destination Tx", action: onOpenDestination)
                        .font(.caption)
                }
                if transfer.lastTrackingError != nil || transfer.status == .failed {
                    Button("Support Summary", action: onContactSupport)
                        .font(.caption)
                }
                Spacer()
            }

            if let trackingError = transfer.lastTrackingError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(trackingError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(8)
            }
            
            HStack {
                Text(transfer.initiatedAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if transfer.status == .completed, let completed = transfer.completedAt {
                    Text("• Completed in \(formatDuration(from: transfer.initiatedAt, to: completed))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let lastStatusCheckAt = transfer.lastStatusCheckAt {
                Text("Last live status check \(lastStatusCheckAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if !transfer.status.isFinal {
                Text("Waiting for the first live bridge status update from the provider.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !transfer.status.isFinal {
                Text("Expected completion around \(transfer.estimatedCompletion.formatted(date: .omitted, time: .shortened)).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Quoted min receive \(formatAmount(transfer.minimumAmountOut)) \(transfer.tokenSymbol)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if let totalFeeUSD = transfer.totalFeeUSD {
                    Text("Fee $\(String(format: "%.2f", totalFeeUSD))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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
    
    private var transferProgress: Double {
        switch transfer.status {
        case .pending:
            return 0.1
        case .sourceConfirmed:
            return 0.3
        case .inTransit:
            return 0.6
        case .waitingDestination:
            return 0.85
        case .completed, .failed, .refunded:
            return 1.0
        }
    }
    
    private func formatAmount(_ weiString: String) -> String {
        guard let wei = Double(weiString) else { return "0" }
        return String(format: "%.6f", wei / 1e18)
    }
    
    private func formatDuration(from start: Date, to end: Date) -> String {
        let seconds = Int(end.timeIntervalSince(start))
        if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            return "\(seconds / 60)m"
        } else {
            return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
        }
    }
}

// MARK: - Bridge Status Badge

struct BridgeStatusBadge: View {
    let status: BridgeService.BridgeStatus
    
    var body: some View {
        Text(status.displayName)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.2))
            .foregroundColor(status.color)
            .cornerRadius(4)
    }
}

// MARK: - Preview

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    NavigationView {
        BridgeView()
    }
}
#endif
#endif
#endif
