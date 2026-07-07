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
# Configuration
# ============================================
LINEAGE_BRANCH="lineage-23.2"
KERNEL_BRANCH="lineage-22.1"
DEVICE="gta9p"
LUNCH_TARGET="lineage_${DEVICE}-userdebug"
LOGFILE="build_$(date +%Y%m%d_%H%M%S).log"

# All device repos (owner/repo path branch)
REPOS=(
    "bthavanish/android_kernel_samsung_sm6375     kernel/samsung/sm6375       ${KERNEL_BRANCH}"
    "bthavanish/android_device_samsung_gta9p-common device/samsung/gta9p-common ${LINEAGE_BRANCH}"
    "bthavanish/android_device_samsung_gta9p      device/samsung/gta9p        ${LINEAGE_BRANCH}"
    "bthavanish/android_vendor_samsung_gta9p-common vendor/samsung/gta9p-common ${LINEAGE_BRANCH}"
    "bthavanish/android_vendor_samsung_gta9p      vendor/samsung/gta9p        ${LINEAGE_BRANCH}"
)

# ============================================
# Helpers
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $*" | tee -a "$LOGFILE"; }
warn() { echo -e "${YELLOW}[!]${NC} $*" | tee -a "$LOGFILE"; }
err() { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOGFILE"; }
die() { err "$@"; exit 1; }

cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        err "Build failed at line $BASH_LINENO (exit code: $exit_code)"
        err "Check full log: $LOGFILE"
        warn "Partial output may be in out/target/product/${DEVICE}/"
    fi
}
trap cleanup EXIT

# ============================================
# Pre-flight checks
# ============================================
preflight() {
    log "=== Pre-flight checks ==="

    # Check we're in a git repo or have .repo
    if [ ! -d ".repo" ] && [ ! -d ".git" ]; then
        warn "Not in a repo-managed directory. Proceeding anyway (crave may set up later)."
    fi

    # Check essential commands
    for cmd in repo git; do
        if ! command -v "$cmd" &>/dev/null; then
            die "Required command not found: $cmd"
        fi
    done

    # Check crave resync exists
    if [ ! -f "/opt/crave/resync.sh" ]; then
        die "/opt/crave/resync.sh not found. Are you running on crave.io?"
    fi

    # Check disk space (need at least 100GB free)
    local free_gb
    free_gb=$(df -BG --output=avail . 2>/dev/null | tail -1 | tr -d ' G')
    if [ -n "$free_gb" ] && [ "$free_gb" -lt 100 ]; then
        warn "Only ${free_gb}GB free disk space. Build may fail (recommended: 100GB+)."
    fi

    # Check RAM
    local ram_gb
    ram_gb=$(free -g 2>/dev/null | awk '/Mem:/{print $2}' || echo "0")
    if [ "$ram_gb" -lt 16 ]; then
        warn "Only ${ram_gb}GB RAM available. Build may be slow (recommended: 64GB+)."
    fi

    log "Pre-flight checks passed"
}

# ============================================
# Step 1: Initialize LineageOS repo
# ============================================
init_repo() {
    log "=== [1/6] Initializing LineageOS ${LINEAGE_BRANCH} ==="

    # Remove old local manifests
    rm -rf .repo/local_manifests

    # Remove old manifests.xml if it exists and points to different branch
    if [ -f ".repo/manifest.xml" ]; then
        local current_branch
        current_branch=$(grep -oP 'revision="\K[^"]+' .repo/manifest.xml 2>/dev/null | head -1 || true)
        if [ -n "$current_branch" ] && [ "$current_branch" != "$LINEAGE_BRANCH" ]; then
            warn "Existing manifest points to branch: $current_branch (expected: $LINEAGE_BRANCH)"
            warn "Reinitializing repo..."
            rm -rf .repo/manifests .repo/manifest.xml
        fi
    fi

    # Check if repo is already initialized with correct branch
    if [ -f ".repo/manifest.xml" ] && grep -q "$LINEAGE_BRANCH" .repo/manifest.xml 2>/dev/null; then
        log "Repo already initialized with ${LINEAGE_BRANCH}, skipping init"
        return 0
    fi

    # Initialize
    if ! repo init -u https://github.com/LineageOS/android.git \
        -b "$LINEAGE_BRANCH" \
        --git-lfs 2>&1 | tee -a "$LOGFILE"; then
        die "repo init failed. Check network connectivity and branch name."
    fi

    log "Repo initialized successfully"
}

# ============================================
# Step 2: Create local manifests
# ============================================
create_manifests() {
    log "=== [2/6] Creating local manifests ==="

    mkdir -p .repo/local_manifests

    # Build manifest XML
    local manifest="<manifest>\n"

    for repo_info in "${REPOS[@]}"; do
        read -r repo_name repo_path repo_branch <<< "$repo_info"

        # Validate inputs
        if [ -z "$repo_name" ] || [ -z "$repo_path" ] || [ -z "$repo_branch" ]; then
            die "Invalid repo entry: $repo_info"
        fi

        # Check repo exists on GitHub
        if ! git ls-remote --heads "https://github.com/${repo_name}.git" "$repo_branch" &>/dev/null; then
            die "Repository or branch not found: ${repo_name} @ ${repo_branch}"
        fi

        manifest+="    <project name=\"${repo_name}\" path=\"${repo_path}\" remote=\"github\" revision=\"${repo_branch}\" />\n"
        log "  Added: ${repo_name} -> ${repo_path} @ ${repo_branch}"
    done

    manifest+="</manifest>"

    # Write manifest file
    echo -e "$manifest" > .repo/local_manifests/gta9p.xml

    # Validate XML (basic check)
    if ! grep -q "<manifest>" .repo/local_manifests/gta9p.xml; then
        die "Generated manifest XML is malformed"
    fi

    log "Local manifests created successfully"
}

# ============================================
# Step 3: Sync sources
# ============================================
sync_sources() {
    log "=== [3/6] Syncing sources ==="

    # Clean any stale git states that cause resync issues
    find .repo -name ".git" -type d 2>/dev/null | while read -r gitdir; do
        local parent
        parent=$(dirname "$gitdir")
        if [ -d "$parent" ] && [ ! -f "$parent/config" ]; then
            warn "Removing stale git dir: $gitdir"
            rm -rf "$gitdir"
        fi
    done

    # Use crave's resync (required by rules)
    if ! /opt/crave/resync.sh 2>&1 | tee -a "$LOGFILE"; then
        err "resync.sh failed. Trying to diagnose..."

        # Check for common issues
        if grep -q "merge conflict" "$LOGFILE" 2>/dev/null; then
            err "Merge conflict detected. Try: crave run --clean --no-patch -- \"...\""
        fi
        if grep -q "already exists" "$LOGFILE" 2>/dev/null; then
            err "Project already exists. Try removing .repo/local_manifests and resyncing."
        fi

        die "Source sync failed. Check log: $LOGFILE"
    fi

    # Verify critical paths exist after sync
    local critical_paths=(
        "build/envsetup.sh"
        "device/samsung/gta9p/device.mk"
        "device/samsung/gta9p-common/gta9p.mk"
        "vendor/samsung/gta9p/gta9p-vendor.mk"
        "vendor/samsung/gta9p-common/gta9p-common-vendor.mk"
    )

    for path in "${critical_paths[@]}"; do
        if [ ! -f "$path" ]; then
            die "Critical file missing after sync: $path"
        fi
    done

    log "Sources synced successfully"
}

# ============================================
# Step 4: Setup build environment
# ============================================
setup_build_env() {
    log "=== [4/6] Setting up build environment ==="

    # Source build environment
    if ! source build/envsetup.sh 2>&1 | tee -a "$LOGFILE"; then
        die "Failed to source build/envsetup.sh"
    fi

    # Verify lunch function is available
    if ! type lunch &>/dev/null; then
        die "lunch function not available after sourcing envsetup.sh"
    fi

    log "Build environment ready"
}

# ============================================
# Step 5: Select lunch target
# ============================================
select_target() {
    log "=== [5/6] Selecting lunch target: ${LUNCH_TARGET} ==="

    # Check if the product makefile exists
    if [ ! -f "device/samsung/gta9p/lineage_${DEVICE}.mk" ]; then
        die "Product makefile not found: device/samsung/gta9p/lineage_${DEVICE}.mk"
    fi

    # Check AndroidProducts.mk lists our product
    if ! grep -q "lineage_${DEVICE}.mk" "device/samsung/gta9p/AndroidProducts.mk" 2>/dev/null; then
        die "lineage_${DEVICE}.mk not listed in AndroidProducts.mk"
    fi

    # Run lunch
    if ! lunch "$LUNCH_TARGET" 2>&1 | tee -a "$LOGFILE"; then
        err "lunch failed. Available targets:"
        lunch 2>&1 | grep -i "$DEVICE" || warn "No targets matching '${DEVICE}' found"
        die "lunch ${LUNCH_TARGET} failed"
    fi

    # Verify lunch set the right variables
    if [ -z "${TARGET_PRODUCT:-}" ]; then
        die "TARGET_PRODUCT not set after lunch"
    fi

    log "Lunch target selected: ${TARGET_PRODUCT}"
}

# ============================================
# Step 6: Build
# ============================================
build_rom() {
    log "=== [6/6] Starting build ==="
    log "Build command: mka bacon"
    log "Started: $(date)"

    # Check we have a valid .config or will generate one
    if [ ! -f "out/.config" ] && [ ! -f "out/target/product/${DEVICE}/obj/KERNEL_OBJ/.config" ]; then
        warn "No existing kernel config found. Build will generate one."
    fi

    # Run the build
    if ! mka bacon 2>&1 | tee -a "$LOGFILE"; then
        err "Build failed. Common causes:"
        err "  1. Missing proprietary blobs (check vendor/samsung/gta9p/proprietary/)"
        err "  2. SELinux policy errors (check device/samsung/gta9p-common/sepolicy/)"
        err "  3. Missing kernel config (check kernel/samsung/sm6375/)"
        err "  4. Java/JDK version mismatch"
        die "mka bacon failed. Full log: $LOGFILE"
    fi

    log "Build completed: $(date)"
}

# ============================================
# Step 7: Verify output
# ============================================
verify_output() {
    log "=== Verifying build output ==="

    local outdir="out/target/product/${DEVICE}"

    if [ ! -d "$outdir" ]; then
        die "Output directory not found: $outdir"
    fi

    # Check for zip
    local zips
    zips=$(find "$outdir" -maxdepth 1 -name "*.zip" -type f 2>/dev/null)

    if [ -z "$zips" ]; then
        warn "No zip file found in $outdir"
        warn "Checking for other outputs..."

        # Check for partial outputs
        if [ -f "$outdir/obj/ETC/manifest_check_intermediates/manifest.xml" ]; then
            log "Manifest check passed"
        fi
        if [ -f "$outdir/previous_build_config.mk" ]; then
            log "Previous build config exists (incremental build)"
        fi

        die "Build did not produce a zip file"
    fi

    # List all zips
    echo "$zips" | while read -r zip; do
        local size
        size=$(du -h "$zip" | cut -f1)
        log "Output: ${zip} (${size})"
    done

    log "=== BUILD SUCCESSFUL ==="
    log "Flash: out/target/product/${DEVICE}/lineage-*.zip"
}

# ============================================
# Main
# ============================================
main() {
    log "============================================"
    log "LineageOS 23.2 Build for Samsung Galaxy Tab A9+"
    log "Device: ${DEVICE} | Branch: ${LINEAGE_BRANCH}"
    log "Log: ${LOGFILE}"
    log "============================================"

    preflight
    init_repo
    create_manifests
    sync_sources
    setup_build_env
    select_target
    build_rom
    verify_output
}

main "$@"
