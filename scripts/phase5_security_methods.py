#!/usr/bin/env python3
"""
Phase 5: Remove duplicate security methods from ContentView
and update calls to use securityVM.method() instead
"""
import re

contentview_path = "/Users/x/Desktop/888/swift-app/Sources/swift-app/ContentView.swift"

with open(contentview_path, 'r') as f:
    content = f.read()

# Methods to remove from ContentView (they exist in SecurityViewModel)
methods_to_remove = [
    'handlePasscodeChange',
    'lock',
    'recordActivity', 
    'scheduleAutoLockCountdown',
    'startActivityMonitoringIfNeeded',
    'stopActivityMonitoring',
    'refreshBiometricAvailability',
    'attemptBiometricUnlock',
    'hashPasscode',
]

# Function to remove a method definition (handles multi-line functions)
def remove_method(content, method_name):
    # Pattern to match function definition including decorators like @MainActor
    # Match from (optional @MainActor/newline) + "private func methodName" to closing brace
    pattern = rf'(\n    @MainActor\n)?    private func {method_name}\([^)]*\)[^\{{]*\{{[^}}]*\}}'
    
    # For simple one-liner or short methods, use a more targeted approach
    # Find the start of the method
    start_patterns = [
        rf'\n    @MainActor\n    private func {method_name}\(',
        rf'\n    private func {method_name}\('
    ]
    
    for start_pat in start_patterns:
        match = re.search(start_pat, content)
        if match:
            start_idx = match.start()
            # Find matching closing brace by counting braces
            brace_count = 0
            in_method = False
            end_idx = start_idx
            
            for i, char in enumerate(content[start_idx:], start_idx):
                if char == '{':
                    brace_count += 1
                    in_method = True
                elif char == '}':
                    brace_count -= 1
                    if in_method and brace_count == 0:
                        end_idx = i + 1
                        break
            
            if end_idx > start_idx:
                # Remove the method
                removed = content[start_idx:end_idx]
                print(f"Removing {method_name}: {len(removed)} chars")
                content = content[:start_idx] + content[end_idx:]
                return content
    
    return content

# Remove duplicate method definitions
for method in methods_to_remove:
    content = remove_method(content, method)

# Now update method calls to use securityVM prefix
# But avoid replacing already-prefixed calls
call_replacements = [
    (r'(?<!securityVM\.)handlePasscodeChange\(\)', 'securityVM.handlePasscodeChange()'),
    (r'(?<!securityVM\.)(?<![a-zA-Z_])lock\(\)', 'securityVM.lock()'),
    (r'(?<!securityVM\.)recordActivity\(\)', 'securityVM.recordActivity()'),
    (r'(?<!securityVM\.)scheduleAutoLockCountdown\(\)', 'securityVM.scheduleAutoLockCountdown()'),
    (r'(?<!securityVM\.)startActivityMonitoringIfNeeded\(\)', 'securityVM.startActivityMonitoringIfNeeded()'),
    (r'(?<!securityVM\.)stopActivityMonitoring\(\)', 'securityVM.stopActivityMonitoring()'),
    (r'(?<!securityVM\.)refreshBiometricAvailability\(\)', 'securityVM.refreshBiometricAvailability()'),
    (r'(?<!securityVM\.)attemptBiometricUnlock\(', 'securityVM.attemptBiometricUnlock('),
    (r'(?<!securityVM\.)hashPasscode\(', 'securityVM.hashPasscode('),
]

for pattern, replacement in call_replacements:
    count = len(re.findall(pattern, content))
    if count > 0:
        print(f"Replacing {count} calls: {pattern[:30]}...")
        content = re.sub(pattern, replacement, content)

with open(contentview_path, 'w') as f:
    f.write(content)

print(f"\nUpdated {contentview_path}")
