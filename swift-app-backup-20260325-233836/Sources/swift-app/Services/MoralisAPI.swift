import Foundation

// MARK: - Moralis API Service
/// High-reliability blockchain data provider used by Trust Wallet, Exodus, MetaMask, Ledger
/// Supports: Ethereum, BSC, Polygon, Solana, and 30+ other chains
/// Free tier: 40,000 CU/day (~1,333 requests), Starter: $49/mo for 3M CU

@MainActor
final class MoralisAPI: ObservableObject {
    static let shared = MoralisAPI()
    
    // MARK: - Configuration
    
    private var apiKey: String? {
        APIKeys.shared.moralisKey
    }
    
    private let baseURL = "https://deep-index.moralis.io/api/v2.2"
    private let solanaBaseURL = "https://solana-gateway.moralis.io"
    
    // Rate limiting
    private let rateLimiter = APIRateLimiter(name: "Moralis", config: .init(requestsPerSecond: 25, burstSize: 50, retryAfterHeader: true))
    
    // MARK: - Supported Chains
    
    enum Chain: String {
        case ethereum = "eth"
        case bsc = "bsc"
        case polygon = "polygon"
        case avalanche = "avalanche"
        case fantom = "fantom"
        case arbitrum = "arbitrum"
        case optimism = "optimism"
        case base = "base"
        case linea = "linea"
        case sepolia = "sepolia"
        case solana = "mainnet"
        case solanaDevnet = "devnet"
        
        var chainId: String {
            switch self {
            case .ethereum: return "0x1"
            case .bsc: return "0x38"
            case .polygon: return "0x89"
            case .avalanche: return "0xa86a"
            case .fantom: return "0xfa"
            case .arbitrum: return "0xa4b1"
            case .optimism: return "0xa"
            case .base: return "0x2105"
            case .linea: return "0xe708"
            case .sepolia: return "0xaa36a7"
            case .solana, .solanaDevnet: return rawValue
            }
        }
    }
    
    // MARK: - Wallet Balance (EVM)
    
    /// Get native balance for EVM wallet
    func getNativeBalance(address: String, chain: Chain) async throws -> Double {
        guard let key = apiKey else {
            throw MoralisError.noAPIKey
        }
        
        try await rateLimiter.acquire()
        
        let url = URL(string: "\(baseURL)/\(address)/balance?chain=\(chain.rawValue)")!
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MoralisError.invalidResponse
        }
        
        if httpResponse.statusCode == 429 {
            await rateLimiter.reportRateLimit()
            throw MoralisError.rateLimited
        }
        
        guard httpResponse.statusCode == 200 else {
            throw MoralisError.httpError(httpResponse.statusCode)
        }
        
        let result = try JSONDecoder().decode(NativeBalanceResponse.self, from: data)
        
        // Convert from Wei to ETH (18 decimals)
        if let balance = Double(result.balance) {
            return balance / 1_000_000_000_000_000_000
        }
        return 0
    }
    
    /// Get all token balances for EVM wallet
    func getTokenBalances(address: String, chain: Chain) async throws -> [TokenBalance] {
        guard let key = apiKey else {
            throw MoralisError.noAPIKey
        }
        
        try await rateLimiter.acquire()
        
        let url = URL(string: "\(baseURL)/\(address)/erc20?chain=\(chain.rawValue)")!
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw MoralisError.invalidResponse
        }
        
        return try JSONDecoder().decode([TokenBalance].self, from: data)
    }
    
    // MARK: - Transaction History (EVM)
    
    /// Get transaction history for EVM wallet
    func getTransactions(address: String, chain: Chain, limit: Int = 100) async throws -> [MoralisTransaction] {
        guard let key = apiKey else {
            throw MoralisError.noAPIKey
        }
        
        try await rateLimiter.acquire()
        
        let url = URL(string: "\(baseURL)/\(address)?chain=\(chain.rawValue)&limit=\(limit)")!
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw MoralisError.invalidResponse
        }
        
        let result = try JSONDecoder().decode(TransactionHistoryResponse.self, from: data)
        return result.result
    }
    
    /// Get ERC-20 token transfers
    func getTokenTransfers(address: String, chain: Chain, limit: Int = 100) async throws -> [TokenTransfer] {
        guard let key = apiKey else {
            throw MoralisError.noAPIKey
        }
        
        try await rateLimiter.acquire()
        
        let url = URL(string: "\(baseURL)/\(address)/erc20/transfers?chain=\(chain.rawValue)&limit=\(limit)")!
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw MoralisError.invalidResponse
        }
        
        let result = try JSONDecoder().decode(TokenTransferResponse.self, from: data)
        return result.result
    }
    
    // MARK: - Solana Support
    
    /// Get Solana native balance
    func getSolanaBalance(address: String, network: Chain = .solana) async throws -> Double {
        guard let key = apiKey else {
            throw MoralisError.noAPIKey
        }
        
        try await rateLimiter.acquire()
        
        let url = URL(string: "\(solanaBaseURL)/account/\(network.rawValue)/\(address)/balance")!
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw MoralisError.invalidResponse
        }
        
        let result = try JSONDecoder().decode(SolanaBalanceResponse.self, from: data)
        
        // Convert lamports to SOL (lamports is a string)
        let lamportsValue = Double(result.lamports) ?? 0
        return lamportsValue / 1_000_000_000
    }
    
    /// Get Solana SPL token balances
    func getSolanaTokens(address: String, network: Chain = .solana) async throws -> [SolanaToken] {
        guard let key = apiKey else {
            throw MoralisError.noAPIKey
        }
        
        try await rateLimiter.acquire()
        
        let url = URL(string: "\(solanaBaseURL)/account/\(network.rawValue)/\(address)/tokens")!
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw MoralisError.invalidResponse
        }
        
        return try JSONDecoder().decode([SolanaToken].self, from: data)
    }
    
    // MARK: - Price API
    
    /// Get token price
    func getTokenPrice(address: String, chain: Chain) async throws -> TokenPrice {
        guard let key = apiKey else {
            throw MoralisError.noAPIKey
        }
        
        try await rateLimiter.acquire()
        
        let url = URL(string: "\(baseURL)/erc20/\(address)/price?chain=\(chain.rawValue)")!
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw MoralisError.invalidResponse
        }
        
        return try JSONDecoder().decode(TokenPrice.self, from: data)
    }
    
    /// Get multiple token prices
    func getMultipleTokenPrices(tokens: [(address: String, chain: Chain)]) async throws -> [String: Double] {
        var prices: [String: Double] = [:]
        
        for token in tokens {
            do {
                let price = try await getTokenPrice(address: token.address, chain: token.chain)
                prices[token.address] = price.usdPrice
            } catch {
                // Continue with other tokens if one fails
                continue
            }
        }
        
        return prices
    }
}

// MARK: - Response Models

extension MoralisAPI {
    
    struct NativeBalanceResponse: Codable {
        let balance: String
    }
    
    struct TokenBalance: Codable {
        let tokenAddress: String
        let name: String?
        let symbol: String?
        let decimals: Int
        let balance: String
        let logo: String?
        let thumbnail: String?
        
        enum CodingKeys: String, CodingKey {
            case tokenAddress = "token_address"
            case name, symbol, decimals, balance, logo, thumbnail
        }
        
        var balanceDecimal: Double {
            guard let balanceInt = Double(balance) else { return 0 }
            return balanceInt / pow(10, Double(decimals))
        }
    }
    
    struct TransactionHistoryResponse: Codable {
        let result: [MoralisTransaction]
        let cursor: String?
    }
    
    struct MoralisTransaction: Codable, Identifiable {
        let hash: String
        let nonce: String?
        let transactionIndex: String?
        let fromAddress: String
        let toAddress: String?
        let value: String
        let gas: String?
        let gasPrice: String?
        let blockTimestamp: String?
        let blockNumber: String?
        let blockHash: String?
        let receiptStatus: String?
        
        var id: String { hash }
        
        enum CodingKeys: String, CodingKey {
            case hash, nonce, value, gas
            case transactionIndex = "transaction_index"
            case fromAddress = "from_address"
            case toAddress = "to_address"
            case gasPrice = "gas_price"
            case blockTimestamp = "block_timestamp"
            case blockNumber = "block_number"
            case blockHash = "block_hash"
            case receiptStatus = "receipt_status"
        }
        
        var valueETH: Double {
            guard let val = Double(value) else { return 0 }
            return val / 1_000_000_000_000_000_000
        }
        
        var timestamp: Date? {
            guard let ts = blockTimestamp else { return nil }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: ts) ?? ISO8601DateFormatter().date(from: ts)
        }
    }
    
    struct TokenTransferResponse: Codable {
        let result: [TokenTransfer]
        let cursor: String?
    }
    
    struct TokenTransfer: Codable, Identifiable {
        let transactionHash: String
        let tokenAddress: String
        let fromAddress: String
        let toAddress: String
        let value: String
        let tokenDecimals: Int
        let tokenName: String?
        let tokenSymbol: String?
        let blockTimestamp: String?
        
        var id: String { transactionHash + tokenAddress }
        
        enum CodingKeys: String, CodingKey {
            case value
            case transactionHash = "transaction_hash"
            case tokenAddress = "token_address"
            case fromAddress = "from_address"
            case toAddress = "to_address"
            case tokenDecimals = "token_decimals"
            case tokenName = "token_name"
            case tokenSymbol = "token_symbol"
            case blockTimestamp = "block_timestamp"
        }
        
        var valueDecimal: Double {
            guard let val = Double(value) else { return 0 }
            return val / pow(10, Double(tokenDecimals))
        }
    }
    
    struct SolanaBalanceResponse: Codable {
        let lamports: String
        let solana: String
    }
    
    struct SolanaToken: Codable, Identifiable {
        let associatedTokenAddress: String
        let mint: String
        let name: String?
        let symbol: String?
        let amount: String
        let decimals: Int
        
        var id: String { mint }
        
        enum CodingKeys: String, CodingKey {
            case associatedTokenAddress, mint, name, symbol, amount, decimals
        }
        
        var balanceDecimal: Double {
            guard let amt = Double(amount) else { return 0 }
            return amt / pow(10, Double(decimals))
        }
    }
    
    struct TokenPrice: Codable {
        let tokenAddress: String?
        let usdPrice: Double
        let usdPriceFormatted: String?
        let exchangeName: String?
        let exchangeAddress: String?
        
        enum CodingKeys: String, CodingKey {
            case usdPrice
            case tokenAddress = "tokenAddress"
            case usdPriceFormatted = "usdPriceFormatted"
            case exchangeName = "exchangeName"
            case exchangeAddress = "exchangeAddress"
        }
    }
}

// MARK: - Errors

enum MoralisError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case rateLimited
    case httpError(Int)
    case decodingError(Error)
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "Moralis API key not configured. Add it in Settings > API Keys."
        case .invalidResponse:
            return "Invalid response from Moralis API."
        case .rateLimited:
            return "Rate limited. Please wait a moment."
        case .httpError(let code):
            return "HTTP error \(code) from Moralis API."
        case .decodingError(let error):
            return "Failed to decode Moralis response: \(error.localizedDescription)"
        }
    }
}
