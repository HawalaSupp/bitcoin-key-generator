import Foundation

/// Service for fiat on-ramp functionality (buy crypto with fiat)
@MainActor
final class OnRampService: ObservableObject {
    static let shared = OnRampService()
    
    @Published var quotes: [OnRampQuote] = []
    @Published var isLoading = false
    @Published var error: String?
    
    // MARK: - Types
    
    enum Provider: String, CaseIterable, Identifiable {
        case moonpay = "MoonPay"
        case transak = "Transak"
        case ramp = "Ramp Network"
        
        var id: String { rawValue }
        
        var estimatedFeePercent: Double {
            switch self {
            case .moonpay: return 4.5
            case .transak: return 5.0
            case .ramp: return 2.5
            }
        }
        
        var iconName: String {
            switch self {
            case .moonpay: return "moon.fill"
            case .transak: return "arrow.triangle.swap"
            case .ramp: return "bolt.fill"
            }
        }
        
        var description: String {
            switch self {
            case .moonpay: return "Supports 100+ countries with card and bank transfers"
            case .transak: return "Low fees for European users with SEPA"
            case .ramp: return "Best rates with Apple Pay support"
            }
        }
    }
    
    enum PaymentMethod: String, CaseIterable, Identifiable {
        case creditCard = "Credit Card"
        case debitCard = "Debit Card"
        case applePay = "Apple Pay"
        case bankTransfer = "Bank Transfer"
        case sepa = "SEPA"
        case ach = "ACH"
        
        var id: String { rawValue }
        
        var iconName: String {
            switch self {
            case .creditCard: return "creditcard.fill"
            case .debitCard: return "creditcard"
            case .applePay: return "apple.logo"
            case .bankTransfer: return "building.columns"
            case .sepa: return "eurosign.circle.fill"
            case .ach: return "dollarsign.circle"
            }
        }
    }
    
    enum FiatCurrency: String, CaseIterable, Identifiable {
        case usd = "USD"
        case eur = "EUR"
        case gbp = "GBP"
        case cad = "CAD"
        case aud = "AUD"
        case chf = "CHF"
        case jpy = "JPY"
        
        var id: String { rawValue }
        
        var symbol: String {
            switch self {
            case .usd: return "$"
            case .eur: return "€"
            case .gbp: return "£"
            case .cad: return "C$"
            case .aud: return "A$"
            case .chf: return "CHF"
            case .jpy: return "¥"
            }
        }
    }
    
    struct OnRampQuote: Identifiable {
        let id = UUID()
        let provider: Provider
        let fiatAmount: Double
        let fiatCurrency: FiatCurrency
        let cryptoAmount: Double
        let cryptoSymbol: String
        let feeAmount: Double
        let feePercent: Double
        let exchangeRate: Double
        
        var totalCost: Double {
            fiatAmount + feeAmount
        }
        
        var effectiveRate: Double {
            totalCost / cryptoAmount
        }
    }
    
    struct OnRampRequest {
        let fiatAmount: Double
        let fiatCurrency: FiatCurrency
        let cryptoSymbol: String
        let walletAddress: String
        let email: String?
        let network: String?
        
        init(
            fiatAmount: Double,
            fiatCurrency: FiatCurrency = .usd,
            cryptoSymbol: String,
            walletAddress: String,
            email: String? = nil,
            network: String? = nil
        ) {
            self.fiatAmount = fiatAmount
            self.fiatCurrency = fiatCurrency
            self.cryptoSymbol = cryptoSymbol
            self.walletAddress = walletAddress
            self.email = email
            self.network = network
        }
    }
    
    // MARK: - API Keys (should be loaded from secure storage)
    
    private struct APIKeys {
        static var moonpayApiKey: String {
            // In production, load from Keychain or environment
            ProcessInfo.processInfo.environment["MOONPAY_API_KEY"] ?? "pk_test_demo"
        }
        
        static var transakApiKey: String {
            ProcessInfo.processInfo.environment["TRANSAK_API_KEY"] ?? "demo_api_key"
        }
        
        static var rampApiKey: String {
            ProcessInfo.processInfo.environment["RAMP_API_KEY"] ?? "demo_api_key"
        }
    }
    
    // MARK: - Quote Fetching
    
    @MainActor
    func fetchQuotes(request: OnRampRequest) async {
        isLoading = true
        error = nil
        
        var fetchedQuotes: [OnRampQuote] = []
        
        // Fetch from all providers in parallel
        async let moonpayQuote = fetchMoonPayQuote(request: request)
        async let transakQuote = fetchTransakQuote(request: request)
        async let rampQuote = fetchRampQuote(request: request)
        
        if let quote = await moonpayQuote {
            fetchedQuotes.append(quote)
        }
        if let quote = await transakQuote {
            fetchedQuotes.append(quote)
        }
        if let quote = await rampQuote {
            fetchedQuotes.append(quote)
        }
        
        // Sort by effective rate (best first)
        quotes = fetchedQuotes.sorted { $0.effectiveRate < $1.effectiveRate }
        isLoading = false
        
        if quotes.isEmpty {
            error = "No quotes available"
        }
    }
    
    // MARK: - Provider-Specific Quote Fetching
    
    private func fetchMoonPayQuote(request: OnRampRequest) async -> OnRampQuote? {
        // In production, this would call the MoonPay API
        // For now, simulate with estimated values
        let fee = request.fiatAmount * 0.045 // 4.5% fee
        let cryptoAmount = estimateCryptoAmount(
            fiat: request.fiatAmount - fee,
            symbol: request.cryptoSymbol
        )
        
        return OnRampQuote(
            provider: .moonpay,
            fiatAmount: request.fiatAmount,
            fiatCurrency: request.fiatCurrency,
            cryptoAmount: cryptoAmount,
            cryptoSymbol: request.cryptoSymbol,
            feeAmount: fee,
            feePercent: 4.5,
            exchangeRate: (request.fiatAmount - fee) / cryptoAmount
        )
    }
    
    private func fetchTransakQuote(request: OnRampRequest) async -> OnRampQuote? {
        let fee = request.fiatAmount * 0.05 // 5% fee
        let cryptoAmount = estimateCryptoAmount(
            fiat: request.fiatAmount - fee,
            symbol: request.cryptoSymbol
        )
        
        return OnRampQuote(
            provider: .transak,
            fiatAmount: request.fiatAmount,
            fiatCurrency: request.fiatCurrency,
            cryptoAmount: cryptoAmount,
            cryptoSymbol: request.cryptoSymbol,
            feeAmount: fee,
            feePercent: 5.0,
            exchangeRate: (request.fiatAmount - fee) / cryptoAmount
        )
    }
    
    private func fetchRampQuote(request: OnRampRequest) async -> OnRampQuote? {
        let fee = request.fiatAmount * 0.025 // 2.5% fee
        let cryptoAmount = estimateCryptoAmount(
            fiat: request.fiatAmount - fee,
            symbol: request.cryptoSymbol
        )
        
        return OnRampQuote(
            provider: .ramp,
            fiatAmount: request.fiatAmount,
            fiatCurrency: request.fiatCurrency,
            cryptoAmount: cryptoAmount,
            cryptoSymbol: request.cryptoSymbol,
            feeAmount: fee,
            feePercent: 2.5,
            exchangeRate: (request.fiatAmount - fee) / cryptoAmount
        )
    }
    
    // MARK: - Widget URL Generation
    
    func buildWidgetURL(provider: Provider, request: OnRampRequest) -> URL? {
        switch provider {
        case .moonpay:
            return buildMoonPayURL(request: request)
        case .transak:
            return buildTransakURL(request: request)
        case .ramp:
            return buildRampURL(request: request)
        }
    }
    
    private func buildMoonPayURL(request: OnRampRequest) -> URL? {
        var components = URLComponents(string: "https://buy.moonpay.com")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "apiKey", value: APIKeys.moonpayApiKey),
            URLQueryItem(name: "currencyCode", value: request.cryptoSymbol.lowercased()),
            URLQueryItem(name: "baseCurrencyCode", value: request.fiatCurrency.rawValue.lowercased()),
            URLQueryItem(name: "baseCurrencyAmount", value: String(format: "%.2f", request.fiatAmount)),
            URLQueryItem(name: "walletAddress", value: request.walletAddress),
        ]
        
        if let email = request.email {
            items.append(URLQueryItem(name: "email", value: email))
        }
        
        components.queryItems = items
        return components.url
    }
    
    private func buildTransakURL(request: OnRampRequest) -> URL? {
        var components = URLComponents(string: "https://global.transak.com")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "apiKey", value: APIKeys.transakApiKey),
            URLQueryItem(name: "cryptoCurrencyCode", value: request.cryptoSymbol.uppercased()),
            URLQueryItem(name: "fiatCurrency", value: request.fiatCurrency.rawValue),
            URLQueryItem(name: "fiatAmount", value: String(format: "%.2f", request.fiatAmount)),
            URLQueryItem(name: "walletAddress", value: request.walletAddress),
            URLQueryItem(name: "disableWalletAddressForm", value: "true"),
        ]
        
        if let email = request.email {
            items.append(URLQueryItem(name: "email", value: email))
        }
        
        if let network = request.network {
            items.append(URLQueryItem(name: "network", value: network.lowercased()))
        }
        
        components.queryItems = items
        return components.url
    }
    
    private func buildRampURL(request: OnRampRequest) -> URL? {
        var components = URLComponents(string: "https://buy.ramp.network")!
        
        let asset = formatRampAsset(
            symbol: request.cryptoSymbol,
            network: request.network
        )
        
        var items: [URLQueryItem] = [
            URLQueryItem(name: "hostApiKey", value: APIKeys.rampApiKey),
            URLQueryItem(name: "swapAsset", value: asset),
            URLQueryItem(name: "fiatCurrency", value: request.fiatCurrency.rawValue),
            URLQueryItem(name: "fiatValue", value: String(format: "%.2f", request.fiatAmount)),
            URLQueryItem(name: "userAddress", value: request.walletAddress),
        ]
        
        if let email = request.email {
            items.append(URLQueryItem(name: "userEmailAddress", value: email))
        }
        
        components.queryItems = items
        return components.url
    }
    
    private func formatRampAsset(symbol: String, network: String?) -> String {
        let networkName: String
        if let network = network {
            networkName = network.uppercased()
        } else {
            // Default networks
            switch symbol.uppercased() {
            case "ETH", "USDC", "USDT", "DAI": networkName = "ETHEREUM"
            case "MATIC": networkName = "POLYGON"
            case "BNB": networkName = "BSC"
            case "AVAX": networkName = "AVALANCHE"
            case "BTC": return "BTC_BTC"
            default: networkName = "ETHEREUM"
            }
        }
        return "\(symbol.uppercased())_\(networkName)"
    }
    
    // MARK: - Helpers
    
    private func estimateCryptoAmount(fiat: Double, symbol: String) -> Double {
        // Rough estimates for demo - in production use real prices
        let prices: [String: Double] = [
            "BTC": 68000.0,
            "ETH": 3500.0,
            "USDC": 1.0,
            "USDT": 1.0,
            "DAI": 1.0,
            "SOL": 150.0,
            "MATIC": 0.85,
            "AVAX": 35.0,
            "BNB": 580.0,
        ]
        
        let price = prices[symbol.uppercased()] ?? 1.0
        return fiat / price
    }
    
    func formatFiat(_ amount: Double, currency: FiatCurrency) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.rawValue
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency.symbol)\(amount)"
    }
    
    func formatCrypto(_ amount: Double, symbol: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 8
        formatter.minimumFractionDigits = 4
        return "\(formatter.string(from: NSNumber(value: amount)) ?? String(amount)) \(symbol.uppercased())"
    }
}
