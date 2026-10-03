#!/usr/bin/env bash

set -u

PASS=0
WARN=0
FAIL=0

ok() {
    printf '[ OK ] %s\n' "$1"
    PASS=$((PASS + 1))
}

warn() {
    printf '[WARN] %s\n' "$1"
    WARN=$((WARN + 1))
}

fail() {
    printf '[FAIL] %s\n' "$1"
    FAIL=$((FAIL + 1))
}

echo "=== FINGERPRINT KIT v1 — HARDWARE COMPATIBILITY VERIFY ==="
echo

# ------------------------------------------------------------
# Architecture
# ------------------------------------------------------------
echo "--- ARCHITECTURE ---"
ARCH="$(uname -m)"

if [[ "$ARCH" == "x86_64" ]]; then
    ok "Architecture: $ARCH"
else
    fail "Architecture mismatch: $ARCH (expected x86_64)"
fi

echo

# ------------------------------------------------------------
# OS
# ------------------------------------------------------------
echo "--- OS ---"

if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    echo "Detected: ${PRETTY_NAME:-unknown}"

    if [[ "${ID:-}" == "ubuntu" ]]; then
        ok "Ubuntu detected"
    else
        warn "Non-Ubuntu OS detected: ${ID:-unknown}"
    fi
else
    warn "/etc/os-release not readable"
fi

echo

# ------------------------------------------------------------
# DMI / ASUS model
# ------------------------------------------------------------
echo "--- SYSTEM MODEL ---"

DMI_PRODUCT="$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || true)"
DMI_SYS_VENDOR="$(cat /sys/devices/virtual/dmi/id/sys_vendor 2>/dev/null || true)"
DMI_BOARD="$(cat /sys/devices/virtual/dmi/id/board_name 2>/dev/null || true)"
DMI_BIOS="$(cat /sys/devices/virtual/dmi/id/bios_version 2>/dev/null || true)"

echo "sys_vendor : ${DMI_SYS_VENDOR:-unknown}"
echo "product    : ${DMI_PRODUCT:-unknown}"
echo "board      : ${DMI_BOARD:-unknown}"
echo "BIOS       : ${DMI_BIOS:-unknown}"

if [[ "$DMI_SYS_VENDOR" == "ASUSTeK COMPUTER INC." &&
      "$DMI_PRODUCT" == *"X513EA"* ]]; then
    ok "ASUS X513EA hardware detected"
elif [[ "$DMI_SYS_VENDOR" == "ASUSTeK COMPUTER INC." &&
        "$DMI_PRODUCT" == *"K513EA"* ]]; then
    ok "ASUS K513EA hardware detected"
else
    fail "Expected ASUS X513EA/K513EA hardware"
fi

echo

# ------------------------------------------------------------
# ACPI ELAN7001
# ------------------------------------------------------------
echo "--- ACPI FINGERPRINT ---"

ACPI_PATH="/sys/bus/acpi/devices/ELAN7001:00"

if [[ -d "$ACPI_PATH" ]]; then
    ok "ACPI device ELAN7001:00 exists"

    if [[ -e "$ACPI_PATH/physical_node" ]]; then
        ok "ELAN7001 physical node exists"
        readlink -f "$ACPI_PATH/physical_node" || true
    else
        warn "ELAN7001 physical_node missing"
    fi
else
    fail "ACPI device ELAN7001:00 not found"
fi

echo

# ------------------------------------------------------------
# SPI device
# ------------------------------------------------------------
echo "--- SPI ---"

SPI_PATH="/sys/bus/spi/devices/spi-ELAN7001:00"

if [[ -d "$SPI_PATH" ]]; then
    ok "SPI device spi-ELAN7001:00 exists"

    if [[ -L "$SPI_PATH/driver" ]]; then
        SPI_DRIVER="$(basename "$(readlink -f "$SPI_PATH/driver")")"
        echo "driver: $SPI_DRIVER"

        if [[ "$SPI_DRIVER" == "spidev" ]]; then
            ok "ELAN7001 is bound to spidev"
        else
            warn "ELAN7001 is bound to '$SPI_DRIVER', expected spidev"
        fi
    else
        warn "SPI driver symlink missing"
    fi
else
    fail "SPI device spi-ELAN7001:00 not found"
fi

if [[ -e /dev/spidev0.0 ]]; then
    ok "/dev/spidev0.0 exists"
else
    fail "/dev/spidev0.0 not found"
fi

echo

# ------------------------------------------------------------
# SPI buffer
# ------------------------------------------------------------
echo "--- SPI BUFFER ---"

SPI_BUFSIZ="$(cat /sys/module/spidev/parameters/bufsiz 2>/dev/null || true)"

if [[ -n "$SPI_BUFSIZ" ]]; then
    echo "spidev bufsiz: $SPI_BUFSIZ"

    if [[ "$SPI_BUFSIZ" == "32768" ]]; then
        ok "spidev bufsiz = 32768"
    else
        fail "spidev bufsiz = $SPI_BUFSIZ (expected 32768)"
    fi
else
    fail "Unable to read spidev bufsiz"
fi

echo

# ------------------------------------------------------------
# HID companion
# ------------------------------------------------------------
echo "--- HID COMPANION ---"

HID_MATCH=0

for hid in /sys/class/hidraw/hidraw*/device; do
    [[ -d "$hid" ]] || continue

    HID_ID="$(cat "$hid/uevent" 2>/dev/null | sed -n 's/^HID_ID=//p')"

    if [[ "$HID_ID" == *"000004F3:00003104"* ]]; then
        HID_MATCH=1
        echo "Matched HID: $hid"
        echo "HID_ID: $HID_ID"

        if [[ -r "$hid/uevent" ]]; then
            cat "$hid/uevent" | grep -E '^(HID_ID|HID_NAME|DRIVER)=' || true
        fi

        break
    fi
done

if [[ "$HID_MATCH" -eq 1 ]]; then
    ok "HID companion 04F3:3104 detected"
else
    fail "HID companion 04F3:3104 not found"
fi

echo

# ------------------------------------------------------------
# libfprint / fprintd
# ------------------------------------------------------------
echo "--- FPRINT STACK ---"

if command -v fprintd-list >/dev/null 2>&1; then
    ok "fprintd-list available"
else
    warn "fprintd-list not installed"
fi

if command -v fprintd-enroll >/dev/null 2>&1; then
    ok "fprintd-enroll available"
else
    warn "fprintd-enroll not installed"
fi

LIBFP="$(ldconfig -p 2>/dev/null | awk '/libfprint-2\.so\.2/{print $NF; exit}')"

CUSTOM_LIB="/usr/local/lib/x86_64-linux-gnu/libfprint-2.so.2"

if [[ -e "$CUSTOM_LIB" ]]; then
    ok "Custom libfprint exists: $CUSTOM_LIB"
else
    fail "Custom libfprint not found: $CUSTOM_LIB"
fi

if [[ -n "$LIBFP" ]]; then
    echo "libfprint resolved to: $LIBFP"

    if [[ "$LIBFP" == "$CUSTOM_LIB" ]]; then
        ok "Custom /usr/local libfprint is active"
    else
        fail "System libfprint is active instead of custom /usr/local library"
    fi
else
    fail "libfprint-2.so.2 not found via ldconfig"
fi

echo

# ------------------------------------------------------------
# PAM
# ------------------------------------------------------------
echo "--- PAM ---"

if [[ -f /usr/share/pam-configs/fprintd ]]; then
    ok "pam-auth-update fprintd profile exists"
else
    warn "fprintd PAM profile not found"
fi

if grep -Eq 'pam_fprintd\.so' /etc/pam.d/common-auth 2>/dev/null; then
    ok "Fingerprint authentication is enabled in common-auth"
else
    warn "pam_fprintd is not enabled in common-auth"
fi

echo

# ------------------------------------------------------------
# Kernel
# ------------------------------------------------------------
echo "--- KERNEL ---"

KERNEL="$(uname -r)"
echo "Kernel: $KERNEL"

if [[ "$KERNEL" == "7.0.0-34-generic" ]]; then
    ok "Known tested kernel"
else
    warn "Kernel differs from tested baseline"
fi

echo

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------
echo "=== SUMMARY ==="
echo "PASS : $PASS"
echo "WARN : $WARN"
echo "FAIL : $FAIL"
echo

if [[ "$FAIL" -eq 0 ]]; then
    echo "RESULT: HARDWARE COMPATIBILITY PASS"
    echo "No system changes were made."
    exit 0
else
    echo "RESULT: HARDWARE COMPATIBILITY FAIL"
    echo "No system changes were made."
    exit 1
fi
