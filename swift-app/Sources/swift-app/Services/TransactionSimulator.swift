import Foundation
import SwiftUI
import Combine

// MARK: - Transaction Simulation Service
/// Simulates transactions before sending to detect potential issues
/// Provides clear, human-readable explanations of what will happen

@MainActor
final class TransactionSimulator: ObservableObject {
    
    // MARK: - Published State
    @Published private(set) var isSimulating = false
    @Published private(set) var lastSimulation: SimulationResult?
    @Published private(set) var warnings: [SimulationWarning] = []
    
    // MARK: - Singleton
    static let shared = TransactionSimulator()
    
    private init() {}
    
    // MARK: - Simulation Types
    
    struct TransactionRequest {
        let chain: String
        let fromAddress: String
        let toAddress: String
        let amount: Decimal
        let tokenSymbol: String
        let isNative: Bool
        let contractAddress: String?
        let data: Data?
        let gasLimit: UInt64?
        let maxFeePerGas: UInt64?
        let maxPriorityFee: UInt64?
    }
    
    struct SimulationResult: Identifiable {
        let id = UUID()
        let success: Bool
        let estimatedGas: UInt64
        let estimatedFee: Decimal
        let estimatedFeeUSD: Decimal
        let balanceAfter: Decimal
        let warnings: [SimulationWarning]
        let changes: [BalanceChange]
        let riskLevel: RiskLevel
        let timestamp: Date
        let explanation: String
    }
    
    struct BalanceChange: Identifiable {
        let id = UUID()
        let token: String
        let symbol: String
        let amount: Decimal
        let isIncoming: Bool
        let contractAddress: String?
    }
    
    enum RiskLevel: String {
        case low = "Low Risk"
        case medium = "Medium Risk"
        case high = "High Risk"
        case critical = "Critical Risk"
        
        var color: Color {
            switch self {
            case .low: return .green
            case .medium: return .yellow
            case .high: return .orange
            case .critical: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .low: return "checkmark.shield.fill"
            case .medium: return "exclamationmark.shield.fill"
            case .high: return "exclamationmark.triangle.fill"
            case .critical: return "xmark.shield.fill"
            }
        }
    }
    
    struct SimulationWarning: Identifiable {
        let id = UUID()
        let type: WarningType
        let title: String
        let message: String
        let severity: Severity
        let actionable: Bool
        let action: String?
        
        enum WarningType {
            case newAddress
            case largeAmount
            case contractInteraction
            case highGas
            case lowBalance
            case tokenApproval
            case suspiciousContract
            case networkMismatch
            case recentlyCreatedAddress
            case exchangeAddress
            case knownScam
            case unusualActivity
        }
        
        enum Severity {
            case info
            case warning
            case danger
            
            var color: Color {
                switch self {
                case .info: return .blue
                case .warning: return .orange
                case .danger: return .red
                }
            }
            
            var icon: String {
                switch self {
                case .info: return "info.circle.fill"
                case .warning: return "exclamationmark.triangle.fill"
                case .danger: return "xmark.octagon.fill"
                }
            }
        }
    }
    
    // MARK: - Simulation
    
    /// Simulate a transaction and return detailed results
    func simulate(_ request: TransactionRequest) async throws -> SimulationResult {
        isSimulating = true
        defer { isSimulating = false }
        
        var warnings: [SimulationWarning] = []
        var riskLevel: RiskLevel = .low
        
        // 1. Check if recipient is a new address
        if await isFirstTimeAddress(request.toAddress, chain: request.chain) {
            warnings.append(SimulationWarning(
                type: .newAddress,
                title: "First-time Recipient",
                message: "You've never sent to this address before. Double-check it's correct.",
                severity: .warning,
                actionable: true,
                action: "Verify Address"
            ))
            riskLevel = max(riskLevel, .medium)
        }
        
        // 2. Check for large amounts
        let largeThreshold: Decimal = 1000 // USD equivalent
        let amountUSD = await estimateUSDValue(request.amount, symbol: request.tokenSymbol)
        if amountUSD > largeThreshold {
            warnings.append(SimulationWarning(
                type: .largeAmount,
                title: "Large Transaction",
                message: "This transaction is worth approximately $\(amountUSD.formatted()). Consider sending a small test amount first.",
                severity: .warning,
                actionable: true,
                action: "Send Test Amount"
            ))
            riskLevel = max(riskLevel, .medium)
        }
        
        // 3. Check for contract interaction
        if request.data != nil || !request.isNative {
            warnings.append(SimulationWarning(
                type: .contractInteraction,
                title: "Smart Contract Interaction",
                message: "This transaction interacts with a smart contract. Review the details carefully.",
                severity: .info,
                actionable: false,
                action: nil
            ))
        }
        
        // 4. Check if it's a token approval (ERC-20 approve)
        if let data = request.data, isTokenApproval(data) {
            let approvalAmount = parseApprovalAmount(data)
            if approvalAmount == Decimal.greatestFiniteMagnitude {
                warnings.append(SimulationWarning(
                    type: .tokenApproval,
                    title: "Unlimited Token Approval",
                    message: "This grants unlimited spending permission. Consider setting a specific limit.",
                    severity: .danger,
                    actionable: true,
                    action: "Set Custom Limit"
                ))
                riskLevel = max(riskLevel, .high)
            } else {
                warnings.append(SimulationWarning(
                    type: .tokenApproval,
                    title: "Token Approval",
                    message: "This allows the contract to spend up to \(approvalAmount) tokens.",
                    severity: .warning,
                    actionable: false,
                    action: nil
                ))
            }
        }
        
        // 5. Check against known scam addresses
        if await isKnownScamAddress(request.toAddress) {
            warnings.append(SimulationWarning(
                type: .knownScam,
                title: "⚠️ Known Scam Address",
                message: "This address has been reported as a scam. Do NOT proceed.",
                severity: .danger,
                actionable: false,
                action: nil
            ))
            riskLevel = .critical
        }
        
        // 6. Check for network mismatch (e.g., sending mainnet funds to testnet-style address)
        if let mismatch = detectNetworkMismatch(request) {
            warnings.append(SimulationWarning(
                type: .networkMismatch,
                title: "Possible Network Mismatch",
                message: mismatch,
                severity: .danger,
                actionable: false,
                action: nil
            ))
            riskLevel = max(riskLevel, .high)
        }
        
        // 7. Estimate gas
        let estimatedGas = estimateGas(for: request)
        let gasPrice = await getCurrentGasPrice(chain: request.chain)
        let estimatedFee = Decimal(estimatedGas) * gasPrice
        let estimatedFeeUSD = await estimateUSDValue(estimatedFee, symbol: nativeToken(for: request.chain))
        
        // 8. Check if gas is unusually high
        let normalGasUSD: Decimal = 5
        if estimatedFeeUSD > normalGasUSD * 3 {
            let multiplier = NSDecimalNumber(decimal: estimatedFeeUSD / normalGasUSD).intValue
            warnings.append(SimulationWarning(
                type: .highGas,
                title: "High Network Fee",
                message: "Current fees are \(multiplier)x higher than normal. Consider waiting.",
                severity: .warning,
                actionable: true,
                action: "Set Fee Alert"
            ))
        }
        
        // 9. Check balance sufficiency
        let currentBalance = await getBalance(address: request.fromAddress, chain: request.chain, token: request.tokenSymbol)
        let totalNeeded = request.amount + estimatedFee
        let balanceAfter = currentBalance - totalNeeded
        
        if balanceAfter < 0 {
            warnings.append(SimulationWarning(
                type: .lowBalance,
                title: "Insufficient Balance",
                message: "You need \(totalNeeded) but only have \(currentBalance). Transaction will fail.",
                severity: .danger,
                actionable: false,
                action: nil
            ))
            riskLevel = .critical
        }
        
        // 10. ROADMAP-08: Cross-transaction pattern heuristics
        // Detect repeated sends to the same address in a short window
        let recentPattern = checkRepeatedSendPattern(to: request.toAddress, chain: request.chain, amount: request.amount)
        if let patternWarning = recentPattern {
            warnings.append(patternWarning)
            riskLevel = max(riskLevel, .medium)
        }
        
        // Build result
        let changes = [
            BalanceChange(
                token: request.tokenSymbol,
                symbol: request.tokenSymbol,
                amount: request.amount,
                isIncoming: false,
                contractAddress: request.contractAddress
            )
        ]
        
        let explanation = buildExplanation(request: request, warnings: warnings, riskLevel: riskLevel)
        
        let result = SimulationResult(
            success: riskLevel != .critical,
            estimatedGas: estimatedGas,
            estimatedFee: estimatedFee,
            estimatedFeeUSD: estimatedFeeUSD,
            balanceAfter: max(0, balanceAfter),
            warnings: warnings,
            changes: changes,
            riskLevel: riskLevel,
            timestamp: Date(),
            explanation: explanation
        )
        
        self.lastSimulation = result
        self.warnings = warnings
        
        return result
    }
    
    // MARK: - Helper Methods
    
    /// ROADMAP-08: Cross-transaction pattern heuristics
    /// Detects multiple sends to the same address within a short window
    private func checkRepeatedSendPattern(to address: String, chain: String, amount: Decimal) -> SimulationWarning? {
        let key = "hawala.txpattern.history"
        let windowSeconds: TimeInterval = 600 // 10-minute window
        let maxRepeatCount = 2 // warn after 2 sends to same address
        
        var entries = loadTxPatternHistory(key: key)
        let now = Date().timeIntervalSince1970
        let cutoff = now - windowSeconds
        
        // Prune old entries
        entries = entries.filter { $0.timestamp > cutoff }
        
        // Count recent sends to this address
        let recentCount = entries.filter {
            $0.address.lowercased() == address.lowercased() && $0.chain == chain
        }.count
        
        // Record this send attempt
        entries.append(TxPatternEntry(address: address.lowercased(), chain: chain, amount: "\(amount)", timestamp: now))
        if entries.count > 50 { entries = Array(entries.suffix(50)) }
        saveTxPatternHistory(entries, key: key)
        
        if recentCount >= maxRepeatCount {
            return SimulationWarning(
                type: .unusualActivity,
                title: "Repeated Sends Detected",
                message: "You've sent to this address \(recentCount) times in the last 10 minutes. This may indicate a duplicate transaction.",
                severity: .warning,
                actionable: true,
                action: "Review Transactions"
            )
        }
        
        return nil
    }
    
    private struct TxPatternEntry: Codable {
        let address: String
        let chain: String
        let amount: String
        let timestamp: TimeInterval
    }
    
    private func loadTxPatternHistory(key: String) -> [TxPatternEntry] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([TxPatternEntry].self, from: data)) ?? []
    }
    
    private func saveTxPatternHistory(_ entries: [TxPatternEntry], key: String) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    private func isFirstTimeAddress(_ address: String, chain: String) async -> Bool {
        // Check local history for previous transactions to this address
        let key = "hawala.sentAddresses.\(chain)"
        let sentAddresses = UserDefaults.standard.stringArray(forKey: key) ?? []
        return !sentAddresses.contains(address.lowercased())
    }
    
    private func estimateUSDValue(_ amount: Decimal, symbol: String) async -> Decimal {
        // In production, fetch real prices from API
        let mockPrices: [String: Decimal] = [
            "ETH": 2500,
            "BTC": 45000,
            "SOL": 100,
            "USDC": 1,
            "USDT": 1
        ]
        return amount * (mockPrices[symbol.uppercased()] ?? 1)
    }
    
    private func isTokenApproval(_ data: Data) -> Bool {
        // Check for ERC-20 approve function selector: 0x095ea7b3
        guard data.count >= 4 else { return false }
        let selector = data.prefix(4)
        return selector == Data([0x09, 0x5e, 0xa7, 0xb3])
    }
    
    private func parseApprovalAmount(_ data: Data) -> Decimal {
        guard data.count >= 68 else { return 0 }
        let amountData = data.suffix(32)
        // Check for max uint256 (unlimited approval)
        if amountData == Data(repeating: 0xff, count: 32) {
            return Decimal.greatestFiniteMagnitude
        }
        // Parse actual amount (simplified)
        return Decimal(1000) // Placeholder
    }
    
    private func isKnownScamAddress(_ address: String) async -> Bool {
        // In production, check against scam database
        let knownScams = [
            "0x000000000000000000000000000000000000dead",
            "0xscammer123" // Placeholder
        ]
        return knownScams.contains(address.lowercased())
    }
    
    private func detectNetworkMismatch(_ request: TransactionRequest) -> String? {
        // Check for common mismatches
        if request.chain.lowercased().contains("mainnet") {
            if request.toAddress.hasPrefix("tb1") || request.toAddress.hasPrefix("2") {
                return "This appears to be a testnet address, but you're on mainnet."
            }
        }
        return nil
    }
    
    private func estimateGas(for request: TransactionRequest) -> UInt64 {
        if let gas = request.gasLimit {
            return gas
        }
        // Default estimates
        if request.data != nil {
            return 100_000 // Contract interaction
        }
        if !request.isNative {
            return 65_000 // Token transfer
        }
        return 21_000 // Simple ETH transfer
    }
    
    private func getCurrentGasPrice(chain: String) async -> Decimal {
        // In production, fetch real gas prices
        return Decimal(0.00000002) // 20 gwei in ETH
    }
    
    private func nativeToken(for chain: String) -> String {
        let tokens: [String: String] = [
            "ethereum": "ETH",
            "bitcoin": "BTC",
            "solana": "SOL",
            "polygon": "MATIC"
        ]
        return tokens[chain.lowercased()] ?? "ETH"
    }
    
    private func getBalance(address: String, chain: String, token: String) async -> Decimal {
        // In production, fetch real balance
        return Decimal(1.5)
    }
    
    private func buildExplanation(request: TransactionRequest, warnings: [SimulationWarning], riskLevel: RiskLevel) -> String {
        var parts: [String] = []
        
        parts.append("You're sending \(request.amount) \(request.tokenSymbol) to \(shortenAddress(request.toAddress)).")
        
        if !warnings.isEmpty {
            let warningCount = warnings.filter { $0.severity == .warning || $0.severity == .danger }.count
            if warningCount > 0 {
                parts.append("\(warningCount) potential issue(s) detected.")
            }
        }
        
        switch riskLevel {
        case .low:
            parts.append("This transaction looks safe.")
        case .medium:
            parts.append("Review the warnings before proceeding.")
        case .high:
            parts.append("Caution: This transaction has elevated risk.")
        case .critical:
            parts.append("⚠️ Do not proceed with this transaction.")
        }
        
        return parts.joined(separator: " ")
    }
    
    private func shortenAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
    
    /// Record a successful send for future first-time detection
    func recordSentAddress(_ address: String, chain: String) {
        let key = "hawala.sentAddresses.\(chain)"
        var sentAddresses = UserDefaults.standard.stringArray(forKey: key) ?? []
        let normalized = address.lowercased()
        if !sentAddresses.contains(normalized) {
            sentAddresses.append(normalized)
            UserDefaults.standard.set(sentAddresses, forKey: key)
        }
    }
}

// MARK: - Transaction Simulation View

struct TransactionSimulationView: View {
    let simulation: TransactionSimulator.SimulationResult
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    @State private var hasReviewedWarnings = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            ScrollView {
                VStack(spacing: 20) {
                    // Summary
                    summaryCard
                    
                    // Warnings
                    if !simulation.warnings.isEmpty {
                        warningsSection
                    }
                    
                    // Balance Changes
                    balanceChangesSection
                    
                    // Fee Details
                    feeDetailsCard
                }
                .padding(24)
            }
            
            // Action Buttons
            actionButtons
        }
        .background(Color.black)
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Transaction Preview")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(simulation.explanation)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            // Risk Badge
            HStack(spacing: 6) {
                Image(systemName: simulation.riskLevel.icon)
                Text(simulation.riskLevel.rawValue)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(simulation.riskLevel.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(simulation.riskLevel.color.opacity(0.15))
            )
        }
        .padding(24)
        .background(Color.white.opacity(0.03))
    }
    
    private var summaryCard: some View {
        VStack(spacing: 16) {
            ForEach(simulation.changes) { change in
                HStack {
                    Image(systemName: change.isIncoming ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(change.isIncoming ? .green : .orange)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(change.isIncoming ? "Receive" : "Send")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                        
                        Text("\(change.amount.formatted()) \(change.symbol)")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    private var warningsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Warnings")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            
            ForEach(simulation.warnings) { warning in
                WarningRow(warning: warning)
            }
        }
    }
    
    private var balanceChangesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("After Transaction")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            
            HStack {
                Text("Remaining Balance")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
                
                Spacer()
                
                Text("\(simulation.balanceAfter.formatted())")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.05))
            )
        }
    }
    
    private var feeDetailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Network Fee")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            
            HStack {
                Text("Estimated Fee")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(simulation.estimatedFee.formatted())")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text("≈ $\(simulation.estimatedFeeUSD.formatted())")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.05))
            )
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                onCancel()
            } label: {
                Text("Cancel")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
            
            Button {
                onConfirm()
            } label: {
                Text(simulation.riskLevel == .critical ? "Do Not Send" : "Confirm & Send")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(simulation.riskLevel == .critical ? .white : .black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(simulation.riskLevel == .critical ? Color.red : Color.white)
                    )
            }
            .buttonStyle(.plain)
            .disabled(simulation.riskLevel == .critical)
        }
        .padding(24)
        .background(Color.black)
    }
}

private struct WarningRow: View {
    let warning: TransactionSimulator.SimulationWarning
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: warning.severity.icon)
                .font(.system(size: 16))
                .foregroundColor(warning.severity.color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(warning.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                Text(warning.message)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            if warning.actionable, let action = warning.action {
                Button {
                    // Handle action
                } label: {
                    Text(action)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(warning.severity.color)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(warning.severity.color.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(warning.severity.color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Risk Level Comparable

extension TransactionSimulator.RiskLevel: Comparable {
    static func < (lhs: TransactionSimulator.RiskLevel, rhs: TransactionSimulator.RiskLevel) -> Bool {
        let order: [TransactionSimulator.RiskLevel] = [.low, .medium, .high, .critical]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}
