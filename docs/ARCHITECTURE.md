# ELAN7001 Fingerprint Linux Support Kit — Architecture

## 1. Project Overview

This document describes the hardware, software, fingerprint-processing pipeline, and verification behavior investigated for the ELAN7001 fingerprint sensor on the ASUS VivoBook X513EA/K513EA.

The purpose is to provide a source-grounded reference for maintaining the driver integration, investigating matching reliability, and evaluating potential algorithm improvements.

The guiding principle is:

**Observe → Identify → Verify → Change → Test → Benchmark → Keep only useful changes.**

Do not modify the driver or matching algorithm merely because a change appears reasonable. First establish the current behavior, identify the relevant code path, design a focused test, and preserve a reproducible baseline.

### Evidence labels

* **Verified:** Directly observed in source code, command output, or a repeatable test.
* **Observed:** Seen during interactive use but not validated under controlled conditions.
* **Hypothesis:** A plausible explanation requiring further evidence.
* **Open question:** Not yet resolved.

Hardware compatibility, successful enrollment, and successful verification are separate properties. A sensor can communicate successfully while image acquisition or matching remains unreliable.

## 2. Target Hardware and Operating System

### Laptop

* Manufacturer/model family: ASUS VivoBook X513EA/K513EA.
* CPU: Intel Core i5-1135G7.
* Integrated graphics: Intel Iris Xe.
* Firmware version observed: X513EA.318.
* Operating system: Ubuntu 26.04.1 LTS.
* Kernel versions observed during investigation include `7.0.0-34-generic`.

Exact configuration may differ between installations. Reconfirm it before reproducing a result.

### Fingerprint sensor

The investigated device is exposed through the ELAN SPI fingerprint path.

| Item                         | Observation                                    | Evidence status                                                             |
| ---------------------------- | ---------------------------------------------- | --------------------------------------------------------------------------- |
| ACPI/device name             | `ELAN7001`                                     | Observed                                                                    |
| SPI device                   | `/dev/spidev0.0` appeared during investigation | Observed                                                                    |
| Companion HID identifier     | `04F3:3104`                                    | Observed                                                                    |
| Community sensor description | `eFSA80SC`, 80×80                              | Reported by project manifest/community sources; not independently confirmed |
| Sensor protocol              | ELAN SPI driver path                           | Verified in the investigated software integration                           |

The companion HID identifier should not automatically be treated as the fingerprint sensor's SPI identifier. A device can expose multiple interfaces for different functions.

The exact silicon model, firmware revision, and electrical/protocol specification remain open questions unless confirmed by authoritative hardware documentation.

### Windows reference package

The Windows driver package observed during research was:

`Fingerprint_WBF_SPI_DCH_ELAN_Z_V4.5.11001.11701_24283_2.exe`

Reported package version: `4.5.11001.11701`, dated 2021-08-18.

This is useful as a reference for the vendor-supported configuration, but the existence of a Windows driver does not establish that its internal algorithm or protocol details are known.

## 3. High-Level Architecture

The Linux fingerprint path consists of several layers:

1. Physical sensor and platform interfaces.
2. Kernel interfaces and device enumeration.
3. libfprint's ELAN SPI driver.
4. Image acquisition and preprocessing.
5. Feature extraction and template storage.
6. Matching and threshold evaluation.
7. fprintd user-space service.
8. PAM integration for applications such as `sudo`.

Each layer can fail independently.

For example:

* Device discovery can succeed while SPI communication fails.
* SPI communication can succeed while captured frames are unusable.
* Image acquisition can succeed while feature extraction finds too few keypoints.
* Feature extraction can succeed while genuine-user matching fails.
* Matching can succeed while PAM configuration prevents authentication.
* Repeated acquisition can trigger a hardware or driver safety shutdown.

Troubleshooting should identify the failing layer before changing other layers.

## 4. Windows Architecture

Windows uses the Windows Biometric Framework (WBF) to expose supported biometric devices to applications and the operating system.

The observed ELAN package is a reference point for the supported Windows configuration. However, the exact internal pipeline, image transformations, template format, and matcher used by the vendor package have not been established from the available evidence.

Do not assume that the Windows driver and the Linux SIGFM implementation use the same feature extractor or matching algorithm.

A useful future investigation would compare:

* Device identification and firmware behavior.
* Enrollment requirements and capture feedback.
* Retry and timeout behavior.
* Whether the sensor requires specific initialization sequences.
* Whether vendor documentation describes image orientation or image format.

Avoid reverse-engineering or redistributing proprietary components without first checking the applicable license and legal constraints.

## 5. Linux Hardware Discovery

The investigation identified an ELAN SPI path associated with `ELAN7001` and a companion HID identifier `04F3:3104`.

Useful diagnostic commands include:

```bash
uname -a
cat /etc/os-release

ls -l /dev/spidev*
lsusb

grep -R . /sys/bus/spi/devices/*/modalias 2>/dev/null
grep -R . /sys/bus/spi/devices/*/uevent 2>/dev/null

sudo journalctl -k -b --no-pager
```

Not every command will return useful output on every installation. For example, `/dev/spidev0.0` may be absent when a kernel driver owns the SPI device or when the device has not been exposed through spidev.

Do not conclude that the fingerprint hardware is absent solely because it does not appear as a conventional USB fingerprint device.

### Hardware identity caveat

`ELAN7001`, the SPI interface, and `04F3:3104` are useful identifiers for this particular investigation. They should not be generalized to every ASUS VivoBook or every ELAN fingerprint sensor.

## 6. Linux Software Architecture

### libfprint

libfprint implements fingerprint-device support and matching interfaces used by applications and services.

The investigated integration adds support for the ELAN SPI device and selects SIGFM matching for the relevant driver configuration.

The source repository used as a baseline was:

`https://github.com/goodix-fp-linux-dev/libfprint.git`

Investigated baseline commit:

`07306bbc9256942595e31fb0f407b364ffa24d07`

The local source tree had modifications in:

* `libfprint/drivers/elanspi.c`
* `libfprint/drivers/elanspi.h`

These changes must be reviewed separately from the upstream baseline when reproducing the build.

### Community integration

The community integration investigated was:

`https://github.com/r4nd3l/elan-3104-fingerprint-linux.git`

The observed HEAD was:

`a8b8af8e0100f5bfb4bee87b60bfcfb887b0af6`

A patch used during the investigation had SHA-256:

`8448fa69bcfebfe8e3b98fd6382d96a7a8e5092707c51d055fb31cc62aa66e8c`

Always verify a patch hash against the actual patch file before treating it as a reproducible artifact.

### Build and installation

The investigated custom build used:

* Prefix: `/usr/local`
* Library directory: `lib/x86_64-linux-gnu`
* Driver selection: `elanspi`
* Documentation generation disabled.
* udev rules and hardware database generation disabled in that build configuration.

The build completed with 99/99 reported targets in the observed run.

The resulting custom library was installed at:

`/usr/local/lib/x86_64-linux-gnu/libfprint-2.so.2.0.0`

The custom library was observed resolving ahead of the distribution-provided library.

This can affect all applications using libfprint, not only the fingerprint enrollment utility. Keep a record of the active library path and build revision when diagnosing behavior.

Useful checks:

```bash
ldconfig -p | grep libfprint
find /usr/local/lib -name 'libfprint-2.so*' -print 2>/dev/null
find /usr/lib -name 'libfprint-2.so*' -print 2>/dev/null
```

The precise runtime resolution should be confirmed on the machine where the test is performed.

### fprintd and PAM

Observed versions:

* fprintd: `1.94.5-4`
* Distribution libfprint package: `1:1.95.1+tod1-0ubuntu2`
* PAM integration package: `1.94.5-4`

The custom libfprint build and distribution fprintd package are separate components. Updating one does not necessarily update the other.

PAM configuration should be treated as an authentication-policy change. Before enabling or modifying fingerprint authentication, retain a working password-based recovery path.

## 7. Fingerprint Processing Pipeline

The investigated matching path can be summarized as:

1. Acquire an image from the sensor.
2. Apply the ELAN driver's configured image handling.
3. Extract keypoints and descriptors through SIGFM's image-processing implementation.
4. Reject extraction if too few keypoints are found.
5. Compare descriptors between the enrolled template and the captured image.
6. Filter candidate correspondences.
7. Evaluate geometric consistency.
8. Produce a score.
9. Compare the score with the configured threshold.
10. Return a match, no-match, or error result.

A failure at an earlier stage should not be diagnosed as a threshold problem without evidence.

### Driver image handling

The investigated patch changed image-processing behavior, including the removal of a 2× resize and changes to image flags and smoothing.

The implementation was observed to use a separable smoothing kernel with coefficients:

`{34, 111, 218, 298, 218, 111, 34}`

The investigated path also used the native image scale and set `FPI_IMAGE_COLORS_INVERTED`.

These are implementation observations, not proof that the processing is optimal for this sensor. Their effect on matching reliability must be measured against a reproducible baseline.

### Verified SIGFM Matching Implementation

The following details are derived from the inspected SIGFM implementation in `libfprint/sigfm/sigfm.cpp`, `libfprint/sigfm/img-info.hpp`, `libfprint/fp-image.c`, and the libfprint print-matching path. Recheck these details if the source revision changes.

#### Feature extraction

* Input is copied into an OpenCV single-channel, 8-bit image (`CV_8UC1`).
* `cv::SIFT::create()->detectAndCompute()` extracts SIFT keypoints and descriptors.
* `SigfmImgInfo` stores the keypoints and descriptor matrix.
* libfprint rejects extraction when fewer than 25 keypoints are found, returning `No enough keypoints found`.

#### Descriptor matching

* `cv::BFMatcher` performs a k-nearest-neighbour search with `k = 2`.
* The first candidate is retained when its descriptor distance is less than `0.75` times the second candidate's distance.
* The implementation returns a score of `0` if fewer than five descriptor matches are accepted.

#### Geometric consistency and score

* Accepted feature correspondences are compared pairwise.
* A pair is considered geometrically compatible when the relative difference between the two inter-feature distances is at most `0.05`.
* Compatible pairs are represented using sine and cosine components derived from their relative geometry.
* The implementation counts pairs of angle records whose sine and cosine components satisfy the configured `0.05` relative-difference checks.
* This count is returned as the SIGFM match score.
* Exceptions return `-1`; the caller treats a negative score as a matching error.

#### libfprint decision path

* The ELAN driver selects `FPI_DEVICE_ALGO_SIGFM` and configures the threshold as `100`.
* libfprint dispatches matching to `fpi_print_sigfm_match()` when SIGFM is selected.
* The matcher returns success when `score >= threshold`.
* The value `100` is an implementation threshold, not a probability, percentage, or independently validated security guarantee.

#### Code-review item: `match::operator<`

The inspected implementation of `match::operator<` repeats the comparison `this->p1.y < right.p1.y` in both parts of its expression:

```cpp
return (this->p1.y < right.p1.y) ||
       ((this->p1.y < right.p1.y) && this->p1.x < right.p1.x);
```

As written, the second clause cannot distinguish points with equal `y` coordinates because it repeats the same strict comparison. The comparator therefore does not implement the apparent intended ordering by `y`, then `x`. Since `match` objects are stored in `std::set<match>`, distinct correspondences can be treated as equivalent by the set's ordering and omitted from the resulting vector.

This is a confirmed source-level logic defect in the inspected revision. Its effect on real fingerprint scores and verification outcomes has not yet been measured. Before changing it, add a minimal test for equal and unequal coordinates, define the intended ordering of correspondence pairs, and compare score distributions before and after the fix using repeatable test samples.

#### Limits of current evidence

* The code establishes the implemented algorithm and threshold semantics; it does not establish the best threshold for this sensor.
* The patch author's score-range comments are not a substitute for independently collected genuine-user and impostor measurements.
* Current interactive tests are preliminary operational observations, not a controlled false-rejection or false-acceptance evaluation.
* Threshold selection and algorithm changes should be evaluated using repeatable samples and separate development and held-out test data.

## 8. Enrollment, Verification, and Template Data

Enrollment captures samples and stores fingerprint data in the format supported by the active libfprint implementation.

Verification compares a newly captured image against the stored enrollment data. Successful enrollment does not guarantee that future captures will produce a sufficient number of features or a score above the matching threshold.

Observed enrolled fingers during the investigation included the right middle finger and right index finger.

The following command can be used to inspect the current user's enrollment list:

```bash
fprintd-list "$USER"
```

Enrollment and verification results depend on multiple factors, including:

* Finger placement and movement.
* Contact area and pressure.
* Image quality and contrast.
* Sensor temperature and operational state.
* Feature extraction success.
* Descriptor-match count.
* Geometric consistency.
* The configured threshold.

Do not store or publish fingerprint images or biometric templates casually. They are sensitive biometric data.

## 9. Observed Test Results and Reliability

### Interactive verification test

A preliminary test recorded 60 valid verification attempts:

* 39 reported a match.
* 21 reported no match.
* Observed match fraction: 65%.

This is a small interactive test, not a controlled biometric evaluation. It does not establish a false-acceptance rate, false-rejection rate, or equal-error rate.

The result may reflect capture variability, image processing, feature extraction, matching behavior, the comparator issue described above, or a combination of factors. The current evidence does not isolate the cause.

### Overheating-related shutdown

During extended testing, attempt 61 and subsequent attempts produced `verify-disconnected`. The system journal reported that the device was disabled to prevent overheating. The device later recovered after a waiting period without a reboot.

This is an observed operational safety event. No independently measured sensor temperature was recorded, so it should not be described as a confirmed temperature reading or as proof of a specific thermal defect.

Do not disable the device's overheating protection merely to increase the number of test attempts. Use bounded test sessions, allow cooling when the device shuts down, and collect relevant logs.

### Interpreting scores

The matching threshold is configured as `100` in the inspected ELAN driver path. A score above that value means only that the implementation accepted the match under its configured rule.

It does not mean a 100% match, 100% confidence, or a quantified security level.

Any threshold adjustment should be based on representative genuine-user and impostor data, with a separate held-out test set.

## 10. Security and Operational Boundaries

Fingerprint authentication is one authentication mechanism, not a replacement for all account-recovery methods.

Recommended precautions:

* Keep password-based recovery available.
* Do not disable PAM modules or password authentication without a tested recovery route.
* Do not weaken matching thresholds solely to make enrollment or verification appear more reliable.
* Do not disable thermal protection to force continuous operation.
* Avoid logging or sharing raw biometric images and templates.
* Record the exact source revision, patch hash, build configuration, and active library path when reporting results.
* Keep experimental algorithm changes isolated from the known-working build.

A successful test on one laptop should not be interpreted as proof of compatibility or security across all devices using the same broad model family.

## 11. Open Questions and Research Priorities

The following work should be completed in small, independently verifiable steps.

1. **Reproduce the baseline.** Record the exact source revision, patch hash, build configuration, runtime library path, and test procedure.
2. **Investigate capture stability.** Collect bounded-session logs and distinguish acquisition errors from matching failures.
3. **Review the comparator.** Confirm the intended ordering of `match` values and write a minimal test covering equal and unequal coordinates.
4. **Measure the comparator's impact.** Compare retained correspondence counts and scores before and after a narrowly scoped fix using repeatable samples.
5. **Inspect coordinate conversion.** Determine whether converting SIFT keypoint coordinates to integer points discards information that matters to geometric matching.
6. **Establish a controlled dataset.** Separate development samples from held-out genuine-user and impostor samples.
7. **Evaluate preprocessing.** Test image scale, smoothing, inversion, and orientation one variable at a time.
8. **Evaluate thresholds.** Record genuine and impostor score distributions before recommending a threshold.
9. **Document device safety behavior.** Record shutdown and recovery conditions without bypassing protective behavior.
10. **Verify the final documentation.** Check all paths and claims against the exact source revision and current device output.

Do not combine multiple algorithm changes into one experiment. Otherwise, it becomes difficult to attribute an improvement or regression to a particular change.

## 12. Evidence and Confidence Convention

When adding findings to this document, include enough context for another contributor to reproduce them.

For source-code claims, record:

* Repository and source revision.
* File and function name.
* Relevant code path.
* Whether the claim describes implementation behavior or measured behavior.

For experimental claims, record:

* Device and operating-system details.
* Test procedure and number of attempts.
* Valid, failed, and interrupted attempts.
* Relevant logs and error messages.
* Whether the data were collected from genuine-user or impostor comparisons.
* Known limitations and potential confounders.

Avoid presenting hypotheses as confirmed causes. If a finding has not been reproduced, label it as preliminary or unresolved.

## 13. Intended Use by Future Contributors

This document is intended to help contributors understand the integration before making changes to the driver or matching algorithm.

The preferred workflow is:

1. Observe the current behavior.
2. Identify the responsible layer and code path.
3. Verify the hypothesis against source or diagnostic output.
4. Make one minimal change.
5. Test correctness and recovery behavior.
6. Benchmark against the same baseline.
7. Keep the change only if the result is reproducible and useful.

The primary objective is reliable, maintainable support—not maximizing a single interactive success count at the expense of correctness, security, or hardware safety.
