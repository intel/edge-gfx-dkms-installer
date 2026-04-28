# edge-gfx-dkms — Build and Install Guide

Step-by-step instructions for building, installing, verifying, updating, and removing this DKMS module.

**DKMS module name/version:** see `PACKAGE_NAME` / `PACKAGE_VERSION` in `dkms.conf`  
**Supported kernel series:** `6.18.x`  
**Modules installed:** `i915`, `kvmgt` → `/lib/modules/<kver>/updates/dkms/`

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Clone the Repository](#2-clone-the-repository)
3. [Configure the Quilt Patch Source](#3-configure-the-quilt-patch-source)
4. [Register and Build with DKMS](#4-register-and-build-with-dkms)
5. [Verify the Installation](#5-verify-the-installation)
6. [Rebuild After a Kernel Update](#6-rebuild-after-a-kernel-update)
7. [Uninstall](#7-uninstall)
8. [Building a Distributable .deb Package (optional)](#8-building-a-distributable-deb-package-optional)
9. [Next Steps](#9-next-steps)

---

## 1. Prerequisites

### Required packages

```bash
sudo apt update
sudo apt install -y \
    dkms \
    build-essential \
    git \
    linux-headers-$(uname -r)
```

### Kernel version

This DKMS tree is validated against the **6.18.x** series. Confirm the running
kernel before proceeding:

```bash
uname -r
# Expected: 6.18.x
```

If the headers package is not available from your distro, download and install
them manually:

```bash
# Example for kernel 6.18.18 built from kernel.org:
sudo dpkg -i linux-headers-6.18.18_*.deb
```

### Internet access (first build only)

The build fetches two things on first run:

| What | From | Cached at |
|------|------|-----------|
| Upstream kernel tarball (`linux-6.18.19.tar.xz`) | `cdn.kernel.org` | `.cache/` |
| SR-IOV quilt patches | `github.com/intel/linux-intel-quilt` | `.cache/linux-intel-quilt/` |

Both are cached locally after the first build. Subsequent builds are fully
offline unless `QUILT_FORCE_FETCH=1` is set.

---

## 2. Clone the Repository

```bash
cd ~/workspace
git clone <repo-url> drivers.gpu.tools.edge-gfx-dkms-installer
cd drivers.gpu.tools.edge-gfx-dkms-installer
git checkout origin/6.18/linux
```

Verify key files are present:

```bash
ls dkms.conf UPSTREAM_VERSION quilt.conf patches/series
```

---

## 3. Configure the Quilt Patch Source

The quilt repository URL and branch are pre-configured in `quilt.conf`:

```bash
cat quilt.conf
QUILT_REPO="${QUILT_REPO:-https://github.com/intel/linux-intel-quilt.git}"
QUILT_BRANCH="${QUILT_BRANCH:-6.18/linux}"
```

The defaults work out of the box for the standard setup. Edit `quilt.conf` only
if you need to point at a fork or a fixed branch:

```bash
# Example: pin to a specific branch instead of auto-detecting
sed -i 's|QUILT_BRANCH=.*|QUILT_BRANCH="${QUILT_BRANCH:-6.18/linux}"|' quilt.conf
```

---

## 4. Register and Build with DKMS

### Step 1 — Register the source tree

```bash
sudo dkms add .
```

DKMS copies the source tree to `/usr/src/<PACKAGE_NAME>-<PACKAGE_VERSION>/`.

Confirm:

```bash
PKG=$(sed -n 's/^PACKAGE_NAME="\(.*\)"/\1/p' dkms.conf)
VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' dkms.conf)
dkms status "$PKG"
# <pkg>/<ver>: added
```

### Step 2 — Build

```bash
PKG=$(sed -n 's/^PACKAGE_NAME="\(.*\)"/\1/p' dkms.conf)
VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' dkms.conf)
sudo dkms build -m "$PKG" -v "$VER" -k $(uname -r)
```

What happens during the build:

1. `scripts/dkms-pre-build.sh` runs as the DKMS `PRE_BUILD` hook:
   - Downloads `linux-$(cat UPSTREAM_VERSION).tar.xz` from kernel.org (cached).
   - Clones `.cache/linux-intel-quilt/` from the quilt repo (cached after first run).
   - Re-extracts a pristine `kernel-src/drivers/gpu/drm/i915/` snapshot.
   - Applies the SR-IOV patch stack (listed in `patches/series`).
2. DKMS compiles the module against `/lib/modules/<kver>/build`.

Build log is written to `/var/lib/dkms/${PKG}/${VER}/<kver>/build/make.log`.

### Step 3 — Install

```bash
PKG=$(sed -n 's/^PACKAGE_NAME="\(.*\)"/\1/p' dkms.conf)
VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' dkms.conf)
sudo dkms install -m "$PKG" -v "$VER" -k $(uname -r)
```

Steps 2 and 3 can be combined:

```bash
PKG=$(sed -n 's/^PACKAGE_NAME="\(.*\)"/\1/p' dkms.conf)
VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' dkms.conf)
sudo dkms install --force -m "$PKG" -v "$VER" -k $(uname -r)
```

### Using a proxy (optional)

If you are behind an HTTP/HTTPS proxy, set `http_proxy` / `https_proxy` for the
DKMS build/install commands. This matters for the `PRE_BUILD` hook (it downloads
the kernel tarball and fetches the quilt patch repo).

```bash
PROXY=http://<proxy>:<port>

PKG=$(sed -n 's/^PACKAGE_NAME="\(.*\)"/\1/p' dkms.conf)
VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' dkms.conf)

sudo env https_proxy="$PROXY" \
    http_proxy="$PROXY" \
    dkms build -m "$PKG" -v "$VER" -k "$(uname -r)"

sudo env https_proxy="$PROXY" \
    http_proxy="$PROXY" \
    dkms install --force -m "$PKG" -v "$VER" -k "$(uname -r)"
```

---

## 5. Verify the Installation

### DKMS status

```bash
PKG=$(sed -n 's/^PACKAGE_NAME="\(.*\)"/\1/p' dkms.conf)
VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' dkms.conf)

dkms status "$PKG"
# Expected: <pkg>/<ver>, <kver>, <arch>: installed
```

### Module path

```bash
sudo modinfo -F filename i915
# Expected: /lib/modules/<kver>/updates/dkms/i915.ko*

sudo modinfo -F filename kvmgt
# Expected: /lib/modules/<kver>/updates/dkms/kvmgt.ko*
```

The path must be under `updates/dkms/` — not `kernel/drivers/gpu/drm/i915/`.

---

## 6. Rebuild After a Kernel Update

`AUTOINSTALL="yes"` in `dkms.conf` triggers an automatic rebuild when a new
kernel is installed (provided the kernel matches `BUILD_EXCLUSIVE_KERNEL`).

### Manual rebuild for a specific kernel version

```bash
sudo apt install linux-headers-6.18.20

PKG=$(sed -n 's/^PACKAGE_NAME="\(.*\)"/\1/p' dkms.conf)
VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' dkms.conf)

sudo dkms build -m "$PKG" -v "$VER" -k 6.18.20
sudo dkms install -m "$PKG" -v "$VER" -k 6.18.20
```

### Force refresh of the quilt patch cache

```bash
PKG=$(sed -n 's/^PACKAGE_NAME="\(.*\)"/\1/p' dkms.conf)
VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' dkms.conf)

sudo QUILT_FORCE_FETCH=1 dkms build -m "$PKG" -v "$VER" -k "$(uname -r)"
```

---

## 7. Uninstall

### Remove for the running kernel only

```bash
PKG=$(sed -n 's/^PACKAGE_NAME="\(.*\)"/\1/p' dkms.conf)
VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' dkms.conf)

sudo dkms remove -m "$PKG" -v "$VER" -k "$(uname -r)"
```

### Remove for all kernels and deregister

```bash
PKG=$(sed -n 's/^PACKAGE_NAME="\(.*\)"/\1/p' dkms.conf)
VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' dkms.conf)

sudo dkms remove -m "$PKG" -v "$VER" --all
```

---

## 8. Building a Distributable .deb Package (optional)

The `debian/` directory provides a `dh-dkms` scaffold that produces a standard
Debian binary package. The `.deb` ships only the DKMS **source tree** — the
kernel module is compiled locally on the target machine at install time.

### Prerequisites

For a reproducible build (and a self-check install), prefer the helper script:

```bash
./scripts/build-deb.sh --no-install
```

If you need to build behind a proxy:

```bash
PROXY=http://<proxy>:<port>

sudo env https_proxy="$PROXY" \
    http_proxy="$PROXY" \
    ./scripts/build-deb.sh --no-install
```

It prints the exact output path it produced.

Generated/downloaded artifacts (`.cache/`, extracted `kernel-src/` subdirs, log files)
are excluded via `debian/source/options`.

## 9. Next Steps

- Enable SR-IOV and create VFs: see [sriov-guide.md](sriov-guide.md)
- Build troubleshooting: see [build-failures.md](build-failures.md)
