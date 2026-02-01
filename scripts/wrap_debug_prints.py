#!/usr/bin/env python3
"""
Wrap Swift print statements in #if DEBUG blocks for production safety.
Only affects print statements that contain bracketed tags like [SendView], [ETH TX], etc.
Skips prints that are already inside #if DEBUG blocks.
"""

import os
import re
import sys

def is_inside_debug_block(lines, current_idx):
    """Check if current line is already inside an #if DEBUG block"""
    depth = 0
    for i in range(current_idx - 1, -1, -1):
        line = lines[i].strip()
        if line == '#endif':
            depth += 1
        elif line.startswith('#if DEBUG') or line == '#if DEBUG':
            if depth == 0:
                return True
            depth -= 1
        elif line.startswith('#if ') and not line.startswith('#if DEBUG'):
            if depth == 0:
                return False
    return False

def process_file(filepath):
    """Process a Swift file to wrap tagged prints in #if DEBUG"""
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    lines = content.split('\n')
    modified = False
    result = []
    i = 0
    
    # Pattern for print statements with tags like [SendView], [ETH TX], etc.
    tagged_print_pattern = re.compile(r'^(\s*)print\(\s*"?\[')
    
    while i < len(lines):
        line = lines[i]
        
        # Check if this is a tagged print statement
        match = tagged_print_pattern.match(line)
        if match:
            indent = match.group(1)
            
            # Skip if already inside DEBUG block
            if is_inside_debug_block(result + [line], len(result)):
                result.append(line)
                i += 1
                continue
            
            # Collect multi-line print statements
            print_lines = [line]
            paren_count = line.count('(') - line.count(')')
            
            while paren_count > 0 and i + 1 < len(lines):
                i += 1
                print_lines.append(lines[i])
                paren_count += lines[i].count('(') - lines[i].count(')')
            
            # Wrap in #if DEBUG
            result.append(f'{indent}#if DEBUG')
            result.extend(print_lines)
            result.append(f'{indent}#endif')
            modified = True
        else:
            result.append(line)
        
        i += 1
    
    if modified:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write('\n'.join(result))
        return True
    return False

def main():
    """Main entry point"""
    swift_app_dir = '/Users/x/Desktop/888/swift-app/Sources'
    
    # Files to process (high-priority ones with sensitive debug info)
    priority_files = [
        'swift-app/Views/SendView.swift',
        'swift-app/Services/TransactionBroadcaster.swift',
        'swift-app/Services/RustCLIBridge.swift',
        'swift-app/Services/EVMNonceManager.swift',
        'swift-app/Services/FeeEstimationService.swift',
    ]
    
    modified_count = 0
    
    for relative_path in priority_files:
        filepath = os.path.join(swift_app_dir, relative_path)
        if os.path.exists(filepath):
            if process_file(filepath):
                print(f"✅ Modified: {relative_path}")
                modified_count += 1
            else:
                print(f"⏭️  Skipped (no changes): {relative_path}")
        else:
            print(f"❌ Not found: {filepath}")
    
    print(f"\n📊 Total files modified: {modified_count}")

if __name__ == '__main__':
    main()
