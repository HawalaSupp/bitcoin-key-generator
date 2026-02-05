#!/usr/bin/env python3
"""
Step 1: Remove duplicate @State declarations that are now in ViewModels
Step 2: Update usages to use ViewModel prefix (but not in @State declarations or parameter labels)
"""
import re

contentview_path = "/Users/x/Desktop/888/swift-app/Sources/swift-app/ContentView.swift"

with open(contentview_path, 'r') as f:
    lines = f.readlines()

# Properties to migrate to navigationVM
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

# Properties to migrate to securityVM
security_props = [
    'showPrivacyBlur', 'biometricState', 'lastActivityTimestamp', 'autoLockTask'
]

all_props = set(nav_props + security_props)

# Step 1: Remove @State declarations for migrated properties
new_lines = []
removed_count = 0
for line in lines:
    # Check if this is a @State declaration for a migrated property
    is_migrated_state = False
    for prop in all_props:
        # Match @State declarations like: @State private var showSplashScreen = true
        if re.search(rf'@State\s+(private\s+)?var\s+{prop}\b', line):
            is_migrated_state = True
            removed_count += 1
            print(f"Removing @State declaration: {line.strip()}")
            break
    if not is_migrated_state:
        new_lines.append(line)

content = ''.join(new_lines)

# Step 2: Update usages (not @State declarations since we removed them, not parameter labels)
def replace_nav_property(prop, content):
    # Replace $prop with $navigationVM.prop (binding) - only if not already prefixed
    pattern = r'(?<!navigationVM\.)\$' + prop + r'\b'
    content = re.sub(pattern, f'$navigationVM.{prop}', content)
    
    # Replace bare property access - not preceded by "navigationVM." or "$" or alphanumeric
    # and not followed by ":" (to avoid parameter labels)
    pattern = r'(?<!navigationVM\.)(?<!\$)(?<![a-zA-Z_])' + prop + r'(?!:)\b'
    content = re.sub(pattern, f'navigationVM.{prop}', content)
    
    return content

def replace_security_property(prop, content):
    pattern = r'(?<!securityVM\.)\$' + prop + r'\b'
    content = re.sub(pattern, f'$securityVM.{prop}', content)
    
    pattern = r'(?<!securityVM\.)(?<!\$)(?<![a-zA-Z_])' + prop + r'(?!:)\b'
    content = re.sub(pattern, f'securityVM.{prop}', content)
    
    return content

# Apply replacements
for prop in nav_props:
    content = replace_nav_property(prop, content)

for prop in security_props:
    content = replace_security_property(prop, content)

with open(contentview_path, 'w') as f:
    f.write(content)

print(f"\nRemoved {removed_count} @State declarations")
print(f"Applied ViewModel prefixes to usages in {contentview_path}")
