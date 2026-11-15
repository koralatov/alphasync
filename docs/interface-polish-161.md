# Interface polish in build 161

Private **2.0.5, build 161** is verified and ready for testing after the user reported that build 160 appears to work.  Apply the wording, icons, sidebar scale, connection colour, and toolbar choices agreed in the discussion.  This is a test build towards stable 2.1 for Apple Silicon.  Publication and retirement remain disabled.

## Changes

| Area | Change |
| --- | --- |
| Clear warning | Name the file and Neo, explain that clearing leaves the file empty, and use ‘Save a copy of the text first’ |
| Clear and Replace buttons | Put Cancel first and the destructive action last, with neither as the default; retain initial focus on Cancel and an explicit Escape shortcut |
| Other scopes | Name selected files or all files in the chosen applet; adapt singular and plural wording; give Replace the same plain phrasing |
| Applet icons | Share `square.and.pencil` for AlphaWord, `text.book.closed` for dictionary data, `gearshape` for System, and `app` for unknown applets |
| File and device icons | Keep `doc.text` for a file and use `externaldrive.connected.to.line.below` for the Neo in the sidebar and Inspector |
| Sidebar heading | Use the same native row metrics as child items, with a heavier weight and a heading accessibility trait |
| Connection status | Colour only the light system green; retain Connected text and an accessible state label |
| Toolbar | Use four individual native items named Back Up, Clear Files, Inspector, and Refresh; default to Icon and Text |
| Saved appearance | Offer Icon and Text, Icon Only, and Text Only in View → Toolbar Appearance; remember both menu and native display-mode changes |
| Help | Update current labels, toolbar instructions, and Clear and Replace keyboard guidance; retain the separate dictionary-import warning behaviour |

The toolbar bridge uses public `NSView.window`, `NSToolbar.displayMode`, and key-value observation.  It neither replaces the toolbar nor changes window frames, delegates, or private subviews.  Apply after SwiftUI has attached the view, check for a replacement toolbar on updates, and ignore callbacks from a detached toolbar.  The public macOS 15 display-mode customisation property is availability-guarded; the View menu works from macOS 13.  This avoids requiring newer SwiftUI toolbar APIs that are absent from the compatibility compiler.

The Neo heading remains grouped with its items.  A normal, untagged Label row inherits native sidebar font and symbol metrics, including the system’s Sidebar Icon Size choice.  It is not a new selection destination.  Keep the NavigationSplitView at the root and the zero-minimum flexible frames that corrected build 159’s table sizing.

The native sidebar table includes a zero-height structural row for a Section without a separate header.  Geometry checks skip only that first structural row, then require the Neo heading and All Files row to have positive height and remain inside the visible viewport.  They do not skip clipped or zero-height content rows.

Only wording changes in FileOperations.  Preserve the existing mode switch, USB buffers, serial executor, packet handling, limits, operation consent, backup cancellation, recovery-before-write rule, and readback verification.  Keep all prior private builds and evidence, public release notes and assets, all twelve version tags, and frozen legacy source.

## Full compile and build milestone

Review the code and diffs before execution.  Two preference regressions extend the Swift suite from 170 to **172**, covering all saved display choices and invalid stored values.  Native checks must verify symbol availability, matching sidebar row sizes, native toolbar labels, all commands visible at minimum width in every mode, display changes, saved native choices, and actual window reconnection.  Capture the file Inspector in Light, and the Neo, AlphaWord, dictionary, and unknown-app Inspectors in both appearances.  Complete file Inspector checks in Dark remain in the manual checklist.

Clear and Replace checks must confirm absence of a default button, safe Return, keypad Enter, and initial Space, and working Escape cancellation.  Review captured button order and appearance visually.  Confirm deliberate activation with disposable files during physical testing.  SwiftUI draws these controls without NSButton subviews, and its virtual accessibility elements do not expose the complete AppKit accessibility protocol to this in-process checker; do not add private inspection or shipping test hooks.  Do not weaken the existing twenty real-window observations, read-only preview checks, isolated preferences, disabled USB discovery, or combined failing 120-second interface deadline.

Require both pinned Mac compilers, all 172 Swift tests, all 55 Help and release fixtures, both app editions and helpers, signatures, architectures, hardened runtime, matching symbols, and native execution of both exact canonical downloads.  Independently check the four artifact digests, twelve asset hashes, both packaged Help books against tested source, and captured images.  Retain the macOS 26 compositor limitation if it still applies.  The existing file-list timing remains diagnostic; remove its stale hard-coded build number.

Only after all checks pass, record the tested source and permanent evidence in `releases/verification/2.0.5-161`, provide a separate private Apple Silicon ZIP, and send the requested completion email.  Compare public release listings, notes, asset metadata, all version tags, legacy source, and latest-release state with the fresh baseline.  No public 2.0.5 release or tag is authorised.

## Verified result

Source `1b5495c5b78efcbb09c9a700c0caf18d82047a0b` passed [run 43734374426](https://github.com/koralatov/alphasync/actions/runs/43734374426) on 15 November 2026.  Both pinned hosts passed all **172 Swift tests**, all **55 fixtures**, twenty real-window observations, six toolbar-mode captures, and both app and helper builds.  Both exact canonical editions then ran natively on Apple Silicon.  Swift compiler warnings were absent; both hosts retain build-tool notices about App Intents extraction and stripping signed helpers.

Independent downloads matched all four artifact digests and twelve asset hashes.  Both eighteen-page Help books and all eighty-three links passed validation, and their twenty authored files matched tested source.  Review covered eighty captured images.  Green pixels were present in the status area in both appearances on both hosts.  See the [permanent record](../releases/verification/2.0.5-161/verification.json), [geometry](../releases/verification/2.0.5-161/interface-layouts.json), [toolbar checks](../releases/verification/2.0.5-161/toolbar-checks.json), and [image review](../releases/verification/2.0.5-161/interface-review.json).

The complete sidebar is visible in the macOS 15 captures.  macOS 26 layer capture omits compositor-backed sidebar and some toolbar effects, while live native geometry and item properties pass.  The macOS 15 Text Only dark layer image retains a light toolbar background; screen-composited appearance needs manual review.  The file Inspector was captured in Light; the generic Dark Inspector fixture used a Neo selection.  The unchanged file-document symbol, full Dark file Inspector behaviour, system sidebar size variants, and VoiceOver remain part of physical review.

Three diagnostic runs corrected checker assumptions about SwiftUI-drawn buttons, virtual accessibility objects, and a zero-height Section marker.  The final run retains the original twenty positive-height and viewport checks, direct keyboard safety assertions, the combined deadline, both compiler gates, and package verification.  The diagnostic sources and outcomes are retained in the permanent record.

The separate Apple Silicon test ZIP is **AlphaSync-2.0.5-161-macOS-13-apple-silicon.zip**, 2,915,530 bytes, SHA-256 `4f65b7eb3424038825e4a0c5ebde5a51b63543cbad771c765e17bddfca03e08b`.  Earlier candidates remain preserved.  Only 1.5.1 and 2.0.4 are public.  Their notes and eighteen assets, all twelve version tags, frozen legacy source, and latest-release state match the fresh baseline.  No release or tag was created.

## Physical checks

Use the [manual checklist](../tests/manual-checks.md).  Check the new warning copy and controls with disposable files, toolbar persistence after restart, system sidebar sizes, Light and Dark appearance, contrast, accent colours, VoiceOver, and the connection light on the affected M2 Air.  Repeat physical connection, resizing, first-row access, reading, saving, backup, recovery, replacement, and verification.  The user’s working report does not establish every transfer or destructive operation.  macOS 13 runtime, actual Login Items approval, native Help Viewer, and VoiceOver still require manual results.

## Apple references

- [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)
- [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)
- [Icons](https://developer.apple.com/design/human-interface-guidelines/icons)
- [Sidebar row size](https://developer.apple.com/documentation/swiftui/environmentvalues/sidebarrowsize)
- [Native toolbar display mode](https://developer.apple.com/documentation/appkit/nstoolbar/displaymode-swift.property)
