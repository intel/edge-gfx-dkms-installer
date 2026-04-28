#!/usr/bin/env bash
set -euo pipefail

# fetch-quilt-patches.sh — Ensure a shallow clone of a quilt patch repository
# is available, then output the path to its patches/ directory.
#
# Usage:
#   fetch-quilt-patches.sh <repo_url> <branch> <cache_dir>
#
# Environment overrides (take precedence over positional args):
#   QUILT_REPO         — repository URL
#   QUILT_BRANCH       — branch name
#   QUILT_FORCE_FETCH  — set to "1" to force a fetch even if cache is present
#
# Outputs the path to <cache_dir>/patches/ on stdout.
# All progress and status messages go to stderr.

repo_url="${QUILT_REPO:-${1:-}}"
branch="${QUILT_BRANCH:-${2:-}}"
cache_dir="${3:-}"

if [[ -z "${repo_url}" || -z "${branch}" || -z "${cache_dir}" ]]; then
	echo "usage: $0 <repo_url> <branch> <cache_dir>" >&2
	echo "       or set QUILT_REPO and QUILT_BRANCH environment variables" >&2
	exit 2
fi

if [[ ! -d "${cache_dir}/.git" ]]; then
	echo "Cloning quilt repo (branch: ${branch})…" >&2
	git clone --depth=1 --branch "${branch}" "${repo_url}" "${cache_dir}" >&2
else
	current_branch="$(git -C "${cache_dir}" symbolic-ref --short HEAD 2>/dev/null || echo "")"
	if [[ "${current_branch}" != "${branch}" ]]; then
		echo "Switching quilt repo branch: ${current_branch:-detached} → ${branch}" >&2
		git -C "${cache_dir}" remote set-branches origin "${branch}" >&2
		git -C "${cache_dir}" fetch --depth=1 origin "${branch}" >&2
		git -C "${cache_dir}" checkout -B "${branch}" "origin/${branch}" >&2
	elif [[ "${QUILT_FORCE_FETCH:-0}" == "1" ]]; then
		echo "Updating quilt repo (branch: ${branch})…" >&2
		git -C "${cache_dir}" fetch --depth=1 origin "${branch}" >&2
		git -C "${cache_dir}" reset --hard "origin/${branch}" >&2
	else
		echo "Using cached quilt repo (branch: ${branch}). Set QUILT_FORCE_FETCH=1 to update." >&2
	fi
fi

if [[ ! -d "${cache_dir}/patches" ]]; then
	echo "quilt repo has no patches/ directory: ${cache_dir}" >&2
	exit 2
fi

echo "${cache_dir}/patches"
