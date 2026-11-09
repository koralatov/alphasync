# AlphaSync

AlphaSync copies text files between your Mac and an AlphaSmart Neo. It can also back up the files on your Neo and open automatically when you connect it.

## Download

[Download AlphaSync 1.5.1 for macOS 11 and 12](https://github.com/koralatov/alphasync/releases/download/v1.5.1/AlphaSync-1.5.1-147-macOS-11-12-universal.zip).

This is the final version for macOS 11 Big Sur and macOS 12 Monterey. The same download works on Intel and Apple Silicon Macs. No version for newer macOS systems is included in this release.

You can find your macOS version in **Apple menu → About This Mac**. Keep using 1.5.1 on macOS 11 or 12; version 1.6 and later will require a newer system.

The [1.5.1 release page](https://github.com/koralatov/alphasync/releases/tag/v1.5.1) keeps the download and release notes available. Its [legacy source branch](https://github.com/koralatov/alphasync/tree/legacy-macos-11-12) is preserved separately from ongoing development.

## Install

1. Double-click the downloaded ZIP file to unpack it.
2. Quit AlphaSync if it is already running.
3. Drag the **AlphaSync** app into your **Applications** folder. If you are updating an older copy, replace it when Finder asks.
4. Open **Applications**, then double-click **AlphaSync**.

## If your Mac blocks AlphaSync

Your Mac may say that it cannot verify AlphaSync. Dismiss the warning, then open **System Preferences → Security & Privacy → General**.

Find the message about AlphaSync and click **Open Anyway**. If you see an **Open** button first, click it to reach **Open Anyway**. Follow the prompts, using your Mac login password or Touch ID if asked.

Your Mac remembers that you allowed this copy of AlphaSync. You can then open it by double-clicking it as usual. Apple has [more help with opening downloaded apps](https://support.apple.com/en-gb/102445).

## Use AlphaSync

Open AlphaSync and connect your Neo with a USB cable. Your Neo’s files appear in the window.

- **Read a file:** double-click it to open a read-only window. Use **Font** to choose **Regular** or **Monospaced**. Click **Copy to Clipboard** to copy the complete text. Use **Edit → Copy** for a selection or **Find → Find…** to search.
- **Copy files to your Mac:** drag them from AlphaSync into a Finder folder.
- **Copy text files to your Neo:** drag them from Finder into AlphaSync.
- **Back up your files:** click **Backup**. You can choose where backups are saved in **Preferences**.
- **Clear files:** select a file for **Clear File…**, or select **AlphaWord** for **Clear All Files…**. The warning names what will be cleared, and **Cancel** is the default.

Replacing and clearing files show a warning attached to the main window. **Cancel** is the default. To proceed, click **Replace**, **Clear File**, or **Clear All Files**.

**Save a recovery copy first** is on by default. AlphaSync saves the original text before changing it. If the copy cannot be saved, the change stops. In **Preferences**, use **Open Recovery Copies** to find saved originals inside your backup folder. To restore one, drag its text file onto the matching file in AlphaSync.

Preferences lets you keep recovery copies for 7, 30, or 90 days, or until you remove them. The default is 30 days. Expired copies move to Trash when a new recovery copy is made. You can turn recovery copies off in Preferences or in a warning. Keep separate backups of important files.

If a text file is too large for your Neo, AlphaSync explains the limit and leaves your files unchanged. Shorten the text or split it into smaller files, then try again.

Backup logs are off by default. If you want a record of copied files and any errors, enable **Save a backup log** in **Preferences**. The log is saved inside each dated backup folder.

If AlphaSync cannot read the complete file list, it stops the backup and asks you to reconnect your Neo. It will not label a partial list as a complete backup.

A backup folder ends in **(Incomplete)** until that Neo’s backup finishes successfully. If you stop a backup or a file cannot be copied, the folder keeps this label. The result shows the location and offers a button to open it in Finder.

To have AlphaSync open whenever you connect your Neo, turn on automatic opening in **Preferences**. Keep the app in Applications, and follow any approval prompts shown in Preferences.

AlphaSync follows your Mac’s Light or Dark appearance automatically.

## Help and support

Choose **Help → AlphaSync Help** or press **⌘?** for the built-in guide.
The Help menu also includes the licence, release notes for your version, and a link to the GitHub project. Choose **Report Issue…** to report a problem on GitHub.
Choose **Contact Us…** to open an email addressed to **mike@koralatov.com** in your usual mail app.

## Advanced users

For the preserved source, build instructions, tests, supported text formats, and implementation notes, see the [technical guide](TECHNICAL.md).

## Licence

AlphaSync was originally written by tSoniq. The original copyright notices and BSD-style licence remain in [LICENSE](LICENSE) and the source files.
