#!/bin/bash
# build_a12s.sh - One-shot build script for LineageOS 21 on Samsung Galaxy A12s
#
# Usage:
#   source build/envsetup.sh
#   lunch lineage_a12s-ap2a-userdebug
#   bash build_a12s.sh
#
# What it fixes:
# 1. hiddenapi: soong puts jars as order-only deps, so ${in} expands empty
#    -> patch_hiddenapi.py moves jars to regular inputs
# 2. hiddenapi-flags.csv: generate_hiddenapi_lists crashes on assertion
#    -> patched generate_hiddenapi_lists.py to warn instead of crash
# 3. Zip rule: ln -f hardlinks cross-device
#    -> replaced with no-op (zip built by droid target)

set -e
cd ~/lineage-a12s

NINJA_BIN="prebuilts/build-tools/linux-x86/bin/ninja"
COMBINED_NINJA="out/combined-lineage_a12s.ninja"
BUILD_NINJA="out/build-lineage_a12s.ninja"

echo "=== Step 1: Patch hiddenapi ninja rules ==="
python3 patch_hiddenapi.py

echo ""
echo "=== Step 2: Fix broken zip rule in build ninja ==="
# The zip rule does: ln -f <zip> which hardlinks to itself (cross-device fail)
sed -i 's|(ln -f  out/target/product/a12s/lineage-21.0-20260712-UNOFFICIAL-a12s.zip )|(true )|' "$BUILD_NINJA"
echo "Done"

echo ""
echo "=== Step 3: Run bacon build ==="
$NINJA_BIN -f "$COMBINED_NINJA" -j$(nproc) bacon 2>&1 | tail -40
