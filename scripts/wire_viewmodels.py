#!/usr/bin/env python3
"""Wire ViewModels to ContentView - replace @State references with ViewModel properties"""
import re
import sys

def main():
    filepath = '/Users/x/Desktop/888/swift-app/Sources/swift-app/ContentView.swift'
    
    with open(filepath, 'r') as f:
        content = f.read()
    
    # Navigation-related replacements (precise patterns using word boundaries)
    replacements = [
        # Splash screen
        (r'\$showSplashScreen\b', '$navigationVM.showSplashScreen'),
        (r'\bshowSplashScreen\b', 'navigationVM.showSplashScreen'),
        
        # Onboarding
        (r'\$onboardingStep\b', '$navigationVM.onboardingStep'),
        (r'\bonboardingStep\b', 'navigationVM.onboardingStep'),
        (r'\$shouldAutoGenerateAfterOnboarding\b', '$navigationVM.shouldAutoGenerateAfterOnboarding'),
        (r'\bshouldAutoGenerateAfterOnboarding\b', 'navigationVM.shouldAutoGenerateAfterOnboarding'),
        (r'\$completedOnboardingThisSession\b', '$navigationVM.completedOnboardingThisSession'),
        (r'\bcompletedOnboardingThisSession\b', 'navigationVM.completedOnboardingThisSession'),
        
        # Core sheets
        (r'\$showSettingsPanel\b', '$navigationVM.showSettingsPanel'),
        (r'\bshowSettingsPanel\b', 'navigationVM.showSettingsPanel'),
        (r'\$showSecuritySettings\b', '$navigationVM.showSecuritySettings'),
        (r'\bshowSecuritySettings\b', 'navigationVM.showSecuritySettings'),
        (r'\$showAllPrivateKeysSheet\b', '$navigationVM.showAllPrivateKeysSheet'),
        (r'\bshowAllPrivateKeysSheet\b', 'navigationVM.showAllPrivateKeysSheet'),
        (r'\$showReceiveSheet\b', '$navigationVM.showReceiveSheet'),
        (r'\bshowReceiveSheet\b', 'navigationVM.showReceiveSheet'),
        (r'\$showSendPicker\b', '$navigationVM.showSendPicker'),
        (r'\bshowSendPicker\b', 'navigationVM.showSendPicker'),
        (r'\$showSeedPhraseSheet\b', '$navigationVM.showSeedPhraseSheet'),
        (r'\bshowSeedPhraseSheet\b', 'navigationVM.showSeedPhraseSheet'),
        (r'\$showTransactionHistorySheet\b', '$navigationVM.showTransactionHistorySheet'),
        (r'\bshowTransactionHistorySheet\b', 'navigationVM.showTransactionHistorySheet'),
        (r'\$showKeyboardShortcutsHelp\b', '$navigationVM.showKeyboardShortcutsHelp'),
        (r'\bshowKeyboardShortcutsHelp\b', 'navigationVM.showKeyboardShortcutsHelp'),
        
        # Feature sheets
        (r'\$showContactsSheet\b', '$navigationVM.showContactsSheet'),
        (r'\bshowContactsSheet\b', 'navigationVM.showContactsSheet'),
        (r'\$showStakingSheet\b', '$navigationVM.showStakingSheet'),
        (r'\bshowStakingSheet\b', 'navigationVM.showStakingSheet'),
        (r'\$showNotificationsSheet\b', '$navigationVM.showNotificationsSheet'),
        (r'\bshowNotificationsSheet\b', 'navigationVM.showNotificationsSheet'),
        (r'\$showMultisigSheet\b', '$navigationVM.showMultisigSheet'),
        (r'\bshowMultisigSheet\b', 'navigationVM.showMultisigSheet'),
        (r'\$showHardwareWalletSheet\b', '$navigationVM.showHardwareWalletSheet'),
        (r'\bshowHardwareWalletSheet\b', 'navigationVM.showHardwareWalletSheet'),
        (r'\$showWatchOnlySheet\b', '$navigationVM.showWatchOnlySheet'),
        (r'\bshowWatchOnlySheet\b', 'navigationVM.showWatchOnlySheet'),
        (r'\$showWalletConnectSheet\b', '$navigationVM.showWalletConnectSheet'),
        (r'\bshowWalletConnectSheet\b', 'navigationVM.showWalletConnectSheet'),
        (r'\$showBatchTransactionSheet\b', '$navigationVM.showBatchTransactionSheet'),
        (r'\bshowBatchTransactionSheet\b', 'navigationVM.showBatchTransactionSheet'),
        
        # Phase 3 Feature Sheets
        (r'\$showL2AggregatorSheet\b', '$navigationVM.showL2AggregatorSheet'),
        (r'\bshowL2AggregatorSheet\b', 'navigationVM.showL2AggregatorSheet'),
        (r'\$showPaymentLinksSheet\b', '$navigationVM.showPaymentLinksSheet'),
        (r'\bshowPaymentLinksSheet\b', 'navigationVM.showPaymentLinksSheet'),
        (r'\$showTransactionNotesSheet\b', '$navigationVM.showTransactionNotesSheet'),
        (r'\bshowTransactionNotesSheet\b', 'navigationVM.showTransactionNotesSheet'),
        (r'\$showSellCryptoSheet\b', '$navigationVM.showSellCryptoSheet'),
        (r'\bshowSellCryptoSheet\b', 'navigationVM.showSellCryptoSheet'),
        (r'\$showPriceAlertsSheet\b', '$navigationVM.showPriceAlertsSheet'),
        (r'\bshowPriceAlertsSheet\b', 'navigationVM.showPriceAlertsSheet'),
        
        # Phase 4 Feature Sheets
        (r'\$showSmartAccountSheet\b', '$navigationVM.showSmartAccountSheet'),
        (r'\bshowSmartAccountSheet\b', 'navigationVM.showSmartAccountSheet'),
        (r'\$showGasAccountSheet\b', '$navigationVM.showGasAccountSheet'),
        (r'\bshowGasAccountSheet\b', 'navigationVM.showGasAccountSheet'),
        (r'\$showPasskeyAuthSheet\b', '$navigationVM.showPasskeyAuthSheet'),
        (r'\bshowPasskeyAuthSheet\b', 'navigationVM.showPasskeyAuthSheet'),
        (r'\$showGaslessTxSheet\b', '$navigationVM.showGaslessTxSheet'),
        (r'\bshowGaslessTxSheet\b', 'navigationVM.showGaslessTxSheet'),
        
        # Security sheets (in navigationVM)
        (r'\$showSecurityNotice\b', '$navigationVM.showSecurityNotice'),
        (r'\bshowSecurityNotice\b', 'navigationVM.showSecurityNotice'),
        (r'\$showUnlockSheet\b', '$navigationVM.showUnlockSheet'),
        (r'\bshowUnlockSheet\b', 'navigationVM.showUnlockSheet'),
        (r'\$showExportPasswordPrompt\b', '$navigationVM.showExportPasswordPrompt'),
        (r'\bshowExportPasswordPrompt\b', 'navigationVM.showExportPasswordPrompt'),
        (r'\$showImportPasswordPrompt\b', '$navigationVM.showImportPasswordPrompt'),
        (r'\bshowImportPasswordPrompt\b', 'navigationVM.showImportPasswordPrompt'),
        (r'\$showImportPrivateKeySheet\b', '$navigationVM.showImportPrivateKeySheet'),
        (r'\bshowImportPrivateKeySheet\b', 'navigationVM.showImportPrivateKeySheet'),
        (r'\$pendingImportData\b', '$navigationVM.pendingImportData'),
        (r'\bpendingImportData\b', 'navigationVM.pendingImportData'),
        
        # Send context
        (r'\$sendChainContext\b', '$navigationVM.sendChainContext'),
        (r'\bsendChainContext\b', 'navigationVM.sendChainContext'),
        (r'\$pendingSendChain\b', '$navigationVM.pendingSendChain'),
        (r'\bpendingSendChain\b', 'navigationVM.pendingSendChain'),
        
        # Transaction detail
        (r'\$selectedTransactionForDetail\b', '$navigationVM.selectedTransactionForDetail'),
        (r'\bselectedTransactionForDetail\b', 'navigationVM.selectedTransactionForDetail'),
        (r'\$speedUpTransaction\b', '$navigationVM.speedUpTransaction'),
        (r'\bspeedUpTransaction\b', 'navigationVM.speedUpTransaction'),
        (r'\$cancelTransaction\b', '$navigationVM.cancelTransaction'),
        (r'\bcancelTransaction\b', 'navigationVM.cancelTransaction'),
        
        # Viewport
        (r'\$viewportWidth\b', '$navigationVM.viewportWidth'),
        (r'\bviewportWidth\b', 'navigationVM.viewportWidth'),
        
        # Security state (securityVM)
        (r'\$showPrivacyBlur\b', '$securityVM.showPrivacyBlur'),
        (r'\bshowPrivacyBlur\b', 'securityVM.showPrivacyBlur'),
        (r'\$biometricState\b', '$securityVM.biometricState'),
        (r'\bbiometricState\b', 'securityVM.biometricState'),
        (r'\$lastActivityTimestamp\b', '$securityVM.lastActivityTimestamp'),
        (r'\blastActivityTimestamp\b', 'securityVM.lastActivityTimestamp'),
        (r'\$autoLockTask\b', '$securityVM.autoLockTask'),
        (r'\bautoLockTask\b', 'securityVM.autoLockTask'),
    ]
    
    for pattern, replacement in replacements:
        content = re.sub(pattern, replacement, content)
    
    with open(filepath, 'w') as f:
        f.write(content)
    
    print(f"Replaced references in {filepath}")

if __name__ == '__main__':
    main()
