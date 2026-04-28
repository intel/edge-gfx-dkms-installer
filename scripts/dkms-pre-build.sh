#!/usr/bin/env bash
set -euo pipefail

# Runs inside DKMS build directory.
# Apply patches if present.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
KERNEL_SRC_DIR="${ROOT_DIR}/kernel-src"

# Integrity check: abort if the scripts directory or this hook are not owned
# by root. This detects tampering before any privileged build work begins.
# (Installed under /usr/src/ by dpkg, so root ownership is the invariant.)
_assert_root_owned() {
    local path="$1"
    local owner
    owner="$(stat -c '%U' "${path}" 2>/dev/null)" || {
        echo "ERROR: Cannot stat '${path}' — aborting." >&2
        exit 1
    }
    if [[ "${owner}" != "root" ]]; then
        echo "ERROR: '${path}' is owned by '${owner}', expected 'root'." >&2
        echo "       The DKMS source tree may have been tampered with. Aborting." >&2
        exit 1
    fi
}
_assert_root_owned "${SCRIPT_DIR}"
_assert_root_owned "${BASH_SOURCE[0]}"

# shellcheck source=scripts/helpers/lib-i915-vendor.sh
_assert_root_owned "${SCRIPT_DIR}/helpers/lib-i915-vendor.sh"
source "${SCRIPT_DIR}/helpers/lib-i915-vendor.sh"

# Supported kernel series for this DKMS tree: 6.18.x and 6.18-intel.
supported_kver_re='^6\.18[.\-]'
kver_for_check="${kernelver:-${KERNELVER:-}}"
if [[ -n "${kver_for_check}" && ! "${kver_for_check}" =~ ${supported_kver_re} ]]; then
	echo "WARNING: edge-gfx-dkms supports only 6.18 kernels; refusing to build for ${kver_for_check}." >&2
	exit 3
fi

# If this PRE_BUILD script exits non-zero, DKMS may still attempt to run MAKE
# against whatever is left in kernel-src/.  Remove the i915 source tree on any
# failure so the subsequent MAKE step also fails, preventing a silent build with
# unpatched code.
_cleanup_on_failure() {
	echo "PRE_BUILD failed — removing kernel-src/ to prevent building unpatched module." >&2
	rm -rf "${KERNEL_SRC_DIR}/drivers/gpu/drm/i915"
}
trap _cleanup_on_failure ERR

prepare_kernel_build_tree() {
	# DKMS builds run as root and provide:
	# - $kernelver (e.g. 6.18.17)
	# - $kernel_source_dir (usually /lib/modules/<kver>/build)
	# Some kernel header trees are "prepared" enough to build external modules
	# but do not ship a top-level .config. Parts of Kbuild/DKMS tooling still
	# expect it to exist and may fail early with:
	#   cp: cannot stat '/lib/modules/<kver>/build/.config'
	local kver="${kernelver:-${KERNELVER:-}}"
	[[ -z "${kver}" ]] && return 0

	local ksrc="${kernel_source_dir:-}"
	if [[ -z "${ksrc}" ]]; then
		ksrc="/lib/modules/${kver}/build"
	fi
	[[ ! -d "${ksrc}" ]] && return 0

    # Ensure .config exists (prefer the running kernel's shipped config).
    # Priority:
    #   1. Already present in the headers tree (nothing to do).
    #   2. /lib/modules/<kver>/build/.config — shipped by some distro header
    #      packages (e.g. Fedora, RHEL derivatives) when ksrc differs from
    #      the default headers path.
    #   3. /boot/config-<kver>  — Debian/Ubuntu standard location.
    #   4. /proc/config.gz      — Arch, Gentoo, some Ubuntu kernels.
    #   5. Hard error — never silently fall back to a wrong config.
    if [[ ! -f "${ksrc}/.config" ]]; then
        if [[ -f "/lib/modules/${kver}/build/.config" ]]; then
            cp -f "/lib/modules/${kver}/build/.config" "${ksrc}/.config"
        elif [[ -f "/boot/config-${kver}" ]]; then
            cp -f "/boot/config-${kver}" "${ksrc}/.config"
        elif [[ -r /proc/config.gz ]]; then
            zcat /proc/config.gz > "${ksrc}/.config"
        else
            echo "Missing ${ksrc}/.config and no /boot/config-${kver} or /proc/config.gz to seed it." >&2
            echo "Install full kernel headers for ${kver} or copy a config into ${ksrc}/.config." >&2
            exit 2
        fi
    fi

	# If the header tree isn't fully prepared, prepare it now.
	if [[ ! -f "${ksrc}/include/generated/autoconf.h" || ! -f "${ksrc}/include/config/auto.conf" ]]; then
		make -C "${ksrc}" olddefconfig >/dev/null
		make -C "${ksrc}" prepare modules_prepare >/dev/null
	fi
}

ver_file="${ROOT_DIR}/UPSTREAM_VERSION"

get_upstream_version() {
	if [[ ! -f "${ver_file}" ]]; then
		echo "Missing i915 sources and ${ver_file}." >&2
		echo "Run: ${ROOT_DIR}/scripts/helpers/update-from-kernel-org-lts.sh <kernel_version>" >&2
		exit 2
	fi
	local version
	version="$(tr -d '[:space:]' < "${ver_file}")"
	if [[ -z "${version}" ]]; then
		echo "Empty ${ver_file}" >&2
		exit 2
	fi
	echo "${version}"
}

# Always start from a pristine extracted snapshot.
#
# DKMS may invoke this hook multiple times for the same build directory (e.g.
# rebuilds after patch changes). If we keep a previously patched tree around,
# subsequent patch runs may fail or end up partially applied.
prepare_kernel_build_tree

# Determine the i915 source version to use.
# If the running kernel's base version (e.g. 6.18.15 from 6.18.15+deb13-amd64)
# differs from UPSTREAM_VERSION, prefer the kernel's base version so the built
# module matches the kernel's internal symbol ABI exactly.
upstream_version="$(get_upstream_version)"
kver_base="${kernelver%%[^0-9.]*}"   # strip distro suffix: 6.18.15+deb13-amd64 → 6.18.15
kver_base="${kver_base%%.}"          # strip any trailing dot
if [[ -n "${kver_base}" && "${kver_base}" != "${upstream_version}" ]]; then
	echo "NOTE: kernel base version (${kver_base}) differs from UPSTREAM_VERSION (${upstream_version})." >&2
	echo "      Building i915 from kernel base version ${kver_base} to match kernel ABI." >&2
	version="${kver_base}"
else
	version="${upstream_version}"
fi

_assert_root_owned "${ROOT_DIR}/scripts/fetch-kernel-tarball.sh"
tarball_path=$(bash "${ROOT_DIR}/scripts/fetch-kernel-tarball.sh" "${version}")

# Extract i915 plus all ancillary paths in a single tar pass.
# Each extra tar invocation on the same .xz file requires a full re-decompression
# (~30-90 s).  Optional paths are silently skipped if absent from this kernel version.
extract_i915_from_tarball "${ROOT_DIR}" "${KERNEL_SRC_DIR}" "${tarball_path}" "${version}" 0 \
	"Documentation/gpu/i915.rst" \
	"include/drm/intel"

# Verify files that are strictly required for the patchset to apply.
if [[ -f "${ROOT_DIR}/patches/series" ]]; then
	if [[ ! -f "${KERNEL_SRC_DIR}/Documentation/gpu/i915.rst" ]]; then
		echo "Missing Documentation/gpu/i915.rst in ${tarball_path} (version ${version})" >&2
		exit 2
	fi
fi

intel_drm_hdr_dir="${KERNEL_SRC_DIR}/include/drm/intel"
if [[ ! -f "${intel_drm_hdr_dir}/pciids.h" ]]; then
	echo "Missing include/drm/intel/pciids.h in ${tarball_path} (version ${version})" >&2
	exit 2
fi

# Fetch SR-IOV patch series from the remote quilt repository.
# Persistent defaults are read from quilt.conf (env vars take precedence).
if [[ -f "${ROOT_DIR}/quilt.conf" ]]; then
	# shellcheck disable=SC1091
	_assert_root_owned "${ROOT_DIR}/quilt.conf"
	source "${ROOT_DIR}/quilt.conf"
fi
_quilt_url="${QUILT_REPO:-https://github.com/intel/linux-intel-quilt.git}"
_quilt_branch="${QUILT_BRANCH:-$(git -C "${ROOT_DIR}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")}"
if [[ -z "${_quilt_branch}" ]]; then
	echo "ERROR: QUILT_BRANCH is not set and could not auto-detect git branch." >&2
	echo "       Set QUILT_BRANCH in quilt.conf or as an environment variable." >&2
	exit 2
fi
_assert_root_owned "${ROOT_DIR}/scripts/helpers/fetch-quilt-patches.sh"
QUILT_PATCHES_DIR="$("${ROOT_DIR}/scripts/helpers/fetch-quilt-patches.sh" \
	"${_quilt_url}" "${_quilt_branch}" "${ROOT_DIR}/.cache/linux-intel-quilt")"
export QUILT_PATCHES_DIR

_assert_root_owned "${ROOT_DIR}/scripts/apply-patches.sh"
"${ROOT_DIR}/scripts/apply-patches.sh" "${ROOT_DIR}" "${kernelver:-}" "${QUILT_PATCHES_DIR}"
