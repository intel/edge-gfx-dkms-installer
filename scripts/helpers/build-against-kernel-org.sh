#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
scripts_dir="$(cd -- "${script_dir}/.." && pwd)"
repo_root="$(cd -- "${scripts_dir}/.." && pwd)"

series=""
version=""
config_path=""
clean=0
jobs=""

usage() {
	cat >&2 <<'EOF'
usage:
  build-against-kernel-org.sh [--series X.Y | --version X.Y.Z] [--config /path/to/.config] [--clean] [-j N]

Builds this external i915 DKMS tree against a kernel.org kernel *build tree*
created locally (no distro linux-headers package needed).

Examples:
  # Latest longterm in 6.12 series (via kernel.org releases.json)
	./scripts/helpers/build-against-kernel-org.sh --series 6.12

  # Explicit version (useful if the series is not marked longterm)
	./scripts/helpers/build-against-kernel-org.sh --version 6.18.19

  # Provide a known-good config to reduce "missing CONFIG_*" surprises
	./scripts/helpers/build-against-kernel-org.sh --series 6.12 --config /boot/config-$(uname -r)
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--series)
			series="${2:-}"; shift 2 ;;
		--version)
			version="${2:-}"; shift 2 ;;
		--config)
			config_path="${2:-}"; shift 2 ;;
		--clean)
			clean=1; shift ;;
		-j)
			jobs="${2:-}"; shift 2 ;;
		-h|--help)
			usage; exit 0 ;;
		*)
			echo "unknown arg: $1" >&2
			usage
			exit 2
			;;
	esac
done

if [[ -n "${series}" && -n "${version}" ]]; then
	echo "use only one of --series or --version" >&2
	exit 2
fi

if [[ -z "${series}" && -z "${version}" ]]; then
	echo "must provide --series X.Y or --version X.Y.Z" >&2
	exit 2
fi

if [[ -n "${series}" ]]; then
	if ! version="$(python3 "${script_dir}/get-lts-version.py" --series "${series}" 2>/dev/null || true)"; then
		version=""
	fi
	if [[ -z "${version}" ]]; then
		echo "could not determine latest longterm version for series ${series}" >&2
		echo "try: --version X.Y.Z" >&2
		exit 2
	fi
fi

src_dir="${repo_root}/.kernel-src/linux-${version}"
build_dir="${repo_root}/.kernel-build/linux-${version}"
mkdir -p "${repo_root}/.kernel-src" "${repo_root}/.kernel-build"

if [[ "${clean}" -eq 1 ]]; then
	rm -rf "${src_dir}" "${build_dir}"
fi

if [[ ! -d "${src_dir}" ]]; then
		tarball="$(bash "${scripts_dir}/fetch-kernel-tarball.sh" "${version}")"
	mkdir -p "${src_dir}"
	echo "Extracting full kernel source to ${src_dir}" >&2
	tar -C "${src_dir}" -xf "${tarball}" --strip-components=1 "linux-${version}" 
fi

mkdir -p "${build_dir}"

# Choose a config.
if [[ -n "${config_path}" ]]; then
	if [[ ! -f "${config_path}" ]]; then
		echo "config not found: ${config_path}" >&2
		exit 2
	fi
	cp -f "${config_path}" "${build_dir}/.config"
else
	# Best-effort: reuse the running kernel config if available.
	if [[ -f "/boot/config-$(uname -r)" ]]; then
		cp -f "/boot/config-$(uname -r)" "${build_dir}/.config"
	elif [[ -r /proc/config.gz ]]; then
		zcat /proc/config.gz > "${build_dir}/.config"
	fi
fi

make_args=("-C" "${src_dir}" "O=${build_dir}")
if [[ -n "${jobs}" ]]; then
	make_args+=("-j${jobs}")
fi

# Prepare the build tree.
if [[ -f "${build_dir}/.config" ]]; then
	echo "Preparing kernel build tree (olddefconfig + modules_prepare)" >&2
	make "${make_args[@]}" olddefconfig
else
	echo "No config found; generating defconfig + modules_prepare" >&2
	make "${make_args[@]}" defconfig
fi

make "${make_args[@]}" modules_prepare

# Apply our patch stack and build the external module against this build tree.
# This keeps module sources under repo_root/kernel-src and kernel build output under build_dir.
export kernelver="${version}"
"${repo_root}/scripts/dkms-pre-build.sh" >/dev/null

echo "Building module against kernel ${version} (build tree: ${build_dir})" >&2
make "${make_args[@]}" "KBUILD_MODPOST_WARN=1" "M=${repo_root}/kernel-src" modules

echo "OK: built against ${version}" >&2
