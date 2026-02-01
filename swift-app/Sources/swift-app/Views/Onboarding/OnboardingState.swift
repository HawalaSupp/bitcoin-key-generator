import SwiftUI

// MARK: - Onboarding State Machine
// Complete state management for the Hawala onboarding experience

// MARK: - Onboarding Path
/// The two main paths through onboarding
enum OnboardingPath: String, CaseIterable {
    case quick = "quick"
    case guided = "guided"
    
    var displayName: String {
        switch self {
        case .quick: return "Quick Setup"
        case .guided: return "Guided Setup"
        }
    }
    
    var description: String {
        switch self {
        case .quick: return "Skip education, fast setup"
        case .guided: return "Full walkthrough"
        }
    }
}

// MARK: - Onboarding Step (New system)
/// All possible steps in the new onboarding flow
enum NewOnboardingStep: String, CaseIterable, Identifiable, Equatable {
    // Shared steps
    case welcome
    case pathSelection
    
    // Content steps (used by both paths)
    case selfCustodyEducation
    case personaSelection
    case createOrImport
    case recoveryPhraseDisplay
    case recoveryPhraseInput
    case verifyBackup
    case guardianSetup
    case practiceMode
    case securitySetup
    case biometricsSetup
    case powerSettings
    case securityScore
    case ready
    
    // Hardware/watch flows
    case hardwareWalletConnect
    case watchAddressInput
    
    // Import method selection flow (Phase 4)
    case importMethodSelection
    case importSeedPhrase
    case importPrivateKey
    case importQRCode
    case importHardwareWallet
    case importiCloudBackup
    case importHawalaFile
    case importSuccess
    case lostBackupRecovery
    
    var id: String { rawValue }
}

// MARK: - Wallet Creation Method
/// How the user wants to create/import their wallet
enum WalletCreationMethod: String, CaseIterable, Identifiable {
    case create = "create"
    case importSeed = "import_seed"
    case ledger = "ledger"
    case trezor = "trezor"
    case keystone = "keystone"
    case watchOnly = "watch_only"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .create: return "plus.circle.fill"
        case .importSeed: return "doc.text.fill"
        case .ledger: return "cpu"
        case .trezor: return "cpu"
        case .keystone: return "qrcode"
        case .watchOnly: return "eye.fill"
        }
    }
    
    var title: String {
        switch self {
        case .create: return "Create New Wallet"
        case .importSeed: return "Import Recovery Phrase"
        case .ledger: return "Ledger"
        case .trezor: return "Trezor"
        case .keystone: return "Keystone"
        case .watchOnly: return "Watch Address"
        }
    }
    
    var subtitle: String {
        switch self {
        case .create: return "Start fresh with a new self-custody wallet"
        case .importSeed: return "12, 18, or 24 word recovery phrase"
        case .ledger: return "Connect via USB or Bluetooth"
        case .trezor: return "Connect via USB"
        case .keystone: return "Scan QR codes"
        case .watchOnly: return "Track any address"
        }
    }
}

// MARK: - User Persona
/// User type for personalized experience
enum UserPersona: String, CaseIterable, Identifiable {
    case beginner = "beginner"
    case collector = "collector"
    case trader = "trader"
    case builder = "builder"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .beginner: return "👤"
        case .collector: return "💎"
        case .trader: return "📈"
        case .builder: return "🔧"
        }
    }
    
    var title: String {
        switch self {
        case .beginner: return "Beginner"
        case .collector: return "Collector"
        case .trader: return "Trader"
        case .builder: return "Builder"
        }
    }
    
    var tagline: String {
        switch self {
        case .beginner: return "Just here to HODL"
        case .collector: return "NFTs and art lover"
        case .trader: return "DeFi and swaps"
        case .builder: return "Developer mode ON"
        }
    }
    
    /// Default settings for this persona (basic, used for onboarding)
    var defaultSettings: BasicPersonaSettings {
        switch self {
        case .beginner:
            return BasicPersonaSettings(
                showEducationalTooltips: true,
                enabledChains: ["ETH", "BTC"],
                showAdvancedFeatures: false,
                enableTestnet: false,
                enableTransactionSimulation: true,
                defaultGasMode: .recommended
            )
        case .collector:
            return BasicPersonaSettings(
                showEducationalTooltips: false,
                enabledChains: ["ETH", "SOL", "BTC", "MATIC"],
                showAdvancedFeatures: false,
                enableTestnet: false,
                enableTransactionSimulation: true,
                defaultGasMode: .recommended
            )
        case .trader:
            return BasicPersonaSettings(
                showEducationalTooltips: false,
                enabledChains: ["ETH", "SOL", "ARB", "OP", "BTC", "BASE"],
                showAdvancedFeatures: true,
                enableTestnet: false,
                enableTransactionSimulation: true,
                defaultGasMode: .aggressive
            )
        case .builder:
            return BasicPersonaSettings(
                showEducationalTooltips: false,
                enabledChains: ["ETH", "SOL", "ARB", "OP", "BASE", "AVAX"],
                showAdvancedFeatures: true,
                enableTestnet: true,
                enableTransactionSimulation: true,
                defaultGasMode: .custom
            )
        }
    }
}

// MARK: - Basic Persona Settings (Legacy)
/// Simplified settings for onboarding screen defaults
struct BasicPersonaSettings {
    var showEducationalTooltips: Bool
    var enabledChains: [String]
    var showAdvancedFeatures: Bool
    var enableTestnet: Bool
    var enableTransactionSimulation: Bool
    var defaultGasMode: GasMode
    
    enum GasMode: String {
        case recommended
        case aggressive
        case custom
    }
}

// MARK: - Security Score
/// Tracks security setup completion
struct SecurityScore {
    var biometricEnabled: Bool = false
    var pinCreated: Bool = false
    var backupCompleted: Bool = false
    var backupVerified: Bool = false
    var guardiansAdded: Bool = false
    var twoFactorEnabled: Bool = false
    
    var score: Int {
        var total = 0
        if pinCreated { total += 20 }
        if biometricEnabled { total += 15 }
        if backupCompleted { total += 25 }
        if backupVerified { total += 15 }
        if guardiansAdded { total += 15 }
        if twoFactorEnabled { total += 10 }
        return total
    }
    
    var maxScore: Int { 100 }
    
    var completedItems: [(title: String, description: String)] {
        var items: [(String, String)] = []
        if pinCreated { items.append(("PIN created", "6-digit passcode set")) }
        if biometricEnabled { items.append(("Biometric lock enabled", "Touch ID active")) }
        if backupCompleted { items.append(("Recovery phrase backed up", "Saved securely")) }
        if backupVerified { items.append(("Backup verified", "Recovery tested")) }
        if guardiansAdded { items.append(("Recovery guardians added", "Social recovery ready")) }
        if twoFactorEnabled { items.append(("2FA enabled", "Extra protection")) }
        return items
    }
    
    var pendingItems: [(title: String, description: String, points: Int)] {
        var items: [(String, String, Int)] = []
        if !pinCreated { items.append(("Create PIN", "Set up passcode", 20)) }
        if !biometricEnabled { items.append(("Enable biometrics", "Quick unlock", 15)) }
        if !backupCompleted { items.append(("Back up recovery phrase", "Save your keys", 25)) }
        if !backupVerified { items.append(("Verify backup", "Confirm you saved it", 15)) }
        if !guardiansAdded { items.append(("Add recovery guardians", "Social recovery", 15)) }
        if !twoFactorEnabled { items.append(("Enable 2FA", "Extra protection", 10)) }
        return items
    }
    
    enum SecurityItem {
        case pinSet
        case biometricsEnabled
        case backupCompleted
        case backupVerified
        case guardianAdded
        case twoFactorEnabled
    }
    
    mutating func complete(_ item: SecurityItem) {
        switch item {
        case .pinSet: pinCreated = true
        case .biometricsEnabled: biometricEnabled = true
        case .backupCompleted: backupCompleted = true
        case .backupVerified: backupVerified = true
        case .guardianAdded: guardiansAdded = true
        case .twoFactorEnabled: twoFactorEnabled = true
        }
    }
}

// MARK: - Onboarding Guardian
/// A recovery guardian for social recovery (onboarding-specific)
struct OnboardingGuardian: Identifiable, Codable {
    let id: UUID
    var name: String
    var contactMethod: ContactMethod
    var contactValue: String
    var isConfirmed: Bool
    var addedDate: Date
    
    enum ContactMethod: String, Codable, CaseIterable {
        case email
        case phone
        case walletAddress
        
        var icon: String {
            switch self {
            case .email: return "envelope.fill"
            case .phone: return "phone.fill"
            case .walletAddress: return "wallet.pass.fill"
            }
        }
        
        var placeholder: String {
            switch self {
            case .email: return "guardian@email.com"
            case .phone: return "+1 (555) 123-4567"
            case .walletAddress: return "0x... or ENS name"
            }
        }
    }
    
    init(name: String, method: ContactMethod, value: String) {
        self.id = UUID()
        self.name = name
        self.contactMethod = method
        self.contactValue = value
        self.isConfirmed = false
        self.addedDate = Date()
    }
}

// MARK: - Onboarding Chain
/// Blockchain networks available for selection during onboarding
struct OnboardingChain: Identifiable {
    let id: String
    let name: String
    let icon: String
    let isEVM: Bool
    
    static let all: [OnboardingChain] = [
        OnboardingChain(id: "ETH", name: "Ethereum", icon: "⟠", isEVM: true),
        OnboardingChain(id: "BTC", name: "Bitcoin", icon: "₿", isEVM: false),
        OnboardingChain(id: "SOL", name: "Solana", icon: "◎", isEVM: false),
        OnboardingChain(id: "ARB", name: "Arbitrum", icon: "🔵", isEVM: true),
        OnboardingChain(id: "OP", name: "Optimism", icon: "🔴", isEVM: true),
        OnboardingChain(id: "BASE", name: "Base", icon: "🔷", isEVM: true),
        OnboardingChain(id: "MATIC", name: "Polygon", icon: "⬡", isEVM: true),
        OnboardingChain(id: "AVAX", name: "Avalanche", icon: "🔺", isEVM: true),
        OnboardingChain(id: "BSC", name: "BNB Chain", icon: "⬡", isEVM: true),
    ]
}

// MARK: - Onboarding State
/// Observable state container for the new onboarding flow
@MainActor
class OnboardingState: ObservableObject {
    // MARK: - Navigation
    @Published var currentStep: NewOnboardingStep = .welcome
    @Published var selectedPath: OnboardingPath? = nil
    @Published var navigationHistory: [NewOnboardingStep] = []
    
    // MARK: - User Choices
    @Published var selectedCreationMethod: WalletCreationMethod? = nil
    @Published var selectedPersona: UserPersona? = nil
    @Published var selectedImportMethod: WalletImportMethod? = nil
    
    // MARK: - Wallet Data
    @Published var generatedRecoveryPhrase: [String] = []
    @Published var importedRecoveryPhrase: [String] = []
    @Published var generatedAddress: String = ""
    @Published var watchAddress: String = ""
    @Published var isWalletCreated: Bool = false
    @Published var importedWalletName: String = ""
    
    // MARK: - Security
    @Published var passcode: String = ""
    @Published var confirmPasscode: String = ""
    @Published var isConfirmingPasscode: Bool = false
    @Published var biometricsEnabled: Bool = false
    @Published var iCloudBackupEnabled: Bool = false
    @Published var securityScore: SecurityScore = SecurityScore()
    
    // MARK: - Verification
    @Published var verificationSelections: [Int: String] = [:]
    
    // MARK: - Guardians
    @Published var guardians: [OnboardingGuardian] = []
    
    // MARK: - Power Settings
    @Published var selectedChains: Set<String> = ["ETH", "BTC", "SOL"]
    @Published var developerModeEnabled: Bool = false
    @Published var enableTestnet: Bool = false
    
    // MARK: - UI State
    @Published var isLoading: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var showPasscodeError: Bool = false
    
    // MARK: - Navigation Methods
    
    func navigateTo(_ step: NewOnboardingStep) {
        navigationHistory.append(currentStep)
        withAnimation(.easeInOut(duration: 0.35)) {
            currentStep = step
        }
    }
    
    func goBack() {
        guard let previousStep = navigationHistory.popLast() else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            currentStep = previousStep
        }
    }
    
    func canGoBack() -> Bool {
        !navigationHistory.isEmpty
    }
    
    // MARK: - Validation
    
    func validatePasscode() -> Bool {
        guard passcode.count == 6 else { return false }
        guard confirmPasscode == passcode else {
            showPasscodeError = true
            errorMessage = "Passcodes don't match"
            return false
        }
        securityScore.pinCreated = true
        return true
    }
    
    // MARK: - Reset
    
    func reset() {
        currentStep = .welcome
        navigationHistory = []
        selectedPath = nil
        selectedCreationMethod = nil
        selectedPersona = nil
        selectedImportMethod = nil
        generatedRecoveryPhrase = []
        importedRecoveryPhrase = []
        generatedAddress = ""
        watchAddress = ""
        isWalletCreated = false
        importedWalletName = ""
        passcode = ""
        confirmPasscode = ""
        isConfirmingPasscode = false
        biometricsEnabled = false
        iCloudBackupEnabled = false
        securityScore = SecurityScore()
        verificationSelections = [:]
        guardians = []
        selectedChains = ["ETH", "BTC", "SOL"]
        developerModeEnabled = false
        enableTestnet = false
        isLoading = false
        showError = false
        errorMessage = ""
    }
}
