# AlphaSync

AlphaSync copies text files between your Mac and an AlphaSmart Neo. It can also back up your Neo and open automatically when you connect it.

## Connection fixes in testing

A Neo can remain in keyboard mode with public version 2.0.4.  Unpublished 2.0.5 corrects the mode switch, USB buffers, and System applet query.  On 15 November 2026, the user reported that the private build 158 now works on the M2 Air; its screenshot confirms a connected file list.  The [USB comparison](docs/usb-parity-audit.md) and [build 158 record](releases/verification/2.0.5-158/verification.json) preserve the changes and passed checks.

Private **2.0.5, build 159** is ready to test the correction for sidebar and file rows hidden beneath the toolbar.  It also aligns Clear with its one-applet rule and preserves the working USB code. [Run 43718196869](https://github.com/koralatov/alphasync/actions/runs/43718196869) passed 157 Swift tests, all 55 fixtures, twenty browser layout observations per host, both app builds, and exact-package execution on Apple Silicon.  Independent hashes and Help checks passed.  The [layout investigation](docs/connected-layout.md) and [record](releases/verification/2.0.5-159/verification.json) explain the results and remaining physical checks toward stable **2.1 for Apple Silicon**.  After that release is verified and published, planned development will pause except for future macOS compatibility updates.  Only 1.5.1 and 2.0.4 are public.

Private **2.0.5, build 160** is ready for performance and correctness testing.  It reduces repeated list and preview work, bounds dictionary word buffers, and fixes explicit retry and late backup cancellation.  [Run 43725850279](https://github.com/koralatov/alphasync/actions/runs/43725850279) passed 170 Swift tests, all 55 fixtures, both host builds and native interfaces, and exact-package execution on Apple Silicon.  Independent hashes and Help checks passed.  See the [maintenance review](docs/maintenance-160.md) and [record](releases/verification/2.0.5-160/verification.json).  It adds no features and preserves the working USB packet handling and build 159’s layout.  Physical M2 Air checks remain required.

Private **2.0.5, build 161** is ready for testing with clearer Clear and Replace confirmations, distinct applet icons, a matching Neo heading, a green connection light, and labelled toolbar commands.  Choose **View → Toolbar Appearance** for Icon and Text, Icon Only, or Text Only.  Clear and Replace have no default button; Cancel has the initial keyboard focus, and Escape cancels.  **Save a copy of the text first** retains the existing recovery protection.  Both hosts passed 172 Swift tests, all 55 fixtures, native interfaces, and both editions in [run 43734374426](https://github.com/koralatov/alphasync/actions/runs/43734374426); both exact packaged apps ran on Apple Silicon.  Independent hashes, Help validation, and eighty-image review passed.  See the [interface review](docs/interface-polish-161.md) and [record](releases/verification/2.0.5-161/verification.json).  Physical M2 Air checks remain required.

Private **2.0.5, build 162** is ready for testing with a permanently visible sidebar, slightly indented child items, and a filled keyboard icon for the Neo.  It removes the Hide Sidebar control reported to freeze build 161.  The sidebar width remains adjustable.  Both pinned hosts passed 172 Swift tests, all 55 fixtures, thirty-two native window observations, and both editions in [run 43743043759](https://github.com/koralatov/alphasync/actions/runs/43743043759).  Both exact packaged apps ran on Apple Silicon.  Independent hashes, both Help books, and 92-image review passed.  See the [sidebar review](docs/sidebar-162.md) and [record](releases/verification/2.0.5-162/verification.json).  The old freeze was not reproduced on hosted macOS 15.8.2; confirmation on the affected M2 Air remains required.

Private **2.0.5, build 163** is ready for testing with Preview shown only for one selected file.  A Neo or applet keeps its header icon and More Information, without the redundant enlarged icon below.  Multiple selected files have no Preview section.  Both pinned hosts passed 172 Swift tests, all 55 fixtures, thirty-two native window observations, and both editions in [run 43756388436](https://github.com/koralatov/alphasync/actions/runs/43756388436).  Both exact packaged apps ran on Apple Silicon.  Independent hashes, both Help books, and 96-image review passed.  File reading and all earlier fixes are retained.  See the [Inspector review](docs/inspector-163.md) and [record](releases/verification/2.0.5-163/verification.json).  The user reports that build 162 appears to work; the remaining physical checks towards 2.1 continue separately.

Private **2.0.5, build 164** is being prepared with more consistent cancellation, clearer VoiceOver feedback, relevant menu commands, and reusable file-size formatting.  The five changes are in focused commits.  The [maintenance review](docs/maintenance-164.md) documents the full build milestone and remaining M2 Air checks before the decision on stable 2.1.

## Version 2.0.4

Version 2.0.4 improves the Swift rewrite first released as 2.0 and requires **macOS 13 or later**. It includes all changes prepared under the unpublished 2.0.1 development version.

Version 2.0.4, **build 154**, reviews and rewrites all built-in Help. The guide covers every function with short task pages, related links, and practical troubleshooting. It explains backup scope, selection, recovery, and safe stopping. The pages use scalable text and follow Light and Dark appearance.

Choose one download from the [2.0.4 release](https://github.com/koralatov/alphasync/releases/tag/v2.0.4):

- [**Universal**](https://github.com/koralatov/alphasync/releases/download/v2.0.4/AlphaSync-2.0.4-154-macOS-13-universal.zip): for Intel and Apple Silicon Macs.
- [**Apple Silicon**](https://github.com/koralatov/alphasync/releases/download/v2.0.4/AlphaSync-2.0.4-154-macOS-13-apple-silicon.zip): for Macs with an M-series chip.

Both offer the same file-transfer features. Install one edition. You can find your macOS version and chip in **Apple menu → About This Mac**.

Automatic opening recovers after temporary monitoring errors and sleep. Backup folders follow moves and renames, dictionary imports explain omitted words, and Quit stops read-only preparation while letting a committed change finish safely. See the [release notes](releases/2.0.4.md).

## macOS 11 and 12

[Download AlphaSync 1.5.1 for macOS 11 and 12](https://github.com/koralatov/alphasync/releases/download/v1.5.1/AlphaSync-1.5.1-147-macOS-11-12-universal.zip).

This is the final version for these systems, on Intel and Apple Silicon. Its [release page](https://github.com/koralatov/alphasync/releases/tag/v1.5.1), downloads, and [legacy source](https://github.com/koralatov/alphasync/tree/legacy-macos-11-12) are preserved. They remain separate from version 2.0.4.

## Install

1. Double-click the downloaded ZIP file to unpack it.
2. Quit AlphaSync if it is already running.
3. Drag **AlphaSync** into your **Applications** folder. Replace the older app when Finder asks.
4. Open **Applications**, then double-click **AlphaSync**.

If macOS blocks the app, follow [Apple’s instructions for opening a downloaded app](https://support.apple.com/en-gb/102445). On macOS 11 and 12, the approval is in **System Preferences → Security & Privacy → General**. On newer systems, look in **System Settings → Privacy & Security**.

## Use version 2.0.4

Connect your Neo with a USB cable. AlphaSync expands from its connection message to show your files. Choose an applet in the sidebar.

- **Read a file:** double-click it. Its separate window is read-only. Choose **Regular** or **Monospaced**, use **Copy to Clipboard** for the complete text, or use **Edit → Find** to search.
- **Save files to your Mac:** select them, then choose **File → Save to Mac…**, or drag their names into Finder.
- **Add text to your Neo:** choose an applet, clear the file selection, then choose **File → Import Text Files to Neo…**.
- **Replace a file:** select it, then import one text file, or drop a text file onto its name. Review the warning before continuing.
- **Back up your Neo:** click **Backup**. Choose the destination in **AlphaSync → Settings…**.
- **Clear files:** select the files for **Clear File…** or **Clear Selected Files…**. With an applet selected and no files selected, **Clear All Files…** clears that applet’s files.

Replacing and clearing files require confirmation. **Cancel** is the default and has initial keyboard focus. **Save a recovery copy first** is on by default. If that copy fails, the change stops.

In **Settings**, choose **Open Recovery Copies** to find the saved originals. Restore text by importing its saved `.txt` file onto the matching file on your Neo. Recovery copies also retain the original Neo data. Keep separate backups of important work.

Recovery copies are kept for 30 days by default. Settings offers 7, 30, or 90 days, or no automatic expiry. Expired recognised copies move to Trash when a new copy is made.

If text is too large, or contains a character your Neo cannot store, AlphaSync explains the problem and stops before changing the file. Shorten the text or replace the character, then try again.

Dictionary words must contain 2 to 20 characters. If some words fall outside that range, AlphaSync shows their count and examples before you choose whether to continue. A non-empty dictionary import with no usable words is rejected. Continuing a replacement still requires the normal Replace confirmation.

Backup logs are off unless you enable them in Settings. Each log stays inside its dated backup folder. An unfinished backup keeps **(Incomplete)** in its folder name. The result shows what was saved, its location, and a button to open the folder.

To open AlphaSync whenever you connect your Neo, enable automatic opening in Settings. Keep the app in Applications and follow any Login Items approval prompt.

AlphaSync follows your Mac’s Light or Dark appearance.

The downloads have ad hoc signatures and are not Apple-notarised. The [release notes](releases/2.0.4.md) describe the build checks and the remaining physical Neo, Login Items approval, and macOS 13 testing. Native Help Viewer and VoiceOver checks also remain unverified.

## Help and support

Choose **Help → AlphaSync Help** or press **⌘?** for the built-in guide. All eighteen pages work offline, including the original licence. Start with a task, or use the troubleshooting and support topics when something goes wrong. The Help menu also includes release notes, the licence, and links to GitHub and its issue tracker. **Contact Us…** opens an email to **mike@koralatov.com** in your usual mail app. It leaves sending the message to you.

## Advanced users

See the [technical guide](TECHNICAL.md) for building, testing, formats, and migration details. The [1.5.1 guide](https://github.com/koralatov/alphasync/blob/v1.5.1/README.md) describes the preserved older app.

## Licence

AlphaSync was originally written by tSoniq. Its original copyright notices and BSD-style licence remain in [LICENSE](LICENSE).
