# Edge Graphics Dynamic Kernel Module Support (DKMS)

## Introduction
**Dynamic Kernel Module Support (DKMS)** is a framework that automatically rebuilds kernel modules whenever a new kernel is installed, keeping out-of-tree drivers in sync with the running kernel without manual intervention.

This package uses DKMS to build and install Intel graphics kernel modules (`i915`, `xe` *(future)*) with out-of-tree patches that deliver functionality not yet merged into the upstream kernel, bug fixes and updated platforms support by Edge. It sources a vendored kernel.org LTS i915 snapshot and applies a patch stack fetched from a remote quilt repository, ensuring the modules remain current across kernel updates.

## Licence
The Edge Graphics DKMS installer is distributed under the [MIT license](doc/license.md)

## Supported Platforms
* Intel(R) Arrowlake Desktop ARL-S
* Intel(R) ArrowlakeH Mobile ARL-H

## Supported Host Operating System
* Ubuntu 24.04.4 LTS

## Kernel Supported
* Intel Distributed Kernel [v6.18](https://github.com/intel/linux-intel-lts/tree/lts-v6.18.23-linux-260422T014959Z)
* Debian13 Kernel [v6.18](https://packages.debian.org/trixie-backports/debian-installer/kernel-image-6.18.15+deb13-amd64-di)
* Canonical Kernel [v6.18](https://kernel.ubuntu.com/mainline/v6.18)
---

## Quick start

```bash
sudo apt install dkms build-essential git linux-headers-$(uname -r)

git clone <repo-url> drivers.gpu.tools.edge-gfx-dkms-installer
cd drivers.gpu.tools.edge-gfx-dkms-installer
git checkout origin/6.18/linux

PKG=$(sed -n 's/^PACKAGE_NAME="\(.*\)"/\1/p' dkms.conf)
VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' dkms.conf)

sudo dkms add .
sudo dkms build -m "$PKG" -v "$VER"
sudo dkms install -m "$PKG" -v "$VER"
```

Behind a proxy? See [`doc/build-install-guide.md`](doc/build-install-guide.md#using-a-proxy-optional).

### Verification

```bash
sudo modinfo -F filename i915
# Output: /lib/modules/<kver>/updates/dkms/i915.ko
sudo modinfo -F filename kvmgt
# Output: /lib/modules/<kver>/updates/dkms/kvmgt.ko
```

## Documentation

| Document | Contents |
|----------|----------|
| [`doc/build-install-guide.md`](doc/build-install-guide.md) | Build, install, verify, uninstall, rebuild after kernel update, optional `.deb` packaging |
| [`doc/sriov-guide.md`](doc/sriov-guide.md) | Enable SR-IOV at boot + create Virtual Functions (VFs) |
| [`doc/build-failures.md`](doc/build-failures.md) | Build failures quick reference |
| [`doc/documentation.md`](doc/documentation.md) | Extension guide: adding patches, new kernel series, updating snapshots, compat shims, helper scripts reference |
| [`doc/SECURITY.md`](doc/SECURITY.md) | Security policy and vulnerability reporting process |
| [`doc/license.md`](doc/license.md) | Project license (MIT) |
| [`scripts/README.md`](scripts/README.md) | Per-script description of every file under `scripts/` |
| [`patches/README.md`](patches/README.md) | Patch workflow: quilt source, `patches/series`, local compat patches, offline fallback |

---

## How it works

1. **DKMS `PRE_BUILD`** (`scripts/dkms-pre-build.sh`) runs before every build:
   - Downloads `linux-$(cat UPSTREAM_VERSION).tar.xz` from kernel.org (cached in `.cache/`).
   - Clones the SR-IOV quilt patch repo (URL/branch from `quilt.conf`) into `.cache/linux-intel-quilt/`.
   - Re-extracts a pristine `kernel-src/drivers/gpu/drm/i915/` snapshot.
   - Applies the patch stack listed in `patches/series`.
2. **DKMS MAKE** compiles the module against `/lib/modules/<kver>/build`.
3. Modules are installed to `/lib/modules/<kver>/updates/dkms/`, taking precedence over the in-tree driver.

---

## Key configuration files

| File | Purpose |
|------|---------|
| `UPSTREAM_VERSION` | Pinned kernel.org tarball version (e.g. `6.18.19`) |
| `quilt.conf` | Quilt repo URL and branch (`QUILT_REPO`, `QUILT_BRANCH`) |
| `patches/series` | Ordered list of SR-IOV patches to apply |
| `dkms.conf` | DKMS package descriptor (`BUILD_EXCLUSIVE_KERNEL`, `PRE_BUILD`) |
| `debian/` | Debian packaging scaffold — builds a distributable `.deb` via `dpkg-buildpackage` |

---

## Packaging (optional)

See [`doc/build-install-guide.md`](doc/build-install-guide.md) ("Building a Distributable .deb Package").

