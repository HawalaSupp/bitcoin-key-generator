import SwiftUI
import Combine

// MARK: - Persona System
/// Manages user personas and their associated defaults/preferences

@MainActor
final class PersonaManager: ObservableObject {
    
    // MARK: - Published State
    @Published private(set) var currentPersona: UserPersona?
    @Published private(set) var settings: PersonaSettings = PersonaSettings()
    
    // MARK: - Storage
    private let personaKey = "hawala.persona.current"
    private let settingsKey = "hawala.persona.settings"
    
    // MARK: - Singleton
    static let shared = PersonaManager()
    
    private init() {
        loadState()
    }
    
    // MARK: - Persona Selection
    
    func selectPersona(_ persona: UserPersona) {
        currentPersona = persona
        settings = PersonaSettings.defaults(for: persona)
        saveState()
        
        // Post notification for other components
        NotificationCenter.default.post(name: .personaChanged, object: persona)
        
        #if DEBUG
        print("🎭 Persona selected: \(persona.rawValue)")
        print("   Settings: \(settings)")
        #endif
    }
    
    /// Get the recommended word count for seed phrase
    var recommendedWordCount: Int {
        switch currentPersona {
        case .beginner, .collector:
            return 12
        case .trader, .builder:
            return 24
        case .none:
            return 12
        }
    }
    
    /// Should show educational tooltips?
    var showTooltips: Bool {
        settings.showEducationalTooltips
    }
    
    /// Should show simplified UI?
    var useSimplifiedUI: Bool {
        settings.simplifiedInterface
    }
    
    /// Default chains to enable
    var defaultChains: [String] {
        guard let persona = currentPersona else {
            return ["ethereum", "bitcoin"]
        }
        
        switch persona {
        case .beginner:
            return ["ethereum", "bitcoin"] // Basic chains only
        case .collector:
            return ["ethereum", "bitcoin", "solana"]
        case .trader:
            return ["ethereum", "bitcoin", "solana", "polygon", "arbitrum", "optimism"]
        case .builder:
            return Array(SupportedChain.allCases.map { $0.rawValue }.prefix(15))
        }
    }
    
    // MARK: - Settings Updates
    
    func updateSetting(_ keyPath: WritableKeyPath<PersonaSettings, Bool>, value: Bool) {
        settings[keyPath: keyPath] = value
        saveState()
    }
    
    func updateSetting(_ keyPath: WritableKeyPath<PersonaSettings, Int>, value: Int) {
        settings[keyPath: keyPath] = value
        saveState()
    }
    
    // MARK: - Persistence
    
    private func saveState() {
        if let persona = currentPersona {
            UserDefaults.standard.set(persona.rawValue, forKey: personaKey)
        }
        
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }
    
    private func loadState() {
        if let rawValue = UserDefaults.standard.string(forKey: personaKey),
           let persona = UserPersona(rawValue: rawValue) {
            currentPersona = persona
        }
        
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let savedSettings = try? JSONDecoder().decode(PersonaSettings.self, from: data) {
            settings = savedSettings
        }
    }
}

// MARK: - Persona Settings

struct PersonaSettings: Codable, Equatable {
    // UI Preferences
    var showEducationalTooltips: Bool = true
    var simplifiedInterface: Bool = false
    var showAdvancedFeatures: Bool = false
    var showTestnetChains: Bool = false
    
    // Security Preferences
    var autoLockMinutes: Int = 5
    var requireBiometricForSend: Bool = true
    var hideBalancesByDefault: Bool = false
    var showTransactionSimulation: Bool = true
    
    // Transaction Preferences
    var confirmLargeTransactions: Bool = true
    var largeTransactionThreshold: Int = 500 // USD
    var showGasPriceWarnings: Bool = true
    var preferFastGas: Bool = false
    
    // Notification Preferences
    var notifyOnReceive: Bool = true
    var notifyOnLargeMovements: Bool = true
    var notifyOnPriceAlerts: Bool = false
    
    /// Get default settings for a persona
    static func defaults(for persona: UserPersona) -> PersonaSettings {
        var settings = PersonaSettings()
        
        switch persona {
        case .beginner:
            settings.showEducationalTooltips = true
            settings.simplifiedInterface = true
            settings.showAdvancedFeatures = false
            settings.showTestnetChains = false
            settings.autoLockMinutes = 2
            settings.requireBiometricForSend = true
            settings.showTransactionSimulation = true
            settings.confirmLargeTransactions = true
            settings.largeTransactionThreshold = 100
            
        case .collector:
            settings.showEducationalTooltips = true
            settings.simplifiedInterface = true
            settings.showAdvancedFeatures = false
            settings.showTestnetChains = false
            settings.autoLockMinutes = 5
            settings.requireBiometricForSend = true
            settings.hideBalancesByDefault = true
            settings.showTransactionSimulation = true
            
        case .trader:
            settings.showEducationalTooltips = false
            settings.simplifiedInterface = false
            settings.showAdvancedFeatures = true
            settings.showTestnetChains = false
            settings.autoLockMinutes = 15
            settings.requireBiometricForSend = false
            settings.showTransactionSimulation = true
            settings.showGasPriceWarnings = true
            settings.preferFastGas = true
            settings.notifyOnPriceAlerts = true
            
        case .builder:
            settings.showEducationalTooltips = false
            settings.simplifiedInterface = false
            settings.showAdvancedFeatures = true
            settings.showTestnetChains = true
            settings.autoLockMinutes = 30
            settings.requireBiometricForSend = false
            settings.showTransactionSimulation = true
            settings.confirmLargeTransactions = true
            settings.largeTransactionThreshold = 1000
        }
        
        return settings
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let personaChanged = Notification.Name("com.hawala.personaChanged")
}

// MARK: - Educational Content System

struct EducationalContent {
    
    // MARK: - Lesson Types
    
    struct Lesson: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let content: [LessonPage]
        let estimatedMinutes: Int
        let category: Category
        
        enum Category: String, CaseIterable {
            case basics = "Basics"
            case security = "Security"
            case transactions = "Transactions"
            case advanced = "Advanced"
            
            var color: Color {
                switch self {
                case .basics: return .blue
                case .security: return .green
                case .transactions: return .orange
                case .advanced: return .purple
                }
            }
        }
    }
    
    struct LessonPage: Identifiable {
        let id = UUID()
        let title: String
        let content: String
        let illustration: String? // SF Symbol or asset name
        let interactive: InteractiveElement?
    }
    
    enum InteractiveElement {
        case quiz(questions: [QuizQuestion])
        case simulation(type: SimulationType)
        case checkbox(text: String)
    }
    
    struct QuizQuestion: Identifiable {
        let id = UUID()
        let question: String
        let options: [String]
        let correctIndex: Int
        let explanation: String
    }
    
    enum SimulationType {
        case receiveTransaction
        case sendTransaction
        case backupPhrase
    }
    
    // MARK: - Static Content
    
    static let selfCustodyLesson = Lesson(
        id: "self-custody-101",
        title: "What is Self-Custody?",
        subtitle: "Understand your keys, your coins",
        icon: "key.fill",
        content: [
            LessonPage(
                title: "Traditional Banks vs Crypto",
                content: "With a bank, they hold your money and control access. With crypto, YOU hold your assets directly using cryptographic keys.",
                illustration: "building.columns.fill",
                interactive: nil
            ),
            LessonPage(
                title: "Your Keys = Your Crypto",
                content: "A private key is like a master password that proves you own your crypto. Whoever has this key can spend the funds.",
                illustration: "key.fill",
                interactive: nil
            ),
            LessonPage(
                title: "Recovery Phrase",
                content: "Your recovery phrase (12 or 24 words) can regenerate your private key. It's the ONLY way to recover your wallet if you lose access.",
                illustration: "doc.text.fill",
                interactive: nil
            ),
            LessonPage(
                title: "Quick Check",
                content: "Let's make sure you understand the basics.",
                illustration: nil,
                interactive: .quiz(questions: [
                    QuizQuestion(
                        question: "Who controls your crypto in a self-custody wallet?",
                        options: ["The wallet company", "You", "The blockchain", "No one"],
                        correctIndex: 1,
                        explanation: "Correct! In self-custody, only you control your private keys and therefore your crypto."
                    ),
                    QuizQuestion(
                        question: "What happens if you lose your recovery phrase?",
                        options: ["Call customer support", "Reset your password", "Your funds may be lost forever", "Nothing, it's optional"],
                        correctIndex: 2,
                        explanation: "Important! There is no customer support for self-custody. Your recovery phrase is the only way to restore access."
                    )
                ])
            )
        ],
        estimatedMinutes: 3,
        category: .basics
    )
    
    static let securityBestPractices = Lesson(
        id: "security-101",
        title: "Staying Safe",
        subtitle: "Protect your assets from threats",
        icon: "shield.fill",
        content: [
            LessonPage(
                title: "Never Share Your Phrase",
                content: "Hawala will NEVER ask for your recovery phrase. No legitimate service will. Anyone who asks is trying to steal your funds.",
                illustration: "exclamationmark.shield.fill",
                interactive: nil
            ),
            LessonPage(
                title: "Phishing Attacks",
                content: "Scammers create fake websites that look real. Always verify you're on the correct site. Bookmark important sites.",
                illustration: "link.badge.plus",
                interactive: nil
            ),
            LessonPage(
                title: "Secure Your Backup",
                content: "Write your recovery phrase on paper. Never take a photo or save it digitally. Store it in a safe place.",
                illustration: "doc.text.fill",
                interactive: .checkbox(text: "I understand I should never store my recovery phrase digitally")
            )
        ],
        estimatedMinutes: 2,
        category: .security
    )
    
    static let transactionBasics = Lesson(
        id: "transactions-101",
        title: "Sending & Receiving",
        subtitle: "How crypto transactions work",
        icon: "arrow.left.arrow.right",
        content: [
            LessonPage(
                title: "Wallet Addresses",
                content: "Your wallet address is like an email address for crypto. You can share it publicly to receive funds.",
                illustration: "at",
                interactive: nil
            ),
            LessonPage(
                title: "Transaction Fees",
                content: "Every transaction requires a small fee paid to the network. Fees vary based on network congestion.",
                illustration: "dollarsign.circle.fill",
                interactive: nil
            ),
            LessonPage(
                title: "Confirmations",
                content: "Transactions need confirmations from the network. More confirmations = more security. Wait for confirmations before considering a payment complete.",
                illustration: "checkmark.circle.fill",
                interactive: nil
            ),
            LessonPage(
                title: "Practice",
                content: "Let's practice receiving and sending with a simulation.",
                illustration: nil,
                interactive: .simulation(type: .receiveTransaction)
            )
        ],
        estimatedMinutes: 4,
        category: .transactions
    )
    
    static var allLessons: [Lesson] {
        [selfCustodyLesson, securityBestPractices, transactionBasics]
    }
    
    static func lessons(for persona: UserPersona) -> [Lesson] {
        switch persona {
        case .beginner:
            return allLessons // All lessons
        case .collector:
            return [securityBestPractices] // Just security
        case .trader, .builder:
            return [] // Skip education
        }
    }
}

// MARK: - Tooltip System

struct TooltipData: Identifiable {
    let id: String
    let title: String
    let message: String
    let learnMoreURL: String?
}

@MainActor
final class TooltipManager: ObservableObject {
    
    @Published var activeTooltip: TooltipData?
    @Published private(set) var dismissedTooltips: Set<String> = []
    
    static let shared = TooltipManager()
    
    private let dismissedKey = "hawala.tooltips.dismissed"
    
    private init() {
        loadDismissed()
    }
    
    // MARK: - Predefined Tooltips
    
    static let tooltips: [String: TooltipData] = [
        "send_address": TooltipData(
            id: "send_address",
            title: "Recipient Address",
            message: "Enter the wallet address of the person or service you're sending to. Double-check this - transactions cannot be reversed!",
            learnMoreURL: nil
        ),
        "gas_fee": TooltipData(
            id: "gas_fee",
            title: "Network Fee",
            message: "This fee goes to the network (not Hawala) to process your transaction. Higher fees = faster confirmation.",
            learnMoreURL: nil
        ),
        "recovery_phrase": TooltipData(
            id: "recovery_phrase",
            title: "Recovery Phrase",
            message: "These 12-24 words are the ONLY way to recover your wallet. Write them down and store safely. Never share them!",
            learnMoreURL: nil
        ),
        "chain_selector": TooltipData(
            id: "chain_selector",
            title: "Blockchain Networks",
            message: "Different cryptocurrencies live on different networks. Make sure you're on the right network before sending.",
            learnMoreURL: nil
        ),
        "balance_hidden": TooltipData(
            id: "balance_hidden",
            title: "Hidden Balance",
            message: "Your balance is hidden for privacy. Tap to reveal temporarily.",
            learnMoreURL: nil
        )
    ]
    
    // MARK: - Show/Dismiss
    
    func show(_ tooltipId: String) {
        guard !dismissedTooltips.contains(tooltipId),
              let tooltip = Self.tooltips[tooltipId],
              PersonaManager.shared.showTooltips else {
            return
        }
        
        activeTooltip = tooltip
    }
    
    func dismiss(_ tooltipId: String, permanently: Bool = false) {
        if permanently {
            dismissedTooltips.insert(tooltipId)
            saveDismissed()
        }
        
        if activeTooltip?.id == tooltipId {
            activeTooltip = nil
        }
    }
    
    func dismissAll() {
        activeTooltip = nil
    }
    
    func reset() {
        dismissedTooltips.removeAll()
        saveDismissed()
    }
    
    // MARK: - Persistence
    
    private func saveDismissed() {
        UserDefaults.standard.set(Array(dismissedTooltips), forKey: dismissedKey)
    }
    
    private func loadDismissed() {
        if let dismissed = UserDefaults.standard.stringArray(forKey: dismissedKey) {
            dismissedTooltips = Set(dismissed)
        }
    }
}

// MARK: - Educational Tooltip View

struct EducationalTooltipView: View {
    let tooltip: TooltipData
    let onDismiss: (Bool) -> Void
    
    @State private var isVisible = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                
                Text(tooltip.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button {
                    onDismiss(false)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            
            Text(tooltip.message)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            
            HStack {
                if tooltip.learnMoreURL != nil {
                    Button("Learn More") {
                        // Open URL
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.blue)
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                Button("Don't show again") {
                    onDismiss(true)
                }
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: "#2C2C2E"))
                .shadow(color: .black.opacity(0.3), radius: 10)
        )
        .frame(maxWidth: 320)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 10)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isVisible = true
            }
        }
    }
}

// MARK: - Tooltip Modifier

struct TooltipModifier: ViewModifier {
    let tooltipId: String
    let alignment: Alignment
    
    @ObservedObject var tooltipManager = TooltipManager.shared
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: alignment) {
                if let tooltip = tooltipManager.activeTooltip, tooltip.id == tooltipId {
                    EducationalTooltipView(tooltip: tooltip) { permanent in
                        tooltipManager.dismiss(tooltipId, permanently: permanent)
                    }
                    .padding(8)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .onAppear {
                // Delay to avoid immediate tooltip on view appear
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    tooltipManager.show(tooltipId)
                }
            }
    }
}

extension View {
    func educationalTooltip(_ tooltipId: String, alignment: Alignment = .top) -> some View {
        self.modifier(TooltipModifier(tooltipId: tooltipId, alignment: alignment))
    }
}

// MARK: - Progressive Disclosure Manager

@MainActor
final class ProgressiveDisclosureManager: ObservableObject {
    
    @Published private(set) var unlockedFeatures: Set<String> = []
    @Published private(set) var featureUsageCounts: [String: Int] = [:]
    
    static let shared = ProgressiveDisclosureManager()
    
    private let unlockedKey = "hawala.features.unlocked"
    private let usageKey = "hawala.features.usage"
    
    private init() {
        loadState()
    }
    
    // MARK: - Features
    
    enum Feature: String, CaseIterable {
        // Basic features (always visible)
        case send = "send"
        case receive = "receive"
        case viewBalance = "viewBalance"
        
        // Unlocked after first successful transaction
        case transactionHistory = "transactionHistory"
        case addressBook = "addressBook"
        
        // Unlocked after 3 transactions
        case swapTokens = "swapTokens"
        case staking = "staking"
        
        // Unlocked after 10 transactions or manual unlock
        case advancedGas = "advancedGas"
        case customRPC = "customRPC"
        case messageSign = "messageSign"
        
        // Developer features
        case testnetChains = "testnetChains"
        case debugMode = "debugMode"
        
        var requiredTransactions: Int {
            switch self {
            case .send, .receive, .viewBalance:
                return 0
            case .transactionHistory, .addressBook:
                return 1
            case .swapTokens, .staking:
                return 3
            case .advancedGas, .customRPC, .messageSign:
                return 10
            case .testnetChains, .debugMode:
                return 0 // Manually unlocked
            }
        }
        
        var unlockMessage: String {
            switch self {
            case .transactionHistory:
                return "Transaction history is now available!"
            case .addressBook:
                return "You can now save addresses to your address book"
            case .swapTokens:
                return "Token swapping is now unlocked"
            case .staking:
                return "Staking is now available"
            case .advancedGas:
                return "Advanced gas settings unlocked"
            case .customRPC:
                return "Custom RPC endpoints now available"
            case .messageSign:
                return "Message signing unlocked"
            default:
                return ""
            }
        }
    }
    
    // MARK: - Feature Access
    
    func isUnlocked(_ feature: Feature) -> Bool {
        // Basic features always unlocked
        if feature.requiredTransactions == 0 {
            return true
        }
        
        // Check persona - advanced users get everything
        if let persona = PersonaManager.shared.currentPersona {
            if persona == .trader || persona == .builder {
                return true
            }
        }
        
        // Check if manually unlocked
        if unlockedFeatures.contains(feature.rawValue) {
            return true
        }
        
        // Check transaction count
        let transactionCount = featureUsageCounts["transactions"] ?? 0
        return transactionCount >= feature.requiredTransactions
    }
    
    func unlock(_ feature: Feature) {
        guard !unlockedFeatures.contains(feature.rawValue) else { return }
        
        unlockedFeatures.insert(feature.rawValue)
        saveState()
        
        // Post notification
        NotificationCenter.default.post(
            name: .featureUnlocked,
            object: feature
        )
        
        #if DEBUG
        print("🔓 Feature unlocked: \(feature.rawValue)")
        #endif
    }
    
    func recordUsage(_ feature: String) {
        featureUsageCounts[feature, default: 0] += 1
        saveState()
        checkUnlocks()
    }
    
    func recordTransaction() {
        recordUsage("transactions")
    }
    
    private func checkUnlocks() {
        let transactionCount = featureUsageCounts["transactions"] ?? 0
        
        for feature in Feature.allCases {
            if !unlockedFeatures.contains(feature.rawValue) &&
               transactionCount >= feature.requiredTransactions &&
               feature.requiredTransactions > 0 {
                unlock(feature)
            }
        }
    }
    
    // MARK: - Persistence
    
    private func saveState() {
        UserDefaults.standard.set(Array(unlockedFeatures), forKey: unlockedKey)
        UserDefaults.standard.set(featureUsageCounts, forKey: usageKey)
    }
    
    private func loadState() {
        if let unlocked = UserDefaults.standard.stringArray(forKey: unlockedKey) {
            unlockedFeatures = Set(unlocked)
        }
        
        if let usage = UserDefaults.standard.dictionary(forKey: usageKey) as? [String: Int] {
            featureUsageCounts = usage
        }
    }
    
    func reset() {
        unlockedFeatures.removeAll()
        featureUsageCounts.removeAll()
        saveState()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let featureUnlocked = Notification.Name("com.hawala.featureUnlocked")
}

// MARK: - Feature Lock View Modifier

struct FeatureLockModifier: ViewModifier {
    let feature: ProgressiveDisclosureManager.Feature
    let showLockOverlay: Bool
    
    @ObservedObject var manager = ProgressiveDisclosureManager.shared
    
    var isUnlocked: Bool {
        manager.isUnlocked(feature)
    }
    
    func body(content: Content) -> some View {
        if isUnlocked {
            content
        } else if showLockOverlay {
            content
                .blur(radius: 3)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Text("Complete \(feature.requiredTransactions) transactions to unlock")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.5))
                }
                .allowsHitTesting(false)
        } else {
            EmptyView()
        }
    }
}

extension View {
    func requiresFeature(_ feature: ProgressiveDisclosureManager.Feature, showLock: Bool = true) -> some View {
        self.modifier(FeatureLockModifier(feature: feature, showLockOverlay: showLock))
    }
}
