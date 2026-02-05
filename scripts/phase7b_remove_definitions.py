#!/usr/bin/env python3
"""
Phase 7b: Remove balance method DEFINITIONS from ContentView
They're now used via balanceService
"""

contentview_path = "/Users/x/Desktop/888/swift-app/Sources/swift-app/ContentView.swift"

with open(contentview_path, 'r') as f:
    lines = f.readlines()

# Methods to remove - these are the function definitions
methods_to_remove = [
    'startBalanceFetch',
    'startEthereumAndTokenBalanceFetch',
    'scheduleBalanceFetch',
    'cancelBalanceFetchTasks',
    'launchBalanceFetchTask',
    'runBalanceFetchLoop',
    'applyLoadingState',
    'performBalanceFetch',
    'friendlyBackoffMessage',
    'formatRetryDuration',
    'fetchBitcoinBalance',
    'fetchLitecoinBalance',
    'fetchSolanaBalance',
    'fetchXrpBalance',
    'fetchXrpBalanceViaRippleDataAPI',
    'fetchXrpBalanceViaRippleRPC',
    'requestXrpBalance',
    'fetchXrpBalanceViaXrpScan',
    'xrplAccountInfoPayload',
    'xrplResponseIndicatesUnfundedAccount',
    'fetchBnbBalance',
    'fetchEthereumBalanceViaInfura',
    'fetchEthereumBalanceViaAlchemy',
    'fetchEthereumBalanceViaBlockchair',
    'fetchERC20Balance',
    'fetchERC20BalanceViaAlchemy',
    'fetchERC20BalanceViaBlockchair',
    'fetchEthplorerAccount',
    'tokenBalance',
    'decimalFromHex',
    'decimalDividingByPowerOfTen',
    'normalizeAddressForCall',
    'fetchEthereumBalance',
    'fetchEthereumSepoliaBalance',
    'formatCryptoAmount',
    'extractNumericAmount',
]

content = ''.join(lines)
original_lines = len(lines)

def remove_method_definition(content, method_name):
    """
    Remove a method definition by finding:
    1. The function signature line
    2. Following open braces until we match the closing brace
    """
    import re
    
    # Find "@MainActor\n    private func methodName(" or "    private func methodName("
    patterns = [
        rf'\n    @MainActor\n    private func {method_name}\([^)]*\)',
        rf'\n    private func {method_name}\([^)]*\)',
    ]
    
    for pattern in patterns:
        match = re.search(pattern, content)
        if match:
            start_idx = match.start()
            
            # Find the opening brace
            brace_start = content.find('{', match.end())
            if brace_start == -1:
                continue
                
            # Count braces to find matching close
            brace_count = 1
            i = brace_start + 1
            while i < len(content) and brace_count > 0:
                if content[i] == '{':
                    brace_count += 1
                elif content[i] == '}':
                    brace_count -= 1
                i += 1
            
            if brace_count == 0:
                end_idx = i
                removed_content = content[start_idx:end_idx]
                removed_lines = removed_content.count('\n')
                print(f"Removing {method_name}: {removed_lines} lines")
                content = content[:start_idx] + content[end_idx:]
                return content
    
    return content

# Remove each method
for method in methods_to_remove:
    content = remove_method_definition(content, method)

with open(contentview_path, 'w') as f:
    f.write(content)

new_lines = content.count('\n') + 1
print(f"\nRemoved {original_lines - new_lines} lines")
print(f"ContentView.swift: {original_lines} → {new_lines} lines")
