# scripts/ (helper tooling)

This directory contains helper scripts for vendoring an upstream i915 snapshot, applying the local patch stack, and building/testing this DKMS tree.

Implementation note: common vendoring logic is shared via `scripts/helpers/lib-i915-vendor.sh` and sourced by the scripts that need it.

## How this relates to DKMS

DKMS builds this repo against an **existing** target kernel build tree (usually `/lib/modules/<kver>/build`). DKMS does **not** reconfigure or rebuild your kernel.

What DKMS **does** in this repo:
- Runs `scripts/dkms-pre-build.sh` as the DKMS `PRE_BUILD` hook (see `dkms.conf`).
  - This regenerates `kernel-src/` from the cached upstream tarball listed by `UPSTREAM_VERSION`.
  - Then it applies patches from `patches/` using `scripts/apply-patches.sh`.
- Then DKMS calls `make -C ${kernel_source_dir} M=<dkms_build_dir>/kernel-src modules` to compile the external module(s).

What DKMS **does not** do:
- It does not download kernel sources.
- It does not change the kernel `.config` used by the target kernel.

## Layout

This directory is split into:
- Top-level `scripts/`: scripts that are part of the DKMS build flow (directly or as children of the DKMS `PRE_BUILD` hook).
- `scripts/helpers/`: maintenance/CI helpers that are **not** invoked by DKMS automatically.

## DKMS build scripts (top-level)

### build-deb.sh
Builds a distributable `.deb` package and optionally installs it to test the
full DKMS build cycle on the running kernel.

Usage:
- `scripts/build-deb.sh` — build, install, and verify module installation
- `scripts/build-deb.sh --no-install` — build the `.deb` only
- `scripts/build-deb.sh --output-dir /path/to/dir` — write `.deb` to a custom directory

What it does:
1. Runs `dpkg-buildpackage --build=binary --no-sign` to produce `edge-gfx-dkms_<ver>-1_all.deb`.
2. Removes any existing DKMS registration and dpkg install for the package.
3. Installs the new `.deb` via `dpkg --install` (triggers postinst DKMS hooks).
4. Runs `dkms build` + `dkms install` for the running kernel with `QUILT_FORCE_FETCH=1`.
5. Verifies `dkms status` shows `installed` and `i915.ko.*` exists under `/lib/modules/<kver>/updates/dkms/`.

### dkms-pre-build.sh
DKMS `PRE_BUILD` hook (see `dkms.conf`).

Responsibilities:
- Ensures `UPSTREAM_VERSION` exists and uses it to select an upstream tarball.
- Re-extracts a pristine i915 snapshot into `kernel-src/` every time (avoids partially patched trees).
- Extracts a few non-i915 files from the same tarball if the patch stack needs them.
- Ensures `include/drm/intel/` headers exist in `kernel-src/` (many distro kernel headers packages omit them).
- Clones/updates the remote quilt patch repository via `scripts/helpers/fetch-quilt-patches.sh`.
- Runs `scripts/apply-patches.sh`.

### apply-patches.sh
Applies the patch stack to `kernel-src/`.

Patch selection:
- **SR-IOV series**: reads `patches/series` for the ordered list of patches, then
  resolves each entry from `QUILT_PATCHES_DIR` (the quilt repo clone). Falls back
  to `patches/sriov-6_18/` if `QUILT_PATCHES_DIR` is empty (offline development).
- **Local compat patches**: applies `patches/*.patch` in lexical order afterward.
- **Series-specific filtering**: if a patch filename mentions only `6.12` or only
  `6.18`, it is applied only when `kernelver` matches that series.

It also maintains `kernel-src/.dkms-patches.state` to avoid re-applying identical patches across repeated builds.

### fetch-kernel-tarball.sh
Downloads `linux-<ver>.tar.xz` from kernel.org into `.cache/` with basic integrity checks.

Usage:
- `./scripts/fetch-kernel-tarball.sh 6.12.77`

## Maintenance helpers (scripts/helpers/)

### helpers/fetch-quilt-patches.sh
Clone or update a shallow copy of the remote quilt patch repository. Called
automatically by `dkms-pre-build.sh`; can also be run manually.

Usage:
- `./scripts/helpers/fetch-quilt-patches.sh <repo_url> <branch> <cache_dir>`
- `QUILT_FORCE_FETCH=1 ./scripts/helpers/fetch-quilt-patches.sh ...` — force re-fetch
- Environment: `QUILT_REPO`, `QUILT_BRANCH`, `QUILT_FORCE_FETCH`

### helpers/update-from-kernel-org-lts.sh
Vendor an i915 snapshot from the latest kernel.org **longterm** release.

Usage:
- `./scripts/helpers/update-from-kernel-org-lts.sh` (uses pinned series in `UPSTREAM_SERIES`, or derives from `uname -r`)
- `./scripts/helpers/update-from-kernel-org-lts.sh --series 6.12`
- `./scripts/helpers/update-from-kernel-org-lts.sh --latest`
- `./scripts/helpers/update-from-kernel-org-lts.sh --unpin`
- `./scripts/helpers/update-from-kernel-org-lts.sh 6.12.77`

### helpers/sync-i915-from-kernel-tree.sh
Syncs i915 sources from an already-checked-out kernel tree on disk.

Usage:
- `./scripts/helpers/sync-i915-from-kernel-tree.sh /path/to/linux [upstream_version]`

### helpers/build-against-kernel-org.sh
Build this external module against a locally-created kernel.org kernel **build tree** (handy for CI/portability testing when you don't have distro headers).

Usage:
- `./scripts/helpers/build-against-kernel-org.sh --series 6.12`
- `./scripts/helpers/build-against-kernel-org.sh --version 6.18.19`
- Optional base config: `--config /path/to/.config`
- Optional cleanup: `--clean`

What it does (high level):
- Downloads and extracts a full kernel.org tarball to `.kernel-src/linux-<ver>/`.
- Creates build output under `.kernel-build/linux-<ver>/`.
- Runs `olddefconfig` (or `defconfig`) and `modules_prepare`.
- Runs `scripts/dkms-pre-build.sh` to regenerate `kernel-src/` and apply patches.
- Builds the external module via `make ... M=$PWD/kernel-src modules`.


### helpers/get-lts-version.py
Queries `https://www.kernel.org/releases.json` and prints the latest **longterm** version.

Usage:
- `python3 ./scripts/helpers/get-lts-version.py` (latest longterm overall)
- `python3 ./scripts/helpers/get-lts-version.py --series 6.12` (latest longterm in series)

### helpers/shellcheck-scan.sh
Runs `shellcheck` across `*.sh` files under the repo (or a provided subdirectory) and prints a pass/warn/fail summary.

Usage:
- `./scripts/helpers/shellcheck-scan.sh` — scan the whole repo
- `./scripts/helpers/shellcheck-scan.sh scripts/` — scan only scripts
- `./scripts/helpers/shellcheck-scan.sh scripts/helpers/` — scan only helper scripts
