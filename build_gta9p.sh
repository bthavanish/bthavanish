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

set -euo pipefail

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
BG_BLACK='\033[40m'

LOGFILE="build_$(date +%Y%m%d_%H%M%S).log"

header() {
    clear
    echo -e "${BG_BLACK}"
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║   ██╗     ██╗███╗   ███╗██████╗     █████╗  ██████╗ ██████╗  ║"
    echo "║   ██║     ██║████╗ ████║██╔══██╗   ██╔══██╗██╔═══██╗██╔══██╗ ║"
    echo "║   ██║     ██║██╔████╔██║██████╔╝   ███████║██║   ██║██████╔╝ ║"
    echo "║   ██║     ██║██║╚██╔╝██║██╔═══╝    ██╔══██║██║   ██║██╔══██╗ ║"
    echo "║   ███████╗██║██║ ╚═╝ ██║██║        ██║  ██║╚██████╔╝██║  ██║ ║"
    echo "║   ╚══════╝╚═╝╚═╝     ╚═╝╚═╝        ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝ ║"
    echo "║                                                              ║"
    echo "║          ${WHITE}Samsung Galaxy Tab A9+ (SM-X216B)${CYAN}               ║"
    echo "║          ${DIM}LineageOS 23.2 | Android 16 QPR2${RESET}${CYAN}${BOLD}                ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
    echo ""
}

step() {
    local step_num=$1
    local total=$2
    local msg=$3
    echo -e "${BLUE}${BOLD}[$step_num/$total]${RESET} ${WHITE}${BOLD}$msg${RESET}"
    echo -e "${DIM}────────────────────────────────────────────────────────────${RESET}"
}

ok() {
    echo -e "  ${GREEN}✓${RESET} $1"
}

warn() {
    echo -e "  ${YELLOW}⚠${RESET} $1"
    echo "  [WARN] $1" >> "$LOGFILE"
}

err() {
    echo -e "  ${RED}✗${RESET} $1"
    echo "  [ERROR] $1" >> "$LOGFILE"
}

die() {
    err "$1"
    echo ""
    echo -e "${RED}${BOLD}╔══════════════════════════════════════════╗${RESET}"
    echo -e "${RED}${BOLD}║           BUILD FAILED                   ║${RESET}"
    echo -e "${RED}${BOLD}╚══════════════════════════════════════════╝${RESET}"
    echo -e "  Log: ${DIM}${LOGFILE}${RESET}"
    exit 1
}

spinner() {
    local pid=$1
    local msg=${2:-"Working..."}
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}%s${RESET} %s" "${spin:i++%${#spin}:1}" "$msg"
        sleep 0.1
    done
    printf "\r"
}

progress_bar() {
    local current=$1
    local total=$2
    local width=40
    local pct=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    printf "\r  ["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "] %3d%%" "$pct"
}

# ============================================
# Configuration
# ============================================
LINEAGE_BRANCH="lineage-23.2"
KERNEL_BRANCH="lineage-22.1"
DEVICE="gta9p"
LUNCH_TARGET="lineage_${DEVICE}-userdebug"
TOTAL_STEPS=6

REPOS=(
    "bthavanish/android_kernel_samsung_sm6375      kernel/samsung/sm6375        ${KERNEL_BRANCH}"
    "bthavanish/android_device_samsung_gta9p-common device/samsung/gta9p-common  ${LINEAGE_BRANCH}"
    "bthavanish/android_device_samsung_gta9p       device/samsung/gta9p         ${LINEAGE_BRANCH}"
    "bthavanish/android_vendor_samsung_gta9p-common vendor/samsung/gta9p-common  ${LINEAGE_BRANCH}"
    "bthavanish/android_vendor_samsung_gta9p       vendor/samsung/gta9p         ${LINEAGE_BRANCH}"
)

# ============================================
# Helpers
# ============================================
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        err "Build failed at line ${BASH_LINENO[0]:-unknown} (exit code: $exit_code)"
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
        if command -v "$cmd" &>/dev/null; then
            ok "$cmd found: $(command -v "$cmd")"
        else
            err "$cmd not found"
            ((issues++))
        fi
    done

    # Crave
    if [ -f "/opt/crave/resync.sh" ]; then
        ok "crave resync found"
    else
        err "/opt/crave/resync.sh not found (not on crave.io?)"
        ((issues++))
    fi

    # Disk space
    local free_gb
    free_gb=$(df -BG --output=avail . 2>/dev/null | tail -1 | tr -d ' G' || echo "0")
    if [ "$free_gb" -ge 100 ]; then
        ok "Disk space: ${free_gb}GB free"
    elif [ "$free_gb" -ge 50 ]; then
        warn "Disk space: ${free_gb}GB free (recommended: 100GB+)"
    else
        err "Disk space: ${free_gb}GB free (need 50GB+ minimum)"
        ((issues++))
    fi

    # RAM
    local ram_gb
    ram_gb=$(free -g 2>/dev/null | awk '/Mem:/{print $2}' || echo "0")
    if [ "$ram_gb" -ge 32 ]; then
        ok "RAM: ${ram_gb}GB"
    elif [ "$ram_gb" -ge 16 ]; then
        warn "RAM: ${ram_gb}GB (recommended: 32GB+)"
    else
        warn "RAM: ${ram_gb}GB (build may be slow)"
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
    if [ -f ".repo/manifest.xml" ] && grep -q "$LINEAGE_BRANCH" .repo/manifest.xml 2>/dev/null; then
        ok "Already initialized with ${LINEAGE_BRANCH}"
        return 0
    fi

    # Remove stale init
    if [ -d ".repo/manifests" ]; then
        warn "Removing previous repo init (different branch)"
        rm -rf .repo/manifests .repo/manifest.xml
    fi

    echo -e "  ${DIM}Cloning LineageOS manifest...${RESET}"
    if ! repo init -u https://github.com/LineageOS/android.git \
        -b "$LINEAGE_BRANCH" \
        --git-lfs 2>&1 | tee -a "$LOGFILE"; then
        die "repo init failed"
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
    local total=${#REPOS[@]}

    for repo_info in "${REPOS[@]}"; do
        read -r repo_name repo_path repo_branch <<< "$repo_info"
        ((count++))
        progress_bar $count $total
        echo ""

        # Validate repo exists
        if git ls-remote --heads "https://github.com/${repo_name}.git" "$repo_branch" &>/dev/null; then
            ok "${repo_name} @ ${repo_branch}"
        else
            die "Repository not found: ${repo_name} @ ${repo_branch}"
        fi
    done

    # Write manifest
    {
        echo "<manifest>"
        for repo_info in "${REPOS[@]}"; do
            read -r repo_name repo_path repo_branch <<< "$repo_info"
            echo "    <project name=\"${repo_name}\" path=\"${repo_path}\" remote=\"github\" revision=\"${repo_branch}\" />"
        done
        echo "</manifest>"
    } > .repo/local_manifests/gta9p.xml

    echo ""
    ok "Local manifests created (${#REPOS[@]} repos)"
    echo ""
}

# ============================================
# Step 4: Sync
# ============================================
sync_sources() {
    step 4 $TOTAL_STEPS "Syncing Sources"

    echo -e "  ${DIM}This may take 30-60 minutes...${RESET}"
    echo -e "  ${DIM}Using /opt/crave/resync.sh (required by crave rules)${RESET}"
    echo ""

    if ! /opt/crave/resync.sh 2>&1 | tee -a "$LOGFILE"; then
        err "Sync failed. Common fixes:"
        echo -e "    ${YELLOW}1${RESET} Run with --clean flag"
        echo -e "    ${YELLOW}2${RESET} Check network connectivity"
        echo -e "    ${YELLOW}3${RESET} Verify all repos are public"
        die "Source sync failed"
    fi

    # Verify critical files
    echo ""
    echo -e "  ${DIM}Verifying sync...${RESET}"
    local missing=0
    for f in build/envsetup.sh device/samsung/gta9p/device.mk vendor/samsung/gta9p/gta9p-vendor.mk; do
        if [ -f "$f" ]; then
            ok "$f"
        else
            err "$f missing"
            ((missing++))
        fi
    done

    [ $missing -eq 0 ] || die "$missing critical file(s) missing after sync"
    echo ""
}

# ============================================
# Step 5: Build env + lunch
# ============================================
setup_and_lunch() {
    step 5 $TOTAL_STEPS "Build Environment & Lunch"

    echo -e "  ${DIM}Sourcing build/envsetup.sh...${RESET}"
    if ! source build/envsetup.sh 2>&1 | tee -a "$LOGFILE"; then
        die "Failed to source envsetup.sh"
    fi
    ok "envsetup.sh loaded"

    echo -e "  ${DIM}Running lunch ${LUNCH_TARGET}...${RESET}"
    if ! lunch "$LUNCH_TARGET" 2>&1 | tee -a "$LOGFILE"; then
        err "lunch failed. Trying to find available targets:"
        lunch 2>&1 | grep -i "gta9p\|samsung" | head -5 || echo "  No matching targets"
        die "lunch ${LUNCH_TARGET} failed"
    fi
    ok "Target: ${TARGET_PRODUCT:-unknown}"
    echo ""
}

# ============================================
# Step 6: Build
# ============================================
build_rom() {
    step 6 $TOTAL_STEPS "Building ROM"

    echo -e "  ${MAGENTA}${BOLD}This will take 1-3 hours depending on server load${RESET}"
    echo -e "  ${DIM}Output: out/target/product/${DEVICE}/lineage-*.zip${RESET}"
    echo ""
    echo -e "  ${CYAN}Building...${RESET}"
    echo ""

    local start_time=$SECONDS

    if ! mka bacon 2>&1 | tee -a "$LOGFILE"; then
        err "Build failed. Check log: ${LOGFILE}"
        die "mka bacon failed"
    fi

    local elapsed=$(( SECONDS - start_time ))
    local mins=$(( elapsed / 60 ))
    local secs=$(( elapsed % 60 ))

    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}${BOLD}║          BUILD SUCCESSFUL!               ║${RESET}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${WHITE}Time:${RESET} ${mins}m ${secs}s"
    echo -e "  ${WHITE}Output:${RESET} out/target/product/${DEVICE}/"
    echo ""

    # List zips
    local zips
    zips=$(find "out/target/product/${DEVICE}" -maxdepth 1 -name "*.zip" -type f 2>/dev/null)
    if [ -n "$zips" ]; then
        echo -e "  ${GREEN}Files:${RESET}"
        echo "$zips" | while read -r z; do
            local size
            size=$(du -h "$z" | cut -f1)
            echo -e "    ${GREEN}→${RESET} $(basename "$z") ${DIM}(${size})${RESET}"
        done
    fi

    echo ""
    echo -e "  ${DIM}Log: ${LOGFILE}${RESET}"
    echo -e "  ${DIM}Flash: adb push out/target/product/${DEVICE}/lineage-*.zip /sdcard/${RESET}"
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
