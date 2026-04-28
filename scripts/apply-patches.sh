#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-}"
if [[ -z "${ROOT_DIR}" ]]; then
	echo "usage: $0 /path/to/edge-gfx-dkms [kernelver] [quilt_patches_dir]" >&2
	exit 2
fi

KERNELVER="${2:-${kernelver:-${KERNELVER:-}}}"

# Directory containing the remote quilt patch files (from fetch-quilt-patches.sh).
# If empty, falls back to the local patches/sriov-6_18/ directory.
QUILT_PATCHES_DIR="${3:-}"

KERNEL_SRC_DIR="${ROOT_DIR}/kernel-src"
if [[ ! -d "${KERNEL_SRC_DIR}" ]]; then
	echo "kernel source dir not found: ${KERNEL_SRC_DIR}" >&2
	exit 2
fi

cd "${KERNEL_SRC_DIR}"

PATCH_DIR="${ROOT_DIR}/patches"
if [[ ! -d "${PATCH_DIR}" ]]; then
	echo "patch dir not found: ${PATCH_DIR}" >&2
	exit 2
fi

collect_patches_from_dir() {
	local dir="$1"
	if [[ ! -d "${dir}" ]]; then
		return 0
	fi

	# If a series file exists, respect it; otherwise apply *.patch in lexical order.
	if [[ -f "${dir}/series" ]]; then
		while IFS= read -r line; do
			[[ -z "${line}" ]] && continue
			[[ "${line}" =~ ^# ]] && continue
			patch_list+=("${dir}/${line}")
		done < "${dir}/series"
	else
		while IFS= read -r -d '' p; do
			patch_list+=("${p}")
		done < <(find "${dir}" -maxdepth 1 -type f -name '*.patch' -print0 | sort -z)
	fi
}

# Collect SR-IOV patches listed in a series file, resolving each entry against
# the quilt patches directory (or local sriov-6_18/ fallback if quilt_dir is empty).
collect_patches_from_series() {
	local series_file="$1"
	local quilt_dir="${2:-}"

	if [[ ! -f "${series_file}" ]]; then
		echo "SR-IOV series file not found: ${series_file}" >&2
		exit 2
	fi

	while IFS= read -r line; do
		[[ -z "${line}" ]] && continue
		[[ "${line}" =~ ^# ]] && continue

		local patch_path
		if [[ -n "${quilt_dir}" ]]; then
			patch_path="${quilt_dir}/${line}"
		else
			# Fallback: local sriov-6_18/ directory (for offline/development use).
			patch_path="${PATCH_DIR}/sriov-6_18/${line}"
		fi
		patch_list+=("${patch_path}")
	done < "${series_file}"
}

patch_list=()

# SR-IOV series: driven by patches/series, patch files fetched from quilt repo.
collect_patches_from_series "${PATCH_DIR}/series" "${QUILT_PATCHES_DIR}"

# Top-level compat patches (local, lexical order; patches/series is not used here).
while IFS= read -r -d '' p; do
	patch_list+=("${p}")
done < <(find "${PATCH_DIR}" -maxdepth 1 -type f -name '*.patch' -print0 | sort -z)

# Apply series-specific compat patches only to their intended target kernels.
# Convention: if a patch filename mentions exactly one of {6.12, 6.18}, it is
# treated as series-scoped. (Patches that mention both apply to both.)
if [[ -n "${KERNELVER}" ]]; then
	filtered=()
	for p in "${patch_list[@]}"; do
		base="$(basename "${p}")"
		wants_612=0
		wants_618=0
		if [[ "${base}" =~ (^|[^0-9])6\.12([^0-9]|$) ]]; then
			wants_612=1
		fi
		if [[ "${base}" =~ (^|[^0-9])6\.18([^0-9]|$) ]]; then
			wants_618=1
		fi

		if [[ ${wants_612} -eq 1 && ${wants_618} -eq 0 && ! "${KERNELVER}" =~ ^6\.12 ]]; then
			continue
		fi
		if [[ ${wants_618} -eq 1 && ${wants_612} -eq 0 && ! "${KERNELVER}" =~ ^6\.18 ]]; then
			continue
		fi
		filtered+=("${p}")
	done
	patch_list=("${filtered[@]}")
fi

if (( ${#patch_list[@]} == 0 )); then
	echo "No patches to apply (patches/*.patch or patches/series)."
	exit 0
fi

# Avoid re-applying on repeated DKMS invocations.
state_file="${KERNEL_SRC_DIR}/.dkms-patches.state"
new_state=""
for p in "${patch_list[@]}"; do
	if [[ ! -f "${p}" ]]; then
		echo "missing patch: ${p}" >&2
		exit 2
	fi
	# Include path in state to avoid collisions (same filename in different dirs).
	rel="${p#"${ROOT_DIR}"/}"
	new_state+="$(sha256sum "${p}" | awk '{print $1}')  ${rel}"$'\n'
done

if [[ -f "${state_file}" ]] && cmp -s <(printf "%s" "${new_state}") "${state_file}"; then
	echo "Patches already applied (state matches)."
	exit 0
fi

for p in "${patch_list[@]}"; do
	echo "Applying $(basename "${p}")"
	# Clean up any stale rejects so we can detect a new failure.
	find "${KERNEL_SRC_DIR}" -maxdepth 20 -name '*.rej' -delete >/dev/null 2>&1 || true

	# Apply forward. For large compat patches it's common that some hunks are
	# already present (patch exits 1) but the overall result is still correct.
	set +e
	patch -p1 --batch --no-backup-if-mismatch --forward < "${p}"
	patch_rc=$?
	set -e

	if [[ ${patch_rc} -eq 0 ]]; then
		continue
	fi

	# rc=2 typically means malformed patch or fatal patching error.
	if [[ ${patch_rc} -ge 2 ]]; then
		echo "Failed to apply: $(basename "${p}")" >&2
		exit 1
	fi

	# rc=1: check whether we produced rejects (real failure) or just skipped hunks.
	# If the patch is already applied, avoid failing the build.
	#
	# Note: GNU patch may still drop a *.rej when it detects a reversed patch
	# in batch mode. Treat that case as success and remove any rejects.
	if patch -p1 --batch --dry-run --reverse --silent < "${p}" >/dev/null 2>&1; then
		find "${KERNEL_SRC_DIR}" -maxdepth 20 -name '*.rej' -delete >/dev/null 2>&1 || true
		echo "Already applied: $(basename "${p}")"
		continue
	fi

	if find "${ROOT_DIR}" -maxdepth 20 -name '*.rej' | grep -q .; then
		echo "Failed to apply (rejects produced): $(basename "${p}")" >&2
		exit 1
	fi

	# Otherwise accept (some hunks may have been skipped).
	echo "Applied with skipped hunks: $(basename "${p}")"
done

printf "%s" "${new_state}" > "${state_file}"
