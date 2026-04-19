import Foundation

// MARK: - Unified Blockchain Data Provider
/// Provides reliable blockchain data with intelligent fallback between providers
/// Priority: Moralis (Trust Wallet/Exodus) → Alchemy → Tatum → Public APIs

@MainActor
final class UnifiedBlockchainProvider: ObservableObject {
    static let shared = UnifiedBlockchainProvider()
    
    // MARK: - Provider References
    
    private let moralis = MoralisAPI.shared
    private let apiKeys = APIKeys.shared
    
    // MARK: - Chain Mapping
    
    enum SupportedChain: String, CaseIterable, Codable {
        case bitcoin = "bitcoin"
        case bitcoinTestnet = "bitcoin-testnet"
        case litecoin = "litecoin"
        case ethereum = "ethereum"
        case ethereumSepolia = "ethereum-sepolia"
        case polygon = "polygon"
        case bnb = "bnb"
        case arbitrum = "arbitrum"
        case optimism = "optimism"
        case base = "base"
        case avalanche = "avalanche"
        case solana = "solana"
        case solanaDevnet = "solana-devnet"
        case xrp = "xrp"
        case xrpTestnet = "xrp-testnet"
        
        var moralisChain: MoralisAPI.Chain? {
            switch self {
            case .ethereum: return .ethereum
            case .ethereumSepolia: return .sepolia
            case .polygon: return .polygon
            case .bnb: return .bsc
            case .arbitrum: return .arbitrum
            case .optimism: return .optimism
            case .base: return .base
            case .avalanche: return .avalanche
            case .solana: return .solana
            case .solanaDevnet: return .solanaDevnet
            default: return nil
            }
        }
        
        var alchemyChain: APIKeys.AlchemyChain? {
            switch self {
            case .ethereum: return .ethereumMainnet
            case .ethereumSepolia: return .ethereumSepolia
            case .polygon: return .polygonMainnet
            case .arbitrum: return .arbitrumMainnet
            case .optimism: return .optimismMainnet
            case .base: return .baseMainnet
            case .solana: return .solanaMainnet
            case .solanaDevnet: return .solanaDevnet
            default: return nil
            }
        }
        
        var isEVM: Bool {
            switch self {
            case .ethereum, .ethereumSepolia, .polygon, .bnb, .arbitrum, .optimism, .base, .avalanche:
                return true
            default:
                return false
            }
        }
        
        var isBitcoinLike: Bool {
            switch self {
            case .bitcoin, .bitcoinTestnet, .litecoin:
                return true
            default:
                return false
            }
        }
    }
    
    // MARK: - Balance Fetching
    
    /// Fetch native balance with automatic provider fallback
    func fetchBalance(address: String, chain: SupportedChain) async throws -> Double {
        var lastError: Error?
        
        // Provider 1: Moralis (best for EVM chains)
        if let moralisChain = chain.moralisChain, apiKeys.hasMoralisKey {
            do {
                if chain == .solana || chain == .solanaDevnet {
                    return try await moralis.getSolanaBalance(address: address, network: moralisChain)
                } else {
                    return try await moralis.getNativeBalance(address: address, chain: moralisChain)
                }
            } catch {
                #if DEBUG
                print("⚠️ Moralis balance failed for \(chain): \(error.localizedDescription)")
                #endif
                lastError = error
            }
        }
        
        // Provider 2: Alchemy
        if let alchemyChain = chain.alchemyChain, apiKeys.hasAlchemyKey {
            do {
                return try await fetchBalanceViaAlchemy(address: address, chain: alchemyChain)
            } catch {
                #if DEBUG
                print("⚠️ Alchemy balance failed for \(chain): \(error.localizedDescription)")
                #endif
                lastError = error
            }
        }
        
        // Provider 3: Chain-specific public APIs
        do {
            return try await fetchBalanceViaPublicAPI(address: address, chain: chain)
        } catch {
            #if DEBUG
            print("⚠️ Public API balance failed for \(chain): \(error.localizedDescription)")
            #endif
            lastError = error
        }
        
        throw lastError ?? UnifiedProviderError.allProvidersFailed
    }
    
    // MARK: - Transaction History
    
    /// Fetch transaction history with automatic provider fallback
    func fetchTransactionHistory(address: String, chain: SupportedChain, limit: Int = 50) async throws -> [UnifiedTransaction] {
        var lastError: Error?
        
        // Provider 1: Moralis (excellent for EVM)
        if let moralisChain = chain.moralisChain, apiKeys.hasMoralisKey {
            do {
                let txs = try await moralis.getTransactions(address: address, chain: moralisChain, limit: limit)
                return txs.map { UnifiedTransaction(from: $0, chain: chain, userAddress: address) }
            } catch {
                #if DEBUG
                print("⚠️ Moralis history failed for \(chain): \(error.localizedDescription)")
                #endif
                lastError = error
            }
        }
        
        // Provider 2: Chain-specific public APIs
        do {
            return try await fetchHistoryViaPublicAPI(address: address, chain: chain, limit: limit)
        } catch {
            #if DEBUG
            print("⚠️ Public API history failed for \(chain): \(error.localizedDescription)")
            #endif
            lastError = error
        }
        
        throw lastError ?? UnifiedProviderError.allProvidersFailed
    }
    
    // MARK: - Alchemy Integration
    
    private func fetchBalanceViaAlchemy(address: String, chain: APIKeys.AlchemyChain) async throws -> Double {
        guard let baseURL = apiKeys.alchemyBaseURL(for: chain) else {
            throw UnifiedProviderError.noAPIKey
        }
        
        let url = URL(string: baseURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Different RPC methods for different chains
        let body: [String: Any]
        if chain == .solanaMainnet || chain == .solanaDevnet {
            body = [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "getBalance",
                "params": [address]
            ]
        } else {
            body = [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "eth_getBalance",
                "params": [address, "latest"]
            ]
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        if chain == .solanaMainnet || chain == .solanaDevnet {
            struct SolanaResponse: Codable {
                struct Result: Codable {
                    let value: Int
                }
                let result: Result
            }
            let response = try JSONDecoder().decode(SolanaResponse.self, from: data)
            return Double(response.result.value) / 1_000_000_000 // lamports to SOL
        } else {
            struct EVMResponse: Codable {
                let result: String
            }
            let response = try JSONDecoder().decode(EVMResponse.self, from: data)
            let hexValue = response.result.hasPrefix("0x") ? String(response.result.dropFirst(2)) : response.result
            if let weiValue = UInt64(hexValue, radix: 16) {
                return Double(weiValue) / 1_000_000_000_000_000_000
            }
        }
        
        return 0
    }
    
    // MARK: - Public API Fallbacks
    
    private func fetchBalanceViaPublicAPI(address: String, chain: SupportedChain) async throws -> Double {
        switch chain {
        case .bitcoin:
            return try await fetchBitcoinBalanceViaMempool(address: address, isTestnet: false)
        case .bitcoinTestnet:
            return try await fetchBitcoinBalanceViaMempool(address: address, isTestnet: true)
        case .litecoin:
            return try await fetchLitecoinBalanceViaBlockcypher(address: address)
        case .ethereum, .ethereumSepolia:
            // Fallback to Etherscan
            return try await fetchEthereumBalanceViaEtherscan(address: address, isTestnet: chain == .ethereumSepolia)
        case .solana, .solanaDevnet:
            return try await fetchSolanaBalanceViaRPC(address: address, isDevnet: chain == .solanaDevnet)
        case .xrp, .xrpTestnet:
            return try await fetchXRPBalanceViaRPC(address: address, isTestnet: chain == .xrpTestnet)
        case .bnb:
            return try await fetchBNBBalanceViaBscScan(address: address)
        default:
            throw UnifiedProviderError.unsupportedChain
        }
    }
    
    private func fetchHistoryViaPublicAPI(address: String, chain: SupportedChain, limit: Int) async throws -> [UnifiedTransaction] {
        switch chain {
        case .bitcoin:
            return try await fetchBitcoinHistoryViaMempool(address: address, isTestnet: false)
        case .bitcoinTestnet:
            return try await fetchBitcoinHistoryViaMempool(address: address, isTestnet: true)
        case .ethereum, .ethereumSepolia:
            return try await fetchEthereumHistoryViaEtherscan(address: address, isTestnet: chain == .ethereumSepolia, limit: limit)
        default:
            throw UnifiedProviderError.unsupportedChain
        }
    }
    
    // MARK: - Bitcoin via Mempool.space
    
    private func fetchBitcoinBalanceViaMempool(address: String, isTestnet: Bool) async throws -> Double {
        let baseURL = isTestnet ? "https://mempool.space/testnet/api" : "https://mempool.space/api"
        let url = URL(string: "\(baseURL)/address/\(address)")!
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        struct AddressInfo: Codable {
            struct ChainStats: Codable {
                let funded_txo_sum: Int
                let spent_txo_sum: Int
            }
            let chain_stats: ChainStats
            let mempool_stats: ChainStats
        }
        
        let info = try JSONDecoder().decode(AddressInfo.self, from: data)
        let confirmedBalance = info.chain_stats.funded_txo_sum - info.chain_stats.spent_txo_sum
        let pendingBalance = info.mempool_stats.funded_txo_sum - info.mempool_stats.spent_txo_sum
        
        return Double(confirmedBalance + pendingBalance) / 100_000_000 // satoshis to BTC
    }
    
    private func fetchBitcoinHistoryViaMempool(address: String, isTestnet: Bool) async throws -> [UnifiedTransaction] {
        let baseURL = isTestnet ? "https://mempool.space/testnet/api" : "https://mempool.space/api"
        let url = URL(string: "\(baseURL)/address/\(address)/txs")!
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        struct MempoolTx: Codable {
            let txid: String
            let status: TxStatus
            let vin: [Vin]
            let vout: [Vout]
            
            struct TxStatus: Codable {
                let confirmed: Bool
                let block_time: Int?
            }
            struct Vin: Codable {
                let prevout: Prevout?
                struct Prevout: Codable {
                    let scriptpubkey_address: String?
                    let value: Int
                }
            }
            struct Vout: Codable {
                let scriptpubkey_address: String?
                let value: Int
            }
        }
        
        let txs = try JSONDecoder().decode([MempoolTx].self, from: data)
        
        return txs.map { tx in
            let isSend = tx.vin.contains { $0.prevout?.scriptpubkey_address == address }
            let totalIn = tx.vin.filter { $0.prevout?.scriptpubkey_address == address }.reduce(0) { $0 + ($1.prevout?.value ?? 0) }
            let totalOut = tx.vout.filter { $0.scriptpubkey_address == address }.reduce(0) { $0 + $1.value }
            let netValue = isSend ? totalIn - totalOut : totalOut - totalIn
            
            return UnifiedTransaction(
                id: tx.txid,
                hash: tx.txid,
                from: isSend ? address : "Unknown",
                to: isSend ? "Multiple" : address,
                value: Double(abs(netValue)) / 100_000_000,
                timestamp: tx.status.block_time.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                status: tx.status.confirmed ? .confirmed : .pending,
                type: isSend ? .send : .receive,
                chain: isTestnet ? .bitcoinTestnet : .bitcoin
            )
        }
    }
    
    // MARK: - Litecoin via Blockcypher
    
    private func fetchLitecoinBalanceViaBlockcypher(address: String) async throws -> Double {
        let url = URL(string: "https://api.blockcypher.com/v1/ltc/main/addrs/\(address)/balance")!
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        struct BalanceResponse: Codable {
            let balance: Int
            let unconfirmed_balance: Int
        }
        
        let response = try JSONDecoder().decode(BalanceResponse.self, from: data)
        return Double(response.balance + response.unconfirmed_balance) / 100_000_000
    }
    
    // MARK: - Ethereum via Etherscan
    
    private func fetchEthereumBalanceViaEtherscan(address: String, isTestnet: Bool) async throws -> Double {
        let baseURL = isTestnet ? "https://api-sepolia.etherscan.io/api" : "https://api.etherscan.io/api"
        let url = URL(string: "\(baseURL)?module=account&action=balance&address=\(address)&tag=latest")!
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        struct EtherscanResponse: Codable {
            let result: String
        }
        
        let response = try JSONDecoder().decode(EtherscanResponse.self, from: data)
        if let weiValue = Double(response.result) {
            return weiValue / 1_000_000_000_000_000_000
        }
        return 0
    }
    
    private func fetchEthereumHistoryViaEtherscan(address: String, isTestnet: Bool, limit: Int) async throws -> [UnifiedTransaction] {
        let baseURL = isTestnet ? "https://api-sepolia.etherscan.io/api" : "https://api.etherscan.io/api"
        let url = URL(string: "\(baseURL)?module=account&action=txlist&address=\(address)&startblock=0&endblock=99999999&page=1&offset=\(limit)&sort=desc")!
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        struct EtherscanTxResponse: Codable {
            let result: [EtherscanTx]
        }
        struct EtherscanTx: Codable {
            let hash: String
            let from: String
            let to: String
            let value: String
            let timeStamp: String
            let isError: String?
        }
        
        let response = try JSONDecoder().decode(EtherscanTxResponse.self, from: data)
        
        return response.result.map { tx in
            let isSend = tx.from.lowercased() == address.lowercased()
            let timestamp = Double(tx.timeStamp).map { Date(timeIntervalSince1970: $0) }
            let value = (Double(tx.value) ?? 0) / 1_000_000_000_000_000_000
            
            return UnifiedTransaction(
                id: tx.hash,
                hash: tx.hash,
                from: tx.from,
                to: tx.to,
                value: value,
                timestamp: timestamp,
                status: tx.isError == "0" ? .confirmed : .failed,
                type: isSend ? .send : .receive,
                chain: isTestnet ? .ethereumSepolia : .ethereum
            )
        }
    }
    
    // MARK: - Solana via RPC
    
    private func fetchSolanaBalanceViaRPC(address: String, isDevnet: Bool) async throws -> Double {
        let rpcURL = isDevnet ? "https://api.devnet.solana.com" : "https://api.mainnet-beta.solana.com"
        let url = URL(string: rpcURL)!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getBalance",
            "params": [address]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct SolanaResponse: Codable {
            struct Result: Codable {
                let value: Int
            }
            let result: Result
        }
        
        let response = try JSONDecoder().decode(SolanaResponse.self, from: data)
        return Double(response.result.value) / 1_000_000_000
    }
    
    // MARK: - XRP via RPC
    
    private func fetchXRPBalanceViaRPC(address: String, isTestnet: Bool) async throws -> Double {
        let rpcURL = isTestnet ? "https://s.altnet.rippletest.net:51234" : "https://xrplcluster.com"
        let url = URL(string: rpcURL)!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "method": "account_info",
            "params": [[
                "account": address,
                "ledger_index": "validated"
            ]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct XRPResponse: Codable {
            struct Result: Codable {
                struct AccountData: Codable {
                    let Balance: String
                }
                let account_data: AccountData?
            }
            let result: Result
        }
        
        let response = try JSONDecoder().decode(XRPResponse.self, from: data)
        if let balance = response.result.account_data?.Balance, let drops = Double(balance) {
            return drops / 1_000_000
        }
        return 0
    }
    
    // MARK: - BNB via BscScan
    
    private func fetchBNBBalanceViaBscScan(address: String) async throws -> Double {
        let url = URL(string: "https://api.bscscan.com/api?module=account&action=balance&address=\(address)&tag=latest")!
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        struct BscScanResponse: Codable {
            let result: String
        }
        
        let response = try JSONDecoder().decode(BscScanResponse.self, from: data)
        if let weiValue = Double(response.result) {
            return weiValue / 1_000_000_000_000_000_000
        }
        return 0
    }
}

// MARK: - Unified Transaction Model

struct UnifiedTransaction: Identifiable, Codable {
    let id: String
    let hash: String
    let from: String
    let to: String
    let value: Double
    let timestamp: Date?
    let status: TransactionStatus
    let type: TransactionType
    let chain: UnifiedBlockchainProvider.SupportedChain
    
    enum TransactionStatus: String, Codable {
        case pending
        case confirmed
        case failed
    }
    
    enum TransactionType: String, Codable {
        case send
        case receive
        case swap
        case contract
    }
    
    init(id: String, hash: String, from: String, to: String, value: Double, timestamp: Date?, status: TransactionStatus, type: TransactionType, chain: UnifiedBlockchainProvider.SupportedChain) {
        self.id = id
        self.hash = hash
        self.from = from
        self.to = to
        self.value = value
        self.timestamp = timestamp
        self.status = status
        self.type = type
        self.chain = chain
    }
    
    init(from moralisTx: MoralisAPI.MoralisTransaction, chain: UnifiedBlockchainProvider.SupportedChain, userAddress: String) {
        self.id = moralisTx.hash
        self.hash = moralisTx.hash
        self.from = moralisTx.fromAddress
        self.to = moralisTx.toAddress ?? ""
        self.value = moralisTx.valueETH
        self.timestamp = moralisTx.timestamp
        self.status = moralisTx.receiptStatus == "1" ? .confirmed : .pending
        self.type = moralisTx.fromAddress.lowercased() == userAddress.lowercased() ? .send : .receive
        self.chain = chain
    }
}

// MARK: - Errors

enum UnifiedProviderError: LocalizedError {
    case noAPIKey
    case allProvidersFailed
    case unsupportedChain
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured for this provider."
        case .allProvidersFailed:
            return "All providers failed. Check your internet connection."
        case .unsupportedChain:
            return "This blockchain is not supported."
        case .invalidResponse:
            return "Invalid response from provider."
        }
    }
}
