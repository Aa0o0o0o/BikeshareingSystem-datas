"""Clean decorative comments and blank lines from main_demo.m.
Run after major edits to ensure minimal academic-style formatting.
"""
import re

with open('main_demo.m', 'r') as f:
    lines = f.readlines()

out = []
i = 0
while i < len(lines):
    s = lines[i].rstrip('\n')
    if re.match(r'^\s*%%\s*={5,}', s) or re.match(r'^\s*%{5,}', s):
        i += 1
        continue
    if re.match(r"^\s*fprintf\('=+", s):
        i += 1
        continue
    out.append(s + '\n')
    i += 1

final = []
prev_empty = False
for line in out:
    if line.strip() == '':
        if not prev_empty:
            final.append(line)
        prev_empty = True
    else:
        final.append(line)
        prev_empty = False

with open('main_demo.m', 'w') as f:
    f.writelines(final)

print('Done cleaning main_demo.m')
