#!/usr/bin/env python3
"""
ViewModel wiring script v2 - More careful approach
Avoids double-replacing by using negative lookbehind
Avoids replacing parameter labels
"""
import re

contentview_path = "/Users/x/Desktop/888/swift-app/Sources/swift-app/ContentView.swift"

with open(contentview_path, 'r') as f:
    content = f.read()

# Navigation VM properties - use negative lookbehind to avoid double-replacing
nav_props = [
    'showSplashScreen', 'selectedChain', 'onboardingStep',
    'completedOnboardingThisSession', 'shouldAutoGenerateAfterOnboarding',
    'showAllPrivateKeysSheet', 'showSettingsPanel', 'showContactsSheet',
    'showStakingSheet', 'showNotificationsSheet', 'showMultisigSheet',
    'showHardwareWalletSheet', 'showWatchOnlySheet', 'showWalletConnectSheet',
    'showReceiveSheet', 'showSendPicker', 'showBatchTransactionSheet',
    'showL2AggregatorSheet', 'showPaymentLinksSheet', 'showTransactionNotesSheet',
    'showSellCryptoSheet', 'showPriceAlertsSheet', 'showSmartAccountSheet',
    'showGasAccountSheet', 'showPasskeyAuthSheet', 'showGaslessTxSheet',
    'sendChainContext', 'pendingSendChain', 'showSeedPhraseSheet',
    'showTransactionHistorySheet', 'selectedTransactionForDetail',
    'speedUpTransaction', 'cancelTransaction', 'viewportWidth',
    'showSecurityNotice', 'showSecuritySettings', 'showUnlockSheet',
    'showExportPasswordPrompt', 'showImportPasswordPrompt', 'pendingImportData',
    'showImportPrivateKeySheet', 'showKeyboardShortcutsHelp'
]

security_props = [
    'showPrivacyBlur', 'biometricState', 'lastActivityTimestamp', 'autoLockTask'
]

def replace_nav_property(prop, content):
    # Replace $prop with $navigationVM.prop (binding) - only if not already prefixed
    # (?<!navigationVM\.) is negative lookbehind
    pattern = r'(?<!navigationVM\.)\$' + prop + r'\b'
    content = re.sub(pattern, f'$navigationVM.{prop}', content)
    
    # Replace prop (value access) - only if not already prefixed and not a parameter label
    # Also avoid replacing in @State declarations and in parameter label position (before colon)
    # Pattern: word boundary, not preceded by "navigationVM.", not followed by ":"
    pattern = r'(?<!navigationVM\.)(?<!\$)(?<![a-zA-Z_])' + prop + r'(?!:)\b'
    content = re.sub(pattern, f'navigationVM.{prop}', content)
    
    return content

def replace_security_property(prop, content):
    # Replace $prop with $securityVM.prop (binding)
    pattern = r'(?<!securityVM\.)\$' + prop + r'\b'
    content = re.sub(pattern, f'$securityVM.{prop}', content)
    
    # Replace prop (value access) - not preceded by "securityVM." and not a parameter label
    pattern = r'(?<!securityVM\.)(?<!\$)(?<![a-zA-Z_])' + prop + r'(?!:)\b'
    content = re.sub(pattern, f'securityVM.{prop}', content)
    
    return content

# Apply navigation replacements
for prop in nav_props:
    content = replace_nav_property(prop, content)

# Apply security replacements
for prop in security_props:
    content = replace_security_property(prop, content)

with open(contentview_path, 'w') as f:
    f.write(content)

print(f"Applied ViewModel wiring to {contentview_path}")
