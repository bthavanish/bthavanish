#!/bin/bash
# LineageOS 23.2 Build Script for Samsung Galaxy Tab A9+ (gta9p / SM-X216B)
# Designed for crave.io
#
# Usage:
#   crave run --no-patch --clean "bash build_gta9p.sh"
#
# Or upload to GitHub and:
#   crave run --no-patch --clean "git clone https://github.com/bthavanish/build_scripts && bash build_scripts/build_gta9p.sh"

set -e

echo "=== LineageOS 23.2 Build for Samsung Galaxy Tab A9+ ==="
echo "Start: $(date)"

# -----------------------------------------------
# Step 1: Initialize LineageOS 23.2 repo
# -----------------------------------------------
echo "[1/6] Initializing LineageOS repo..."
rm -rf .repo/local_manifests
repo init -u https://github.com/LineageOS/android.git \
    -b lineage-23.2 \
    --git-lfs \
    --depth=1

# -----------------------------------------------
# Step 2: Create local manifests for our repos
# -----------------------------------------------
echo "[2/6] Creating local manifests..."
mkdir -p .repo/local_manifests

cat > .repo/local_manifests/gta9p.xml << 'EOF'
<manifest>
    <!-- Kernel -->
    <project name="bthavanish/android_kernel_samsung_sm6375"
             path="kernel/samsung/sm6375"
             remote="github"
             revision="lineage-22.1" />

    <!-- Device trees -->
    <project name="bthavanish/android_device_samsung_gta9p-common"
             path="device/samsung/gta9p-common"
             remote="github"
             revision="lineage-23.2" />

    <project name="bthavanish/android_device_samsung_gta9p"
             path="device/samsung/gta9p"
             remote="github"
             revision="lineage-23.2" />

    <!-- Vendor blobs -->
    <project name="bthavanish/android_vendor_samsung_gta9p-common"
             path="vendor/samsung/gta9p-common"
             remote="github"
             revision="lineage-23.2" />

    <project name="bthavanish/android_vendor_samsung_gta9p"
             path="vendor/samsung/gta9p"
             remote="github"
             revision="lineage-23.2" />
</manifest>
EOF

# -----------------------------------------------
# Step 3: Sync sources
# -----------------------------------------------
echo "[3/6] Syncing sources (this takes a while)..."
/opt/crave/resync.sh

# -----------------------------------------------
# Step 4: Fix kernel repo if shallow clone issues
# -----------------------------------------------
echo "[4/6] Verifying kernel..."
if [ ! -f "kernel/samsung/sm6375/Makefile" ]; then
    echo "Kernel missing, re-cloning..."
    rm -rf kernel/samsung/sm6375
    git clone --depth=1 -b lineage-22.1 \
        https://github.com/bthavanish/android_kernel_samsung_sm6375.git \
        kernel/samsung/sm6375
fi

# -----------------------------------------------
# Step 5: Setup build environment
# -----------------------------------------------
echo "[5/6] Setting up build environment..."
source build/envsetup.sh

# Lunch target: lineage_gta9p-userdebug
# (product name from lineage_gta9p.mk: PRODUCT_NAME := lineage_gta9p)
lunch lineage_gta9p-userdebug

# -----------------------------------------------
# Step 6: Build
# -----------------------------------------------
echo "[6/6] Starting build..."
echo "Build started: $(date)"

# Build the ROM (use mka for parallel builds)
mka bacon

echo "=== Build Complete ==="
echo "End: $(date)"
echo "Output: out/target/product/gta9p/"

# List the output
ls -la out/target/product/gta9p/*.zip 2>/dev/null || echo "No zip found, check build log"
