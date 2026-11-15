# Connected window layout and the path to 2.1

On 15 November 2026, the user reported that the supplied 2.0.5 test build now works with the Neo on the M2 MacBook Air. The screenshot confirms a connected file list. It also shows the sidebar’s top items, file headings, and File 1 hidden beneath the title bar and toolbar. Scrolling cannot expose them. This is a window layout problem after connection, rather than evidence that those files are missing.

The user corrected the proposed 2.0.6 version to the next 2.0.5 build. Prepare **2.0.5, build 159**, privately. Do not publish a release or change protected references.

## Corrections

The file manager wrapped NavigationSplitView in a vertical stack with warning and status rows, then clipped the browser. That confined drawing without preserving the toolbar safe area used by the native sidebar and table. Previous interface checks used ordinary titled windows, so they did not establish first-row visibility with the app’s full-size content and unified toolbar arrangement.

Keep the navigation container within the window’s measured viewport. Reserve warning and status rows inside its file column, around a table sized to the remaining space. The sidebar retains its native toolbar safe area. Remove the outer clipping wrapper; clip only the table’s own measured viewport. Do not add fixed toolbar heights, negative padding, window repositioning, or private view traversal to the app.

AppKit’s [contentLayoutRect](https://developer.apple.com/documentation/appkit/nswindow/contentlayoutrect) gives the area not obscured by the title bar and toolbar. Measure those live coordinates in the native checks instead of assuming the same toolbar height on every macOS version. Keep normal SwiftUI layout inside each navigation column so the file table cannot draw beneath its neighbouring bars.

The related review found that the toolbar and File menu enabled Clear for files from different writable applets, although the operation and context menu require one applet at a time. Enforce that rule in shared command eligibility. Keep a valid selection from one writable applet enabled, with the existing confirmation and recovery protections. The built-in Help already explains this rule.

Preserve build 158’s USB implementation, file formats, preflights, recovery, and readback verification. Review connected and waiting layouts, sidebar selection, filtered and empty applets, file scrolling, warning insertion and removal, resizing, reconnection, and Clear eligibility.

## Full compile and build milestone

Review edits before tests. This is the non-publishing milestone for 2.0.5, build 159. Two Clear regressions extend the Swift suite from 155 to 157. Require all 55 Help and release fixtures, both pinned Mac compilers, both app editions and helpers, native interfaces, signatures, architectures, matching symbols, Help, and native execution of the exact canonical downloads.

Add twenty native browser layout observations across Light and Dark Mode, using the app’s SwiftUI Window scene and actual toolbar. Connect in the waiting window, then check the first sidebar items, first file, and headings against the actual unobscured area. Cover warning messages, minimum and expanded sizes, warning removal, a 64-file list scrolled to its end, an empty read-only applet, filter changes, and reconnection. Retain private preferences and a combined failing 120-second deadline for component and window-scene checks. The checker does not access USB hardware or register a login item.

Inspect captured images as well as geometry. Independently verify artifact digests, all twelve assets, both Help books, and authored files against the tested source. Keep a separate private Apple Silicon ZIP and preserve earlier candidates. Record actual results after execution; hosted checks cannot establish every real Neo operation.

The initial milestone source `8bc3fbd21135c1b40a4942465d465fe041d0ec4a` hit the older compiler’s type-checking limit in the expanded sample-file expression before tests ran. Replace that expression with typed intermediate values and a simple loop, without changing the app correction. Require a fresh full milestone for the corrected source and retain the failed run as diagnostic history.

The corrected fixture source `52cee3f46131024d243525ff8dfe9936adef5211` passed 157 Swift tests, all 55 fixtures, and both app builds on the older host. Its new full-toolbar checks confirmed first-row visibility but caught the connection warning overlapping the headings and File 1 on macOS 15. A root-level safe-area inset did not reserve that warning’s space in the native split view. Keep the root navigation container and move both bars into the file column instead. Retain the failing warning assertion, capture failure images and partial geometry, and repeat the full milestone before handover.

The file-column source `2bf2aafbead3542df22d59f92c196a803f37ad48` passed all 157 Swift tests and 55 fixtures on Intel. Its native check caught the browser expanding to a 1,024-point intrinsic height after adding a warning, beyond the 560-point unobscured window. Pin the navigation container and native table to their measured GeometryReader viewports so intrinsic ideal sizes cannot displace visible rows. Keep every geometry assertion. Move the existing native checker before the app builds and require its success there, retaining all build, package, and publication gates. This catches layout faults sooner without weakening verification. Explicitly discard the diagnostic capture’s optional result to keep both compilers clean.

Source `f61b51cdd1fa51d7f53d2f46d111de15b040b80a` passed the Swift regressions on Apple Silicon, but its standalone hosting-controller fixture still produced inconsistent browser sizing. Replace that artificial browser window with a SwiftUI App and Window scene using the same default size, content-size policy, commands, and shared MainView as AlphaSyncApp. Let SwiftUI create its real toolbar and manage connection transitions. Await layout asynchronously instead of running nested event loops during browser updates. Retain all twenty visibility observations, actual-window images, partial failure geometry, and view-tree diagnostics. The separate component checks still cover About, Settings, Inspector, confirmation defaults, and read-only text. Both phases must succeed within the existing combined deadline before app builds proceed.

The first scene harness, source `a52dc451661c654f3fbed204aadbe7eccab21039`, passed component checks but timed out in the application event loop before opening its window. Its regular activation policy was set in a driver created only by that window. Move activation to application launch through the test App delegate, with startup and probe checkpoints. Keep the timeout and all assertions; the production app is unchanged by this harness correction.

## Physical checks and 2.1

The intended stable release is **2.1 for Apple Silicon**. Build 159 is a test toward that goal. Retain both current targets during validation; this request does not retire an edition or publish 2.1. After 2.1 is verified and released, suspend feature development and limit planned maintenance to future macOS compatibility.

1. Confirm build 159 in About on the M2 Air. Connect the Neo and check that its heading, All Files, column headings, and File 1 are fully visible. Test launching before and after attachment.
2. Resize, scroll both lists, change displayed applets, and reconnect. Every item must remain reachable clear of the toolbar and status bar.
3. Complete real opening, saving, backup, drag export, import, rename, replacement, dictionary, recovery, and readback checks in the [manual checklist](../tests/manual-checks.md). Use verified backups and disposable writing for changes to the Neo.
4. Check intended macOS versions, native Help, accessibility, and actual Login Items approval. Record unavailable systems and untested functions explicitly.
5. Publish 2.1 only on a release request after reviewing functional results. Preserve frozen 1.5.1, existing assets and tags, and public 2.0.4 until an authorised release and retirement plan changes them.
