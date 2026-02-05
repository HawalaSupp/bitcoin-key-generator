import Foundation

// MARK: - Balance Fetch Service

/// Centralized service for fetching cryptocurrency balances across all chains
/// with caching, rate limiting, retry logic, and proper error handling.
/// Extracted from ContentView.swift per ROADMAP-03 feature module extraction.
@MainActor
final class BalanceFetchService: ObservableObject {
    static let shared = BalanceFetchService()
    
    // MARK: - Published State
    
    @Published var balanceStates: [String: ChainBalanceState] = [:]
    @Published var isLoading = false
    
    // MARK: - Cache
    
    private var cachedBalances: [String: CachedBalance] = [:]
    private var balanceBackoff: [String: BackoffTracker] = [:]
    private var fetchTasks: [String: Task<Void, Never>] = [:]
    
    // MARK: - Configuration
    
    private let minimumRetryDelay: TimeInterval = 0.5
    private let cacheDuration: TimeInterval = 60 // 1 minute
    
    private init() {
        loadCachedBalances()
    }
    
    // MARK: - Public API
    
    /// Fetch balances for all chains from the provided keys
    func fetchAllBalances(from keys: AllKeys) {
        cancelAllFetchTasks()
        balanceBackoff.removeAll()
        isLoading = true
        
        // Group 1: BlockCypher APIs (rate limited, must be spaced out)
        scheduleBalanceFetch(for: "bitcoin") {
            try await self.fetchBitcoinBalance(address: keys.bitcoin.address)
        }
        
        scheduleBalanceFetch(for: "bitcoin-testnet", delay: 0.5) {
            try await self.fetchBitcoinBalance(address: keys.bitcoinTestnet.address, isTestnet: true)
        }
        
        scheduleBalanceFetch(for: "litecoin", delay: 1.0) {
            try await self.fetchLitecoinBalance(address: keys.litecoin.address)
        }
        
        // Group 2: Independent APIs (can run in parallel)
        scheduleBalanceFetch(for: "solana") {
            try await self.fetchSolanaBalance(address: keys.solana.publicKeyBase58)
        }
        
        scheduleBalanceFetch(for: "xrp") {
            try await self.fetchXRPBalance(address: keys.xrp.classicAddress)
        }
        
        scheduleBalanceFetch(for: "bnb") {
            try await self.fetchBNBBalance(address: keys.bnb.address)
        }
        
        // Group 3: Ethereum and ERC-20 tokens
        let ethAddress = keys.ethereum.address
        scheduleBalanceFetch(for: "ethereum") {
            try await self.fetchEthereumBalance(address: ethAddress)
        }
        
        scheduleBalanceFetch(for: "ethereum-sepolia", delay: 0.3) {
            try await self.fetchEthereumSepoliaBalance(address: ethAddress)
        }
        
        // ERC-20 Tokens
        scheduleBalanceFetch(for: "usdt-erc20", delay: 0.7) {
            try await self.fetchERC20Balance(
                address: ethAddress,
                contractAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
                decimals: 6,
                symbol: "USDT"
            )
        }
        
        scheduleBalanceFetch(for: "usdc-erc20", delay: 1.4) {
            try await self.fetchERC20Balance(
                address: ethAddress,
                contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
                decimals: 6,
                symbol: "USDC"
            )
        }
        
        scheduleBalanceFetch(for: "dai-erc20", delay: 2.1) {
            try await self.fetchERC20Balance(
                address: ethAddress,
                contractAddress: "0x6B175474E89094C44Da98b954EedeAC495271d0F",
                decimals: 18,
                symbol: "DAI"
            )
        }
    }
    
    /// Refresh a single chain's balance
    func refreshBalance(for chainId: String, address: String) {
        cancelFetchTask(for: chainId)
        balanceBackoff[chainId] = nil
        
        switch chainId {
        case "bitcoin":
            scheduleBalanceFetch(for: chainId) { try await self.fetchBitcoinBalance(address: address) }
        case "bitcoin-testnet":
            scheduleBalanceFetch(for: chainId) { try await self.fetchBitcoinBalance(address: address, isTestnet: true) }
        case "litecoin":
            scheduleBalanceFetch(for: chainId) { try await self.fetchLitecoinBalance(address: address) }
        case "solana":
            scheduleBalanceFetch(for: chainId) { try await self.fetchSolanaBalance(address: address) }
        case "xrp":
            scheduleBalanceFetch(for: chainId) { try await self.fetchXRPBalance(address: address) }
        case "bnb":
            scheduleBalanceFetch(for: chainId) { try await self.fetchBNBBalance(address: address) }
        case "ethereum":
            scheduleBalanceFetch(for: chainId) { try await self.fetchEthereumBalance(address: address) }
        case "ethereum-sepolia":
            scheduleBalanceFetch(for: chainId) { try await self.fetchEthereumSepoliaBalance(address: address) }
        default:
            break
        }
    }
    
    /// Cancel all pending fetch tasks
    func cancelAllFetchTasks() {
        for (_, task) in fetchTasks {
            task.cancel()
        }
        fetchTasks.removeAll()
    }
    
    // MARK: - Bitcoin Balance
    
    private func fetchBitcoinBalance(address: String, isTestnet: Bool = false) async throws -> String {
        guard !address.isEmpty else { return "0 BTC" }
        
        let baseURL = isTestnet
            ? "https://blockstream.info/testnet/api/address/\(address)"
            : "https://blockstream.info/api/address/\(address)"
        
        guard let url = URL(string: baseURL) else {
            throw BalanceFetchError.invalidRequest
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }
        
        if httpResponse.statusCode == 429 {
            throw BalanceFetchError.rateLimited
        }
        
        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stats = json["chain_stats"] as? [String: Any],
              let fundedSum = stats["funded_txo_sum"] as? Int,
              let spentSum = stats["spent_txo_sum"] as? Int else {
            throw BalanceFetchError.invalidPayload
        }
        
        let balanceSats = fundedSum - spentSum
        let balanceBTC = Double(balanceSats) / 100_000_000.0
        let symbol = isTestnet ? "tBTC" : "BTC"
        return formatCryptoAmount(balanceBTC, symbol: symbol, maxFractionDigits: 8)
    }
    
    // MARK: - Litecoin Balance
    
    private func fetchLitecoinBalance(address: String) async throws -> String {
        guard !address.isEmpty else { return "0 LTC" }
        
        guard let url = URL(string: "https://litecoinspace.org/api/address/\(address)") else {
            throw BalanceFetchError.invalidRequest
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }
        
        if httpResponse.statusCode == 429 {
            throw BalanceFetchError.rateLimited
        }
        
        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stats = json["chain_stats"] as? [String: Any],
              let fundedSum = stats["funded_txo_sum"] as? Int,
              let spentSum = stats["spent_txo_sum"] as? Int else {
            throw BalanceFetchError.invalidPayload
        }
        
        let balanceSats = fundedSum - spentSum
        let balanceLTC = Double(balanceSats) / 100_000_000.0
        return formatCryptoAmount(balanceLTC, symbol: "LTC", maxFractionDigits: 8)
    }
    
    // MARK: - Solana Balance
    
    private func fetchSolanaBalance(address: String) async throws -> String {
        guard !address.isEmpty else { return "0 SOL" }
        
        guard let url = URL(string: "https://api.mainnet-beta.solana.com") else {
            throw BalanceFetchError.invalidRequest
        }
        
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getBalance",
            "params": [address]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 15
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidResponse
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let value = result["value"] as? Int else {
            throw BalanceFetchError.invalidPayload
        }
        
        let balanceSOL = Double(value) / 1_000_000_000.0
        return formatCryptoAmount(balanceSOL, symbol: "SOL", maxFractionDigits: 9)
    }
    
    // MARK: - XRP Balance
    
    private func fetchXRPBalance(address: String) async throws -> String {
        guard !address.isEmpty else { return "0 XRP" }
        
        // Try multiple endpoints for reliability
        let endpoints = [
            "https://xrplcluster.com/",
            "https://s1.ripple.com:51234/",
            "https://s2.ripple.com:51234/"
        ]
        
        var lastError: Error = BalanceFetchError.invalidResponse
        
        for endpoint in endpoints {
            do {
                return try await requestXRPBalance(address: address, endpoint: endpoint)
            } catch {
                lastError = error
                continue
            }
        }
        
        throw lastError
    }
    
    private func requestXRPBalance(address: String, endpoint: String) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw BalanceFetchError.invalidRequest
        }
        
        let payload: [String: Any] = [
            "method": "account_info",
            "params": [[
                "account": address,
                "ledger_index": "validated"
            ]]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 10
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidResponse
        }
        
        // Check for unfunded account
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let result = json["result"] as? [String: Any],
           let error = result["error"] as? String,
           error == "actNotFound" {
            return "0 XRP"
        }
        
        let balanceDecimal = try BalanceResponseParser.parseXRPLBalance(from: data)
        let balance = NSDecimalNumber(decimal: balanceDecimal).doubleValue
        return formatCryptoAmount(balance, symbol: "XRP", maxFractionDigits: 6)
    }
    
    // MARK: - BNB Balance
    
    private func fetchBNBBalance(address: String) async throws -> String {
        guard !address.isEmpty else { return "0 BNB" }
        
        guard let url = URL(string: "https://api.bscscan.com/api?module=account&action=balance&address=\(address)&tag=latest") else {
            throw BalanceFetchError.invalidRequest
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidResponse
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? String,
              let balanceWei = Decimal(string: result) else {
            throw BalanceFetchError.invalidPayload
        }
        
        let balanceBNB = NSDecimalNumber(decimal: balanceWei / Decimal(string: "1000000000000000000")!).doubleValue
        return formatCryptoAmount(balanceBNB, symbol: "BNB", maxFractionDigits: 8)
    }
    
    // MARK: - Ethereum Balance
    
    private func fetchEthereumBalance(address: String) async throws -> String {
        guard !address.isEmpty else { return "0 ETH" }
        
        // Try Ethplorer first (has good free tier)
        guard let url = URL(string: "https://api.ethplorer.io/getAddressInfo/\(address)?apiKey=freekey") else {
            throw BalanceFetchError.invalidRequest
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }
        
        if httpResponse.statusCode == 404 {
            return "0 ETH"
        }
        
        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }
        
        let ethResponse = try JSONDecoder().decode(EthplorerAddressResponse.self, from: data)
        return formatCryptoAmount(ethResponse.eth.balance, symbol: "ETH", maxFractionDigits: 6)
    }
    
    private func fetchEthereumSepoliaBalance(address: String) async throws -> String {
        guard !address.isEmpty else { return "0 ETH" }
        
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
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 15
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidResponse
        }
        
        let ethDecimal = try BalanceResponseParser.parseAlchemyETHBalance(from: data)
        let balance = NSDecimalNumber(decimal: ethDecimal).doubleValue
        return formatCryptoAmount(balance, symbol: "ETH", maxFractionDigits: 6)
    }
    
    // MARK: - ERC-20 Token Balance
    
    private func fetchERC20Balance(address: String, contractAddress: String, decimals: Int, symbol: String) async throws -> String {
        guard !address.isEmpty else { return "0 \(symbol)" }
        
        // Use Alchemy for ERC-20 balance
        guard let url = URL(string: APIConfig.alchemyMainnetURL) else {
            throw BalanceFetchError.invalidRequest
        }
        
        // eth_call to balanceOf(address)
        let balanceOfSelector = "0x70a08231"
        let paddedAddress = String(repeating: "0", count: 24) + address.dropFirst(2)
        let callData = balanceOfSelector + paddedAddress
        
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_call",
            "params": [
                ["to": contractAddress, "data": callData],
                "latest"
            ],
            "id": 1
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 15
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidResponse
        }
        
        let balanceDecimal = try BalanceResponseParser.parseAlchemyERC20Balance(from: data, decimals: decimals)
        let balance = NSDecimalNumber(decimal: balanceDecimal).doubleValue
        return formatCryptoAmount(balance, symbol: symbol, maxFractionDigits: min(decimals, 6))
    }
    
    // MARK: - Scheduling & Task Management
    
    private func scheduleBalanceFetch(for chainId: String, delay: TimeInterval = 0, fetcher: @escaping () async throws -> String) {
        cancelFetchTask(for: chainId)
        applyLoadingState(for: chainId)
        
        fetchTasks[chainId] = Task {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            
            guard !Task.isCancelled else { return }
            
            await runBalanceFetchLoop(chainId: chainId, fetcher: fetcher)
        }
    }
    
    private func runBalanceFetchLoop(chainId: String, fetcher: @escaping () async throws -> String) async {
        while !Task.isCancelled {
            let success = await performBalanceFetch(chainId: chainId, fetcher: fetcher)
            
            if success {
                balanceBackoff[chainId] = nil
                break
            }
            
            var tracker = balanceBackoff[chainId] ?? BackoffTracker()
            let retryDelay = tracker.registerFailure()
            balanceBackoff[chainId] = tracker
            
            await MainActor.run {
                let message = "Retry in \(formatRetryDuration(retryDelay))"
                balanceStates[chainId] = .failed(message)
            }
            
            try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
        }
    }
    
    private func performBalanceFetch(chainId: String, fetcher: @escaping () async throws -> String) async -> Bool {
        do {
            let balance = try await fetcher()
            let now = Date()
            
            await MainActor.run {
                balanceStates[chainId] = .loaded(value: balance, lastUpdated: now)
                saveBalanceToCache(chainId: chainId, balance: balance)
            }
            
            return true
        } catch {
            #if DEBUG
            print("[\(chainId)] Balance fetch error: \(error.localizedDescription)")
            #endif
            return false
        }
    }
    
    private func cancelFetchTask(for chainId: String) {
        fetchTasks[chainId]?.cancel()
        fetchTasks[chainId] = nil
    }
    
    private func applyLoadingState(for chainId: String) {
        if let cached = cachedBalances[chainId] {
            balanceStates[chainId] = .refreshing(previous: cached.value, lastUpdated: cached.lastUpdated)
        } else {
            balanceStates[chainId] = .loading
        }
    }
    
    // MARK: - Caching
    
    /// Private wrapper for disk serialization since CachedBalance is not Codable
    private struct SerializableCachedBalance: Codable {
        let value: String
        let lastUpdated: Date
        
        init(from cached: CachedBalance) {
            self.value = cached.value
            self.lastUpdated = cached.lastUpdated
        }
        
        func toCachedBalance() -> CachedBalance {
            CachedBalance(value: value, lastUpdated: lastUpdated)
        }
    }
    
    private func saveBalanceToCache(chainId: String, balance: String) {
        cachedBalances[chainId] = CachedBalance(value: balance, lastUpdated: Date())
        saveCacheToDisk()
    }
    
    private func loadCachedBalances() {
        guard let url = cacheFileURL,
              let data = try? Data(contentsOf: url),
              let serialized = try? JSONDecoder().decode([String: SerializableCachedBalance].self, from: data) else {
            return
        }
        
        cachedBalances = serialized.mapValues { $0.toCachedBalance() }
        
        // Apply cached values to state
        for (chainId, cached) in cachedBalances {
            balanceStates[chainId] = .loaded(value: cached.value, lastUpdated: cached.lastUpdated)
        }
    }
    
    private func saveCacheToDisk() {
        let serialized = cachedBalances.mapValues { SerializableCachedBalance(from: $0) }
        guard let url = cacheFileURL,
              let data = try? JSONEncoder().encode(serialized) else {
            return
        }
        try? data.write(to: url)
    }
    
    private var cacheFileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("balance_cache.json")
    }
    
    // MARK: - Formatting
    
    private func formatCryptoAmount(_ amount: Double, symbol: String, maxFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxFractionDigits
        let formatted = formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.\(maxFractionDigits)f", amount)
        return "\(formatted) \(symbol)"
    }
    
    private func formatRetryDuration(_ delay: TimeInterval) -> String {
        if delay < 60 {
            return "\(Int(delay))s"
        } else {
            let minutes = Int(delay / 60)
            let seconds = Int(delay.truncatingRemainder(dividingBy: 60))
            return seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes)m"
        }
    }
}

// MARK: - Supporting Types

// Using existing types from ChainStates.swift:
// - ChainBalanceState
// - CachedBalance
// - BackoffTracker
// Using existing BalanceFetchError from ChainKeys.swift
