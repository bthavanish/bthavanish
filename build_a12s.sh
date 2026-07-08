#!/bin/bash
# LineageOS 21 Build for Samsung Galaxy A12s (a12s / SM-A127F/DS)
# Unsupported ROM method for crave.io
#
# Setup (one time):
#   crave clone list                                  # find "LOS 21" project ID
#   crave clone create --projectID <ID> /crave-devspaces/Lineage-a12s
#
# Build:
#   cd /crave-devspaces/Lineage-a12s
#   crave run --no-patch -- "bash build_a12s.sh"

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

LOGFILE="build_$(date +%Y%m%d_%H%M%S).log"
TOTAL_STEPS=7

header() {
    echo ""
    echo -e "${CYAN}${BOLD}"
    echo "=========================================="
    echo "  LINEAGEOS 21 - Samsung Galaxy A12s"
    echo "  SM-A127F/DS | Exynos 850 (s5e3830)"
    echo "=========================================="
    echo -e "${RESET}"
    echo ""
}

step() {
    echo -e "${BLUE}${BOLD}[$1/$TOTAL_STEPS]${RESET} ${WHITE}${BOLD}$2${RESET}"
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
LINEAGE_BRANCH="lineage-21"
DEVICE="a12s"
LUNCH_TARGET="lineage_${DEVICE}-userdebug"

# Required environment for Samsung legacy kernel build system
export KERNEL_DEFCONFIG="exynos850-a12snsxx_defconfig"
export TARGET_SOC="exynos850"

REPO_NAMES=(
    "bthavanish/android_kernel_samsung_a12s"
    "bthavanish/android_device_samsung_exynos850-common"
    "bthavanish/android_device_samsung_a12s"
    "bthavanish/android_vendor_samsung_exynos850-common"
    "bthavanish/android_vendor_samsung_a12s"
    "LineageOS/android_hardware_samsung"
    "LineageOS/android_hardware_samsung_slsi-linaro_libbt"
    "LineageOS/android_hardware_samsung_slsi_linaro_libhwjpeg"
)
REPO_PATHS=(
    "kernel/samsung/a12s"
    "device/samsung/exynos850-common"
    "device/samsung/a12s"
    "vendor/samsung/exynos850-common"
    "vendor/samsung/a12s"
    "hardware/samsung"
    "hardware/samsung/slsi/libbt"
    "hardware/samsung/slsi/libhwjpeg"
)
REPO_BRANCHES=(
    "${LINEAGE_BRANCH}"
    "${LINEAGE_BRANCH}"
    "${LINEAGE_BRANCH}"
    "${LINEAGE_BRANCH}"
    "${LINEAGE_BRANCH}"
    "${LINEAGE_BRANCH}"
    "${LINEAGE_BRANCH}"
    "${LINEAGE_BRANCH}"
)
REPO_REMOTES=(
    "github"
    "github"
    "github"
    "github"
    "github"
    "github"
    "github"
    "github"
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
# Step 1: Pre-flight checks
# ============================================
preflight() {
    step 1 "Pre-flight Checks"
    local issues=0

    # Commands
    for cmd in repo git ccache; do
        if command -v "$cmd" >/dev/null 2>&1; then
            ok "$cmd found"
        else
            if [ "$cmd" = "ccache" ]; then
                warn "ccache not found — builds will be slower without it"
            else
                err "$cmd not found"
                issues=$((issues + 1))
            fi
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

    # Kernel userdebug cfg — create if missing to prevent merge_config failure
    local user_cfg="kernel/samsung/a12s/arch/arm64/configs/exynos850_userdebug.cfg"
    if [ -f "$user_cfg" ]; then
        ok "Kernel userdebug.cfg found"
    else
        warn "Kernel userdebug.cfg missing — will be created after sync (Issue 2.1)"
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
    step 2 "Initializing LineageOS ${LINEAGE_BRANCH}"

    rm -rf .repo/local_manifests

    # Use grep with || true so set -e doesn't fire on no-match
    local already_init=0
    if [ -f ".repo/manifest.xml" ]; then
        if grep -q "$LINEAGE_BRANCH" .repo/manifest.xml 2>/dev/null; then
            already_init=1
        else
            warn "Different branch detected, reinitializing"
            rm -rf .repo/manifests .repo/manifest.xml
        fi
    fi

    if [ $already_init -eq 1 ]; then
        ok "Already initialized with ${LINEAGE_BRANCH}"
    else
        echo -e "  ${DIM}Cloning LineageOS manifest...${RESET}"
        if ! repo init -u https://github.com/LineageOS/android.git \
            -b "$LINEAGE_BRANCH" \
            --git-lfs >> "$LOGFILE" 2>&1; then
            die "repo init failed — check log: ${LOGFILE}"
        fi
        ok "Repo initialized"
    fi
    echo ""
}

# ============================================
# Step 3: Local manifests
# ============================================
create_manifests() {
    step 3 "Adding Device Repos"

    mkdir -p .repo/local_manifests

    local count=0
    local total=${#REPO_NAMES[@]}

    for i in $(seq 0 $((total - 1))); do
        count=$((count + 1))
        local name="${REPO_NAMES[$i]}"
        local path="${REPO_PATHS[$i]}"
        local branch="${REPO_BRANCHES[$i]}"
        local remote="${REPO_REMOTES[$i]}"

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
            echo "    <project name=\"${REPO_NAMES[$i]}\" path=\"${REPO_PATHS[$i]}\" remote=\"${REPO_REMOTES[$i]}\" revision=\"${REPO_BRANCHES[$i]}\" />"
        done
        echo "</manifest>"
    } > .repo/local_manifests/a12s.xml

    echo ""
    ok "Local manifests created (${total} repos)"
    echo ""
}

# ============================================
# Step 4: Sync
# ============================================
sync_sources() {
    step 4 "Syncing Sources"

    echo -e "  ${DIM}Using /opt/crave/resync.sh ...${RESET}"
    echo -e "  ${DIM}This may take 30-60 minutes...${RESET}"
    echo ""

    if ! /opt/crave/resync.sh >> "$LOGFILE" 2>&1; then
        err "Sync failed. Check log: ${LOGFILE}"
        die "Source sync failed"
    fi

    # Verify critical files post-sync
    echo -e "  ${DIM}Verifying sync...${RESET}"
    local missing=0
    local critical_files=(
        "build/envsetup.sh"
        "device/samsung/a12s/device.mk"
        "device/samsung/exynos850-common/BoardConfigCommon.mk"
        "vendor/samsung/a12s/a12s-vendor.mk"
        "vendor/samsung/exynos850-common/exynos850-common-vendor.mk"
        "kernel/samsung/a12s/arch/arm64/configs/exynos850-a12snsxx_defconfig"
        "hardware/samsung/Android.bp"
    )
    for f in "${critical_files[@]}"; do
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

    # Create kernel userdebug cfg if it doesn't exist — prevents merge_config
    # from failing when TARGET_BUILD_VARIANT=userdebug (AndroidKernel.mk line 60)
    local user_cfg="kernel/samsung/a12s/arch/arm64/configs/exynos850_userdebug.cfg"
    if [ ! -f "$user_cfg" ]; then
        warn "Creating empty exynos850_userdebug.cfg (required by AndroidKernel.mk)"
        touch "$user_cfg"
        ok "Created ${user_cfg}"
    fi

    echo ""
}

# ============================================
# Step 5: ccache
# ============================================
setup_ccache() {
    step 5 "ccache Setup"

    if command -v ccache >/dev/null 2>&1; then
        export USE_CCACHE=1
        export CCACHE_EXEC
        CCACHE_EXEC=$(command -v ccache)

        # Only set size if the cache is fresh — respect existing config
        if ! ccache -s 2>/dev/null | grep -q "max cache size"; then
            ccache -M 50G >> "$LOGFILE" 2>&1
            ok "ccache: 50GB max size set"
        else
            ok "ccache: using existing config"
        fi

        local cache_dir
        cache_dir=$(ccache -p 2>/dev/null | grep "cache_dir" | awk '{print $4}' || echo "~/.ccache")
        ok "ccache: cache dir = ${cache_dir}"
    else
        warn "ccache not available — skipping (expect slower rebuilds)"
        export USE_CCACHE=0
    fi
    echo ""
}

# ============================================
# Step 6: Build env + lunch
# ============================================
setup_and_lunch() {
    step 6 "Build Environment & Lunch"

    echo -e "  ${DIM}Sourcing build/envsetup.sh...${RESET}"
    # envsetup.sh sets up functions but doesn't return useful exit codes reliably
    # shellcheck source=/dev/null
    if ! source build/envsetup.sh >> "$LOGFILE" 2>&1; then
        die "Failed to source envsetup.sh"
    fi
    ok "envsetup.sh loaded"

    # Re-export kernel vars after envsetup in case it clobbered them
    export KERNEL_DEFCONFIG="exynos850-a12snsxx_defconfig"
    export TARGET_SOC="exynos850"

    echo -e "  ${DIM}Running lunch ${LUNCH_TARGET}...${RESET}"
    if ! lunch "$LUNCH_TARGET" >> "$LOGFILE" 2>&1; then
        err "lunch ${LUNCH_TARGET} failed"
        die "lunch failed — check log: ${LOGFILE}"
    fi
    ok "Target: ${TARGET_PRODUCT:-unknown} (${TARGET_BUILD_VARIANT:-unknown})"
    echo ""
}

# ============================================
# Step 7: Build
# ============================================
build_rom() {
    step 7 "Building ROM"

    echo -e "  ${MAGENTA}This will take 1-3 hours...${RESET}"
    echo -e "  ${DIM}Output: out/target/product/${DEVICE}/lineage-*.zip${RESET}"
    echo -e "  ${DIM}Progress filtered — full output in: ${LOGFILE}${RESET}"
    echo ""

    local start_time=$SECONDS

    # Stream live progress while capturing full log.
    # Filter to show only important lines so crave output stays readable.
    if ! mka bacon 2>&1 | tee -a "$LOGFILE" \
        | grep --line-buffered -E "^\[|FAILED|error:|make:|Building|Compiling|Linking|Package" \
        | grep --line-buffered -v "^$"; then
        err "Build failed — check log: ${LOGFILE}"
        # Print last 40 lines of log to help diagnose
        echo ""
        echo -e "  ${YELLOW}Last 40 lines of build log:${RESET}"
        tail -40 "$LOGFILE" | sed 's/^/    /'
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
    echo -e "  ${DIM}Full log: ${LOGFILE}${RESET}"
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
    setup_ccache
    setup_and_lunch
    build_rom

    local total_time=$(( SECONDS - start_time ))
    local total_mins=$(( total_time / 60 ))
    echo -e "  ${DIM}Total time: ${total_mins} minutes${RESET}"
    echo ""
}

main "$@"
