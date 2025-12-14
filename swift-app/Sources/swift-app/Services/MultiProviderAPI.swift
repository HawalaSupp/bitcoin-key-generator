import Foundation

// MARK: - Multi-Provider API Service
/// Provides fallback API endpoints for price data, balances, and sparklines
/// Uses Alchemy as primary provider when API key is available

@MainActor
final class MultiProviderAPI: ObservableObject {
    static let shared = MultiProviderAPI()
    
    // Cached API keys access
    private let apiKeys = APIKeys.shared
    
    // MARK: - Initialization
    
    init() {
        // Initialize Alchemy API key on first launch if not already stored (synchronous)
        initializeAlchemyKey()
        
        // Debug: Print Alchemy status
        if apiKeys.hasAlchemyKey {
            print("🔑 Alchemy API configured and ready")
        } else {
            print("⚠️ Alchemy API key not configured - using public endpoints")
        }
    }
    
    private func initializeAlchemyKey() {
        // Only set if not already in keychain
        if !apiKeys.hasAlchemyKey {
            // Store the key securely in Keychain (one-time setup)
            APIKeys.setAlchemyKey("WcVDqtKyv4UjYvp6vBDK8")
        }
    }
    
    // MARK: - Health Manager Reference
    
    private var healthManager: ProviderHealthManager {
        ProviderHealthManager.shared
    }
    
    // MARK: - Price Providers
    
    /// Fetches prices from multiple providers with automatic fallback
    func fetchPrices() async throws -> [String: Double] {
        // Try CoinCap first (no API key needed, generous limits)
        do {
            print("📊 Trying CoinCap for prices...")
            let prices = try await fetchPricesFromCoinCap()
            healthManager.recordSuccess(for: .coinCap)
            return prices
        } catch {
            print("⚠️ CoinCap failed: \(error.localizedDescription)")
            healthManager.recordFailure(for: .coinCap, error: error)
        }
        
        // Try CryptoCompare second
        do {
            print("📊 Trying CryptoCompare for prices...")
            let prices = try await fetchPricesFromCryptoCompare()
            healthManager.recordSuccess(for: .cryptoCompare)
            return prices
        } catch {
            print("⚠️ CryptoCompare failed: \(error.localizedDescription)")
            healthManager.recordFailure(for: .cryptoCompare, error: error)
        }
        
        // Finally try CoinGecko (most likely to be rate limited)
        print("📊 Trying CoinGecko for prices...")
        do {
            let prices = try await fetchPricesFromCoinGecko()
            healthManager.recordSuccess(for: .coinGecko)
            return prices
        } catch {
            healthManager.recordFailure(for: .coinGecko, error: error)
            throw error
        }
    }
    
    // MARK: - Alchemy Ethereum Balance
    
    /// Fetch Ethereum balance using Alchemy (primary) with fallbacks
    func fetchEthereumBalanceViaAlchemy(address: String) async throws -> Double {
        // Try Alchemy first if key is available
        if let alchemyURL = apiKeys.alchemyBaseURL(for: APIKeys.AlchemyChain.ethereumMainnet) {
            do {
                print("📡 Fetching ETH balance from Alchemy...")
                let balance = try await fetchEthBalanceFromRPC(address: address, endpoint: alchemyURL)
                healthManager.recordSuccess(for: .alchemy)
                return balance
            } catch {
                print("⚠️ Alchemy ETH balance failed: \(error.localizedDescription)")
                healthManager.recordFailure(for: .alchemy, error: error)
            }
        }
        
        // Fallback to public RPCs
        return try await fetchEthereumBalance(address: address)
    }
    
    // MARK: - Alchemy Solana Balance
    
    /// Fetch Solana balance using Alchemy (primary) with fallbacks
    func fetchSolanaBalanceViaAlchemy(address: String) async throws -> Double {
        // Try Alchemy first if key is available
        if let alchemyURL = apiKeys.alchemyBaseURL(for: APIKeys.AlchemyChain.solanaMainnet) {
            do {
                print("📡 Fetching SOL balance from Alchemy...")
                let balance = try await fetchSolBalanceFromAlchemy(url: alchemyURL, address: address)
                healthManager.recordSuccess(for: .alchemy)
                return balance
            } catch {
                print("⚠️ Alchemy SOL balance failed: \(error.localizedDescription)")
                healthManager.recordFailure(for: .alchemy, error: error)
            }
        }
        
        // Fallback to public RPCs
        return try await fetchSolanaBalance(address: address)
    }
    
    private func fetchSolBalanceFromAlchemy(url: String, address: String) async throws -> Double {
        guard let rpcURL = URL(string: url) else {
            throw APIError.invalidRequest
        }
        
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("HawalaApp/2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getBalance",
            "params": [address]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        // Debug: Print response status and body for troubleshooting
        if httpResponse.statusCode != 200 {
            if let responseBody = String(data: data, encoding: .utf8) {
                print("⚠️ Alchemy SOL HTTP \(httpResponse.statusCode): \(responseBody.prefix(200))")
            }
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.parseError
        }
        
        // Check for error response
        if let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Unknown error"
            print("⚠️ Alchemy SOL API error: \(message)")
            throw APIError.apiError(message)
        }
        
        guard let result = json["result"] as? [String: Any],
              let lamports = result["value"] as? Int64 else {
            if let responseBody = String(data: data, encoding: .utf8) {
                print("⚠️ Alchemy SOL parse failed: \(responseBody.prefix(300))")
            }
            throw APIError.parseError
        }
        
        // Convert lamports to SOL (1 SOL = 1,000,000,000 lamports)
        let solBalance = Double(lamports) / 1_000_000_000.0
        print("✅ Alchemy SOL balance: \(solBalance)")
        return solBalance
    }
    
    // MARK: - CoinCap API (Free, generous limits)
    private func fetchPricesFromCoinCap() async throws -> [String: Double] {
        let url = URL(string: "https://api.coincap.io/v2/assets?ids=bitcoin,ethereum,litecoin,monero,solana,xrp,binance-coin")!
        
        var request = URLRequest(url: url)
        request.setValue("HawalaApp/2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            throw APIError.parseError
        }
        
        var prices: [String: Double] = [:]
        
        for asset in dataArray {
            guard let id = asset["id"] as? String,
                  let priceString = asset["priceUsd"] as? String,
                  let price = Double(priceString) else { continue }
            
            // Map CoinCap IDs to our chain IDs
            switch id {
            case "bitcoin": prices["bitcoin"] = price
            case "ethereum": prices["ethereum"] = price
            case "litecoin": prices["litecoin"] = price
            case "monero": prices["monero"] = price
            case "solana": prices["solana"] = price
            case "xrp": prices["ripple"] = price
            case "binance-coin": prices["binancecoin"] = price
            default: break
            }
        }
        
        guard !prices.isEmpty else {
            throw APIError.noData
        }
        
        print("✅ CoinCap returned \(prices.count) prices")
        return prices
    }
    
    // MARK: - CryptoCompare API (Free tier available)
    private func fetchPricesFromCryptoCompare() async throws -> [String: Double] {
        let url = URL(string: "https://min-api.cryptocompare.com/data/pricemulti?fsyms=BTC,ETH,LTC,XMR,SOL,XRP,BNB&tsyms=USD")!
        
        var request = URLRequest(url: url)
        request.setValue("HawalaApp/2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.parseError
        }
        
        var prices: [String: Double] = [:]
        
        // Map symbols to chain IDs
        let symbolMap = [
            "BTC": "bitcoin",
            "ETH": "ethereum", 
            "LTC": "litecoin",
            "XMR": "monero",
            "SOL": "solana",
            "XRP": "ripple",
            "BNB": "binancecoin"
        ]
        
        for (symbol, chainId) in symbolMap {
            if let priceData = json[symbol] as? [String: Any],
               let usdPrice = priceData["USD"] as? Double {
                prices[chainId] = usdPrice
            }
        }
        
        guard !prices.isEmpty else {
            throw APIError.noData
        }
        
        print("✅ CryptoCompare returned \(prices.count) prices")
        return prices
    }
    
    // MARK: - CoinGecko API (Most restricted, use as last resort)
    private func fetchPricesFromCoinGecko() async throws -> [String: Double] {
        let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,litecoin,monero,solana,ripple,binancecoin&vs_currencies=usd")!
        
        var request = URLRequest(url: url)
        request.setValue("HawalaApp/2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        if httpResponse.statusCode == 429 {
            throw APIError.rateLimited
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.parseError
        }
        
        var prices: [String: Double] = [:]
        
        let coinIds = ["bitcoin", "ethereum", "litecoin", "monero", "solana", "ripple", "binancecoin"]
        for coinId in coinIds {
            if let coinData = json[coinId] as? [String: Any],
               let usdPrice = coinData["usd"] as? Double {
                prices[coinId] = usdPrice
            }
        }
        
        guard !prices.isEmpty else {
            throw APIError.noData
        }
        
        print("✅ CoinGecko returned \(prices.count) prices")
        return prices
    }
    
    // MARK: - Sparkline Data with Fallbacks
    
    func fetchSparkline(for chainId: String) async throws -> [Double] {
        let coinCapId = coinCapIdFor(chainId)
        
        // Try CoinCap first
        do {
            return try await fetchSparklineFromCoinCap(coinId: coinCapId)
        } catch {
            print("⚠️ CoinCap sparkline failed for \(chainId): \(error.localizedDescription)")
        }
        
        // Fallback to CoinGecko
        let coinGeckoId = coinGeckoIdFor(chainId)
        return try await fetchSparklineFromCoinGecko(coinId: coinGeckoId)
    }
    
    private func fetchSparklineFromCoinCap(coinId: String) async throws -> [Double] {
        // CoinCap provides 24h history
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let dayAgo = now - (24 * 60 * 60 * 1000)
        
        let url = URL(string: "https://api.coincap.io/v2/assets/\(coinId)/history?interval=h1&start=\(dayAgo)&end=\(now)")!
        
        var request = URLRequest(url: url)
        request.setValue("HawalaApp/2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            throw APIError.parseError
        }
        
        let prices = dataArray.compactMap { item -> Double? in
            if let priceStr = item["priceUsd"] as? String {
                return Double(priceStr)
            }
            return nil
        }
        
        guard !prices.isEmpty else {
            throw APIError.noData
        }
        
        return prices
    }
    
    private func fetchSparklineFromCoinGecko(coinId: String) async throws -> [Double] {
        let url = URL(string: "https://api.coingecko.com/api/v3/coins/\(coinId)/market_chart?vs_currency=usd&days=1")!
        
        var request = URLRequest(url: url)
        request.setValue("HawalaApp/2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        if httpResponse.statusCode == 429 {
            throw APIError.rateLimited
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let prices = json["prices"] as? [[Any]] else {
            throw APIError.parseError
        }
        
        return prices.compactMap { $0.last as? Double }
    }
    
    // MARK: - Balance Fetching with Fallbacks
    
    func fetchBitcoinBalance(address: String, isTestnet: Bool = false) async throws -> Double {
        let errors: [Error] = []
        
        // Try mempool.space first (most reliable)
        do {
            let balance = try await fetchBitcoinBalanceFromMempool(address: address, isTestnet: isTestnet)
            healthManager.recordSuccess(for: .mempool)
            return balance
        } catch {
            print("⚠️ Mempool.space failed: \(error.localizedDescription)")
            healthManager.recordFailure(for: .mempool, error: error)
        }
        
        // Try Blockstream second
        if !isTestnet {
            do {
                let balance = try await fetchBitcoinBalanceFromBlockstream(address: address)
                healthManager.recordSuccess(for: .blockchair) // Using blockchair as generic blockchain provider
                return balance
            } catch {
                print("⚠️ Blockstream failed: \(error.localizedDescription)")
            }
        }
        
        // Try BlockCypher last
        do {
            let balance = try await fetchBitcoinBalanceFromBlockCypher(address: address, isTestnet: isTestnet)
            return balance
        } catch {
            print("⚠️ BlockCypher failed: \(error.localizedDescription)")
        }
        
        throw APIError.allProvidersFailed(errors)
    }
    
    private func fetchBitcoinBalanceFromMempool(address: String, isTestnet: Bool) async throws -> Double {
        let baseURL = isTestnet ? "https://mempool.space/testnet/api" : "https://mempool.space/api"
        guard let url = URL(string: "\(baseURL)/address/\(address)") else {
            throw APIError.invalidRequest
        }
        
        var request = URLRequest(url: url)
        request.setValue("HawalaApp/2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        if httpResponse.statusCode == 404 {
            return 0.0 // Address not found = 0 balance
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chainStats = json["chain_stats"] as? [String: Any] else {
            throw APIError.parseError
        }
        
        let funded = (chainStats["funded_txo_sum"] as? NSNumber)?.doubleValue ?? 0
        let spent = (chainStats["spent_txo_sum"] as? NSNumber)?.doubleValue ?? 0
        return max(0, funded - spent) / 100_000_000.0
    }
    
    private func fetchBitcoinBalanceFromBlockstream(address: String) async throws -> Double {
        guard let url = URL(string: "https://blockstream.info/api/address/\(address)") else {
            throw APIError.invalidRequest
        }
        
        var request = URLRequest(url: url)
        request.setValue("HawalaApp/2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        if httpResponse.statusCode == 404 {
            return 0.0
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chainStats = json["chain_stats"] as? [String: Any] else {
            throw APIError.parseError
        }
        
        let funded = (chainStats["funded_txo_sum"] as? NSNumber)?.doubleValue ?? 0
        let spent = (chainStats["spent_txo_sum"] as? NSNumber)?.doubleValue ?? 0
        return max(0, funded - spent) / 100_000_000.0
    }
    
    private func fetchBitcoinBalanceFromBlockCypher(address: String, isTestnet: Bool) async throws -> Double {
        let baseURL = isTestnet ? "https://api.blockcypher.com/v1/btc/test3" : "https://api.blockcypher.com/v1/btc/main"
        guard let url = URL(string: "\(baseURL)/addrs/\(address)/balance") else {
            throw APIError.invalidRequest
        }
        
        var request = URLRequest(url: url)
        request.setValue("HawalaApp/2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        if httpResponse.statusCode == 429 {
            throw APIError.rateLimited
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let balance = json["balance"] as? NSNumber else {
            throw APIError.parseError
        }
        
        return balance.doubleValue / 100_000_000.0
    }
    
    // MARK: - Solana Balance with Fallbacks
    
    func fetchSolanaBalance(address: String) async throws -> Double {
        // Try Alchemy FIRST if key is available
        if let alchemyURL = apiKeys.alchemyBaseURL(for: APIKeys.AlchemyChain.solanaMainnet) {
            do {
                print("📡 Fetching SOL balance from Alchemy...")
                let balance = try await fetchSolanaBalanceFromRPC(address: address, endpoint: alchemyURL)
                print("✅ Alchemy SOL balance: \(balance)")
                return balance
            } catch {
                print("⚠️ Alchemy SOL failed: \(error.localizedDescription)")
            }
        }
        
        // List of public Solana RPC endpoints as fallback
        let endpoints = [
            "https://api.mainnet-beta.solana.com",
            "https://solana-api.projectserum.com",
            "https://rpc.ankr.com/solana"
        ]
        
        for endpoint in endpoints {
            do {
                return try await fetchSolanaBalanceFromRPC(address: address, endpoint: endpoint)
            } catch {
                print("⚠️ Solana RPC \(endpoint) failed: \(error.localizedDescription)")
                continue
            }
        }
        
        throw APIError.allProvidersFailed([])
    }
    
    private func fetchSolanaBalanceFromRPC(address: String, endpoint: String) async throws -> Double {
        guard let url = URL(string: endpoint) else {
            throw APIError.invalidRequest
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("HawalaApp/2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getBalance",
            "params": [address]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let value = result["value"] as? NSNumber else {
            throw APIError.parseError
        }
        
        return value.doubleValue / 1_000_000_000.0
    }
    
    // MARK: - Ethereum Balance with Fallbacks
    
    func fetchEthereumBalance(address: String) async throws -> Double {
        // Debug: Check Alchemy status
        print("🔍 Checking Alchemy for ETH: hasKey=\(apiKeys.hasAlchemyKey)")
        
        // Try Alchemy FIRST if key is available
        if let alchemyURL = apiKeys.alchemyBaseURL(for: APIKeys.AlchemyChain.ethereumMainnet) {
            do {
                print("📡 Fetching ETH balance from Alchemy: \(alchemyURL.prefix(50))...")
                let balance = try await fetchEthBalanceFromRPC(address: address, endpoint: alchemyURL)
                print("✅ Alchemy ETH balance: \(balance)")
                return balance
            } catch {
                print("⚠️ Alchemy ETH failed: \(error.localizedDescription)")
            }
        } else {
            print("⚠️ Alchemy URL not available for ETH")
        }
        
        // Try public RPC endpoints as fallback
        let endpoints = [
            "https://eth.llamarpc.com",
            "https://rpc.ankr.com/eth",
            "https://ethereum.publicnode.com",
            "https://1rpc.io/eth"
        ]
        
        for endpoint in endpoints {
            do {
                return try await fetchEthBalanceFromRPC(address: address, endpoint: endpoint)
            } catch {
                print("⚠️ ETH RPC \(endpoint) failed: \(error.localizedDescription)")
                continue
            }
        }
        
        throw APIError.allProvidersFailed([])
    }
    
    private func fetchEthBalanceFromRPC(address: String, endpoint: String) async throws -> Double {
        guard let url = URL(string: endpoint) else {
            throw APIError.invalidRequest
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("HawalaApp/2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "eth_getBalance",
            "params": [address, "latest"]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? String else {
            throw APIError.parseError
        }
        
        // Convert hex to decimal
        let wei = hexToDecimal(result)
        return wei / 1_000_000_000_000_000_000.0
    }
    
    // MARK: - Bitcoin UTXO Fetching with Fallbacks
    
    struct UTXO {
        let txid: String
        let vout: Int
        let value: Int64
        let scriptPubKey: String
        let confirmed: Bool
        let blockHeight: Int?
    }
    
    /// Fetches UTXOs for a Bitcoin/Litecoin address with automatic fallback
    func fetchBitcoinUTXOs(address: String, isTestnet: Bool = false, isLitecoin: Bool = false) async throws -> [UTXO] {
        if isLitecoin {
            return try await fetchLitecoinUTXOs(address: address)
        }
        
        // Try mempool.space first (most reliable for Bitcoin)
        do {
            print("📡 Fetching UTXOs from mempool.space for \(address.prefix(10))...")
            return try await fetchUTXOsFromMempool(address: address, isTestnet: isTestnet)
        } catch {
            print("⚠️ mempool.space UTXOs failed: \(error.localizedDescription)")
        }
        
        // Try Blockstream second
        if !isTestnet {
            do {
                print("📡 Fetching UTXOs from Blockstream...")
                return try await fetchUTXOsFromBlockstream(address: address)
            } catch {
                print("⚠️ Blockstream UTXOs failed: \(error.localizedDescription)")
            }
        }
        
        // Try BlockCypher as last resort
        do {
            print("📡 Fetching UTXOs from BlockCypher...")
            return try await fetchUTXOsFromBlockCypher(address: address, isTestnet: isTestnet)
        } catch {
            print("⚠️ BlockCypher UTXOs failed: \(error.localizedDescription)")
        }
        
        throw APIError.allProvidersFailed([])
    }
    
    private func fetchUTXOsFromMempool(address: String, isTestnet: Bool) async throws -> [UTXO] {
        let baseURL = isTestnet ? "https://mempool.space/testnet/api" : "https://mempool.space/api"
        guard let url = URL(string: "\(baseURL)/address/\(address)/utxo") else {
            throw APIError.invalidRequest
        }
        
        var request = URLRequest(url: url)
        request.setValue("HawalaApp/2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        if httpResponse.statusCode == 404 {
            return [] // Address not found = no UTXOs
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw APIError.parseError
        }
        
        return jsonArray.compactMap { utxo -> UTXO? in
            guard let txid = utxo["txid"] as? String,
                  let vout = utxo["vout"] as? Int else {
                return nil
            }
            
            // Value can come as Int or Int64, handle both
            let value: Int64
            if let intValue = utxo["value"] as? Int {
                value = Int64(intValue)
            } else if let int64Value = utxo["value"] as? Int64 {
                value = int64Value
            } else if let nsNumber = utxo["value"] as? NSNumber {
                value = nsNumber.int64Value
            } else {
                print("⚠️ UTXO value parse failed for \(txid.prefix(8))")
                return nil
            }
            
            let status = utxo["status"] as? [String: Any]
            let confirmed = status?["confirmed"] as? Bool ?? false
            let blockHeight = status?["block_height"] as? Int
            
            print("📦 UTXO: \(txid.prefix(8))... value=\(value) confirmed=\(confirmed)")
            
            return UTXO(
                txid: txid,
                vout: vout,
                value: value,
                scriptPubKey: "",
                confirmed: confirmed,
                blockHeight: blockHeight
            )
        }
    }
    
    private func fetchUTXOsFromBlockstream(address: String) async throws -> [UTXO] {
        guard let url = URL(string: "https://blockstream.info/api/address/\(address)/utxo") else {
            throw APIError.invalidRequest
        }
        
        var request = URLRequest(url: url)
        request.setValue("HawalaApp/2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        if httpResponse.statusCode == 404 {
            return []
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw APIError.parseError
        }
        
        return jsonArray.compactMap { utxo -> UTXO? in
            guard let txid = utxo["txid"] as? String,
                  let vout = utxo["vout"] as? Int else {
                return nil
            }
            
            // Value can come as Int or Int64
            let value: Int64
            if let intValue = utxo["value"] as? Int {
                value = Int64(intValue)
            } else if let int64Value = utxo["value"] as? Int64 {
                value = int64Value
            } else if let nsNumber = utxo["value"] as? NSNumber {
                value = nsNumber.int64Value
            } else {
                return nil
            }
            
            let status = utxo["status"] as? [String: Any]
            let confirmed = status?["confirmed"] as? Bool ?? false
            let blockHeight = status?["block_height"] as? Int
            
            return UTXO(
                txid: txid,
                vout: vout,
                value: value,
                scriptPubKey: "",
                confirmed: confirmed,
                blockHeight: blockHeight
            )
        }
    }
    
    private func fetchUTXOsFromBlockCypher(address: String, isTestnet: Bool) async throws -> [UTXO] {
        let baseURL = isTestnet ? "https://api.blockcypher.com/v1/btc/test3" : "https://api.blockcypher.com/v1/btc/main"
        guard let url = URL(string: "\(baseURL)/addrs/\(address)?unspentOnly=true&includeScript=true") else {
            throw APIError.invalidRequest
        }
        
        var request = URLRequest(url: url)
        request.setValue("HawalaApp/2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        if httpResponse.statusCode == 404 {
            return []
        }
        
        if httpResponse.statusCode == 429 {
            throw APIError.rateLimited
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let txrefs = json["txrefs"] as? [[String: Any]] else {
            // No txrefs = no UTXOs
            return []
        }
        
        return txrefs.compactMap { utxo -> UTXO? in
            guard let txid = utxo["tx_hash"] as? String,
                  let vout = utxo["tx_output_n"] as? Int else {
                return nil
            }
            
            // Value can come as Int or Int64
            let value: Int64
            if let intValue = utxo["value"] as? Int {
                value = Int64(intValue)
            } else if let int64Value = utxo["value"] as? Int64 {
                value = int64Value
            } else if let nsNumber = utxo["value"] as? NSNumber {
                value = nsNumber.int64Value
            } else {
                return nil
            }
            
            let confirmations = utxo["confirmations"] as? Int ?? 0
            let blockHeight = utxo["block_height"] as? Int
            let script = utxo["script"] as? String ?? ""
            
            return UTXO(
                txid: txid,
                vout: vout,
                value: value,
                scriptPubKey: script,
                confirmed: confirmations > 0,
                blockHeight: blockHeight
            )
        }
    }
    
    private func fetchLitecoinUTXOs(address: String) async throws -> [UTXO] {
        // Use litecoinspace.org (mempool clone for Litecoin)
        do {
            guard let url = URL(string: "https://litecoinspace.org/api/address/\(address)/utxo") else {
                throw APIError.invalidRequest
            }
            
            var request = URLRequest(url: url)
            request.setValue("HawalaApp/2.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 20
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            if httpResponse.statusCode == 404 {
                return []
            }
            
            guard httpResponse.statusCode == 200 else {
                throw APIError.httpError(httpResponse.statusCode)
            }
            
            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw APIError.parseError
            }
            
            return jsonArray.compactMap { utxo -> UTXO? in
                guard let txid = utxo["txid"] as? String,
                      let vout = utxo["vout"] as? Int else {
                    return nil
                }
                
                // Value can come as Int or Int64
                let value: Int64
                if let intValue = utxo["value"] as? Int {
                    value = Int64(intValue)
                } else if let int64Value = utxo["value"] as? Int64 {
                    value = int64Value
                } else if let nsNumber = utxo["value"] as? NSNumber {
                    value = nsNumber.int64Value
                } else {
                    return nil
                }
                
                let status = utxo["status"] as? [String: Any]
                let confirmed = status?["confirmed"] as? Bool ?? false
                let blockHeight = status?["block_height"] as? Int
                
                return UTXO(
                    txid: txid,
                    vout: vout,
                    value: value,
                    scriptPubKey: "",
                    confirmed: confirmed,
                    blockHeight: blockHeight
                )
            }
        } catch {
            print("⚠️ litecoinspace.org UTXOs failed, trying Blockchair: \(error.localizedDescription)")
        }
        
        // Fallback to Blockchair for Litecoin
        guard let url = URL(string: "https://api.blockchair.com/litecoin/dashboards/address/\(address)?limit=100") else {
            throw APIError.invalidRequest
        }
        
        var request = URLRequest(url: url)
        request.setValue("HawalaApp/2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let addressData = dataDict[address] as? [String: Any],
              let utxosArray = addressData["utxo"] as? [[String: Any]] else {
            return []
        }
        
        return utxosArray.compactMap { utxo -> UTXO? in
            guard let txid = utxo["transaction_hash"] as? String,
                  let vout = utxo["index"] as? Int else {
                return nil
            }
            
            // Value can come as Int or Int64
            let value: Int64
            if let intValue = utxo["value"] as? Int {
                value = Int64(intValue)
            } else if let int64Value = utxo["value"] as? Int64 {
                value = int64Value
            } else if let nsNumber = utxo["value"] as? NSNumber {
                value = nsNumber.int64Value
            } else {
                return nil
            }
            
            let blockId = utxo["block_id"] as? Int ?? 0
            let script = utxo["script_hex"] as? String ?? ""
            
            return UTXO(
                txid: txid,
                vout: vout,
                value: value,
                scriptPubKey: script,
                confirmed: blockId > 0,
                blockHeight: blockId > 0 ? blockId : nil
            )
        }
    }
    
    // MARK: - Helper Functions
    
    private func coinCapIdFor(_ chainId: String) -> String {
        switch chainId {
        case "bitcoin": return "bitcoin"
        case "ethereum": return "ethereum"
        case "litecoin": return "litecoin"
        case "monero": return "monero"
        case "solana": return "solana"
        case "xrp": return "xrp"
        case "bnb": return "binance-coin"
        default: return chainId
        }
    }
    
    private func coinGeckoIdFor(_ chainId: String) -> String {
        switch chainId {
        case "xrp": return "ripple"
        case "bnb": return "binancecoin"
        default: return chainId
        }
    }
    
    private func hexToDecimal(_ hex: String) -> Double {
        var hexStr = hex
        if hexStr.hasPrefix("0x") {
            hexStr = String(hexStr.dropFirst(2))
        }
        
        guard let value = UInt64(hexStr, radix: 16) else {
            return 0
        }
        
        return Double(value)
    }
    
    // MARK: - Error Types
    
    enum APIError: Error, LocalizedError {
        case invalidRequest
        case invalidResponse
        case httpError(Int)
        case parseError
        case noData
        case rateLimited
        case allProvidersFailed([Error])
        case apiError(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidRequest: return "Invalid request"
            case .invalidResponse: return "Invalid response"
            case .httpError(let code): return "HTTP error \(code)"
            case .parseError: return "Failed to parse response"
            case .noData: return "No data returned"
            case .rateLimited: return "Rate limited"
            case .allProvidersFailed: return "All API providers failed"
            case .apiError(let message): return message
            }
        }
    }
}
