# Build Failures — Quick Reference

---

## Exit code 3 — wrong kernel series

```
WARNING: <package> supports only <series>; refusing to build for <kver>.
```

Install a supported kernel or update the series guard (see `BUILD_EXCLUSIVE_KERNEL`
in `dkms.conf` and the matching check in `scripts/dkms-pre-build.sh`).

## `git clone` / `git fetch` fails during quilt fetch

The pre-build hook exits immediately. Check network access and the URL in
`quilt.conf`:

```bash
cat quilt.conf

git ls-remote "${QUILT_REPO}" HEAD
```

## Missing patch file

A filename listed in `patches/series` was not found in the quilt repo. The cache
may be stale or `patches/series` references a patch that was renamed/removed.

```bash
PKG=$(sed -n 's/^PACKAGE_NAME="\(.*\)"/\1/p' dkms.conf)
VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' dkms.conf)

rm -rf .cache/linux-intel-quilt
sudo dkms build -m "$PKG" -v "$VER" -k "$(uname -r)"
```

## `patch: Hunk #N FAILED`

The snapshot in `UPSTREAM_VERSION` has drifted from the version the patches were
written against.

```bash
./scripts/helpers/update-from-kernel-org-lts.sh "$(cat UPSTREAM_VERSION)"

PKG=$(sed -n 's/^PACKAGE_NAME="\(.*\)"/\1/p' dkms.conf)
VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' dkms.conf)

sudo dkms build -m "$PKG" -v "$VER" -k "$(uname -r)"
```

## `cannot stat '/lib/modules/<kver>/build/.config'`

Kernel headers are incomplete.

```bash
sudo apt install --reinstall linux-headers-$(uname -r)
```

## `modinfo i915` still shows the in-tree driver after install

```bash
depmod -a
sudo modinfo -F filename i915

dkms status "$(sed -n 's/^PACKAGE_NAME="\(.*\)"/\1/p' dkms.conf)"
ls "/lib/modules/$(uname -r)/updates/dkms/i915.ko"* 2>/dev/null
```

## Build log location

```bash
PKG=$(sed -n 's/^PACKAGE_NAME="\(.*\)"/\1/p' dkms.conf)
VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' dkms.conf)

cat "/var/lib/dkms/${PKG}/${VER}/$(uname -r)/x86_64/log/make.log"
```
