#!/bin/bash
# ============================================================
# LineageOS 21 — Samsung Galaxy A12s (SM-A127F/DS)
# Complete AWS build script (Ubuntu 22.04)
#
# Usage:
#   bash a12s/aws-build.sh
#
# Requirements:
#   - Ubuntu 22.04 (AWS c5.4xlarge or similar, 16+ cores)
#   - 30GB+ RAM (or add swap — script handles this)
#   - 300GB+ free disk
# ============================================================
set -euo pipefail

# ── Config ──────────────────────────────────────────────────
DEVICE="a12s"
LINEAGE_BRANCH="lineage-21"
BUILD_DIR="$HOME/lineage-a12s"
LUNCH_TARGET="lineage_${DEVICE}-ap2a-userdebug"
LOGFILE="$HOME/build_a12s_$(date +%Y%m%d_%H%M%S).log"

export KERNEL_DEFCONFIG="exynos850-a12snsxx_defconfig"
export TARGET_SOC="exynos850"
export UNSAFE_DISABLE_HIDDENAPI_FLAGS=true
export ALLOW_MISSING_DEPENDENCIES=true
export READELF=/usr/bin/aarch64-linux-gnu-readelf

# Device repos (bthavanish forks)
REPO_NAMES=(
    "bthavanish/android_kernel_samsung_a12s"
    "bthavanish/android_device_samsung_exynos850-common"
    "bthavanish/android_device_samsung_a12s"
    "bthavanish/android_vendor_samsung_exynos850-common"
    "bthavanish/android_vendor_samsung_a12s"
)
REPO_PATHS=(
    "kernel/samsung/a12s"
    "device/samsung/exynos850-common"
    "device/samsung/a12s"
    "vendor/samsung/exynos850-common"
    "vendor/samsung/a12s"
)

# ── TUI ─────────────────────────────────────────────────────
BOLD='\033[1m' DIM='\033[2m' RESET='\033[0m'
RED='\033[1;31m' GREEN='\033[1;32m' YELLOW='\033[1;33m'
BLUE='\033[1;34m' CYAN='\033[1;36m' WHITE='\033[1;37m'

step()  { echo -e "\n${BLUE}${BOLD}[$1/$2]${RESET} ${WHITE}${BOLD}$3${RESET}\n${DIM}------------------------------------------${RESET}"; }
ok()    { echo -e "  ${GREEN}[OK]${RESET} $1"; }
warn()  { echo -e "  ${YELLOW}[WARN]${RESET} $1"; }
err()   { echo -e "  ${RED}[ERR]${RESET} $1"; }
die()   { err "$1"; echo -e "\n${RED}${BOLD}BUILD FAILED${RESET}\n  Log: ${LOGFILE}"; exit 1; }

TOTAL_STEPS=9
cleanup() { [ $? -ne 0 ] && echo -e "\n${RED}${BOLD}BUILD FAILED${RESET}\n  Log: ${LOGFILE}"; }
trap cleanup EXIT

# ── Step 1: System packages ────────────────────────────────
install_packages() {
    step 1 $TOTAL_STEPS "System Packages"

    sudo apt-get update -qq
    sudo apt-get install -y -qq \
        bc bison build-essential ccache curl flex g++-multilib gcc-multilib \
        git git-lfs gnupg gperf lib32readline-dev lib32z1-dev libdw-dev \
        libelf-dev liblz4-tool libncurses-dev lib32ncurses-dev libssl-dev \
        libxml2-utils lz4 lzop openjdk-17-jdk pngcrush protobuf-compiler \
        python3 python3-protobuf rsync schedtool squashfs-tools xsltproc zip \
        zlib1g-dev libtinfo5 python-is-python3 \
        gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu 2>&1 | tail -5

    ok "System packages installed"
}

# ── Step 2: Swap ────────────────────────────────────────────
setup_swap() {
    step 2 $TOTAL_STEPS "Swap Setup"

    local swapfile="/tmp/swapfile2"
    local current_swap
    current_swap=$(free -m | awk '/Swap/{print $2}')

    if [ "$current_swap" -ge 15000 ]; then
        ok "Swap: ${current_swap}MB already configured"
        return 0
    fi

    if [ -f "$swapfile" ]; then
        sudo swapoff "$swapfile" 2>/dev/null || true
        sudo rm -f "$swapfile"
    fi

    sudo fallocate -l 16G "$swapfile"
    sudo chmod 600 "$swapfile"
    sudo mkswap "$swapfile" >/dev/null
    sudo swapon "$swapfile"

    current_swap=$(free -m | awk '/Swap/{print $2}')
    ok "Swap: ${current_swap}MB active"
}

# ── Step 3: Repo tool ──────────────────────────────────────
install_repo() {
    step 3 $TOTAL_STEPS "Repo Tool"

    mkdir -p "$HOME/.bin"
    export PATH="$HOME/.bin:$PATH"

    if [ -f "$HOME/.bin/repo" ]; then
        ok "Repo already installed"
        return 0
    fi

    curl -s https://storage.googleapis.com/git-repo-downloads/repo > "$HOME/.bin/repo"
    chmod a+rx "$HOME/.bin/repo"
    ok "Repo installed"
}

# ── Step 4: Git identity ────────────────────────────────────
setup_git() {
    step 4 $TOTAL_STEPS "Git Identity"

    git config --global user.name "bthavanish"
    git config --global user.email "bthavanish@users.noreply.github.com"
    git lfs install 2>/dev/null || true

    ok "Git configured for bthavanish"
}

# ── Step 5: Init repo ──────────────────────────────────────
init_repo() {
    step 5 $TOTAL_STEPS "Initializing LineageOS ${LINEAGE_BRANCH}"

    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    if [ -f ".repo/manifest.xml" ]; then
        if grep -q "$LINEAGE_BRANCH" .repo/manifest.xml 2>/dev/null; then
            ok "Already initialized"
        else
            warn "Different branch detected, reinitializing"
            rm -rf .repo/manifests .repo/manifest.xml
            repo init -u https://github.com/LineageOS/android.git \
                -b "$LINEAGE_BRANCH" --git-lfs --no-clone-bundle >> "$LOGFILE" 2>&1
        fi
    else
        repo init -u https://github.com/LineageOS/android.git \
            -b "$LINEAGE_BRANCH" --git-lfs --no-clone-bundle >> "$LOGFILE" 2>&1
    fi

    ok "Repo initialized"
}

# ── Step 6: Local manifests ────────────────────────────────
create_manifests() {
    step 6 $TOTAL_STEPS "Device Repos"

    cd "$BUILD_DIR"
    mkdir -p .repo/local_manifests

    {
        echo "<manifest>"
        for i in $(seq 0 $((${#REPO_NAMES[@]} - 1))); do
            echo "    <project name=\"${REPO_NAMES[$i]}\" path=\"${REPO_PATHS[$i]}\" remote=\"github\" revision=\"${LINEAGE_BRANCH}\" />"
        done
        echo "    <project name=\"LineageOS/android_hardware_samsung\" path=\"hardware/samsung\" remote=\"github\" revision=\"${LINEAGE_BRANCH}\" />"
        echo "    <project name=\"LineageOS/android_hardware_samsung_slsi-linaro_libbt\" path=\"hardware/samsung/slsi/libbt\" remote=\"github\" revision=\"${LINEAGE_BRANCH}\" />"
        echo "    <project name=\"LineageOS/android_hardware_samsung_slsi_linaro_libhwjpeg\" path=\"hardware/samsung/slsi/libhwjpeg\" remote=\"github\" revision=\"${LINEAGE_BRANCH}\" />"
        echo "</manifest>"
    } > .repo/local_manifests/a12s.xml

    ok "Local manifests created"
}

# ── Step 7: Sync sources ───────────────────────────────────
sync_sources() {
    step 7 $TOTAL_STEPS "Syncing Sources"

    cd "$BUILD_DIR"

    # Create kernel userdebug cfg to prevent merge_config failure
    mkdir -p kernel/samsung/a12s/arch/arm64/configs
    touch kernel/samsung/a12s/arch/arm64/configs/exynos850_userdebug.cfg

    repo sync -c --force-sync --no-clone-bundle --no-tags -j"$(nproc)" \
        >> "$LOGFILE" 2>&1 || die "Sync failed — check log"

    # Copy vendor kernel modules to system partition
    if [ -d vendor/samsung/a12s/proprietary/lib/modules ]; then
        mkdir -p system/lib/modules
        cp -a vendor/samsung/a12s/proprietary/lib/modules/* system/lib/modules/ 2>/dev/null || true
        ok "Kernel modules copied to system"
    fi

    ok "Sources synced"
}

# ── Step 8: Kernel patches ─────────────────────────────────
apply_patches() {
    step 8 $TOTAL_STEPS "Kernel Patches"

    cd "$BUILD_DIR"

    # Symlink clang toolchain
    local clang_prebuilt="prebuilts/clang/host/linux-x86"
    local clang_old="$clang_prebuilt/clang-r353983c"
    local clang_new="$clang_prebuilt/clang-r450784e"

    if [ -d "$clang_new" ] && [ ! -L "$clang_old" ]; then
        ln -sfn "$(realpath "$clang_new")" "$clang_old"
        ok "Symlinked clang-r353983c -> clang-r450784e"
    elif [ -L "$clang_old" ]; then
        ok "Clang symlink already exists"
    fi

    # Kernel Makefile patches
    local kmake="kernel/samsung/a12s/Makefile"

    # Remove -Wno-sizeof-pointer-div (unsupported by clang 14)
    if grep -q "Wno-sizeof-pointer-div" "$kmake"; then
        sed -i '/-Wno-sizeof-pointer-div/d' "$kmake"
        ok "Removed -Wno-sizeof-pointer-div"
    fi

    # Change -Werror=unknown-warning-option to -Wno-error=unknown-warning-option
    if grep -q "Werror=unknown-warning-option" "$kmake"; then
        sed -i 's/-Werror=unknown-warning-option/-Wno-error=unknown-warning-option/g' "$kmake"
        ok "Fixed -Werror=unknown-warning-option"
    fi

    # Remove -no-integrated-as (clang 14 works fine with integrated assembler)
    if grep -q "\-no-integrated-as" "$kmake"; then
        sed -i 's/ -no-integrated-as//g' "$kmake"
        ok "Removed -no-integrated-as"
    fi

    # Add -gdwarf-4 to KBUILD_CFLAGS (old GCC ld can't read DWARF5)
    if ! grep -q "gdwarf-4" "$kmake"; then
        sed -i '/^KBUILD_CFLAGS.*+= -g$/a KBUILD_CFLAGS += -gdwarf-4' "$kmake"
        ok "Added -gdwarf-4"
    fi

    # Hardcode GCC_TOOLCHAIN_DIR
    if ! grep -q "GCC_TOOLCHAIN_DIR.*:= /usr" "$kmake"; then
        sed -i '/^ifeq ($(TOOLCHAIN),)/a GCC_TOOLCHAIN_DIR := /usr' "$kmake"
        ok "Hardcoded GCC_TOOLCHAIN_DIR"
    fi

    # Unconditionally set READELF
    if ! grep -q "^READELF.*:= /usr/bin" "$kmake"; then
        sed -i '/^ifeq ($(READELF),)/a READELF := /usr/bin/aarch64-linux-gnu-readelf' "$kmake"
        ok "Hardcoded READELF path"
    fi

    # Fix FMP readelf paths
    for fmp in kernel/samsung/a12s/scripts/fmp/ELF.py kernel/samsung/a12s/scripts/fmp/IntegrityRoutine.py; do
        if [ -f "$fmp" ] && grep -q "CROSS_COMPILE.*readelf" "$fmp"; then
            sed -i 's|CROSS_COMPILE.*readelf|/usr/bin/aarch64-linux-gnu-readelf|g' "$fmp"
            ok "Fixed readelf in $(basename "$fmp")"
        fi
    done

    # Add stpcpy implementation (clang 14 generates calls, old libc lacks it)
    if ! grep -q "stpcpy" kernel/samsung/a12s/lib/string.c; then
        cat >> kernel/samsung/a12s/lib/string.c << 'STPCPY_EOF'

char *stpcpy(char *__restrict__ dest, const char *__restrict__ src)
{
	size_t i;

	for (i = 0; src[i]; i++)
		dest[i] = src[i];
	dest[i] = 0;

	return dest + i;
}
STPCPY_EOF
        ok "Added stpcpy implementation"
    fi

    if ! grep -q "stpcpy" kernel/samsung/a12s/include/linux/string.h; then
        sed -i '/^extern.*strlcat/a extern char *stpcpy(char *,const char *);' kernel/samsung/a12s/include/linux/string.h
        ok "Added stpcpy declaration"
    fi

    ok "Kernel patches applied"
}

# ── Step 9: Build ──────────────────────────────────────────
build_rom() {
    step 9 $TOTAL_STEPS "Building ROM"

    cd "$BUILD_DIR"

    export USE_CCACHE=1
    export CCACHE_EXEC=/usr/bin/ccache
    ccache -M 50G >> "$LOGFILE" 2>&1 || true

    source build/envsetup.sh
    lunch "$LUNCH_TARGET"

    # Re-export after envsetup (it may clobber them)
    export KERNEL_DEFCONFIG="exynos850-a12snsxx_defconfig"
    export TARGET_SOC="exynos850"
    export UNSAFE_DISABLE_HIDDENAPI_FLAGS=true
    export ALLOW_MISSING_DEPENDENCIES=true
    export READELF=/usr/bin/aarch64-linux-gnu-readelf

    echo -e "\n  ${CYAN}Stage 1: kernel + bootimage${RESET}"
    mka bootimage -j"$(nproc)" 2>&1 | tee -a "$LOGFILE" \
        | grep --line-buffered -E "^\[|FAILED|error:" || true
    ok "bootimage built"

    echo -e "\n  ${CYAN}Stage 2: full ROM (bacon)${RESET}"
    mka bacon -j"$(nproc)" -k 2>&1 | tee -a "$LOGFILE" \
        | grep --line-buffered -E "^\[|FAILED|error:|Package" || true

    echo ""
    echo -e "${GREEN}${BOLD}=========================================="
    echo -e "  BUILD COMPLETE"
    echo -e "==========================================${RESET}"
    echo ""

    ls -lah out/target/product/a12s/*.zip 2>/dev/null \
        && echo -e "  ${GREEN}Flashable zip ready!${RESET}" \
        || echo -e "  ${YELLOW}No zip found — run 'mka bacon' again${RESET}"

    echo -e "  ${DIM}Log: ${LOGFILE}${RESET}\n"
}

# ── Main ────────────────────────────────────────────────────
main() {
    echo -e "\n${CYAN}${BOLD}=========================================="
    echo "  LineageOS 21 — Samsung Galaxy A12s"
    echo "  SM-A127F/DS | Exynos 850"
    echo "==========================================${RESET}\n"
    echo -e "  ${DIM}Log: ${LOGFILE}${RESET}"

    local start_time=$SECONDS

    install_packages
    setup_swap
    install_repo
    setup_git
    init_repo
    create_manifests
    sync_sources
    apply_patches
    build_rom

    local total=$(( SECONDS - start_time ))
    echo -e "  ${DIM}Total time: $((total / 60))m $((total % 60))s${RESET}\n"
}

main "$@"
