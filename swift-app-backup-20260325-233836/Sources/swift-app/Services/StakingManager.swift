import Foundation

// MARK: - Staking Models

/// Represents a validator for staking
struct Validator: Identifiable, Codable {
    let id: String
    let name: String
    let address: String
    let commission: Double // Percentage (e.g., 5.0 = 5%)
    let apy: Double // Annual percentage yield
    let totalStake: Double
    let isActive: Bool
    let chain: String
    
    var formattedAPY: String {
        String(format: "%.2f%%", apy)
    }
    
    var formattedCommission: String {
        String(format: "%.1f%%", commission)
    }
}

/// Represents a user's staking position
struct StakePosition: Identifiable, Codable {
    let id: String
    let chain: String
    let validatorAddress: String
    let validatorName: String
    let stakedAmount: Double
    let rewards: Double
    let status: StakeStatus
    let stakedAt: Date
    let symbol: String
    
    enum StakeStatus: String, Codable {
        case active
        case activating
        case deactivating
        case inactive
    }
    
    var formattedAmount: String {
        String(format: "%.4f %@", stakedAmount, symbol)
    }
    
    var formattedRewards: String {
        String(format: "%.6f %@", rewards, symbol)
    }
}

/// Staking statistics for a chain
struct StakingStats: Codable {
    let chain: String
    let totalStaked: Double
    let totalRewards: Double
    let averageAPY: Double
    let symbol: String
}

// MARK: - Staking Manager

@MainActor
class StakingManager: ObservableObject {
    static let shared = StakingManager()
    
    @Published var validators: [String: [Validator]] = [:] // Keyed by chain
    @Published var positions: [StakePosition] = []
    @Published var stats: [String: StakingStats] = [:]
    @Published var isLoading = false
    @Published var error: String?
    
    private init() {}
    
    // MARK: - Solana Staking
    
    /// Fetch Solana validators
    func fetchSolanaValidators() async {
        isLoading = true
        error = nil
        
        do {
            let url = URL(string: "https://api.mainnet-beta.solana.com")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body: [String: Any] = [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "getVoteAccounts",
                "params": []
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            
            struct VoteAccountsResponse: Codable {
                let result: VoteAccountsResult?
                
                struct VoteAccountsResult: Codable {
                    let current: [VoteAccount]
                    
                    struct VoteAccount: Codable {
                        let votePubkey: String
                        let nodePubkey: String
                        let activatedStake: Int64
                        let commission: Int
                    }
                }
            }
            
            let response = try JSONDecoder().decode(VoteAccountsResponse.self, from: data)
            
            if let result = response.result {
                // Get top 50 validators by stake
                let topValidators = result.current
                    .sorted { $0.activatedStake > $1.activatedStake }
                    .prefix(50)
                    .enumerated()
                    .map { index, account in
                        Validator(
                            id: account.votePubkey,
                            name: "Validator #\(index + 1)",
                            address: account.votePubkey,
                            commission: Double(account.commission),
                            apy: estimateSolanaAPY(commission: Double(account.commission)),
                            totalStake: Double(account.activatedStake) / 1_000_000_000,
                            isActive: true,
                            chain: "solana"
                        )
                    }
                
                validators["solana"] = Array(topValidators)
            }
        } catch {
            self.error = "Failed to fetch validators: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    /// Estimate Solana APY based on commission
    private func estimateSolanaAPY(commission: Double) -> Double {
        // Base Solana staking APY is around 6-7%, minus commission
        let baseAPY = 6.5
        return baseAPY * (1 - commission / 100)
    }
    
    /// Fetch user's Solana stake accounts
    func fetchSolanaStakeAccounts(for address: String) async {
        do {
            let url = URL(string: "https://api.mainnet-beta.solana.com")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body: [String: Any] = [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "getStakeActivation",
                "params": [address]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            
            // Parse stake activation response
            // This would need the actual stake account addresses
            print("Stake accounts response: \(String(data: data, encoding: .utf8) ?? "")")
            
        } catch {
            print("Failed to fetch stake accounts: \(error)")
        }
    }
    
    /// Create a stake delegation transaction for Solana
    func createSolanaStakeTransaction(
        fromAddress: String,
        validatorVoteAccount: String,
        amountSOL: Double,
        recentBlockhash: String
    ) async throws -> String {
        // This would create a stake account and delegate to the validator
        // Requires:
        // 1. Create stake account instruction
        // 2. Initialize stake instruction
        // 3. Delegate stake instruction
        
        // For now, return a placeholder - full implementation needs Solana SDK
        throw StakingError.notImplemented("Solana staking transaction creation requires native SDK")
    }
    
    // MARK: - Ethereum Staking (Lido)
    
    /// Fetch Lido staking stats
    func fetchLidoStats() async {
        do {
            // Lido API for staking stats
            let url = URL(string: "https://eth-api.lido.fi/v1/protocol/steth/apr/sma")!
            let (data, _) = try await URLSession.shared.data(from: url)
            
            struct LidoAPRResponse: Codable {
                let data: LidoData
                
                struct LidoData: Codable {
                    let smaApr: Double
                }
            }
            
            let response = try JSONDecoder().decode(LidoAPRResponse.self, from: data)
            
            // Create a "Lido" validator entry
            let lidoValidator = Validator(
                id: "lido-eth",
                name: "Lido (stETH)",
                address: "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84",
                commission: 10.0, // Lido takes 10%
                apy: response.data.smaApr,
                totalStake: 0, // Would need separate call
                isActive: true,
                chain: "ethereum"
            )
            
            validators["ethereum"] = [lidoValidator]
            
        } catch {
            print("Failed to fetch Lido stats: \(error)")
            // Fallback with estimated values
            let lidoValidator = Validator(
                id: "lido-eth",
                name: "Lido (stETH)",
                address: "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84",
                commission: 10.0,
                apy: 3.8, // Approximate current APY
                totalStake: 0,
                isActive: true,
                chain: "ethereum"
            )
            validators["ethereum"] = [lidoValidator]
        }
    }
    
    /// Create Lido staking transaction (ETH -> stETH)
    func createLidoStakeTransaction(amountETH: Double) -> (to: String, data: String, value: String) {
        // Lido submit() function - just send ETH to the contract
        let lidoContract = "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84"
        let submitSelector = "0xa1903eab" // submit(address _referral)
        let referral = "0x0000000000000000000000000000000000000000"
        let data = submitSelector + String(referral.dropFirst(2)).leftPadded(toLength: 64, withPad: "0")
        
        let weiValue = Int(amountETH * 1_000_000_000_000_000_000)
        let hexValue = String(weiValue, radix: 16)
        
        return (to: lidoContract, data: data, value: "0x" + hexValue)
    }
    
    // MARK: - BNB Staking
    
    /// Fetch BNB validators
    func fetchBNBValidators() async {
        // BSC staking is done through the staking contract
        // For simplicity, we'll show a few known validators
        let bnbValidators = [
            Validator(
                id: "bnb-binance",
                name: "Binance Node",
                address: "0x...",
                commission: 0,
                apy: 2.5,
                totalStake: 0,
                isActive: true,
                chain: "bnb"
            ),
            Validator(
                id: "bnb-ankr",
                name: "Ankr",
                address: "0x...",
                commission: 10,
                apy: 2.3,
                totalStake: 0,
                isActive: true,
                chain: "bnb"
            )
        ]
        
        validators["bnb"] = bnbValidators
    }
    
    // MARK: - Unified Methods
    
    /// Fetch all validators for supported chains
    func fetchAllValidators() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchSolanaValidators() }
            group.addTask { await self.fetchLidoStats() }
            group.addTask { await self.fetchBNBValidators() }
        }
    }
    
    /// Get total staked value across all positions
    func totalStakedValue(prices: [String: Double]) -> Double {
        positions.reduce(0) { total, position in
            let price = prices[position.chain] ?? 0
            return total + (position.stakedAmount * price)
        }
    }
    
    /// Get total rewards across all positions
    func totalRewards(prices: [String: Double]) -> Double {
        positions.reduce(0) { total, position in
            let price = prices[position.chain] ?? 0
            return total + (position.rewards * price)
        }
    }
}

// MARK: - Errors

enum StakingError: LocalizedError {
    case notImplemented(String)
    case insufficientBalance
    case invalidValidator
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .notImplemented(let msg): return msg
        case .insufficientBalance: return "Insufficient balance for staking"
        case .invalidValidator: return "Invalid validator address"
        case .networkError(let msg): return "Network error: \(msg)"
        }
    }
}

// MARK: - String Extension

extension String {
    func leftPadded(toLength: Int, withPad: String) -> String {
        let padCount = toLength - self.count
        guard padCount > 0 else { return self }
        return String(repeating: withPad, count: padCount) + self
    }
}
