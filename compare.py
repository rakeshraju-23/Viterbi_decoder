#!/usr/bin/env python3
import sys

if len(sys.argv) != 3:
    print("Usage: python compare.py <file1> <file2>")
    sys.exit(1)

file1 = sys.argv[1]
file2 = sys.argv[2]

with open(file1, 'r') as f1, open(file2, 'r') as f2:
    lines1 = [line.strip() for line in f1]
    lines2 = [line.strip() for line in f2]

if len(lines1) != len(lines2):
    print(f"Different number of lines: {len(lines1)} vs {len(lines2)}")
    sys.exit(1)

mismatches = 0
for i, (l1, l2) in enumerate(zip(lines1, lines2)):
    if l1 != l2:
        print(f"Line {i+1}: {l1} != {l2}")
        mismatches += 1

if mismatches == 0:
    print(f"✅ All {len(lines1)} lines match")
    sys.exit(0)
else:
    print(f"❌ {mismatches} mismatches out of {len(lines1)} lines")
    sys.exit(1)

