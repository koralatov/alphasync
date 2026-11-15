# Connected window layout and the path to 2.1

On 15 November 2026, the user reported that the supplied 2.0.5 test build now works with the Neo on the M2 MacBook Air. The screenshot confirms a connected file list. It also shows the sidebar’s top items, file headings, and File 1 hidden beneath the title bar and toolbar. Scrolling cannot expose them. This is a window layout problem after connection, rather than evidence that those files are missing.

The user corrected the proposed 2.0.6 version to the next 2.0.5 build. Prepare **2.0.5, build 159**, privately. Do not publish a release or change protected references.

## Corrections

The file manager wrapped NavigationSplitView in a vertical stack with warning and status rows, then clipped the browser. That confined drawing without preserving the toolbar safe area used by the native sidebar and table. Previous interface checks used ordinary titled windows, so they did not establish first-row visibility with the app’s full-size content and unified toolbar arrangement.

Keep the navigation container in charge of layout. Reserve warning and status bars with public SwiftUI safe-area insets so both native scroll views receive them. Remove the clipping wrapper. Do not add fixed toolbar heights, negative padding, window repositioning, or private view traversal to the app.

Apple’s [safeAreaInset documentation](https://developer.apple.com/documentation/swiftui/view/safeareainset(edge:alignment:spacing:content:)) describes reserving adjacent content space and updating the safe area. AppKit’s [contentLayoutRect](https://developer.apple.com/documentation/appkit/nswindow/contentlayoutrect) gives the area not obscured by the title bar and toolbar. Measure those live coordinates in the native checks instead of assuming the same toolbar height on every macOS version.

The related review found that the toolbar and File menu enabled Clear for files from different writable applets, although the operation and context menu require one applet at a time. Enforce that rule in shared command eligibility. Keep a valid selection from one writable applet enabled, with the existing confirmation and recovery protections. The built-in Help already explains this rule.

Preserve build 158’s USB implementation, file formats, preflights, recovery, and readback verification. Review connected and waiting layouts, sidebar selection, filtered and empty applets, file scrolling, warning insertion and removal, resizing, reconnection, and Clear eligibility.

## Full compile and build milestone

Review edits before tests. This is the non-publishing milestone for 2.0.5, build 159. Two Clear regressions extend the Swift suite from 155 to 157. Require all 55 Help and release fixtures, both pinned Mac compilers, both app editions and helpers, native interfaces, signatures, architectures, matching symbols, Help, and native execution of the exact canonical downloads.

Add twenty native browser layout observations across Light and Dark Mode, using a full-size content window and unified toolbar. Connect in the waiting window, then check the first sidebar items, first file, and headings against the actual unobscured area. Cover warning messages, minimum and expanded sizes, warning removal, a 64-file list scrolled to its end, an empty read-only applet, filter changes, and reconnection. Retain the failing 120-second deadline and private preferences. The checker does not access USB hardware or register a login item.

Inspect captured images as well as geometry. Independently verify artifact digests, all twelve assets, both Help books, and authored files against the tested source. Keep a separate private Apple Silicon ZIP and preserve earlier candidates. Record actual results after execution; hosted checks cannot establish every real Neo operation.

## Physical checks and 2.1

The intended stable release is **2.1 for Apple Silicon**. Build 159 is a test toward that goal. Retain both current targets during validation; this request does not retire an edition or publish 2.1. After 2.1 is verified and released, suspend feature development and limit planned maintenance to future macOS compatibility.

1. Confirm build 159 in About on the M2 Air. Connect the Neo and check that its heading, All Files, column headings, and File 1 are fully visible. Test launching before and after attachment.
2. Resize, scroll both lists, change displayed applets, and reconnect. Every item must remain reachable clear of the toolbar and status bar.
3. Complete real opening, saving, backup, drag export, import, rename, replacement, dictionary, recovery, and readback checks in the [manual checklist](../tests/manual-checks.md). Use verified backups and disposable writing for changes to the Neo.
4. Check intended macOS versions, native Help, accessibility, and actual Login Items approval. Record unavailable systems and untested functions explicitly.
5. Publish 2.1 only on a release request after reviewing functional results. Preserve frozen 1.5.1, existing assets and tags, and public 2.0.4 until an authorised release and retirement plan changes them.
