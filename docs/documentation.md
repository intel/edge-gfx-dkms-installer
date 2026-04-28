# edge-gfx-dkms — Extension Guide

How to extend `drivers.gpu.tools.edge-gfx-dkms-installer` to support new patches,
new kernel series, and new i915 upstream snapshots.

> **DKMS module name:** see `PACKAGE_NAME` in `dkms.conf`  
> **DKMS module version:** see `PACKAGE_VERSION` in `dkms.conf`  
> **Upstream i915 series:** `6.18.x` (pinned in `UPSTREAM_VERSION`)  

---

## Table of Contents

1. [Repository Overview](#1-repository-overview)
2. [Key Files Reference](#2-key-files-reference)
3. [How the Build Works (DKMS Flow)](#3-how-the-build-works-dkms-flow)
4. [Updating to a New i915 Upstream Snapshot](#4-updating-to-a-new-i915-upstream-snapshot)
5. [Extending to a New Kernel Series](#5-extending-to-a-new-kernel-series)
6. [Adding or Modifying Patches](#6-adding-or-modifying-patches)
7. [Adding Compatibility Shims](#7-adding-compatibility-shims)
8. [Installing and Managing the DKMS Module](#8-installing-and-managing-the-dkms-module)
9. [Building Without DKMS (Manual / CI)](#9-building-without-dkms-manual--ci)
10. [Helper Scripts Reference](#10-helper-scripts-reference)
11. [Troubleshooting](#11-troubleshooting)
12. [Building a Distributable .deb Package](#12-building-a-distributable-deb-package)

---

## 1. Repository Overview

```
drivers.gpu.tools.edge-gfx-dkms-installer/
├── dkms.conf                        # DKMS package descriptor
├── UPSTREAM_VERSION                 # Pinned upstream kernel version (e.g. 6.18.19)
├── UPSTREAM_SERIES                  # Optional: pins the kernel.org LTS series (e.g. 6.18)
├── quilt.conf                       # Persistent QUILT_REPO / QUILT_BRANCH defaults
├── Makefile                         # Top-level external-module wrapper (sets LINUXINCLUDE)
├── debian/                          # Debian packaging scaffold (dh-dkms)
│   ├── control                      # Package metadata and dependencies
│   ├── rules                        # Build rules (overrides dh_auto_build/install)
│   ├── changelog                    # Debian version history
│   ├── copyright                    # GPL-2.0-only
│   ├── edge-gfx-dkms.dkms           # dh_dkms entry point → dkms.conf
│   └── source/
│       ├── format                   # 3.0 (quilt)
│       └── options                  # Excludes generated artifacts from diff
├── kernel-src/                      # Vendored i915 snapshot (mostly git-ignored, re-extracted on build)
│   ├── Makefile                     # Internal external-module wrapper for DKMS
│   ├── drivers/gpu/drm/i915/        # i915 driver source (from kernel.org tarball)
│   ├── include/
│   │   ├── config.h                 # Compat shims and DKMS_MODULE_SOURCE_DIR helper
│   │   └── drm/                     # DRM headers (including intel/ if present in tarball)
│   └── compat/include/              # Extra compat headers committed to the repo
│       └── drm/clients/drm_client_setup.h
├── patches/
│   ├── README.md                    # Patch conventions and quilt fetch details
│   ├── series                       # Ordered list of SR-IOV patches to apply (from quilt repo)
│   ├── sriov-6_18/                  # Local fallback: SR-IOV patches for offline development
│   ├── 0001-i915-6.12-build-compat-fixes.patch  # Applied only when kernelver=6.12.*
│   ├── 0001-trace-define_trace-*.patch           # Top-level compat patches (all kernels)
│   ├── 0002-i915-iov-sysfs-bin_attr-compat.patch
│   ├── 0003-i915-sriov-export-ns-token.patch
│   └── 0004-i915-sriov-ns-compat-6.12-6.18.patch
└── scripts/
    ├── README.md                    # Script documentation
    ├── apply-patches.sh             # Applies the patch stack to kernel-src/
    ├── dkms-pre-build.sh            # DKMS PRE_BUILD hook (re-extracts + patches)
    ├── fetch-kernel-tarball.sh      # Downloads linux-<ver>.tar.xz from kernel.org
    └── helpers/                     # Maintenance/CI helpers (not invoked by DKMS)
        ├── lib-i915-vendor.sh       # Shared extraction/vendoring functions
        ├── update-from-kernel-org-lts.sh  # One-shot vendor update from kernel.org
        ├── sync-i915-from-kernel-tree.sh  # Vendor from a local kernel checkout
        ├── build-against-kernel-org.sh    # Build/test against a kernel.org build tree
        ├── fetch-quilt-patches.sh         # Clone/cache the remote quilt patch repo
        └── get-lts-version.py             # Queries kernel.org releases.json for latest LTS
```

### Modules built

| Index | Module | Source path inside `kernel-src/` |
|-------|--------|-----------------------------------|
| 0 | `i915` | `drivers/gpu/drm/i915/` |
| 1 | `kvmgt` | `drivers/gpu/drm/i915/` (GVT-g SR-IOV helper) |

Both are installed to `/updates/` so they override the in-tree i915 when loaded.

---

## 2. Key Files Reference

### `UPSTREAM_VERSION`

Single line: the kernel.org tarball version used to vendor `kernel-src/`. Set by
`scripts/helpers/update-from-kernel-org-lts.sh` at vendor time and re-read every
DKMS `PRE_BUILD` invocation by `scripts/dkms-pre-build.sh`.

```
6.18.19
```

To upgrade: update this file or run `update-from-kernel-org-lts.sh`.

### `UPSTREAM_SERIES` (optional)

Single line: the LTS series tracked by the auto-update helpers (e.g. `6.18`).
Written by `update-from-kernel-org-lts.sh --series X.Y`. If absent, the helpers
derive the series from `uname -r`.

### `quilt.conf`

Sourced by `scripts/dkms-pre-build.sh` on every DKMS build. Defines the default
URL and branch for the remote SR-IOV quilt patch repository. Environment
variables always take precedence over values in this file.

```bash
QUILT_REPO="${QUILT_REPO:-https://github.com/intel/linux-intel-quilt.git}"
QUILT_BRANCH="${QUILT_BRANCH:-6.18/linux}"
```

To point at a fork or a different branch permanently, edit this file and commit
the change. To override for a single run without editing the file:

```bash
QUILT_REPO=https://github.com/myfork/linux-intel-quilt.git \
QUILT_BRANCH=my-branch \
PKG=$(sed -n 's/^PACKAGE_NAME="\(.*\)"/\1/p' dkms.conf) \
VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' dkms.conf) \
sudo dkms build -m "$PKG" -v "$VER" -k $(uname -r)
```

### `dkms.conf`

Controls DKMS behaviour. Refer to the actual `dkms.conf` in this repo for canonical values.

Key points:
- `kernel_source_dir` — DKMS-provided variable pointing to `/lib/modules/<kver>/build`
- `BUILD_EXCLUSIVE_KERNEL` — restricts automated installs to 6.18.x series
- `PRE_BUILD` — runs on every build, re-extracts the pristine snapshot and applies patches

### `kernel-src/include/config.h`

Committed compat header included by every compilation unit (via `-include` in
both `Makefile`s). Contains:
- `DKMS_MODULE_SOURCE_DIR` macro and `MODULE_ABS_PATH()` helper for trace events
- Small `#if LINUX_VERSION_CODE < KERNEL_VERSION(x,y,z)` stubs for APIs that
  moved between kernel releases (e.g. `ratelimit_state_get_miss`, `rdmsrq_safe`,
  `poll_timeout_us_atomic`, `range_overflows_t`, `BIT_U32/16/8`, `GENMASK_U32/16/8`)

### `kernel-src/compat/include/`

Extra compat headers that the i915 snapshot needs but newer distro kernels may
not provide in their headers package:

- `drm/clients/drm_client_setup.h` — `drm_client_setup()` wrapper stub

### `patches/series`

The authoritative ordered list of SR-IOV patches to apply. Each line is a
patch filename that must exist in the quilt repo's `patches/` directory
(see `scripts/helpers/fetch-quilt-patches.sh`). This file drives both quilt
fetches and local fallback builds.

Useful for temporarily disabling a patch without modifying the quilt repo:

```
# Temporarily disabled:
# 0010-drm-i915-Bypass-gem_set_tiling-and-gem_get_tiling.drm
0011-drm-i915-enable-CCS-on-DG1-and-TGL-for-testing.drm
…
```

---

## 3. How the Build Works (DKMS Flow)

```
dkms build <PACKAGE_NAME>/<PACKAGE_VERSION> -k <kver>
  │
  ├─ PRE_BUILD: scripts/dkms-pre-build.sh
  │    ├─ 1. prepare_kernel_build_tree()
  │    │      └─ Copies /boot/config-<kver> → /lib/modules/<kver>/build/.config if missing
  │    │         Runs olddefconfig + modules_prepare if autoconf.h missing
  │    │
  │    ├─ 2. version=$(cat UPSTREAM_VERSION)               # e.g. 6.18.19
  │    │
  │    ├─ 3. scripts/fetch-kernel-tarball.sh <version>
  │    │      └─ Downloads linux-6.18.19.tar.xz to .cache/
  │    │         (cached; integrity-checked with xz -t)
  │    │
  │    ├─ 4. extract_i915_from_tarball()                   # from lib-i915-vendor.sh
  │    │      ├─ rm -rf kernel-src/drivers/gpu/drm/i915/   # pristine every time
  │    │      ├─ tar extract → kernel-src/drivers/gpu/drm/i915/
  │    │      ├─ tar extract → kernel-src/drivers/platform/x86/intel_ips.h (if present)
  │    │      └─ Patch i915/Makefile: ensure "obj-m += i915.o"
  │    │
  │    ├─ 5. ensure_from_tarball() for sriov-specific extra files
  │    │      └─ tar extract → kernel-src/Documentation/gpu/i915.rst
  │    │
  │    ├─ 6. Ensure kernel-src/include/drm/intel/ headers (extract from tarball if needed)
  │    │
  │    ├─ 7. scripts/helpers/fetch-quilt-patches.sh <url> <branch> .cache/linux-intel-quilt
  │    │      ├─ Clone with --depth=1 if not cached
  │    │      ├─ Fetch + reset if QUILT_FORCE_FETCH=1 or branch changed
  │    │      └─ Outputs .cache/linux-intel-quilt/patches/ path → QUILT_PATCHES_DIR
  │    │
  │    └─ 8. scripts/apply-patches.sh <root_dir> <kernelver> <quilt_patches_dir>
  │           ├─ Collect SR-IOV patches: read patches/series, resolve each from QUILT_PATCHES_DIR
  │           │    (fallback: patches/sriov-6_18/ if QUILT_PATCHES_DIR is empty)
  │           ├─ Collect patches/*.patch (local compat patches, lexical order)
  │           ├─ Filter: 6.12-only patches are skipped on 6.18, and vice versa
  │           ├─ Skip if .dkms-patches.state matches current sha256 set
  │           └─ patch -p1 --forward (handles already-applied gracefully)
  │
  └─ MAKE: make -C /lib/modules/<kver>/build M=<dkms_tree>/kernel-src modules
```

The `kernel-src/` directory is **always re-extracted from the cached tarball**
on each DKMS build invocation. This guarantees patches are always applied to a
clean baseline and never double-applied.

---

## 4. Updating to a New i915 Upstream Snapshot

### Within the same kernel series (e.g. 6.18.18 → 6.18.19)

```bash
cd ~/workspace/drivers.gpu.tools.edge-gfx-dkms-installer

# Download the new tarball and re-vendor kernel-src/
./scripts/helpers/update-from-kernel-org-lts.sh 6.18.19

# Verify the snapshot applied cleanly with the patch stack:
./scripts/helpers/build-against-kernel-org.sh --version 6.18.19
```

`update-from-kernel-org-lts.sh` will:
1. Download `linux-6.18.19.tar.xz` to `.cache/`
2. Re-extract `kernel-src/drivers/gpu/drm/i915/` from the new tarball
3. Write `6.18.19` to `UPSTREAM_VERSION`

You can then commit:
```bash
git add UPSTREAM_VERSION
git commit -m "vendor: update i915 snapshot to 6.18.19"
```

The patch state file `kernel-src/.dkms-patches.state` is gitignored — it is
recreated on every DKMS build.

### Auto-track latest LTS in a series

```bash
# Fetch and pin the latest 6.18.x from kernel.org automatically
./scripts/helpers/update-from-kernel-org-lts.sh --series 6.18

# Or without pinning (uses uname -r to derive the series):
./scripts/helpers/update-from-kernel-org-lts.sh

# Track the newest LTS overall (ignores UPSTREAM_SERIES):
./scripts/helpers/update-from-kernel-org-lts.sh --latest

# Remove the UPSTREAM_SERIES pin:
./scripts/helpers/update-from-kernel-org-lts.sh --unpin
```

### From a local kernel checkout

If you have already cloned or built a kernel tree locally:

```bash
./scripts/helpers/sync-i915-from-kernel-tree.sh /path/to/linux 6.18.18
```

This uses `rsync` to copy `drivers/gpu/drm/i915/` into `kernel-src/` without
downloading anything.

---

## 5. Extending to a New Kernel Series

### Step 1 — Update `BUILD_EXCLUSIVE_KERNEL` in `dkms.conf`

The current exclusivity regex allows only `6.18.x`:

```bash
BUILD_EXCLUSIVE_KERNEL="^6\\.18\\..*"
```

To support an additional series (e.g. add 6.12.x), broaden it:

```bash
BUILD_EXCLUSIVE_KERNEL="^6\\.(12|18)\\..*"
```

Or to allow any 6.x:

```bash
BUILD_EXCLUSIVE_KERNEL="^6\\..*"
```

### Step 2 — Update the version guard in `scripts/dkms-pre-build.sh`

The script has a matching early exit:

```bash
supported_kver_re='^6\.18\..*'
kver_for_check="${kernelver:-${KERNELVER:-}}"
if [[ -n "${kver_for_check}" && ! "${kver_for_check}" =~ ${supported_kver_re} ]]; then
   echo "WARNING: edge-gfx-dkms supports only 6.18.x kernels; refusing to build…" >&2
    exit 3
fi
```

Change `supported_kver_re` to match the new series:

```bash
supported_kver_re='^6\.(12|18)\..*'
```

### Step 3 — Vendor an i915 snapshot for the new series

The snapshot in `kernel-src/` must come from a kernel whose i915 source is
compatible with the patches you want to apply:

```bash
./scripts/helpers/update-from-kernel-org-lts.sh --series 6.12
```

This writes `6.12.xx` to `UPSTREAM_VERSION`. **The tarball series must match the
kernel the module will be built against** — building a 6.18 i915 snapshot against
a 6.12 kernel header tree typically fails due to API differences.

### Step 4 — Add series-specific compat patches

See [Section 6](#6-adding-or-modifying-patches) for the naming convention that
scopes patches to a specific kernel series (e.g. `0001-i915-6.12-build-compat-fixes.patch`
is automatically applied only on `kernelver=6.12.*`).

### Step 5 — Test the new series build

```bash
./scripts/helpers/build-against-kernel-org.sh --series 6.12 --config /boot/config-$(uname -r)
```

### Step 6 — Commit the changes

```bash
git add UPSTREAM_VERSION UPSTREAM_SERIES dkms.conf scripts/dkms-pre-build.sh patches/
git commit -m "support: add 6.12 series"
```

---

## 6. Adding or Modifying Patches

### Patch sources and application order

Patches are applied in this order by `scripts/apply-patches.sh`:

1. **SR-IOV series** (from quilt repo) — applied first, to all builds  
   - `patches/series` lists the patches to apply in order  
   - Each entry is fetched from `.cache/linux-intel-quilt/patches/` (cloned from
     `https://github.com/intel/linux-intel-quilt.git` on the matching branch)  
   - Offline fallback: if the quilt cache is absent, looks in `patches/sriov-6_18/`  
2. **Local compat patches** — `patches/*.patch` applied after the SR-IOV series  
   - Applied in lexical order; `patches/series` is not used for this step

### Kernel-series scoping by filename

`apply-patches.sh` filters patches by filename automatically:

| Filename contains | Applied to |
|-------------------|------------|
| `6.12` only (not `6.18`) | `kernelver=6.12.*` only |
| `6.18` only (not `6.12`) | `kernelver=6.18.*` only |
| both, or neither | all builds |

Example: `0001-i915-6.12-build-compat-fixes.patch` contains `6.12` and not
`6.18`, so it is only applied when building against a 6.12.x kernel.

### Adding a new patch to the SR-IOV series

SR-IOV patches are sourced from the quilt repo. To add a new one:

1. Add the patch file to the quilt repo's `patches/` directory on the matching
   branch and push it.

2. Add the filename to `patches/series` in this repo at the desired position:
   ```
   …
   0066-drm-i915-move-sriov-selftest-buffer-out-of-stack.drm
   0067-drm-i915-my-feature.drm
   ```

3. Force a cache refresh and test application:
   ```bash
   QUILT_FORCE_FETCH=1 kernelver=$(uname -r) bash scripts/dkms-pre-build.sh
   ```

4. Do a full DKMS build cycle to confirm it applies and compiles:
   ```bash
   PKG=$(sed -n 's/^PACKAGE_NAME="\(.*\)"/\1/p' dkms.conf)
   VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' dkms.conf)
   sudo dkms remove -m "$PKG" -v "$VER" --all
   sudo dkms add .
   sudo dkms build -m "$PKG" -v "$VER" -k $(uname -r)
   ```

### Adding a new top-level compat patch

Top-level patches (in `patches/` directly, not a subdirectory) are applied
**after** the SR-IOV series and are intended for out-of-tree build fixes.

Naming convention: include the target kernel version if series-scoped.

```bash
# Applies only on 6.18.x kernels:
patches/0005-i915-sriov-ns-compat-6.18-only.patch

# Applies to all kernels (no version in name):
patches/0005-i915-sriov-fix-build-all-kernels.patch
```

### Temporarily disabling a patch

Add a comment to `patches/series`:

```
# 0010-drm-i915-Bypass-gem_set_tiling-and-gem_get_tiling.drm
0011-drm-i915-enable-CCS-on-DG1-and-TGL-for-testing.drm
```

The commented line is ignored. The patch stays in the quilt repo and can be
re-enabled by removing the `#`.

### Patch idempotency

`apply-patches.sh` uses `kernel-src/.dkms-patches.state` (a sha256 digest of all
selected patches) to skip re-application across repeated DKMS builds. This state
file is gitignored and is always cleared when `dkms-pre-build.sh` re-extracts the
snapshot. If a patch fails because it is already applied, the script detects the
reverse and silently continues — it does not fail the build.

---

## 7. Adding Compatibility Shims

There are two places for compatibility code:

### `kernel-src/include/config.h` — inline C shims

For small API backports that fit in a header (inline functions, `#define`
wrappers, type aliases). This file is always included via `-include config.h` in
both top-level `Makefile`s, so the guards are available in every translation unit.

Pattern:

```c
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 20, 0)
#ifndef some_new_api
static inline int some_new_api(struct foo *f) { return f->old_field; }
#endif
#endif
```

### `kernel-src/compat/include/` — full stub headers

For missing header files that the i915 driver `#include`s by path. Committed to
the repo and never re-extracted from the upstream tarball.

Example — if a new i915 snapshot starts including
`<drm/clients/some_new_client.h>` which is absent from older distro kernel
headers:

```bash
mkdir -p kernel-src/compat/include/drm/clients
cat > kernel-src/compat/include/drm/clients/some_new_client.h <<'EOF'
/* compat stub */
#pragma once
static inline void some_new_client_setup(struct drm_device *dev,
                                         const struct drm_client_funcs *funcs) {}
EOF
git add kernel-src/compat/include/drm/clients/some_new_client.h
git commit -m "compat: add stub for some_new_client.h (added in kernel 6.20)"
```

The `compat/include/` directory is added via `-idirafter` in both `Makefile`s,
meaning it is searched **after** real kernel headers, so the stub is used only if
the system headers do not already provide the file.

---

## 8. Installing and Managing the DKMS Module

These operational steps are documented in the build docs (kept separate to avoid duplication here):

- DKMS build/install (and optional `.deb` packaging): `doc/build-install-guide.md`
- Verify module override: `doc/build-install-guide.md`
- Enable SR-IOV boot params + create VFs: `doc/sriov-guide.md`
- Uninstall: `doc/build-install-guide.md`
- Rebuild after kernel update: `doc/build-install-guide.md`

---

## 9. Building Without DKMS (Manual / CI)

### Against the running kernel's headers

```bash
cd ~/workspace/drivers.gpu.tools.edge-gfx-dkms-installer

# Step 1: vendor (or ensure UPSTREAM_VERSION is current)
./scripts/helpers/update-from-kernel-org-lts.sh

# Step 2: run pre-build manually to extract + patch
kernelver=$(uname -r) bash scripts/dkms-pre-build.sh

# Step 3: build
make -C /lib/modules/$(uname -r)/build M=$PWD/kernel-src modules
```

### Against a kernel.org build tree (no distro headers required)

Use `build-against-kernel-org.sh` — it downloads a full kernel.org source,
builds a minimal build tree, then builds the external module against it:

```bash
# Latest longterm in 6.18 series
./scripts/helpers/build-against-kernel-org.sh --series 6.18

# Explicit version
./scripts/helpers/build-against-kernel-org.sh --version 6.18.19

# Provide your running kernel's config to avoid CONFIG_* surprises
./scripts/helpers/build-against-kernel-org.sh --version 6.18.19 \
    --config /boot/config-$(uname -r)

# With parallelism
./scripts/helpers/build-against-kernel-org.sh --version 6.18.19 -j $(nproc)

# Clean up intermediate build trees and start fresh
./scripts/helpers/build-against-kernel-org.sh --version 6.18.19 --clean
```

Kernel source is downloaded to `.kernel-src/linux-<ver>/` and build output goes
to `.kernel-build/linux-<ver>/`. Both directories are gitignored.

---

## 10. Helper Scripts Reference

### `scripts/fetch-kernel-tarball.sh <version>`

Downloads `linux-<version>.tar.xz` from `cdn.kernel.org` to `.cache/`. Validates
integrity with `xz -t` and re-downloads if the cached copy is corrupt. Returns
the path to the tarball on stdout (stderr carries progress messages).

```bash
tarball=$(./scripts/fetch-kernel-tarball.sh 6.18.19)
echo "Tarball at: $tarball"
```

Controlled by `CACHE_DIR` environment variable (defaults to `.cache/`).

### `scripts/helpers/fetch-quilt-patches.sh <repo_url> <branch> <cache_dir>`

Clones (or updates) the remote quilt repository into `<cache_dir>` using a
shallow clone (`--depth=1`). Outputs the path to `<cache_dir>/patches/` on
stdout so `dkms-pre-build.sh` can capture it via command substitution.

```bash
# Typically called by dkms-pre-build.sh; can also be invoked manually:
./scripts/helpers/fetch-quilt-patches.sh \
    https://github.com/intel/linux-intel-quilt.git \
    6.18/linux .cache/linux-intel-quilt
```

Behaviour:
- **First run:** clones with `--depth=1 --branch <branch>`.
- **Subsequent runs:** uses cached clone unless the branch changed or
  `QUILT_FORCE_FETCH=1` is set.
- **Branch switch:** fetches the new branch and checks it out.

Environment overrides: `QUILT_REPO`, `QUILT_BRANCH`, `QUILT_FORCE_FETCH`.

### `scripts/apply-patches.sh <root_dir> [kernelver] [quilt_patches_dir]`

Applies the full patch stack to `kernel-src/`. The third argument is the path
to the quilt repo's `patches/` directory (output of `fetch-quilt-patches.sh`).
If omitted, falls back to `patches/sriov-6_18/` for offline use.

```bash
./scripts/apply-patches.sh . 6.18.19 .cache/linux-intel-quilt/patches
```

State file: `kernel-src/.dkms-patches.state` — sha256 of all applied patches.
Identical state → patches are skipped (idempotent).

### `scripts/helpers/lib-i915-vendor.sh`

Bash library sourced by other scripts. Provides:

- `extract_i915_from_tarball(root_dir, kernel_src_dir, tarball_path, version, verbose)`  
  Extracts `drivers/gpu/drm/i915/` and optional `intel_ips.h` from the tarball.
  Always starts from a clean slate (deletes existing files first). Writes
  `UPSTREAM_VERSION`. Patches `i915/Makefile` to add `obj-m += i915.o` if absent.

- `_i915_patch_makefile_objm(makefile, verbose)`  
  Internal: inserts `obj-m += i915.o` before the first non-comment/non-blank line
  in the Makefile.

### `scripts/helpers/update-from-kernel-org-lts.sh`

Full vendor-update workflow. Downloads the tarball, extracts i915, updates
`UPSTREAM_VERSION`. Supports `--series`, `--latest`, `--unpin`, and an explicit
version positional argument. Uses `get-lts-version.py` to query kernel.org unless
an explicit version is given.

### `scripts/helpers/sync-i915-from-kernel-tree.sh <kernel_tree> [version]`

Syncs `kernel-src/` from a local kernel checkout via `rsync`. Does not download
anything. Useful when you have a local git tree with custom patches applied.

```bash
./scripts/helpers/sync-i915-from-kernel-tree.sh ~/linux-6.18 6.18.19
```

### `scripts/helpers/build-against-kernel-org.sh`

See [Section 9](#9-building-without-dkms-manual--ci). Downloads a full kernel
source, builds a minimal build tree with `olddefconfig` + `modules_prepare`, runs
`dkms-pre-build.sh`, then builds the module externally.

### `scripts/helpers/get-lts-version.py [--series X.Y]`

Queries `https://www.kernel.org/releases.json` and prints the latest longterm
version. Used internally by `update-from-kernel-org-lts.sh`.

```bash
python3 ./scripts/helpers/get-lts-version.py            # latest LTS overall
python3 ./scripts/helpers/get-lts-version.py --series 6.18
```

---

## 11. Troubleshooting

### DKMS build exits with code 3 — wrong kernel series

```
WARNING: edge-gfx-dkms supports only 6.18.x kernels; refusing to build for 6.12.0.
```

Either use a supported kernel or expand the series guard — see
[Section 5, Step 2](#step-2--update-the-version-guard-in-scriptsdkms-pre-buildsh).

### `patch: Hunk #N FAILED` during `apply-patches.sh`

The i915 snapshot in `UPSTREAM_VERSION` has diverged from the version the patches
were written against. Options:

1. **Update the snapshot** to match the version the patch targets:
   ```bash
   ./scripts/helpers/update-from-kernel-org-lts.sh 6.18.12
   ```

2. **Re-roll the failing patch** in the quilt repo against the new snapshot, then
   force a cache refresh:
   ```bash
   # Edit the patch in the quilt repo, then:
   QUILT_FORCE_FETCH=1 kernelver=$(uname -r) bash scripts/dkms-pre-build.sh
   ```

3. **Temporarily disable** the failing patch in `patches/series`.

### `Missing include/drm/intel/ headers`

The tarball at `UPSTREAM_VERSION` does not contain `include/drm/intel/pciids.h`.
This was added starting around 6.12. Options:
- Upgrade `UPSTREAM_VERSION` to a release that contains those headers, or
- Add a stub header to `kernel-src/compat/include/drm/intel/pciids.h`

### `cannot stat '/lib/modules/<kver>/build/.config'`

The kernel headers package is incomplete. `dkms-pre-build.sh` will copy
`/boot/config-<kver>` automatically if available. If not:

```bash
sudo apt install linux-headers-<kver>
# If still missing .config:
sudo cp /boot/config-$(uname -r) /lib/modules/<kver>/build/.config
```

### DKMS build fails on `canonical-certs.pem`

Ubuntu's `.config` references `/etc/ssl/certs/…`. Clear the signing config:

```bash
sudo sed -i 's|^CONFIG_SYSTEM_TRUSTED_KEYS=.*|CONFIG_SYSTEM_TRUSTED_KEYS=""|' \
    /lib/modules/<kver>/build/.config
sudo sed -i 's|^CONFIG_SYSTEM_REVOCATION_KEYS=.*|CONFIG_SYSTEM_REVOCATION_KEYS=""|' \
    /lib/modules/<kver>/build/.config
```

### `modinfo i915` still shows in-tree driver after install

```bash
PKG=$(sed -n 's/^PACKAGE_NAME="\(.*\)"/\1/p' dkms.conf)
dkms status "$PKG"               # confirm installed status
depmod -a                         # rebuild module dependency map
modinfo i915 | grep filename      # should show updates/dkms/i915.ko[.zst]
```

If the in-tree driver takes precedence, check `modprobe` configuration:

```bash
cat /etc/modprobe.d/i915.conf 2>/dev/null   # should not blacklist i915
ls /lib/modules/$(uname -r)/updates/dkms/    # confirm i915.ko[.zst] exists
```

### i915 module loads but SR-IOV VFs unavailable

Confirm GuC and max_vfs boot parameters are set:

```bash
cat /proc/cmdline | grep -o 'i915\.[^ ]*'
# Should contain: i915.enable_guc=3 i915.max_vfs=7
```

Check SR-IOV capability:

```bash
cat /sys/bus/pci/devices/0000:00:02.0/sriov_totalvfs   # must be > 0
echo 2 | sudo tee /sys/bus/pci/devices/0000:00:02.0/sriov_numvfs
```

### Stale `.dkms-patches.state` after modifying a patch

The state file is keyed by sha256 of all applied patches. Any patch modification
automatically invalidates it on the next build. If you need to force re-application
immediately:

```bash
rm kernel-src/.dkms-patches.state
```

---

## 12. Building a Distributable .deb Package

See `doc/build-install-guide.md` ("Building a Distributable .deb Package").
