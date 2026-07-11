#!/bin/bash
# ============================================================
# Samsung Galaxy Tab A9+ (SM-X216B) — LineageOS 23.2
# Full server setup + build (Ubuntu/Debian)
#
# Usage:
#   bash gta9p/server-build.sh
# ============================================================
set -e

LINEAGE_BRANCH="lineage-23.2"
KERNEL_BRANCH="samsung-5.4.249"
DEVICE="gta9p"
LUNCH_TARGET="lineage_${DEVICE}-userdebug"
BUILD_DIR="$HOME/android"
LOGFILE="$HOME/build_gta9p_$(date +%Y%m%d_%H%M%S).log"
TOTAL_STEPS=7

BOLD='\033[1m' DIM='\033[2m' RESET='\033[0m'
RED='\033[1;31m' GREEN='\033[1;32m' YELLOW='\033[1;33m'
BLUE='\033[1;34m' CYAN='\033[1;36m' WHITE='\033[1;37m'

step()  { echo -e "\n${BLUE}${BOLD}[$1/$2]${RESET} ${WHITE}${BOLD}$3${RESET}\n${DIM}------------------------------------------${RESET}"; }
ok()    { echo -e "  ${GREEN}[OK]${RESET} $1"; }
warn()  { echo -e "  ${YELLOW}[WARN]${RESET} $1"; }
err()   { echo -e "  ${RED}[ERR]${RESET} $1"; }
die()   { err "$1"; echo -e "\n${RED}${BOLD}BUILD FAILED${RESET}\n  Log: ${LOGFILE}"; exit 1; }

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
REPO_BRANCHES=("${LINEAGE_BRANCH}" "${LINEAGE_BRANCH}" "${LINEAGE_BRANCH}" "${LINEAGE_BRANCH}" "${LINEAGE_BRANCH}")

exec > >(tee -a "$LOGFILE") 2>&1
cleanup() { [ $? -ne 0 ] && echo -e "\n${RED}${BOLD}BUILD FAILED${RESET}\n  Log: ${LOGFILE}"; }
trap cleanup EXIT

# ── Packages ────────────────────────────────────────────────
install_packages() {
    step 1 $TOTAL_STEPS "System Packages"
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

# ── Java ────────────────────────────────────────────────────
setup_java() {
    step 2 $TOTAL_STEPS "Java"
    if java -version 2>&1 | grep -q "17"; then
        ok "Java 17 already installed"
    else
        sudo apt-get install -y -qq openjdk-17-jdk 2>&1 | tail -3
        export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
        ok "Java 17 installed"
    fi
}

# ── Repo ────────────────────────────────────────────────────
install_repo() {
    step 3 $TOTAL_STEPS "Repo Tool"
    mkdir -p ~/.bin
    export PATH="$HOME/.bin:$PATH"
    [ -f "$HOME/.bin/repo" ] && { ok "Repo already installed"; return 0; }
    curl -s https://storage.googleapis.com/git-repo-downloads/repo > ~/.bin/repo
    chmod a+rx ~/.bin/repo
    ok "Repo installed"
}

# ── ccache ──────────────────────────────────────────────────
setup_ccache() {
    step 4 $TOTAL_STEPS "ccache"
    export USE_CCACHE=1
    export CCACHE_DIR="$HOME/.ccache"
    export CCACHE_EXEC=$(which ccache)
    [ ! -d "$CCACHE_DIR" ] && ccache -M 50G 2>&1 | tail -1
    ok "ccache configured (50GB)"
}

# ── Sync ────────────────────────────────────────────────────
sync_sources() {
    step 5 $TOTAL_STEPS "Syncing Sources"
    mkdir -p "$BUILD_DIR" && cd "$BUILD_DIR"

    if [ -f ".repo/manifest.xml" ] && grep -q "$LINEAGE_BRANCH" .repo/manifest.xml 2>/dev/null; then
        ok "Repo already initialized"
    else
        rm -rf .repo/manifests .repo/manifest.xml
        repo init -u https://github.com/LineageOS/android.git -b "$LINEAGE_BRANCH" --git-lfs
        ok "Repo initialized"
    fi

    mkdir -p .repo/local_manifests
    {
        echo "<manifest>"
        for i in $(seq 0 $((${#REPO_NAMES[@]} - 1))); do
            echo "    <project name=\"${REPO_NAMES[$i]}\" path=\"${REPO_PATHS[$i]}\" remote=\"github\" revision=\"${REPO_BRANCHES[$i]}\" />"
        done
        echo "</manifest>"
    } > .repo/local_manifests/gta9p.xml
    ok "Local manifests created"

    repo sync --force-sync -c -j$(nproc) --no-clone-bundle --no-tags 2>&1 | tail -10
    ok "Sources synced"
}

# ── Build env ───────────────────────────────────────────────
setup_build() {
    step 6 $TOTAL_STEPS "Build Environment"
    cd "$BUILD_DIR"
    source build/envsetup.sh
    ok "envsetup.sh loaded"
    lunch "$LUNCH_TARGET"
    ok "Lunch target: ${TARGET_PRODUCT:-unknown}"
}

# ── Build ───────────────────────────────────────────────────
build_rom() {
    step 7 $TOTAL_STEPS "Building ROM"
    cd "$BUILD_DIR"
    echo -e "  ${CYAN}Building... (1-3 hours)${RESET}\n"
    local start=$SECONDS
    mka bacon
    local elapsed=$(( SECONDS - start ))
    echo -e "\n${GREEN}${BOLD}BUILD SUCCESSFUL!${RESET}"
    echo -e "  Time: $((elapsed / 60))m $((elapsed % 60))s"
    find "out/target/product/${DEVICE}" -maxdepth 1 -name "*.zip" -exec ls -lh {} \; 2>/dev/null
    echo -e "  ${DIM}Log: ${LOGFILE}${RESET}\n"
}

main() {
    echo -e "\n${CYAN}${BOLD}LineageOS 23.2 — Samsung Galaxy Tab A9+ (Server Build)${RESET}\n"
    install_packages; setup_java; install_repo; setup_ccache; sync_sources; setup_build; build_rom
}
main "$@"
