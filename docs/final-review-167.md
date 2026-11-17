# Final review before physical testing

Private **2.0.5, build 167** is being prepared following the user’s request for worthwhile improvements before tonight’s testing.  Build 166 remains verified, saved, and separately available.  No public release or retirement is authorised.

## Focused corrections

Validate create and rename names at the service boundary using `NeoFileAttributes`, before any engine write.  Keep the protocol’s own validation unchanged.  Regressions exercise empty rename names, overlong names, control characters, and unsupported Unicode against an engine that otherwise accepts them.  Require no writes, unchanged device bytes and metadata, preserved import sources, and accurate operation-failure facts.

Share the small file-panel cancellation predicate across import, export, and backup-folder selection.  It checks both `NSCocoaErrorDomain` and `NSUserCancelledError`.  Other domains with the same numeric code must remain visible.  Preserve captured request lifetimes and discard a finished panel’s request on either outcome.

Use the optional `AS_RELEASE_NOTES_REF` to link private builds to source release notes before their public tag exists.  Keep the exact public-tag fallback, including reissue tags.  The current private override is `master`; publication rejects a nonempty override before any API call.  An authorised public release must clear it and repeat verification.  No tag is created by this maintenance work.

Use singular wording for one backed-up file, selectable summaries, and semantic headings in About and native dialogs.  Add complete, stopped, and empty native backup results in both appearances.  Return must invoke Done, while folder-opening controls remain explicit actions.

## Review boundary

The pass found no reason to alter the successful low-level USB sequence, packet validation, codecs, serial executor, atomic-file handling, recovery protection, original-byte comparison, committed-write completion, native browser geometry, or Reader and Find ownership.  Keep those implementations unchanged.  Do not add speculative abstractions, retries, caches, dependencies, or new features before tonight’s testing.

## Full non-publishing milestone

Require **212 Swift regressions** and **56 fixtures** on Intel with Xcode 26.6 and macOS 26 and Apple Silicon with Xcode 16.4 and macOS 15.  Build both app editions and helpers without Swift compiler warnings.  Keep thirty-two browser observations, twelve sidebar records, six toolbar records, twelve Find observations, and eight safe confirmation records per host.  Add six backup result records and two explicit toolbar replacement records per host.

Retain the strict combined 120-second native interface deadline.  Capture nineteen component views and fifteen window scenes per appearance per host, **136 images in total**, and review the actual final-source captures.  Keep the Intel dark toolbar layer-mask and unbundled About fallback limits explicit.

Require native execution of both exact canonical downloads on Apple Silicon; independent checks of four artifact digests and twelve asset hashes; architectures, minimum macOS 13, signatures, hardened runtime, helpers, matching symbols, and both Help books.  Confirm the packaged private notes reference.  Compare protected public releases and notes, eighteen assets, twelve tags, frozen legacy source, and latest 2.0.4 with the preserved build 165 and before-work baselines.

Permanent evidence belongs in `releases/verification/2.0.5-167`.  All final-source build, review, saving, and notification gates remain pending at this milestone.  Save a separate canonical Apple Silicon ZIP only when those verification gates pass, commit final documentation, then send the authorised one-off CalxGPT email with its actual link.  Keep the existing completed automation paused.

## Tonight’s decision

Follow the [physical checklist](../tests/manual-checks.md).  Hosted checks cannot establish physical Neo operations, actual VoiceOver speech, keyboard focus and editing, regional settings, final composited appearance, macOS 13 runtime, Help Viewer, or Login Items approval.  Physical Neo testing comes next before deciding on stable 2.1.  Further changes should respond to those results.

## Apple references

- [Cocoa error evaluation](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/ErrorHandlingCocoa/CreateCustomizeNSError/CreateCustomizeNSError.html)
- [SwiftUI accessibility traits](https://developer.apple.com/documentation/swiftui/accessibilitytraits)
- [Text views](https://developer.apple.com/design/human-interface-guidelines/text-views)

## Initial fixture correction

Initial source `d61546c9dfec5c143e96db32483bb5ee7b3b35f4` passed all 212 Swift regressions and 56 fixtures on both hosts in [run 44060811730](https://github.com/koralatov/alphasync/actions/runs/44060811730), but the component checker stopped at a new AppKit default-button-cell assertion.  A SwiftUI keyboard shortcut need not expose a titled `NSWindow.defaultButtonCell`.  The corrected fixture tests the actual Return event and requires the Done callback exactly once, with no automatic dismissal before input.  It retains all three result states and both appearances.  Production source is unchanged by this correction.  The failed source is not packaged, saved, or ready for notification.  Repeat the full milestone on the corrected source.

## Toolbar replacement correction

Corrected fixture source `0dcc8b477d4a9dd2ab6824a92a0c5623c5440ca1` passed the Intel 212 Swift regressions, 56 fixtures, all component checks, and the six actual backup Return checks in [run 44061454502](https://github.com/koralatov/alphasync/actions/runs/44061454502).  The existing real-window gate then found an Intel Dark reconnection mismatch: the native toolbar displayed icons only while the preference and stored choice remained Icon and Text.  Keep that failing assertion unchanged.

A queued content update can precede SwiftUI’s installation of a replacement toolbar.  Observe the window’s public `toolbar` property and apply the saved appearance when it changes, retaining the existing active-toolbar mode observer.  New native checks in both appearances replace a toolbar, verify the saved choice, ignore changes from the former toolbar, save a current native choice, and apply a preference change.  Keep the strict combined 120-second deadline, all prior browser and toolbar gates, and 136 captured images.  Repeat the full milestone before packaging or saving.  This is a real UI reliability correction; USB and transfer safeguards remain unchanged.
