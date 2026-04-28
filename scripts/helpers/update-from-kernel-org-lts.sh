#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
scripts_dir="$(cd -- "${script_dir}/.." && pwd)"
root_dir="$(cd -- "${scripts_dir}/.." && pwd)"

# shellcheck source=scripts/helpers/lib-i915-vendor.sh
source "${script_dir}/lib-i915-vendor.sh"

version=""
series=""
force_latest="0"
unpin_series="0"

while [[ $# -gt 0 ]]; do
	case "$1" in
		--series)
			series="${2:-}"
			shift 2
			;;
		--latest)
			force_latest="1"
			shift
			;;
		--unpin)
			unpin_series="1"
			shift
			;;
		-h|--help)
			echo "usage: $0 [--series <major.minor>] [--latest] [--unpin] [<kernel_version>]" >&2
			echo "" >&2
			echo "Defaults:" >&2
			echo "  - tracks latest LTS within UPSTREAM_SERIES (or uname-derived series)" >&2
			echo "Options:" >&2
			echo "  --series X.Y   Pin/switch the LTS series (writes UPSTREAM_SERIES)" >&2
			echo "  --latest       Ignore UPSTREAM_SERIES and track latest LTS overall" >&2
			echo "  --unpin        Remove UPSTREAM_SERIES pin" >&2
			exit 0
			;;
		*)
			# Explicit version positional arg.
			if [[ -z "${version}" ]]; then
				version="$1"
				shift
			else
				echo "unexpected argument: $1" >&2
				exit 2
			fi
			;;
	esac
done

series_file="${root_dir}/UPSTREAM_SERIES"

if [[ "${unpin_series}" == "1" ]]; then
	rm -f "${series_file}"
fi

if [[ "${force_latest}" != "1" && -n "${series}" ]]; then
	echo "${series}" > "${series_file}"
elif [[ "${force_latest}" != "1" && -f "${series_file}" ]]; then
	series="$(cat "${series_file}" 2>/dev/null || true)"
fi

if [[ -z "${version}" ]]; then
	# If no explicit version requested, prefer a pinned series.
	if [[ "${force_latest}" != "1" && -z "${series}" ]] && command -v uname >/dev/null 2>&1; then
		kver="$(uname -r)"
		if [[ "${kver}" =~ ^([0-9]+\.[0-9]+) ]]; then
			series="${BASH_REMATCH[1]}"
			if [[ -n "${series}" && ! -f "${series_file}" ]]; then
				echo "${series}" > "${series_file}"
			fi
		fi
	fi

	if command -v python3 >/dev/null 2>&1; then
		if [[ "${force_latest}" != "1" && -n "${series}" ]]; then
			version=$(python3 "${script_dir}/get-lts-version.py" --series "${series}" || true)
		else
			version=$(python3 "${script_dir}/get-lts-version.py" || true)
		fi
	fi
fi

if [[ -z "${version}" ]]; then
	echo "Could not auto-detect latest LTS. Provide an explicit version:" >&2
	echo "  $0 6.6.82" >&2
	exit 2
fi

tarball_path=$(bash "${scripts_dir}/fetch-kernel-tarball.sh" "${version}")

kernel_src_dir="${root_dir}/kernel-src"
extract_i915_from_tarball "${root_dir}" "${kernel_src_dir}" "${tarball_path}" "${version}" 1

echo "Done. Now add your SR-IOV patches into ${root_dir}/patches/."
echo "(Vendored kernel bits are under: ${root_dir}/kernel-src/)"
