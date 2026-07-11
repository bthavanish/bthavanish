#!/bin/bash
# ============================================================
# Samsung Galaxy Tab A9+ (SM-X216B) — LineageOS 23.2
# Crave.io build script
#
# Usage:
#   cd /crave-devspaces/Lineage-gta9p
#   crave run --no-patch -- "bash gta9p/crave-build.sh"
# ============================================================
set -e

LINEAGE_BRANCH="lineage-23.2"
KERNEL_BRANCH="samsung-5.4.249"
DEVICE="gta9p"
LUNCH_TARGET="lineage_${DEVICE}-userdebug"
TOTAL_STEPS=6

BOLD='\033[1m' DIM='\033[2m' RESET='\033[0m'
RED='\033[1;31m' GREEN='\033[1;32m' YELLOW='\033[1;33m'
BLUE='\033[1;34m' CYAN='\033[1;36m' WHITE='\033[1;37m'

LOGFILE="build_$(date +%Y%m%d_%H%M%S).log"

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

cleanup() { [ $? -ne 0 ] && echo -e "\n${RED}${BOLD}BUILD FAILED${RESET}\n  Log: ${LOGFILE}"; }
trap cleanup EXIT

# ── Pre-flight ──────────────────────────────────────────────
preflight() {
    step 1 $TOTAL_STEPS "Pre-flight Checks"
    local issues=0
    for cmd in repo git; do
        command -v "$cmd" >/dev/null 2>&1 && ok "$cmd found" || { err "$cmd not found"; issues=$((issues + 1)); }
    done
    [ -f "/opt/crave/resync.sh" ] && ok "crave resync found" || { err "/opt/crave/resync.sh not found"; issues=$((issues + 1)); }
    local free_gb=$(df -k . 2>/dev/null | tail -1 | awk '{print int($4/1024/1024)}')
    [ "$free_gb" -ge 100 ] && ok "Disk: ${free_gb}GB free" || warn "Disk: ${free_gb}GB free (recommend 100GB+)"
    [ $issues -gt 0 ] && die "Pre-flight failed"
    ok "All checks passed"
}

# ── Init ────────────────────────────────────────────────────
init_repo() {
    step 2 $TOTAL_STEPS "Initializing LineageOS ${LINEAGE_BRANCH}"
    rm -rf .repo/local_manifests
    if [ -f ".repo/manifest.xml" ] && grep -q "$LINEAGE_BRANCH" .repo/manifest.xml 2>/dev/null; then
        ok "Already initialized"
    else
        rm -rf .repo/manifests .repo/manifest.xml
        repo init -u https://github.com/LineageOS/android.git -b "$LINEAGE_BRANCH" --git-lfs >> "$LOGFILE" 2>&1
        ok "Repo initialized"
    fi
}

# ── Manifests ───────────────────────────────────────────────
create_manifests() {
    step 3 $TOTAL_STEPS "Device Repos"
    mkdir -p .repo/local_manifests
    {
        echo "<manifest>"
        for i in $(seq 0 $((${#REPO_NAMES[@]} - 1))); do
            echo "    <project name=\"${REPO_NAMES[$i]}\" path=\"${REPO_PATHS[$i]}\" remote=\"github\" revision=\"${REPO_BRANCHES[$i]}\" />"
        done
        echo "</manifest>"
    } > .repo/local_manifests/gta9p.xml
    ok "Local manifests created"
}

# ── Sync ────────────────────────────────────────────────────
sync_sources() {
    step 4 $TOTAL_STEPS "Syncing Sources"
    /opt/crave/resync.sh >> "$LOGFILE" 2>&1 || die "Sync failed"
    for f in build/envsetup.sh device/samsung/gta9p/device.mk vendor/samsung/gta9p/gta9p-vendor.mk; do
        [ -f "$f" ] && ok "$f" || die "$f missing after sync"
    done
    ok "Sources synced"
}

# ── Build env ───────────────────────────────────────────────
setup_and_lunch() {
    step 5 $TOTAL_STEPS "Build Environment & Lunch"
    source build/envsetup.sh >> "$LOGFILE" 2>&1
    lunch "$LUNCH_TARGET" >> "$LOGFILE" 2>&1 || die "lunch failed"
    ok "Target: ${TARGET_PRODUCT:-unknown}"
}

# ── Build ───────────────────────────────────────────────────
build_rom() {
    step 6 $TOTAL_STEPS "Building ROM"
    echo -e "  ${CYAN}Building... (1-3 hours)${RESET}\n"
    local start=$SECONDS
    mka bacon >> "$LOGFILE" 2>&1 || die "mka bacon failed"
    local elapsed=$(( SECONDS - start ))
    echo -e "\n${GREEN}${BOLD}BUILD SUCCESSFUL!${RESET}"
    echo -e "  Time: $((elapsed / 60))m $((elapsed % 60))s"
    find "out/target/product/${DEVICE}" -maxdepth 1 -name "*.zip" -exec ls -lh {} \; 2>/dev/null
    echo -e "  ${DIM}Log: ${LOGFILE}${RESET}\n"
}

main() {
    echo -e "\n${CYAN}${BOLD}LineageOS 23.2 — Samsung Galaxy Tab A9+${RESET}\n"
    preflight; init_repo; create_manifests; sync_sources; setup_and_lunch; build_rom
}
main "$@"
