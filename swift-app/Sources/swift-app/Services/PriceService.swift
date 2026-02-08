import Foundation
import SwiftUI

/// Service responsible for fetching and managing cryptocurrency prices and FX rates
/// Extracted from ContentView to improve separation of concerns
@MainActor
final class PriceService: ObservableObject {
    // MARK: - Published State
    @Published var priceStates: [String: ChainPriceState] = [:]
    @Published var cachedPrices: [String: CachedPrice] = [:]
    @Published var fxRates: [String: Double] = [:] // Currency code -> rate (relative to USD)
    
    // MARK: - Internal State
    var priceBackoffTracker = BackoffTracker()
    var priceUpdateTask: Task<Void, Never>?
    var fxRatesFetchTask: Task<Void, Never>?
    
    // MARK: - Configuration
    var coingeckoAPIKey: String?
    
    // MARK: - Constants
    let trackedPriceChainIDs = [
        "bitcoin", "bitcoin-testnet", "ethereum", "ethereum-sepolia", "litecoin", "monero",
        "solana", "xrp", "bnb", "usdt-erc20", "usdc-erc20", "dai-erc20"
    ]
    private let pricePollingInterval: TimeInterval = 120
    
    // MARK: - Singleton
    static let shared = PriceService()
    
    private init() {}
    
    // MARK: - Public API
    
    func startPriceUpdatesIfNeeded(sparklineCache: SparklineCache) {
        guard priceUpdateTask == nil else { return }
        sparklineCache.apiKey = coingeckoAPIKey
        sparklineCache.fetchAllSparklines()
        priceUpdateTask = Task { await priceUpdateLoop() }
        startFXRatesFetch()
    }
    
    func stopPriceUpdates() {
        priceUpdateTask?.cancel()
        priceUpdateTask = nil
    }
    
    func markPriceStatesLoading() {
        for id in trackedPriceChainIDs {
            priceStates[id] = .loading
        }
    }
    
    func ensurePriceStateEntries() {
        for id in trackedPriceChainIDs where priceStates[id] == nil {
            applyPriceLoadingState(for: id)
        }
    }
    
    func defaultPriceState(for chainID: String) -> ChainPriceState {
        if let staticDisplay = staticPriceDisplay(for: chainID, fxRates: fxRates, storedFiatCurrency: "USD") {
            return .loaded(value: staticDisplay, lastUpdated: Date())
        }
        return .loading
    }
    
    func defaultPriceStateWithCurrency(for chainID: String, storedFiatCurrency: String) -> ChainPriceState {
        if let staticDisplay = staticPriceDisplay(for: chainID, fxRates: fxRates, storedFiatCurrency: storedFiatCurrency) {
            return .loaded(value: staticDisplay, lastUpdated: Date())
        }
        return .loading
    }
    
    func staticPriceDisplay(for chainID: String, fxRates: [String: Double], storedFiatCurrency: String) -> String? {
        switch chainID {
        case "usdt-erc20", "usdc-erc20", "dai-erc20":
            return formatFiatAmountInSelectedCurrency(1.0, storedFiatCurrency: storedFiatCurrency)
        case "bitcoin-testnet", "ethereum-sepolia":
            return "Testnet asset"
        default:
            return nil
        }
    }
    
    func primeStateCaches(for keys: AllKeys, balanceService: BalanceService, storedFiatCurrency: String) {
        let chains = keys.chainInfos
        for chain in chains {
            let balanceDefault = balanceService.defaultBalanceState(for: chain.id)
            let priceDefault = defaultPriceStateWithCurrency(for: chain.id, storedFiatCurrency: storedFiatCurrency)
            balanceService.balanceStates[chain.id] = balanceDefault
            priceStates[chain.id] = priceDefault
        }
    }
    
    func resetState() {
        priceStates.removeAll()
        cachedPrices.removeAll()
        priceBackoffTracker = BackoffTracker()
    }
    
    // MARK: - FX Rates
    
    func startFXRatesFetch() {
        fxRatesFetchTask?.cancel()
        fxRatesFetchTask = Task {
            do {
                let rates = try await fetchFXRates()
                self.fxRates = rates
            } catch {
                #if DEBUG
                print("Failed to fetch FX rates: \(error)")
                #endif
                // Keep existing rates if fetch fails
            }
        }
    }
    
    func fetchFXRates() async throws -> [String: Double] {
        // CoinGecko provides exchange rates for many currencies relative to BTC
        // We use USD as base (rate = 1.0) and calculate other rates
        let baseURL: String
        if let apiKey = coingeckoAPIKey, !apiKey.isEmpty {
            baseURL = "https://pro-api.coingecko.com/api/v3/exchange_rates?x_cg_pro_api_key=\(apiKey)"
        } else {
            baseURL = "https://api.coingecko.com/api/v3/exchange_rates"
        }
        
        guard let url = URL(string: baseURL) else {
            throw BalanceFetchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/\(AppVersion.displayVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }
        
        // Handle rate limiting
        if httpResponse.statusCode == 429 {
            throw BalanceFetchError.rateLimited
        }
        
        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidResponse
        }

        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = object as? [String: Any],
              let rates = dictionary["rates"] as? [String: Any] else {
            throw BalanceFetchError.invalidPayload
        }

        // Get USD value (base)
        guard let usdInfo = rates["usd"] as? [String: Any],
              let usdValue = usdInfo["value"] as? Double else {
            return ["USD": 1.0]
        }

        var fxRates: [String: Double] = ["USD": 1.0]
        
        // Calculate rates relative to USD
        let currencyCodes = ["EUR": "eur", "GBP": "gbp", "JPY": "jpy", "CAD": "cad", 
                            "AUD": "aud", "CHF": "chf", "CNY": "cny", "INR": "inr", "PLN": "pln"]
        
        for (code, apiKey) in currencyCodes {
            if let info = rates[apiKey] as? [String: Any],
               let value = info["value"] as? Double {
                // Rate relative to USD: how many units of currency per 1 USD
                fxRates[code] = value / usdValue
            }
        }

        return fxRates
    }
    
    // MARK: - Price Fetching
    
    func priceUpdateLoop() async {
        while !Task.isCancelled {
            let result = await fetchAndStorePrices()
            
            if result.rateLimited {
                let delay = priceBackoffTracker.registerFailure()
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } else if result.success {
                priceBackoffTracker.registerSuccess()
                try? await Task.sleep(nanoseconds: UInt64(pricePollingInterval * 1_000_000_000))
            } else {
                try? await Task.sleep(nanoseconds: UInt64(pricePollingInterval * 1_000_000_000))
            }
        }
    }
    
    func fetchAndStorePrices() async -> (success: Bool, rateLimited: Bool) {
        do {
            let snapshot = try await fetchPriceSnapshot()
            updatePriceStates(with: snapshot, timestamp: Date())
            return (success: true, rateLimited: false)
        } catch BalanceFetchError.rateLimited {
            applyPriceStaleState(message: "Rate limited")
            return (success: false, rateLimited: true)
        } catch {
            applyPriceStaleState(message: "Error fetching prices")
            return (success: false, rateLimited: false)
        }
    }
    
    func applyPriceStaleState(message: String) {
        for chainId in trackedPriceChainIDs {
            if let cached = cachedPrices[chainId] {
                priceStates[chainId] = .stale(value: cached.value, lastUpdated: cached.lastUpdated, message: message)
            }
        }
    }
    
    func updatePriceStates(with snapshot: [String: Double], timestamp: Date) {
        for chainId in trackedPriceChainIDs {
            if let identifiers = priceIdentifiers(for: chainId) {
                for identifier in identifiers {
                    if let price = snapshot[identifier] {
                        let formatted = formatPrice(price)
                        cachedPrices[chainId] = CachedPrice(value: formatted, lastUpdated: timestamp)
                        priceStates[chainId] = .loaded(value: formatted, lastUpdated: timestamp)
                        break
                    }
                }
            } else if let staticDisplay = staticPriceDisplay(for: chainId, fxRates: fxRates, storedFiatCurrency: "USD") {
                priceStates[chainId] = .loaded(value: staticDisplay, lastUpdated: timestamp)
            }
        }
    }
    
    func priceIdentifiers(for chainId: String) -> [String]? {
        switch chainId {
        case "bitcoin":
            return ["bitcoin"]
        case "ethereum":
            return ["ethereum"]
        case "litecoin":
            return ["litecoin"]
        case "monero":
            return ["monero"]
        case "solana":
            return ["solana"]
        case "xrp":
            return ["ripple", "xrp"]
        case "bnb":
            return ["binancecoin", "bnb"]
        case "bitcoin-testnet", "ethereum-sepolia", "usdt-erc20", "usdc-erc20", "dai-erc20":
            return nil
        default:
            return nil
        }
    }
    
    func fetchPriceSnapshot() async throws -> [String: Double] {
        // Use MultiProviderAPI with automatic fallbacks (CoinCap -> CryptoCompare -> CoinGecko)
        do {
            return try await MultiProviderAPI.shared.fetchPrices()
        } catch {
            // If all providers fail, throw rate limited error to trigger retry
            throw BalanceFetchError.rateLimited
        }
    }
    
    // MARK: - Price State Management
    
    func applyPriceLoadingState(for chainId: String, storedFiatCurrency: String = "USD") {
        let now = Date()
        let state = PriceStateReducer.loadingState(
            cache: cachedPrices[chainId],
            staticDisplay: staticPriceDisplay(for: chainId, fxRates: fxRates, storedFiatCurrency: storedFiatCurrency),
            now: now
        )
        if case .loaded(let value, let timestamp) = state {
            cachedPrices[chainId] = CachedPrice(value: value, lastUpdated: timestamp)
        }
        priceStates[chainId] = state
    }
    
    func applyPriceFailureState(message: String, storedFiatCurrency: String = "USD") {
        let now = Date()
        for id in trackedPriceChainIDs {
            let state = PriceStateReducer.failureState(
                cache: cachedPrices[id],
                staticDisplay: staticPriceDisplay(for: id, fxRates: fxRates, storedFiatCurrency: storedFiatCurrency),
                message: message,
                now: now
            )
            if case .loaded(let value, let timestamp) = state {
                cachedPrices[id] = CachedPrice(value: value, lastUpdated: timestamp)
            }
            priceStates[id] = state
        }
    }
    
    // MARK: - Formatting
    
    func formatPrice(_ price: Double) -> String {
        return formatFiatAmountInSelectedCurrency(price, storedFiatCurrency: "USD")
    }
    
    func formatFiatAmountInSelectedCurrency(_ amountInUSD: Double, storedFiatCurrency: String = "USD", useSelectedCurrency: Bool = true) -> String {
        // ROADMAP-04 E12: $0 price → "Price unavailable"
        if amountInUSD <= 0 {
            return "Price unavailable"
        }
        
        let currency = useSelectedCurrency ? (FiatCurrency(rawValue: storedFiatCurrency) ?? .usd) : .usd
        let rate = fxRates[currency.rawValue] ?? 1.0
        let convertedAmount = amountInUSD * rate
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.rawValue
        
        // Use appropriate locale for currency formatting
        switch currency {
        case .eur: formatter.locale = Locale(identifier: "de_DE")
        case .gbp: formatter.locale = Locale(identifier: "en_GB")
        case .jpy: formatter.locale = Locale(identifier: "ja_JP")
        case .cad: formatter.locale = Locale(identifier: "en_CA")
        case .aud: formatter.locale = Locale(identifier: "en_AU")
        case .chf: formatter.locale = Locale(identifier: "de_CH")
        case .cny: formatter.locale = Locale(identifier: "zh_CN")
        case .inr: formatter.locale = Locale(identifier: "en_IN")
        case .pln: formatter.locale = Locale(identifier: "pl_PL")
        case .usd: formatter.locale = Locale(identifier: "en_US")
        }
        
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        
        return formatter.string(from: NSNumber(value: convertedAmount)) ?? "\(currency.symbol)\(String(format: "%.2f", convertedAmount))"
    }

    func formatFiatAmount(_ amount: Double, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = Locale(identifier: "en_US")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }

    // MARK: - Portfolio Calculations

    /// Extract a numeric fiat price from a ChainPriceState
    func extractFiatPrice(from state: ChainPriceState) -> Double? {
        let value: String
        switch state {
        case .loaded(let string, _), .refreshing(let string, _), .stale(let string, _, _):
            value = string
        default:
            return nil
        }

        let filtered = value.filter { "0123456789.,-".contains($0) }
        guard !filtered.isEmpty else { return nil }
        let normalized = filtered.replacingOccurrences(of: ",", with: "")
        return Double(normalized)
    }

    /// Calculate total portfolio value across all chains
    func calculatePortfolioTotal(keys: AllKeys?, balanceStates: [String: ChainBalanceState], balanceService: BalanceService) -> (total: Double?, hasData: Bool) {
        guard let keys else { return (nil, false) }
        var accumulator: Double = 0
        var hasValue = false

        for chain in keys.chainInfos {
            let balanceState = balanceStates[chain.id] ?? balanceService.defaultBalanceState(for: chain.id)
            let priceState = priceStates[chain.id] ?? defaultPriceState(for: chain.id)

            guard
                let balance = balanceService.extractNumericAmount(from: balanceState),
                let price = extractFiatPrice(from: priceState)
            else { continue }

            hasValue = true
            accumulator += balance * price
        }

        return hasValue ? (accumulator, true) : (nil, false)
    }

    /// The most recent price update timestamp across all chains
    var latestPriceUpdate: Date? {
        priceStates.values.compactMap { state in
            switch state {
            case .loaded(_, let timestamp):
                return timestamp
            case .refreshing(_, let timestamp):
                return timestamp
            case .stale(_, let timestamp, _):
                return timestamp
            default:
                return nil
            }
        }.max()
    }

    /// Human-readable price status line for the portfolio header
    func priceStatusLine(storedFiatCurrency: String) -> String {
        if priceStates.isEmpty {
            return "Fetching live prices…"
        }

        if priceStates.values.contains(where: { state in
            if case .loading = state { return true }
            return false
        }) {
            return "Fetching live prices…"
        }
        if priceStates.values.contains(where: { state in
            if case .refreshing = state { return true }
            return false
        }) {
            return "Refreshing live prices…"
        }

        if priceStates.values.contains(where: { state in
            if case .stale = state { return true }
            return false
        }) {
            if let latest = latestPriceUpdate, let relative = relativeTimeDescription(from: latest) {
                return "Showing cached prices • updated \(relative)"
            }
            return "Showing cached prices"
        }

        if let latest = latestPriceUpdate, let relative = relativeTimeDescription(from: latest) {
            return "Live estimate • updated \(relative)"
        }

        return "Live estimate"
    }
}
