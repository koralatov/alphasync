# Manual checks for AlphaSync 1.6

Record the app version, build, source commit, edition, exact macOS version, architecture, Neo model, result, and any failure. Hosted builds and simulated transfers do not establish physical USB or macOS 13 runtime compatibility.

The [frozen 1.5.1 checklist](https://github.com/koralatov/alphasync/blob/v1.5.1/tests/manual-checks.md) retains the macOS 11 and 12 checks and Mike’s earlier macOS 12 report. Do not apply 1.6 changes to that release.

## Runtime coverage

| System and edition | Required check | Result |
| --- | --- | --- |
| macOS 13, Intel, Universal | Minimum runtime, physical Neo, Settings, and login helper | Not run |
| macOS 13, Apple Silicon, Universal | Minimum runtime and physical Neo | Not run |
| macOS 13, Apple Silicon, Apple Silicon | Minimum runtime, physical Neo, and helper | Not run |
| Later macOS, Intel, Universal | Physical transfers and full interface | Not run |
| Later macOS, Apple Silicon, both editions | Physical transfers, full interface, and helper | Not run |

Use known-good independent backups and disposable Neo files for writing checks. Install and test one edition at a time. Preserve the original files separately.

## Windows, appearance, and accessibility

- Open without a Neo. Confirm a compact connection message with the native cable symbol. Connect a Neo and check that the same window expands to fit the sidebar, file list, and every toolbar item. Disconnect the last Neo and check that it becomes compact again. Repeat with two Neos, full screen, and a sheet open.
- Resize the connected window. Confirm that table columns, status, and available memory fit, with memory aligned at the trailing edge. Check long applet names and connection errors.
- Change system appearance between Light, Dark, and Auto without restarting. Check the list, selection, toolbar, Settings, Inspector, About, sheets, file panels, and Help Viewer. Repeat with Increase Contrast, Reduce Motion, a different accent colour, and scroll bars always visible.
- Use keyboard navigation and VoiceOver throughout. Confirm that control labels, disabled states, sidebar groups, file sizes, progress, and read-only text are understandable. Check all controls on a small screen.
- Open About, close it after activating a link, and reopen it. No link should start with keyboard focus. Tab must still reach every link. Check version 1.6, build 148, the correct edition description, and the selected icon in About, Finder, and the Dock.
- Inspect a file, applet, and Neo. General and Preview must stay open, details must be selectable, and previous file text must clear when the selection changes. Check long metadata and unknown limits.
- Compare bytes and decimal KB with Finder, including 0, 1, 999, 1,000, 1,024, and 12,000 bytes. Exact values such as 51,200 bytes must use regional grouping and fit their fields.

## Reading and file actions

- Double-click a file’s name, icon, and Size cell. Each action should open one independent read-only window with the complete file. Empty space and applet selection must not open a file.
- Read a long and an empty file. Resize, scroll, select, copy, and use the native Find bar, Find Next, Find Previous, and Use Selection for Find. Typing, paste, cut, delete, and dropped text must not change the preview or Neo.
- Switch between Regular and Monospaced. Confirm system fonts and default size, preserved text and selection, independent open windows, and the remembered choice for newly opened windows.
- Copy to Clipboard must copy all loaded text, including text beyond the visible window, without changing selection or scroll. Check its disabled states for loading, empty files, and failed reads. Check the native symbol beside Read-only.
- Disconnect during a read, and close a loading window. Failed reads should explain the failure; closed windows must stay closed. Successfully loaded text must remain readable and copyable after disconnection.
- Export selected files through Save to Mac and by dragging names into Finder. Existing files must remain intact, and another copy must get a unique name. Exports and backups must be UTF-8.
- From All Files, right-click an unselected file. Open, Save, Rename, and Clear must refer to that file, rather than a previously selected row. A dropped text file must replace the named row only after confirmation.
- Import several text files with no file selected. Change the selection while a longer import is active. Its original applet destination must remain fixed. If a later file fails, the message must acknowledge any files already added.
- Rename a supported file. Reject unsupported or overlong names without silent truncation. Check successful verification, failure messages, and the refreshed list. Other applet formats must remain read-only.
- Change the file filter while an excluded applet is selected. A valid visible selection must replace it. Check natural ordering of File 1, File 2, and File 10.

## Imports and destructive changes

- Import matching MacASCII, UTF-8, and UTF-16 files, including both UTF-16 byte orders with byte-order marks. Check pound signs, supported accents, curly quotes, tabs, and paragraph breaks.
- Import matching LF, CRLF, and CR text. Paragraph breaks must be consistent.
- Import unsupported characters, including `≡` and emoji. The import must explain the character and leave device files unchanged.
- Try a 2 MB text file when adding and replacing. Both must reject the converted size before any file-writing command. Check exact and just-over limits, and a file that fits free memory but exceeds the per-file limit.
- With little free memory, check that a same-size or smaller replacement can succeed, while growth and creation preserve the reserve and reject insufficient space. Missing or damaged limit and memory replies must block writes.
- Open Clear File, Clear Selected Files, Clear All Files, and Replace warnings. Check the named targets. Cancel must be the default and initial focus. Immediately press Space, Return, keypad Enter, and Escape, each on a fresh warning. None may change device data. Repeat with keyboard navigation enabled, then deliberately reach the destructive button with Tab.
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
- Open Licence offline and compare it with LICENSE. Development release notes must open the 1.6 development notes, rather than a nonexistent public release. GitHub and issue commands must open the intended pages.
- Contact Us must open an unsent message to mike@koralatov.com. Issue and contact forms may include only version, build, edition, system version, and process architecture. Leave reports and messages unsubmitted. Check the Copy Link fallback with an unavailable handler.

Use the final development ZIP for a clean-install check on another Mac. Record results here before proposing a public 1.6 release.
