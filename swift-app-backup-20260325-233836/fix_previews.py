#!/usr/bin/env python3
import os

def fix_preview(content):
    lines = content.split('\n')
    result = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.strip().startswith('#Preview'):
            result.append('#if false')
            brace_count = 0
            started = False
            while i < len(lines):
                result.append(lines[i])
                brace_count += lines[i].count('{') - lines[i].count('}')
                if '{' in lines[i]:
                    started = True
                if started and brace_count == 0:
                    break
                i += 1
            result.append('#endif')
        else:
            result.append(line)
        i += 1
    return '\n'.join(result)

def main():
    root_dir = 'Sources/swift-app'
    for root, dirs, files in os.walk(root_dir):
        for f in files:
            if f.endswith('.swift'):
                path = os.path.join(root, f)
                with open(path, 'r') as file:
                    content = file.read()
                if '#Preview' in content:
                    fixed = fix_preview(content)
                    with open(path, 'w') as file:
                        file.write(fixed)
                    print('Fixed:', path)

if __name__ == '__main__':
    main()
