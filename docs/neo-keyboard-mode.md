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

## Follow-up: test build crash reported

On 11 November 2026, the user reported that the supplied 2.0.5, build 155 quits unexpectedly. The photograph shows the generic macOS crash dialog. It does not include an exception type, termination reason, crashed thread, macOS version, or whether the crash occurs before or after connection. The connection correction is not confirmed.

Keep the exact tested source and matching build 155 crash symbols for diagnosis. Obtain the full report through Show Details and establish whether the Neo was attached when the app quit. Do not infer the failing call from the dialog or issue another speculative USB correction. A changed test app must use a fresh build number; no public release is authorised.

## Crash diagnosis and build 156 milestone

The full report identifies version 2.0.5, build 155, running natively on the M2 Air with macOS 14.7.1 (23H222). The executable and matching dSYM UUIDs agree with the supplied build. The exception is `EXC_CRASH (SIGABRT)` on `com.koralatov.alphasync.usb`. Its exception backtrace reaches `-[IOBufferMutableData bytes]` from `USBModeSwitchConnection.send(_:timeout:)`, then the mode-switch sequence and initial discovery. This locates the failure in USB buffer handling. No private report identifiers or paths are stored in this record.

The adapter allocated a kernel-backed buffer with `ioData(withCapacity:)`, set its length, and used normal Foundation mutation methods. The bulk read and write paths used the same pattern; reads also bridged that specialised buffer to Swift Data. Apple’s [I/O buffer documentation](https://developer.apple.com/documentation/iousbhost/iousbhostobject/iodata(withcapacity:)) states that the kernel-backed buffer’s length and capacity cannot change and that a resize throws an exception. Swift error handling does not turn that Objective-C exception into a normal transfer error.

Prepare a distinct unpublished build 156. Use ordinary Foundation NSMutableData, which both documented [control requests](https://developer.apple.com/documentation/iousbhost/iousbhostobject/senddevicerequest:data:bytestransferred:completiontimeout:error:) and [bulk requests](https://developer.apple.com/documentation/iousbhost/iousbhostpipe/sendiorequestwithdata:bytestransferred:completiontimeout:error:) accept. A shared buffer boundary creates owned, bounded buffers and copies only the completed input bytes into independent Swift Data. All three native request paths use this boundary. They no longer allocate or resize specialised kernel-backed buffers. The exact legacy mode-switch controls, timeouts, eight-byte bulk framing, retries, and file protection remain required.

Eight new regressions exercise the actual Foundation buffers supplied to the low-level sender, including the immutable byte getter named in the crash, supported Foundation buffer operations, independent ownership, partial reads, zero input, invalid sizes and counts, incomplete output, and preserved transfer errors. This adds coverage below the previous command-list simulation.

This is the compile and full build milestone. Tests were deferred during routine edits. Run both host jobs, all existing checks and the new buffer regressions, both app editions and helpers, native interfaces, Help, signatures, symbols, and native Apple Silicon package verification without publishing. The new candidate still needs a physical connection and file-read test on the reported Air. Keep the original build 155 and its evidence; preserve the public releases, tags, and frozen legacy source.

## Build 156 results and remaining gate

Source `89c26ce25918153341e7f367a7219d5d8baaf5a4` passed both app-build jobs in [run 43020148543](https://github.com/koralatov/alphasync/actions/runs/43020148543). Intel with Xcode 26.6 and Apple Silicon with Xcode 16.4 each passed 123 Swift regressions, including the eight buffer checks, all 55 fixtures, both app and helper builds, and native interface checks, without compiler warnings. The downloaded canonical assets passed local checksum, metadata, and archive validation. Both Help books contain eighteen pages, eighty-three valid links, the original licence, and nonempty indexes, and their twenty authored files match the tested source.

The final native download job received no Mac runner in either of two fifteen-minute queue attempts. It was cancelled before executing a step, so the overall run is not a passed full milestone. Keep the native download gate open and preserve the successful builds. The [permanent record](../releases/verification/2.0.5-156/verification.json) preserves the results and exact asset hashes. Public releases, all twelve tags, and the frozen legacy source remain unchanged. Physical crash resolution on the M2 Air with macOS 14.7.1 is still unverified. The user has requested an email with the completed outcome.
