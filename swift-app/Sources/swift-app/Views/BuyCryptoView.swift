import SwiftUI

/// View for purchasing crypto with fiat currency through various on-ramp providers
struct BuyCryptoView: View {
    @StateObject private var onRampService = OnRampService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var fiatAmount: String = "100"
    @State private var selectedFiat: OnRampService.FiatCurrency = .usd
    @State private var selectedCrypto: String = "ETH"
    @State private var walletAddress: String = ""
    @State private var selectedProvider: OnRampService.Provider?
    @State private var showProviderSheet = false
    @State private var isLoadingQuotes = false
    @State private var hoveringQuote: String?
    @State private var hoveringChip: Int?
    @State private var hoveringProvider: String?
    @State private var appeared = false
    
    private let cryptoOptions = ["BTC", "ETH", "USDC", "USDT", "SOL", "MATIC", "AVAX", "BNB"]

    private var draftRequest: OnRampService.OnRampRequest? {
        guard let amount = Double(fiatAmount), amount > 0 else { return nil }

        let trimmedAddress = walletAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else { return nil }

        return OnRampService.OnRampRequest(
            fiatAmount: amount,
            fiatCurrency: selectedFiat,
            cryptoSymbol: selectedCrypto,
            walletAddress: trimmedAddress
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            headerBar
            
            Divider()
                .background(Color.white.opacity(0.06))
            
            ScrollView {
                VStack(spacing: HawalaTheme.Spacing.xl) {
                    // Hero amount
                    amountSection
                    
                    // Crypto selection
                    cryptoSection
                    
                    // Wallet address
                    addressSection
                    
                    // Get quotes button
                    getQuotesButton

                    if let error = onRampService.error {
                        errorSection(message: error)
                    }
                    
                    // Quotes list
                    if !onRampService.quotes.isEmpty {
                        quotesSection
                    }
                    
                    // Provider info
                    providerInfoSection
                }
                .padding(HawalaTheme.Spacing.xl)
            }
        }
        .background(HawalaTheme.Colors.background)
        .frame(minWidth: 550, idealWidth: 650, minHeight: 600, idealHeight: 750)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { appeared = true }
        }
        .sheet(isPresented: $showProviderSheet) {
            if let provider = selectedProvider {
                providerWebView(provider: provider)
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 32, height: 32)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Buy Crypto")
                    .font(.clashGroteskMedium(size: 18))
                    .foregroundColor(.white)
                Text("Purchase with fiat currency")
                    .font(.system(size: 12))
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            
            Spacer()
            
            Image(systemName: "creditcard.fill")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.3))
                .frame(width: 32, height: 32)
                .background(HawalaTheme.Colors.backgroundTertiary)
                .clipShape(Circle())
        }
        .padding(.horizontal, HawalaTheme.Spacing.xl)
        .padding(.vertical, HawalaTheme.Spacing.lg)
    }

    // MARK: - Error

    private func errorSection(message: String) -> some View {
        HStack(alignment: .top, spacing: HawalaTheme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundColor(HawalaTheme.Colors.warning)

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.8))

            Spacer()
        }
        .padding(HawalaTheme.Spacing.lg)
        .background(HawalaTheme.Colors.warning.opacity(0.08))
        .cornerRadius(HawalaTheme.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                .stroke(HawalaTheme.Colors.warning.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Components
    
    private var amountSection: some View {
        VStack(spacing: HawalaTheme.Spacing.lg) {
            HawalaOverlaySectionHeader(icon: "dollarsign.circle", title: "Amount")
            
            // Hero amount display
            VStack(spacing: HawalaTheme.Spacing.md) {
                HStack(spacing: HawalaTheme.Spacing.sm) {
                    // Fiat currency picker
                    Menu {
                        ForEach(OnRampService.FiatCurrency.allCases) { currency in
                            Button(currency.rawValue) { selectedFiat = currency }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(selectedFiat.symbol)
                                .font(.clashGroteskMedium(size: 28))
                                .foregroundColor(.white.opacity(0.4))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    
                    TextField("0", text: $fiatAmount)
                        .textFieldStyle(.plain)
                        .font(.clashGroteskMedium(size: 36))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, HawalaTheme.Spacing.lg)
                
                // Quick amount chips
                HStack(spacing: HawalaTheme.Spacing.sm) {
                    ForEach(Array([50, 100, 250, 500].enumerated()), id: \.offset) { index, amount in
                        Button(action: { fiatAmount = String(amount) }) {
                            Text("\(selectedFiat.symbol)\(amount)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(fiatAmount == String(amount) ? .white : .white.opacity(0.5))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    fiatAmount == String(amount)
                                    ? Color.white.opacity(0.10)
                                    : (hoveringChip == index ? Color.white.opacity(0.06) : Color.white.opacity(0.03))
                                )
                                .cornerRadius(HawalaTheme.Radius.sm)
                                .overlay(
                                    RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm)
                                        .stroke(
                                            fiatAmount == String(amount) ? Color.white.opacity(0.15) : Color.white.opacity(0.06),
                                            lineWidth: 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .onHover { h in hoveringChip = h ? index : nil }
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
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
    }
    
    private var cryptoSection: some View {
        VStack(spacing: HawalaTheme.Spacing.lg) {
            HawalaOverlaySectionHeader(icon: "bitcoinsign.circle", title: "Select Asset")
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: HawalaTheme.Spacing.sm),
                GridItem(.flexible(), spacing: HawalaTheme.Spacing.sm),
                GridItem(.flexible(), spacing: HawalaTheme.Spacing.sm),
                GridItem(.flexible(), spacing: HawalaTheme.Spacing.sm),
            ], spacing: HawalaTheme.Spacing.sm) {
                ForEach(cryptoOptions, id: \.self) { crypto in
                    let isSelected = selectedCrypto == crypto
                    Button(action: { withAnimation(HawalaTheme.Animation.fast) { selectedCrypto = crypto } }) {
                        VStack(spacing: 6) {
                            Image(systemName: cryptoIcon(for: crypto))
                                .font(.system(size: 20))
                                .foregroundColor(cryptoColor(for: crypto))
                            Text(crypto)
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(0.5)
                                .foregroundColor(isSelected ? .white : .white.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, HawalaTheme.Spacing.md)
                        .background(isSelected ? Color.white.opacity(0.10) : Color.white.opacity(0.03))
                        .cornerRadius(HawalaTheme.Radius.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                                .stroke(
                                    isSelected ? Color.white.opacity(0.15) : Color.white.opacity(0.06),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .animation(.easeOut(duration: 0.4).delay(0.05), value: appeared)
    }
    
    private var addressSection: some View {
        VStack(spacing: HawalaTheme.Spacing.lg) {
            HawalaOverlaySectionHeader(icon: "wallet.pass", title: "Wallet Address")
            
            HStack(spacing: HawalaTheme.Spacing.sm) {
                TextField("Enter your \(selectedCrypto) address", text: $walletAddress)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(HawalaTheme.Spacing.md)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .cornerRadius(HawalaTheme.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                
                Button(action: pasteAddress) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(HawalaTheme.Radius.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .animation(.easeOut(duration: 0.4).delay(0.1), value: appeared)
    }
    
    @State private var hoveringGetQuotes = false
    
    private var getQuotesButton: some View {
        let isDisabled = walletAddress.isEmpty || fiatAmount.isEmpty || onRampService.isLoading
        
        return Button(action: fetchQuotes) {
            HStack(spacing: HawalaTheme.Spacing.sm) {
                if onRampService.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                }
                Text(onRampService.isLoading ? "Checking Providers..." : "Check Providers")
                    .font(.system(size: 13, weight: .semibold))
                if !onRampService.isLoading {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .foregroundColor(isDisabled ? .white.opacity(0.3) : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isDisabled ? Color.white.opacity(0.04) : (hoveringGetQuotes ? Color.white.opacity(0.18) : Color.white.opacity(0.12)))
            .cornerRadius(HawalaTheme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                    .stroke(Color.white.opacity(isDisabled ? 0.04 : 0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { h in hoveringGetQuotes = h }
        .animation(HawalaTheme.Animation.fast, value: hoveringGetQuotes)
    }
    
    private var quotesSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.lg) {
            HStack {
                HawalaOverlaySectionHeader(icon: "list.bullet.rectangle", title: "Quotes")
                Spacer()
                Text("Best rate first")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.3))
            }
            
            ForEach(onRampService.quotes) { quote in
                quoteCard(quote: quote)
            }
        }
    }
    
    private func quoteCard(quote: OnRampService.OnRampQuote) -> some View {
        let isBest = quote.id == onRampService.quotes.first?.id
        let isHovering = hoveringQuote == quote.id.uuidString
        
        return Button(action: {
            selectedProvider = quote.provider
            showProviderSheet = true
        }) {
            HStack(spacing: HawalaTheme.Spacing.lg) {
                // Provider icon
                Image(systemName: quote.provider.iconName)
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm, style: .continuous))
                
                // Details
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: HawalaTheme.Spacing.sm) {
                        Text(quote.provider.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        if isBest {
                            Text("BEST")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.8)
                                .foregroundColor(HawalaTheme.Colors.success)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(HawalaTheme.Colors.success.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                    
                    Text("Fee: \(String(format: "%.1f%%", quote.feePercent)) (\(onRampService.formatFiat(quote.feeAmount, currency: quote.fiatCurrency)))")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }
                
                Spacer()
                
                // Amount
                VStack(alignment: .trailing, spacing: 4) {
                    Text(onRampService.formatCrypto(quote.cryptoAmount, symbol: quote.cryptoSymbol))
                        .font(.clashGroteskMedium(size: 16))
                        .foregroundColor(.white)
                    Text(onRampService.formatFiat(quote.totalCost, currency: quote.fiatCurrency))
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(HawalaTheme.Spacing.lg)
            .background(isHovering ? Color.white.opacity(0.06) : HawalaTheme.Colors.backgroundSecondary)
            .cornerRadius(HawalaTheme.Radius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg)
                    .stroke(
                        isBest ? HawalaTheme.Colors.success.opacity(0.3) : Color.white.opacity(0.06),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { h in hoveringQuote = h ? quote.id.uuidString : nil }
        .animation(HawalaTheme.Animation.fast, value: isHovering)
    }
    
    private var providerInfoSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.lg) {
            HawalaOverlaySectionHeader(icon: "building.2", title: "Supported Providers")
            
            VStack(spacing: 2) {
                ForEach(OnRampService.Provider.allCases) { provider in
                    let status = draftRequest.map { onRampService.providerStatus(provider: provider, request: $0) }
                    let isHovering = hoveringProvider == provider.rawValue

                    HStack(spacing: HawalaTheme.Spacing.md) {
                        Image(systemName: provider.iconName)
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm, style: .continuous))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: HawalaTheme.Spacing.sm) {
                                Text(provider.rawValue)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.85))

                                if let status {
                                    Text(status.state.label.uppercased())
                                        .font(.system(size: 9, weight: .bold))
                                        .tracking(0.5)
                                        .foregroundColor(statusForegroundColor(for: status.state))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(statusBackgroundColor(for: status.state))
                                        .cornerRadius(4)
                                }
                            }

                            Text(status?.detail ?? provider.description)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.35))
                        }
                        
                        Spacer()

                        if let status, status.canOpenWidget {
                            Button(action: {
                                selectedProvider = provider
                                showProviderSheet = true
                            }) {
                                Text("Open")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.6))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.06))
                                    .cornerRadius(HawalaTheme.Radius.sm)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm)
                                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(HawalaTheme.Spacing.md)
                    .background(isHovering ? Color.white.opacity(0.04) : Color.clear)
                    .cornerRadius(HawalaTheme.Radius.md)
                    .onHover { h in hoveringProvider = h ? provider.rawValue : nil }
                    .animation(HawalaTheme.Animation.fast, value: isHovering)
                }
            }
            .padding(HawalaTheme.Spacing.sm)
            .background(HawalaTheme.Colors.backgroundSecondary)
            .cornerRadius(HawalaTheme.Radius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
    }
    
    private func providerWebView(provider: OnRampService.Provider) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Buy via \(provider.rawValue)")
                    .font(.clashGroteskMedium(size: 16))
                    .foregroundColor(.white)
                Spacer()
                Button(action: { showProviderSheet = false }) {
                    Text("Done")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(HawalaTheme.Radius.sm)
                }
                .buttonStyle(.plain)
            }
            .padding(HawalaTheme.Spacing.lg)
            .background(HawalaTheme.Colors.backgroundSecondary)
            
            // Placeholder for WebView
            VStack(spacing: HawalaTheme.Spacing.lg) {
                Image(systemName: "globe")
                    .font(.system(size: 48))
                    .foregroundColor(.white.opacity(0.15))
                
                Text("Widget would open here")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                
                if let url = buildProviderURL(provider: provider) {
                    Link("Open in Browser", destination: url)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(HawalaTheme.Radius.sm)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HawalaTheme.Colors.background)
        }
        .frame(minWidth: 500, minHeight: 600)
    }
    
    // MARK: - Actions
    
    private func fetchQuotes() {
        guard let request = draftRequest else { return }
        
        Task {
            await onRampService.fetchQuotes(request: request)
        }
    }
    
    private func pasteAddress() {
        if let string = NSPasteboard.general.string(forType: .string) {
            walletAddress = string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
    private func buildProviderURL(provider: OnRampService.Provider) -> URL? {
        guard let request = draftRequest else { return nil }
        return onRampService.buildWidgetURL(provider: provider, request: request)
    }
    
    // MARK: - Helpers
    
    private func cryptoIcon(for symbol: String) -> String {
        switch symbol {
        case "BTC": return "bitcoinsign.circle.fill"
        case "ETH": return "diamond.fill"
        case "USDC", "USDT", "DAI": return "dollarsign.circle.fill"
        case "SOL": return "sun.max.fill"
        case "MATIC": return "hexagon.fill"
        case "AVAX": return "snow"
        case "BNB": return "square.stack.3d.up.fill"
        default: return "circle.fill"
        }
    }
    
    private func cryptoColor(for symbol: String) -> Color {
        switch symbol {
        case "BTC": return HawalaTheme.Colors.bitcoin
        case "ETH": return HawalaTheme.Colors.ethereum
        case "SOL": return HawalaTheme.Colors.solana
        case "BNB": return HawalaTheme.Colors.bnb
        case "USDC", "USDT": return Color(hex: "2775CA")
        case "MATIC": return Color(hex: "8247E5")
        case "AVAX": return Color(hex: "E84142")
        default: return .white.opacity(0.5)
        }
    }

    private func statusBackgroundColor(for state: OnRampService.ProviderAvailabilityState) -> Color {
        switch state {
        case .widgetReady:
            return HawalaTheme.Colors.success.opacity(0.15)
        case .missingConfiguration:
            return HawalaTheme.Colors.warning.opacity(0.15)
        case .unsupportedAsset:
            return HawalaTheme.Colors.error.opacity(0.15)
        case .invalidRequest:
            return Color.white.opacity(0.06)
        }
    }

    private func statusForegroundColor(for state: OnRampService.ProviderAvailabilityState) -> Color {
        switch state {
        case .widgetReady:
            return HawalaTheme.Colors.success
        case .missingConfiguration:
            return HawalaTheme.Colors.warning
        case .unsupportedAsset:
            return HawalaTheme.Colors.error
        case .invalidRequest:
            return .white.opacity(0.4)
        }
    }
}

// MARK: - Preview

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    BuyCryptoView()
        .frame(width: 500, height: 800)
}
#endif
#endif
#endif
