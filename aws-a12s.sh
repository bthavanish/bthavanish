#!/bin/bash
set -e

DEVICE="a12s"
LINEAGE_BRANCH="lineage-21.0"
LINEAGE_BRANCH_2="lineage-21"
BUILD_DIR="$HOME/lineage-a12s"
LUNCH_TARGET="lineage_${DEVICE}-userdebug"

export KERNEL_DEFCONFIG="exynos850-a12snsxx_defconfig"
export TARGET_SOC="exynos850"

step() {
    echo
    echo "╔════════════════════════════════════════╗"
    echo "║ $1"
    echo "╚════════════════════════════════════════╝"
    echo
}

step "1/7  Installing build packages"

sudo apt update
sudo apt install -y \
    bc bison build-essential ccache curl flex g++-multilib gcc-multilib \
    git git-lfs gnupg gperf lib32readline-dev lib32z1-dev libdw-dev \
    libelf-dev liblz4-tool libncurses-dev lib32ncurses-dev libssl-dev \
    libxml2-utils lz4 lzop openjdk-17-jdk pngcrush protobuf-compiler \
    python3 python3-protobuf rsync schedtool squashfs-tools xsltproc zip \
    zlib1g-dev

step "2/7  Installing repo"

mkdir -p "$HOME/.bin"
if [ ! -f "$HOME/.bin/repo" ]; then
    curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o "$HOME/.bin/repo"
    chmod +x "$HOME/.bin/repo"
fi
export PATH="$HOME/.bin:$PATH"

step "3/7  Setting git identity"

git config --global user.name "bthavanish"
git config --global user.email "bthavanish@gmail.com"
git lfs install

step "4/7  Initializing LineageOS"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [ ! -d .repo ]; then
    repo init -u https://github.com/LineageOS/android.git -b "$LINEAGE_BRANCH" --git-lfs --no-clone-bundle
fi

mkdir -p .repo/local_manifests

cat > .repo/local_manifests/a12s.xml <<EOF
<manifest>
    <project name="bthavanish/android_kernel_samsung_a12s" path="kernel/samsung/a12s" remote="github" revision="$LINEAGE_BRANCH" />
    <project name="bthavanish/android_device_samsung_exynos850-common" path="device/samsung/exynos850-common" remote="github" revision="$LINEAGE_BRANCH" />
    <project name="bthavanish/android_device_samsung_a12s" path="device/samsung/a12s" remote="github" revision="$LINEAGE_BRANCH" />
    <project name="bthavanish/android_vendor_samsung_exynos850-common" path="vendor/samsung/exynos850-common" remote="github" revision="$LINEAGE_BRANCH" />
    <project name="bthavanish/android_vendor_samsung_a12s" path="vendor/samsung/a12s" remote="github" revision="$LINEAGE_BRANCH" />
    <project name="LineageOS/android_hardware_samsung" path="hardware/samsung" remote="github" revision="$LINEAGE_BRANCH_2" />
    <project name="LineageOS/android_hardware_samsung_slsi-linaro_libbt" path="hardware/samsung/slsi/libbt" remote="github" revision="$LINEAGE_BRANCH_2" />
    <project name="LineageOS/android_hardware_samsung_slsi_linaro_libhwjpeg" path="hardware/samsung/slsi/libhwjpeg" remote="github" revision="$LINEAGE_BRANCH_2" />
</manifest>
EOF

step "5/7  Syncing sources"

repo sync -c --force-sync --no-clone-bundle --no-tags -j"$(nproc)"

step "6/7  Preparing build files"

mkdir -p kernel/samsung/a12s/arch/arm64/configs
touch kernel/samsung/a12s/arch/arm64/configs/exynos850_userdebug.cfg

export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache
ccache -M 50G

source build/envsetup.sh
lunch "$LUNCH_TARGET"

step "7/7  Building"

mka bacon -j"$(nproc)"
