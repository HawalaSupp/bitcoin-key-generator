import SwiftUI

/// Main staking dashboard view
struct StakingView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var stakingManager = StakingManager.shared
    @State private var selectedChain: String = "solana"
    @State private var showStakeSheet = false
    @State private var selectedValidator: Validator?
    @State private var stakeAmount = ""
    @State private var isStaking = false
    @State private var errorMessage: String?
    
    private let supportedChains = [
        ("solana", "SOL", "Solana"),
        ("ethereum", "ETH", "Ethereum (Lido)"),
        ("bnb", "BNB", "BNB Chain")
    ]
    
    var body: some View {
        HawalaSheetShell(title: "Staking", width: 620, height: 580) {
            // Chain selector
            chainSelector
            
            // Stats overview
            statsOverview
            
            // Active positions
            if !stakingManager.positions.filter({ $0.chain == selectedChain }).isEmpty {
                activePositions
            }
            
            // Validators list
            validatorsList
        }
        .task {
            await stakingManager.fetchAllValidators()
        }
        .sheet(isPresented: $showStakeSheet) {
            if let validator = selectedValidator {
                StakeInputSheet(
                    validator: validator,
                    chain: selectedChain,
                    onStake: { amount in
                        Task { await performStake(validator: validator, amount: amount) }
                    },
                    onCancel: { showStakeSheet = false }
                )
            }
        }
        .alert("Staking Error", isPresented: .constant(errorMessage != nil)) {
            Button("Dismiss") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
    
    private var chainSelector: some View {
        HStack(spacing: 6) {
            ForEach(supportedChains, id: \.0) { chain in
                Button {
                    withAnimation(.spring(response: 0.3)) { selectedChain = chain.0 }
                } label: {
                    VStack(spacing: 2) {
                        Text(chain.1)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(selectedChain == chain.0 ? .white : .white.opacity(0.4))
                        Text(chain.2)
                            .font(.system(size: 9))
                            .foregroundColor(selectedChain == chain.0 ? .white.opacity(0.5) : .white.opacity(0.2))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        selectedChain == chain.0
                            ? Color.white.opacity(0.2)
                            : Color.white.opacity(0.03)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                selectedChain == chain.0
                                    ? Color.white.opacity(0.4)
                                    : .clear,
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var statsOverview: some View {
        HStack(spacing: 8) {
            StatCard(title: "Total Staked", value: formattedTotalStaked, subtitle: "Across all validators", icon: "lock.fill", color: Color.white.opacity(0.5))
            StatCard(title: "Total Rewards", value: formattedTotalRewards, subtitle: "Earned to date", icon: "gift.fill", color: Color(red: 0.20, green: 0.84, blue: 0.29))
            StatCard(title: "Avg. APY", value: formattedAvgAPY, subtitle: "Annual yield", icon: "percent", color: Color(red: 1, green: 0.84, blue: 0.04))
        }
    }
    
    private var formattedTotalStaked: String {
        let positions = stakingManager.positions.filter { $0.chain == selectedChain }
        let total = positions.reduce(0) { $0 + $1.stakedAmount }
        let symbol = supportedChains.first { $0.0 == selectedChain }?.1 ?? ""
        return String(format: "%.4f %@", total, symbol)
    }
    
    private var formattedTotalRewards: String {
        let positions = stakingManager.positions.filter { $0.chain == selectedChain }
        let total = positions.reduce(0) { $0 + $1.rewards }
        let symbol = supportedChains.first { $0.0 == selectedChain }?.1 ?? ""
        return String(format: "%.6f %@", total, symbol)
    }
    
    private var formattedAvgAPY: String {
        let validators = stakingManager.validators[selectedChain] ?? []
        guard !validators.isEmpty else { return "—" }
        let avgAPY = validators.reduce(0) { $0 + $1.apy } / Double(validators.count)
        return String(format: "%.2f%%", avgAPY)
    }
    
    private var activePositions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HawalaOverlaySectionHeader(icon: "lock.fill", title: "Your Staking Positions")
            ForEach(stakingManager.positions.filter { $0.chain == selectedChain }) { position in
                PositionCard(position: position)
            }
        }
        .hawalaSectionCard()
    }
    
    private var validatorsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HawalaOverlaySectionHeader(icon: "server.rack", title: "Available Validators")
                Spacer()
                if stakingManager.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            
            let validators = stakingManager.validators[selectedChain] ?? []
            
            if validators.isEmpty && !stakingManager.isLoading {
                Text("No validators available")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(validators) { validator in
                    ValidatorRow(validator: validator) {
                        selectedValidator = validator
                        showStakeSheet = true
                    }
                }
            }
        }
        .hawalaSectionCard()
    }
    
    private func performStake(validator: Validator, amount: Double) async {
        isStaking = true
        
        do {
            switch selectedChain {
            case "solana":
                throw StakingError.notImplemented("Solana staking requires wallet signature. Coming soon!")
            case "ethereum":
                // For Lido, we'd create the transaction and prompt for signing
                throw StakingError.notImplemented("Ethereum staking via Lido requires wallet signature. Coming soon!")
            case "bnb":
                throw StakingError.notImplemented("BNB staking requires wallet signature. Coming soon!")
            default:
                throw StakingError.notImplemented("Unsupported chain")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isStaking = false
        showStakeSheet = false
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.35))
            }
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(.system(size: 8))
                .foregroundColor(.white.opacity(0.2))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.white.opacity(0.04), lineWidth: 1)
                )
        )
    }
}

struct PositionCard: View {
    let position: StakePosition
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(position.validatorName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                        Text(position.formattedAmount)
                            .font(.system(size: 10, design: .monospaced))
                    }
                    .foregroundColor(.white.opacity(0.5))
                    HStack(spacing: 4) {
                        Image(systemName: "gift")
                            .font(.system(size: 9))
                        Text(position.formattedRewards)
                            .font(.system(size: 10, design: .monospaced))
                    }
                    .foregroundColor(Color(red: 0.20, green: 0.84, blue: 0.29))
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                StatusBadge(status: position.status)
                Text("Since \(position.stakedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.2))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.white.opacity(0.04), lineWidth: 1)
                )
        )
    }
}

struct StatusBadge: View {
    let status: StakePosition.StakeStatus
    
    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .clipShape(Capsule())
    }
    
    private var backgroundColor: Color {
        switch status {
        case .active: return Color(red: 0.20, green: 0.84, blue: 0.29).opacity(0.15)
        case .activating: return Color(red: 1, green: 0.84, blue: 0.04).opacity(0.15)
        case .deactivating: return Color(red: 1, green: 0.27, blue: 0.23).opacity(0.15)
        case .inactive: return Color.white.opacity(0.06)
        }
    }
    
    private var foregroundColor: Color {
        switch status {
        case .active: return Color(red: 0.20, green: 0.84, blue: 0.29)
        case .activating: return Color(red: 1, green: 0.84, blue: 0.04)
        case .deactivating: return Color(red: 1, green: 0.27, blue: 0.23)
        case .inactive: return .white.opacity(0.3)
        }
    }
}

struct ValidatorRow: View {
    let validator: Validator
    let onStake: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(validator.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                    if validator.isActive {
                        Circle()
                            .fill(Color(red: 0.20, green: 0.84, blue: 0.29))
                            .frame(width: 6, height: 6)
                    }
                }
                Text(validator.address.prefix(20) + "...")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(validator.formattedAPY)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(red: 0.20, green: 0.84, blue: 0.29))
                Text("Commission: \(validator.formattedCommission)")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.3))
            }
            
            Button("Stake") { onStake() }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.12))
                .clipShape(Capsule())
                .buttonStyle(.plain)
                .help("Delegate tokens to this validator")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.white.opacity(0.04), lineWidth: 1)
                )
        )
    }
}

struct StakeInputSheet: View {
    let validator: Validator
    let chain: String
    let onStake: (Double) -> Void
    let onCancel: () -> Void
    
    @State private var amount = ""
    @State private var availableBalance = 0.0
    
    private var symbol: String {
        switch chain {
        case "solana": return "SOL"
        case "ethereum": return "ETH"
        case "bnb": return "BNB"
        default: return ""
        }
    }
    
    var body: some View {
        HawalaSheetShell(title: "Stake \(symbol)", width: 400, height: 460) {
            // Validator info
            VStack(spacing: 6) {
                Text(validator.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "percent")
                            .font(.system(size: 10))
                        Text(validator.formattedAPY)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(Color(red: 0.20, green: 0.84, blue: 0.29))
                    HStack(spacing: 4) {
                        Image(systemName: "tag")
                            .font(.system(size: 10))
                        Text(validator.formattedCommission)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.4))
                }
            }
            .hawalaSectionCard()

            // Amount input
            VStack(spacing: 10) {
                HawalaOverlaySectionHeader(icon: "number", title: "Amount to Stake")
                HStack {
                    TextField("0.0", text: $amount)
                        .font(.system(size: 28, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .help("Amount to lock in staking — funds are illiquid during the unbonding period")
                    Text(symbol)
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.35))
                }
                if availableBalance > 0 {
                    Button("Max: \(String(format: "%.4f", availableBalance)) \(symbol)") {
                        amount = String(format: "%.4f", availableBalance * 0.99)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.5))
                    .buttonStyle(.plain)
                    .help("Stake maximum balance — reserves a small amount for transaction fees")
                }
            }
            .hawalaSectionCard()

            // Estimated rewards
            if let amountDouble = Double(amount), amountDouble > 0 {
                VStack(spacing: 4) {
                    Text("Estimated Annual Rewards")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                    let annualReward = amountDouble * (validator.apy / 100)
                    Text("+\(String(format: "%.4f", annualReward)) \(symbol)")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(red: 0.20, green: 0.84, blue: 0.29))
                }
                .hawalaSectionCard()
            }

            HawalaActionButton(icon: "lock.fill", label: "Stake \(symbol)", style: .primary) {
                if let amountDouble = Double(amount), amountDouble > 0 {
                    onStake(amountDouble)
                }
            }
        }
    }
}

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    StakingView()
}
#endif
#endif
#endif
