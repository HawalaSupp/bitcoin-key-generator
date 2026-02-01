import SwiftUI

/// View for purchasing crypto with fiat currency through various on-ramp providers
struct BuyCryptoView: View {
    @StateObject private var onRampService = OnRampService.shared
    
    @State private var fiatAmount: String = "100"
    @State private var selectedFiat: OnRampService.FiatCurrency = .usd
    @State private var selectedCrypto: String = "ETH"
    @State private var walletAddress: String = ""
    @State private var selectedProvider: OnRampService.Provider?
    @State private var showProviderSheet = false
    @State private var isLoadingQuotes = false
    
    private let cryptoOptions = ["BTC", "ETH", "USDC", "USDT", "SOL", "MATIC", "AVAX", "BNB"]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection
                
                // Amount input
                amountSection
                
                // Crypto selection
                cryptoSection
                
                // Wallet address
                addressSection
                
                // Get quotes button
                getQuotesButton
                
                // Quotes list
                if !onRampService.quotes.isEmpty {
                    quotesSection
                }
                
                // Provider info
                providerInfoSection
            }
            .padding()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showProviderSheet) {
            if let provider = selectedProvider {
                providerWebView(provider: provider)
            }
        }
    }
    
    // MARK: - Components
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "creditcard.and.123")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            
            Text("Buy Crypto")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Purchase cryptocurrency with your preferred payment method")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical)
    }
    
    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Amount")
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack {
                // Fiat currency picker
                Picker("", selection: $selectedFiat) {
                    ForEach(OnRampService.FiatCurrency.allCases) { currency in
                        Text(currency.rawValue).tag(currency)
                    }
                }
                .labelsHidden()
                .frame(width: 80)
                
                // Amount text field
                TextField("Amount", text: $fiatAmount)
                    .textFieldStyle(.roundedBorder)
                    .font(.title2)
                
                // Quick amount buttons
                HStack(spacing: 8) {
                    ForEach([50, 100, 250, 500], id: \.self) { amount in
                        Button(action: { fiatAmount = String(amount) }) {
                            Text("\(selectedFiat.symbol)\(amount)")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var cryptoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Buy")
                .font(.subheadline)
                .fontWeight(.medium)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 12) {
                ForEach(cryptoOptions, id: \.self) { crypto in
                    Button(action: { selectedCrypto = crypto }) {
                        VStack(spacing: 4) {
                            Image(systemName: cryptoIcon(for: crypto))
                                .font(.title2)
                            Text(crypto)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            selectedCrypto == crypto ?
                            Color.accentColor.opacity(0.2) :
                            Color.clear
                        )
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    selectedCrypto == crypto ? Color.accentColor : Color.gray.opacity(0.3),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var addressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wallet Address")
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack {
                TextField("Enter your \(selectedCrypto) address", text: $walletAddress)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                
                Button(action: pasteAddress) {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var getQuotesButton: some View {
        Button(action: fetchQuotes) {
            HStack {
                if onRampService.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.trailing, 4)
                }
                Text(onRampService.isLoading ? "Getting Quotes..." : "Get Quotes")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .buttonStyle(.borderedProminent)
        .disabled(walletAddress.isEmpty || fiatAmount.isEmpty || onRampService.isLoading)
    }
    
    private var quotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Available Quotes")
                    .font(.headline)
                Spacer()
                Text("Best rate first")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ForEach(onRampService.quotes) { quote in
                quoteCard(quote: quote)
            }
        }
    }
    
    private func quoteCard(quote: OnRampService.OnRampQuote) -> some View {
        let isBest = quote.id == onRampService.quotes.first?.id
        
        return Button(action: {
            selectedProvider = quote.provider
            showProviderSheet = true
        }) {
            HStack(spacing: 16) {
                // Provider icon
                Image(systemName: quote.provider.iconName)
                    .font(.title)
                    .foregroundColor(.accentColor)
                    .frame(width: 44)
                
                // Details
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(quote.provider.rawValue)
                            .font(.headline)
                        if isBest {
                            Text("Best")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                        }
                    }
                    
                    Text("Fee: \(String(format: "%.1f%%", quote.feePercent)) (\(onRampService.formatFiat(quote.feeAmount, currency: quote.fiatCurrency)))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Amount
                VStack(alignment: .trailing, spacing: 4) {
                    Text(onRampService.formatCrypto(quote.cryptoAmount, symbol: quote.cryptoSymbol))
                        .font(.headline)
                    Text(onRampService.formatFiat(quote.totalCost, currency: quote.fiatCurrency))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isBest ? Color.green.opacity(0.5) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var providerInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Supported Providers")
                .font(.headline)
            
            ForEach(OnRampService.Provider.allCases) { provider in
                HStack(spacing: 12) {
                    Image(systemName: provider.iconName)
                        .font(.title2)
                        .foregroundColor(.accentColor)
                        .frame(width: 32)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(provider.rawValue)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("~\(String(format: "%.1f%%", provider.estimatedFeePercent)) fee")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text(provider.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func providerWebView(provider: OnRampService.Provider) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Buy via \(provider.rawValue)")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    showProviderSheet = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            // Placeholder for WebView
            VStack {
                Image(systemName: "globe")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)
                    .padding()
                
                Text("Widget would open here")
                    .font(.title2)
                
                if let url = buildProviderURL(provider: provider) {
                    Link("Open in Browser", destination: url)
                        .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 500, minHeight: 600)
    }
    
    // MARK: - Actions
    
    private func fetchQuotes() {
        guard let amount = Double(fiatAmount), amount > 0 else { return }
        guard !walletAddress.isEmpty else { return }
        
        let request = OnRampService.OnRampRequest(
            fiatAmount: amount,
            fiatCurrency: selectedFiat,
            cryptoSymbol: selectedCrypto,
            walletAddress: walletAddress
        )
        
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
        guard let amount = Double(fiatAmount), amount > 0 else { return nil }
        
        let request = OnRampService.OnRampRequest(
            fiatAmount: amount,
            fiatCurrency: selectedFiat,
            cryptoSymbol: selectedCrypto,
            walletAddress: walletAddress
        )
        
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
