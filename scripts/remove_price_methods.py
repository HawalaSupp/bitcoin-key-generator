#!/usr/bin/env python3
import sys

with open('/Users/x/Desktop/888/swift-app/Sources/swift-app/ContentView.swift', 'r') as f:
    lines = f.readlines()

# Find start: The @MainActor line before startPriceUpdatesIfNeeded
# Find end: The line before @MainActor for handleScenePhase

start_line = None
end_line = None

for i, line in enumerate(lines):
    if 'private func startPriceUpdatesIfNeeded()' in line and i > 2600:
        # Start at the @MainActor line (2 lines before)
        start_line = i - 1  # @MainActor is one line before
        break

for i in range(len(lines)-1, 2600, -1):
    if 'private func handleScenePhase(_ phase: ScenePhase)' in lines[i]:
        # End at the line before the @MainActor for handleScenePhase
        # Go back to find the @MainActor
        for j in range(i-1, i-5, -1):
            if '@MainActor' in lines[j]:
                end_line = j - 1  # Line before @MainActor
                break
        break

if start_line is None or end_line is None:
    print(f"Could not find block: start={start_line}, end={end_line}")
    sys.exit(1)

print(f"Removing lines {start_line+1} to {end_line+1} (1-indexed)")
print(f"Total lines to remove: {end_line - start_line + 1}")

# Build new content
new_lines = lines[:start_line] + ['\n'] + lines[end_line+1:]

print(f"Original: {len(lines)} lines")
print(f"New: {len(new_lines)} lines")

with open('/Users/x/Desktop/888/swift-app/Sources/swift-app/ContentView.swift', 'w') as f:
    f.writelines(new_lines)

print("Done!")
