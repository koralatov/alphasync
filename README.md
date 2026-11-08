# AlphaSync

AlphaSync copies text files between your Mac and an AlphaSmart NEO.  It can also back up the files on your NEO and open automatically when you connect it.

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
3. Drag the **AlphaSync** app into your **Applications** folder.  If you are updating an older copy, replace it when Finder asks.
4. Open **Applications**, then double-click **AlphaSync**.

## If your Mac blocks AlphaSync

Your Mac may say that it cannot verify AlphaSync.  Dismiss the warning, then open the settings for your macOS version:

| macOS | Where to go |
|---|---|
| 11 and 12 | **System Preferences → Security & Privacy → General** |
| 13 and later | **System Settings → Privacy & Security**, then scroll to **Security** |

Find the message about AlphaSync and click **Open Anyway**.  If you see an **Open** button first, click it to reach **Open Anyway**.  Follow the prompts, using your Mac login password or Touch ID if asked.

Your Mac remembers that you allowed this copy of AlphaSync.  You can then open it by double-clicking it as usual.  Apple has [more help with opening downloaded apps](https://support.apple.com/en-gb/102445).

## Use AlphaSync

Open AlphaSync and connect your NEO with a USB cable.  Your NEO’s files appear in the window.

- **Copy files to your Mac:** drag them from AlphaSync into a Finder folder.
- **Copy text files to your NEO:** drag them from Finder into AlphaSync.
- **Back up your files:** click **Backup**.  You can choose where backups are saved in **Preferences**.
- **Clear files:** select a file for **Clear File…**, or select **AlphaWord** for **Clear All Files…**.  The warning names what will be cleared, and **Cancel** is the default.

Back up the files on your NEO before replacing or clearing them.

Backup logs are off by default.  If you want a record of copied files and any errors, enable **Save a backup log** in **Preferences**.  The log is saved inside each dated backup folder.

To have AlphaSync open whenever you connect your NEO, turn on automatic opening in **Preferences**.  Keep the app in Applications, and follow any approval prompts shown in Preferences.

AlphaSync follows your Mac’s Light or Dark appearance automatically.

## Advanced users

For development downloads, build instructions, tests, supported text formats, and implementation notes, see the [technical guide](TECHNICAL.md).

## Licence

AlphaSync was originally written by tSoniq.  The original copyright notices and BSD-style licence remain in [LICENSE](LICENSE) and the source files.
