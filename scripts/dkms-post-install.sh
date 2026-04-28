#!/usr/bin/env bash
set -euo pipefail

# dkms-post-install.sh — Post-install hook for edge-gfx-dkms.
#
# Two responsibilities:
#   1. Fix module compression format (xz-CRC64 → CRC32 for Debian kernels).
#   2. Generate a MOK key pair, enroll it (if Secure Boot is active), and
#      sign all installed modules so they load on Secure Boot systems.
#
# DKMS provides: $kernelver, $kernel_source_dir, $pkgname, $pkgver

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

# Integrity check: abort if the scripts directory or this hook are not owned
# by root. This detects tampering before any privileged post-install work begins.
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

# Derive package name/version from dkms.conf — more reliable than $pkgname/$pkgver
# which are not exported by all DKMS versions.
_pkgname="$(sed -n 's/^PACKAGE_NAME="\(.*\)"/\1/p' "${ROOT_DIR}/dkms.conf")"
_pkgver="$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' "${ROOT_DIR}/dkms.conf")"
pkgname="${pkgname:-${_pkgname}}"
pkgver="${pkgver:-${_pkgver}}"

# DKMS typically provides $kernelver; fall back to common alternatives for manual runs.
kernelver="${kernelver:-${KERNELVER:-$(uname -r)}}"

MODULES_DIR="/lib/modules/${kernelver}/updates/dkms"
MODULES=("i915" "kvmgt")

# MOK key pair location — /var/lib/dkms/ is root-owned and persists across upgrades.
MOK_KEY="/var/lib/dkms/mok.key"
MOK_PUB="/var/lib/dkms/mok.pub"

# Detect what compression format the kernel uses.
# Strategy:
#   1. Examine a reference .ko* file from the kernel's own modules.
#   2. Fall back to kernel .config CONFIG_MODULE_COMPRESS_* settings.
#   3. Default to "none" (leave as-is) if detection fails.
detect_kernel_compression() {
    local ref
    ref=$(find "/lib/modules/${kernelver}/kernel/drivers/gpu/drm" \
        -name "drm.ko*" 2>/dev/null | head -1)
    [[ -z "${ref}" ]] && ref=$(find "/lib/modules/${kernelver}/kernel" \
        -name "*.ko*" 2>/dev/null | head -1)

    if [[ -n "${ref}" ]]; then
        case "${ref}" in
            *.ko.zst)  echo "zst";     return ;;
            *.ko.xz)
                if file "${ref}" 2>/dev/null | grep -q "CRC32"; then
                    echo "xz-crc32"
                else
                    echo "xz-crc64"
                fi
                return
                ;;
            *.ko.gz)   echo "gz";      return ;;
            *.ko)      echo "none";    return ;;
        esac
    fi

    # Fallback: read kernel build config
    local ksrc="/lib/modules/${kernelver}/build"
    local config=""
    if [[ -f "${ksrc}/.config" ]]; then
        config="${ksrc}/.config"
    elif [[ -f "/boot/config-${kernelver}" ]]; then
        config="/boot/config-${kernelver}"
    fi

    if [[ -n "${config}" ]]; then
        if grep -q "^CONFIG_MODULE_COMPRESS_ZSTD=y" "${config}"; then
            echo "zst"; return
        elif grep -q "^CONFIG_MODULE_COMPRESS_XZ=y" "${config}"; then
            # Can't detect CRC variant from config alone — assume CRC32
            # (safer: CRC32 is the Debian/upstream default for xz modules)
            echo "xz-crc32"; return
        elif grep -q "^CONFIG_MODULE_COMPRESS_GZIP=y" "${config}"; then
            echo "gz"; return
        fi
    fi

    echo "none"
}

recompress_module() {
    local name="$1"
    local fmt="$2"
    local base="${MODULES_DIR}/${name}.ko"

    # Find the currently installed module (any compression)
    local installed
    installed="$(find "${MODULES_DIR}" -maxdepth 1 -type f -name "${name}.ko*" -print 2>/dev/null | head -n 1 || true)"
    [[ -z "${installed}" ]] && return 0

    # Decompress to plain .ko if needed
    case "${installed}" in
        *.ko.xz)  xz -d "${installed}"; installed="${base}" ;;
        *.ko.zst) zstd -d --rm "${installed}"; installed="${base}" ;;
        *.ko.gz)  gunzip "${installed}"; installed="${base}" ;;
        *.ko)     : ;;  # already uncompressed
    esac

    # Recompress to target format
    local final_installed
    case "${fmt}" in
        zst)
            zstd -19 --rm "${installed}" -o "${base}.zst"
            final_installed="${base}.zst"
            echo "Recompressed ${name}.ko → ${name}.ko.zst" >&2
            ;;
        xz-crc32)
            xz -e --check=crc32 "${installed}"
            final_installed="${base}.xz"
            echo "Recompressed ${name}.ko → ${name}.ko.xz (CRC32)" >&2
            ;;
        xz-crc64|none)
            # Already correct or no compression needed — leave as-is
            final_installed="${installed}"
            ;;
    esac

    # Sync the recompressed file back into the DKMS build tree so that
    # 'dkms status' does not falsely report a diff between built and installed.
    local arch
    arch="$(uname -m)"
    local dkms_module_dir="/var/lib/dkms/${pkgname}/${pkgver}/${kernelver}/${arch}/module"
    if [[ -d "${dkms_module_dir}" && -n "${final_installed:-}" ]]; then
        cp -f "${final_installed}" "${dkms_module_dir}/${name}.ko${final_installed##*.ko}"
        # Remove stale copies with other extensions to avoid confusion.
        for ext in .xz .zst .gz ""; do
            local stale="${dkms_module_dir}/${name}.ko${ext}"
            [[ "${stale}" != "${dkms_module_dir}/${name}.ko${final_installed##*.ko}" ]] && rm -f "${stale}"
        done
    fi
}

fmt=$(detect_kernel_compression)
echo "Detected kernel module compression: ${fmt}" >&2

# Only recompress if the kernel uses a different format than DKMS produces (xz-crc64)
if [[ "${fmt}" == "xz-crc32" || "${fmt}" == "zst" ]]; then
    for mod in "${MODULES[@]}"; do
        recompress_module "${mod}" "${fmt}"
    done
    depmod "${kernelver}"
    echo "Module recompression complete." >&2
fi

# ---------------------------------------------------------------------------
# MOK key generation
# ---------------------------------------------------------------------------
# Idempotent: no-op if both key files already exist and mok.pub is valid DER.
# kmodsign and mokutil both require the certificate in DER (binary) format;
# the private key remains PEM.
generate_mok() {
    if [[ -f "${MOK_KEY}" && -f "${MOK_PUB}" ]]; then
        if openssl x509 -inform DER -noout -in "${MOK_PUB}" 2>/dev/null; then
            echo "MOK key pair already exists at ${MOK_KEY} / ${MOK_PUB}" >&2
            return 0
        fi
        echo "Existing ${MOK_PUB} is not DER-encoded — regenerating key pair..." >&2
    fi
    echo "Generating RSA-2048 MOK key pair..." >&2
    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '${tmpdir}'" RETURN
    # Step 1: generate PEM key + PEM self-signed cert
    openssl req -new -x509 -newkey rsa:2048 \
        -keyout "${MOK_KEY}" \
        -out    "${tmpdir}/mok.pem" \
        -days   36500 \
        -subj   "/CN=DKMS sriov-i915 signing key/" \
        -nodes 2>/dev/null
    # Step 2: convert PEM cert → DER (required by kmodsign and mokutil)
    openssl x509 -in "${tmpdir}/mok.pem" -outform DER -out "${MOK_PUB}"
    chmod 0400 "${MOK_KEY}"
    echo "MOK key pair generated (key: PEM, cert: DER)." >&2
}

# ---------------------------------------------------------------------------
# Secure Boot state helpers
# ---------------------------------------------------------------------------
is_secure_boot_active() {
    if ! command -v mokutil &>/dev/null; then
        return 1
    fi
    mokutil --sb-state 2>/dev/null | grep -q "SecureBoot enabled"
}

# Returns 0 if MOK_PUB fingerprint is already in the firmware MOK database.
is_mok_enrolled() {
    [[ -f "${MOK_PUB}" ]] || return 1
    command -v mokutil &>/dev/null || return 1

    local fingerprint
    fingerprint=$(openssl x509 -inform DER -noout -fingerprint -sha256 -in "${MOK_PUB}" 2>/dev/null \
        | sed 's/.*=//;s/://g' | tr '[:upper:]' '[:lower:]')
    [[ -z "${fingerprint}" ]] && return 1

    # mokutil --list-enrolled outputs lines like "SHA256 Fingerprint: AA:BB:..."
    mokutil --list-enrolled 2>/dev/null \
        | grep -i "SHA256 Fingerprint" \
        | sed 's/.*://;s/://g;s/ //g' \
        | tr '[:upper:]' '[:lower:]' \
        | grep -qF "${fingerprint}"
}

enroll_mok() {
    echo "Enrolling MOK key via mokutil..." >&2
    mokutil --import "${MOK_PUB}"
    cat >&2 <<'EOF'

  *** MOK ENROLLMENT REQUIRED ***
  The DKMS signing key has been staged for enrollment.
  REBOOT NOW and confirm the key at the UEFI MOK Manager prompt.
  After reboot, re-run:  modprobe i915
  Key location: /var/lib/dkms/mok.pub

EOF
}

# ---------------------------------------------------------------------------
# Module signing
# ---------------------------------------------------------------------------
# Locate the best available signing tool for this kernel.
find_signing_tool() {
    # kmodsign is the preferred wrapper (ships in linux-headers on Ubuntu,
    # linux-kbuild on Debian).
    if command -v kmodsign &>/dev/null; then
        echo "kmodsign"
        return
    fi

    # Fallback: scripts/sign-file compiled inside the kernel header tree.
    local sign_file="/lib/modules/${kernelver}/build/scripts/sign-file"
    if [[ -x "${sign_file}" ]]; then
        echo "${sign_file}"
        return
    fi

    echo "" # signal: no tool found
}

# Sign one module file in-place, preserving its compression format.
# Arg: full path to installed .ko[.xz|.zst|.gz] file.
sign_module_file() {
    local module_path="$1"
    local signing_tool="$2"
    local name
    name="$(basename "${module_path}")"
    name="${name%.ko*}"   # strip .ko + any compression suffix

    local tmpko
    tmpko="$(mktemp /tmp/dkms-sign-${name}-XXXXXX.ko)"
    # Ensure temp file is removed on exit from this function.
    trap "rm -f '${tmpko}'" RETURN

    # Decompress to plain .ko in tmp
    case "${module_path}" in
        *.ko.xz)  xz  -d -k -c "${module_path}" > "${tmpko}" ;;
        *.ko.zst) zstd -d -k -c "${module_path}" > "${tmpko}" ;;
        *.ko.gz)  gunzip -k -c "${module_path}"  > "${tmpko}" ;;
        *.ko)     cp "${module_path}" "${tmpko}"  ;;
    esac

    # Sign the uncompressed .ko
    if [[ "${signing_tool}" == "kmodsign" ]]; then
        kmodsign sha512 "${MOK_KEY}" "${MOK_PUB}" "${tmpko}"
    else
        # sign-file syntax: sign-file <hash> <key> <cert> <module> [<dest>]
        "${signing_tool}" sha512 "${MOK_KEY}" "${MOK_PUB}" "${tmpko}"
    fi

    # Recompress back to original format and replace in-place
    case "${module_path}" in
        *.ko.xz)
            # Preserve the CRC variant of the original file.
            if file "${module_path}" 2>/dev/null | grep -q "CRC32"; then
                xz -e --check=crc32 -c "${tmpko}" > "${module_path}.tmp"
            else
                xz -e -c "${tmpko}" > "${module_path}.tmp"
            fi
            mv "${module_path}.tmp" "${module_path}"
            ;;
        *.ko.zst)
            zstd -19 -c "${tmpko}" > "${module_path}.tmp"
            mv "${module_path}.tmp" "${module_path}"
            ;;
        *.ko.gz)
            gzip -c "${tmpko}" > "${module_path}.tmp"
            mv "${module_path}.tmp" "${module_path}"
            ;;
        *.ko)
            cp "${tmpko}" "${module_path}"
            ;;
    esac

    echo "Signed: ${module_path}" >&2
}

# ---------------------------------------------------------------------------
# Signing orchestration
# ---------------------------------------------------------------------------
# Note on DKMS 3.x: dkms.conf declares SIGN_KEY/SIGN_CERT pointing to our
# MOK key pair.  DKMS 3.x uses those directives to sign modules BEFORE
# POST_INSTALL runs, so modules will already carry "DKMS sriov-i915 signing
# key" when we get here.  We detect that case and skip re-signing.
# On DKMS 2.x (Debian, RHEL, older Ubuntu) these directives are ignored and
# we sign here as the sole signing path.
generate_mok   # idempotent; key was already created by PRE_BUILD under DKMS

signing_tool=$(find_signing_tool)

if [[ -z "${signing_tool}" ]]; then
    echo "WARNING: No module signing tool found (kmodsign / scripts/sign-file)." >&2
    echo "         Install linux-headers-${kernelver} or linux-kbuild to enable signing." >&2
else
    if is_secure_boot_active; then
        if ! is_mok_enrolled; then
            enroll_mok
        else
            echo "MOK key already enrolled in firmware." >&2
        fi
    else
        echo "Secure Boot is not active — modules will be signed but enrollment is not required." >&2
    fi

    signed_count=0
    skipped_count=0
    for mod in "${MODULES[@]}"; do
        module_file=$(ls "${MODULES_DIR}/${mod}.ko"* 2>/dev/null | head -1) || true
        if [[ -z "${module_file}" ]]; then
            echo "WARNING: ${mod}.ko not found in ${MODULES_DIR} — skipping signing." >&2
            continue
        fi
        # Check if this module is already signed with our key (DKMS 3.x path).
        existing_signer=$(modinfo -F signer "${module_file}" 2>/dev/null || true)
        if [[ "${existing_signer}" == "DKMS sriov-i915 signing key" ]]; then
            echo "Already signed by our key: ${module_file}" >&2
            skipped_count=$((skipped_count + 1))
            continue
        fi
        sign_module_file "${module_file}" "${signing_tool}"
        signed_count=$((signed_count + 1))
    done
    if [[ "${skipped_count}" -gt 0 && "${signed_count}" -eq 0 ]]; then
        echo "All modules already signed by DKMS 3.x with our key — no re-signing needed." >&2
    else
        echo "Module signing complete (${signed_count} signed, ${skipped_count} already signed, kernel ${kernelver})." >&2
    fi
fi
