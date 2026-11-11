# Neo remains in keyboard mode

## Hardware report

On 11 November 2026, Mike reported that AlphaSync 2.0.4 leaves his Neo displaying ‘Attached to MAC, emulating keyboard’ on an M2 MacBook Air. Version 1.5.1 works on that Mac. The photograph establishes keyboard mode; it does not show the Mac app’s message, macOS version, or USB error code.

This is a real hardware failure of the Swift rewrite. The earlier successful builds and simulated transfers did not establish that the keyboard-to-transfer handoff worked on a physical Neo.

## Difference from the working driver

The [1.5.1 driver](https://github.com/koralatov/alphasync/blob/v1.5.1/AlphaSync/Driver/ASDeviceFactory.cc) discovers the USB device, opens it, reads configuration descriptor zero, selects that descriptor’s configuration value, and sends five control requests on endpoint zero. It does not depend on a HID child service being exposed to applications.

The Swift rewrite instead listed IOHID devices, looked for interface 1, and sent IOHID output reports. It omitted the configuration selection. If no matching HID child appeared, it attempted nothing and reported no failure. This is a concrete difference in the failing path; physical testing is still required to establish whether the correction resolves Mike’s setup.

## Correction prepared for 2.0.5, build 155

Discover `IOUSBHostDevice` entries with the exact Neo vendor and keyboard-mode product IDs, `081e:bd04`. Open the device with the public IOUSBHost API and empty options. Read configuration descriptor zero and select its actual value, including when that value is already selected. Then send the same requests as 1.5.1:

| Field | Value |
| --- | --- |
| Request type | `0x21`: host-to-device, class, interface |
| Request | `9`: HID SET_REPORT |
| Value | `0x0200`: output report, ID zero |
| Interface index | `1` |
| Data length | One byte |
| Ordered data bytes | `e0`, `e1`, `e2`, `e3`, `e4` |

Each control request has a five-second timeout. A failed or incomplete request stops that sequence. The connection is closed on success and every failure path. Existing per-device state prevents repeated automatic attempts after failure and allows explicit retry or reconnection. Discovery failures and the underlying macOS error domain and code are shown in the app.

Observe both USB devices and interfaces so discovery starts when the device appears and runs again when its transfer interface is ready. The login helper still reads registry metadata only. No HID input, driver capture, security bypass, or DriverKit extension is added. Bulk file transfers and their file-protection checks are unchanged.

Apple documents device-level configuration and default-endpoint control requests in [IOUSBHostDevice](https://developer.apple.com/documentation/iousbhost/iousbhostdevice), [configuration selection](https://developer.apple.com/documentation/iousbhost/iousbhostdevice/configurewithvalue:matchinterfaces:error:), and [control requests](https://developer.apple.com/documentation/iousbhost/iousbhostobject/senddevicerequest:data:bytestransferred:completiontimeout:error:).

## Compile and build milestone

Routine edits defer automated tests to this milestone. Run the full non-publishing Build and test workflow for the exact correction source. Require both Intel and Apple Silicon builds, all existing regressions and fixtures, six new mode-switch protocol regressions, native interface checks, generated Help indexes, and native verification of both packaged apps on Apple Silicon. Record compiler corrections and the final tested source.

The new regressions check the external legacy sequence, non-default configuration values, invalid configurations, descriptor and configuration failures, failure at every report, short or invalid transfer counts, finite timeouts, and connection cleanup. They do not claim that a physical Neo changed mode.

The first native compile, run `43005148138` for source `9b9dd5942ce50a1033bf389f6a82087461974cb4`, found the control-request selector’s modern Swift name. Replace the obsolete imported `__sendDeviceRequest` spelling with `__send` and repeat the full milestone. This was a compiler correction, not a successful hardware test.

Before publication, test the new build on the reported M2 Air with only one AlphaSync edition running. Record the macOS version and the app’s exact message. Confirm that the Neo leaves keyboard mode, files appear, reading and Save to Mac work, and unplugging and reconnecting work. Test writes, read-back verification, and recovery only with disposable Neo files. Also test Intel, a Neo already in transfer mode, multiple Neos, denial of accessory access, and another app holding the device.

Version 2.0.5 remains unpublished. Keep the 1.5.1 and 2.0.4 public releases and every source tag unchanged until a separate release request.

## Hosted build result

On 11 November 2026, [build run 43005406688](https://github.com/koralatov/alphasync/actions/runs/43005406688) passed for exact source `56e1db9936a115bf09494d3e0d51bd2d504ecc8f`. Intel with Xcode 26.6 and Apple Silicon with Xcode 16.4 each passed 115 Swift regressions, including the six new mode-switch checks, all 55 validation fixtures, both app and helper builds, and native interface checks. The canonical packages passed native Apple Silicon verification, including both app-version commands, signatures, architectures, hardened runtime, matching symbols, and Help. The independently downloaded twelve asset hashes matched the native verification manifest; both eighteen-page Help books and eighty-three links matched the tested source and preserved the original licence and index. Publication was skipped. Physical mode switching on Mike’s Neo remains unverified.

The [permanent candidate record](../releases/verification/2.0.5-155/verification.json) retains the source, results, hashes, original compiler correction, and limits. The test build is a candidate for physical verification, not a published release.
