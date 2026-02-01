#!/usr/bin/env python3
"""Remove duplicated model code from ContentView.swift"""

import os

# Read the file
filepath = 'swift-app/Sources/swift-app/ContentView.swift'
with open(filepath, 'r') as f:
    lines = f.readlines()

print(f"Original lines: {len(lines)}")

# We need to remove:
# Lines 5877-5989 - Bitcoin Transaction Types to just before SendAssetPickerSheet
# Lines 11213-13333 - ChainInfo through KeyGeneratorError (after adjustment for first removal)
# But since we're removing the first block, the second block shifts down by 113 lines
# So we need to account for this

# Actually, let's do it in one pass using original line numbers
# and just mark which lines to keep

keep_lines = []
for i, line in enumerate(lines):
    line_num = i + 1  # 1-indexed
    
    # Skip the first range (Bitcoin Transaction Types through before SendAssetPickerSheet)
    if 5877 <= line_num <= 5989:
        continue
    
    # Skip the second range (ChainInfo through KeyGeneratorError ending brace)
    if 11213 <= line_num <= 13333:
        continue
    
    keep_lines.append(line)

print(f"New lines: {len(keep_lines)}")
print(f"Removed: {len(lines) - len(keep_lines)} lines")

# Write back
with open(filepath, 'w') as f:
    f.writelines(keep_lines)

print("File updated successfully")
