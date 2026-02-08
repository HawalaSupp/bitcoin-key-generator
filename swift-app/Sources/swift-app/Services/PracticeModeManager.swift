import SwiftUI
import Combine

// MARK: - Practice Mode Manager
/// Manages the practice/simulation mode for new users to learn without risk

@MainActor
final class PracticeModeManager: ObservableObject {
    
    // MARK: - Published State
    @Published var isActive = false
    @Published var currentScenario: PracticeScenario?
    @Published var completedScenarios: Set<String> = []
    @Published var practiceBalance: Decimal = 1.5 // Fake ETH balance
    @Published var practiceTransactions: [PracticeTransaction] = []
    
    // MARK: - Storage
    private let completedKey = "hawala.practice.completed"
    
    // MARK: - Singleton
    static let shared = PracticeModeManager()
    
    private init() {
        loadState()
    }
    
    // MARK: - Scenarios
    
    struct PracticeScenario: Identifiable {
        let id: String
        let title: String
        let description: String
        let type: ScenarioType
        let steps: [PracticeStep]
        let reward: String
        
        enum ScenarioType {
            case receive
            case send
            case swap
            case backup
        }
    }
    
    struct PracticeStep: Identifiable {
        let id: String
        let instruction: String
        let hint: String?
        let validation: ValidationRule
        
        enum ValidationRule {
            case anyAction
            case enterAddress
            case enterAmount(min: Decimal, max: Decimal)
            case confirmTransaction
            case copyAddress
            case verifyWords(indices: [Int])
        }
    }
    
    struct PracticeTransaction: Identifiable {
        let id = UUID()
        let type: TransactionType
        let amount: Decimal
        let token: String
        let timestamp: Date
        let counterparty: String
        
        enum TransactionType {
            case sent
            case received
        }
    }
    
    // MARK: - Static Scenarios
    
    static let receiveScenario = PracticeScenario(
        id: "receive-101",
        title: "Receive Crypto",
        description: "Learn how to receive your first crypto payment",
        type: .receive,
        steps: [
            PracticeStep(
                id: "find-address",
                instruction: "Tap 'Receive' to see your wallet address",
                hint: "Your address is like an email - share it to receive funds",
                validation: .anyAction
            ),
            PracticeStep(
                id: "copy-address",
                instruction: "Copy your wallet address",
                hint: "You can share this address with anyone who wants to send you crypto",
                validation: .copyAddress
            ),
            PracticeStep(
                id: "wait-confirmation",
                instruction: "Great! A friend is sending you 0.1 ETH...",
                hint: "In real life, you'd wait for network confirmations",
                validation: .anyAction
            )
        ],
        reward: "You've learned how to receive crypto! 🎉"
    )
    
    static let sendScenario = PracticeScenario(
        id: "send-101",
        title: "Send Crypto",
        description: "Practice sending crypto safely",
        type: .send,
        steps: [
            PracticeStep(
                id: "tap-send",
                instruction: "Tap 'Send' to start a transaction",
                hint: nil,
                validation: .anyAction
            ),
            PracticeStep(
                id: "enter-address",
                instruction: "Enter the recipient's address",
                hint: "Always double-check addresses - transactions cannot be reversed!",
                validation: .enterAddress
            ),
            PracticeStep(
                id: "enter-amount",
                instruction: "Enter the amount to send (try 0.01 ETH)",
                hint: "Start with small amounts when sending to new addresses",
                validation: .enterAmount(min: 0.001, max: 0.1)
            ),
            PracticeStep(
                id: "review-confirm",
                instruction: "Review the transaction details and confirm",
                hint: "Always verify the address and amount before confirming",
                validation: .confirmTransaction
            )
        ],
        reward: "You've learned how to send crypto safely! 🚀"
    )
    
    static let backupScenario = PracticeScenario(
        id: "backup-101",
        title: "Backup Practice",
        description: "Practice verifying your recovery phrase",
        type: .backup,
        steps: [
            PracticeStep(
                id: "view-phrase",
                instruction: "These are your recovery words. In a real wallet, write them down on paper.",
                hint: "Never take a screenshot or save digitally",
                validation: .anyAction
            ),
            PracticeStep(
                id: "verify-words",
                instruction: "Select the correct words to verify you've saved them",
                hint: "This ensures you have an accurate backup",
                validation: .verifyWords(indices: [3, 7, 11])
            )
        ],
        reward: "You understand how to backup your wallet! 🔐"
    )
    
    static var allScenarios: [PracticeScenario] {
        [receiveScenario, sendScenario, backupScenario]
    }
    
    // MARK: - Practice Flow
    
    func startPractice() {
        isActive = true
        practiceBalance = 1.5
        
        // Simulate receiving funds after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.simulateIncomingTransaction()
        }
        
        #if DEBUG
        print("🎮 Practice mode started")
        #endif
    }
    
    func endPractice() {
        isActive = false
        currentScenario = nil
        
        #if DEBUG
        print("🎮 Practice mode ended")
        #endif
    }
    
    func startScenario(_ scenario: PracticeScenario) {
        currentScenario = scenario
        
        #if DEBUG
        print("🎮 Started scenario: \(scenario.title)")
        #endif
    }
    
    func completeScenario(_ scenarioId: String) {
        completedScenarios.insert(scenarioId)
        currentScenario = nil
        saveState()
        
        // Update security score if backup scenario
        if scenarioId == "backup-101" {
            SecurityScoreManager.shared.complete(.practiceCompleted)
        }
        
        #if DEBUG
        print("🎮 Completed scenario: \(scenarioId)")
        #endif
    }
    
    func isCompleted(_ scenarioId: String) -> Bool {
        completedScenarios.contains(scenarioId)
    }
    
    var allScenariosCompleted: Bool {
        Self.allScenarios.allSatisfy { completedScenarios.contains($0.id) }
    }
    
    // MARK: - Simulated Transactions
    
    func simulateIncomingTransaction() {
        guard isActive else { return }
        
        let amount: Decimal = 0.1
        practiceBalance += amount
        
        let tx = PracticeTransaction(
            type: .received,
            amount: amount,
            token: "ETH",
            timestamp: Date(),
            counterparty: "0x1234...abcd (Practice)"
        )
        practiceTransactions.insert(tx, at: 0)
        
        #if DEBUG
        print("🎮 Simulated incoming: +\(amount) ETH")
        #endif
    }
    
    func simulateOutgoingTransaction(amount: Decimal, to address: String) {
        guard isActive else { return }
        guard practiceBalance >= amount else { return }
        
        practiceBalance -= amount
        
        let tx = PracticeTransaction(
            type: .sent,
            amount: amount,
            token: "ETH",
            timestamp: Date(),
            counterparty: address
        )
        practiceTransactions.insert(tx, at: 0)
        
        #if DEBUG
        print("🎮 Simulated outgoing: -\(amount) ETH to \(address)")
        #endif
    }
    
    // MARK: - Practice Wallet Address
    
    var practiceAddress: String {
        "0x742d35Cc6634C0532925a3b844Bc9e7595f00000"
    }
    
    // MARK: - Persistence
    
    private func saveState() {
        UserDefaults.standard.set(Array(completedScenarios), forKey: completedKey)
    }
    
    private func loadState() {
        if let completed = UserDefaults.standard.stringArray(forKey: completedKey) {
            completedScenarios = Set(completed)
        }
    }
    
    func reset() {
        completedScenarios.removeAll()
        practiceTransactions.removeAll()
        practiceBalance = 1.5
        saveState()
    }
}

// MARK: - Practice Mode View

struct PracticeModeView: View {
    @ObservedObject var manager = PracticeModeManager.shared
    @State private var selectedScenario: PracticeModeManager.PracticeScenario?
    @State private var showScenarioDetail = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            ScrollView {
                VStack(spacing: 24) {
                    // Practice Balance Card
                    balanceCard
                    
                    // Scenarios
                    scenariosSection
                    
                    // Recent Practice Transactions
                    if !manager.practiceTransactions.isEmpty {
                        transactionsSection
                    }
                }
                .padding(24)
            }
        }
        .background(Color.black)
        .sheet(item: $selectedScenario) { scenario in
            PracticeScenarioView(scenario: scenario) {
                selectedScenario = nil
            }
        }
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "gamecontroller.fill")
                        .foregroundColor(.green)
                    
                    Text("Practice Mode")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Text("Learn with simulated transactions - no real money")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            Button {
                manager.endPractice()
            } label: {
                Text("Exit")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(Color.white.opacity(0.03))
    }
    
    private var balanceCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Practice Balance")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
                
                Spacer()
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Simulated")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.green)
                }
            }
            
            HStack(alignment: .bottom, spacing: 8) {
                Text("\(manager.practiceBalance.formatted()) ETH")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                VStack(spacing: 8) {
                    Button {
                        selectedScenario = PracticeModeManager.sendScenario
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.circle.fill")
                            Text("Send")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.orange.opacity(0.3))
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        selectedScenario = PracticeModeManager.receiveScenario
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Receive")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.green.opacity(0.3))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [Color.green.opacity(0.2), Color.green.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private var scenariosSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Learning Scenarios")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            
            ForEach(PracticeModeManager.allScenarios) { scenario in
                ScenarioCard(
                    scenario: scenario,
                    isCompleted: manager.isCompleted(scenario.id)
                ) {
                    selectedScenario = scenario
                }
            }
        }
    }
    
    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Practice Transactions")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            
            ForEach(manager.practiceTransactions) { tx in
                PracticeTransactionRow(transaction: tx)
            }
        }
    }
}

// MARK: - Scenario Card

private struct ScenarioCard: View {
    let scenario: PracticeModeManager.PracticeScenario
    let isCompleted: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isCompleted ? Color.green.opacity(0.2) : Color.white.opacity(0.1))
                        .frame(width: 48, height: 48)
                    
                    if isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: iconFor(scenario.type))
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(scenario.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text(scenario.description)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                if !isCompleted {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }
    
    private func iconFor(_ type: PracticeModeManager.PracticeScenario.ScenarioType) -> String {
        switch type {
        case .receive: return "arrow.down.circle"
        case .send: return "arrow.up.circle"
        case .swap: return "arrow.left.arrow.right.circle"
        case .backup: return "doc.text"
        }
    }
}

// MARK: - Practice Transaction Row

private struct PracticeTransactionRow: View {
    let transaction: PracticeModeManager.PracticeTransaction
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.type == .received ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(transaction.type == .received ? .green : .orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.type == .received ? "Received" : "Sent")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                Text(transaction.counterparty)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            Text("\(transaction.type == .received ? "+" : "-")\(transaction.amount.formatted()) \(transaction.token)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(transaction.type == .received ? .green : .white)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
        )
    }
}

// MARK: - Practice Scenario View

struct PracticeScenarioView: View {
    let scenario: PracticeModeManager.PracticeScenario
    let onComplete: () -> Void
    
    @State private var currentStepIndex = 0
    @State private var isCompleted = false
    @State private var inputAddress = ""
    @State private var inputAmount = ""
    @State private var hasCopied = false
    
    @ObservedObject var manager = PracticeModeManager.shared
    
    var currentStep: PracticeModeManager.PracticeStep? {
        guard currentStepIndex < scenario.steps.count else { return nil }
        return scenario.steps[currentStepIndex]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    onComplete()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text("\(currentStepIndex + 1) of \(scenario.steps.count)")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
                
                Spacer()
                
                // Spacer for symmetry
                Color.clear.frame(width: 16, height: 16)
            }
            .padding(20)
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 4)
                    
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: geo.size.width * CGFloat(currentStepIndex + 1) / CGFloat(scenario.steps.count), height: 4)
                }
            }
            .frame(height: 4)
            
            if isCompleted {
                // Completion view
                completionView
            } else if let step = currentStep {
                // Step content
                stepContent(step)
            }
        }
        .background(Color.black)
    }
    
    @ViewBuilder
    private func stepContent(_ step: PracticeModeManager.PracticeStep) -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Instruction
            VStack(spacing: 12) {
                Text(step.instruction)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                if let hint = step.hint {
                    Text(hint)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Interactive area based on validation type
            switch step.validation {
            case .copyAddress:
                addressCopyArea
                
            case .enterAddress:
                addressInputArea
                
            case .enterAmount(let min, let max):
                amountInputArea(min: min, max: max)
                
            case .confirmTransaction:
                confirmationArea
                
            default:
                EmptyView()
            }
            
            Spacer()
            
            // Continue button
            Button {
                advanceStep()
            } label: {
                Text(isLastStep ? "Complete" : "Continue")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(canAdvance ? Color.white : Color.white.opacity(0.3))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canAdvance)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
    
    private var addressCopyArea: some View {
        VStack(spacing: 16) {
            Text("Your Address")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
            
            HStack {
                Text(manager.practiceAddress)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Button {
                    hasCopied = true
                    ClipboardHelper.copySensitive(manager.practiceAddress, timeout: 60)
                } label: {
                    Image(systemName: hasCopied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 16))
                        .foregroundColor(hasCopied ? .green : .white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
            )
        }
        .padding(.horizontal, 24)
    }
    
    private var addressInputArea: some View {
        VStack(spacing: 12) {
            TextField("Enter address", text: $inputAddress)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
            
            Text("Try: 0x742d...0001")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 24)
    }
    
    private func amountInputArea(min: Decimal, max: Decimal) -> some View {
        VStack(spacing: 12) {
            HStack {
                TextField("0.00", text: $inputAmount)
                    .textFieldStyle(.plain)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text("ETH")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Text("Available: \(manager.practiceBalance.formatted()) ETH")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 24)
    }
    
    private var confirmationArea: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                HStack {
                    Text("To:")
                    Spacer()
                    Text(inputAddress.isEmpty ? "0x742d...0001" : inputAddress)
                        .foregroundColor(.white.opacity(0.6))
                }
                
                HStack {
                    Text("Amount:")
                    Spacer()
                    Text("\(inputAmount.isEmpty ? "0.01" : inputAmount) ETH")
                        .foregroundColor(.white.opacity(0.6))
                }
                
                HStack {
                    Text("Fee:")
                    Spacer()
                    Text("~0.0005 ETH")
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .font(.system(size: 14))
            .foregroundColor(.white)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
            )
        }
        .padding(.horizontal, 24)
    }
    
    private var completionView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            OnboardingAnimatedCheckmark(size: 80)
            
            VStack(spacing: 8) {
                Text("Nice work!")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Text(scenario.reward)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            Button {
                manager.completeScenario(scenario.id)
                onComplete()
            } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
    
    private var isLastStep: Bool {
        currentStepIndex == scenario.steps.count - 1
    }
    
    private var canAdvance: Bool {
        guard let step = currentStep else { return false }
        
        switch step.validation {
        case .anyAction:
            return true
        case .copyAddress:
            return hasCopied
        case .enterAddress:
            return inputAddress.count > 10
        case .enterAmount(let min, let max):
            guard let amount = Decimal(string: inputAmount) else { return false }
            return amount >= min && amount <= max
        case .confirmTransaction:
            return true
        case .verifyWords:
            return true // Simplified for now
        }
    }
    
    private func advanceStep() {
        if isLastStep {
            withAnimation {
                isCompleted = true
            }
        } else {
            withAnimation {
                currentStepIndex += 1
            }
        }
    }
}
