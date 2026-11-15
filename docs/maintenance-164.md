# Maintenance in build 164

Prepare private **2.0.5, build 164** with the five authorised maintenance changes in separate focused commits.  The user will test the resulting copy before deciding whether to prepare and publish stable 2.1.  This milestone does not authorise publication or retirement of a release.

## Cancellation before a file change

Creation and renaming now accept the same cancellation callback used by replacement.  Check it between preparation requests, before the final handshake, and again after that handshake immediately before the first file-changing request.  Replacement and clearing also check after the handshake.  Keep the successful legacy command sequence, packet layouts, checksums, timeouts, and readback verification.  Once writing begins, finish and verify the committed change, including all selected files in a multi-file clear.

Five independent wire regressions check cancellation in the final handshake and successful completion after writing starts.  Two Quit lifetime checks cover creation and renaming through AppStore.  Cancellation before a file changes must not be classified as a possible write failure; failures after a change must keep that warning.

## Cancellation during inventory

Propagate task cancellation and Quit’s stop request through connection scans, explicit refresh, applet headers, and file metadata.  Check between completed requests without interrupting a bounded USB call.  A cancelled refresh preserves a healthy cached connection, and a cancelled opening closes its unpublished handle.  Do not record cancellation as a connection failure or publish an incomplete inventory.

Use cancellable inventories for read-only preparation and the initial backup scan.  Stopping that initial scan returns a stopped backup with no folders, rather than a false completion or partial file list.  Post-write snapshot verification remains uncancellable.  Three wire checks, three service checks, and one Quit check cover these cases.

## Accessibility feedback

Give transfer indicators task-specific accessible labels.  Hide the decorative duplicate spinner from VoiceOver when a determinate indicator is available.  Retain native percentage values.  Show transfer progress only for active work, while a waiting confirmation still keeps conflicting controls unavailable.

Use public AppKit accessibility announcements for non-modal connection and completion updates.  Combine related connection and error changes over 200 ms, suppress identical state updates, avoid duplicating a modal warning’s announcement, and cancel queued speech on Quit.  Post only when VoiceOver is enabled and AlphaSync is active.  Four isolated regressions check feedback through actual AppStore operations without enabling speech or changing system preferences.  Capture both known and unknown progress in both appearances.

## Menu availability

Find commands use the active, loaded Reader’s focused scene context and weak text-view target.  They stay unavailable in other windows, during loading, and after failure.  Direct targeting keeps Find working when another control in the Reader has keyboard focus.  Avoid traversing private framework views in application code.  Retain the native Find bar, shortcuts, and existing read-only text behaviour.

Context menus contain relevant actions.  Hide Rename and Clear for read-only data, hide unavailable transfer actions while busy, and keep the destructive action last.  Preserve the existing connection identities, target capture, consent, and backend checks.

The real SwiftUI scene checker exercises all four Find commands’ availability in the browser, a loaded Reader, and the browser after closing that Reader.  Activate the actual native menu command with an unrelated field focused and require the Reader’s native Find bar.  Repeat in both appearances and preserve the six observations per host.  Physical context-menu and keyboard checks remain explicit.

## File-size formatting

Use one immutable byte-count format style with the autoupdating locale, decimal file units, bytes and KB, numeric zero, and no extra actual-byte-count suffix.  Compare eleven boundary and representative values against build 163’s fresh formatter on each native host.  Record same-host warm diagnostic timings without a speed threshold or USB throughput claim.  Exact byte counts remain unchanged.

## Compile and build milestone

Review the five commits before running tests.  The planned suite is **190 Swift tests**, with the existing **55 fixtures**, both pinned compilers, both app editions and helpers, all **thirty-two browser observations per host**, sidebar widths and sizes, all toolbar modes, and the combined failing 120-second interface deadline.  Native captures increase to **54 per host, 108 overall**, including progress states and Find in both appearances.

Require native execution of both exact canonical packages on Apple Silicon, architectures, minimum deployment, signatures, hardened runtime, helpers, matching symbols, four independent artifact digests, twelve asset hashes, and both Help books against tested source.  Review captured images and preserve permanent results under `releases/verification/2.0.5-164`.  Provide a separate Apple Silicon test ZIP after verification.  Preserve earlier private copies, public 1.5.1 and 2.0.4 notes and assets, all twelve version tags, and frozen legacy source.

## Physical checks before 2.1

Continue the [manual checklist](../tests/manual-checks.md) on the M2 Air when available.  Check Quit during creation, renaming, and refresh; safe completion after writing starts; stopped initial backups; VoiceOver labels, state updates, and duplicate speech; Find with the font control or another control focused; context menus for read-only and writable data; and file-size labels under the actual regional settings.  Keep earlier transfers, recovery, help, helper approval, oldest-runtime, and full screen-composited appearance checks open until results are recorded.

## Apple references

- [VoiceOver](https://developer.apple.com/design/human-interface-guidelines/voiceover)
- [Accessibility announcements](https://developer.apple.com/documentation/appkit/nsaccessibility-swift.struct/notification/announcementrequested)
- [Menus](https://developer.apple.com/design/human-interface-guidelines/menus)
- [Context menus](https://developer.apple.com/design/human-interface-guidelines/context-menus)
- [Byte-count format style](https://developer.apple.com/documentation/foundation/bytecountformatstyle)
