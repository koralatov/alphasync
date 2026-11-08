# Manual release checks

Record the exact app version, build number, source commit, macOS version, architecture, NEO model, result, and any failure.  A deployment target check establishes how the executable was built; runtime and USB checks need the actual system and device.

## Systems

| System | Check | Manual result |
|---|---|---|
| macOS 11, Intel | Minimum runtime and older login-item API | Not run |
| macOS 11, Apple Silicon | Minimum runtime and older login-item API | Not run |
| macOS 12.7.5 | Available older Mac and older login-item API | Not run |
| macOS 13 or later | Launcher registration, approval, and settings changes | Not run |
| macOS 26, Intel and Apple Silicon | Universal app, real USB transfers on both architectures | Not run |
| macOS 27 or later, Apple Silicon | Modern app, real USB transfers, and launcher approval | Not run |

macOS 12.7.5 provides a useful older-system check.  Passing there does not establish a result for macOS 11.  The automated macOS 15 and 26 builds also do not fill either macOS 11 row.

Record the host with `sw_vers` and `uname -m`.  If Xcode tools are installed, run `scripts/verify-app.sh /Applications/AlphaSync.app` to check both architectures, deployment targets, versions, dependencies, signatures, and window loading on that host.

With the app running, change macOS Appearance between Light, Dark, and Auto in System Settings (System Preferences on macOS 11 and 12).  Check the main list, selected and unselected rows, toolbar, Inspector previews and details, Preferences, backup sheet, alerts, file panels, and Apple Help Viewer.  Check Increase Contrast and a different accent colour too.  The app should update without restarting.  Confirm that file renaming still accepts Return, cancels with Escape, and is unavailable during a transfer.  `scripts/check-appearance.sh /Applications/AlphaSync.app build/appearance` provides automated appearance checks and screenshots without using a NEO; the system-setting and hardware checks still need a person.

For the modern app, run `scripts/verify-app.sh /Applications/AlphaSync.app modern` on macOS 27 or later.  This requires exactly `arm64` in both the app and launcher, with a macOS 27 minimum.  Verify that the release contains both downloads with matching versions and source commits, and install only the app appropriate for the test Mac.

## Preferences

- Open Preferences, change the file filter, close the window, and reopen it.  Confirm that the selected filter and main file list agree, including after restarting the app.
- Choose a different backup folder, and make a Quick Backup there.  Reopen the chooser and cancel it; the selected folder should stay the same.  Check a long folder path and its full-path tooltip.
- With macOS keyboard navigation enabled, use Tab, Shift-Tab, and Space to reach and operate the controls.  Check the labels with VoiceOver and open Preferences Help using the help button.
- Confirm that **Save a backup log** is unticked until enabled, including after upgrading.  Enable it, restart the app, and check that it stays enabled.  Disable it again and confirm that the choice is saved.  Check the new control and explanation in Light and Dark Mode.
- Check the grouped layout and readable status text in Light and Dark Mode on an older supported Mac.  On macOS 11 and 12, the Login Items settings button should be absent.

## Launcher

Move the app to its final location before enabling automatic launching.  On macOS 11 and 12, check enabling, disabling, logout and login, and reconnecting the NEO.  An unknown saved registration state is expected when the older helper is not running.

On macOS 13 and later, check the approval-required state, the settings button, granting and revoking approval, and returning to Preferences.  Confirm that registration failures show the system’s error instead of an approval message.

## Files and responsiveness

Keep known-good backups before testing writes to the NEO.

- Open the app without a NEO.  Check the compact waiting window, native cable symbol, and USB instruction in Light and Dark Mode.  Connect a NEO and confirm that the same window expands to the file viewer, initially 480 points wide.  Disconnect and reconnect; a chosen file viewer size should be restored.
- With two NEOs, disconnect one and confirm that the file viewer stays open.  Disconnect the last one to return to the waiting window.  Check a connection failure and confirm that its explanation is visible.
- Disconnect during a backup or file sheet.  Read and dismiss the result before the parent shrinks.  Repeat in full screen; the window should return to the compact size after leaving full screen.  Check the animation with Reduce Motion enabled.
- In the file viewer, check readable filenames and sizes, toolbar buttons, and status bar.  Widen and narrow the window; the Name column should take up the extra space while Size keeps its width.
- Check an empty file and files of 1, 999, 1,000, 1,024, and 12,000 bytes.  The list, Inspector summary, device memory, and available-memory status should use bytes below 1 KB and decimal KB from 1 KB upwards.  Compare with Finder and check the Mac’s regional number formatting in Light and Dark Mode.
- Check exact byte counts in file and applet details, including minimum and maximum file sizes, ROM, workspace RAM, and file RAM.  Values such as 51,200 and 106,432 bytes should have grouping separators and fit their fields.  Check singular ‘1 byte’, zero, the ‘unlimited’ maximum, and the grouped byte limit in an oversized-file warning.
- Open the Clear warning for a file and an applet.  Cancel should be the default; Return, keypad Enter, and Escape should dismiss the warning without clearing anything.  With a disposable file and a known-good backup, confirm that deliberately choosing OK still clears only the indicated contents.
- Select a file and check the **Clear File…** label, then select AlphaWord and check **Clear All Files…**.  Each tooltip should name its target.  Check that both labels fit the 480-point window in Light and Dark Mode, and that clearing remains disabled during transfers and for unsupported selections.
- Copy files in both directions, including pound signs, accented letters, and curly quotes.
- Import matching MacASCII, UTF-8, and UTF-16 files, including both UTF-16 byte orders with byte-order marks.  Confirm that exported copies and backups use UTF-8 and preserve the text.
- Import the same paragraphs with LF, CRLF, and CR endings.  Check for the same paragraph breaks.
- Import unsupported characters and oversized text.  Confirm that an explanation appears and the existing device file is unchanged.
- Export files and folders to Finder, and drop text files onto the NEO.
- Start a longer transfer and confirm that windows still repaint and respond.  Disconnect and reconnect, and check that queued work for the old connection fails rather than reaching the replacement connection.

## Backups

- Back up named files, numbered file spaces, and empty files with logging off.  Confirm that only the copied files and their applet folders appear in each dated destination, with no new logs or separate reports folder.
- Enable **Save a backup log** and repeat.  Each NEO’s dated folder should contain **AlphaSync Backup Log.plist**, listing only its files, saved paths, errors, and final state.  Repeat on the same day and confirm that each dated destination keeps its own log.  Changing the option during a backup should affect the next backup.
- Check the completion sheet’s file count and dated folder path.  Click **Open Backup Folder** and confirm that Finder opens that exact folder.  **Done** should dismiss the sheet, including when Return is pressed.
- With two NEOs, confirm that both dated locations are listed and **Open Backup Folders** opens both.  Check long paths in Light and Dark Mode, copy a displayed path, and confirm that the text and buttons fit.
- Force a file failure and confirm that **Backup incomplete** shows saved and failed counts while still offering any folders that were created.  A backup that created no folder should not offer a Finder button.
- Repeat into the same destination.  Confirm that completed files are not overwritten.
- Choose an unwritable destination and confirm that copying stops with an explanation.
- With logging enabled, cancel between files, and disconnect between files.  Check their distinct log states and the files already saved.  With two NEOs, finish the first and stop during the second; the first log should stay complete while the second records the interruption.
- On a disposable test backup with logging enabled, force-quit during a long export.  Check that its final filename does not identify a partial file and that the log remains unfinished.  Inspect any hidden temporary file separately.
- Quit during a transfer.  Confirm that the app remains responsive while the current work finishes and the device closes.

## Distribution

- Check Finder, the Dock, and About for each download.  Universal should show the original green icon; the macOS 27 Apple Silicon build should show the preferred glass icon.  Check small and large icon sizes in Light and Dark Mode.

Use the final stapled ZIP for a clean-install check on a second Mac.  Record Gatekeeper behaviour, opening every window, automatic launching, and a real transfer.  Developer ID signing and notarisation require the release certificate and Keychain profile; ad hoc CI artifacts do not establish these results.
