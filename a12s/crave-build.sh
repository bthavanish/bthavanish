#!/bin/bash
# Crave.io build script
# Upload a12s/ directory to Crave and run this

set -euo pipefail

echo "=== LineageOS 21 for Samsung Galaxy A12s ==="
echo "Build started at $(date)"

# The crave build environment already has deps
# Just need to init repo and build
cd ~/lineage-a12s 2>/dev/null || {
    mkdir -p ~/lineage-a12s
    cd ~/lineage-a12s
    repo init -u https://github.com/LineageOS/android.git -b lineage-21 --git-lfs
}

# Apply patches
bash -c "$(curl -fsSL https://raw.githubusercontent.com/bthavanish/bthavanish/main/a12s/aws-build.sh)" || true

# Build
source build/envsetup.sh
lunch lineage_a12s-ap2a-userdebug

# Fix hiddenapi and build
m --skip-soong-tests nothing
python3 patch_hiddenapi.py 2>/dev/null || true
sed -i 's|(ln -f  out/target/product/a12s/lineage-21.0-20260712-UNOFFICIAL-a12s.zip )|(true )|' out/build-lineage_a12s.ninja 2>/dev/null || true

prebuilts/build-tools/linux-x86/bin/ninja -f out/combined-lineage_a12s.ninja -j$(nproc) bacon

echo "Build finished at $(date)"
ls -lh out/target/product/a12s/*.zip 2>/dev/null
