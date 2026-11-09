# AlphaSync

AlphaSync copies text files between your Mac and an AlphaSmart Neo. It can also back up your Neo and open automatically when you connect it.

## Version 1.6

Version 1.6 is in development and requires **macOS 13 or later**. It has not been released yet.

There will be two downloads from the same release:

- **Universal:** for Intel and Apple Silicon Macs.
- **Apple Silicon:** for Macs with an M-series chip.

Both offer the same file-transfer features. Install one edition. You can find your macOS version and chip in **Apple menu → About This Mac**.

## macOS 11 and 12

[Download AlphaSync 1.5.1 for macOS 11 and 12](https://github.com/koralatov/alphasync/releases/download/v1.5.1/AlphaSync-1.5.1-147-macOS-11-12-universal.zip).

This is the final version for these systems, on Intel and Apple Silicon. Its [release page](https://github.com/koralatov/alphasync/releases/tag/v1.5.1), downloads, and [legacy source](https://github.com/koralatov/alphasync/tree/legacy-macos-11-12) are preserved. Development of 1.6 does not change them.

## Install

1. Double-click the downloaded ZIP file to unpack it.
2. Quit AlphaSync if it is already running.
3. Drag **AlphaSync** into your **Applications** folder. Replace the older app when Finder asks.
4. Open **Applications**, then double-click **AlphaSync**.

If macOS blocks the app, follow [Apple’s instructions for opening a downloaded app](https://support.apple.com/en-gb/102445). On macOS 11 and 12, the approval is in **System Preferences → Security & Privacy → General**. On newer systems, look in **System Settings → Privacy & Security**.

## Use version 1.6

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

Backup logs are off unless you enable them in Settings. Each log stays inside its dated backup folder. An unfinished backup keeps **(Incomplete)** in its folder name. The result shows what was saved, its location, and a button to open the folder.

To open AlphaSync whenever you connect your Neo, enable automatic opening in Settings. Keep the app in Applications and follow any Login Items approval prompt.

AlphaSync follows your Mac’s Light or Dark appearance.

## Help and support

Choose **Help → AlphaSync Help** or press **⌘?** for the built-in guide. The Help menu also includes release notes, the licence, and links to GitHub and its issue tracker. **Contact Us…** opens an email to **mike@koralatov.com** in your usual mail app. It leaves sending the message to you.

## Advanced users

See the [technical guide](TECHNICAL.md) for building, testing, formats, and migration details. The [1.5.1 guide](https://github.com/koralatov/alphasync/blob/v1.5.1/README.md) describes the preserved older app.

## Licence

AlphaSync was originally written by tSoniq. Its original copyright notices and BSD-style licence remain in [LICENSE](LICENSE).
