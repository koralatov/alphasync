# AlphaSync

AlphaSync is a native Mac file manager for AlphaSmart NEO devices.  It copies text files in both directions, backs up named files and file spaces, and can open automatically when a NEO is connected.

Each release provides two downloads built from the same source and version:

| Download | Supported macOS | Processors |
|---|---|---|
| Universal | 11 through 26 | Intel and Apple Silicon |
| Modern | 27 and later | Apple Silicon |

## Download and run on a Mac

Choose **Universal** for macOS 11 through 26.  Choose **Modern** for macOS 27 and later on Apple Silicon.  You can check your macOS version and processor in **Apple menu → About This Mac**.

### Download

Published downloads appear on the [Releases page](https://github.com/koralatov/alphasync/releases).  For development downloads, see the [technical guide](TECHNICAL.md#development-downloads).

### Install and open

1. Quit any copy of AlphaSync that is already running.
2. Drag the extracted **AlphaSync.app** into **Applications**.  Both versions use the same preferences and bundle identifiers, so replace the existing app when changing versions.
3. Open **Applications**, then double-click **AlphaSync**.  If macOS blocks the first launch, follow the steps below.
4. Connect your NEO with a USB cable.  Its files appear in the main window.  Drag files to Finder to copy them to your Mac, or drag text files into AlphaSync to send them to the NEO.

Keep **AlphaSync.app** intact.  Its automatic-launch helper is already inside the app.  Move it to Applications before enabling automatic launching in Preferences.

### If macOS blocks the first launch

For an unidentified-developer or verification warning, dismiss the warning and open the settings for your macOS version:

| macOS | Settings |
|---|---|
| 11 and 12 | **System Preferences → Security & Privacy → General** |
| 13 and later | **System Settings → Privacy & Security**, then scroll to **Security** |

Find the message about AlphaSync and choose **Open Anyway**.  If an **Open** button appears first, click it to reach **Open Anyway**.  Follow the confirmation prompts, entering your Mac login password or using Touch ID if asked.

macOS saves an exception for this copy of the app.  Later launches can use the usual double-click.  Apple’s [instructions for opening downloaded apps](https://support.apple.com/en-gb/102445) explain this approval process.

## Technical guide

For development downloads, build instructions, tests, file formats, and implementation details, see the [technical guide](TECHNICAL.md).

## Licence

AlphaSync was originally written by tSoniq.  The original copyright notices and BSD-style licence remain in [LICENSE](LICENSE) and the source files.
