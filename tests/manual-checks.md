# Manual release checks

Record the exact app version, build number, source commit, macOS version, architecture, Neo model, result, and any failure. A deployment target check establishes how the executable was built; runtime and USB checks need the actual system and device.

## Systems

| System | Check | Manual result |
|---|---|---|
| macOS 11, Intel | Minimum runtime and older login-item API | Not run |
| macOS 11, Apple Silicon | Minimum runtime and older login-item API | Not run |
| macOS 12.7.5 | Available older Mac and older login-item API | Not run |
| macOS 13 or later | Launcher registration, approval, and settings changes | Not run |
| macOS 26, Intel and Apple Silicon | Universal app, real USB transfers on both architectures | Not run |
| macOS 27 or later, Apple Silicon | Modern app, real USB transfers, and launcher approval | Not run |

macOS 12.7.5 provides a useful older-system check. Passing there does not establish a result for macOS 11. The automated macOS 15 and 26 builds also do not fill either macOS 11 row.

Record the host with `sw_vers` and `uname -m`. If Xcode tools are installed, run `scripts/verify-app.sh /Applications/AlphaSync.app` to check both architectures, deployment targets, versions, dependencies, signatures, and window loading on that host.

With the app running, change macOS Appearance between Light, Dark, and Auto in System Settings (System Preferences on macOS 11 and 12). Check the main list, selected and unselected rows, toolbar, Inspector previews and details, Preferences, backup sheet, alerts, file panels, and Apple Help Viewer. Check Increase Contrast and a different accent colour too. The app should update without restarting. Confirm that file renaming still accepts Return, cancels with Escape, and is unavailable during a transfer. `scripts/check-appearance.sh /Applications/AlphaSync.app build/appearance` provides automated appearance checks and screenshots without using a Neo; the system-setting and hardware checks still need a person.

For the modern app, run `scripts/verify-app.sh /Applications/AlphaSync.app modern` on macOS 27 or later. This requires exactly `arm64` in both the app and launcher, with a macOS 27 minimum. Verify that the release contains both downloads with matching versions and source commits, and install only the app appropriate for the test Mac.

## Help menu

- Open Help without a Neo and during a background transfer. Confirm that the system Search field is present, AlphaSync Help is the first app command, and Help remains the last menu. Test ⌘? and VoiceOver navigation.
- Search for a command and a Help topic such as “backup”, “monospaced”, or “licence”. Open a result and check the current guide in Help Viewer. Repeat after moving or updating the app, including on macOS 11 and 12.
- Open Licence while offline and compare it with the original notice. Check scrolling and Light and Dark appearance. Open Release Notes and confirm that its version and GitHub tag match About, rather than whichever release is newest online.
- Check that AlphaSync on GitHub opens the repository in the default browser and Report Issue… opens GitHub’s new-issue form, with a report template and the app and system details. No text files or device identifiers should be included. Leave the report unsubmitted.
- Check that Contact Us… opens an unsent message to mike@koralatov.com in the default mail app, with the correct version in its subject. Cancel the message. If a handler is unavailable, check the native error alert and Copy Link button.

## Preferences

- Open Preferences, change the file filter, close the window, and reopen it. Confirm that the selected filter and main file list agree, including after restarting the app.
- Choose a different backup folder, and make a Quick Backup there. Reopen the chooser and cancel it; the selected folder should stay the same. Check a long folder path and its full-path tooltip.
- With macOS keyboard navigation enabled, use Tab, Shift-Tab, and Space to reach and operate the controls. Check the labels with VoiceOver and open Preferences Help using the help button.
- Confirm that **Save a backup log** is unticked until enabled, including after upgrading. Enable it, restart the app, and check that it stays enabled. Disable it again and confirm that the choice is saved. Check the new control and explanation in Light and Dark Mode.
- Check the grouped layout and readable status text in Light and Dark Mode on an older supported Mac. On macOS 11 and 12, the Login Items settings button should be absent.
- On a small screen, confirm that Preferences fits the visible screen and scrolls to every control. Repeat with long status text and macOS set to show scroll bars always. Check keyboard navigation and VoiceOver through the scrollable form.
- Check that recovery copies are enabled by default and retention starts at 30 days. Change both settings, restart, and confirm that they persist. Open Recovery Copies and confirm that Finder opens it within the selected backup folder.

## Launcher

Move the app to its final location before enabling automatic launching. On macOS 11 and 12, check enabling, disabling, logout and login, and reconnecting the Neo. An unknown saved registration state is expected when the older helper is not running.

On macOS 13 and later, check the approval-required state, the settings button, granting and revoking approval, and returning to Preferences. Confirm that registration failures show the system’s error instead of an approval message.

## Files and responsiveness

Keep known-good backups before testing writes to the Neo.

- Open the app without a Neo. Check the compact waiting window, native cable symbol, and USB instruction in Light and Dark Mode. Connect a Neo and confirm that the same window expands to the file viewer, initially 480 points wide. Disconnect and reconnect; a chosen file viewer size should be restored.
- With two Neos, disconnect one and confirm that the file viewer stays open. Disconnect the last one to return to the waiting window. Check a connection failure and confirm that its explanation is visible.
- Disconnect during a backup or file sheet. Read and dismiss the result before the parent shrinks. Repeat in full screen; the window should return to the compact size after leaving full screen. Check the animation with Reduce Motion enabled.
- In the file viewer, check readable filenames and sizes, toolbar buttons, and status bar. Widen and narrow the window; the Name column should take up the extra space while Size keeps its width.
- Check that Backup, Clear, and Info have matching native toolbar gaps, including after upgrading an unchanged toolbar from an older version. A deliberately customised toolbar should keep its layout. The available-memory count should stay at the right edge when resizing, and the progress spinner should appear beside the connection message during transfers.
- Check an empty file and files of 1, 999, 1,000, 1,024, and 12,000 bytes. The list, Inspector summary, device memory, and available-memory status should use bytes below 1 KB and decimal KB from 1 KB upwards. Compare with Finder and check the Mac’s regional number formatting in Light and Dark Mode.
- Check exact byte counts in file and applet details, including minimum and maximum file sizes, ROM, workspace RAM, and file RAM. Values such as 51,200 and 106,432 bytes should have grouping separators and fit their fields. Check singular ‘1 byte’, zero, an unavailable maximum, and the grouped byte limit in an oversized-file warning.
- Open the Inspector for a file, applet, and Neo. Preview and More Info should stay open with bold headings, native separators, and aligned detail rows. Check long names and copyright text, select and copy a detail value, and switch between Light and Dark Mode.
- Double-click a file’s name, icon, and Size cell. Each should open one separate read-only window, initially 640 × 480 points, containing the complete file. Double-clicking a device, applet, header, or empty space should not open a file. Confirm that Return still permits renaming in the main list and that Escape cancels it.
- In the file window, scroll and copy text with the Edit menu and keyboard shortcuts. Try typing, pasting, cutting, deleting, and dropping text; the contents should remain unchanged. Resize to the minimum size and enlarge it again; long lines should wrap without horizontal scrolling. Check Light, Dark, and Auto appearance.
- Switch between Regular and Monospaced. Both should use the system font and default size, retain the text and selection, and leave other open windows unchanged. New windows should remember the last choice, including after restarting AlphaSync. Close one file window and check that the app and other windows stay open.
- Open empty and long files, disconnect during a read, and close a loading window. Empty files should be identified, failed reads should explain the problem, and a closed window should stay closed when its read finishes. After a successful read, disconnect the Neo and check that the opened text can still be read and copied.
- Scroll through a long file preview and copy text from it. The preview should wrap and stay read-only. Change to an applet or Neo and check its icon preview. Clear the selection and select several items; previous details and preview text should disappear. Confirm that changing the selected item keeps the top of the Inspector in place and that closing and reopening it works.
- Open the Clear warning for a file and an applet, and the Replace warning by dropping a file. Each should be a native sheet attached to the main window. Cancel should be the default; Return, keypad Enter, and Escape should dismiss it without changing the Neo. With disposable files and known-good backups, confirm that deliberately choosing Replace, Clear File, or Clear All Files changes only the named contents.
- Select a file and check the **Clear File…** label, then select AlphaWord and check **Clear All Files…**. Each tooltip should name its target. Check that both labels fit the 480-point window in Light and Dark Mode, and that clearing remains disabled during transfers and for unsupported selections.
- Copy files in both directions, including pound signs, accented letters, and curly quotes.
- Import matching MacASCII, UTF-8, and UTF-16 files, including both UTF-16 byte orders with byte-order marks. Confirm that exported copies and backups use UTF-8 and preserve the text.
- Import the same paragraphs with LF, CRLF, and CR endings. Check for the same paragraph breaks.
- Import unsupported characters and oversized text. Confirm that an explanation appears and the existing device file is unchanged.
- Drop a 2 MB plain-text file onto AlphaWord and onto an existing file. Both should reject it with the Neo’s maximum, before changing any device file. Also test a file above the per-file limit that still fits in the available memory, and files exactly at and just above the converted-size limit.
- With little free memory, check that adding a file or growing an existing file reports insufficient space, while replacing a file with the same or a smaller allocation still works. Keep a known-good backup and use disposable files.
- If size or memory information cannot be read, check that the import is blocked with a reconnect instruction. An unknown AlphaWord maximum should appear as ‘unavailable’ in the Inspector. Confirm that the warnings and grouped byte counts remain readable in Light and Dark Mode.
- Export files and folders to Finder, and drop text files onto the Neo.
- Start a longer transfer and confirm that windows still repaint and respond. Disconnect and reconnect, and check that queued work for the old connection fails rather than reaching the replacement connection.

## Recovery and verification

- With recovery enabled, replace and clear disposable files. Confirm that each original is readable as UTF-8 under Recovery Copies before the operation completes. Restore a copy onto the matching Neo file and compare all text, including empty files, accents, pound signs, and paragraph breaks.
- Clear all files in a disposable AlphaWord test set. Check that the recovery folder contains every original, with no missing or truncated files. If the complete device file list cannot be read, the requested recovery must stop the clear.
- Use an unwritable backup destination or a full test volume. A requested recovery copy must block replacement or clearing, leave the Neo unchanged, and explain the failure. Check that incomplete copies keep their marker and that existing copies are preserved.
- On disposable recovery folders, test 7-, 30-, and 90-day expiry and keeping copies until removed. Only recognised expired complete recovery copies should move to Trash when a new copy is made. Incomplete folders, symlinks, and unrelated files must remain. Confirm that older copies can be recovered from Trash. Never adjust dates on the user’s real backups for this check.
- Turn the recovery option off deliberately and confirm that the next sheet reflects it. Re-enable it. Cancelled sheets must not save a changed preference or start a destructive operation.
- On real hardware, create, replace, and clear disposable files and confirm the final text on the Neo. Disconnect during a write or verification. Any failure after writing must say contents may have changed and include the recovery location when one was saved. Check that a failed rename is reported and the file list refreshes to the actual name.
- Check natural ordering of names such as File 1, File 2, and File 10. Connect a Neo containing several longer files and confirm that ordinary list refreshes no longer read every complete file. Opening a reader or a visible Inspector preview must still load the complete text.
- In a read-only file window, test Copy, Select All, Find, Find Next, Find Previous, and Use Selection for Find through both menus and shortcuts. Search and copying must leave the original text unchanged.

## Backups

- Back up named files, numbered file spaces, and empty files with logging off. Confirm that only the copied files and their applet folders appear in each dated destination, with no new logs or separate reports folder.
- Enable **Save a backup log** and repeat. Each Neo’s dated folder should contain **AlphaSync Backup Log.plist**, listing only its files, saved paths, errors, and final state. Repeat on the same day and confirm that each dated destination keeps its own log. Changing the option during a backup should affect the next backup.
- Check the completion sheet’s file count and dated folder path. Click **Open Backup Folder** and confirm that Finder opens that exact folder. **Done** should dismiss the sheet, including when Return is pressed.
- With two Neos, confirm that both dated locations are listed and **Open Backup Folders** opens both. Check long paths in Light and Dark Mode, copy a displayed path, and confirm that the text and buttons fit.
- Force a file failure and confirm that **Backup incomplete** shows saved and failed counts while still offering any folders that were created. A backup that created no folder should not offer a Finder button.
- Repeat into the same destination. Confirm that completed files are not overwritten.
- Choose an unwritable destination and confirm that copying stops with an explanation.
- With logging enabled, cancel between files, and disconnect between files. Check their distinct log states and the files already saved. With two Neos, finish the first and stop during the second; the first log should stay complete while the second records the interruption.
- With logs off and on, check that a dated backup starts with (Incomplete), and that only a successful Neo backup loses the suffix. Cancel, disconnect, and force-quit during disposable test backups. Their folders must remain marked incomplete, and any log must remain accurate. Check that version 2 relative log paths still locate the copied files after a successful folder rename. Inspect any hidden temporary files separately.
- Quit during a transfer. Confirm that the app remains responsive while the current work finishes and the device closes.

## Distribution

- Check Finder, the Dock, and About for each download. Universal should show the original green icon; the macOS 27 Apple Silicon build should show the preferred glass icon. Check small and large icon sizes in Light and Dark Mode.

Use the final download ZIP for a clean-install check on a second Mac. Record first-launch behaviour, opening every window, automatic launching, and a real transfer.
