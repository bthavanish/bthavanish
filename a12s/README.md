# LineageOS 21 — Samsung Galaxy A12s (SM-A127F/DS)

## Quick Start (Fresh AWS Instance)
```bash
git clone https://github.com/bthavanish/bthavanish.git
cd bthavanish
bash a12s/aws-build.sh
```

## What `aws-build.sh` Does
1. Installs system packages (Ubuntu 22.04)
2. Sets up 16GB swap
3. Installs repo tool
4. Configures git identity
5. Initializes LineageOS 21 repo
6. Creates local manifests (device repos)
7. Syncs sources
8. Applies all patches (clang 14, VINTF, hiddenapi)
9. Builds ROM via ninja (with hiddenapi fix)
10. Creates flashable zip

## Known Build Fixes
- **Clang 14**: kernel Makefile patched for compatibility
- **hiddenapi**: soong ninja bug fixed via `patch_hiddenapi.py`
- **generate_hiddenapi_lists**: assertion downgraded to warning
- **VINTF**: conflicting Samsung manifests removed
- **__uint128_t**: guarded for ILP32 builds

## Manual Build (After Initial Setup)
```bash
cd ~/lineage-a12s
source build/envsetup.sh
lunch lineage_a12s-ap2a-userdebug
bash a12s/build_a12s.sh
```

## Output
- `out/target/product/a12s/lineage-21.0-YYYYMMDD-UNOFFICIAL-a12s.zip`
- All images: boot.img, system.img, vendor.img, product.img, odm.img, dtbo.img, vbmeta.img
