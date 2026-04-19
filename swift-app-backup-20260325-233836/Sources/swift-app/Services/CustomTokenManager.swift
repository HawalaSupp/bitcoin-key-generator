import SwiftUI
import Foundation

// MARK: - Custom Token Models

/// Represents a custom ERC-20 or SPL token added by the user
struct CustomToken: Identifiable, Codable, Equatable {
    let id: UUID
    let contractAddress: String
    let symbol: String
    let name: String
    let decimals: Int
    let chain: TokenChain
    let logoURL: String?
    let addedAt: Date
    
    var chainId: String {
        switch chain {
        case .ethereum: return "\(symbol.lowercased())-erc20"
        case .bsc: return "\(symbol.lowercased())-bep20"
        case .solana: return "\(symbol.lowercased())-spl"
        }
    }
    
    init(id: UUID = UUID(), contractAddress: String, symbol: String, name: String, decimals: Int, chain: TokenChain, logoURL: String? = nil, addedAt: Date = Date()) {
        self.id = id
        self.contractAddress = contractAddress
        self.symbol = symbol
        self.name = name
        self.decimals = decimals
        self.chain = chain
        self.logoURL = logoURL
        self.addedAt = addedAt
    }
}

enum TokenChain: String, CaseIterable, Codable, Identifiable {
    case ethereum = "ethereum"
    case bsc = "bsc"
    case solana = "solana"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .ethereum: return "Ethereum (ERC-20)"
        case .bsc: return "BNB Chain (BEP-20)"
        case .solana: return "Solana (SPL)"
        }
    }
    
    var icon: String {
        switch self {
        case .ethereum: return "diamond.fill"
        case .bsc: return "bitcoinsign.circle.fill"
        case .solana: return "sun.max.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .ethereum: return HawalaTheme.Colors.ethereum
        case .bsc: return HawalaTheme.Colors.bnb
        case .solana: return HawalaTheme.Colors.solana
        }
    }
    
    var addressPlaceholder: String {
        switch self {
        case .ethereum, .bsc: return "0x..."
        case .solana: return "Token mint address"
        }
    }
    
    var explorerBaseURL: String {
        switch self {
        case .ethereum: return "https://etherscan.io/token/"
        case .bsc: return "https://bscscan.com/token/"
        case .solana: return "https://solscan.io/token/"
        }
    }
}

// MARK: - Custom Token Manager

@MainActor
final class CustomTokenManager: ObservableObject {
    static let shared = CustomTokenManager()
    
    @Published var tokens: [CustomToken] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let storageKey = "hawala.customTokens"
    
    private init() {
        loadTokens()
    }
    
    // MARK: - Persistence
    
    private func loadTokens() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([CustomToken].self, from: data) else {
            return
        }
        tokens = decoded
    }
    
    private func saveTokens() {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
    
    // MARK: - Token Management
    
    func addToken(_ token: CustomToken) throws {
        // Validate not already added
        if tokens.contains(where: { $0.contractAddress.lowercased() == token.contractAddress.lowercased() && $0.chain == token.chain }) {
            throw TokenError.alreadyExists
        }
        
        tokens.append(token)
        saveTokens()
    }
    
    func removeToken(_ token: CustomToken) {
        tokens.removeAll { $0.id == token.id }
        saveTokens()
    }
    
    func getTokens(for chain: TokenChain) -> [CustomToken] {
        tokens.filter { $0.chain == chain }
    }
    
    // MARK: - Token Info Fetching
    
    /// Fetch token metadata from blockchain
    func fetchTokenInfo(contractAddress: String, chain: TokenChain) async throws -> CustomToken {
        isLoading = true
        defer { isLoading = false }
        
        switch chain {
        case .ethereum:
            return try await fetchERC20TokenInfo(contractAddress: contractAddress, chain: .ethereum, rpcURL: "https://eth-mainnet.g.alchemy.com/v2/")
        case .bsc:
            return try await fetchERC20TokenInfo(contractAddress: contractAddress, chain: .bsc, rpcURL: "https://bsc-dataseed.binance.org/")
        case .solana:
            return try await fetchSPLTokenInfo(mintAddress: contractAddress)
        }
    }
    
    private func fetchERC20TokenInfo(contractAddress: String, chain: TokenChain, rpcURL: String) async throws -> CustomToken {
        // Fetch name, symbol, decimals via eth_call
        
        // Name: keccak256("name()")[:4] = 0x06fdde03
        let nameData = try await callContract(contractAddress: contractAddress, data: "0x06fdde03", rpcURL: rpcURL)
        let name = decodeString(from: nameData)
        
        // Symbol: keccak256("symbol()")[:4] = 0x95d89b41
        let symbolData = try await callContract(contractAddress: contractAddress, data: "0x95d89b41", rpcURL: rpcURL)
        let symbol = decodeString(from: symbolData)
        
        // Decimals: keccak256("decimals()")[:4] = 0x313ce567
        let decimalsData = try await callContract(contractAddress: contractAddress, data: "0x313ce567", rpcURL: rpcURL)
        let decimals = decodeUint(from: decimalsData)
        
        guard !name.isEmpty, !symbol.isEmpty else {
            throw TokenError.invalidContract
        }
        
        return CustomToken(
            contractAddress: contractAddress,
            symbol: symbol,
            name: name,
            decimals: decimals,
            chain: chain
        )
    }
    
    private func callContract(contractAddress: String, data: String, rpcURL: String) async throws -> String {
        // Build RPC request
        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "eth_call",
            "params": [
                ["to": contractAddress, "data": data],
                "latest"
            ]
        ]
        
        guard let url = URL(string: rpcURL) else {
            throw TokenError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TokenError.networkError
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? String else {
            throw TokenError.invalidResponse
        }
        
        return result
    }
    
    private func decodeString(from hex: String) -> String {
        // ABI decoding for string: skip offset (32 bytes), length (32 bytes), then read string
        guard hex.count > 130 else { return "" } // 0x + 64 + 64 + at least something
        
        let cleanHex = String(hex.dropFirst(2)) // Remove 0x
        guard cleanHex.count >= 128 else { return "" }
        
        // Get length from bytes 32-64 (64-128 in hex)
        let lengthHex = String(cleanHex[cleanHex.index(cleanHex.startIndex, offsetBy: 64)..<cleanHex.index(cleanHex.startIndex, offsetBy: 128)])
        guard let length = Int(lengthHex, radix: 16), length > 0, length < 100 else { return "" }
        
        // Get string data starting at byte 64 (128 in hex)
        let startIndex = cleanHex.index(cleanHex.startIndex, offsetBy: 128)
        let endIndex = cleanHex.index(startIndex, offsetBy: min(length * 2, cleanHex.count - 128))
        let stringHex = String(cleanHex[startIndex..<endIndex])
        
        // Convert hex to string
        var chars: [Character] = []
        var index = stringHex.startIndex
        while index < stringHex.endIndex {
            let nextIndex = stringHex.index(index, offsetBy: 2, limitedBy: stringHex.endIndex) ?? stringHex.endIndex
            if let byte = UInt8(String(stringHex[index..<nextIndex]), radix: 16), byte > 0 {
                chars.append(Character(UnicodeScalar(byte)))
            }
            index = nextIndex
        }
        
        return String(chars).trimmingCharacters(in: .whitespaces)
    }
    
    private func decodeUint(from hex: String) -> Int {
        guard hex.count > 2 else { return 18 } // Default to 18 decimals
        let cleanHex = String(hex.dropFirst(2))
        return Int(cleanHex, radix: 16) ?? 18
    }
    
    private func fetchSPLTokenInfo(mintAddress: String) async throws -> CustomToken {
        // For Solana, we query the token metadata using Helius API or Solscan
        // First try Helius (has good metadata support)
        
        let heliusURL = "https://api.helius.xyz/v0/token-metadata?api-key=15e18f63-9f81-4c92-9a18-e3bc3e90e28f"
        
        guard let url = URL(string: heliusURL) else {
            throw TokenError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "mintAccounts": [mintAddress]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            // Fallback to Solscan if Helius fails
            return try await fetchSPLTokenInfoViaSolscan(mintAddress: mintAddress)
        }
        
        // Parse Helius response
        if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let tokenData = jsonArray.first {
            
            let onChainMetadata = tokenData["onChainMetadata"] as? [String: Any]
            let offChainMetadata = tokenData["offChainMetadata"] as? [String: Any]
            let legacyMetadata = tokenData["legacyMetadata"] as? [String: Any]
            
            // Try to get symbol and name from various sources
            var symbol = ""
            var name = ""
            var decimals = 9 // SPL default
            var logoURL: String?
            
            // From on-chain metadata
            if let metadata = onChainMetadata?["metadata"] as? [String: Any] {
                if let data = metadata["data"] as? [String: Any] {
                    symbol = (data["symbol"] as? String)?.trimmingCharacters(in: .whitespaces.union(.controlCharacters)) ?? ""
                    name = (data["name"] as? String)?.trimmingCharacters(in: .whitespaces.union(.controlCharacters)) ?? ""
                }
            }
            
            // From off-chain metadata (usually better)
            if let offChain = offChainMetadata?["metadata"] as? [String: Any] {
                if symbol.isEmpty {
                    symbol = (offChain["symbol"] as? String)?.trimmingCharacters(in: .whitespaces.union(.controlCharacters)) ?? ""
                }
                if name.isEmpty {
                    name = (offChain["name"] as? String)?.trimmingCharacters(in: .whitespaces.union(.controlCharacters)) ?? ""
                }
                logoURL = offChain["image"] as? String
            }
            
            // From legacy metadata
            if let legacy = legacyMetadata {
                if symbol.isEmpty {
                    symbol = (legacy["symbol"] as? String) ?? ""
                }
                if name.isEmpty {
                    name = (legacy["name"] as? String) ?? ""
                }
                if logoURL == nil {
                    logoURL = legacy["logoURI"] as? String
                }
                if let dec = legacy["decimals"] as? Int {
                    decimals = dec
                }
            }
            
            // Get decimals from account info
            if let account = tokenData["account"] as? [String: Any],
               let accountData = account["data"] as? [String: Any],
               let parsed = accountData["parsed"] as? [String: Any],
               let info = parsed["info"] as? [String: Any],
               let dec = info["decimals"] as? Int {
                decimals = dec
            }
            
            if !symbol.isEmpty && !name.isEmpty {
                return CustomToken(
                    contractAddress: mintAddress,
                    symbol: symbol,
                    name: name,
                    decimals: decimals,
                    chain: .solana,
                    logoURL: logoURL
                )
            }
        }
        
        // Fallback to Solscan
        return try await fetchSPLTokenInfoViaSolscan(mintAddress: mintAddress)
    }
    
    private func fetchSPLTokenInfoViaSolscan(mintAddress: String) async throws -> CustomToken {
        // Use Solscan public API
        let urlString = "https://public-api.solscan.io/token/meta?tokenAddress=\(mintAddress)"
        
        guard let url = URL(string: urlString) else {
            throw TokenError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TokenError.invalidContract
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TokenError.invalidResponse
        }
        
        let symbol = (json["symbol"] as? String) ?? ""
        let name = (json["name"] as? String) ?? ""
        let decimals = (json["decimals"] as? Int) ?? 9
        let logoURL = json["icon"] as? String
        
        guard !symbol.isEmpty else {
            throw TokenError.invalidContract
        }
        
        return CustomToken(
            contractAddress: mintAddress,
            symbol: symbol,
            name: name.isEmpty ? symbol : name,
            decimals: decimals,
            chain: .solana,
            logoURL: logoURL
        )
    }
    
    // MARK: - Token Balance Fetching
    
    /// Fetch balance for a custom token
    func fetchTokenBalance(token: CustomToken, walletAddress: String) async throws -> Decimal {
        switch token.chain {
        case .ethereum, .bsc:
            return try await fetchERC20Balance(token: token, walletAddress: walletAddress)
        case .solana:
            return try await fetchSPLBalance(token: token, walletAddress: walletAddress)
        }
    }
    
    private func fetchERC20Balance(token: CustomToken, walletAddress: String) async throws -> Decimal {
        let rpcURL = token.chain == .ethereum
            ? "https://eth-mainnet.g.alchemy.com/v2/"
            : "https://bsc-dataseed.binance.org/"
        
        // balanceOf(address): 0x70a08231 + address padded to 32 bytes
        let addressPadded = String(repeating: "0", count: 24) + walletAddress.dropFirst(2)
        let data = "0x70a08231" + addressPadded
        
        let result = try await callContract(contractAddress: token.contractAddress, data: data, rpcURL: rpcURL)
        
        // Parse the hex balance
        let cleanHex = result.hasPrefix("0x") ? String(result.dropFirst(2)) : result
        guard let balanceInt = UInt64(cleanHex, radix: 16) else {
            return 0
        }
        
        let divisor = pow(Decimal(10), token.decimals)
        return Decimal(balanceInt) / divisor
    }
    
    private func fetchSPLBalance(token: CustomToken, walletAddress: String) async throws -> Decimal {
        // Use Solana RPC to get token account balance
        let rpcURL = "https://api.mainnet-beta.solana.com"
        
        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getTokenAccountsByOwner",
            "params": [
                walletAddress,
                ["mint": token.contractAddress],
                ["encoding": "jsonParsed"]
            ]
        ]
        
        guard let url = URL(string: rpcURL) else {
            throw TokenError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TokenError.networkError
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let value = result["value"] as? [[String: Any]] else {
            return 0 // No token account = 0 balance
        }
        
        // Sum up all token accounts for this mint
        var totalBalance: Decimal = 0
        for account in value {
            if let accountData = account["account"] as? [String: Any],
               let data = accountData["data"] as? [String: Any],
               let parsed = data["parsed"] as? [String: Any],
               let info = parsed["info"] as? [String: Any],
               let tokenAmount = info["tokenAmount"] as? [String: Any],
               let uiAmount = tokenAmount["uiAmount"] as? Double {
                totalBalance += Decimal(uiAmount)
            }
        }
        
        return totalBalance
    }
    
    // MARK: - Token Auto-Detection
    
    /// Scan wallet for ERC-20 tokens with balance
    func detectERC20Tokens(walletAddress: String) async throws -> [CustomToken] {
        // Use Alchemy's getTokenBalances API
        let alchemyURL = "https://eth-mainnet.g.alchemy.com/v2/demo"
        
        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "alchemy_getTokenBalances",
            "params": [walletAddress]
        ]
        
        guard let url = URL(string: alchemyURL) else {
            throw TokenError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TokenError.networkError
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let tokenBalances = result["tokenBalances"] as? [[String: Any]] else {
            return []
        }
        
        var detectedTokens: [CustomToken] = []
        
        for tokenBalance in tokenBalances {
            guard let contractAddress = tokenBalance["contractAddress"] as? String,
                  let balanceHex = tokenBalance["tokenBalance"] as? String,
                  balanceHex != "0x0" && balanceHex != "0x" else {
                continue
            }
            
            // Skip if already in our list
            if tokens.contains(where: { $0.contractAddress.lowercased() == contractAddress.lowercased() }) {
                continue
            }
            
            // Fetch token info
            do {
                let token = try await fetchTokenInfo(contractAddress: contractAddress, chain: .ethereum)
                detectedTokens.append(token)
            } catch {
                // Skip tokens we can't fetch metadata for
                continue
            }
        }
        
        return detectedTokens
    }
    
    /// Scan wallet for SPL tokens with balance
    func detectSPLTokens(walletAddress: String) async throws -> [CustomToken] {
        let rpcURL = "https://api.mainnet-beta.solana.com"
        
        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getTokenAccountsByOwner",
            "params": [
                walletAddress,
                ["programId": "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"],
                ["encoding": "jsonParsed"]
            ]
        ]
        
        guard let url = URL(string: rpcURL) else {
            throw TokenError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TokenError.networkError
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let value = result["value"] as? [[String: Any]] else {
            return []
        }
        
        var detectedTokens: [CustomToken] = []
        var seenMints: Set<String> = Set(tokens.filter { $0.chain == .solana }.map { $0.contractAddress })
        
        for account in value {
            guard let accountData = account["account"] as? [String: Any],
                  let data = accountData["data"] as? [String: Any],
                  let parsed = data["parsed"] as? [String: Any],
                  let info = parsed["info"] as? [String: Any],
                  let mint = info["mint"] as? String,
                  let tokenAmount = info["tokenAmount"] as? [String: Any],
                  let uiAmount = tokenAmount["uiAmount"] as? Double,
                  uiAmount > 0 else {
                continue
            }
            
            // Skip if already seen
            if seenMints.contains(mint) {
                continue
            }
            seenMints.insert(mint)
            
            // Fetch token info
            do {
                let token = try await fetchTokenInfo(contractAddress: mint, chain: .solana)
                detectedTokens.append(token)
            } catch {
                // Skip tokens we can't fetch metadata for
                continue
            }
        }
        
        return detectedTokens
    }
    
    /// Add multiple detected tokens
    func addDetectedTokens(_ tokens: [CustomToken]) {
        for token in tokens {
            try? addToken(token)
        }
    }
    
    // MARK: - Validation
    
    func validateContractAddress(_ address: String, chain: TokenChain) -> Bool {
        switch chain {
        case .ethereum, .bsc:
            // Check if valid Ethereum address (0x + 40 hex chars)
            let pattern = "^0x[a-fA-F0-9]{40}$"
            return address.range(of: pattern, options: .regularExpression) != nil
        case .solana:
            // Check if valid Solana address (base58, 32-44 chars)
            let base58Chars = CharacterSet(charactersIn: "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
            return address.count >= 32 && address.count <= 44 && address.unicodeScalars.allSatisfy { base58Chars.contains($0) }
        }
    }
}

// MARK: - Token Errors

enum TokenError: LocalizedError {
    case alreadyExists
    case invalidContract
    case invalidURL
    case networkError
    case invalidResponse
    case notImplemented(String)
    
    var errorDescription: String? {
        switch self {
        case .alreadyExists: return "This token has already been added"
        case .invalidContract: return "Invalid contract address or not an ERC-20/BEP-20 token"
        case .invalidURL: return "Invalid RPC URL"
        case .networkError: return "Network error while fetching token info"
        case .invalidResponse: return "Invalid response from blockchain"
        case .notImplemented(let msg): return msg
        }
    }
}

// MARK: - Add Token Sheet View

struct AddCustomTokenSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var tokenManager = CustomTokenManager.shared
    
    @State private var contractAddress = ""
    @State private var symbol = ""
    @State private var name = ""
    @State private var decimals = "18"
    @State private var selectedChain: TokenChain = .ethereum
    @State private var isLoading = false
    @State private var error: String?
    @State private var fetchedToken: CustomToken?
    @State private var manualEntry = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
                .background(HawalaTheme.Colors.border)
            
            // Content
            ScrollView {
                VStack(spacing: HawalaTheme.Spacing.xl) {
                    chainSelector
                    addressInput
                    
                    if let token = fetchedToken {
                        tokenPreview(token)
                    } else if manualEntry {
                        manualEntryFields
                    }
                    
                    if let error = error {
                        errorView(error)
                    }
                }
                .padding(HawalaTheme.Spacing.xl)
            }
            
            Divider()
                .background(HawalaTheme.Colors.border)
            
            // Footer
            footer
        }
        .frame(width: 450, height: 550)
        .background(HawalaTheme.Colors.background)
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add Custom Token")
                    .font(HawalaTheme.Typography.h3)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text("Import any ERC-20, BEP-20, or SPL token")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            
            Spacer()
            
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(HawalaTheme.Spacing.lg)
    }
    
    private var chainSelector: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
            Text("Network")
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
            
            HStack(spacing: HawalaTheme.Spacing.sm) {
                ForEach(TokenChain.allCases) { chain in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            selectedChain = chain
                            fetchedToken = nil
                            error = nil
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: chain.icon)
                                .font(.system(size: 12))
                            Text(chain == .ethereum ? "ETH" : chain == .bsc ? "BSC" : "SOL")
                                .font(HawalaTheme.Typography.caption)
                        }
                        .padding(.horizontal, HawalaTheme.Spacing.md)
                        .padding(.vertical, HawalaTheme.Spacing.sm)
                        .background(selectedChain == chain ? chain.color.opacity(0.2) : HawalaTheme.Colors.backgroundTertiary)
                        .foregroundColor(selectedChain == chain ? chain.color : HawalaTheme.Colors.textSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm))
                        .overlay(
                            RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm)
                                .strokeBorder(selectedChain == chain ? chain.color : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var addressInput: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
            Text("Contract Address")
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
            
            HStack(spacing: HawalaTheme.Spacing.sm) {
                TextField(selectedChain.addressPlaceholder, text: $contractAddress)
                    .textFieldStyle(.plain)
                    .font(HawalaTheme.Typography.mono)
                    .padding(HawalaTheme.Spacing.md)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm))
                    .onChange(of: contractAddress) { _ in
                        fetchedToken = nil
                        error = nil
                    }
                
                Button {
                    Task { await fetchTokenInfo() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 80, height: 36)
                    } else {
                        Text("Fetch")
                            .font(HawalaTheme.Typography.body)
                            .frame(width: 80, height: 36)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(HawalaTheme.Colors.accent)
                .disabled(contractAddress.isEmpty || isLoading || !tokenManager.validateContractAddress(contractAddress, chain: selectedChain))
            }
            
            if !tokenManager.validateContractAddress(contractAddress, chain: selectedChain) && !contractAddress.isEmpty {
                Text("Invalid \(selectedChain.displayName) address format")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.error)
            }
        }
    }
    
    private func tokenPreview(_ token: CustomToken) -> some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            HStack {
                Text("Token Found")
                    .font(HawalaTheme.Typography.captionBold)
                    .foregroundColor(HawalaTheme.Colors.success)
                
                Spacer()
                
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(HawalaTheme.Colors.success)
            }
            
            HStack(spacing: HawalaTheme.Spacing.md) {
                // Token icon placeholder
                ZStack {
                    Circle()
                        .fill(selectedChain.color.opacity(0.2))
                        .frame(width: 48, height: 48)
                    
                    Text(String(token.symbol.prefix(2)))
                        .font(HawalaTheme.Typography.h4)
                        .foregroundColor(selectedChain.color)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(token.name)
                        .font(HawalaTheme.Typography.body)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    
                    Text("\(token.symbol) • \(token.decimals) decimals")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
                
                Spacer()
            }
        }
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.success.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                .strokeBorder(HawalaTheme.Colors.success.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var manualEntryFields: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            Text("Enter Token Details Manually")
                .font(HawalaTheme.Typography.captionBold)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
            
            VStack(spacing: HawalaTheme.Spacing.sm) {
                HStack {
                    Text("Symbol")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                        .frame(width: 80, alignment: .leading)
                    
                    TextField("e.g. USDT", text: $symbol)
                        .textFieldStyle(.plain)
                        .padding(HawalaTheme.Spacing.sm)
                        .background(HawalaTheme.Colors.backgroundTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm))
                }
                
                HStack {
                    Text("Name")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                        .frame(width: 80, alignment: .leading)
                    
                    TextField("e.g. Tether USD", text: $name)
                        .textFieldStyle(.plain)
                        .padding(HawalaTheme.Spacing.sm)
                        .background(HawalaTheme.Colors.backgroundTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm))
                }
                
                HStack {
                    Text("Decimals")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                        .frame(width: 80, alignment: .leading)
                    
                    TextField("18", text: $decimals)
                        .textFieldStyle(.plain)
                        .padding(HawalaTheme.Spacing.sm)
                        .background(HawalaTheme.Colors.backgroundTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm))
                        .frame(width: 80)
                    
                    Spacer()
                }
            }
        }
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: HawalaTheme.Spacing.sm) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(HawalaTheme.Colors.warning)
                
                Text(message)
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                
                Spacer()
            }
            
            Button("Enter details manually") {
                manualEntry = true
                error = nil
            }
            .font(HawalaTheme.Typography.caption)
            .foregroundColor(HawalaTheme.Colors.accent)
        }
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.warning.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
    }
    
    private var footer: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.plain)
            .foregroundColor(HawalaTheme.Colors.textSecondary)
            
            Spacer()
            
            Button {
                addToken()
            } label: {
                Text("Add Token")
                    .font(HawalaTheme.Typography.body)
                    .padding(.horizontal, HawalaTheme.Spacing.xl)
            }
            .buttonStyle(.borderedProminent)
            .tint(HawalaTheme.Colors.accent)
            .disabled(!canAddToken)
        }
        .padding(HawalaTheme.Spacing.lg)
    }
    
    private var canAddToken: Bool {
        if let _ = fetchedToken {
            return true
        }
        if manualEntry && !symbol.isEmpty && !name.isEmpty && !contractAddress.isEmpty {
            return true
        }
        return false
    }
    
    private func fetchTokenInfo() async {
        isLoading = true
        error = nil
        
        do {
            let token = try await tokenManager.fetchTokenInfo(contractAddress: contractAddress, chain: selectedChain)
            fetchedToken = token
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func addToken() {
        let token: CustomToken
        
        if let fetched = fetchedToken {
            token = fetched
        } else {
            token = CustomToken(
                contractAddress: contractAddress,
                symbol: symbol.uppercased(),
                name: name,
                decimals: Int(decimals) ?? 18,
                chain: selectedChain
            )
        }
        
        do {
            try tokenManager.addToken(token)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Custom Tokens List View

struct CustomTokensListView: View {
    @ObservedObject private var tokenManager = CustomTokenManager.shared
    @State private var showAddSheet = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Custom Tokens")
                        .font(HawalaTheme.Typography.h4)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    
                    Text("\(tokenManager.tokens.count) tokens added")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
                
                Spacer()
                
                Button {
                    showAddSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add Token")
                    }
                    .font(HawalaTheme.Typography.caption)
                    .padding(.horizontal, HawalaTheme.Spacing.md)
                    .padding(.vertical, HawalaTheme.Spacing.sm)
                    .background(HawalaTheme.Colors.accent.opacity(0.15))
                    .foregroundColor(HawalaTheme.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm))
                }
                .buttonStyle(.plain)
            }
            
            if tokenManager.tokens.isEmpty {
                emptyState
            } else {
                tokensList
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddCustomTokenSheet()
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 40))
                .foregroundColor(HawalaTheme.Colors.textTertiary)
            
            Text("No custom tokens")
                .font(HawalaTheme.Typography.body)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
            
            Text("Add ERC-20, BEP-20, or SPL tokens by their contract address")
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(HawalaTheme.Spacing.xxl)
    }
    
    private var tokensList: some View {
        VStack(spacing: HawalaTheme.Spacing.sm) {
            ForEach(tokenManager.tokens) { token in
                CustomTokenRow(token: token)
            }
        }
    }
}

struct CustomTokenRow: View {
    let token: CustomToken
    @ObservedObject private var tokenManager = CustomTokenManager.shared
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            // Token icon
            ZStack {
                Circle()
                    .fill(token.chain.color.opacity(0.2))
                    .frame(width: 36, height: 36)
                
                Text(String(token.symbol.prefix(2)))
                    .font(HawalaTheme.Typography.captionBold)
                    .foregroundColor(token.chain.color)
            }
            
            // Token info
            VStack(alignment: .leading, spacing: 2) {
                Text(token.symbol)
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text(token.name)
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
            }
            
            Spacer()
            
            // Chain badge
            Text(token.chain == .ethereum ? "ERC-20" : token.chain == .bsc ? "BEP-20" : "SPL")
                .font(HawalaTheme.Typography.label)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(token.chain.color.opacity(0.15))
                .foregroundColor(token.chain.color)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            
            // Actions
            if isHovered {
                Button {
                    tokenManager.removeToken(token)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(HawalaTheme.Colors.error)
                        .frame(width: 28, height: 28)
                        .background(HawalaTheme.Colors.error.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(HawalaTheme.Spacing.md)
        .background(isHovered ? HawalaTheme.Colors.backgroundHover : HawalaTheme.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
        .onHover { isHovered = $0 }
    }
}

// MARK: - Custom Tokens Sheet (Settings Integration)

struct CustomTokensSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var tokenManager = CustomTokenManager.shared
    @State private var showAddSheet = false
    @State private var showAutoDetectSheet = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom Tokens")
                        .font(HawalaTheme.Typography.h3)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    
                    Text("\(tokenManager.tokens.count) tokens added")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
                
                Spacer()
                
                Button {
                    showAutoDetectSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkle.magnifyingglass")
                        Text("Auto-Detect")
                    }
                    .font(HawalaTheme.Typography.caption)
                    .padding(.horizontal, HawalaTheme.Spacing.md)
                    .padding(.vertical, HawalaTheme.Spacing.sm)
                    .background(HawalaTheme.Colors.success.opacity(0.15))
                    .foregroundColor(HawalaTheme.Colors.success)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm))
                }
                .buttonStyle(.plain)
                
                Button {
                    showAddSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add Token")
                    }
                    .font(HawalaTheme.Typography.caption)
                    .padding(.horizontal, HawalaTheme.Spacing.md)
                    .padding(.vertical, HawalaTheme.Spacing.sm)
                    .background(HawalaTheme.Colors.accent)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm))
                }
                .buttonStyle(.plain)
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(HawalaTheme.Colors.backgroundTertiary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(HawalaTheme.Spacing.lg)
            
            Divider()
                .background(HawalaTheme.Colors.border)
            
            // Content
            if tokenManager.tokens.isEmpty {
                VStack(spacing: HawalaTheme.Spacing.md) {
                    Spacer()
                    
                    Image(systemName: "circle.hexagongrid")
                        .font(.system(size: 48))
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                    
                    Text("No custom tokens")
                        .font(HawalaTheme.Typography.h4)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                    
                    Text("Add ERC-20, BEP-20, or SPL tokens\nby their contract address")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                        .multilineTextAlignment(.center)
                    
                    Button {
                        showAddSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Your First Token")
                        }
                        .font(HawalaTheme.Typography.body)
                        .padding(.horizontal, HawalaTheme.Spacing.xl)
                        .padding(.vertical, HawalaTheme.Spacing.md)
                        .background(HawalaTheme.Colors.accent)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, HawalaTheme.Spacing.md)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: HawalaTheme.Spacing.sm) {
                        ForEach(tokenManager.tokens) { token in
                            CustomTokenRow(token: token)
                        }
                    }
                    .padding(HawalaTheme.Spacing.lg)
                }
            }
        }
        .frame(width: 500, height: 450)
        .background(HawalaTheme.Colors.background)
        .sheet(isPresented: $showAddSheet) {
            AddCustomTokenSheet()
        }
        .sheet(isPresented: $showAutoDetectSheet) {
            AutoDetectTokensSheet()
        }
    }
}

// MARK: - Auto-Detect Tokens Sheet

struct AutoDetectTokensSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var tokenManager = CustomTokenManager.shared
    
    @State private var isScanning = false
    @State private var detectedTokens: [CustomToken] = []
    @State private var selectedTokens: Set<UUID> = []
    @State private var error: String?
    @State private var scanComplete = false
    
    // You would get these from the wallet manager
    @State private var ethAddress: String = ""
    @State private var solAddress: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto-Detect Tokens")
                        .font(HawalaTheme.Typography.h3)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    
                    Text("Scan your wallets for tokens")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(HawalaTheme.Colors.backgroundTertiary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(HawalaTheme.Spacing.lg)
            
            Divider()
                .background(HawalaTheme.Colors.border)
            
            // Content
            if isScanning {
                scanningView
            } else if scanComplete && detectedTokens.isEmpty {
                noTokensFoundView
            } else if !detectedTokens.isEmpty {
                detectedTokensView
            } else {
                startScanView
            }
            
            // Footer
            Divider()
                .background(HawalaTheme.Colors.border)
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
                
                Spacer()
                
                if !detectedTokens.isEmpty {
                    Button {
                        addSelectedTokens()
                    } label: {
                        Text("Add \(selectedTokens.count) Tokens")
                            .font(HawalaTheme.Typography.body)
                            .padding(.horizontal, HawalaTheme.Spacing.xl)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(HawalaTheme.Colors.accent)
                    .disabled(selectedTokens.isEmpty)
                }
            }
            .padding(HawalaTheme.Spacing.lg)
        }
        .frame(width: 500, height: 500)
        .background(HawalaTheme.Colors.background)
    }
    
    private var startScanView: some View {
        VStack(spacing: HawalaTheme.Spacing.xl) {
            Spacer()
            
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(HawalaTheme.Colors.accent)
            
            VStack(spacing: HawalaTheme.Spacing.sm) {
                Text("Scan for Tokens")
                    .font(HawalaTheme.Typography.h4)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text("Automatically detect ERC-20 and SPL tokens\nin your wallets with non-zero balances")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            // Address inputs
            VStack(spacing: HawalaTheme.Spacing.md) {
                HStack {
                    Image(systemName: "diamond")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    
                    TextField("Ethereum Address (0x...)", text: $ethAddress)
                        .textFieldStyle(.plain)
                        .font(HawalaTheme.Typography.mono)
                        .padding(HawalaTheme.Spacing.sm)
                        .background(HawalaTheme.Colors.backgroundTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm))
                }
                
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.purple)
                        .frame(width: 24)
                    
                    TextField("Solana Address", text: $solAddress)
                        .textFieldStyle(.plain)
                        .font(HawalaTheme.Typography.mono)
                        .padding(HawalaTheme.Spacing.sm)
                        .background(HawalaTheme.Colors.backgroundTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm))
                }
            }
            .padding(.horizontal, HawalaTheme.Spacing.xl)
            
            Button {
                Task { await startScan() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                    Text("Start Scan")
                }
                .font(HawalaTheme.Typography.body)
                .padding(.horizontal, HawalaTheme.Spacing.xl)
                .padding(.vertical, HawalaTheme.Spacing.md)
                .background(HawalaTheme.Colors.accent)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
            }
            .buttonStyle(.plain)
            .disabled(ethAddress.isEmpty && solAddress.isEmpty)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    private var scanningView: some View {
        VStack(spacing: HawalaTheme.Spacing.xl) {
            Spacer()
            
            ProgressView()
                .scaleEffect(1.5)
            
            VStack(spacing: HawalaTheme.Spacing.sm) {
                Text("Scanning Wallets...")
                    .font(HawalaTheme.Typography.h4)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text("Looking for tokens with non-zero balances")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    private var noTokensFoundView: some View {
        VStack(spacing: HawalaTheme.Spacing.xl) {
            Spacer()
            
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundColor(HawalaTheme.Colors.success)
            
            VStack(spacing: HawalaTheme.Spacing.sm) {
                Text("Scan Complete")
                    .font(HawalaTheme.Typography.h4)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text("No new tokens found in your wallets.\nAll detected tokens are already added.")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(HawalaTheme.Typography.body)
                    .padding(.horizontal, HawalaTheme.Spacing.xxl)
            }
            .buttonStyle(.borderedProminent)
            .tint(HawalaTheme.Colors.accent)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    private var detectedTokensView: some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            HStack {
                Text("Found \(detectedTokens.count) tokens")
                    .font(HawalaTheme.Typography.captionBold)
                    .foregroundColor(HawalaTheme.Colors.success)
                
                Spacer()
                
                Button {
                    if selectedTokens.count == detectedTokens.count {
                        selectedTokens.removeAll()
                    } else {
                        selectedTokens = Set(detectedTokens.map { $0.id })
                    }
                } label: {
                    Text(selectedTokens.count == detectedTokens.count ? "Deselect All" : "Select All")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, HawalaTheme.Spacing.lg)
            .padding(.top, HawalaTheme.Spacing.md)
            
            ScrollView {
                VStack(spacing: HawalaTheme.Spacing.sm) {
                    ForEach(detectedTokens) { token in
                        DetectedTokenRow(
                            token: token,
                            isSelected: selectedTokens.contains(token.id),
                            onToggle: {
                                if selectedTokens.contains(token.id) {
                                    selectedTokens.remove(token.id)
                                } else {
                                    selectedTokens.insert(token.id)
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, HawalaTheme.Spacing.lg)
            }
        }
    }
    
    private func startScan() async {
        isScanning = true
        error = nil
        detectedTokens = []
        
        do {
            var allTokens: [CustomToken] = []
            
            // Scan Ethereum if address provided
            if !ethAddress.isEmpty {
                let ethTokens = try await tokenManager.detectERC20Tokens(walletAddress: ethAddress)
                allTokens.append(contentsOf: ethTokens)
            }
            
            // Scan Solana if address provided
            if !solAddress.isEmpty {
                let solTokens = try await tokenManager.detectSPLTokens(walletAddress: solAddress)
                allTokens.append(contentsOf: solTokens)
            }
            
            detectedTokens = allTokens
            selectedTokens = Set(allTokens.map { $0.id }) // Select all by default
            scanComplete = true
        } catch {
            self.error = error.localizedDescription
        }
        
        isScanning = false
    }
    
    private func addSelectedTokens() {
        let tokensToAdd = detectedTokens.filter { selectedTokens.contains($0.id) }
        tokenManager.addDetectedTokens(tokensToAdd)
        dismiss()
    }
}

struct DetectedTokenRow: View {
    let token: CustomToken
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button {
            onToggle()
        } label: {
            HStack(spacing: HawalaTheme.Spacing.md) {
                // Checkbox
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? HawalaTheme.Colors.accent : HawalaTheme.Colors.textTertiary)
                
                // Token icon
                ZStack {
                    Circle()
                        .fill(token.chain.color.opacity(0.2))
                        .frame(width: 36, height: 36)
                    
                    Text(String(token.symbol.prefix(2)))
                        .font(HawalaTheme.Typography.captionBold)
                        .foregroundColor(token.chain.color)
                }
                
                // Token info
                VStack(alignment: .leading, spacing: 2) {
                    Text(token.symbol)
                        .font(HawalaTheme.Typography.body)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    
                    Text(token.name)
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
                
                Spacer()
                
                // Chain badge
                Text(token.chain == .ethereum ? "ERC-20" : token.chain == .bsc ? "BEP-20" : "SPL")
                    .font(HawalaTheme.Typography.label)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(token.chain.color.opacity(0.15))
                    .foregroundColor(token.chain.color)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .padding(HawalaTheme.Spacing.md)
            .background(isSelected ? HawalaTheme.Colors.accent.opacity(0.1) : HawalaTheme.Colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                    .strokeBorder(isSelected ? HawalaTheme.Colors.accent : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#if DEBUG
struct CustomTokenManager_Previews: PreviewProvider {
    static var previews: some View {
        AddCustomTokenSheet()
            .preferredColorScheme(.dark)
    }
}
#endif
