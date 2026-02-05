#!/usr/bin/env python3
"""
Phase 7: Wire BalanceService - careful approach
1. Update method calls to use balanceService.
2. Remove function definitions
"""
import re

contentview_path = "/Users/x/Desktop/888/swift-app/Sources/swift-app/ContentView.swift"

with open(contentview_path, 'r') as f:
    content = f.read()

original_len = len(content)

# Balance methods that exist in BalanceService and need their CALLS updated
# We only replace calls INSIDE function bodies, not the function definitions themselves
balance_methods = [
    'fetchBitcoinBalance',
    'fetchLitecoinBalance',
    'fetchSolanaBalance',
    'fetchXrpBalance',
    'fetchXrpBalanceViaRippleDataAPI',
    'fetchXrpBalanceViaRippleRPC',
    'requestXrpBalance',
    'fetchXrpBalanceViaXrpScan',
    'fetchBnbBalance',
    'fetchEthereumBalanceViaInfura',
    'fetchEthereumBalanceViaAlchemy',
    'fetchEthereumBalanceViaBlockchair',
    'fetchERC20Balance',
    'fetchERC20BalanceViaAlchemy',
    'fetchERC20BalanceViaBlockchair',
    'fetchEthplorerAccount',
    'fetchEthereumBalance',
    'fetchEthereumSepoliaBalance',
    'formatCryptoAmount',
]

# Replace method calls (but not function definitions)
# Pattern: "try await methodName(" or just "methodName(" at start of expression
for method in balance_methods:
    # Replace "try await methodName(" with "try await balanceService.methodName("
    pattern = rf'try await (?!balanceService\.){method}\('
    replacement = f'try await balanceService.{method}('
    content = re.sub(pattern, replacement, content)
    
    # Replace "return methodName(" with "return balanceService.methodName("
    pattern = rf'return (?!balanceService\.){method}\('
    replacement = f'return balanceService.{method}('
    content = re.sub(pattern, replacement, content)

# Replace startBalanceFetch and startEthereumAndTokenBalanceFetch calls
content = re.sub(r'(?<!\.)startBalanceFetch\(for:', 'balanceService.startBalanceFetch(for:', content)
content = re.sub(r'(?<!\.)startEthereumAndTokenBalanceFetch\(', 'balanceService.startEthereumAndTokenBalanceFetch(', content)

# Replace scheduleBalanceFetch calls
content = re.sub(r'(?<!\.)scheduleBalanceFetch\(for:', 'balanceService.scheduleBalanceFetch(for:', content)

# Replace cancelBalanceFetchTasks calls
content = re.sub(r'(?<!\.)cancelBalanceFetchTasks\(\)', 'balanceService.cancelBalanceFetchTasks()', content)

# Replace applyLoadingState calls
content = re.sub(r'(?<![\.a-zA-Z_])applyLoadingState\(for:', 'balanceService.applyLoadingState(for:', content)

# Replace extractNumericAmount calls
content = re.sub(r'(?<![\.a-zA-Z_])extractNumericAmount\(from:', 'balanceService.extractNumericAmount(from:', content)

with open(contentview_path, 'w') as f:
    f.write(content)

new_len = len(content)
print(f"Updated method calls. Content changed by {original_len - new_len} chars")
print("Next: Run phase7b to remove function definitions")
