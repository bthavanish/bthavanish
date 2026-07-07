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

# ============================================
# TUI / Styling
# ============================================
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'

LOGFILE="build_$(date +%Y%m%d_%H%M%S).log"

header() {
    echo ""
    echo -e "${CYAN}${BOLD}"
    echo "=========================================="
    echo "  LINEAGEOS 23.2 - Samsung Galaxy Tab A9+"
    echo "  SM-X216B | SM6375 (holi)"
    echo "=========================================="
    echo -e "${RESET}"
    echo ""
}

step() {
    echo -e "${BLUE}${BOLD}[$1/$2]${RESET} ${WHITE}${BOLD}$3${RESET}"
    echo -e "${DIM}------------------------------------------${RESET}"
}

ok() {
    echo -e "  ${GREEN}[OK]${RESET} $1"
}

warn() {
    echo -e "  ${YELLOW}[WARN]${RESET} $1"
    echo "  [WARN] $1" >> "$LOGFILE"
}

err() {
    echo -e "  ${RED}[ERR]${RESET} $1"
    echo "  [ERROR] $1" >> "$LOGFILE"
}

die() {
    err "$1"
    echo ""
    echo -e "${RED}${BOLD}=========================================="
    echo -e "  BUILD FAILED"
    echo -e "==========================================${RESET}"
    echo -e "  Log: ${LOGFILE}"
    exit 1
}

# ============================================
# Configuration
# ============================================
LINEAGE_BRANCH="lineage-23.2"
KERNEL_BRANCH="lineage-22.1"
DEVICE="gta9p"
LUNCH_TARGET="lineage_${DEVICE}-userdebug"
TOTAL_STEPS=6

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
# Cleanup on failure
# ============================================
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        err "Script failed (exit code: $exit_code)"
        err "Full log: ${LOGFILE}"
    fi
}
trap cleanup EXIT

# ============================================
# Pre-flight checks
# ============================================
preflight() {
    step 1 $TOTAL_STEPS "Pre-flight Checks"
    local issues=0

    # Commands
    for cmd in repo git; do
        if command -v "$cmd" >/dev/null 2>&1; then
            ok "$cmd found"
        else
            err "$cmd not found"
            issues=$((issues + 1))
        fi
    done

    # Crave resync
    if [ -f "/opt/crave/resync.sh" ]; then
        ok "crave resync found"
    else
        err "/opt/crave/resync.sh not found (not on crave?)"
        issues=$((issues + 1))
    fi

    # Disk space
    local free_kb
    free_kb=$(df -k . 2>/dev/null | tail -1 | awk '{print $4}' || echo "0")
    local free_gb=$((free_kb / 1024 / 1024))
    if [ "$free_gb" -ge 100 ]; then
        ok "Disk: ${free_gb}GB free"
    elif [ "$free_gb" -ge 50 ]; then
        warn "Disk: ${free_gb}GB free (recommend 100GB+)"
    else
        err "Disk: ${free_gb}GB free (need 50GB+)"
        issues=$((issues + 1))
    fi

    echo ""
    if [ $issues -gt 0 ]; then
        die "Pre-flight failed with $issues issue(s)"
    fi
    ok "All checks passed"
    echo ""
}

# ============================================
# Step 2: Initialize repo
# ============================================
init_repo() {
    step 2 $TOTAL_STEPS "Initializing LineageOS ${LINEAGE_BRANCH}"

    rm -rf .repo/local_manifests

    # Check if already correct
    if [ -f ".repo/manifest.xml" ]; then
        if grep -q "$LINEAGE_BRANCH" .repo/manifest.xml 2>/dev/null; then
            ok "Already initialized with ${LINEAGE_BRANCH}"
            return 0
        else
            warn "Different branch detected, reinitializing"
            rm -rf .repo/manifests .repo/manifest.xml
        fi
    fi

    echo -e "  ${DIM}Cloning LineageOS manifest...${RESET}"
    if ! repo init -u https://github.com/LineageOS/android.git \
        -b "$LINEAGE_BRANCH" \
        --git-lfs >> "$LOGFILE" 2>&1; then
        die "repo init failed - check log: ${LOGFILE}"
    fi

    ok "Repo initialized"
    echo ""
}

# ============================================
# Step 3: Local manifests
# ============================================
create_manifests() {
    step 3 $TOTAL_STEPS "Adding Device Repos"

    mkdir -p .repo/local_manifests

    local count=0
    local total=${#REPO_NAMES[@]}

    for i in $(seq 0 $((total - 1))); do
        count=$((count + 1))
        local name="${REPO_NAMES[$i]}"
        local path="${REPO_PATHS[$i]}"
        local branch="${REPO_BRANCHES[$i]}"

        echo -e "  ${DIM}[$count/$total]${RESET} Checking ${name} @ ${branch}..."

        if git ls-remote --heads "https://github.com/${name}.git" "$branch" >/dev/null 2>&1; then
            ok "${path} @ ${branch}"
        else
            die "Repo or branch not found: ${name} @ ${branch}"
        fi
    done

    # Write manifest
    {
        echo "<manifest>"
        for i in $(seq 0 $((${#REPO_NAMES[@]} - 1))); do
            echo "    <project name=\"${REPO_NAMES[$i]}\" path=\"${REPO_PATHS[$i]}\" remote=\"github\" revision=\"${REPO_BRANCHES[$i]}\" />"
        done
        echo "</manifest>"
    } > .repo/local_manifests/gta9p.xml

    echo ""
    ok "Local manifests created (${total} repos)"
    echo ""
}

# ============================================
# Step 4: Sync
# ============================================
sync_sources() {
    step 4 $TOTAL_STEPS "Syncing Sources"

    echo -e "  ${DIM}Using /opt/crave/resync.sh ...${RESET}"
    echo -e "  ${DIM}This may take 30-60 minutes...${RESET}"
    echo ""

    if ! /opt/crave/resync.sh >> "$LOGFILE" 2>&1; then
        err "Sync failed. Check log: ${LOGFILE}"
        die "Source sync failed"
    fi

    # Verify critical files
    echo -e "  ${DIM}Verifying sync...${RESET}"
    local missing=0
    for f in build/envsetup.sh device/samsung/gta9p/device.mk vendor/samsung/gta9p/gta9p-vendor.mk; do
        if [ -f "$f" ]; then
            ok "$f"
        else
            err "$f missing"
            missing=$((missing + 1))
        fi
    done

    if [ $missing -gt 0 ]; then
        die "$missing critical file(s) missing after sync"
    fi
    echo ""
}

# ============================================
# Step 5: Build env + lunch
# ============================================
setup_and_lunch() {
    step 5 $TOTAL_STEPS "Build Environment & Lunch"

    echo -e "  ${DIM}Sourcing build/envsetup.sh...${RESET}"
    if ! source build/envsetup.sh >> "$LOGFILE" 2>&1; then
        die "Failed to source envsetup.sh"
    fi
    ok "envsetup.sh loaded"

    echo -e "  ${DIM}Running lunch ${LUNCH_TARGET}...${RESET}"
    if ! lunch "$LUNCH_TARGET" >> "$LOGFILE" 2>&1; then
        err "lunch ${LUNCH_TARGET} failed"
        die "lunch failed - check log: ${LOGFILE}"
    fi
    ok "Target: ${TARGET_PRODUCT:-unknown}"
    echo ""
}

# ============================================
# Step 6: Build
# ============================================
build_rom() {
    step 6 $TOTAL_STEPS "Building ROM"

    echo -e "  ${MAGENTA}This will take 1-3 hours...${RESET}"
    echo -e "  ${DIM}Output: out/target/product/${DEVICE}/lineage-*.zip${RESET}"
    echo ""

    local start_time=$SECONDS

    if ! mka bacon >> "$LOGFILE" 2>&1; then
        err "Build failed - check log: ${LOGFILE}"
        die "mka bacon failed"
    fi

    local elapsed=$(( SECONDS - start_time ))
    local mins=$(( elapsed / 60 ))
    local secs=$(( elapsed % 60 ))

    echo ""
    echo -e "${GREEN}${BOLD}=========================================="
    echo -e "  BUILD SUCCESSFUL!"
    echo -e "==========================================${RESET}"
    echo ""
    echo -e "  ${WHITE}Time:${RESET} ${mins}m ${secs}s"
    echo -e "  ${WHITE}Output:${RESET} out/target/product/${DEVICE}/"
    echo ""

    # List zips
    local zips
    zips=$(find "out/target/product/${DEVICE}" -maxdepth 1 -name "*.zip" -type f 2>/dev/null || true)
    if [ -n "$zips" ]; then
        echo -e "  ${GREEN}Files:${RESET}"
        echo "$zips" | while read -r z; do
            local size
            size=$(du -h "$z" | cut -f1)
            echo -e "    ${GREEN}->${RESET} $(basename "$z") ${DIM}(${size})${RESET}"
        done
    fi

    echo ""
    echo -e "  ${DIM}Log: ${LOGFILE}${RESET}"
    echo ""
}

# ============================================
# Main
# ============================================
main() {
    header

    local start_time=$SECONDS

    preflight
    init_repo
    create_manifests
    sync_sources
    setup_and_lunch
    build_rom

    local total_time=$(( SECONDS - start_time ))
    local total_mins=$(( total_time / 60 ))
    echo -e "  ${DIM}Total time: ${total_mins} minutes${RESET}"
    echo ""
}

main "$@"
