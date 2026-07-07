#!/bin/bash
# ============================================
# Full Server Setup + Build Script
# Samsung Galaxy Tab A9+ (gta9p / SM-X216B)
# LineageOS 23.2 (Android 16)
#
# For rented servers (Ubuntu/Debian)
# Logs everything to file + terminal
# ============================================

set -e

# ============================================
# Configuration
# ============================================
LINEAGE_BRANCH="lineage-23.2"
KERNEL_BRANCH="lineage-22.1"
DEVICE="gta9p"
LUNCH_TARGET="lineage_${DEVICE}-userdebug"
BUILD_DIR="$HOME/android"
LOGFILE="$HOME/build_$(date +%Y%m%d_%H%M%S).log"
BRANCH_DATE=$(date +%Y%m%d)

# Repos
REPO_NAMES=(
    "bthavanish/android_kernel_samsung_sm6375"
    "bthavanish/android_device_samsung_gta9p-common"
    "bthavanish/android_device_samsung_gta9p"
    "bthavanish/android_vendor_samsung_gta9p-common"
    "bthavanish/android_vendor_samsung_gta9p"
)
REPO_PATHS=(
    "kernel/samsung/sm6375"
    "device/samsung/gta9p-common"
    "device/samsung/gta9p"
    "vendor/samsung/gta9p-common"
    "vendor/samsung/gta9p"
)
REPO_BRANCHES=(
    "${KERNEL_BRANCH}"
    "${LINEAGE_BRANCH}"
    "${LINEAGE_BRANCH}"
    "${LINEAGE_BRANCH}"
    "${LINEAGE_BRANCH}"
)

# ============================================
# TUI
# ============================================
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'

header() {
    echo ""
    echo -e "${CYAN}${BOLD}=========================================="
    echo "  LINEAGEOS 23.2 - Samsung Galaxy Tab A9+"
    echo "  Server Setup + Build Script"
    echo -e "==========================================${RESET}"
    echo ""
}

step() {
    echo ""
    echo -e "${BLUE}${BOLD}[$1/$2]${RESET} ${WHITE}${BOLD}$3${RESET}"
    echo -e "${DIM}------------------------------------------${RESET}"
}

ok()    { echo -e "  ${GREEN}[OK]${RESET} $1"; }
warn()  { echo -e "  ${YELLOW}[WARN]${RESET} $1"; }
err()   { echo -e "  ${RED}[ERR]${RESET} $1"; }
info()  { echo -e "  ${CYAN}[..]${RESET} $1"; }

die() {
    err "$1"
    echo ""
    echo -e "${RED}${BOLD}=========================================="
    echo "  FATAL: Build aborted"
    echo -e "==========================================${RESET}"
    echo -e "  Log: ${LOGFILE}"
    exit 1
}

# Tee both stdout and stderr to log file
exec > >(tee -a "$LOGFILE") 2>&1

# ============================================
# Cleanup
# ============================================
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        err "Script failed (exit code: $exit_code)"
        err "Check log: ${LOGFILE}"
    fi
}
trap cleanup EXIT

# ============================================
# Step 1: System packages
# ============================================
install_packages() {
    step 1 7 "Installing System Packages"

    sudo apt-get update -qq
    sudo apt-get install -y -qq \
        git-core gnupg flex bison build-essential zip curl zlib1g-dev \
        libc6-dev-i386 libncurses5 lib32ncurses5-dev x11proto-core-dev \
        libx11-dev lib32z1-dev libgl1-mesa-dev libxml2-utils xsltproc \
        unzip fontconfig openjdk-17-jdk python3 python3-pip \
        bc rsync ccache lz4 lzop imagemagick \
        libssl-dev libelf-dev device-tree-compiler \
        pngcrush schedtool 2>&1 | tail -5

    ok "System packages installed"
}

# ============================================
# Step 2: Java
# ============================================
setup_java() {
    step 2 7 "Setting Up Java"

    if java -version 2>&1 | grep -q "17"; then
        ok "Java 17 already installed"
        return 0
    fi

    sudo apt-get install -y -qq openjdk-17-jdk 2>&1 | tail -3
    export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
    ok "Java 17 installed"
}

# ============================================
# Step 3: Repo tool
# ============================================
install_repo() {
    step 3 7 "Installing Repo Tool"

    mkdir -p ~/.bin
    export PATH="$HOME/.bin:$PATH"

    if [ -f "$HOME/.bin/repo" ]; then
        ok "Repo already installed"
        return 0
    fi

    curl -s https://storage.googleapis.com/git-repo-downloads/repo > ~/.bin/repo
    chmod a+rx ~/.bin/repo
    ok "Repo installed"
}

# ============================================
# Step 4: ccache
# ============================================
setup_ccache() {
    step 4 7 "Setting Up ccache"

    export USE_CCACHE=1
    export CCACHE_DIR="$HOME/.ccache"
    export CCACHE_EXEC=$(which ccache)

    if [ ! -d "$CCACHE_DIR" ]; then
        ccache -M 50G 2>&1 | tail -1
    fi

    ok "ccache configured (50GB limit)"
}

# ============================================
# Step 5: Sync sources
# ============================================
sync_sources() {
    step 5 7 "Syncing Sources"

    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    # Init LineageOS
    if [ -f ".repo/manifest.xml" ]; then
        if grep -q "$LINEAGE_BRANCH" .repo/manifest.xml 2>/dev/null; then
            ok "Repo already initialized"
        else
            warn "Different branch, reinitializing"
            rm -rf .repo/manifests .repo/manifest.xml
            repo init -u https://github.com/LineageOS/android.git \
                -b "$LINEAGE_BRANCH" --git-lfs
        fi
    else
        info "Initializing LineageOS ${LINEAGE_BRANCH}..."
        repo init -u https://github.com/LineageOS/android.git \
            -b "$LINEAGE_BRANCH" --git-lfs
    fi
    ok "Repo initialized"

    # Local manifests
    mkdir -p .repo/local_manifests
    {
        echo "<manifest>"
        for i in $(seq 0 $((${#REPO_NAMES[@]} - 1))); do
            echo "    <project name=\"${REPO_NAMES[$i]}\" path=\"${REPO_PATHS[$i]}\" remote=\"github\" revision=\"${REPO_BRANCHES[$i]}\" />"
        done
        echo "</manifest>"
    } > .repo/local_manifests/gta9p.xml
    ok "Local manifests created"

    # Verify repos exist
    info "Verifying repos..."
    for i in $(seq 0 $((${#REPO_NAMES[@]} - 1))); do
        local name="${REPO_NAMES[$i]}"
        local branch="${REPO_BRANCHES[$i]}"
        if git ls-remote --heads "https://github.com/${name}.git" "$branch" >/dev/null 2>&1; then
            ok "${REPO_PATHS[$i]}"
        else
            die "Repo not found: ${name} @ ${branch}"
        fi
    done

    # Sync
    info "Syncing (this takes a while)..."
    repo sync --force-sync -c -j$(nproc) --no-clone-bundle --no-tags 2>&1 | tail -10
    ok "Sources synced"
}

# ============================================
# Step 6: Build environment + lunch
# ============================================
setup_build() {
    step 6 7 "Build Environment"

    cd "$BUILD_DIR"

    source build/envsetup.sh
    ok "envsetup.sh loaded"

    lunch "$LUNCH_TARGET"
    ok "Lunch target: ${TARGET_PRODUCT:-unknown}"
}

# ============================================
# Step 7: Build
# ============================================
build_rom() {
    step 7 7 "Building ROM"

    cd "$BUILD_DIR"

    echo -e "  ${CYAN}Building... (1-3 hours)${RESET}"
    echo ""

    local start_time=$SECONDS

    mka bacon

    local elapsed=$(( SECONDS - start_time ))
    local mins=$(( elapsed / 60 ))
    local secs=$(( elapsed % 60 ))

    echo ""
    echo -e "${GREEN}${BOLD}=========================================="
    echo "  BUILD SUCCESSFUL!"
    echo -e "==========================================${RESET}"
    echo ""
    echo -e "  ${WHITE}Time:${RESET} ${mins}m ${secs}s"

    # List output
    local outdir="out/target/product/${DEVICE}"
    if [ -d "$outdir" ]; then
        echo -e "  ${WHITE}Output:${RESET} ${BUILD_DIR}/${outdir}/"
        local zips
        zips=$(find "$outdir" -maxdepth 1 -name "*.zip" -type f 2>/dev/null || true)
        if [ -n "$zips" ]; then
            echo -e "  ${GREEN}Files:${RESET}"
            echo "$zips" | while read -r z; do
                local size
                size=$(du -h "$z" | cut -f1)
                echo -e "    ${GREEN}->${RESET} $(basename "$z") ${DIM}(${size})${RESET}"
            done
        fi
    fi

    echo ""
    echo -e "  ${DIM}Full log: ${LOGFILE}${RESET}"
    echo ""
}

# ============================================
# Main
# ============================================
main() {
    header

    echo -e "  ${DIM}Log file: ${LOGFILE}${RESET}"
    echo -e "  ${DIM}Build dir: ${BUILD_DIR}${RESET}"
    echo ""

    local start_time=$SECONDS

    install_packages
    setup_java
    install_repo
    setup_ccache
    sync_sources
    setup_build
    build_rom

    local total_time=$(( SECONDS - start_time ))
    local total_mins=$(( total_time / 60 ))
    echo -e "  ${DIM}Total time: ${total_mins} minutes${RESET}"
    echo ""
}

main "$@"
