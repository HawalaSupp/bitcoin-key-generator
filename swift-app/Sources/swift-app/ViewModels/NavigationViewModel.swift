import SwiftUI

/// ViewModel managing all navigation and sheet presentation state
/// This centralizes the ~35 sheet presentation booleans from ContentView
@MainActor
final class NavigationViewModel: ObservableObject {
    // MARK: - Main Navigation
    @Published var selectedChain: ChainInfo?
    @Published var showSplashScreen = true
    
    // MARK: - Sidebar ↔ Tab Sync (ROADMAP-03 E8)
    @Published var sidebarTab: String = "Portfolio"
    
    // MARK: - Onboarding
    @Published var onboardingStep: OnboardingStep = .welcome
    @Published var completedOnboardingThisSession = false
    @Published var shouldAutoGenerateAfterOnboarding = false
    @AppStorage("hawala.onboardingCompleted") var onboardingCompleted = false
    
    // MARK: - Core Sheets
    @Published var showSettingsPanel = false
    @Published var showSecuritySettings = false
    @Published var showAllPrivateKeysSheet = false
    @Published var showReceiveSheet = false
    @Published var showSendPicker = false
    @Published var showSeedPhraseSheet = false
    @Published var showTransactionHistorySheet = false
    @Published var showKeyboardShortcutsHelp = false
    
    // MARK: - Security Sheets
    @Published var showSecurityNotice = false
    @Published var showUnlockSheet = false
    @Published var showExportPasswordPrompt = false
    @Published var showImportPasswordPrompt = false
    @Published var showImportPrivateKeySheet = false
    @Published var showPrivateKeyPasswordPrompt = false
    @Published var pendingImportData: Data?
    
    // MARK: - Feature Sheets
    @Published var showContactsSheet = false
    @Published var showStakingSheet = false
    @Published var showNotificationsSheet = false
    @Published var showMultisigSheet = false
    @Published var showHardwareWalletSheet = false
    @Published var showWatchOnlySheet = false
    @Published var showWalletConnectSheet = false
    @Published var showBatchTransactionSheet = false
    
    // MARK: - Phase 3 Feature Sheets
    @Published var showL2AggregatorSheet = false
    @Published var showPaymentLinksSheet = false
    @Published var showTransactionNotesSheet = false
    @Published var showSellCryptoSheet = false
    @Published var showPriceAlertsSheet = false
    
    // MARK: - Phase 4 Feature Sheets (ERC-4337 Account Abstraction)
    @Published var showSmartAccountSheet = false
    @Published var showGasAccountSheet = false
    @Published var showPasskeyAuthSheet = false
    @Published var showGaslessTxSheet = false
    
    // MARK: - ROADMAP-21: Multi-Wallet
    @Published var showWalletPickerSheet = false
    @Published var showAddWalletSheet = false
    @Published var showDeleteWalletConfirmation = false
    @Published var walletToDelete: UUID?
    
    // MARK: - ROADMAP-22: Hardware Wallet State
    @Published var isHardwareWalletConnected = false
    @Published var connectedHardwareDeviceType: HardwareDeviceType?
    @Published var hardwareWalletFirmwareVersion: String?
    @Published var showHardwareWalletSetupSheet = false
    
    // MARK: - ROADMAP-23: Duress Mode State
    @Published var isDuressActive = false
    @Published var showDuressSetupSheet = false
    @Published var showAuditLogSheet = false
    
    // MARK: - Send Flow Context
    @Published var sendChainContext: ChainInfo?
    @Published var pendingSendChain: ChainInfo?
    
    // MARK: - Receive Flow Context
    @Published var receiveChainContext: ChainInfo?
    
    // MARK: - Transaction Detail
    @Published var selectedTransactionForDetail: HawalaTransactionEntry?
    @Published var speedUpTransaction: PendingTransactionManager.PendingTransaction?
    @Published var cancelTransaction: PendingTransactionManager.PendingTransaction?
    
    // MARK: - Layout
    @Published var viewportWidth: CGFloat = 900
    
    // MARK: - Navigation Actions
    func selectChain(_ chain: ChainInfo?) {
        withAnimation(HawalaTheme.Animation.fast) {
            selectedChain = chain
        }
    }
    
    func closeChainDetail() {
        withAnimation(HawalaTheme.Animation.fast) {
            selectedChain = nil
        }
    }
    
    func openSend(for chain: ChainInfo) {
        pendingSendChain = chain
        selectedChain = nil
    }
    
    func presentQueuedSendIfNeeded() {
        guard let chain = pendingSendChain else { return }
        sendChainContext = chain
        pendingSendChain = nil
    }
    
    func dismissSend() {
        sendChainContext = nil
    }
    
    // MARK: - Onboarding Flow
    func advanceOnboarding() {
        switch onboardingStep {
        case .welcome:
            onboardingStep = .security
        case .security:
            onboardingStep = .passcode
        case .passcode:
            onboardingStep = .ready
        case .ready:
            completeOnboarding()
        }
    }
    
    func completeOnboarding() {
        onboardingCompleted = true
        completedOnboardingThisSession = true
    }
    
    func resetOnboarding() {
        onboardingCompleted = false
        onboardingStep = .welcome
        shouldAutoGenerateAfterOnboarding = false
    }
    
    // MARK: - Bulk Sheet Dismiss
    func dismissAllSheets() {
        showSettingsPanel = false
        showSecuritySettings = false
        showAllPrivateKeysSheet = false
        showReceiveSheet = false
        showSendPicker = false
        showSeedPhraseSheet = false
        showTransactionHistorySheet = false
        showKeyboardShortcutsHelp = false
        showSecurityNotice = false
        showUnlockSheet = false
        showExportPasswordPrompt = false
        showImportPasswordPrompt = false
        showImportPrivateKeySheet = false
        showPrivateKeyPasswordPrompt = false
        showContactsSheet = false
        showStakingSheet = false
        showNotificationsSheet = false
        showMultisigSheet = false
        showHardwareWalletSheet = false
        showWatchOnlySheet = false
        showWalletConnectSheet = false
        showBatchTransactionSheet = false
        showL2AggregatorSheet = false
        showPaymentLinksSheet = false
        showTransactionNotesSheet = false
        showSellCryptoSheet = false
        showPriceAlertsSheet = false
        showSmartAccountSheet = false
        showGasAccountSheet = false
        showPasskeyAuthSheet = false
        showGaslessTxSheet = false
        showWalletPickerSheet = false
        showAddWalletSheet = false
        showDeleteWalletConfirmation = false
        walletToDelete = nil
        showHardwareWalletSetupSheet = false
        showDuressSetupSheet = false
        showAuditLogSheet = false
        sendChainContext = nil
        pendingSendChain = nil
        receiveChainContext = nil
    }
}
