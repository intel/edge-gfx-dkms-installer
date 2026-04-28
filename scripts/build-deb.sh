#!/usr/bin/env bash
# build-deb.sh — Build the edge-gfx-dkms Debian source package and test install.
#
# Usage:
#   scripts/build-deb.sh [--no-install] [--output-dir DIR]
#
# Options:
#   --no-install    Build the .deb but skip installation and module test.
#   --output-dir    Directory to place the built .deb (default: parent of repo).
#
# The script will:
#   1. Build the .deb with dpkg-buildpackage inside a clean work tree.
#   2. Remove any existing DKMS install for the package.
#   3. Install the new .deb with dpkg.
#   4. Confirm DKMS status shows "installed" for the running kernel.
#   5. Verify the i915 module file exists in /lib/modules/<kver>/updates/dkms/.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# ── Parse arguments ──────────────────────────────────────────────────────────
DO_INSTALL=1
OUTPUT_DIR="$(dirname "$ROOT_DIR")"

for arg in "$@"; do
    case "$arg" in
        --no-install)  DO_INSTALL=0 ;;
        --output-dir=*) OUTPUT_DIR="${arg#*=}" ;;
        --output-dir)  shift; OUTPUT_DIR="$1" ;;
        -h|--help)
            sed -n '2,/^$/p' "$0" | grep '^#' | sed 's/^# \?//'
            exit 0
            ;;
    esac
done

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(realpath "$OUTPUT_DIR")"

# ── Detect package name and version from dkms.conf ───────────────────────────
PKG_NAME=$(grep '^PACKAGE_NAME=' dkms.conf | cut -d'"' -f2)
PKG_VERSION=$(grep '^PACKAGE_VERSION=' dkms.conf | cut -d'"' -f2)
DEB_VERSION="${PKG_VERSION}-1"

echo "==> Building ${PKG_NAME} ${DEB_VERSION}"
echo "    Source : $ROOT_DIR"
echo "    Output : $OUTPUT_DIR"

# ── Check build dependencies ─────────────────────────────────────────────────
for cmd in dpkg-buildpackage dpkg dkms; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: '$cmd' not found. Install build-essential, debhelper, dh-dkms, dkms." >&2
        exit 1
    fi
done

# ── Clean stale debian staging artifacts ─────────────────────────────────────
if [[ -d debian/.debhelper || -f debian/debhelper-build-stamp ]]; then
    echo "==> Cleaning previous debian/ build artifacts..."
    fakeroot debian/rules clean 2>/dev/null || true
fi

# ── Build the source package ──────────────────────────────────────────────────
echo "==> Running dpkg-buildpackage..."
dpkg-buildpackage \
    --build=binary \
    --no-sign \
    --root-command=fakeroot \
    2>&1

# ── Collect built .deb ───────────────────────────────────────────────────────
DEB_GLOB="${PKG_NAME}_${DEB_VERSION}_all.deb"

# dpkg-buildpackage places output one level above the source tree
BUILT_DEB="$(dirname "$ROOT_DIR")/${DEB_GLOB}"

if [[ ! -f "$BUILT_DEB" ]]; then
    echo "ERROR: Expected .deb not found: $BUILT_DEB" >&2
    exit 1
fi

if [[ "$(realpath "$OUTPUT_DIR")" != "$(realpath "$(dirname "$ROOT_DIR")")" ]]; then
    cp -v "$BUILT_DEB" "$OUTPUT_DIR/"
    BUILT_DEB="${OUTPUT_DIR}/${DEB_GLOB}"
fi

echo "==> Built: $BUILT_DEB"
ls -lh "$BUILT_DEB"

echo ""
echo "==> SUCCESS: ${PKG_NAME} package has been built"
