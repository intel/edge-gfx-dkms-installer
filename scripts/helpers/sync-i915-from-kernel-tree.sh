#!/usr/bin/env bash
set -euo pipefail

kernel_tree="${1:-}"
upstream_version="${2:-}"
if [[ -z "${kernel_tree}" ]]; then
	echo "usage: $0 /path/to/linux [upstream_version]" >&2
	exit 2
fi

if [[ ! -d "${kernel_tree}/drivers/gpu/drm/i915" ]]; then
	echo "i915 tree not found in: ${kernel_tree}" >&2
	exit 2
fi

root_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
root_dir="$(cd -- "${root_dir}/.." && pwd)"
kernel_src_dir="${root_dir}/kernel-src"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers/lib-i915-vendor.sh
source "${script_dir}/lib-i915-vendor.sh"

mkdir -p "${kernel_src_dir}"
rsync -a --delete "${kernel_tree}/drivers/gpu/drm/i915/" "${kernel_src_dir}/drivers/gpu/drm/i915/"

# Some i915 sources include this via a relative path.
if [[ -f "${kernel_tree}/drivers/platform/x86/intel_ips.h" ]]; then
	mkdir -p "${kernel_src_dir}/drivers/platform/x86"
	install -m 0644 "${kernel_tree}/drivers/platform/x86/intel_ips.h" "${kernel_src_dir}/drivers/platform/x86/intel_ips.h"
fi

if [[ -n "${upstream_version}" ]]; then
	echo "${upstream_version}" > "${root_dir}/UPSTREAM_VERSION"
fi

makefile="${root_dir}/kernel-src/drivers/gpu/drm/i915/Makefile"
_i915_patch_makefile_objm "${makefile}" 1

echo "Synced i915 from ${kernel_tree}"
