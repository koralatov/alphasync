# Permanent sidebar in build 162

Prepare private **2.0.5, build 162** after the user reported that Hide Sidebar freezes build 161.  The user agreed to remove hiding entirely, indent child items one level, and use `keyboard.fill` for the dark-coloured Neo.  Keep the sidebar width adjustable.  This is a test build towards 2.1, with no release publication or retirement.

## Review and implementation

Build 161 uses NavigationSplitView, which supplies the automatic sidebar toolbar button.  Its caption became visible when toolbar labels were enabled.  The existing native tests exercised display modes and resizing, but never activated that button.  The hardware report establishes a regression; the exact blocking stack has not yet been established.

Use a public NSSplitViewController containing two ordinary NSSplitViewItems, rather than sidebar-behaviour items.  Both have `canCollapse = false`.  The navigation pane is 180–300 points wide, initially 220, and the file pane has a 400-point minimum.  The connected window retains its 760-point minimum.  These constraints leave room for both panes.  Ordinary items do not participate in the controller’s `toggleSidebar` action or automatic sidebar collapsing.  No new toolbar button or hide command is added.

The two hosting controllers have empty sizing options because split items own their widths and the outer SwiftUI window owns its limits.  This avoids competing minimum, maximum, and ideal content constraints during a pane transition.  Retain the original flexible zero-minimum frames on the file table and its containers.  Pass system sidebar size, appearance, and contrast through the hosting boundary, and preserve each controller when updating its SwiftUI content.  Set the initial divider once, so ordinary updates retain the user’s width.

Replace the default sidebar command group with the existing toolbar appearance, Inspector, and Refresh commands.  This removes alternate menu routes to hiding.  Keep all four labelled toolbar actions and their saved display modes.  Indent All Files and each applet by fourteen points without changing their font, symbol size, or selection scope.  Share `keyboard.fill` between the sidebar and device Inspector; use system colours in both appearances.

The USB, core, and hardware sources must match build 161 exactly.  Keep all file preflights, consent, recovery, cancellation, and verification behaviour.  Update the current Help, manual checklist, release notes, and technical guide.  Preserve earlier private candidates, both public release listings and downloads, all twelve version tags, and the frozen legacy source.

## Baseline freeze investigation

The separate `sidebar-diagnostic.yml` workflow runs only when its own files change, or on manual request.  It archives exact tested source `1b5495c5b78efcbb09c9a700c0caf18d82047a0b`, changes only the isolated window-check driver, and compiles the original interface on Apple Silicon with Xcode 16.4.  The original MainView hash is recorded.  No frozen branch or tag is checked out or changed.

The probe opens a sample connected window at minimum size and activates the actual toolbar item through its public target/action, or a click within its public view bounds.  It attempts hide and show, recording checkpoints before each action.  A separate twenty-second deadline saves a process sample and terminates the disposable process if it blocks.  A receipt distinguishes a captured action hang, no hang reproduced, and a failed probe.  A diagnostic hang is evidence about the old build, never a passing result for the new app.  Hosted macOS 15 is not the affected physical M2 Air’s reported macOS 14.7.1, so failure to reproduce cannot establish that the user’s report is resolved.

## Full compile and build milestone

Review edits and diffs first.  Keep all **172 Swift tests** and **55 fixtures**, both pinned compilers, both app editions and helpers, all earlier twenty browser observations, and the combined failing 120-second native interface deadline.  Add three divider widths and three system sidebar sizes in each appearance, giving **thirty-two observations per host**.  Verify the native controller, positive pane widths, disabled collapsing, absent toolbar and menu toggle, successful delivery of the former action without hiding, and reconnection.  Retain all warning, first-row, last-row, filtering, empty applet, toolbar, preview, and keyboard-safety checks.

Reset the file Inspector selection for each appearance, correcting build 161’s Dark fixture.  Capture both appearances and all sidebar sizes.  Review the filled keyboard, indentation, matching scales, file Inspector, layout, and connection light.  Retain screen-composited and VoiceOver limits where applicable.

Require native execution of both exact canonical downloads on Apple Silicon, architecture and minimum-version checks, ad hoc signatures, hardened runtime, matching symbols, independent artifact digests and twelve asset hashes, and both Help books against tested source.  Save permanent evidence under `releases/verification/2.0.5-162`.  Provide a separate private Apple Silicon ZIP and the requested completion email only after the candidate checks pass.  Record the baseline diagnostic separately and state whether it reproduced the freeze.

## Physical checks

Use the [manual checklist](../tests/manual-checks.md) on the affected M2 Air.  Confirm that the sidebar remains visible through divider use, window resizing, full screen, file sheets, toolbar changes, disconnecting, and reconnecting.  Check hierarchy, keyboard navigation, VoiceOver, every file and toolbar action, transfers, backups, and disposable recovery and writing operations.  macOS 13 runtime, actual Login Items approval, native Help Viewer, and the reported physical freeze remain manual checks until results are recorded.

## Apple references

- [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
- [NSSplitViewItem](https://developer.apple.com/documentation/appkit/nssplitviewitem)
- [canCollapse](https://developer.apple.com/documentation/appkit/nssplitviewitem/cancollapse)
- [toggleSidebar](https://developer.apple.com/documentation/appkit/nssplitviewcontroller/togglesidebar(_:))
- [Hosting sizing options](https://developer.apple.com/documentation/swiftui/nshostingcontroller/sizingoptions)
