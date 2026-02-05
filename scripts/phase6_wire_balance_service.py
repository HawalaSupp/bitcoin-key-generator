#!/usr/bin/env python3
"""
Phase 6: Wire BalanceService and remove duplicate balance methods from ContentView
"""
import re

contentview_path = "/Users/x/Desktop/888/swift-app/Sources/swift-app/ContentView.swift"

with open(contentview_path, 'r') as f:
    content = f.read()

# 1. Add BalanceService StateObject after walletVM
content = content.replace(
    '@StateObject private var walletVM = WalletViewModel()',
    '@StateObject private var walletVM = WalletViewModel()\n    @StateObject private var balanceService = BalanceService.shared'
)

# 2. Remove duplicate @State declarations for balance-related properties
state_declarations_to_remove = [
    r'@State private var balanceStates: \[String: ChainBalanceState\] = \[:\]\n\s*',
    r'@State private var cachedBalances: \[String: CachedBalance\] = \[:\]\n\s*',
    r'@State private var balanceBackoff: \[String: BackoffTracker\] = \[:\]\n\s*',
    r'@State private var balanceFetchTasks: \[String: Task<Void, Never>\] = \[:\]\n\s*',
]

for pattern in state_declarations_to_remove:
    content = re.sub(pattern, '', content)

# 3. Replace direct state accesses with balanceService
replacements = [
    # Balance states
    (r'(?<!balanceService\.)balanceStates\[', 'balanceService.balanceStates['),
    (r'(?<!balanceService\.)balanceStates\.', 'balanceService.balanceStates.'),
    (r'\$balanceStates', '$balanceService.balanceStates'),
    
    # Cached balances
    (r'(?<!balanceService\.)cachedBalances\[', 'balanceService.cachedBalances['),
    (r'(?<!balanceService\.)cachedBalances\.', 'balanceService.cachedBalances.'),
    
    # Balance backoff
    (r'(?<!balanceService\.)balanceBackoff\[', 'balanceService.balanceBackoff['),
    (r'(?<!balanceService\.)balanceBackoff\.', 'balanceService.balanceBackoff.'),
    
    # Balance fetch tasks
    (r'(?<!balanceService\.)balanceFetchTasks\[', 'balanceService.balanceFetchTasks['),
    (r'(?<!balanceService\.)balanceFetchTasks\.', 'balanceService.balanceFetchTasks.'),
    
    # Method calls
    (r'startBalanceFetch\(for:', 'balanceService.startBalanceFetch(for:'),
    (r'startEthereumAndTokenBalanceFetch\(', 'balanceService.startEthereumAndTokenBalanceFetch('),
    (r'cancelBalanceFetchTasks\(\)', 'balanceService.cancelBalanceFetchTasks()'),
    (r'refreshAllBalances\(\)', 'balanceService.refreshAllBalances(keys: keys!)'),
    (r'extractNumericAmount\(from:', 'balanceService.extractNumericAmount(from:'),
    (r'formatCryptoAmount\(', 'balanceService.formatCryptoAmount('),
]

for pattern, replacement in replacements:
    content = re.sub(pattern, replacement, content)

with open(contentview_path, 'w') as f:
    f.write(content)

print("Updated ContentView to use BalanceService")
print("Next step: Remove the balance-related method implementations from ContentView")
