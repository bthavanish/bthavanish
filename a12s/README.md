# Samsung Galaxy A12s (SM-A127F/DS) — LineageOS 21

Build LineageOS 21 (Android 14) for the Samsung Galaxy A12s on AWS.

## Specs
- **SoC:** Samsung Exynos 850 (s5e3830)
- **Kernel:** 4.19 (Samsung)
- **RAM:** 4GB / 6GB
- **Android:** 14 (LineageOS 21)

## Quick Start (AWS)

```bash
# One-liner on a fresh Ubuntu 22.04 instance:
bash <(curl -fsSL https://raw.githubusercontent.com/bthavanish/bthavanish/main/a12s/aws-build.sh)
```

### Requirements
- Ubuntu 22.04 LTS
- 16+ CPU cores (c5.4xlarge or similar)
- 30GB+ RAM (or 16GB swap — script sets this up)
- 300GB+ free disk space

## What the Script Does
1. Installs all build dependencies
2. Sets up 16GB swap
3. Installs the `repo` tool
4. Syncs LineageOS 21 + device repos
5. Applies kernel patches (clang 14 compatibility, stpcpy, readelf paths)
6. Builds with `mka bacon` (two-stage: bootimage first, then bacon)

## Output
Flashable zip at: `~/lineage-a12s/out/target/product/a12s/lineage-*.zip`

## Build Logs
Full build log: `~/build_a12s_*.log`
