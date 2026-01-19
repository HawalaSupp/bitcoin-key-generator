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
        
        // Initialize Moralis API key if not already set
        initializeMoralisKey()
        
        // Debug: Print provider status
        #if DEBUG
        if apiKeys.hasMoralisKey {
            print("🔑 Moralis API configured and ready (Primary Provider)")
        }
        if apiKeys.hasAlchemyKey {
            print("🔑 Alchemy API configured and ready")
        }
        if !apiKeys.hasMoralisKey && !apiKeys.hasAlchemyKey {
            print("⚠️ No premium API keys configured - using public endpoints")
        }
        #endif
    }
    
    private func initializeMoralisKey() {
        // Store the Moralis key if not already in keychain
        if !apiKeys.hasMoralisKey {
            // Your Moralis API key
            let moralisKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJub25jZSI6IjgyYjhlZDgyLWE3MDktNDc2OS1iNzM3LWI2Y2FiNzcwYmIwMyIsIm9yZ0lkIjoiNDg3Njk1IiwidXNlcklkIjoiNTAxNzY3IiwidHlwZUlkIjoiNTUwMmNhZGQtNDQxNS00ZjAxLWExNGUtZjg1YmY0MTJmZTU0IiwidHlwZSI6IlBST0pFQ1QiLCJpYXQiOjE3NjY4NDc1NDEsImV4cCI6NDkyMjYwNzU0MX0.Tc3kCdcxtHi49TTgfIkPEP7PbLLUxBKjm4YJZPqd7cQ"
            APIKeys.setMoralisKey(moralisKey)
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
    /// Priority: Moralis (Trust Wallet) → CoinCap → CryptoCompare → CoinGecko
    func fetchPrices() async throws -> [String: Double] {
        // Try Moralis first (used by Trust Wallet, Exodus, MetaMask)
        if apiKeys.hasMoralisKey {
            do {
                #if DEBUG
                print("📊 Trying Moralis for prices...")
                #endif
                let prices = try await fetchPricesFromMoralis()
                healthManager.recordSuccess(for: .moralis)
                return prices
            } catch {
                #if DEBUG
                print("⚠️ Moralis failed: \(error.localizedDescription)")
                #endif
                healthManager.recordFailure(for: .moralis, error: error)
            }
        }
        
        // Try CoinCap second (no API key needed, generous limits)
        do {
            #if DEBUG
            print("📊 Trying CoinCap for prices...")
            #endif
            let prices = try await fetchPricesFromCoinCap()
            healthManager.recordSuccess(for: .coinCap)
            return prices
        } catch {
            #if DEBUG
            print("⚠️ CoinCap failed: \(error.localizedDescription)")
            #endif
            healthManager.recordFailure(for: .coinCap, error: error)
        }
        
        // Try CryptoCompare second
        do {
            #if DEBUG
            print("📊 Trying CryptoCompare for prices...")
            #endif
            let prices = try await fetchPricesFromCryptoCompare()
            healthManager.recordSuccess(for: .cryptoCompare)
            return prices
        } catch {
            #if DEBUG
            print("⚠️ CryptoCompare failed: \(error.localizedDescription)")
            #endif
            healthManager.recordFailure(for: .cryptoCompare, error: error)
        }
        
        // Finally try CoinGecko (most likely to be rate limited)
        #if DEBUG
        print("📊 Trying CoinGecko for prices...")
        #endif
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
                #if DEBUG
                print("📡 Fetching ETH balance from Alchemy...")
                #endif
                let balance = try await fetchEthBalanceFromRPC(address: address, endpoint: alchemyURL)
                healthManager.recordSuccess(for: .alchemy)
                return balance
            } catch {
                #if DEBUG
                print("⚠️ Alchemy ETH balance failed: \(error.localizedDescription)")
                #endif
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
                #if DEBUG
                print("📡 Fetching SOL balance from Alchemy...")
                #endif
                let balance = try await fetchSolBalanceFromAlchemy(url: alchemyURL, address: address)
                healthManager.recordSuccess(for: .alchemy)
                return balance
            } catch {
                #if DEBUG
                print("⚠️ Alchemy SOL balance failed: \(error.localizedDescription)")
                #endif
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
            #if DEBUG
            if let responseBody = String(data: data, encoding: .utf8) {
                print("⚠️ Alchemy SOL HTTP \(httpResponse.statusCode): \(responseBody.prefix(200))")
            }
            #endif
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.parseError
        }
        
        // Check for error response
        if let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Unknown error"
            #if DEBUG
            print("⚠️ Alchemy SOL API error: \(message)")
            #endif
            throw APIError.apiError(message)
        }
        
        guard let result = json["result"] as? [String: Any],
              let lamports = result["value"] as? Int64 else {
            #if DEBUG
            if let responseBody = String(data: data, encoding: .utf8) {
                print("⚠️ Alchemy SOL parse failed: \(responseBody.prefix(300))")
            }
            #endif
            throw APIError.parseError
        }
        
        // Convert lamports to SOL (1 SOL = 1,000,000,000 lamports)
        let solBalance = Double(lamports) / 1_000_000_000.0
        #if DEBUG
        print("✅ Alchemy SOL balance: \(solBalance)")
        #endif
        return solBalance
    }
    
    // MARK: - CoinCap API (Free, generous limits)
    private func fetchPricesFromCoinCap() async throws -> [String: Double] {
        // Include all supported chains - CoinCap uses hyphenated IDs
        let coinCapIds = [
            "bitcoin", "ethereum", "litecoin", "monero", "solana", "xrp", "binance-coin",
            "dogecoin", "bitcoin-cash", "cosmos", "cardano", "tron", "algorand", "stellar",
            "near-protocol", "tezos", "hedera-hashgraph", "polkadot", "aptos", "sui", "toncoin",
            "zcash", "dash", "ravencoin", "vechain", "filecoin", "harmony", "oasis-network",
            "internet-computer", "waves", "elrond-egld", "flow", "mina", "zilliqa", "eos", "neo", "nervos-network"
        ].joined(separator: ",")
        
        let url = URL(string: "https://api.coincap.io/v2/assets?ids=\(coinCapIds)")!
        
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
        
        // Map CoinCap IDs to our chain IDs
        let coinCapToChainId: [String: String] = [
            "bitcoin": "bitcoin",
            "ethereum": "ethereum",
            "litecoin": "litecoin",
            "monero": "monero",
            "solana": "solana",
            "xrp": "ripple",
            "binance-coin": "binancecoin",
            "dogecoin": "dogecoin",
            "bitcoin-cash": "bitcoin-cash",
            "cosmos": "cosmos",
            "cardano": "cardano",
            "tron": "tron",
            "algorand": "algorand",
            "stellar": "stellar",
            "near-protocol": "near",
            "tezos": "tezos",
            "hedera-hashgraph": "hedera",
            "polkadot": "polkadot",
            "aptos": "aptos",
            "sui": "sui",
            "toncoin": "ton",
            "zcash": "zcash",
            "dash": "dash",
            "ravencoin": "ravencoin",
            "vechain": "vechain",
            "filecoin": "filecoin",
            "harmony": "harmony",
            "oasis-network": "oasis",
            "internet-computer": "internet-computer",
            "waves": "waves",
            "elrond-egld": "multiversx",
            "flow": "flow",
            "mina": "mina",
            "zilliqa": "zilliqa",
            "eos": "eos",
            "neo": "neo",
            "nervos-network": "nervos"
        ]
        
        for asset in dataArray {
            guard let id = asset["id"] as? String,
                  let priceString = asset["priceUsd"] as? String,
                  let price = Double(priceString) else { continue }
            
            if let chainId = coinCapToChainId[id] {
                prices[chainId] = price
            }
        }
        
        guard !prices.isEmpty else {
            throw APIError.noData
        }
        
        #if DEBUG
        print("✅ CoinCap returned \(prices.count) prices")
        #endif
        return prices
    }
    
    // MARK: - Moralis API (Used by Trust Wallet, Exodus, MetaMask)
    private func fetchPricesFromMoralis() async throws -> [String: Double] {
        let moralis = MoralisAPI.shared
        
        // Token addresses for native tokens (Ethereum mainnet addresses)
        let nativeTokens: [(chain: MoralisAPI.Chain, address: String, key: String)] = [
            (.ethereum, "0x0000000000000000000000000000000000000000", "ethereum"),
            (.bsc, "0x0000000000000000000000000000000000000000", "binancecoin"),
            (.polygon, "0x0000000000000000000000000000000000000000", "polygon"),
            (.arbitrum, "0x0000000000000000000000000000000000000000", "arbitrum"),
        ]
        
        var prices: [String: Double] = [:]
        
        // Fetch EVM chain prices
        for token in nativeTokens {
            do {
                let price = try await moralis.getTokenPrice(
                    address: token.address,
                    chain: token.chain
                )
                prices[token.key] = price.usdPrice
            } catch {
                #if DEBUG
                print("⚠️ Moralis price failed for \(token.key): \(error.localizedDescription)")
                #endif
            }
        }
        
        // For non-EVM chains, use fallback to CoinGecko simple API
        let nonEvmIds = [
            "bitcoin", "litecoin", "monero", "solana", "ripple",
            "dogecoin", "bitcoin-cash", "cosmos", "cardano", "tron", "algorand", "stellar",
            "near", "tezos", "hedera-hashgraph", "polkadot", "aptos", "sui", "the-open-network",
            "zcash", "dash", "ravencoin", "vechain", "filecoin", "harmony", "oasis-network",
            "internet-computer", "waves", "elrond-erd-2", "flow", "mina-protocol", "zilliqa", "eos", "neo", "nervos-network"
        ].joined(separator: ",")
        let fallbackURL = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=\(nonEvmIds)&vs_currencies=usd")!
        var request = URLRequest(url: fallbackURL)
        request.timeoutInterval = 10
        
        // Map CoinGecko IDs to chain IDs
        let geckoToChainId: [String: String] = [
            "bitcoin": "bitcoin", "litecoin": "litecoin", "monero": "monero", 
            "solana": "solana", "ripple": "ripple", "dogecoin": "dogecoin",
            "bitcoin-cash": "bitcoin-cash", "cosmos": "cosmos", "cardano": "cardano",
            "tron": "tron", "algorand": "algorand", "stellar": "stellar",
            "near": "near", "tezos": "tezos", "hedera-hashgraph": "hedera",
            "polkadot": "polkadot", "aptos": "aptos", "sui": "sui",
            "the-open-network": "ton", "zcash": "zcash", "dash": "dash",
            "ravencoin": "ravencoin", "vechain": "vechain", "filecoin": "filecoin",
            "harmony": "harmony", "oasis-network": "oasis", "internet-computer": "internet-computer",
            "waves": "waves", "elrond-erd-2": "multiversx", "flow": "flow",
            "mina-protocol": "mina", "zilliqa": "zilliqa", "eos": "eos", "neo": "neo", "nervos-network": "nervos"
        ]
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: Double]] {
                for (geckoId, chainId) in geckoToChainId {
                    if let price = json[geckoId]?["usd"] {
                        prices[chainId] = price
                    }
                }
            }
        } catch {
            #if DEBUG
            print("⚠️ Moralis fallback price fetch failed: \(error.localizedDescription)")
            #endif
        }
        
        guard !prices.isEmpty else {
            throw APIError.noData
        }
        
        #if DEBUG
        print("✅ Moralis returned \(prices.count) prices")
        #endif
        return prices
    }
    
    // MARK: - CryptoCompare API (Free tier available)
    private func fetchPricesFromCryptoCompare() async throws -> [String: Double] {
        // Include all supported symbols
        let symbols = "BTC,ETH,LTC,XMR,SOL,XRP,BNB,DOGE,BCH,ATOM,ADA,TRX,ALGO,XLM,NEAR,XTZ,HBAR,DOT,APT,SUI,TON,ZEC,DASH,RVN,VET,FIL,ONE,ROSE,ICP,WAVES,EGLD,FLOW,MINA,ZIL,EOS,NEO,CKB"
        let url = URL(string: "https://min-api.cryptocompare.com/data/pricemulti?fsyms=\(symbols)&tsyms=USD")!
        
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
        let symbolMap: [String: String] = [
            "BTC": "bitcoin",
            "ETH": "ethereum", 
            "LTC": "litecoin",
            "XMR": "monero",
            "SOL": "solana",
            "XRP": "ripple",
            "BNB": "binancecoin",
            "DOGE": "dogecoin",
            "BCH": "bitcoin-cash",
            "ATOM": "cosmos",
            "ADA": "cardano",
            "TRX": "tron",
            "ALGO": "algorand",
            "XLM": "stellar",
            "NEAR": "near",
            "XTZ": "tezos",
            "HBAR": "hedera",
            "DOT": "polkadot",
            "APT": "aptos",
            "SUI": "sui",
            "TON": "ton",
            "ZEC": "zcash",
            "DASH": "dash",
            "RVN": "ravencoin",
            "VET": "vechain",
            "FIL": "filecoin",
            "ONE": "harmony",
            "ROSE": "oasis",
            "ICP": "internet-computer",
            "WAVES": "waves",
            "EGLD": "multiversx",
            "FLOW": "flow",
            "MINA": "mina",
            "ZIL": "zilliqa",
            "EOS": "eos",
            "NEO": "neo",
            "CKB": "nervos"
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
        
        #if DEBUG
        print("✅ CryptoCompare returned \(prices.count) prices")
        #endif
        return prices
    }
    
    // MARK: - CoinGecko API (Most restricted, use as last resort)
    private func fetchPricesFromCoinGecko() async throws -> [String: Double] {
        // Include all supported CoinGecko IDs
        let coinGeckoIds = [
            "bitcoin", "ethereum", "litecoin", "monero", "solana", "ripple", "binancecoin",
            "dogecoin", "bitcoin-cash", "cosmos", "cardano", "tron", "algorand", "stellar",
            "near", "tezos", "hedera-hashgraph", "polkadot", "aptos", "sui", "the-open-network",
            "zcash", "dash", "ravencoin", "vechain", "filecoin", "harmony", "oasis-network",
            "internet-computer", "waves", "elrond-erd-2", "flow", "mina-protocol", "zilliqa", "eos", "neo", "nervos-network"
        ].joined(separator: ",")
        
        let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=\(coinGeckoIds)&vs_currencies=usd")!
        
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
        
        // Map CoinGecko IDs to chain IDs
        let coinGeckoToChainId: [String: String] = [
            "bitcoin": "bitcoin",
            "ethereum": "ethereum",
            "litecoin": "litecoin",
            "monero": "monero",
            "solana": "solana",
            "ripple": "ripple",
            "binancecoin": "binancecoin",
            "dogecoin": "dogecoin",
            "bitcoin-cash": "bitcoin-cash",
            "cosmos": "cosmos",
            "cardano": "cardano",
            "tron": "tron",
            "algorand": "algorand",
            "stellar": "stellar",
            "near": "near",
            "tezos": "tezos",
            "hedera-hashgraph": "hedera",
            "polkadot": "polkadot",
            "aptos": "aptos",
            "sui": "sui",
            "the-open-network": "ton",
            "zcash": "zcash",
            "dash": "dash",
            "ravencoin": "ravencoin",
            "vechain": "vechain",
            "filecoin": "filecoin",
            "harmony": "harmony",
            "oasis-network": "oasis",
            "internet-computer": "internet-computer",
            "waves": "waves",
            "elrond-erd-2": "multiversx",
            "flow": "flow",
            "mina-protocol": "mina",
            "zilliqa": "zilliqa",
            "eos": "eos",
            "neo": "neo",
            "nervos-network": "nervos"
        ]
        
        for (coinGeckoId, chainId) in coinGeckoToChainId {
            if let coinData = json[coinGeckoId] as? [String: Any],
               let usdPrice = coinData["usd"] as? Double {
                prices[chainId] = usdPrice
            }
        }
        
        guard !prices.isEmpty else {
            throw APIError.noData
        }
        
        #if DEBUG
        print("✅ CoinGecko returned \(prices.count) prices")
        #endif
        return prices
    }
    
    // MARK: - Sparkline Data with Fallbacks
    
    func fetchSparkline(for chainId: String) async throws -> [Double] {
        let coinCapId = coinCapIdFor(chainId)
        
        // Try CoinCap first
        do {
            return try await fetchSparklineFromCoinCap(coinId: coinCapId)
        } catch {
            #if DEBUG
            print("⚠️ CoinCap sparkline failed for \(chainId): \(error.localizedDescription)")
            #endif
        }
        
        // Fallback to CryptoCompare (reliable, generous limits)
        let symbol = symbolFor(chainId)
        do {
            return try await fetchSparklineFromCryptoCompare(symbol: symbol)
        } catch {
            #if DEBUG
            print("⚠️ CryptoCompare sparkline failed for \(chainId): \(error.localizedDescription)")
            #endif
        }
        
        // Last resort: CoinGecko (most likely to be rate limited)
        let coinGeckoId = coinGeckoIdFor(chainId)
        return try await fetchSparklineFromCoinGecko(coinId: coinGeckoId)
    }
    
    /// Map chain ID to CryptoCompare symbol
    private func symbolFor(_ chainId: String) -> String {
        let mapping: [String: String] = [
            "bitcoin": "BTC", "ethereum": "ETH", "litecoin": "LTC", "monero": "XMR",
            "solana": "SOL", "xrp": "XRP", "ripple": "XRP", "bnb": "BNB", "binancecoin": "BNB",
            "dogecoin": "DOGE", "bitcoin-cash": "BCH", "cosmos": "ATOM", "cardano": "ADA",
            "tron": "TRX", "algorand": "ALGO", "stellar": "XLM", "near": "NEAR",
            "tezos": "XTZ", "hedera": "HBAR", "polkadot": "DOT", "aptos": "APT",
            "sui": "SUI", "ton": "TON", "zcash": "ZEC", "dash": "DASH", "ravencoin": "RVN",
            "vechain": "VET", "filecoin": "FIL", "harmony": "ONE", "oasis": "ROSE",
            "internet-computer": "ICP", "waves": "WAVES", "multiversx": "EGLD", "flow": "FLOW",
            "mina": "MINA", "zilliqa": "ZIL", "eos": "EOS", "neo": "NEO", "nervos": "CKB",
            // Stablecoins
            "usdt-erc20": "USDT", "usdc-erc20": "USDC", "dai-erc20": "DAI"
        ]
        return mapping[chainId] ?? chainId.uppercased()
    }
    
    private func fetchSparklineFromCryptoCompare(symbol: String) async throws -> [Double] {
        // CryptoCompare histohour gives 24 hourly data points
        let url = URL(string: "https://min-api.cryptocompare.com/data/v2/histohour?fsym=\(symbol)&tsym=USD&limit=24")!
        
        var request = URLRequest(url: url)
        request.setValue("HawalaApp/2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataWrapper = json["Data"] as? [String: Any],
              let dataArray = dataWrapper["Data"] as? [[String: Any]] else {
            throw APIError.parseError
        }
        
        let prices = dataArray.compactMap { item -> Double? in
            return item["close"] as? Double
        }
        
        guard !prices.isEmpty else {
            throw APIError.noData
        }
        
        return prices
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
            #if DEBUG
            print("⚠️ Mempool.space failed: \(error.localizedDescription)")
            #endif
            healthManager.recordFailure(for: .mempool, error: error)
        }
        
        // Try Blockstream second
        if !isTestnet {
            do {
                let balance = try await fetchBitcoinBalanceFromBlockstream(address: address)
                healthManager.recordSuccess(for: .blockchair) // Using blockchair as generic blockchain provider
                return balance
            } catch {
                #if DEBUG
                print("⚠️ Blockstream failed: \(error.localizedDescription)")
                #endif
            }
        }
        
        // Try BlockCypher last
        do {
            let balance = try await fetchBitcoinBalanceFromBlockCypher(address: address, isTestnet: isTestnet)
            return balance
        } catch {
            #if DEBUG
            print("⚠️ BlockCypher failed: \(error.localizedDescription)")
            #endif
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
                #if DEBUG
                print("📡 Fetching SOL balance from Alchemy...")
                #endif
                let balance = try await fetchSolanaBalanceFromRPC(address: address, endpoint: alchemyURL)
                #if DEBUG
                print("✅ Alchemy SOL balance: \(balance)")
                #endif
                return balance
            } catch {
                #if DEBUG
                print("⚠️ Alchemy SOL failed: \(error.localizedDescription)")
                #endif
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
                #if DEBUG
                print("⚠️ Solana RPC \(endpoint) failed: \(error.localizedDescription)")
                #endif
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
        #if DEBUG
        print("🔍 Checking Alchemy for ETH: hasKey=\(apiKeys.hasAlchemyKey)")
        #endif
        
        // Try Alchemy FIRST if key is available
        if let alchemyURL = apiKeys.alchemyBaseURL(for: APIKeys.AlchemyChain.ethereumMainnet) {
            do {
                #if DEBUG
                print("📡 Fetching ETH balance from Alchemy: \(alchemyURL.prefix(50))...")
                #endif
                let balance = try await fetchEthBalanceFromRPC(address: address, endpoint: alchemyURL)
                #if DEBUG
                print("✅ Alchemy ETH balance: \(balance)")
                #endif
                return balance
            } catch {
                #if DEBUG
                print("⚠️ Alchemy ETH failed: \(error.localizedDescription)")
                #endif
            }
        } else {
            #if DEBUG
            print("⚠️ Alchemy URL not available for ETH")
            #endif
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
                #if DEBUG
                print("⚠️ ETH RPC \(endpoint) failed: \(error.localizedDescription)")
                #endif
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
            #if DEBUG
            print("📡 Fetching UTXOs from mempool.space for \(address.prefix(10))...")
            #endif
            return try await fetchUTXOsFromMempool(address: address, isTestnet: isTestnet)
        } catch {
            #if DEBUG
            print("⚠️ mempool.space UTXOs failed: \(error.localizedDescription)")
            #endif
        }
        
        // Try Blockstream second
        if !isTestnet {
            do {
                #if DEBUG
                print("📡 Fetching UTXOs from Blockstream...")
                #endif
                return try await fetchUTXOsFromBlockstream(address: address)
            } catch {
                #if DEBUG
                print("⚠️ Blockstream UTXOs failed: \(error.localizedDescription)")
                #endif
            }
        }
        
        // Try BlockCypher as last resort
        do {
            #if DEBUG
            print("📡 Fetching UTXOs from BlockCypher...")
            #endif
            return try await fetchUTXOsFromBlockCypher(address: address, isTestnet: isTestnet)
        } catch {
            #if DEBUG
            print("⚠️ BlockCypher UTXOs failed: \(error.localizedDescription)")
            #endif
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
                #if DEBUG
                print("⚠️ UTXO value parse failed for \(txid.prefix(8))")
                #endif
                return nil
            }
            
            let status = utxo["status"] as? [String: Any]
            let confirmed = status?["confirmed"] as? Bool ?? false
            let blockHeight = status?["block_height"] as? Int
            
            #if DEBUG
            print("📦 UTXO: \(txid.prefix(8))... value=\(value) confirmed=\(confirmed)")
            #endif
            
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
            #if DEBUG
            print("⚠️ litecoinspace.org UTXOs failed, trying Blockchair: \(error.localizedDescription)")
            #endif
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
        let mapping: [String: String] = [
            "bitcoin": "bitcoin",
            "ethereum": "ethereum",
            "litecoin": "litecoin",
            "monero": "monero",
            "solana": "solana",
            "xrp": "xrp",
            "bnb": "binance-coin",
            "dogecoin": "dogecoin",
            "bitcoin-cash": "bitcoin-cash",
            "cosmos": "cosmos",
            "cardano": "cardano",
            "tron": "tron",
            "algorand": "algorand",
            "stellar": "stellar",
            "near": "near-protocol",
            "tezos": "tezos",
            "hedera": "hedera-hashgraph",
            "polkadot": "polkadot",
            "aptos": "aptos",
            "sui": "sui",
            "ton": "toncoin",
            "zcash": "zcash",
            "dash": "dash",
            "ravencoin": "ravencoin",
            "vechain": "vechain",
            "filecoin": "filecoin",
            "harmony": "harmony",
            "oasis": "oasis-network",
            "internet-computer": "internet-computer",
            "waves": "waves",
            "multiversx": "elrond-egld",
            "flow": "flow",
            "mina": "mina",
            "zilliqa": "zilliqa",
            "eos": "eos",
            "neo": "neo",
            "nervos": "nervos-network"
        ]
        return mapping[chainId] ?? chainId
    }
    
    private func coinGeckoIdFor(_ chainId: String) -> String {
        let mapping: [String: String] = [
            "xrp": "ripple",
            "bnb": "binancecoin",
            "hedera": "hedera-hashgraph",
            "near": "near",
            "ton": "the-open-network",
            "oasis": "oasis-network",
            "internet-computer": "internet-computer",
            "multiversx": "elrond-erd-2",
            "mina": "mina-protocol",
            "nervos": "nervos-network"
        ]
        return mapping[chainId] ?? chainId
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
