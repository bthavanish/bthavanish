#!/bin/bash
# LineageOS 23.2 Build Script for Samsung Galaxy Tab A9+ (gta9p / SM-X216B)
# Designed for crave.io (unsupported ROM method)
#
# Prerequisites:
#   1. Install crave CLI: https://fosson.top/crave/getting-started/installing-crave.html
#   2. Create a LineageOS project:
#      crave clone list                          # find LineageOS project ID
#      crave clone create --projectID <ID> /crave-devspaces/Lineage-gta9p
#      cd /crave-devspaces/Lineage-gta9p
#
# Usage (from the project folder):
#   crave run --no-patch -- "bash /path/to/build_gta9p.sh"
#
# Or paste the commands directly into crave run.

set -e

echo "=== LineageOS 23.2 Build for Samsung Galaxy Tab A9+ ==="
echo "Start: $(date)"

# -----------------------------------------------
# Step 1: Reinit with LineageOS 23.2 manifest
# -----------------------------------------------
echo "[1/6] Reinitializing LineageOS repo..."
rm -rf .repo/local_manifests
repo init -u https://github.com/LineageOS/android.git \
    -b lineage-23.2 \
    --git-lfs

# -----------------------------------------------
# Step 2: Create local manifests for device trees
# -----------------------------------------------
echo "[2/6] Creating local manifests..."
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
# Step 3: Sync using resync.sh (required by crave rules)
# -----------------------------------------------
echo "[3/6] Syncing sources..."
/opt/crave/resync.sh

# -----------------------------------------------
# Step 4: Setup build environment
# -----------------------------------------------
echo "[4/6] Setting up build environment..."
source build/envsetup.sh

# -----------------------------------------------
# Step 5: Lunch target
# -----------------------------------------------
echo "[5/6] Selecting lunch target..."
lunch lineage_gta9p-userdebug

# -----------------------------------------------
# Step 6: Build
# -----------------------------------------------
echo "[6/6] Starting build..."
echo "Build started: $(date)"
mka bacon

echo "=== Build Complete ==="
echo "End: $(date)"
echo "Output: out/target/product/gta9p/"
ls -la out/target/product/gta9p/*.zip 2>/dev/null || echo "No zip found, check build log"
