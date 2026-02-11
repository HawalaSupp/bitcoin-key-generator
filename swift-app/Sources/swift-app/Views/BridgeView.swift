import SwiftUI

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
        VStack(spacing: 4) {
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
            .accessibilityLabel("Warning: Preview Feature. Cross-chain bridging is simulated.")
            
            Text("Cross-chain bridging is in preview. Transactions are simulated and do not move real funds.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                
                // Active transfers section
                if !bridgeService.activeTransfers.isEmpty && showActiveTransfers {
                    activeTransfersSection
                }
            }
            .padding()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Bridge")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gearshape")
                }
            }
            ToolbarItem(placement: .automatic) {
                if !bridgeService.activeTransfers.isEmpty {
                    Button(action: { showActiveTransfers.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("\(bridgeService.activeTransfers.count)")
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
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("Cross-Chain Bridge")
                    .font(.headline)
                Spacer()
            }
            
            Text("Transfer tokens between blockchains securely")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("From")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                chainPicker(selection: $sourceChain, label: "Source")
                
                Spacer()
                
                tokenPicker
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
        }
    }
    
    private var swapChainsButton: some View {
        Button(action: swapChains) {
            Image(systemName: "arrow.up.arrow.down.circle.fill")
                .font(.title)
                .foregroundColor(.blue)
        }
        .accessibilityLabel("Swap chains")
        .accessibilityHint("Swap source and destination chains")
        .accessibilityIdentifier("bridge_swap_chains_button")
    }
    
    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("To")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            chainPicker(selection: $destinationChain, label: "Destination")
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
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
            HStack {
                Image(systemName: selection.wrappedValue.icon)
                    .foregroundColor(.blue)
                Text(selection.wrappedValue.displayName)
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Amount")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                TextField("0.0", text: $amount)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .accessibilityLabel("Bridge amount")
                    .accessibilityHint("Enter amount to bridge")
                    .accessibilityIdentifier("bridge_amount_input")
                
                Spacer()
                
                Button("MAX") {
                    Task {
                        await fetchMaxBalance()
                    }
                }
                .font(.caption)
                .foregroundColor(.blue)
                .accessibilityLabel("Use maximum balance")
                .accessibilityHint("Set amount to your full balance")
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
        }
    }
    
    private var getQuotesButton: some View {
        Button(action: fetchQuotes) {
            HStack {
                if bridgeService.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Get Bridge Quotes")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isValidInput ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(!isValidInput || bridgeService.isLoading)
        .accessibilityLabel("Get bridge quotes")
        .accessibilityHint("Fetch quotes from bridge providers")
        .accessibilityIdentifier("bridge_get_quotes_button")
    }
    
    private func quotesSection(quotes: BridgeService.AggregatedQuotes) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Available Routes")
                    .font(.headline)
                Spacer()
                
                // ROADMAP-07 E9: Quote expiry countdown
                if quoteTimeRemaining > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption)
                        Text(formatCountdown(quoteTimeRemaining))
                            .font(.caption.monospacedDigit())
                    }
                    .foregroundColor(quoteTimeRemaining < 60 ? .red : .secondary)
                    .accessibilityLabel("Quote expires in \(quoteTimeRemaining) seconds")
                }
                
                Button(action: { stopQuoteTimer(); showQuotes = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
            
            if let best = quotes.bestQuote {
                QuoteCard(quote: best, label: "Best Rate", isSelected: selectedQuote?.id == best.id)
                    .onTapGesture { selectedQuote = best }
            }
            
            if let fastest = quotes.fastestQuote, fastest.id != quotes.bestQuote?.id {
                QuoteCard(quote: fastest, label: "Fastest", isSelected: selectedQuote?.id == fastest.id)
                    .onTapGesture { selectedQuote = fastest }
            }
            
            if let cheapest = quotes.cheapestQuote,
               cheapest.id != quotes.bestQuote?.id,
               cheapest.id != quotes.fastestQuote?.id {
                QuoteCard(quote: cheapest, label: "Lowest Fee", isSelected: selectedQuote?.id == cheapest.id)
                    .onTapGesture { selectedQuote = cheapest }
            }
            
            // ROADMAP-07 E7: Destination chain confirmation checkbox
            Toggle(isOn: $destinationConfirmed) {
                HStack(spacing: 6) {
                    Image(systemName: "shield.checkered")
                        .foregroundColor(.blue)
                    Text("I confirm I am bridging to **\(destinationChain.displayName)**")
                        .font(.caption)
                }
            }
            .toggleStyle(.checkbox)
            .accessibilityLabel("Confirm destination chain is \(destinationChain.displayName)")
            .accessibilityIdentifier("bridge_destination_confirm_toggle")
            
            // ROADMAP-07 E9: Expired quote warning + auto-refresh
            if quoteTimeRemaining <= 0 && showQuotes {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Quote expired")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Spacer()
                    Button("Refresh") {
                        fetchQuotes()
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Bridge button
            Button(action: { confirmBridge = true }) {
                HStack {
                    Image(systemName: "arrow.left.arrow.right")
                    Text("Bridge \(selectedQuote?.tokenSymbol ?? selectedToken)")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(canBridge ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(!canBridge)
        }
        .padding()
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(16)
    }
    
    /// ROADMAP-07 E7: Bridge requires destination confirmation + valid quote
    private var canBridge: Bool {
        selectedQuote != nil && destinationConfirmed && quoteTimeRemaining > 0
    }
    
    private var activeTransfersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Active Transfers")
                    .font(.headline)
                Spacer()
                Button("Clear Completed") {
                    bridgeService.clearCompletedTransfers()
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            ForEach(bridgeService.activeTransfers) { transfer in
                BridgeTransferCard(transfer: transfer) {
                    Task { try? await bridgeService.trackTransfer(id: transfer.id) }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(16)
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text("Zero Slippage Warning")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Text("With very low slippage (< 0.1%), most bridge transactions will fail due to price movement. Consider increasing to at least 0.5%.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.08))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: quote.provider.icon)
                    .foregroundColor(quote.provider.color)
                Text(quote.provider.displayName)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text(label)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.green)
                    .cornerRadius(4)
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("You Receive")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(quote.formattedAmountOut) \(quote.tokenSymbol)")
                        .font(.headline)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Time")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("~\(quote.estimatedTimeMinutes) min")
                        .font(.subheadline)
                }
            }
            
            if let totalFee = quote.totalFeeUSD {
                HStack {
                    Text("Total Fee")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("$\(String(format: "%.2f", totalFee))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(isSelected ? Color.blue.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Transfer Card

struct BridgeTransferCard: View {
    let transfer: BridgeService.BridgeTransfer
    let onRefresh: () -> Void
    
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
                
                if !transfer.status.isFinal {
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
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var transferProgress: Double {
        let elapsed = Date().timeIntervalSince(transfer.initiatedAt)
        let total = transfer.estimatedCompletion.timeIntervalSince(transfer.initiatedAt)
        return min(elapsed / total, 1.0)
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
