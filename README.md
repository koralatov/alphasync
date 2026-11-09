# AlphaSync

AlphaSync copies text files between your Mac and an AlphaSmart Neo. It can also back up the files on your Neo and open automatically when you connect it.

## Download

Open the [Releases page](https://github.com/koralatov/alphasync/releases) and choose the download for your Mac:

| Download | macOS version | Mac |
|---|---|---|
| Universal | 11 through 26 | Intel or Apple Silicon |
| Modern | 27 and later | Apple Silicon |

You can find your macOS version and your Mac’s chip or processor in **Apple menu → About This Mac**.

If the download you need is not available yet, see [development downloads](TECHNICAL.md#development-downloads).

## Install

1. Double-click the downloaded ZIP file to unpack it.
2. Quit AlphaSync if it is already running.
3. Drag the **AlphaSync** app into your **Applications** folder. If you are updating an older copy, replace it when Finder asks.
4. Open **Applications**, then double-click **AlphaSync**.

## If your Mac blocks AlphaSync

Your Mac may say that it cannot verify AlphaSync. Dismiss the warning, then open the settings for your macOS version:

| macOS | Where to go |
|---|---|
| 11 and 12 | **System Preferences → Security & Privacy → General** |
| 13 and later | **System Settings → Privacy & Security**, then scroll to **Security** |

Find the message about AlphaSync and click **Open Anyway**. If you see an **Open** button first, click it to reach **Open Anyway**. Follow the prompts, using your Mac login password or Touch ID if asked.

Your Mac remembers that you allowed this copy of AlphaSync. You can then open it by double-clicking it as usual. Apple has [more help with opening downloaded apps](https://support.apple.com/en-gb/102445).

## Use AlphaSync

Open AlphaSync and connect your Neo with a USB cable. Your Neo’s files appear in the window.

- **Read a file:** double-click it to open a read-only window. Use **Font** to choose **Regular** or **Monospaced**. Use **Edit → Copy**, **Select All**, or **Find → Find…** to work with the text.
- **Copy files to your Mac:** drag them from AlphaSync into a Finder folder.
- **Copy text files to your Neo:** drag them from Finder into AlphaSync.
- **Back up your files:** click **Backup**. You can choose where backups are saved in **Preferences**.
- **Clear files:** select a file for **Clear File…**, or select **AlphaWord** for **Clear All Files…**. The warning names what will be cleared, and **Cancel** is the default.

Replacing and clearing files show a warning attached to the main window. **Cancel** is the default. To proceed, click **Replace**, **Clear File**, or **Clear All Files**.

**Save a recovery copy first** is on by default. AlphaSync saves the original text before changing it. If the copy cannot be saved, the change stops. In **Preferences**, use **Open Recovery Copies** to find saved originals inside your backup folder. To restore one, drag its text file onto the matching file in AlphaSync.

Preferences lets you keep recovery copies for 7, 30, or 90 days, or until you remove them. The default is 30 days. Expired copies move to Trash when a new recovery copy is made. You can turn recovery copies off in Preferences or in a warning. Keep separate backups of important files.

If a text file is too large for your Neo, AlphaSync explains the limit and leaves your files unchanged. Shorten the text or split it into smaller files, then try again.

Backup logs are off by default. If you want a record of copied files and any errors, enable **Save a backup log** in **Preferences**. The log is saved inside each dated backup folder.

A backup folder ends in **(Incomplete)** until that Neo’s backup finishes successfully. If you stop a backup or a file cannot be copied, the folder keeps this label. The result shows the location and offers a button to open it in Finder.

To have AlphaSync open whenever you connect your Neo, turn on automatic opening in **Preferences**. Keep the app in Applications, and follow any approval prompts shown in Preferences.

AlphaSync follows your Mac’s Light or Dark appearance automatically.

## Help and support

Choose **Help → AlphaSync Help** or press **⌘?** for the built-in guide.
The Help menu also includes the licence, release notes for your version, and a link to the GitHub project. Choose **Report Issue…** to report a problem on GitHub.
Choose **Contact Us…** to open an email addressed to **mike@koralatov.com** in your usual mail app.

## Advanced users

For development downloads, build instructions, tests, supported text formats, and implementation notes, see the [technical guide](TECHNICAL.md).

## Licence

AlphaSync was originally written by tSoniq. The original copyright notices and BSD-style licence remain in [LICENSE](LICENSE) and the source files.
