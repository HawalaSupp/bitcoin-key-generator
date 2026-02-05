#!/usr/bin/env python3
"""
Phase 6b: Remove duplicate balance methods from ContentView
These methods are now in BalanceService
"""
import re

contentview_path = "/Users/x/Desktop/888/swift-app/Sources/swift-app/ContentView.swift"

with open(contentview_path, 'r') as f:
    lines = f.readlines()

# Methods to remove (they're now in BalanceService)
methods_to_remove = [
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
]

content = ''.join(lines)

def remove_method(content, method_name):
    """Remove a method definition by finding matching braces"""
    # Pattern to find function start
    patterns = [
        rf'\n    @MainActor\n    private func {method_name}\(',
        rf'\n    private func {method_name}\('
    ]
    
    for start_pat in patterns:
        match = re.search(start_pat, content)
        if match:
            start_idx = match.start()
            # Find matching closing brace
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
                removed_len = end_idx - start_idx
                print(f"Removing {method_name}: {removed_len} chars")
                content = content[:start_idx] + content[end_idx:]
                return content
    
    return content

removed_count = 0
for method in methods_to_remove:
    old_len = len(content)
    content = remove_method(content, method)
    if len(content) < old_len:
        removed_count += 1

with open(contentview_path, 'w') as f:
    f.write(content)

print(f"\nRemoved {removed_count} methods from ContentView")
