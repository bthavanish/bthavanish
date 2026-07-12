#!/usr/bin/env python3
"""
patch_hiddenapi.py - Fix soong hiddenapi ninja bug

The bug: in out/soong/build.lineage_a12s.ninja, the hiddenapi
annotation-flags and metadata rules list all jars as order-only deps (|),
so ${in} expands empty and class2nonsdklist gets no jar files.

The fix: copy the jars from the stub-flags build block into the
annotation-flags/metadata build blocks as regular inputs (before |).
"""
import sys
import os

SOONG_NINJA = "out/soong/build.lineage_a12s.ninja"

if not os.path.exists(SOONG_NINJA):
    print(f"ERROR: {SOONG_NINJA} not found")
    sys.exit(1)

with open(SOONG_NINJA, 'r') as f:
    lines = f.readlines()

# Step 1: Find hiddenapi-stub-flags.txt build blocks and extract jars
stub_blocks = []
i = 0
while i < len(lines):
    line = lines[i]
    if 'hiddenapi-stub-flags.txt' in line and line.strip().startswith('build '):
        build_start = i
        j = i + 1
        jars = []
        in_pipe = False
        while j < len(lines):
            l = lines[j].rstrip()
            if l.endswith(' $'):
                dep = l.rstrip(' $').strip()
                if '| $' in l:
                    in_pipe = True
                    j += 1
                    continue
                if in_pipe and dep.endswith('.jar'):
                    jars.append(dep)
                j += 1
            else:
                break
        stub_blocks.append((build_start, j, jars))
        i = j
    else:
        i += 1

# Step 2: Find broken g.java.hiddenAPIGenerateCSV rules (pipe before all deps)
broken_rules = []
i = 0
while i < len(lines):
    line = lines[i]
    if 'g.java.hiddenAPIGenerateCSV |' in line:
        # Walk back to 'build $'
        build_start = i
        while build_start > 0 and lines[build_start - 1].rstrip().endswith(' $'):
            build_start -= 1
        # Walk forward to end of build block
        j = i + 1
        while j < len(lines):
            l = lines[j].rstrip()
            if l.endswith(' $'):
                j += 1
            elif l.startswith('    ') and not any(l.strip().startswith(p)
                    for p in ['description', 'tags', 'outFlag', 'stubAPIFlags']):
                j += 1
            else:
                break
        broken_rules.append((build_start, j, i))
        i = j
    else:
        i += 1

if not broken_rules:
    print("No broken rules found - nothing to patch")
    sys.exit(0)

print(f"Found {len(broken_rules)} broken rules, {len(stub_blocks)} stub-flags blocks")

# Step 3: Patch each broken rule
for rule_start, rule_end, pipe_line in reversed(broken_rules):
    # Find the stub-flags block closest above this rule
    best_jars = []
    for sb_start, sb_end, jars in stub_blocks:
        if sb_end <= rule_start:
            best_jars = jars
            break

    if not best_jars:
        print(f"  SKIP: no jars for rule at line {pipe_line + 1}")
        continue

    new_lines = []
    # "build $"
    new_lines.append(lines[rule_start])
    # "    <output>: $"
    new_lines.append(lines[rule_start + 1])
    # "        g.java.hiddenAPIGenerateCSV $"
    new_lines.append("        g.java.hiddenAPIGenerateCSV $\n")
    # Add jars as regular inputs (before |)
    for jar in best_jars:
        new_lines.append(f"        {jar} $\n")
    # "        | $"
    new_lines.append("        | $\n")
    # "        out/soong/hiddenapi/hiddenapi-stub-flags.txt $"
    new_lines.append("        out/soong/hiddenapi/hiddenapi-stub-flags.txt $\n")
    # "        ${g.android.soong.java.config.Class2NonSdkList}"
    new_lines.append("        ${g.android.soong.java.config.Class2NonSdkList}\n")

    # Copy remaining lines (description, tags, outFlag, stubAPIFlags)
    for k in range(pipe_line + 1, rule_end):
        l = lines[k]
        # Skip lines we already added
        if 'hiddenapi-stub-flags.txt' in l and 'outFlag' not in l and 'stubAPIFlags' not in l:
            continue
        if 'Class2NonSdkList' in l:
            continue
        if 'g.java.hiddenAPIGenerateCSV' in l:
            continue
        new_lines.append(l)

    lines[rule_start:rule_end] = new_lines
    print(f"  PATCHED: rule at line {pipe_line + 1} ({len(best_jars)} jars added)")

# Write patched file
with open(SOONG_NINJA, 'w') as f:
    f.writelines(lines)

# Verify
with open(SOONG_NINJA, 'r') as f:
    content = f.read()
remaining = content.count('g.java.hiddenAPIGenerateCSV |')
print(f"\nResult: {remaining} broken rules remaining")
