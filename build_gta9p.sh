#!/bin/bash
# LineageOS 23.2 Build for Samsung Galaxy Tab A9+ (gta9p / SM-X216B)
# Unsupported ROM method for crave.io
#
# Setup (one time):
#   crave clone list                                  # find "LOS 21" project ID
#   crave clone create --projectID <ID> /crave-devspaces/Lineage-gta9p
#
# Build:
#   cd /crave-devspaces/Lineage-gta9p
#   crave run --no-patch -- "bash build_gta9p.sh"

set -e

echo "=== LineageOS 23.2 Build for Samsung Galaxy Tab A9+ ==="
echo "Start: $(date)"

# Reinit to LineageOS 23.2
rm -rf .repo/local_manifests
repo init -u https://github.com/LineageOS/android.git \
    -b lineage-23.2 \
    --git-lfs

# Add our device repos as local manifests
mkdir -p .repo/local_manifests
cat > .repo/local_manifests/gta9p.xml << 'EOF'
<manifest>
    <project name="bthavanish/android_kernel_samsung_sm6375"
             path="kernel/samsung/sm6375"
             remote="github"
             revision="lineage-22.1" />
    <project name="bthavanish/android_device_samsung_gta9p-common"
             path="device/samsung/gta9p-common"
             remote="github"
             revision="lineage-23.2" />
    <project name="bthavanish/android_device_samsung_gta9p"
             path="device/samsung/gta9p"
             remote="github"
             revision="lineage-23.2" />
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

# Sync using crave's resync
/opt/crave/resync.sh

# Build
source build/envsetup.sh
lunch lineage_gta9p-userdebug
mka bacon

echo "=== Build Complete: $(date) ==="
ls -la out/target/product/gta9p/*.zip 2>/dev/null || echo "No zip found"
