import Foundation
import SwiftUI

/// Service responsible for fetching and caching cryptocurrency balances
/// Extracted from ContentView to improve separation of concerns
@MainActor
final class BalanceService: ObservableObject {
    // MARK: - Published State
    @Published var balanceStates: [String: ChainBalanceState] = [:]
    @Published var cachedBalances: [String: CachedBalance] = [:]
    
    // MARK: - Internal State
    var balanceBackoff: [String: BackoffTracker] = [:]
    var balanceFetchTasks: [String: Task<Void, Never>] = [:]
    
    // MARK: - Constants
    private let minimumBalanceRetryDelay: TimeInterval = 0.5
    
    // MARK: - Singleton
    static let shared = BalanceService()
    
    private init() {}
    
    // MARK: - Public API
    
    func startBalanceFetch(for keys: AllKeys) {
        cancelBalanceFetchTasks()
        balanceBackoff.removeAll()
        
        // Group 1: BlockCypher (Rate limited, must be spaced out)
        scheduleBalanceFetch(for: "bitcoin") {
            try await self.fetchBitcoinBalance(address: keys.bitcoin.address)
        }

        scheduleBalanceFetch(for: "bitcoin-testnet", delay: 0.5) {
            try await self.fetchBitcoinBalance(address: keys.bitcoinTestnet.address, isTestnet: true)
        }

        scheduleBalanceFetch(for: "litecoin", delay: 1.0) {
            try await self.fetchLitecoinBalance(address: keys.litecoin.address)
        }

        // Group 2: Independent APIs (Can run in parallel immediately)
        scheduleBalanceFetch(for: "solana") {
            try await self.fetchSolanaBalance(address: keys.solana.publicKeyBase58)
        }

        scheduleBalanceFetch(for: "xrp") {
            try await self.fetchXrpBalance(address: keys.xrp.classicAddress)
        }

        scheduleBalanceFetch(for: "bnb") {
            try await self.fetchBnbBalance(address: keys.bnb.address)
        }

        startEthereumAndTokenBalanceFetch(address: keys.ethereum.address)
    }
    
    func startEthereumAndTokenBalanceFetch(address: String) {
        scheduleBalanceFetch(for: "ethereum") {
            try await self.fetchEthereumBalanceViaInfura(address: address)
        }

        scheduleBalanceFetch(for: "ethereum-sepolia", delay: 0.3) {
            try await self.fetchEthereumSepoliaBalance(address: address)
        }

        scheduleBalanceFetch(for: "usdt-erc20", delay: 0.7) {
            try await self.fetchERC20Balance(
                address: address,
                contractAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
                decimals: 6,
                symbol: "USDT"
            )
        }

        scheduleBalanceFetch(for: "usdc-erc20", delay: 1.4) {
            try await self.fetchERC20Balance(
                address: address,
                contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
                decimals: 6,
                symbol: "USDC"
            )
        }

        scheduleBalanceFetch(for: "dai-erc20", delay: 2.1) {
            try await self.fetchERC20Balance(
                address: address,
                contractAddress: "0x6B175474E89094C44Da98b954EedeAC495271d0F",
                decimals: 18,
                symbol: "DAI"
            )
        }
    }
    
    func refreshAllBalances(keys: AllKeys) {
        startBalanceFetch(for: keys)
    }
    
    func cancelBalanceFetchTasks() {
        for task in balanceFetchTasks.values {
            task.cancel()
        }
        balanceFetchTasks.removeAll()
    }
    
    func primeStateCaches(for keys: AllKeys, trackedChainIDs: [String]) {
        for chainID in trackedChainIDs {
            if balanceStates[chainID] == nil {
                balanceStates[chainID] = defaultBalanceState(for: chainID)
            }
        }
    }
    
    // MARK: - State Management
    
    func scheduleBalanceFetch(for chainId: String, delay: TimeInterval = 0, fetcher: @escaping () async throws -> String) {
        applyLoadingState(for: chainId)
        launchBalanceFetchTask(for: chainId, after: delay, fetcher: fetcher)
    }
    
    func applyLoadingState(for chainId: String) {
        if let cache = cachedBalances[chainId] {
            balanceStates[chainId] = .refreshing(previous: cache.value, lastUpdated: cache.lastUpdated)
        } else {
            balanceStates[chainId] = .loading
        }
    }
    
    func defaultBalanceState(for chainID: String) -> ChainBalanceState {
        if let cache = cachedBalances[chainID] {
            return .loaded(value: cache.value, lastUpdated: cache.lastUpdated)
        }
        return .idle
    }
    
    // MARK: - Private Fetch Helpers
    
    private func launchBalanceFetchTask(for chainId: String, after delay: TimeInterval, fetcher: @escaping () async throws -> String) {
        balanceFetchTasks[chainId]?.cancel()
        let task = Task {
            if delay > 0 {
                let nanos = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }
            await runBalanceFetchLoop(chainId: chainId, fetcher: fetcher)
        }
        balanceFetchTasks[chainId] = task
    }

    private func runBalanceFetchLoop(chainId: String, fetcher: @escaping () async throws -> String) async {
        while !Task.isCancelled {
            let succeeded = await performBalanceFetch(chainId: chainId, fetcher: fetcher)
            if succeeded || Task.isCancelled {
                return
            }

            let pendingDelay = balanceBackoff[chainId]?.remainingBackoff ?? minimumBalanceRetryDelay
            let clampedDelay = max(pendingDelay, minimumBalanceRetryDelay)
            let nanos = UInt64(clampedDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
        }
    }

    private func performBalanceFetch(chainId: String, fetcher: @escaping () async throws -> String) async -> Bool {
        if Task.isCancelled { return false }

        if let tracker = balanceBackoff[chainId], tracker.isInBackoff {
            let pendingDelay = tracker.remainingBackoff
            if pendingDelay > 0 {
                let nanos = UInt64(pendingDelay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                if Task.isCancelled { return false }
            }
        }

        do {
            let displayValue = try await fetcher()
            let now = Date()
            cachedBalances[chainId] = CachedBalance(value: displayValue, lastUpdated: now)
            balanceStates[chainId] = .loaded(value: displayValue, lastUpdated: now)
            balanceBackoff[chainId] = nil
            // Persist to disk cache for instant cold-start display
            AssetCache.shared.cacheBalance(chainId: chainId, balance: displayValue, numericValue: extractNumericBalance(displayValue))
            // Notify for persistent cache saving
            NotificationCenter.default.post(name: .balanceUpdated, object: nil, userInfo: [
                "chainId": chainId,
                "balance": displayValue
            ])
            return true
        } catch {
            var tracker = balanceBackoff[chainId] ?? BackoffTracker()
            let retryDelay = tracker.registerFailure()
            balanceBackoff[chainId] = tracker
            let message = friendlyBackoffMessage(for: error, retryDelay: retryDelay)
            if let cache = cachedBalances[chainId] {
                balanceStates[chainId] = .stale(value: cache.value, lastUpdated: cache.lastUpdated, message: message)
            } else {
                balanceStates[chainId] = .failed(message)
            }
            #if DEBUG
            print("⚠️ Balance fetch error for \(chainId): \(message) – \(error.localizedDescription)")
            #endif
            return false
        }
    }

    private func friendlyBackoffMessage(for error: Error, retryDelay: TimeInterval) -> String {
        var base: String
        if let balanceError = error as? BalanceFetchError {
            switch balanceError {
            case .invalidStatus(let code) where code == 429:
                base = "Temporarily rate limited"
            case .invalidStatus(let code):
                base = "Service returned status \(code)"
            case .invalidRequest:
                base = "Invalid request"
            case .invalidResponse:
                base = "Unexpected response"
            case .invalidPayload:
                base = "Unreadable data"
            case .rateLimited:
                base = "Rate limited - prices updating soon"
            }
        } else {
            base = error.localizedDescription
        }

        if retryDelay > 0.1 {
            return "\(base). Retrying in \(formatRetryDuration(retryDelay))…"
        }
        return base
    }

    private func formatRetryDuration(_ delay: TimeInterval) -> String {
        if delay >= 10 {
            return "\(Int(delay))s"
        } else {
            return String(format: "%.1fs", delay)
        }
    }
    
    // MARK: - Balance Fetchers
    
    func fetchBitcoinBalance(address: String, isTestnet: Bool = false) async throws -> String {
        let symbol = isTestnet ? "tBTC" : "BTC"
        
        do {
            let btc = try await MultiProviderAPI.shared.fetchBitcoinBalance(address: address, isTestnet: isTestnet)
            return formatCryptoAmount(btc, symbol: symbol, maxFractionDigits: 8)
        } catch {
            #if DEBUG
            print("⚠️ All Bitcoin balance providers failed: \(error.localizedDescription)")
            #endif
            throw error
        }
    }

    func fetchLitecoinBalance(address: String) async throws -> String {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://litecoinspace.org/api/address/\(encodedAddress)") else {
            throw BalanceFetchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            return "0.00000000 LTC"
        }

        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = jsonObject as? [String: Any],
              let chainStats = dictionary["chain_stats"] as? [String: Any] else {
            throw BalanceFetchError.invalidPayload
        }

        let funded = (chainStats["funded_txo_sum"] as? NSNumber)?.doubleValue ?? 0
        let spent = (chainStats["spent_txo_sum"] as? NSNumber)?.doubleValue ?? 0
        let balanceInLitoshis = max(0, funded - spent)
        let ltc = balanceInLitoshis / 100_000_000.0
        return formatCryptoAmount(ltc, symbol: "LTC", maxFractionDigits: 8)
    }

    func fetchSolanaBalance(address: String) async throws -> String {
        if APIConfig.isAlchemyConfigured() {
            do {
                #if DEBUG
                print("📡 Trying Alchemy for SOL balance...")
                #endif
                let sol = try await MultiProviderAPI.shared.fetchSolanaBalanceViaAlchemy(address: address)
                return formatCryptoAmount(sol, symbol: "SOL", maxFractionDigits: 6)
            } catch {
                #if DEBUG
                print("⚠️ Alchemy SOL failed: \(error.localizedDescription)")
                #endif
            }
        }
        
        do {
            let sol = try await MultiProviderAPI.shared.fetchSolanaBalance(address: address)
            return formatCryptoAmount(sol, symbol: "SOL", maxFractionDigits: 6)
        } catch {
            #if DEBUG
            print("⚠️ All Solana balance providers failed: \(error.localizedDescription)")
            #endif
            throw error
        }
    }

    func fetchXrpBalance(address: String) async throws -> String {
        // Try official Ripple Data API first
        if let balance = try? await fetchXrpBalanceViaRippleDataAPI(address: address) {
            return balance
        }
        
        // Fallback to XRP Ledger RPC
        if let balance = try? await fetchXrpBalanceViaRippleRPC(address: address) {
            return balance
        }
        
        // Last resort: XRPScan API
        return try await fetchXrpBalanceViaXrpScan(address: address)
    }

    private func fetchXrpBalanceViaRippleDataAPI(address: String) async throws -> String {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://data.ripple.com/v2/accounts/\(encodedAddress)/balances") else {
            throw BalanceFetchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = jsonObject as? [String: Any],
              let balances = dictionary["balances"] as? [[String: Any]] else {
            throw BalanceFetchError.invalidPayload
        }

        for balanceEntry in balances {
            if let currency = balanceEntry["currency"] as? String, currency == "XRP",
               let valueString = balanceEntry["value"] as? String,
               let value = Double(valueString) {
                return formatCryptoAmount(value, symbol: "XRP", maxFractionDigits: 6)
            }
        }

        return "0.000000 XRP"
    }

    private func fetchXrpBalanceViaRippleRPC(address: String) async throws -> String {
        let endpoints = [
            "https://s1.ripple.com:51234/",
            "https://s2.ripple.com:51234/",
            "https://xrplcluster.com/"
        ]
        
        for endpoint in endpoints {
            do {
                return try await requestXrpBalance(address: address, endpoint: endpoint)
            } catch {
                continue
            }
        }
        
        throw BalanceFetchError.invalidResponse
    }

    private func requestXrpBalance(address: String, endpoint: String) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw BalanceFetchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try xrplAccountInfoPayload(address: address)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }

        if xrplResponseIndicatesUnfundedAccount(data) {
            return "0.000000 XRP"
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = jsonObject as? [String: Any],
              let result = dictionary["result"] as? [String: Any],
              let accountData = result["account_data"] as? [String: Any],
              let balanceString = accountData["Balance"] as? String,
              let balanceDrops = Double(balanceString) else {
            throw BalanceFetchError.invalidPayload
        }

        let xrp = balanceDrops / 1_000_000.0
        return formatCryptoAmount(xrp, symbol: "XRP", maxFractionDigits: 6)
    }

    private func fetchXrpBalanceViaXrpScan(address: String) async throws -> String {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.xrpscan.com/api/v1/account/\(encodedAddress)") else {
            throw BalanceFetchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            return "0.000000 XRP"
        }

        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = jsonObject as? [String: Any] else {
            throw BalanceFetchError.invalidPayload
        }

        if let xrpBalance = dictionary["xrpBalance"] as? Double {
            return formatCryptoAmount(xrpBalance, symbol: "XRP", maxFractionDigits: 6)
        } else if let xrpBalanceString = dictionary["xrpBalance"] as? String,
                  let xrpBalance = Double(xrpBalanceString) {
            return formatCryptoAmount(xrpBalance, symbol: "XRP", maxFractionDigits: 6)
        }

        return "0.000000 XRP"
    }

    private func xrplAccountInfoPayload(address: String) throws -> Data {
        let payload: [String: Any] = [
            "method": "account_info",
            "params": [
                [
                    "account": address,
                    "strict": true,
                    "ledger_index": "current",
                    "queue": true
                ]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [])
    }

    private func xrplResponseIndicatesUnfundedAccount(_ data: Data) -> Bool {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
              let dictionary = jsonObject as? [String: Any],
              let result = dictionary["result"] as? [String: Any] else {
            return false
        }

        if let error = result["error"] as? String {
            return error == "actNotFound" || error == "Account not found."
        }

        if let errorMessage = result["error_message"] as? String {
            return errorMessage.contains("not found") || errorMessage.contains("actNotFound")
        }

        return false
    }

    func fetchBnbBalance(address: String) async throws -> String {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.bscscan.com/api?module=account&action=balance&address=\(encodedAddress)&tag=latest") else {
            throw BalanceFetchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = jsonObject as? [String: Any],
              let status = dictionary["status"] as? String, status == "1",
              let resultString = dictionary["result"] as? String,
              let resultWei = Decimal(string: resultString) else {
            if let dictionary = jsonObject as? [String: Any],
               let message = dictionary["message"] as? String,
               message.lowercased().contains("rate limit") {
                throw BalanceFetchError.rateLimited
            }
            throw BalanceFetchError.invalidPayload
        }

        let bnb = decimalDividingByPowerOfTen(resultWei, exponent: 18)
        let bnbDouble = NSDecimalNumber(decimal: bnb).doubleValue
        return formatCryptoAmount(bnbDouble, symbol: "BNB", maxFractionDigits: 6)
    }

    func fetchEthereumBalanceViaInfura(address: String) async throws -> String {
        // Try Alchemy FIRST if configured (most reliable)
        if APIConfig.isAlchemyConfigured() {
            do {
                #if DEBUG
                print("📡 Trying Alchemy for ETH balance...")
                #endif
                return try await fetchEthereumBalanceViaAlchemy(address: address)
            } catch {
                #if DEBUG
                print("⚠️ Alchemy ETH failed: \(error.localizedDescription)")
                #endif
            }
        }
        
        // Use MultiProviderAPI with automatic fallbacks
        do {
            let eth = try await MultiProviderAPI.shared.fetchEthereumBalance(address: address)
            return formatCryptoAmount(eth, symbol: "ETH", maxFractionDigits: 6)
        } catch {
            return try await fetchEthereumBalanceViaBlockchair(address: address)
        }
    }

    private func fetchEthereumBalanceViaAlchemy(address: String) async throws -> String {
        guard let url = URL(string: APIConfig.alchemyMainnetURL) else {
            throw BalanceFetchError.invalidRequest
        }

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getBalance",
            "params": [address, "latest"],
            "id": 1
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }

        let ethDecimal = try BalanceResponseParser.parseAlchemyETHBalance(from: responseData)
        let eth = NSDecimalNumber(decimal: ethDecimal).doubleValue
        return formatCryptoAmount(eth, symbol: "ETH", maxFractionDigits: 6)
    }

    private func fetchEthereumBalanceViaBlockchair(address: String) async throws -> String {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.blockchair.com/ethereum/dashboards/address/\(encodedAddress)") else {
            throw BalanceFetchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = jsonObject as? [String: Any],
              let dataDict = dictionary["data"] as? [String: Any],
              let addressData = dataDict[address.lowercased()] as? [String: Any],
              let addressInfo = addressData["address"] as? [String: Any],
              let balanceWei = addressInfo["balance"] as? NSNumber else {
            throw BalanceFetchError.invalidPayload
        }

        let weiDecimal = Decimal(balanceWei.doubleValue)
        let eth = decimalDividingByPowerOfTen(weiDecimal, exponent: 18)
        let ethDouble = NSDecimalNumber(decimal: eth).doubleValue
        return formatCryptoAmount(ethDouble, symbol: "ETH", maxFractionDigits: 6)
    }

    func fetchEthereumSepoliaBalance(address: String) async throws -> String {
        guard let url = URL(string: APIConfig.alchemySepoliaURL) else {
            throw BalanceFetchError.invalidRequest
        }
        
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getBalance",
            "params": [address, "latest"],
            "id": 1
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }
        
        let ethDecimal = try BalanceResponseParser.parseAlchemyETHBalance(from: responseData)
        let eth = NSDecimalNumber(decimal: ethDecimal).doubleValue
        return formatCryptoAmount(eth, symbol: "ETH", maxFractionDigits: 6)
    }

    func fetchERC20Balance(address: String, contractAddress: String, decimals: Int, symbol: String) async throws -> String {
        if APIConfig.isAlchemyConfigured() {
            return try await fetchERC20BalanceViaAlchemy(address: address, contractAddress: contractAddress, decimals: decimals, symbol: symbol)
        }
        return try await fetchERC20BalanceViaBlockchair(address: address, contractAddress: contractAddress, decimals: decimals, symbol: symbol)
    }

    private func fetchERC20BalanceViaAlchemy(address: String, contractAddress: String, decimals: Int, symbol: String) async throws -> String {
        guard let url = URL(string: APIConfig.alchemyMainnetURL) else {
            throw BalanceFetchError.invalidRequest
        }

        let dataField = "0x70a08231" + normalizeAddressForCall(address)
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_call",
            "params": [
                ["to": contractAddress, "data": dataField],
                "latest"
            ],
            "id": 1
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }

        let jsonObject = try JSONSerialization.jsonObject(with: responseData, options: [])
        guard let dictionary = jsonObject as? [String: Any],
              let resultHex = dictionary["result"] as? String else {
            throw BalanceFetchError.invalidPayload
        }

        let rawBalance = decimalFromHex(resultHex)
        let balance = decimalDividingByPowerOfTen(rawBalance, exponent: decimals)
        let balanceDouble = NSDecimalNumber(decimal: balance).doubleValue
        return formatCryptoAmount(balanceDouble, symbol: symbol, maxFractionDigits: min(decimals, 6))
    }

    private func fetchERC20BalanceViaBlockchair(address: String, contractAddress: String, decimals: Int, symbol: String) async throws -> String {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.blockchair.com/ethereum/erc-20/\(contractAddress)/dashboards/address/\(encodedAddress)") else {
            throw BalanceFetchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = jsonObject as? [String: Any],
              let dataDict = dictionary["data"] as? [String: Any],
              let addressData = dataDict[address.lowercased()] as? [String: Any],
              let balanceString = addressData["balance"] as? String,
              let rawBalance = Decimal(string: balanceString) else {
            throw BalanceFetchError.invalidPayload
        }

        let balance = decimalDividingByPowerOfTen(rawBalance, exponent: decimals)
        let balanceDouble = NSDecimalNumber(decimal: balance).doubleValue
        return formatCryptoAmount(balanceDouble, symbol: symbol, maxFractionDigits: min(decimals, 6))
    }

    // MARK: - Utilities
    
    func formatCryptoAmount(_ amount: Double, symbol: String, maxFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxFractionDigits
        let formatted = formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.\(maxFractionDigits)f", amount)
        return "\(formatted) \(symbol)"
    }

    private func decimalFromHex(_ hexString: String) -> Decimal {
        var hex = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
        hex = hex.trimmingCharacters(in: .whitespaces)
        guard !hex.isEmpty else { return 0 }

        var result: Decimal = 0
        for char in hex.lowercased() {
            result *= 16
            if let digit = Int(String(char), radix: 16) {
                result += Decimal(digit)
            }
        }
        return result
    }

    private func decimalDividingByPowerOfTen(_ value: Decimal, exponent: Int) -> Decimal {
        var result = value
        for _ in 0..<exponent {
            result /= 10
        }
        return result
    }

    private func normalizeAddressForCall(_ address: String) -> String {
        let cleanAddress = address.hasPrefix("0x") ? String(address.dropFirst(2)) : address
        let filtered = cleanAddress.filter { $0.isHexDigit }
        let limited = filtered.count > 64 ? String(filtered.suffix(64)) : filtered
        guard limited.count < 64 else { return limited }
        return String(repeating: "0", count: 64 - limited.count) + limited
    }
    
    // MARK: - Numeric Extraction
    
    func extractNumericAmount(from state: ChainBalanceState) -> Double? {
        switch state {
        case .loaded(let value, _), .refreshing(let value, _), .stale(let value, _, _):
            return extractNumericBalance(value)
        case .idle, .loading, .failed:
            return nil
        }
    }
    
    /// Parse a numeric value from a formatted balance string like "0.00123 BTC"
    func extractNumericBalance(_ displayValue: String) -> Double {
        let numericString = displayValue.components(separatedBy: CharacterSet.decimalDigits.inverted.subtracting(CharacterSet(charactersIn: ".")))
            .joined()
        return Double(numericString) ?? 0
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let balanceUpdated = Notification.Name("balanceUpdated")
}
