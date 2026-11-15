# Permanent sidebar in build 162

Private **2.0.5, build 162** is verified and ready for testing after the user reported that Hide Sidebar freezes build 161.  The user agreed to remove hiding entirely, indent child items one level, and use `keyboard.fill` for the dark-coloured Neo.  The sidebar width remains adjustable.  This is a test build towards 2.1, with no release publication or retirement.

## Review and implementation

Build 161 uses NavigationSplitView, which supplies the automatic sidebar toolbar button.  Its caption became visible when toolbar labels were enabled.  The existing native tests exercised display modes and resizing, but never activated that button.  The hardware report establishes a regression; the exact blocking stack has not yet been established.

Use a public NSSplitViewController containing two ordinary NSSplitViewItems, rather than sidebar-behaviour items.  Both have `canCollapse = false`.  The navigation pane is 180–300 points wide, initially 220, and the file pane has a 400-point minimum.  The connected window retains its 760-point minimum.  These constraints leave room for both panes.  Ordinary items do not participate in the controller’s `toggleSidebar` action or automatic sidebar collapsing.  No new toolbar button or hide command is added.

Use holding priorities 200 for navigation and 199 for files, following Apple’s primary-detail example.  A high-priority sidebar holding constraint prevented the divider from following requested positions in the initial candidate.  Keep the sidebar’s priority above the file pane’s, while allowing ordinary divider constraints to move it.  Retain the native 180-, 300-, and 220-point assertions; this was a real candidate resizing failure.

The two hosting controllers have empty sizing options because split items own their widths and the outer SwiftUI window owns its limits.  This avoids competing minimum, maximum, and ideal content constraints during a pane transition.  Retain the original flexible zero-minimum frames on the file table and its containers.  Pass system sidebar size, appearance, and contrast through the hosting boundary, and preserve each controller when updating its SwiftUI content.  Set the initial divider once, so ordinary updates retain the user’s width.

Replace the default sidebar command group with the existing toolbar appearance, Inspector, and Refresh commands.  This removes alternate menu routes to hiding.  Keep all four labelled toolbar actions and their saved display modes.  Indent All Files and each applet by fourteen points without changing their font, symbol size, or selection scope.  Share `keyboard.fill` between the sidebar and device Inspector; use system colours in both appearances.

The USB, core, and hardware sources must match build 161 exactly.  Keep all file preflights, consent, recovery, cancellation, and verification behaviour.  Update the current Help, manual checklist, release notes, and technical guide.  Preserve earlier private candidates, both public release listings and downloads, all twelve version tags, and the frozen legacy source.

## Baseline freeze investigation

The separate `sidebar-diagnostic.yml` workflow runs only when its own files change, or on manual request.  It archives exact tested source `1b5495c5b78efcbb09c9a700c0caf18d82047a0b`, changes only the isolated window-check driver, and compiles the original interface on Apple Silicon with Xcode 16.4.  The original MainView hash is recorded.  No frozen branch or tag is checked out or changed.

The probe opens a sample connected window at minimum size and activates the actual Hide Sidebar item through its public target/action, or a click within its public view bounds.  It records a checkpoint before the action and captures the resulting window.  A separate twenty-second deadline saves a process sample and terminates the disposable process if it blocks.  A receipt distinguishes a captured action hang, no hang reproduced, and a failed probe.  A diagnostic hang is evidence about the old build, never a passing result for the new app.  Hosted macOS 15 is not the affected physical M2 Air’s reported macOS 14.7.1, so failure to reproduce cannot establish that the user’s report is resolved.

## Full compile and build milestone

Review edits and diffs first.  Keep all **172 Swift tests** and **55 fixtures**, both pinned compilers, both app editions and helpers, all earlier twenty browser observations, and the combined failing 120-second native interface deadline.  Add three divider widths and three system sidebar sizes in each appearance, giving **thirty-two observations per host**.  Verify the native controller, positive pane widths, disabled collapsing, absent toolbar and menu toggle, successful delivery of the former action without hiding, and reconnection.  Retain all warning, first-row, last-row, filtering, empty applet, toolbar, preview, and keyboard-safety checks.

Reset the file Inspector selection for each appearance, correcting build 161’s Dark fixture.  Capture both appearances and all sidebar sizes.  Review the filled keyboard, indentation, matching scales, file Inspector, layout, and connection light.  Retain screen-composited and VoiceOver limits where applicable.

Require native execution of both exact canonical downloads on Apple Silicon, architecture and minimum-version checks, ad hoc signatures, hardened runtime, matching symbols, independent artifact digests and twelve asset hashes, and both Help books against tested source.  Save permanent evidence under `releases/verification/2.0.5-162`.  Provide a separate private Apple Silicon ZIP and the requested completion email only after the candidate checks pass.  Record the baseline diagnostic separately and state whether it reproduced the freeze.

## Verified result

Source `87254457b8c31d1651db567e18202789d2e9e5a2` passed [run 43743043759](https://github.com/koralatov/alphasync/actions/runs/43743043759) on 15 November 2026.  Both Intel with Xcode 26.6 and Apple Silicon with Xcode 16.4 passed all 172 Swift tests, 55 fixtures, thirty-two native window observations, twelve sidebar width and size records, three toolbar modes in each appearance, and both app and helper builds.  Both exact canonical downloads ran natively on Apple Silicon.  There were no Swift compiler warnings; existing App Intents extraction and signed-helper stripping notices remain.

The requested sidebar widths of 180, 300, and 220 points were achieved exactly in both appearances on both hosts.  Both panes remained visible after delivery of the former toggle action.  Toolbar and menu checks found no sidebar toggle.  Existing first-row, last-row, warning, selection, preview, keyboard-safety, and reconnection checks passed.  An earlier candidate’s high holding priority caused a genuine divider-resizing failure; the final priorities follow Apple’s example, and the same assertions now pass.  Other candidate corrections fixed environment forwarding and the checker’s controller lookup without weakening its layout checks.

The exact build 161 Hide Sidebar action completed without a hang in [diagnostic run 43742062437](https://github.com/koralatov/alphasync/actions/runs/43742062437).  Before and after captures confirm that it hid the old sidebar on hosted macOS 15.8.2.  This does not establish the cause of the user’s freeze on macOS 14.7.1.  The final app removes collapsing and the control that triggered the report; physical confirmation remains open.  The initial probe’s additional Show step failed because that control overflowed, so the final probe isolates the actual reported Hide action.

Independent checks matched five artifact ZIP digests, all twelve canonical asset hashes, both package manifests, and both Help books.  Each Help book contains eighteen checked pages and 83 links, with twenty authored files matching the tested source and a non-empty search index.  All 92 captured images were reviewed.  The new native sidebar appears in both hosts’ captures, including the indented hierarchy and filled keyboard symbol.  Dark toolbar compositor materials on macOS 26 and one macOS 15 Text Only background are not faithfully captured by the layer renderer; native geometry and item checks passed, and final on-screen appearance remains manual.  The Dark file Inspector fixture now captures the intended file.

The [permanent record](../releases/verification/2.0.5-162/verification.json) includes native layouts, sidebar and toolbar observations, image hashes and limits, the baseline probe, package hashes, and candidate history.  Core and hardware sources match build 161 exactly.  The separate private Apple Silicon ZIP has SHA-256 `1b21318dcdf985281e9990d7e7ece23555784bd3ff7528dce77de27a89ce94e7`.  Only 1.5.1 and 2.0.4 remain public; their notes and eighteen assets, all twelve version tags, and frozen legacy source are unchanged.

## Physical checks

Use the [manual checklist](../tests/manual-checks.md) on the affected M2 Air.  Confirm that the sidebar remains visible through divider use, window resizing, full screen, file sheets, toolbar changes, disconnecting, and reconnecting.  Check hierarchy, keyboard navigation, VoiceOver, every file and toolbar action, transfers, backups, and disposable recovery and writing operations.  macOS 13 runtime, actual Login Items approval, native Help Viewer, and the reported physical freeze remain manual checks until results are recorded.

## Apple references

- [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
- [NSSplitViewItem](https://developer.apple.com/documentation/appkit/nssplitviewitem)
- [canCollapse](https://developer.apple.com/documentation/appkit/nssplitviewitem/cancollapse)
- [toggleSidebar](https://developer.apple.com/documentation/appkit/nssplitviewcontroller/togglesidebar(_:))
- [Hosting sizing options](https://developer.apple.com/documentation/swiftui/nshostingcontroller/sizingoptions)
- [Primary-detail split-view example](https://developer.apple.com/documentation/appkit/navigating-hierarchical-data-using-outline-and-split-views)
