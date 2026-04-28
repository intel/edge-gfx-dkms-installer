#!/usr/bin/env bash
set -euo pipefail
#
# fetch-kernel-tarball.sh — download the full kernel.org tarball for a given
# kernel version and cache it locally.
#
# Usage:
#   fetch-kernel-tarball.sh <version>
#
# Outputs the path to the cached .tar.xz on stdout.
# All progress messages go to stderr.
#
# Environment overrides:
#   KERNEL_TARBALL_URL_TEMPLATE — printf template with one %s for the version
#                                  (default: https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-%s.tar.xz)
#   CACHE_DIR                   — parent directory for cached tarballs

version="${1:-}"
if [[ -z "${version}" ]]; then
	echo "usage: $0 <kernel_version>" >&2
	exit 2
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd -- "${script_dir}/.." && pwd)"

cache_dir="${CACHE_DIR:-${root_dir}/.cache}"
mkdir -p "${cache_dir}"

tarball="${cache_dir}/linux-${version}.tar.xz"

# Derive the major version number (e.g. "6" from "6.18.15") for the URL path.
major="${version%%.*}"
url_template="${KERNEL_TARBALL_URL_TEMPLATE:-https://cdn.kernel.org/pub/linux/kernel/v%s.x/linux-%s.tar.xz}"
# shellcheck disable=SC2059
url="$(printf "${url_template}" "${major}" "${version}")"

if [[ -f "${tarball}" ]]; then
	echo "Using cached tarball: ${tarball}" >&2
else
	echo "Downloading ${url} ..." >&2
	curl --fail --location --progress-bar \
		--max-time 600 \
		--retry 3 --retry-delay 5 --retry-max-time 1800 \
		-o "${tarball}.tmp" "${url}" >&2
	mv -f "${tarball}.tmp" "${tarball}"
	echo "Download complete: ${tarball}" >&2
fi

echo "${tarball}"
