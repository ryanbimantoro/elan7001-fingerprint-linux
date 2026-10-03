#!/usr/bin/env bash

set -Eeuo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ROOT="${HOME}/fingerprint-kit-build"
SOURCE_DIR="${BUILD_ROOT}/libfprint"
BUILD_DIR="${SOURCE_DIR}/build"

BASE_REPO="https://github.com/goodix-fp-linux-dev/libfprint.git"
BASE_COMMIT="07306bbc9256942595e31fb0f407b364ffa24d07"

PATCH_FILE="${KIT_DIR}/patches/elanspi-3104-sigfm.patch"
PATCH_SHA256="8448fa69bcfebfe8e3b98fd6382d96a7a8e5092707c51d055fb31cc62aa66e8c"

SPI_CONFIG="${KIT_DIR}/config/elan-spidev.conf"
SPI_CONFIG_DEST="/etc/modprobe.d/elan-spidev.conf"

PREFIX="/usr/local"
LIBDIR="lib/x86_64-linux-gnu"

log() {
    printf '\n=== %s ===\n' "$1"
}

die() {
    printf '\n[FAIL] %s\n' "$1" >&2
    exit 1
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 ||
        die "Required command not found: $1"
}

cleanup_on_error() {
    printf '\n[FAIL] Installer stopped. No rollback was attempted.\n' >&2
}

trap cleanup_on_error ERR

# ------------------------------------------------------------
# Preflight
# ------------------------------------------------------------

log "PRECHECK"

[[ "${EUID}" -eq 0 ]] &&
    die "Do not run install.sh as root. Run it as the normal user."

need_cmd bash
need_cmd git
need_cmd meson
need_cmd ninja
need_cmd pkg-config
need_cmd sha256sum
need_cmd ldconfig
need_cmd sudo

[[ -x "${KIT_DIR}/verify.sh" ]] ||
    die "verify.sh is missing or not executable."

[[ -f "${PATCH_FILE}" ]] ||
    die "Patch file not found: ${PATCH_FILE}"

[[ -f "${SPI_CONFIG}" ]] ||
    die "SPI configuration not found: ${SPI_CONFIG}"

# ------------------------------------------------------------
# Hardware gate
# ------------------------------------------------------------

log "HARDWARE COMPATIBILITY GATE"

"${KIT_DIR}/verify.sh"

# ------------------------------------------------------------
# Patch integrity
# ------------------------------------------------------------

log "PATCH INTEGRITY"

ACTUAL_PATCH_SHA256="$(sha256sum "${PATCH_FILE}" | awk '{print $1}')"

echo "Expected: ${PATCH_SHA256}"
echo "Actual  : ${ACTUAL_PATCH_SHA256}"

[[ "${ACTUAL_PATCH_SHA256}" == "${PATCH_SHA256}" ]] ||
    die "Patch SHA-256 mismatch."

echo "[ OK ] Patch integrity verified."

# ------------------------------------------------------------
# Build dependencies
# ------------------------------------------------------------

log "BUILD DEPENDENCY CHECK"

REQUIRED_PKGS=(
    build-essential
    meson
    ninja-build
    pkg-config
    libglib2.0-dev
    libgusb-dev
    libgudev-1.0-dev
    libopencv-dev
    fprintd
    libpam-fprintd
)

MISSING_PKGS=()

for pkg in "${REQUIRED_PKGS[@]}"; do
    if dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null |
        grep -q '^install ok installed$'; then
        echo "[ OK ] ${pkg}"
    else
        echo "[MISS] ${pkg}"
        MISSING_PKGS+=("${pkg}")
    fi
done

if (( ${#MISSING_PKGS[@]} > 0 )); then
    echo
    echo "Missing packages:"
    printf '  %s\n' "${MISSING_PKGS[@]}"
    echo
    echo "Installing missing dependencies..."

    sudo apt-get update
    sudo apt-get install -y "${MISSING_PKGS[@]}"
fi

# ------------------------------------------------------------
# Prepare source
# ------------------------------------------------------------

log "SOURCE PREPARATION"

mkdir -p "${BUILD_ROOT}"

if [[ -d "${SOURCE_DIR}/.git" ]]; then
    echo "Existing source tree detected:"
    echo "  ${SOURCE_DIR}"

    cd "${SOURCE_DIR}"

    CURRENT_REMOTE="$(git remote get-url origin 2>/dev/null || true)"

    if [[ "${CURRENT_REMOTE}" != "${BASE_REPO}" ]]; then
        die "Existing repository remote mismatch: ${CURRENT_REMOTE}"
    fi

    git fetch --no-tags origin "${BASE_COMMIT}"
else
    rm -rf "${SOURCE_DIR}"

    git clone --no-tags "${BASE_REPO}" "${SOURCE_DIR}"

    cd "${SOURCE_DIR}"

    git fetch --no-tags origin "${BASE_COMMIT}"
fi

git checkout --detach "${BASE_COMMIT}"

CURRENT_COMMIT="$(git rev-parse HEAD)"

[[ "${CURRENT_COMMIT}" == "${BASE_COMMIT}" ]] ||
    die "Failed to reach required base commit."

echo "Base repository: ${BASE_REPO}"
echo "Base commit    : ${CURRENT_COMMIT}"

# ------------------------------------------------------------
# Clean source requirement
# ------------------------------------------------------------

log "SOURCE CLEANLINESS"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Existing modifications detected:"
    git status --short
    die "Source tree is not clean. Installer will not overwrite it."
fi

echo "[ OK ] Source tree is clean."

# ------------------------------------------------------------
# Apply patch
# ------------------------------------------------------------

log "APPLY KIT PATCH"

git apply --check "${PATCH_FILE}"
git apply "${PATCH_FILE}"

echo "[ OK ] Patch applied."

# ------------------------------------------------------------
# Verify patched source
# ------------------------------------------------------------

log "PATCHED SOURCE VERIFICATION"

PATCHED_FILES="$(git diff --name-only)"

echo "${PATCHED_FILES}"

EXPECTED_FILES=$'libfprint/drivers/elanspi.c\nlibfprint/drivers/elanspi.h'

[[ "${PATCHED_FILES}" == "${EXPECTED_FILES}" ]] ||
    die "Unexpected patched files."

# ------------------------------------------------------------
# Configure Meson
# ------------------------------------------------------------

log "MESON CONFIGURATION"

rm -rf "${BUILD_DIR}"

meson setup "${BUILD_DIR}" \
    --prefix="${PREFIX}" \
    -Ddrivers=elanspi \
    -Dudev_rules=disabled \
    -Dudev_hwdb=disabled \
    -Ddoc=false

# ------------------------------------------------------------
# Build
# ------------------------------------------------------------

log "BUILD"

ninja -C "${BUILD_DIR}"

# ------------------------------------------------------------
# Install
# ------------------------------------------------------------

log "INSTALL LIBFPRINT"

sudo ninja -C "${BUILD_DIR}" install

# ------------------------------------------------------------
# SPI configuration
# ------------------------------------------------------------

log "SPI CONFIGURATION"

sudo install -D \
    -m 0644 \
    "${SPI_CONFIG}" \
    "${SPI_CONFIG_DEST}"

echo "Installed:"
echo "  ${SPI_CONFIG_DEST}"

# ------------------------------------------------------------
# Verify SPI module configuration
# ------------------------------------------------------------

log "SPI MODULE VERIFICATION"

SPI_BUFSIZ_PATH="/sys/module/spidev/parameters/bufsiz"

if [[ -r "${SPI_BUFSIZ_PATH}" ]]; then
    CURRENT_SPI_BUFSIZ="$(cat "${SPI_BUFSIZ_PATH}")"
    echo "Current spidev bufsiz:"
    echo "  ${CURRENT_SPI_BUFSIZ}"

    if [[ "${CURRENT_SPI_BUFSIZ}" == "32768" ]]; then
        echo "[ OK ] spidev bufsiz=32768 is active."
    else
        echo "[WARN] spidev bufsiz is ${CURRENT_SPI_BUFSIZ}, expected 32768."
        echo "[WARN] The configuration file is installed, but the running"
        echo "       spidev module has not picked up the new parameter yet."
        echo "[WARN] Reboot is recommended before fingerprint enrollment."
    fi
else
    echo "[WARN] ${SPI_BUFSIZ_PATH} is unavailable."
    echo "[WARN] The spidev module may not currently be loaded."
    echo "[WARN] Reboot is recommended after installation."
fi

# ------------------------------------------------------------
# Dynamic linker cache
# ------------------------------------------------------------

log "LD CONFIGURATION"

sudo ldconfig

# ------------------------------------------------------------
# Verify installed library
# ------------------------------------------------------------

log "LIBRARY VERIFICATION"

RESOLVED_LIB="$(
    ldconfig -p |
        awk '/libfprint-2\.so\.2/{print $NF; exit}'
)"

echo "Resolved libfprint:"
echo "  ${RESOLVED_LIB}"

[[ "${RESOLVED_LIB}" == "${PREFIX}/"* ]] ||
    die "Custom /usr/local libfprint is not first in linker resolution."

echo "[ OK ] Custom libfprint is active."

# ------------------------------------------------------------
# Runtime verification
# ------------------------------------------------------------

log "RUNTIME VERIFICATION"

if command -v fprintd-list >/dev/null 2>&1; then
    fprintd-list "${USER}" || true
else
    echo "[WARN] fprintd-list is unavailable."
fi

echo
echo "=== INSTALL COMPLETE ==="
echo
echo "Installed custom libfprint:"
echo "  ${RESOLVED_LIB}"
echo
echo "SPI configuration:"
echo "  ${SPI_CONFIG_DEST}"
echo
echo "NOT modified by this installer:"
echo "  PAM configuration"
echo "  fingerprint enrollment"
echo "  fingerprint database"
echo "  Ubuntu libfprint package"
echo "  broad udev permissions"
echo
echo "Next step:"
echo "  Verify the fingerprint device and enroll manually."
