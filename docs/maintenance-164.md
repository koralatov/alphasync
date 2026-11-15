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

Use public AppKit accessibility announcements for non-modal connection and completion updates.  Combine related connection and error changes over 200 ms, suppress identical state updates, avoid duplicating a modal warning’s announcement, and cancel queued speech on Quit.  Post only when VoiceOver is enabled and AlphaSync is active, with no modal window or attached sheet competing for speech.  Four isolated regressions check feedback through actual AppStore operations without enabling speech or changing system preferences.  Capture both known and unknown progress in both appearances.

## Menu availability

Find commands use a weak association between each loaded Reader’s own native text view and its window.  A small registry observes public key-window notifications and publishes the active target after the current view update.  Shared commands are installed on the complete scene group.  They stay unavailable in other windows, during loading, and after failure.  Direct targeting keeps Find working when another control in the Reader has keyboard focus.  Avoid traversing private framework views in application code.  Retain the native Find bar, shortcuts, and existing read-only text behaviour.

Context menus contain relevant actions.  Hide Rename and Clear for read-only data, hide unavailable transfer actions while busy, and keep the destructive action last.  Preserve the existing connection identities, target capture, consent, and backend checks.

The real SwiftUI scene checker exercises all four Find commands’ availability in the browser, a loaded Reader, and the browser after closing that Reader.  Activate the actual native menu command with an unrelated field focused and require the Reader’s native Find bar.  Repeat in both appearances and preserve the six observations per host.  Physical context-menu and keyboard checks remain explicit.

## File-size formatting

Reuse one main-actor byte-count formatter with the existing decimal file units, bytes and KB, and numeric zero.  Reset it on the system’s locale-change notification.  Compare eleven boundary and representative values against build 163’s fresh formatter on each native host, including after locale invalidation.  Record same-host warm diagnostic timings without a speed threshold or USB throughput claim.  Exact byte counts remain unchanged.

The initial candidate used an immutable format style.  Its native comparison caught changed units and rounding at 999 bytes and at larger sizes.  The final implementation reuses the existing formatter API instead, retaining the same comparison and recording this correction as a focused follow-up commit.

## Compile and build milestone

Review the five commits before running tests.  The planned suite is **190 Swift tests**, with the existing **55 fixtures**, both pinned compilers, both app editions and helpers, all **thirty-two browser observations per host**, sidebar widths and sizes, all toolbar modes, and the combined failing 120-second interface deadline.  Native captures increase to **54 per host, 108 overall**, including progress states and Find in both appearances.

Require native execution of both exact canonical packages on Apple Silicon, architectures, minimum deployment, signatures, hardened runtime, helpers, matching symbols, four independent artifact digests, twelve asset hashes, and both Help books against tested source.  Review captured images and preserve permanent results under `releases/verification/2.0.5-164`.  Provide a separate Apple Silicon test ZIP after verification.  Preserve earlier private copies, public 1.5.1 and 2.0.4 notes and assets, all twelve version tags, and frozen legacy source.

The next compiles caught an isolation and sendability omission in the diagnostic baseline callback.  Its explicitly typed main-actor Sendable closure changes the checker only.  The native Find runs found unavailable commands in a key Reader window.  Applying commands to the complete scene group did not resolve the missing SwiftUI scene value.  The final implementation uses public AppKit window notifications and explicit weak text-view associations instead, preserving all native Find assertions.  Keep this failed candidate distinct from the final verified source.

## Physical checks before 2.1

Continue the [manual checklist](../tests/manual-checks.md) on the M2 Air when available.  Check Quit during creation, renaming, and refresh; safe completion after writing starts; stopped initial backups; VoiceOver labels, state updates, and duplicate speech; Find with the font control or another control focused; context menus for read-only and writable data; and file-size labels under the actual regional settings.  Keep earlier transfers, recovery, help, helper approval, oldest-runtime, and full screen-composited appearance checks open until results are recorded.

## Apple references

- [VoiceOver](https://developer.apple.com/design/human-interface-guidelines/voiceover)
- [Accessibility announcements](https://developer.apple.com/documentation/appkit/nsaccessibility-swift.struct/notification/announcementrequested)
- [Menus](https://developer.apple.com/design/human-interface-guidelines/menus)
- [Context menus](https://developer.apple.com/design/human-interface-guidelines/context-menus)
- [Byte-count format style](https://developer.apple.com/documentation/foundation/bytecountformatstyle)

## Verified private candidate

Final source `f79cf1d532375e4c38b72486e9488fb2aa3868cf` passed [run 43772376923](https://github.com/koralatov/alphasync/actions/runs/43772376923) on 15 November 2026.  Both pinned compilers passed all 190 Swift regressions, 55 fixtures, native component and scene checks, exact formatting comparisons, and both app and helper builds without Swift compiler warnings.  Each host retained thirty-two browser observations, twelve sidebar records, six toolbar records, six Find observations, and 54 captures.  The native Find menu command opened the loaded Reader’s Find bar with an unrelated field focused in both appearances.

Both exact canonical packages ran on Apple Silicon.  Independent checks matched four artifact digests, twelve asset hashes, both Help books, and their tested source.  All 108 captures were reviewed.  Layer captures do not establish final system-composited appearance: the Intel dark captures include opaque white toolbar material masks.  That appearance remains a physical check.  The unbundled About fixture also uses its documented fallback icon; package metadata and artwork were checked separately.

The final checker calls the native menu’s public delegate before validating lazy menu content, matching AppKit’s preparation before display.  It independently requires the correct active Reader target and retains every command-availability and Find-bar assertion.  Only the checker changed in the final source.  The [permanent record](../releases/verification/2.0.5-164/verification.json) preserves earlier failed candidates and all verification limits.

The private Apple Silicon test ZIP is saved separately.  Public releases, their notes and assets, all twelve version tags, and the frozen legacy branch are unchanged.  Publication was skipped.  Continue the physical checks above before deciding on stable 2.1.
