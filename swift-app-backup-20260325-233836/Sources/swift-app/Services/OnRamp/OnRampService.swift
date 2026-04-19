import Foundation

/// Service for fiat on-ramp functionality (buy crypto with fiat)
@MainActor
final class OnRampService: ObservableObject {
    static let shared = OnRampService()

    @Published var quotes: [OnRampQuote] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published private(set) var providerStatuses: [ProviderStatus] = []

    // MARK: - Types

    enum Provider: String, CaseIterable, Identifiable {
        case moonpay = "MoonPay"
        case transak = "Transak"
        case ramp = "Ramp Network"

        var id: String { rawValue }

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

        var supportedCryptoSymbols: Set<String> {
            ["BTC", "ETH", "USDC", "USDT", "SOL", "MATIC", "AVAX", "BNB"]
        }
    }

    enum ProviderAvailabilityState {
        case widgetReady
        case missingConfiguration
        case unsupportedAsset
        case invalidRequest

        var label: String {
            switch self {
            case .widgetReady:
                return "Widget Ready"
            case .missingConfiguration:
                return "Not Configured"
            case .unsupportedAsset:
                return "Unsupported"
            case .invalidRequest:
                return "Fix Input"
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

    enum QuoteSource {
        case providerAPI
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
        let fetchedAt: Date
        let expiresAt: Date?
        let source: QuoteSource

        var totalCost: Double {
            fiatAmount + feeAmount
        }

        var effectiveRate: Double {
            totalCost / cryptoAmount
        }

        var isExpired: Bool {
            guard let expiresAt else { return false }
            return Date() >= expiresAt
        }
    }

    struct ProviderStatus: Identifiable {
        let provider: Provider
        let state: ProviderAvailabilityState
        let detail: String
        let widgetURL: URL?

        var id: Provider { provider }

        var canOpenWidget: Bool {
            widgetURL != nil
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

    // MARK: - API Keys

    private struct APIKeys {
        static var moonpayApiKey: String? {
            sanitizedKey(
                ProcessInfo.processInfo.environment["MOONPAY_API_KEY"],
                invalidValues: ["pk_test_demo"]
            )
        }

        static var transakApiKey: String? {
            sanitizedKey(
                ProcessInfo.processInfo.environment["TRANSAK_API_KEY"],
                invalidValues: ["demo_api_key"]
            )
        }

        static var rampApiKey: String? {
            sanitizedKey(
                ProcessInfo.processInfo.environment["RAMP_API_KEY"],
                invalidValues: ["demo_api_key"]
            )
        }

        private static func sanitizedKey(_ value: String?, invalidValues: Set<String>) -> String? {
            guard let rawValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawValue.isEmpty,
                  !invalidValues.contains(rawValue) else {
                return nil
            }

            return rawValue
        }
    }

    private struct ProviderQuoteResult {
        let status: ProviderStatus
        let quote: OnRampQuote?
    }

    // MARK: - Quote Fetching

    @MainActor
    func fetchQuotes(request: OnRampRequest) async {
        isLoading = true
        error = nil
        quotes = []
        providerStatuses = []

        if let validationError = validate(request: request) {
            providerStatuses = Provider.allCases.map {
                ProviderStatus(provider: $0, state: .invalidRequest, detail: validationError, widgetURL: nil)
            }
            error = validationError
            isLoading = false
            return
        }

        async let moonpayResult = fetchProviderResult(for: .moonpay, request: request)
        async let transakResult = fetchProviderResult(for: .transak, request: request)
        async let rampResult = fetchProviderResult(for: .ramp, request: request)

        let results = await [moonpayResult, transakResult, rampResult]
        providerStatuses = results.map(\.status)
        quotes = results.compactMap(\.quote).sorted { $0.effectiveRate < $1.effectiveRate }
        isLoading = false

        if quotes.isEmpty {
            if providerStatuses.contains(where: \.canOpenWidget) {
                error = "Provider widgets are available, but live rate quotes are not integrated yet. Continue in a configured provider widget to complete the purchase."
            } else {
                error = "No on-ramp providers are configured for this request."
            }
        }
    }

    func providerStatus(provider: Provider, request: OnRampRequest) -> ProviderStatus {
        availabilityStatus(for: provider, request: request)
    }

    // MARK: - Provider-Specific Quote Fetching

    private func fetchProviderResult(for provider: Provider, request: OnRampRequest) async -> ProviderQuoteResult {
        let status = availabilityStatus(for: provider, request: request)
        return ProviderQuoteResult(status: status, quote: nil)
    }

    private func availabilityStatus(for provider: Provider, request: OnRampRequest) -> ProviderStatus {
        if let validationError = validate(request: request) {
            return ProviderStatus(
                provider: provider,
                state: .invalidRequest,
                detail: validationError,
                widgetURL: nil
            )
        }

        let symbol = request.cryptoSymbol.uppercased()
        guard provider.supportedCryptoSymbols.contains(symbol) else {
            return ProviderStatus(
                provider: provider,
                state: .unsupportedAsset,
                detail: "\(provider.rawValue) does not currently support \(symbol) in Hawala's configured buy flow.",
                widgetURL: nil
            )
        }

        guard let widgetURL = buildProviderWidgetURL(provider: provider, request: request) else {
            return ProviderStatus(
                provider: provider,
                state: .missingConfiguration,
                detail: "\(provider.rawValue) is missing required API configuration. Add the provider key in the environment before enabling this route.",
                widgetURL: nil
            )
        }

        return ProviderStatus(
            provider: provider,
            state: .widgetReady,
            detail: "\(provider.rawValue) is configured for widget launch. Live quote API integration is still pending, so pricing is finalized inside the provider checkout.",
            widgetURL: widgetURL
        )
    }

    // MARK: - Widget URL Generation

    func buildWidgetURL(provider: Provider, request: OnRampRequest) -> URL? {
        availabilityStatus(for: provider, request: request).widgetURL
    }

    private func buildProviderWidgetURL(provider: Provider, request: OnRampRequest) -> URL? {
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
        guard let apiKey = APIKeys.moonpayApiKey else { return nil }

        var components = URLComponents(string: "https://buy.moonpay.com")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "apiKey", value: apiKey),
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
        guard let apiKey = APIKeys.transakApiKey else { return nil }

        var components = URLComponents(string: "https://global.transak.com")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "apiKey", value: apiKey),
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
        guard let apiKey = APIKeys.rampApiKey else { return nil }

        var components = URLComponents(string: "https://buy.ramp.network")!

        let asset = formatRampAsset(
            symbol: request.cryptoSymbol,
            network: request.network
        )

        var items: [URLQueryItem] = [
            URLQueryItem(name: "hostApiKey", value: apiKey),
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

    private func validate(request: OnRampRequest) -> String? {
        guard request.fiatAmount > 0 else {
            return "Enter a valid fiat amount before requesting providers."
        }

        guard !request.cryptoSymbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Select a crypto asset before requesting providers."
        }

        guard !request.walletAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Enter a wallet address before requesting providers."
        }

        return nil
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
