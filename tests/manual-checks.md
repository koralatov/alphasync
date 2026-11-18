# Manual checks for AlphaSync 2.0.5

Record the app version, build, source commit, edition, exact macOS version, architecture, Neo model, result, and any failure. Hosted builds and simulated transfers do not establish physical USB or macOS 13 runtime compatibility.

On 11 November 2026, Mike reported that 2.0.4 leaves his Neo in keyboard mode on an M2 MacBook Air, while 1.5.1 works on the same Mac. The photograph does not establish the macOS version or the Mac app’s error. The first 2.0.5 candidate, build 155, crashed in USB buffer handling on macOS 14.7.1. Build 156 must be tested on that setup before this connection issue is marked resolved. Build 155’s hosted run passed 115 Swift tests and 55 fixtures on both hosts, both app builds and native interface checks, and native verification of both canonical packages. See the [candidate record](../releases/verification/2.0.5-155/verification.json). The [investigation](../docs/neo-keyboard-mode.md) records the correction and full physical checklist.

Version 2.0.4, build 154 passed [release run 42906295418](https://github.com/koralatov/alphasync/actions/runs/42906295418) on 10 November 2026 for exact source `7b71c9fa7f8de748c91e26990050decfb2a98472`. Intel with Xcode 26.6 and Apple Silicon with Xcode 16.4 each passed 109 Swift regressions, thirteen Help fixtures, forty-two existing release fixtures, native interface checks, and both app and helper builds. A separate Apple Silicon job verified the downloaded canonical packages and executed both app-version commands natively. Intel publication then independently checked the same packages. All twelve public asset sizes and SHA-256 digests match the downloaded build packages. The [permanent verification record](../releases/verification/2.0.4-154/verification.json) preserves the evidence. Native Help Viewer, VoiceOver, physical Neo transfers, real Login Items approval, and macOS 13 runtime checks remain unverified.

Version 2.0.3, build 153 passed [release run 42819807561](https://github.com/koralatov/alphasync/actions/runs/42819807561) on 10 November 2026 for source `db3ff4c23253c024726dd812868e6ac745a7b831`. Both hosts passed 109 Swift regressions, 42 release fixtures, native interface checks, and app and helper verification. The twelve public assets match the downloaded packages. The [permanent record](../releases/verification/2.0.3-153/verification.json) retains those results. Physical checks below remain unverified.

The [frozen 1.5.1 checklist](https://github.com/koralatov/alphasync/blob/v1.5.1/tests/manual-checks.md) retains the macOS 11 and 12 checks and Mike’s earlier macOS 12 report. Do not apply Swift rewrite changes to that release.

The original build 151 [2.0.2 release run](https://github.com/koralatov/alphasync/actions/runs/42802943901) passed on 10 November 2026 for source `807b4bedf1bb1cd655e934e1495723bb5c203c93`. Both hosts passed 109 Swift regressions, 35 packaging, publication, and retirement fixtures, and the native interface checks. App, helper, architecture, deployment, signature, and symbol verification passed. The published twelve assets match the downloaded packages. These automated results do not change the unverified physical checks below.

The [build 152 reissue](https://github.com/koralatov/alphasync/actions/runs/42816587995) passed on 10 November 2026 for source `fbcc566207d550ee313245e3eff39a55d3c986fb`. Both hosts passed 109 Swift regressions, 42 release fixtures, native interface checks, and app and helper package verification. The twelve public assets match the downloaded packages, including the exact build tag for Help and licence links. The [permanent record](../releases/verification/2.0.2-152/verification.json) retains those results. The physical checks below remain unverified.

## Runtime coverage

Version 2.0.4, build 154 retains the completed transfer and maintenance features of 2.0.2. These physical checks remain outstanding:

- Enable automatic opening with a Neo already connected, including Login Items approval. Quit and reconnect. Check that a failed opening can retry, disabling the option stops the helper, and logout and login preserve the requested setting.
- Stop a backup and quit during a long file read. Previously saved files must remain, the result must say it stopped, and the unfinished folder must retain its marker.
- Connect a second Neo that cannot be opened. Keep the first connected and confirm the warning and Try Again remain visible. The table headings and file rows must stay clear of the warning and status bar. Resize the window and repeat in both appearances.
- Import a dictionary with valid, one-character, and overlong words. Cancel must write nothing for the warned file. Continuing must show the usual Replace confirmation when replacing. A non-empty file with no valid words must leave the dictionary intact. Edit the source after the warning and check that a new review appears.
- Rename or move the selected backup folder, then restart. Backups and recovery copies must use the moved folder. Disconnect its drive or remove the folder; neither operation may recreate the old path. Choose an existing legacy destination once to migrate it.
- With disposable fresh preferences, open the app and Settings without starting a backup. The default folder must not be created. Make the first backup or recovery copy, move its default destination immediately, and restart. Both operations must follow the moved folder. Remove it and confirm neither recreates the old path.
- Connect, disconnect, and reconnect in keyboard and transfer modes, including during a transfer and a confirmation. Check the app and helper after sleep and wake. No periodic idle discovery should be needed. Repeat with two Neos.
- Quit while Replace or Clear is still reading its originals, including the final check after confirmation. No writing may start. Quit after writing starts; all writes and verification in that change must finish before USB closes, with the interface still responsive.
- Cause a reader failure, choose Try Again, then close its window while it is loading. The read must stop between blocks, the window must stay closed, and another operation must become available.
- Check recovery after a temporary observer error and after sleep and wake, with the app running and with only the helper running. The app’s warning must clear after monitoring recovers. Repeated setup failures must use the documented cooldown rather than stop monitoring permanently.

| System and edition | Required check | Result |
| --- | --- | --- |
| macOS 13, Intel, Universal | Minimum runtime, physical Neo, Settings, and login helper | Not run |
| macOS 13, Apple Silicon, Universal | Minimum runtime and physical Neo | Not run |
| macOS 13, Apple Silicon, Apple Silicon | Minimum runtime, physical Neo, and helper | Not run |
| Later macOS, Intel, Universal | Physical transfers and full interface | Not run |
| Later macOS, Apple Silicon, both editions | Physical transfers, full interface, and helper | Not run |
| macOS 27, edition and architecture not specified | General operation | Reported working by Mike on 9 November 2026; individual transfer and helper checks not specified |

The macOS 27 report does not identify the build, source commit, exact system version, or Neo model.  It leaves the macOS 13 runtime checks outstanding.

Use known-good independent backups and disposable Neo files for writing checks. Install and test one edition at a time. Preserve the original files separately.

## Windows, appearance, and accessibility

- Open without a Neo. Confirm a compact connection message with the native cable symbol. Connect a Neo and check that the same window expands to fit the sidebar, file list, and every toolbar item. Disconnect the last Neo and check that it becomes compact again. Repeat with two Neos, full screen, and a sheet open.
- Resize the connected window. Confirm that table columns, status, and available memory fit, with memory aligned at the trailing edge. Check long applet names and connection errors.
- Change system appearance between Light, Dark, and Auto without restarting. Check the list, selection, toolbar, Settings, Inspector, About, sheets, file panels, and Help Viewer. Repeat with Increase Contrast, Reduce Motion, a different accent colour, and scroll bars always visible.
- Use keyboard navigation and VoiceOver throughout. Confirm that control labels, disabled states, sidebar groups, file sizes, progress, and read-only text are understandable. Check all controls on a small screen.
- Open About, close it after activating a link, and reopen it. No link should start with keyboard focus. Tab must still reach every link. Check version 2.0.4, build 154, the correct edition description, and the selected icon in About, Finder, and the Dock.
- Inspect a file, applet, and Neo. More Information and Preview must stay open, details must be selectable, and previous file text must clear when the selection changes. Check long metadata and unknown limits.
- Compare bytes and decimal KB with Finder, including 0, 1, 999, 1,000, 1,024, and 12,000 bytes. Exact values such as 51,200 bytes must use regional grouping and fit their fields.

## Reading and file actions

- Double-click a file’s name, icon, and Size cell. Each action should open one independent read-only window with the complete file. Empty space and applet selection must not open a file.
- Read a long and an empty file. Resize, scroll, select, copy, and use the native Find bar, Find Next, and Find Previous.  Use Selection for Find must be absent from the menu.  Typing, paste, cut, delete, and dropped text must not change the preview or Neo.
- Switch between Regular and Monospaced. Confirm system fonts and default size, preserved text and selection, independent open windows, and the remembered choice for newly opened windows.
- Copy to Clipboard must copy all loaded text, including text beyond the visible window, without changing selection or scroll. Check its disabled states for loading, empty files, and failed reads. Check the native symbol beside Read-only.
- Disconnect during a read, and close a loading window. Failed reads should explain the failure; closed windows must stay closed. Successfully loaded text must remain readable and copyable after disconnection.
- Export selected files through Save to Mac and by dragging names into Finder. Existing files must remain intact, and another copy must get a unique name. Exports and backups must be UTF-8.
- From All Files, right-click an unselected file. Open, Save, Rename, and Clear must refer to that file, rather than a previously selected row. A dropped text file must replace the named row only after confirmation.
- Open an import or export chooser, then change the selected file, applet, or Neo before accepting it. The operation must keep its original targets. Disconnect and reconnect the original Neo while the chooser is open; accepting it must stop with a connection error.
- Inspect a selected file, then replace or clear it, including a replacement of the same size. The preview must reload. Change its text on the device and use Refresh; the preview must show the new text.
- Interrupt an export after one file has reached the Mac. The saved file must remain, and the message must state the saved count and destination. Drag AlphaWord and dictionary files as text, and another applet’s data as XML.
- After a connection or keyboard-mode error, automatic scans and recovery from an unrelated file error must keep its message without retrying the failed connection. Refresh, Try Again, or disconnecting and reconnecting must permit another attempt.
- Import several text files with no file selected. Change the selection while a longer import is active. Its original applet destination must remain fixed. If a later file fails, the message must acknowledge any files already added.
- Rename a supported file. Reject unsupported or overlong names without silent truncation. Check successful verification, failure messages, and the refreshed list. Other applet formats must remain read-only.
- Change the file filter while an excluded applet is selected. A valid visible selection must replace it. Check natural ordering of File 1, File 2, and File 10.

## Imports and destructive changes

- Import matching MacASCII, UTF-8, and UTF-16 files, including both UTF-16 byte orders with byte-order marks. Check pound signs, supported accents, curly quotes, tabs, and paragraph breaks.
- Import matching LF, CRLF, and CR text. Paragraph breaks must be consistent.
- Import unsupported characters, including `≡` and emoji. The import must explain the character and leave device files unchanged.
- Try a 2 MB text file when adding and replacing. Both must reject the converted size before any file-writing command. Check exact and just-over limits, and a file that fits free memory but exceeds the per-file limit.
- With little free memory, check that a same-size or smaller replacement can succeed, while growth and creation preserve the reserve and reject insufficient space. Missing or damaged limit and memory replies must block writes.
- Open Clear File, Clear Selected Files, Clear All Files, and Replace warnings. Check the named targets. Neither button may be the default.  Cancel must precede the destructive button and have the initial keyboard focus.  The warning must name its Neo targets, explain the result, and offer Save a copy of the text first.  Immediately press Space, Return, keypad Enter, and Escape, each on a fresh warning. None may change device data. Repeat with keyboard navigation enabled, then deliberately reach the destructive button with Tab.
- With known-good backups and disposable files, deliberately confirm replacement and clearing. Only named contents may change. Clear All must include every file in that applet, including unbound files, and retain recovery material for all originals.
- Change a file on the device after opening its warning if the hardware permits it. The stale operation must stop rather than overwrite a different original.
- Keep windows responsive during transfers. Disconnect and reconnect another Neo while work is queued. Requests for the old connection must fail rather than reach the replacement device.

## Recovery and verification

- Recovery must initially be enabled, with 30-day retention. Change settings, restart, and confirm persistence. A warning’s temporary recovery choice must not change the saved preference.
- Replace and clear disposable files. Confirm that readable originals, exact raw `.neo` bytes, and identification metadata exist before destructive work completes. Restore saved text onto the matching Neo file and compare it.
- Use an unwritable destination or full disposable test volume. A failed requested recovery copy must block the destructive change and preserve existing copies.
- On disposable recovery folders only, check 7-, 30-, and 90-day expiry and no expiry. Recognised complete expired copies should move to Trash. Incomplete folders, directory symlinks, unrelated files, and unrecognised metadata must remain.
- Disconnect during writing or read-back verification. The warning must explain that device contents may already have changed and include any saved recovery location. A failure after an earlier file changed must not claim that no files changed.

## Backups

- With logging off, back up named, numbered, and empty files. Confirm only the files and applet folders appear in the dated destination. Repeat on the same day; completed backups must not be replaced.
- Enable Save a backup log, restart, and repeat. Each dated destination must contain its own AlphaSync Backup Log.plist with version 3, relative paths, errors, and the final state. Turning logging off again must persist.
- Interrupt discovery or make a reported count disagree with the enumerated files. Backup must stop without treating a partial list as complete.
- Stop or disconnect between files, force a file failure, and use an unwritable destination. Saved files must be retained, failures shown, and unfinished folders marked (Incomplete), with logs off and on. A finished first Neo must remain complete if a second one fails.
- Check counts, long folder paths, singular and plural wording, Open Backup Folder, and Open Backup Folders. Finder must open the actual dated locations. No created folder means no Finder button. Return should dismiss Done.
- Quit during a transfer. The interface must remain responsive while pending work finishes and USB closes safely.

## Settings, launch helper, and Help

- Check saved filters, backup destination, log option, recovery settings, and regular or monospaced preference after upgrading from 1.5.1 and after restarting. Cancelling a folder chooser must preserve its prior value.
- In Applications, enable automatic opening. Check registration errors, approval required, granting and revoking Login Items approval, logout and login, USB reconnection, and disabling it. Confirm the helper does not capture keyboard input or open another edition unexpectedly.
- Open Help with no Neo and during a transfer. Check the system search field, last menu position, AlphaSync Help as the first app item, ⌘?, command search, and topic search.
- Follow every home-page and related-topic link with the network unavailable. Read all eighteen pages, including Licence. Search for importing, renaming, recovery, and troubleshooting in Help Viewer. Check the correct 2.0.4 pages after upgrading a Mac that has cached older Help.
- Resize Help Viewer and enlarge text. Check Light, Dark, Increase Contrast, keyboard focus, VoiceOver headings and links, the shortcut table, and the wrapped licence.
- Follow the instructions with disposable files and compare menu names, selection scope, backup scope across two Neos, manual recovery, and reader behaviour after reconnection.
- Open Licence offline and compare it with LICENSE. Stable release notes must open version 2.0.4 at `v2.0.4`, and the licence must point to the same tag. GitHub and issue commands must open the intended pages.
- Contact Us must open an unsent message to mike@koralatov.com. Issue and contact forms may include only version, build, edition, system version, and process architecture. Leave reports and messages unsubmitted. Check the Copy Link fallback with an unavailable handler.

Use the final 2.0.4 ZIP for a clean-install check on another Mac. Physical Neo, real Login Items approval, and macOS 13 checks remain unverified until results are recorded here. The public release notes must retain that limit.

## Build 156 hosted checks

Both hosts passed 123 Swift regressions, including eight new buffer tests, all 55 fixtures, both app and helper builds, and native interface checks in [run 43020148543](https://github.com/koralatov/alphasync/actions/runs/43020148543). Local checks of all twelve downloaded assets, both eighteen-page Help books, and their eighty-three links passed. The final native download check did not run: neither attempt received a Mac runner. Keep that gate and the physical M2 Air test on macOS 14.7.1 open. See the [permanent record](../releases/verification/2.0.5-156/verification.json).

## Build 157 connection check

The latest report says the Neo recognises AlphaSmart Manager but AlphaSync shows reply 0x90. Build 157 corrects the System applet file-count query and must pass a fresh full build milestone. On the M2 Air, confirm that the file list appears and an existing AlphaWord file opens with its expected text. Check empty read-only applets with Show All Applets, both the dictionary and AlphaWord, Try Again, and unplugging and reconnecting. Record the actual app build and macOS version. Do not mark reading, writing, or backup as passed from manager recognition alone. See the [wire investigation](../docs/neo-parameter-reply.md).

Build 157 passed the full non-publishing [run 43642608956](https://github.com/koralatov/alphasync/actions/runs/43642608956) for source `12e9e29d8e1302265dfb5d8e1d03452df35ed44d`: 131 Swift tests, 55 fixtures, both host builds, native interfaces, and exact-package execution on Apple Silicon. Both Help books and all twelve independent asset hashes passed. These hosted results do not complete the physical checks above. See the [record](../releases/verification/2.0.5-157/verification.json).

## Build 158 USB comparison

Build 158 retains the System applet correction and adds the full [USB comparison and physical checklist](../docs/usb-parity-audit.md). Confirm the build in About, then test launch before and after attachment, complete enumeration, existing-file reads, backup, reconnect, Try Again, and the usual hub or adapter on the affected M2 Air. Compare saved contents with 1.5.1 using the same setup and one app at a time. After a verified backup, use disposable data for create, rename, replace, and interruption checks. Hosted tests cannot complete this hardware checklist.

Final [run 43647897685](https://github.com/koralatov/alphasync/actions/runs/43647897685) passed for source `74be91b1e4d65fcb43bd270cec2fb2ef12c81cc6`: both compilers passed 155 Swift tests, 55 fixtures, both app builds, and native interfaces without warnings. Exact canonical packages ran on Apple Silicon, and independent artifact, asset, symbol, and Help checks passed. The [record](../releases/verification/2.0.5-158/verification.json) preserves the evidence. Physical results above remain unverified.

## Build 159 connected window

The user reports that build 158 now connects and lists Neo files on the M2 Air.  Build 159 keeps that USB implementation and corrects content beneath the toolbar.  Confirm 2.0.5 (159) in About, then check the Neo heading, All Files, file headings, and File 1 after attachment and launch with a Neo already attached.  Resize to minimum and larger sizes, scroll long lists, reconnect, and change filters.  Check empty read-only applets and warning messages without losing access to the browser or status bar.  Clear should remain disabled across different applets and available for supported files within one applet.

The [layout investigation and 2.1 checklist](../docs/connected-layout.md) define the remaining physical transfer, backup, recovery, encoding, dictionary, accessibility, Help, Login Items, and macOS checks.  Passing the hosted layout checks does not complete these real-device checks.  Keep the public releases and all earlier private candidates unchanged.

Build 159 passed the full non-publishing [run 43718196869](https://github.com/koralatov/alphasync/actions/runs/43718196869).  Both hosts passed 157 Swift tests, all 55 fixtures, twenty actual-window observations, and both app builds.  Both exact packaged apps passed native Apple Silicon execution.  Independent asset and Help checks and captured-image review are complete.  These results do not complete the physical checklist above.  See the [record](../releases/verification/2.0.5-159/verification.json).

## Build 160 maintenance checks

Confirm 2.0.5 (160) in About.  Repeat the build 159 layout checks, file-list filtering, renaming, device switching, and reconnection.  Check that lists update immediately and that selection does not move to another file.  Scroll a read-only preview, change its font, and confirm selection, Find, and copy still work.  Check Refresh or Try Again after a recoverable connection failure.

Back up disposable files and stop during a read.  Confirm earlier files remain available, the incomplete folder stays marked, and the log accurately records cancellation.  Exercise dictionary input with long omitted words and unsupported characters, review its warning, and verify imported results.  Repeat opening, saving, drag export, replacement, recovery, and readback checks.  The [maintenance review](../docs/maintenance-160.md) distinguishes hosted verification and diagnostic timing from physical results.

Build 160 passed the full non-publishing [run 43725850279](https://github.com/koralatov/alphasync/actions/runs/43725850279) at its first attempt.  Both hosts passed 170 Swift tests, all 55 fixtures, native preview checks, twenty browser observations, and both app builds.  Both exact packaged apps passed native Apple Silicon execution.  Independent hashes and Help checks and 52-image review passed.  These results do not complete the physical checks above.  See the [record](../releases/verification/2.0.5-160/verification.json).

## Build 161 interface polish

Confirm 2.0.5 (161) in About.  Check the Neo heading and icon at Small, Medium, and Large system sidebar sizes.  AlphaWord must use the writing symbol, SpellCheck the book, System the cog, and unknown applets the generic app symbol in both sidebar and Inspector.  Individual files keep their document symbol.  Check the device Inspector without a file selection.

With a Neo open, confirm a green light beside Connected in both appearances, with Increase Contrast and different accent colours.  VoiceOver must announce the connection state.  Disconnect the last Neo and check that the compact waiting message replaces the connected browser.

The toolbar must initially show Back Up, Clear Files, Inspector, and Refresh with icons and text.  Check hover help, keyboard access, menu equivalents, and VoiceOver names.  Change View → Toolbar Appearance through all three choices, restart, and reconnect; the choice must persist and all four commands must fit at minimum window width.  Repeat the earlier first-row and scrolling checks with every appearance.

Use disposable files to check the revised single-file, selected-file, all-file, and replacement warnings.  Confirm correct targets, button order, no default button, keyboard safety, saved recovery copies, failure protection, and readback.  These physical and accessibility results remain open until recorded.

Build 161 source `1b5495c5b78efcbb09c9a700c0caf18d82047a0b` passed the full non-publishing [run 43734374426](https://github.com/koralatov/alphasync/actions/runs/43734374426): both hosts passed 172 Swift tests, 55 fixtures, native keyboard and preview checks, twenty window observations, all toolbar modes, and both editions.  Both canonical downloads ran on Apple Silicon.  Independent hashes, Help checks, and eighty-image review passed.  The [record](../releases/verification/2.0.5-161/verification.json) preserves the evidence and capture limits.  These hosted results leave the physical and accessibility checks above open.

## Build 162 permanent sidebar

Confirm 2.0.5 (162) in About.  Check that Hide Sidebar and Show Sidebar are absent from the toolbar and View menu.  The sidebar must remain visible when resizing, entering and leaving full screen, double-clicking or dragging its divider, changing toolbar appearance, disconnecting, and reconnecting.  Its divider should still adjust the width within a useful range.  Repeat with two Neos, long applet names, warning messages, and a sheet open.

Confirm the filled keyboard icon for the Neo in both sidebar and Inspector.  Child rows should be indented one level, with the original font and symbol scale.  Repeat at Small, Medium, and Large system sidebar sizes and in both appearances.  Verify keyboard and VoiceOver navigation, selection, file reading, and every toolbar action after using the divider.  Repeat disposable transfer, backup, and recovery checks before 2.1.  Record the actual macOS version and whether the former freeze can still be triggered anywhere.

The full non-publishing [run 43743043759](https://github.com/koralatov/alphasync/actions/runs/43743043759) passed for source `87254457b8c31d1651db567e18202789d2e9e5a2`.  Both hosts passed 172 Swift tests, 55 fixtures, thirty-two native window observations, twelve sidebar width and size records, all toolbar modes, and both editions.  Both exact canonical apps ran on Apple Silicon.  Independent hashes, both Help books, and 92-image review passed.  The [record](../releases/verification/2.0.5-162/verification.json) includes capture limits.  The old Hide action did not hang in the separate macOS 15.8.2 baseline probe; the physical macOS 14.7.1 report remains unconfirmed by hosted checks.  Complete the checks above on the affected M2 Air.

## Build 163 file previews

The user reports that build 162 appears to work on the M2 Air.  Detailed physical checks remain open.  Confirm **2.0.5 (163)** in About, then keep Inspector open while selecting one file, two files, an applet, and the Neo.  Preview, including its heading, must appear only for one file.  A Neo or applet retains its small header icon and More Information without an enlarged duplicate icon.  Return to a file and check its text, loading or failure state, refresh, and empty-file behaviour in both appearances.  Continue the earlier sidebar, transfer, recovery, helper, Help, and accessibility checks as available before 2.1.

Build 163 source `92c5424251ef5ffc2e4f180b6a8bf4ec2454b2dc` passed full non-publishing [run 43756388436](https://github.com/koralatov/alphasync/actions/runs/43756388436): 172 Swift tests, 55 fixtures, thirty-two window observations, and both app editions on each host.  Both exact packaged apps ran on Apple Silicon.  Independent hashes, both Help books, and 96-image review passed, including a live single-to-multiple Inspector selection change.  The [record](../releases/verification/2.0.5-163/verification.json) preserves the result and capture limits.  These checks leave the physical and accessibility checks above open.

## Build 164 maintenance

Confirm **2.0.5 (164)** in About.  With disposable files, quit during the preparation for creation, renaming, replacement, and clearing; no new file change should start after cancellation.  Quit during a longer refresh and check that it stops between metadata requests.  Once a file change has begun writing, it must finish and verify before the connection closes.  Stop a backup during its initial file-list check; the result must say stopped, with no created folder.

With VoiceOver enabled, check the operation name and native progress value, connection and failure updates, completion messages, and absence of duplicate speech from modal warnings.  A waiting confirmation must keep conflicting commands unavailable without an idle progress spinner.  Repeat in both appearances.

Open a loaded Reader, focus its font control or another control, and use each Find command.  The Reader’s text must be the target.  Find must be unavailable in the browser, Inspector, Settings, loading readers, and failed readers, and after closing the Reader.  Right-click writable and read-only files; Rename and Clear must be absent where they do not apply, and destructive actions must remain last.  Check multiple selection and busy states without changing their original targets.

Check byte and decimal KB labels, including zero, one byte, and the 1,000-byte boundary, under your actual regional settings.  Continue all earlier transfer, recovery, helper, Help, and accessibility checks when available.  The [maintenance review](../docs/maintenance-164.md) distinguishes hosted verification from these physical checks.

## Build 165 refinements

Confirm **2.0.5 (165)** in About and continue the existing 2.1 checklist.  Use disposable files and a verified backup.  If hardware permits changing a file’s name or details while a Replace or Clear warning is open, confirm that the stale warning cannot change any named file.  Record a boundary that cannot be exercised as untested.

Review a dictionary import with omitted words.  Cancel must be on the left, initially focused, and available with Escape.  No button is the default, and Return, keypad Enter, and Space must never consent to an import.  Continuing deliberately must still require the usual Replace confirmation for an existing file.  Check selectable omission details.

Try empty, unsupported, overlong, unchanged, and valid different names in Rename.  The visible guidance and VoiceOver hint must explain the disabled state.  Check exact file sizes and available memory with VoiceOver, the backup chooser label, Stop backup, and multiple Neo connection wording when available.

Check native Find after closing, retrying, or reloading a Reader, including when another control has keyboard focus.  Review Light and Dark appearance, actual speech, keyboard focus, Help, Login Items approval, and physical transfers.  The [review](../docs/refinements-165.md) separates hosted checks from these physical results.

## Build 166 simplifications and confirmations

Confirm **2.0.5 (166)** in About and continue the existing 2.1 checklist.  Clear must remain unavailable for an empty or read-only applet, a Neo selected as a whole with no file selection, and while a confirmation or transfer is active.  A selected writable file or files from one writable applet must retain their expected scope.

Open a multiple-file Clear warning using disposable files.  Check that each name is on its own line, including a name with a comma, and that names and the explanation can be selected and copied.  Keep the recovery option enabled for testing.  Return, keypad Enter, and Space must not approve the change; Escape and Cancel must cancel.  Repeat Clear, Replace, and dictionary review in both appearances with VoiceOver.

Cancel a warning, open another, and check normal consent and cancellation.  Change an imported dictionary source while its omission warning is open; continuing must require a fresh review of the new source, then the usual Replace warning.  No completed or cancelled action should unexpectedly reopen a warning or repeat a file change.

Keep a file selected while attaching another Neo where available.  Its preview must remain stable.  Explicit Refresh must show current text, including changes with the same file size.  Check Find after reloading and closing Readers with another control focused.  Continue the wider transfer, recovery, helper, Help, regional, accessibility, and oldest-runtime checks.  Hosted checks and physical limits are recorded separately in the [maintenance plan](../docs/maintenance-166.md).

## Final build 167 checks before 2.1

Install the new candidate and confirm **2.0.5 (167)** in About.  Start with a full backup, verify the saved files, and use disposable Neo text for changes.  Continue the earlier 2.1 checklist.

- Open About’s Release notes link and confirm the private source notes open.  Check Licence through native Help Viewer.
- Rename a disposable file to a valid accented name.  Invalid, unsupported, and overlong names must leave the Neo unchanged.  Import a text file with an overlong or unsupported base name and confirm the error, preserved source, and unchanged Neo inventory.
- Cancel import, export, and backup-folder panels.  Confirm no operation begins.  If a real folder or provider access error occurs, confirm it is reported rather than silently discarded.
- Check completed, stopped, and empty backups.  Check saved counts, preserved originals, readable and selectable errors and paths, Done with Return, and Open Backup Folder in Finder.  A stopped backup must retain already saved files and accurate logs.
- With VoiceOver enabled, check dialog heading navigation, labels, announcements, recovery options, and safe Cancel focus.  Repeat keyboard selection, editing, Find, and Light and Dark appearance checks on the actual Mac.

Hosted checks cannot establish physical Neo transfers, actual VoiceOver speech, final composited materials, macOS 13 runtime, Help Viewer, or Login Items approval.  Record tonight’s physical results before deciding on stable 2.1.  Keep further app changes focused on problems found by that testing.

For build 167, choose each Toolbar Appearance, disconnect and reconnect the Neo, and confirm the chosen style is retained.  Repeat in both appearances and check the toolbar’s native context menu and View menu remain in agreement.

Build 167 exact source `1d8d2ba5ceeedd7caea7c4acf2769f01f7a56304` passed [run 44062779696](https://github.com/koralatov/alphasync/actions/runs/44062779696) with 212 Swift regressions, 56 fixtures, all native checks, and both editions on both pinned hosts.  Both exact packages ran on Apple Silicon.  Independent hashes, both Help books, and 136-image review are complete, and the separate test ZIP is saved.  The [permanent record](../releases/verification/2.0.5-167/verification.json) preserves earlier failed attempts, corrections, and capture limits.  These hosted results leave tonight’s physical checks open.

## Unbuilt drop and Find corrections after build 167

These checks are deferred until a new build is requested.  The existing build 167 ZIP still has the reported behaviour.

- Drop one text file over empty list space and the Neo or applet sidebar with no file selected, one selected, and several selected.  Every drop must be rejected, with no changed selection, new file, replacement warning, or device write.
- Drop several text files over an existing file.  Reject the drop without changing selection or Neo contents.  Drops over absent, disconnected, or read-only targets must also do nothing.
- Drop one text file directly onto a writable file’s name.  The warning must name that file.  Cancel must preserve its contents.  Deliberate consent with disposable data must replace only that file, retain the inventory, and preserve every other file.  Keep recovery enabled when checking retained originals.
- Check that the Find menu has Find, Find Next, and Find Previous, with Use Selection for Find absent.  Repeat availability, native Find bar, unrelated focused field, Reader unload, reload, late cleanup, and close checks.

The [follow-up record](../docs/drop-and-find-follow-up.md) includes the source corrections and the Neo’s own single-file deletion procedure.  No new build or physical result is claimed.
