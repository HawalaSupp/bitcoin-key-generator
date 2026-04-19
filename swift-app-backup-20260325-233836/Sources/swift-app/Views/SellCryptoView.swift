import SwiftUI

// MARK: - Sell Crypto View (Off-Ramp)
/// Convert crypto to fiat via MoonPay, Transak, and other providers
struct SellCryptoView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var error: String?
    @State private var appearAnimation = false
    
    // Selection states
    @State private var selectedCrypto = "ETH"
    @State private var cryptoAmount = ""
    @State private var selectedFiat = "USD"
    @State private var selectedCountry = "US"
    @State private var selectedProvider: HawalaBridge.OffRampProvider?
    
    // Data
    @State private var quotes: [HawalaBridge.OffRampQuote] = []
    @State private var currencies: [HawalaBridge.FiatCurrency] = []
    @State private var cryptos: [HawalaBridge.SellableCrypto] = []
    
    private let supportedCryptos = ["BTC", "ETH", "SOL", "USDC", "USDT"]
    private let supportedFiats = ["USD", "EUR", "GBP", "CAD", "AUD"]
    private let countries = [
        ("US", "🇺🇸 United States"),
        ("GB", "🇬🇧 United Kingdom"),
        ("EU", "🇪🇺 Europe"),
        ("CA", "🇨🇦 Canada"),
        ("AU", "🇦🇺 Australia")
    ]
    
    var body: some View {
        ZStack {
            HawalaTheme.Colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                Divider()
                    .background(HawalaTheme.Colors.divider)
                
                // Content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: HawalaTheme.Spacing.lg) {
                        // Sell form
                        sellFormSection
                        
                        // Get quotes button
                        if !cryptoAmount.isEmpty {
                            getQuotesButton
                        }
                        
                        // Quotes comparison
                        if !quotes.isEmpty {
                            quotesSection
                        }
                        
                        // Provider info
                        providerInfoSection
                    }
                    .padding(.horizontal, HawalaTheme.Spacing.lg)
                    .padding(.vertical, HawalaTheme.Spacing.md)
                }
            }
            
            // Error toast
            if let error = error {
                VStack {
                    Spacer()
                    errorToast(message: error)
                        .padding(.bottom, 40)
                }
            }
        }
        .frame(minWidth: 550, idealWidth: 650, minHeight: 550, idealHeight: 700)
        .onAppear {
            withAnimation(HawalaTheme.Animation.spring) {
                appearAnimation = true
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            VStack(spacing: 2) {
                Text("Sell Crypto")
                    .font(HawalaTheme.Typography.h3)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text("Convert to fiat currency")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
            }
            
            Spacer()
            
            // Info button
            Button(action: { /* Show info */ }) {
                Image(systemName: "info.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    // MARK: - Sell Form
    
    private var sellFormSection: some View {
        VStack(spacing: HawalaTheme.Spacing.lg) {
            // Crypto selection
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                Text("YOU SELL")
                    .font(HawalaTheme.Typography.label)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                
                HStack(spacing: HawalaTheme.Spacing.md) {
                    // Amount input
                    TextField("0.0", text: $cryptoAmount)
                        .textFieldStyle(.plain)
                        .font(HawalaTheme.Typography.display(28))
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                    
                    // Crypto picker
                    Menu {
                        ForEach(supportedCryptos, id: \.self) { crypto in
                            Button(action: { selectedCrypto = crypto }) {
                                HStack {
                                    Text(crypto)
                                    if selectedCrypto == crypto {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            cryptoIcon(selectedCrypto)
                            Text(selectedCrypto)
                                .font(HawalaTheme.Typography.h4)
                                .foregroundColor(HawalaTheme.Colors.textPrimary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12))
                                .foregroundColor(HawalaTheme.Colors.textSecondary)
                        }
                        .padding(HawalaTheme.Spacing.md)
                        .background(HawalaTheme.Colors.backgroundTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                    }
                    .buttonStyle(.plain)
                }
                .padding(HawalaTheme.Spacing.lg)
                .background(HawalaTheme.Colors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg))
            }
            
            // Arrow
            Image(systemName: "arrow.down")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(HawalaTheme.Colors.textSecondary)
                .frame(width: 40, height: 40)
                .background(HawalaTheme.Colors.backgroundTertiary)
                .clipShape(Circle())
            
            // Fiat selection
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                Text("YOU RECEIVE")
                    .font(HawalaTheme.Typography.label)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                
                HStack(spacing: HawalaTheme.Spacing.md) {
                    // Estimated amount (calculated from best quote)
                    if let bestQuote = quotes.first {
                        Text(String(format: "%.2f", bestQuote.fiatAmount))
                            .font(HawalaTheme.Typography.display(28))
                            .foregroundColor(HawalaTheme.Colors.success)
                    } else {
                        Text("—")
                            .font(HawalaTheme.Typography.display(28))
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                    }
                    
                    Spacer()
                    
                    // Fiat picker
                    Menu {
                        ForEach(supportedFiats, id: \.self) { fiat in
                            Button(action: { selectedFiat = fiat }) {
                                HStack {
                                    Text(fiat)
                                    if selectedFiat == fiat {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            fiatFlag(selectedFiat)
                            Text(selectedFiat)
                                .font(HawalaTheme.Typography.h4)
                                .foregroundColor(HawalaTheme.Colors.textPrimary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12))
                                .foregroundColor(HawalaTheme.Colors.textSecondary)
                        }
                        .padding(HawalaTheme.Spacing.md)
                        .background(HawalaTheme.Colors.backgroundTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                    }
                    .buttonStyle(.plain)
                }
                .padding(HawalaTheme.Spacing.lg)
                .background(HawalaTheme.Colors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg))
            }
            
            // Country selector
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                Text("YOUR COUNTRY")
                    .font(HawalaTheme.Typography.label)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                
                Menu {
                    ForEach(countries, id: \.0) { country in
                        Button(action: { selectedCountry = country.0 }) {
                            HStack {
                                Text(country.1)
                                if selectedCountry == country.0 {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(countries.first { $0.0 == selectedCountry }?.1 ?? "Select Country")
                            .font(HawalaTheme.Typography.body)
                            .foregroundColor(HawalaTheme.Colors.textPrimary)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12))
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                    }
                    .padding(HawalaTheme.Spacing.md)
                    .background(HawalaTheme.Colors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func cryptoIcon(_ symbol: String) -> some View {
        let color: Color = {
            switch symbol {
            case "BTC": return HawalaTheme.Colors.bitcoin
            case "ETH": return HawalaTheme.Colors.ethereum
            case "SOL": return HawalaTheme.Colors.solana
            case "USDC", "USDT": return Color(hex: "2775CA")
            default: return HawalaTheme.Colors.textSecondary
            }
        }()
        
        return Circle()
            .fill(color.opacity(0.2))
            .frame(width: 32, height: 32)
            .overlay(
                Text(String(symbol.prefix(1)))
                    .font(HawalaTheme.Typography.captionBold)
                    .foregroundColor(color)
            )
    }
    
    private func fiatFlag(_ code: String) -> some View {
        Text({
            switch code {
            case "USD": return "🇺🇸"
            case "EUR": return "🇪🇺"
            case "GBP": return "🇬🇧"
            case "CAD": return "🇨🇦"
            case "AUD": return "🇦🇺"
            default: return "💵"
            }
        }())
        .font(.system(size: 20))
    }
    
    // MARK: - Get Quotes Button
    
    private var getQuotesButton: some View {
        Button(action: { Task { await getQuotes() } }) {
            HStack {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                Text(quotes.isEmpty ? "Get Quotes" : "Refresh Quotes")
            }
            .font(HawalaTheme.Typography.captionBold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(HawalaTheme.Spacing.md)
            .background(HawalaTheme.Colors.accent)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
    
    // MARK: - Quotes Section
    
    private var quotesSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            HStack {
                Text("PROVIDER QUOTES")
                    .font(HawalaTheme.Typography.label)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                
                Spacer()
                
                Text("Best rate highlighted")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            
            ForEach(Array(quotes.enumerated()), id: \.1.quoteId) { index, quote in
                quoteCard(quote: quote, isBest: index == 0)
            }
        }
    }
    
    private func quoteCard(quote: HawalaBridge.OffRampQuote, isBest: Bool) -> some View {
        Button(action: { selectedProvider = quote.provider }) {
            VStack(spacing: HawalaTheme.Spacing.md) {
                HStack {
                    // Provider logo/name
                    HStack(spacing: HawalaTheme.Spacing.sm) {
                        providerIcon(quote.provider)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(quote.provider.rawValue.capitalized)
                                .font(HawalaTheme.Typography.h4)
                                .foregroundColor(HawalaTheme.Colors.textPrimary)
                            
                            if isBest {
                                Text("Best Rate")
                                    .font(HawalaTheme.Typography.label)
                                    .foregroundColor(HawalaTheme.Colors.success)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Fiat amount
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatCurrency(quote.fiatAmount, currency: quote.fiatCurrency))
                            .font(HawalaTheme.Typography.h3)
                            .foregroundColor(isBest ? HawalaTheme.Colors.success : HawalaTheme.Colors.textPrimary)
                        
                        Text("1 \(quote.cryptoSymbol) = \(formatCurrency(quote.exchangeRate, currency: quote.fiatCurrency))")
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                    }
                }
                
                Divider()
                    .background(HawalaTheme.Colors.divider)
                
                // Fee breakdown
                HStack {
                    feeItem(label: "Provider Fee", value: formatCurrency(quote.providerFee, currency: quote.fiatCurrency))
                    Spacer()
                    feeItem(label: "Network Fee", value: formatCurrency(quote.networkFee, currency: quote.fiatCurrency))
                    Spacer()
                    feeItem(label: "Total Fees", value: formatCurrency(quote.totalFees, currency: quote.fiatCurrency), highlight: true)
                }
            }
            .padding(HawalaTheme.Spacing.lg)
            .background(
                isBest ? HawalaTheme.Colors.success.opacity(0.1) : HawalaTheme.Colors.backgroundSecondary
            )
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg)
                    .strokeBorder(
                        isBest ? HawalaTheme.Colors.success.opacity(0.3) : HawalaTheme.Colors.border,
                        lineWidth: selectedProvider == quote.provider ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private func providerIcon(_ provider: HawalaBridge.OffRampProvider) -> some View {
        let (color, icon): (Color, String) = {
            switch provider {
            case .moonpay: return (Color(hex: "7D00FF"), "moon.fill")
            case .transak: return (Color(hex: "0064E0"), "arrow.triangle.swap")
            case .ramp: return (Color(hex: "21BF73"), "r.circle.fill")
            case .sardine: return (Color(hex: "1E3A5F"), "fish.fill")
            case .banxa: return (Color(hex: "00D395"), "b.circle.fill")
            }
        }()
        
        return ZStack {
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: 40, height: 40)
            
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
        }
    }
    
    private func feeItem(label: String, value: String, highlight: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
            
            Text(value)
                .font(HawalaTheme.Typography.captionBold)
                .foregroundColor(highlight ? HawalaTheme.Colors.warning : HawalaTheme.Colors.textSecondary)
        }
    }
    
    private func formatCurrency(_ amount: Double, currency: String) -> String {
        let symbol: String = {
            switch currency {
            case "USD": return "$"
            case "EUR": return "€"
            case "GBP": return "£"
            case "CAD": return "C$"
            case "AUD": return "A$"
            default: return ""
            }
        }()
        return "\(symbol)\(String(format: "%.2f", amount))"
    }
    
    // MARK: - Provider Info
    
    private var providerInfoSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            Text("ABOUT OFF-RAMP PROVIDERS")
                .font(HawalaTheme.Typography.label)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
            
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                infoRow(icon: "checkmark.shield", text: "All providers are licensed and regulated")
                infoRow(icon: "lock.fill", text: "Your crypto is sent directly to the provider")
                infoRow(icon: "banknote", text: "Funds typically arrive within 1-3 business days")
                infoRow(icon: "person.badge.shield.checkmark", text: "KYC verification may be required")
            }
            .padding(HawalaTheme.Spacing.md)
            .background(HawalaTheme.Colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
        }
    }
    
    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: HawalaTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(HawalaTheme.Colors.info)
                .frame(width: 20)
            
            Text(text)
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
        }
    }
    
    // MARK: - Error Toast
    
    private func errorToast(message: String) -> some View {
        HStack(spacing: HawalaTheme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(HawalaTheme.Colors.error)
            
            Text(message)
                .font(HawalaTheme.Typography.bodySmall)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
        }
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.error.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
    }
    
    // MARK: - Data Operations
    
    private func getQuotes() async {
        guard let amount = Double(cryptoAmount), amount > 0 else {
            error = "Please enter a valid amount"
            return
        }
        
        isLoading = true
        error = nil
        
        do {
            quotes = try HawalaBridge.shared.compareOffRampQuotes(
                cryptoSymbol: selectedCrypto,
                cryptoAmount: amount,
                fiatCurrency: selectedFiat,
                country: selectedCountry
            )
            
            // Sort by fiat amount (descending - best first)
            quotes.sort { $0.fiatAmount > $1.fiatAmount }
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
}

// MARK: - Preview

#if DEBUG
struct SellCryptoView_Previews: PreviewProvider {
    static var previews: some View {
        SellCryptoView()
            .preferredColorScheme(.dark)
    }
}
#endif
