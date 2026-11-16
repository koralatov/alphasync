# Refinements in build 165

Prepare private **2.0.5, build 165** while the user is unable to carry out the physical checklist.  The user authorises further useful accessibility, reliability, data-integrity, usability, and HIG refinements.  Keep the four changes in focused commits.  Preserve build 164 and all earlier private copies.  This work does not authorise publication, release retirement, or changes to frozen legacy references.

## Confirm the same file details

A confirmation already rechecks the original bytes.  It must also reject a changed name, allocation, binding, password, or other detail represented by the selected file snapshot.  Compare every named file with the fresh inventory before saving recovery copies or starting the first write.  A renamed file with unchanged text needs a fresh review.  A metadata change in the last file of a multi-file clear must prevent changes to the first file too.

Replacement preparation compares its fresh attributes with the chosen snapshot, avoiding a warning that names stale details.  Renaming rejects an absent file or read-only applet before calling the device operation.  Four service regressions cover renamed replacement targets, later targets in a clear, read-only renaming, and absent rename targets.  Existing successful change, cancellation, recovery, and readback tests remain required.

All USB setup, protocol commands, packet fields, timeouts, successful wire sequences, file conversion, atomic export, recovery retention, and committed-write behaviour remain unchanged.  These checks reuse existing inventories and attribute requests.  The dictionary source changes only its report wording; its conversion and byte-payload implementation match build 164 exactly.

## Reader Find lifetime

Use SwiftUI’s public `dismantleNSView` hook and the native view’s window lifecycle to detach the removed text view.  Detach only when that exact view is still attached to the context.  Late removal of an older view cannot clear its replacement.

Extend the real-window check without removing its existing assertions.  In both appearances, check browser, loaded Reader, unloaded Reader, reloaded Reader, late old-view cleanup, and closed Reader states.  Require the native Find bar to open through the actual menu command with another field focused before and after reloading.  Keep twelve observations and four Find captures per host.

## Safe, clear forms

Dictionary omission consent puts Cancel before Continue, gives Cancel initial focus and Escape, and gives neither button a default action.  Return, keypad Enter, and Space must never provide consent.  The omission explanation is selectable.  Keep the subsequent Replace confirmation and exact source-text consent checks.

Initial source `985b12350f50cf9791c25c627f2a214eeda3c21b` passed every Intel check in [run 43842283473](https://github.com/koralatov/alphasync/actions/runs/43842283473), including 194 tests, 55 fixtures, native interfaces, and both editions.  Its 60-image visual review caught the existing plural wording when exactly one valid dictionary word remains.  Correct that report copy and run the final source through both hosts and all download gates.  The Apple Silicon job had not started; this initial source is not a fully verified private test build.

Rename uses the existing core validation rules and gives visible guidance and a matching accessibility hint.  Empty or invalid names and an unchanged name cannot enable Rename.  Escape cancels; valid renames retain their standard default action.  Capture the initial guidance in both appearances.  Physical typing, editing, focus, and actual VoiceOver speech remain manual.

## More informative native controls

Expose exact byte amounts for file sizes and available memory while retaining compact visual formatting.  Give the backup folder chooser and Stop backup action explicit accessibility labels.  Count multiple connected Neos accurately in the status label.  Tooltips expose full operation names when the visible progress text is truncated.  Keep the existing native controls, selection semantics, sidebar, and file-only Inspector Preview.

## Completion milestone

After reviewing the focused commits, compile and run the full non-publishing build milestone.  The expected Swift suite is **194 tests**, with the existing **55 fixtures**, both pinned Mac compilers, both app editions and helpers, and no Swift compiler warnings.  Keep all thirty-two browser observations, twelve sidebar records, and six toolbar records per host.  Extend native confirmation checks to dictionary consent and record six safe keyboard results per host.  Require twelve Find observations per host and native Find after a Reader reload.

Keep the combined failing 120-second interface deadline.  Capture fifteen component views and fifteen window-scene views per appearance on each host, **120 images overall**, and inspect the results.  Retain the exact file-size comparison and its diagnostic-only timings.  Verify native execution of both exact canonical packages on Apple Silicon, architectures, minimum deployment, signatures, hardened runtime, helpers, matching symbols, four artifact digests, twelve asset hashes, and both Help books against tested source.

Record final evidence under `releases/verification/2.0.5-165` and save a separate private Apple Silicon test ZIP.  Preserve public 1.5.1 and 2.0.4, their notes and assets, all twelve version tags, and frozen source.  The final system-composited appearance, actual VoiceOver, physical Neo operations, Login Items approval, native Help Viewer, and macOS 13 remain explicit manual checks before deciding on stable 2.1.

## Verified result

Final source `51f7cd2282b4415b58beaa7cbe3e2d0f5e16f570` passed [run 43844201560](https://github.com/koralatov/alphasync/actions/runs/43844201560) on 16 November 2026.  Both pinned hosts passed all 194 Swift regressions, 55 fixtures, native component and window checks, exact size formatting, and both app and helper builds without Swift compiler warnings.  Each host recorded thirty-two browser observations, twelve sidebar records, six toolbar records, twelve Find observations, six confirmation records, and sixty captures.  All 120 final-source captures were reviewed.

The first native download job was cancelled after waiting for a runner and executed no steps.  Only that job was retried; the successful builds and reviewed captures were retained.  The retry passed native execution of both exact canonical apps on Apple Silicon.  All four artifact digests, twelve asset hashes, matching symbols, both Help books, and packaged metadata passed independent checks.  The [permanent record](../releases/verification/2.0.5-165/verification.json) distinguishes the initial candidate, the unstarted native attempt, and the final successful result.

The separate private Apple Silicon test ZIP is saved and ready.  Public 1.5.1 and 2.0.4, their eighteen assets and notes, all twelve version tags, and frozen legacy source remain unchanged.  No release was published or retired.  Physical Neo testing comes next before the decision on stable 2.1; the manual and capture limits above remain open.

The subsequent [simplification review](simplification-review-165.md) covers all forty-nine modern production Swift files.  It proposes a clearer Clear eligibility predicate, identifies a conditional Find API cleanup, and keeps snapshot publication explicit because its preview-invalidation rules differ.  The review makes no production change to this tested build and records the safety boundaries that a future cleanup must retain.

## Apple references

- [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)
- [Accessibility modifiers](https://developer.apple.com/documentation/swiftui/view-accessibility)
- [Cleaning up an AppKit view](https://developer.apple.com/documentation/swiftui/nsviewrepresentable/dismantlensview(_:coordinator:))
