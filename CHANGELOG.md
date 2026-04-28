# Changelog

All notable changes to this repository will be documented in this file.

This project follows a lightweight changelog format inspired by *Keep a Changelog*.

## Unreleased

- (no changes yet)

## 1.0 - 2026-04-24

### Added

- DKMS source tree that builds and installs the `i915` and `kvmgt` kernel modules with SR-IOV support.
- Pre-build workflow that vendors an upstream kernel.org i915 snapshot and applies the SR-IOV patch stack.
- Documentation set:
  - Build/install/verify/uninstall/rebuild after kernel update: `doc/build-install-guide.md`
  - SR-IOV boot parameters and VF creation: `doc/sriov-guide.md`
  - Build failures quick reference: `doc/build-failures.md`
- Debian packaging scaffold (`dh-dkms`) for producing a distributable `.deb`.

### Notes

- DKMS module name: `edge-gfx-dkms` (see `dkms.conf`).
- Supported kernel series: `6.18.x`.
- Modules install under `/lib/modules/<kver>/updates/dkms/`.
- First build may require network access (kernel.org tarball + quilt patch repo); subsequent builds use the local cache.
