#!/usr/bin/env bash
set -euo pipefail

# Shared helpers for vendoring i915 from an upstream kernel.org tarball.
# Intended to be sourced by other scripts in this repo.

_i915_patch_makefile_objm() {
	local makefile="$1"
	local verbose="${2:-0}"

	[[ -f "${makefile}" ]] || return 0
	if grep -Eq '^\s*obj-m\s*\+=\s*i915\.o\s*$' "${makefile}"; then
		return 0
	fi

	local tmp
	tmp="$(mktemp)"

	awk '
		BEGIN{inserted=0; header=1}
		{
			if (inserted==0) {
				if (header==1) {
					if ($0 ~ /^[[:space:]]*#/ || $0 ~ /^[[:space:]]*$/) {
						print $0
						next
					} else {
						print "obj-m += i915.o"
						inserted=1
						header=0
					}
				}
				if ($0 ~ /^[[:space:]]*obj-/) {
					print "obj-m += i915.o"
					inserted=1
				}
			}
			print $0
			header=0
		}
		END{
			if (inserted==0) {
				print "obj-m += i915.o"
			}
		}
	' "${makefile}" > "${tmp}"

	chmod --reference="${makefile}" "${tmp}" 2>/dev/null || true
	mv -f "${tmp}" "${makefile}"

	if [[ "${verbose}" == "1" ]]; then
		echo "Patched i915 Kbuild for external-module builds (added: obj-m += i915.o)." >&2
	fi
}

# Extracts the i915 subtree plus optional extra paths from a kernel.org tarball
# into kernel-src/ using a single tar pass.
#
# Each separate tar invocation on the same .xz file requires a full xz
# re-decompression (~30-90 s).  All paths are therefore extracted together.
# Extra paths are silently skipped if absent from the tarball
# (--ignore-failed-read); callers must verify required files afterwards.
#
# Args:
#   $1: root_dir (repo root)
#   $2: kernel_src_dir (usually ${root_dir}/kernel-src)
#   $3: tarball_path (/path/to/linux-X.Y.Z.tar.xz)
#   $4: version (X.Y.Z)
#   $5: verbose (0/1)
#   $6+: optional extra paths relative to kernel root
#        (e.g. "Documentation/gpu/i915.rst" "include/drm/intel")
extract_i915_from_tarball() {
	local root_dir="$1"
	local kernel_src_dir="$2"
	local tarball_path="$3"
	local version="$4"
	local verbose="${5:-0}"
	shift 5
	local extra_paths=("$@")

	if [[ -z "${root_dir}" || -z "${kernel_src_dir}" || -z "${tarball_path}" || -z "${version}" ]]; then
		echo "extract_i915_from_tarball: missing args" >&2
		return 2
	fi
	if [[ ! -f "${tarball_path}" ]]; then
		echo "tarball not found: ${tarball_path}" >&2
		return 2
	fi

	local prefix="linux-${version}"

	# Ensure we don't keep stale files across updates.
	mkdir -p "${kernel_src_dir}"
	rm -rf "${kernel_src_dir}/drivers/gpu/drm/i915"
	rm -f  "${kernel_src_dir}/drivers/platform/x86/intel_ips.h"
	rm -f  "${kernel_src_dir}/.dkms-patches.state"
	# Clean caller-supplied extra paths for a pristine re-run.
	local _p
	for _p in "${extra_paths[@]}"; do
		rm -rf "${kernel_src_dir:?}/${_p}"
	done

	mkdir -p "${kernel_src_dir}/drivers/gpu/drm"

	# Build the full list of tar paths for a single extraction pass.
	# intel_ips.h is included here; it is optional and handled by --ignore-failed-read.
	local tar_targets=(
		"${prefix}/drivers/gpu/drm/i915"
		"${prefix}/drivers/platform/x86/intel_ips.h"
	)
	for _p in "${extra_paths[@]}"; do
		tar_targets+=("${prefix}/${_p}")
	done

	echo "Extracting i915 source tree from $(basename "${tarball_path}") (xz decompression, please wait)..." >&2
	# --ignore-failed-read: silently skip optional paths absent from this kernel version.
	tar -C "${kernel_src_dir}" --ignore-failed-read -xf "${tarball_path}" \
		--strip-components=1 \
		"${tar_targets[@]}" 2>/dev/null || true
	echo "Extraction complete." >&2

	if [[ ! -d "${kernel_src_dir}/drivers/gpu/drm/i915" ]]; then
		echo "ERROR: drivers/gpu/drm/i915 not found in ${tarball_path}" >&2
		return 2
	fi

	echo "${version}" > "${root_dir}/UPSTREAM_VERSION"

	local makefile="${kernel_src_dir}/drivers/gpu/drm/i915/Makefile"
	_i915_patch_makefile_objm "${makefile}" "${verbose}"
}
