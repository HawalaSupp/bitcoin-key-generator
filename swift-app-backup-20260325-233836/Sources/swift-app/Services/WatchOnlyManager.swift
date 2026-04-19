import Foundation

// MARK: - Watch-Only Wallet Models

/// Blockchain types for watch-only addresses
enum WatchOnlyChain: String, CaseIterable, Codable {
    case bitcoin = "bitcoin"
    case ethereum = "ethereum"
    case litecoin = "litecoin"
    case solana = "solana"
    case bnb = "bnb"
    case xrp = "xrp"
    case monero = "monero"
    
    var displayName: String {
        switch self {
        case .bitcoin: return "Bitcoin"
        case .ethereum: return "Ethereum"
        case .litecoin: return "Litecoin"
        case .solana: return "Solana"
        case .bnb: return "BNB Chain"
        case .xrp: return "XRP"
        case .monero: return "Monero"
        }
    }
    
    var symbol: String {
        switch self {
        case .bitcoin: return "BTC"
        case .ethereum: return "ETH"
        case .litecoin: return "LTC"
        case .solana: return "SOL"
        case .bnb: return "BNB"
        case .xrp: return "XRP"
        case .monero: return "XMR"
        }
    }
    
    var iconName: String {
        switch self {
        case .bitcoin: return "bitcoinsign.circle.fill"
        case .ethereum: return "e.circle.fill"
        case .litecoin: return "l.circle.fill"
        case .solana: return "s.circle.fill"
        case .bnb: return "b.circle.fill"
        case .xrp: return "x.circle.fill"
        case .monero: return "m.circle.fill"
        }
    }
    
    /// Address validation regex patterns
    var addressPattern: String {
        switch self {
        case .bitcoin: return "^(1|3|bc1)[a-zA-HJ-NP-Z0-9]{25,62}$"
        case .ethereum, .bnb: return "^0x[a-fA-F0-9]{40}$"
        case .litecoin: return "^(L|M|ltc1)[a-zA-HJ-NP-Z0-9]{25,62}$"
        case .solana: return "^[1-9A-HJ-NP-Za-km-z]{32,44}$"
        case .xrp: return "^r[1-9A-HJ-NP-Za-km-z]{24,34}$"
        case .monero: return "^4[0-9AB][1-9A-HJ-NP-Za-km-z]{93}$"
        }
    }
    
    func validateAddress(_ address: String) -> Bool {
        let pattern = addressPattern
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return false
        }
        let range = NSRange(address.startIndex..., in: address)
        return regex.firstMatch(in: address, options: [], range: range) != nil
    }
}

/// Watch-only wallet entry
struct WatchOnlyWallet: Identifiable, Codable, Equatable {
    let id: UUID
    var label: String
    let address: String
    let chain: WatchOnlyChain
    let dateAdded: Date
    var lastBalance: Double?
    var lastBalanceUpdate: Date?
    var notes: String?
    
    init(id: UUID = UUID(), label: String, address: String, chain: WatchOnlyChain, notes: String? = nil) {
        self.id = id
        self.label = label
        self.address = address
        self.chain = chain
        self.dateAdded = Date()
        self.notes = notes
    }
    
    var formattedBalance: String {
        guard let balance = lastBalance else { return "--" }
        return String(format: "%.8f %@", balance, chain.symbol)
    }
}

/// Balance fetch result
struct WatchOnlyBalance {
    let walletId: UUID
    let balance: Double
    let usdValue: Double?
    let fetchTime: Date
}

// MARK: - Watch-Only Manager

@MainActor
final class WatchOnlyManager: ObservableObject {
    static let shared = WatchOnlyManager()
    
    @Published var wallets: [WatchOnlyWallet] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var totalPortfolioValue: Double = 0
    
    private let storageKey = "hawala_watch_only_wallets"
    
    private init() {
        loadWallets()
    }
    
    // MARK: - Persistence
    
    private func loadWallets() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([WatchOnlyWallet].self, from: data) else {
            return
        }
        wallets = decoded
    }
    
    private func saveWallets() {
        guard let data = try? JSONEncoder().encode(wallets) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
    
    // MARK: - Wallet Management
    
    func addWallet(label: String, address: String, chain: WatchOnlyChain, notes: String? = nil) throws {
        // Validate address format
        guard chain.validateAddress(address) else {
            throw WatchOnlyError.invalidAddress
        }
        
        // Check for duplicates
        if wallets.contains(where: { $0.address.lowercased() == address.lowercased() && $0.chain == chain }) {
            throw WatchOnlyError.duplicateAddress
        }
        
        let wallet = WatchOnlyWallet(label: label, address: address, chain: chain, notes: notes)
        wallets.append(wallet)
        saveWallets()
        
        // Fetch initial balance
        Task {
            await refreshBalance(for: wallet.id)
        }
    }
    
    func removeWallet(_ wallet: WatchOnlyWallet) {
        wallets.removeAll { $0.id == wallet.id }
        saveWallets()
        calculateTotalValue()
    }
    
    func updateWalletLabel(_ walletId: UUID, newLabel: String) {
        guard let index = wallets.firstIndex(where: { $0.id == walletId }) else { return }
        wallets[index].label = newLabel
        saveWallets()
    }
    
    func updateWalletNotes(_ walletId: UUID, notes: String?) {
        guard let index = wallets.firstIndex(where: { $0.id == walletId }) else { return }
        wallets[index].notes = notes
        saveWallets()
    }
    
    // MARK: - Balance Fetching
    
    func refreshAllBalances() async {
        isLoading = true
        error = nil
        
        await withTaskGroup(of: Void.self) { group in
            for wallet in wallets {
                group.addTask { [weak self] in
                    await self?.refreshBalance(for: wallet.id)
                }
            }
        }
        
        isLoading = false
        calculateTotalValue()
    }
    
    func refreshBalance(for walletId: UUID) async {
        guard let index = wallets.firstIndex(where: { $0.id == walletId }) else { return }
        let wallet = wallets[index]
        
        do {
            let balance = try await fetchBalance(address: wallet.address, chain: wallet.chain)
            await MainActor.run {
                wallets[index].lastBalance = balance
                wallets[index].lastBalanceUpdate = Date()
                saveWallets()
                calculateTotalValue()
            }
        } catch {
            print("Failed to fetch balance for \(wallet.address): \(error)")
        }
    }
    
    private func fetchBalance(address: String, chain: WatchOnlyChain) async throws -> Double {
        // Build API URL based on chain
        let urlString: String
        
        switch chain {
        case .bitcoin:
            urlString = "https://blockchain.info/q/addressbalance/\(address)"
        case .ethereum:
            // Using public API - in production use your own node or paid API
            urlString = "https://api.etherscan.io/api?module=account&action=balance&address=\(address)&tag=latest"
        case .litecoin:
            urlString = "https://api.blockchair.com/litecoin/dashboards/address/\(address)"
        case .solana:
            // Solana requires JSON-RPC
            return try await fetchSolanaBalance(address: address)
        case .bnb:
            urlString = "https://api.bscscan.com/api?module=account&action=balance&address=\(address)"
        case .xrp:
            urlString = "https://api.xrpscan.com/api/v1/account/\(address)"
        case .monero:
            // Monero requires view key for balance - return 0 for now
            return 0
        }
        
        guard let url = URL(string: urlString) else {
            throw WatchOnlyError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        // Parse response based on chain
        return try parseBalanceResponse(data: data, chain: chain)
    }
    
    private func fetchSolanaBalance(address: String) async throws -> Double {
        guard let url = URL(string: "https://api.mainnet-beta.solana.com") else {
            throw WatchOnlyError.invalidURL
        }
        
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
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let value = result["value"] as? Int else {
            throw WatchOnlyError.parseError
        }
        
        // Convert lamports to SOL
        return Double(value) / 1_000_000_000
    }
    
    private func parseBalanceResponse(data: Data, chain: WatchOnlyChain) throws -> Double {
        switch chain {
        case .bitcoin:
            // Returns satoshis as plain number
            guard let satoshis = String(data: data, encoding: .utf8).flatMap({ Double($0) }) else {
                throw WatchOnlyError.parseError
            }
            return satoshis / 100_000_000
            
        case .ethereum, .bnb:
            // Returns JSON with result in wei
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = json["result"] as? String,
                  let wei = Double(result) else {
                throw WatchOnlyError.parseError
            }
            return wei / 1_000_000_000_000_000_000
            
        case .litecoin:
            // Blockchair returns nested JSON
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataDict = json["data"] as? [String: Any],
                  let addresses = dataDict.values.first as? [String: Any],
                  let address = addresses["address"] as? [String: Any],
                  let balance = address["balance"] as? Double else {
                throw WatchOnlyError.parseError
            }
            return balance / 100_000_000
            
        case .xrp:
            // XRPScan returns account info
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let xrpBalance = json["xrpBalance"] as? String,
                  let balance = Double(xrpBalance) else {
                throw WatchOnlyError.parseError
            }
            return balance
            
        default:
            return 0
        }
    }
    
    // MARK: - Portfolio Value
    
    private func calculateTotalValue() {
        // In a real app, fetch current prices and calculate USD value
        // For now, just sum balances weighted by approximate prices
        let prices: [WatchOnlyChain: Double] = [
            .bitcoin: 100_000,
            .ethereum: 3_500,
            .litecoin: 100,
            .solana: 150,
            .bnb: 600,
            .xrp: 2.5,
            .monero: 180
        ]
        
        totalPortfolioValue = wallets.compactMap { wallet -> Double? in
            guard let balance = wallet.lastBalance,
                  let price = prices[wallet.chain] else { return nil }
            return balance * price
        }.reduce(0, +)
    }
    
    // MARK: - Export
    
    func exportAddresses() -> String {
        var csv = "Label,Chain,Address,Balance,Notes\n"
        for wallet in wallets {
            let balance = wallet.lastBalance.map { String($0) } ?? ""
            let notes = wallet.notes ?? ""
            csv += "\"\(wallet.label)\",\(wallet.chain.symbol),\(wallet.address),\(balance),\"\(notes)\"\n"
        }
        return csv
    }
    
    // MARK: - Filtering
    
    func wallets(for chain: WatchOnlyChain) -> [WatchOnlyWallet] {
        wallets.filter { $0.chain == chain }
    }
    
    func searchWallets(query: String) -> [WatchOnlyWallet] {
        guard !query.isEmpty else { return wallets }
        let lowercased = query.lowercased()
        return wallets.filter {
            $0.label.lowercased().contains(lowercased) ||
            $0.address.lowercased().contains(lowercased) ||
            ($0.notes?.lowercased().contains(lowercased) ?? false)
        }
    }
}

// MARK: - Errors

enum WatchOnlyError: LocalizedError {
    case invalidAddress
    case duplicateAddress
    case invalidURL
    case parseError
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidAddress: return "Invalid address format for this chain"
        case .duplicateAddress: return "This address is already being watched"
        case .invalidURL: return "Invalid API URL"
        case .parseError: return "Failed to parse balance response"
        case .networkError(let message): return "Network error: \(message)"
        }
    }
}
