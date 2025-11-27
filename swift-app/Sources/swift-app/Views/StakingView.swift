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
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Chain selector
            chainSelector
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: 20) {
                    // Stats overview
                    statsOverview
                    
                    // Active positions
                    if !stakingManager.positions.filter({ $0.chain == selectedChain }).isEmpty {
                        activePositions
                    }
                    
                    // Validators list
                    validatorsList
                }
                .padding()
            }
        }
        .frame(minWidth: 600, idealWidth: 700, minHeight: 500, idealHeight: 600)
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
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
    
    private var headerView: some View {
        HStack {
            Button("Done") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            
            Spacer()
            
            Text("Staking")
                .font(.headline)
            
            Spacer()
            
            Button {
                Task { await stakingManager.fetchAllValidators() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(stakingManager.isLoading)
        }
        .padding()
    }
    
    private var chainSelector: some View {
        HStack(spacing: 0) {
            ForEach(supportedChains, id: \.0) { chain in
                Button {
                    withAnimation { selectedChain = chain.0 }
                } label: {
                    VStack(spacing: 4) {
                        Text(chain.1)
                            .font(.headline)
                        Text(chain.2)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(selectedChain == chain.0 ? Color.accentColor.opacity(0.15) : Color.clear)
                }
                .buttonStyle(.plain)
                
                if chain.0 != supportedChains.last?.0 {
                    Divider()
                }
            }
        }
        .background(Color.primary.opacity(0.03))
    }
    
    private var statsOverview: some View {
        HStack(spacing: 16) {
            StatCard(
                title: "Total Staked",
                value: formattedTotalStaked,
                subtitle: "Across all validators",
                icon: "lock.fill",
                color: .blue
            )
            
            StatCard(
                title: "Total Rewards",
                value: formattedTotalRewards,
                subtitle: "Earned to date",
                icon: "gift.fill",
                color: .green
            )
            
            StatCard(
                title: "Avg. APY",
                value: formattedAvgAPY,
                subtitle: "Annual yield",
                icon: "percent",
                color: .orange
            )
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Staking Positions")
                .font(.headline)
            
            ForEach(stakingManager.positions.filter { $0.chain == selectedChain }) { position in
                PositionCard(position: position)
            }
        }
    }
    
    private var validatorsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Available Validators")
                    .font(.headline)
                
                Spacer()
                
                if stakingManager.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            
            let validators = stakingManager.validators[selectedChain] ?? []
            
            if validators.isEmpty && !stakingManager.isLoading {
                Text("No validators available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(validators) { validator in
                        ValidatorRow(validator: validator) {
                            selectedValidator = validator
                            showStakeSheet = true
                        }
                    }
                }
            }
        }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
    }
}

struct PositionCard: View {
    let position: StakePosition
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(position.validatorName)
                    .font(.headline)
                
                HStack(spacing: 16) {
                    Label(position.formattedAmount, systemImage: "lock.fill")
                    Label(position.formattedRewards, systemImage: "gift")
                        .foregroundStyle(.green)
                }
                .font(.caption)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                StatusBadge(status: position.status)
                
                Text("Since \(position.stakedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color.primary.opacity(0.03))
        .cornerRadius(10)
    }
}

struct StatusBadge: View {
    let status: StakePosition.StakeStatus
    
    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .cornerRadius(4)
    }
    
    private var backgroundColor: Color {
        switch status {
        case .active: return .green.opacity(0.15)
        case .activating: return .orange.opacity(0.15)
        case .deactivating: return .red.opacity(0.15)
        case .inactive: return .gray.opacity(0.15)
        }
    }
    
    private var foregroundColor: Color {
        switch status {
        case .active: return .green
        case .activating: return .orange
        case .deactivating: return .red
        case .inactive: return .gray
        }
    }
}

struct ValidatorRow: View {
    let validator: Validator
    let onStake: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(validator.name)
                        .font(.headline)
                    
                    if validator.isActive {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                    }
                }
                
                Text(validator.address.prefix(20) + "...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontDesign(.monospaced)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(validator.formattedAPY)
                    .font(.headline)
                    .foregroundStyle(.green)
                
                Text("Commission: \(validator.formattedCommission)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Button("Stake") {
                onStake()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .background(Color.primary.opacity(0.03))
        .cornerRadius(10)
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
        VStack(spacing: 20) {
            // Header
            HStack {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                
                Spacer()
                
                Text("Stake \(symbol)")
                    .font(.headline)
                
                Spacer()
                
                // Invisible spacer for symmetry
                Text("Cancel")
                    .opacity(0)
            }
            .padding()
            
            Divider()
            
            // Validator info
            VStack(spacing: 8) {
                Text(validator.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                HStack(spacing: 20) {
                    Label(validator.formattedAPY, systemImage: "percent")
                        .foregroundStyle(.green)
                    Label(validator.formattedCommission, systemImage: "tag")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
            .padding()
            
            // Amount input
            VStack(spacing: 12) {
                Text("Amount to Stake")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack {
                    TextField("0.0", text: $amount)
                        .font(.system(size: 36, weight: .medium, design: .rounded))
                        .multilineTextAlignment(.center)
                    
                    Text(symbol)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                
                if availableBalance > 0 {
                    Button("Max: \(String(format: "%.4f", availableBalance)) \(symbol)") {
                        amount = String(format: "%.4f", availableBalance * 0.99) // Leave some for fees
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
            }
            .padding()
            
            // Estimated rewards
            if let amountDouble = Double(amount), amountDouble > 0 {
                VStack(spacing: 4) {
                    Text("Estimated Annual Rewards")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    let annualReward = amountDouble * (validator.apy / 100)
                    Text("+\(String(format: "%.4f", annualReward)) \(symbol)")
                        .font(.headline)
                        .foregroundStyle(.green)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(10)
            }
            
            Spacer()
            
            // Stake button
            Button {
                if let amountDouble = Double(amount), amountDouble > 0 {
                    onStake(amountDouble)
                }
            } label: {
                Text("Stake \(symbol)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(Double(amount) ?? 0 <= 0)
            .padding()
        }
        .frame(width: 400, height: 500)
    }
}

#Preview {
    StakingView()
}
