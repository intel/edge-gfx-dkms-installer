## SR-IOV patch series

The SR-IOV patch files are **not stored in this repository**. They are fetched
at DKMS build time from the remote quilt repository:

```
https://github.com/intel/linux-intel-quilt.git
```

The branch used matches the current installer repo branch (e.g. `6.18/linux`).
The clone is cached at `.cache/linux-intel-quilt/` (gitignored).

### Which patches are applied

`patches/series` is the authoritative list of SR-IOV patches to apply, in order.
Each entry is the filename of a patch that must exist in the quilt repo's
`patches/` directory. To disable a patch temporarily, comment out its line:

```
# 0010-drm-i915-Bypass-gem_set_tiling-and-gem_get_tiling.patch
0011-drm-i915-enable-CCS-on-DG1-and-TGL-for-testing.patch
```

To force a re-fetch of the quilt repo (e.g. after the remote branch is updated):

```bash
QUILT_FORCE_FETCH=1 kernelver=$(uname -r) bash scripts/dkms-pre-build.sh
```

### Persistent configuration

Edit `quilt.conf` at the repo root to permanently change the URL or branch:

```bash
# quilt.conf
QUILT_REPO="${QUILT_REPO:-https://github.com/intel/linux-intel-quilt.git}"
QUILT_BRANCH="${QUILT_BRANCH:-6.18/linux}"
```

Environment variables always take precedence over `quilt.conf`:

```bash
QUILT_REPO=https://github.com/intel/linux-intel-quilt.git \
QUILT_BRANCH=6.18/linux \
kernelver=$(uname -r) bash scripts/dkms-pre-build.sh
```

### Local fallback (offline development)

If `QUILT_PATCHES_DIR` is empty (quilt fetch not run), `apply-patches.sh` falls
back to `patches/sriov-6_18/` for the SR-IOV patches. This allows offline builds
when the local `sriov-6_18/` directory is present.

### Top-level compat patches

The `*.patch` files directly in `patches/` (not in a subdirectory) are local
compat patches applied **after** the SR-IOV series. They are picked up in
lexical order and are not sourced from the quilt repo.

Current compat patches:
- `0001-i915-6.12-build-compat-fixes.patch` — applied only when `kernelver=6.12.*`
- `0001-trace-define_trace-…patch` — applied to all builds
- `0002-i915-iov-sysfs-bin_attr-compat.patch`
- `0003-i915-sriov-export-ns-token.patch`
- `0004-i915-sriov-ns-compat-6.12-6.18.patch`

Patches are applied during DKMS build via `PRE_BUILD` in `dkms.conf`.
