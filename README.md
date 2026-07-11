<img src="https://github.com/user-attachments/assets/55c87def-2a8a-47d8-b8b2-224882145b55" align="left" width="200"/>

### Thavanish Brijesh

# Android ROM Build Scripts

Build scripts for custom Android ROMs (LineageOS) on AWS and Crave.io.

## Devices

| Device | Codename | ROM | Script |
|--------|----------|-----|--------|
| Samsung Galaxy A12s | `a12s` | LineageOS 21 (A14) | [`a12s/aws-build.sh`](a12s/aws-build.sh) |
| Samsung Galaxy Tab A9+ | `gta9p` | LineageOS 23.2 (A16) | [`gta9p/server-build.sh`](gta9p/server-build.sh) |

## Quick Start

### AWS (Ubuntu 22.04)
```bash
# Provision EC2 instance
bash aws/provision.sh

# SSH in and run the build
bash a12s/aws-build.sh
```

### Crave.io
```bash
# A12s
cd /crave-devspaces/Lineage-a12s
crave run --no-patch -- "bash a12s/crave-build.sh"

# Tab A9+
cd /crave-devspaces/Lineage-gta9p
crave run --no-patch -- "bash gta9p/crave-build.sh"
```

## Structure

```
a12s/                    Samsung Galaxy A12s (Exynos 850)
  aws-build.sh           AWS build script (complete, tested)
  crave-build.sh         Crave.io build script
gta9p/                   Samsung Galaxy Tab A9+ (SM6375)
  server-build.sh        Full server setup + build
  crave-build.sh         Crave.io build script
aws/
  provision.sh           EC2 instance provisioning
scripts/
  install-opencode.sh    OpenCode installer
```

## Requirements

- **AWS:** c5.4xlarge+ (16 cores), 30GB RAM, 300GB+ disk, Ubuntu 22.04
- **Crave.io:** Any devspace with 16GB+ RAM

## License

Personal build scripts. Use at your own risk.
