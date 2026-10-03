# Fingerprint Kit v1

Reproducible Linux fingerprint setup for ASUS VivoBook X513EA / K513EA
with ELAN7001 SPI fingerprint hardware.

## Target Hardware

This kit was developed and verified on:

- ASUS VivoBook X513EA / K513EA
- DMI product: `VivoBook_ASUSLaptop X513EA_K513EA`
- Board: `X513EA`
- BIOS tested: `X513EA.318`
- ACPI fingerprint device: `ELAN7001:00`
- SPI device: `spi-ELAN7001:00`
- SPI userspace device: `/dev/spidev0.0`
- Fingerprint companion HID: `04F3:3104`
- Sensor: ELAN7001 / eFSA80SC
- Sensor interface: SPI
- Sensor resolution: 80x80

The kit is hardware-specific. A different laptop should pass
`verify.sh` before the installer is used.

## Tested Software

Reference system:

- Ubuntu 26.04.1 LTS
- x86_64
- Kernel: `7.0.0-34-generic`
- fprintd: `1.94.5-4`
- libfprint-2-2: `1:1.95.1+tod1-0ubuntu2`
- libfprint-2-tod1: `1:1.95.1+tod1-0ubuntu2`
- libpam-fprintd: `1.94.5-4`

A different kernel may still work, but kernel differences are not
automatically considered incompatible by `verify.sh`.

## Why This Kit Exists

The Windows driver confirms that the fingerprint hardware works:

- Windows device: `ELAN WBF Fingerprint Sensor`
- ACPI ID: `ELAN7001`
- HID companion: `04F3:3104`
- Windows driver version: `4.5.11001.11701`

On Ubuntu, the stock libfprint ELAN SPI driver expects a matching
HIDRAW device in addition to the SPI device.

This hardware exposes the fingerprint sensor through:

    ELAN7001 -> SPI -> spidev -> /dev/spidev0.0

while the available HID device is:

    04F3:3104 -> hid-multitouch

The stock device matching therefore does not detect the fingerprint
sensor correctly on this hardware.

## Solution

The kit builds a custom libfprint containing the required ELAN SPI
support for HID `04F3:3104`.

The patch:

- adds the ELAN7001 + HID 04F3:3104 device combination
- uses the existing ELAN SPI driver
- applies Gaussian smoothing suitable for the sensor image
- uses the SIGFM matching algorithm
- keeps the native sensor image scale
- configures the required ELAN SPI device entry

The patch is based on the community project:

    https://github.com/r4nd3l/elan-3104-fingerprint-linux

The libfprint source is based on:

    https://github.com/goodix-fp-linux-dev/libfprint.git

Base commit:

    07306bbc9256942595e31fb0f407b364ffa24d07

Community repository HEAD tested:

    a8b8af8e0100f5bfb4dbee87b60bfcfb887b0af6

Patch SHA-256:

    8448fa69bcfebfe8e3b98fd6382d96a7a8e5092707c51d055fb31cc62aa66e8c

## Build Configuration

The installer uses:

    meson setup build \
      --prefix=/usr/local \
      -Ddrivers=elanspi \
      -Dudev_rules=disabled \
      -Dudev_hwdb=disabled \
      -Ddoc=false

The custom library is installed under:

    /usr/local/lib/x86_64-linux-gnu/

The active library should resolve to:

    /usr/local/lib/x86_64-linux-gnu/libfprint-2.so.2

The Ubuntu system libfprint package is not removed or replaced.

## SPI Configuration

The kit installs:

    /etc/modprobe.d/elan-spidev.conf

with:

    options spidev bufsiz=32768

The tested runtime value is:

    /sys/module/spidev/parameters/bufsiz
    32768

The larger SPI buffer is required by the tested configuration.

## Installer Behavior

Run:

    ./install.sh

The installer:

1. Checks the hardware target.
2. Checks required tools.
3. Checks the required source patch.
4. Installs missing build/runtime dependencies.
5. Fetches the pinned libfprint source.
6. Checks out the exact tested base commit.
7. Verifies the patch checksum.
8. Applies the patch.
9. Builds libfprint.
10. Installs the custom library under `/usr/local`.
11. Installs the SPI modprobe configuration.
12. Runs `ldconfig`.
13. Verifies that the custom library is active.
14. Verifies the fingerprint device through fprintd.

The installer does NOT:

- enroll fingerprints
- copy fingerprint enrollment data
- modify the fingerprint database
- manually edit PAM configuration
- remove Ubuntu's libfprint package
- install broad `udev` permissions
- perform a system upgrade
- modify unrelated hardware configuration
- reboot the system automatically

## Hardware Verification

Before installation, run:

    ./verify.sh

The verification script is read-only.

It checks:

- x86_64 architecture
- Ubuntu
- ASUS X513EA/K513EA hardware
- ACPI `ELAN7001`
- SPI `spidev`
- `/dev/spidev0.0`
- SPI buffer size `32768`
- HID `04F3:3104`
- fprintd availability
- custom libfprint presence
- active libfprint resolution
- PAM fingerprint configuration
- tested kernel baseline

A successful result should end with:

    RESULT: HARDWARE COMPATIBILITY PASS

and:

    FAIL : 0

## Fingerprint Enrollment

Enrollment is intentionally manual.

After installation:

    fprintd-list "$USER"

Then enroll a fingerprint:

    fprintd-enroll "$USER"

The kit does not contain or distribute fingerprint enrollment data.

Each user must enroll their own fingerprints on their own machine.

## Authentication

PAM fingerprint authentication can be enabled through:

    sudo pam-auth-update --enable fprintd

The reference machine was verified with fingerprint authentication
through `sudo`.

Password authentication remains available as a fallback.

The installer does not automatically change PAM configuration.

## Known Behavior

Fingerprint matching is not perfectly consistent.

The reference machine has shown:

- successful enrollment
- successful fingerprint verification
- successful sudo fingerprint authentication
- occasional `swipe-too-short`
- occasional failed matching followed by password fallback

This behavior was observed during testing and was intentionally left
unchanged.

The kit does not attempt additional algorithm or sensor tuning beyond
the tested patch.

## Reproducibility

The kit intentionally pins the libfprint base commit and verifies the
patch checksum.

Important files:

    install.sh
    verify.sh
    manifest.txt
    patches/elanspi-3104-sigfm.patch
    config/elan-spidev.conf
    README.md

The kit can therefore be copied to another compatible machine and
audited before installation.

## Compatibility Boundary

This kit should NOT be treated as a universal ELAN fingerprint
installer.

The known target is:

    ASUS X513EA / K513EA
    ACPI ELAN7001
    HID 04F3:3104
    SPI fingerprint sensor

If another machine does not match the expected hardware, stop at
`verify.sh` and investigate that machine separately.

Do not force-install the kit merely because the laptop appears to be
another ASUS VivoBook.

## Reference Verification

Reference machine result:

    PASS : 17
    WARN : 0
    FAIL : 0

Verified:

    Ubuntu 26.04.1 LTS
    Kernel 7.0.0-34-generic
    ASUS X513EA
    ELAN7001
    SPI spidev
    /dev/spidev0.0
    spidev bufsiz=32768
    HID 04F3:3104
    custom libfprint active
    PAM fingerprint enabled

## License & Attribution

The included `patches/elanspi-3104-sigfm.patch` is derived from
libfprint and adapted from the following community project:

    https://github.com/r4nd3l/elan-3104-fingerprint-linux

The upstream-derived patch is distributed under the GNU Lesser General
Public License, version 2.1 or later (LGPL-2.1-or-later).

The corresponding license text is included in `LICENSE`.

The kit's custom installer, verification script, documentation, and
metadata were assembled specifically for the tested ASUS X513EA /
K513EA configuration described in this repository.

## Files

### install.sh

Rebuilds and installs the tested custom libfprint stack.

### verify.sh

Read-only compatibility and installation verification.

### patches/elanspi-3104-sigfm.patch

Exact tested source patch.

### config/elan-spidev.conf

Persistent SPI buffer configuration.

### manifest.txt

Machine, dependency, source, patch, and build metadata.

### README.md

This documentation.

## Version

Fingerprint Kit v1

Reference hardware:

    ASUS VivoBook X513EA / K513EA

Reference OS:

    Ubuntu 26.04.1 LTS
