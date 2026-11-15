# Connected window layout and the path to 2.1

The user reported a working Neo connection on the M2 MacBook Air on 15 November 2026.  The screenshot confirms a connected file list, but the sidebar’s top items, file headings, and File 1 sit beneath the toolbar and cannot be scrolled into view.

The corrected request is a private **2.0.5, build 159**, rather than 2.0.6.  The planned stable release is **2.1 for Apple Silicon**.  This test does not publish a release, retire an edition, change protected tags, or alter the frozen legacy source.

## Changes

Keep NavigationSplitView as the connected browser’s root.  Reserve connection warnings and status information in an ordinary vertical stack inside the file column.  Give the native table, its column, and the navigation container flexible frames with explicit zero minimums.  This lets the file scroll view shrink to the available space instead of imposing its 1,024-point ideal height after a warning appears.  Remove the old clipping wrapper.  Keep the native sidebar, column resizing, toolbar, selection, drag export, row replacement, and background import.

Do not hard-code toolbar heights, add negative padding, reposition the window, or traverse private views in the app.  Native checks use AppKit’s [contentLayoutRect](https://developer.apple.com/documentation/appkit/nswindow/contentlayoutrect) to measure the actual area clear of the toolbar.

The review also found that the toolbar and File menu enabled Clear for files from different writable applets, although the operation and context menu accept one applet at a time.  Shared command eligibility now applies that same rule.  A supported selection within one applet still opens the existing confirmation and recovery flow.  Two regressions check both cases and confirm that preparation performs no write.  The built-in Help already explains the one-applet rule.

Build 158’s USB and core sources are unchanged.  This preserves its mode switch, owned buffers, System applet handling, packet checks, cleanup, preflights, recovery, and readback verification.

## Native layout verification

The previous interface fixture used an ordinary titled hosting-controller window.  It did not establish visibility with the app’s real SwiftUI toolbar and connection transition.  The updated checker launches a temporary app bundle through Launch Services, using the production MainView, Window scene, commands, default size, and content-size policy.  Test preferences and Login Items are isolated; USB discovery is disabled.

Each host must pass ten browser observations in each appearance:

| Observation | Required result |
| --- | --- |
| Connection from the compact waiting window | Neo heading, All Files, File 1, and column headings are visible |
| Connection warning | The warning reserves space above the first file |
| Minimum and expanded window sizes | Both lists remain inside the visible area |
| Warning removal | The table recovers the available space |
| Long list at its start and end | First and final files remain reachable clear of the bars |
| Empty read-only applet | The browser stays visible and changes remain unavailable |
| Applet filter change | A hidden applet does not remain selected |
| Disconnection and reconnection | The same window returns to a usable browser |

Both phases of the checker share a failing 120-second deadline.  The launcher requires a fresh receipt confirming all twenty observations; its own exit status is insufficient.  Failure captures include partial geometry and public view diagnostics.  Browser images read the displayed layer tree without invoking AppKit’s print/cache layout.  Separate component checks retain About, Settings, Inspector, safe confirmation defaults, selectable read-only text, Find support, and copy behaviour.  The test executable and temporary bundle are excluded from shipping app targets.

The expanded checks caught additional warning overflow before handover.  Testing before any connected-browser screenshot confirmed that snapshot rendering was not causing it.  Explicit zero minimums corrected the scroll view’s sizing.  Preserve those assertions and the diagnostic history when maintaining the layout.

## Full build milestone

Require 157 Swift regressions and all 55 Help, package, publication, and retirement fixtures on both pinned hosts.  Both hosts build Universal and Apple Silicon editions and helpers.  Check signatures, hardened runtime, architectures, deployment versions, matching crash symbols, Help, and native execution of the exact canonical downloads.  Independently compare all four artifact digests, twelve asset hashes, both packaged Help books, and their authored files with the tested source.  Inspect captured interfaces in both appearances.

Source `97f15dd1ab338f119df8d093fd87260bf0be82c1` passed [run 43718196869](https://github.com/koralatov/alphasync/actions/runs/43718196869) on both pinned hosts.  All 157 Swift tests, 55 fixtures, forty browser observations, both app and helper builds, and exact-package native execution passed.  Independent digests, all twelve assets, and both Help books matched.  Review covered 52 captured images. macOS 15 images show the complete browser; macOS 26 layer captures omit compositor-backed sidebar and toolbar backgrounds, so geometry establishes those rows’ bounds there and system-composited appearance remains a manual check.  The [permanent record](../releases/verification/2.0.5-159/verification.json) preserves the evidence and diagnostic runs.  A separate private Apple Silicon ZIP is ready.  Hosted checks do not establish every physical Neo operation.

## Physical checks and 2.1

1.  Confirm 2.0.5 (159) in About on the M2 Air.  Check the Neo heading, All Files, column headings, and File 1 after attachment and after launching with the Neo already attached.
2.  Resize, scroll both lists, change displayed applets, and reconnect.  Check warning messages and the status bar.  Every item must remain reachable.
3.  Complete opening, saving, backup, drag export, import, rename, replacement, dictionary, recovery, and readback checks in the [manual checklist](../tests/manual-checks.md).  Use verified backups and disposable writing for changes to the Neo.
4.  Check intended macOS versions, native Help, accessibility, and actual Login Items approval.  Record unavailable systems and untested functions explicitly.
5.  Publish 2.1 only on a release request after reviewing functional results.  Preserve frozen 1.5.1, existing assets and tags, and public 2.0.4 until an authorised release and retirement plan changes them.

After 2.1 is verified and released, suspend feature development and limit planned maintenance to future macOS compatibility.

## Build 162 sidebar change

The user subsequently reported that build 161 freezes when Hide Sidebar is clicked and requested a sidebar that cannot be hidden.  [Build 162](sidebar-162.md) therefore replaces the collapsing navigation container with a public AppKit split controller.  It retains the same SwiftUI content, flexible zero-minimum frames, and every earlier layout observation.  Additional width and system-size checks extend the native observations to thirty-two per host.  The earlier NavigationSplitView-root instruction describes builds 159–161; use the new permanent split container for this authorised change.
