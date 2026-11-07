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

## Launcher

Move the app to its final location before enabling automatic launching.  On macOS 11 and 12, check enabling, disabling, logout and login, and reconnecting the NEO.  An unknown saved registration state is expected when the older helper is not running.

On macOS 13 and later, check the approval-required state, the settings button, granting and revoking approval, and returning to Preferences.  Confirm that registration failures show the system’s error instead of an approval message.

## Files and responsiveness

Keep known-good backups before testing writes to the NEO.

- Copy files in both directions, including pound signs, accented letters, and curly quotes.
- Import matching MacASCII, UTF-8, and UTF-16 files, including both UTF-16 byte orders with byte-order marks.  Confirm that exported copies and backups use UTF-8 and preserve the text.
- Import the same paragraphs with LF, CRLF, and CR endings.  Check for the same paragraph breaks.
- Import unsupported characters and oversized text.  Confirm that an explanation appears and the existing device file is unchanged.
- Export files and folders to Finder, and drop text files onto the NEO.
- Start a longer transfer and confirm that windows still repaint and respond.  Disconnect and reconnect, and check that queued work for the old connection fails rather than reaching the replacement connection.

## Backups

- Back up named files, numbered file spaces, and empty files.  Open the report and check each saved path and the final state.
- Repeat into the same destination.  Confirm that completed files are not overwritten.
- Choose an unwritable destination and confirm that copying stops with an explanation.
- Cancel between files, and disconnect between files.  Check their distinct report states and the files already saved.
- On a disposable test backup, force-quit during a long export.  Check that its final filename does not identify a partial file and that the report remains unfinished.  Inspect any hidden temporary file separately.
- Quit during a transfer.  Confirm that the app remains responsive while the current work finishes and the device closes.

## Distribution

Use the final stapled ZIP for a clean-install check on a second Mac.  Record Gatekeeper behaviour, opening every window, automatic launching, and a real transfer.  Developer ID signing and notarisation require the release certificate and Keychain profile; ad hoc CI artifacts do not establish these results.
