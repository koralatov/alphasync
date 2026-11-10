# AlphaSync 2.0.2

AlphaSync is a free Mac app for reading, copying, and backing up files from an **AlphaSmart Neo** writing device. Connect your Neo with a USB cable to read your writing, save it on your Mac, or send text back to the Neo.

**Version 2.0.2, build 152, requires macOS 13 Ventura or later.** For macOS 11 Big Sur or macOS 12 Monterey, use [AlphaSync 1.5.1](https://github.com/koralatov/alphasync/releases/tag/v1.5.1). Both versions support Intel and Apple Silicon Macs on their supported systems.

AlphaSync was originally written by tSoniq. Version 2.0 was the first public release of the Swift rewrite. This release improves its reliability and includes the work prepared under version 2.0.1, which was never published.

This is the final maintenance reissue of 2.0.2. Build 152 fixes release publication and preserves the verification records. Its file-transfer features match build 151.

## What it does

- **Read your files.** Open a file in a separate, read-only window, search it, and copy its complete text to the clipboard.
- **Copy text in either direction.** Save files to your Mac, add text to the Neo, or replace an existing file after confirmation.
- **Back up your writing.** Save files in dated folders and see which files finished and where they were saved.
- **Keep recovery copies.** Save the original text and original Neo data before replacing or clearing a file. A requested change stops if its recovery copy fails.
- **Open automatically.** Enable automatic opening in Settings to start AlphaSync when a Neo is connected.

## What is different from 2.0

**Automatic opening is more reliable.** Your choice is saved before macOS starts the helper. A failed app opening gets up to three attempts. Connection monitoring can recover after temporary errors, and the app and helper start a fresh observer when the Mac wakes.

**Backups stop sooner.** Stop and Quit can interrupt a backup between blocks of the file being read. Files already saved are kept, and unfinished folders retain their **(Incomplete)** marker.

**Saved destinations follow moves and renames.** AlphaSync remembers the selected folder itself. It also records the first default destination before using it. If a saved destination becomes unavailable, reconnect its drive or choose the folder again in Settings.

**Connection problems stay visible.** A problem with one Neo remains visible while another Neo is connected. The warning and Try Again have their own row above the file table, leaving its headings and files clear.

**Dictionary imports explain omitted words.** Words must contain 2 to 20 characters. If some cannot be used, AlphaSync shows a count and examples before you choose whether to continue. A non-empty source with no usable words is rejected. Editing the source requires a fresh review if it still contains unusable words. Resuming a batch keeps earlier verified additions without importing them twice.

**Closing and quitting behave more predictably.** Closing a reader cancels its initial read or retry. Quit stops read-only preparation for Replace and Clear. A change that has begun writing finishes writing and verification before USB closes.

## How to download it

Check your macOS version and chip in **Apple menu → About This Mac**, then choose one download:

| Download | Which Mac? |
| --- | --- |
| [**Universal**](https://github.com/koralatov/alphasync/releases/download/v2.0.2-build.152/AlphaSync-2.0.2-152-macOS-13-universal.zip) | Intel or Apple Silicon, running macOS 13 or later. Choose this if you are unsure. |
| [**Apple Silicon**](https://github.com/koralatov/alphasync/releases/download/v2.0.2-build.152/AlphaSync-2.0.2-152-macOS-13-apple-silicon.zip) | An M-series Mac running macOS 13 or later. |

Both editions offer the same features. The Universal edition uses the original icon; the Apple Silicon edition uses the newer icon. Install one edition. Each ZIP includes **AlphaSync.app** and its matching automatic-launch helper. The separate **symbols** ZIPs are for developers investigating crashes.

## How to install it

1. Double-click the downloaded ZIP file to unpack it.
2. Quit an older copy of AlphaSync if it is running.
3. Drag **AlphaSync** into your **Applications** folder. Replace the older copy if Finder asks.
4. Open **Applications**, then double-click **AlphaSync**.

These downloads have ad hoc signatures and are not Apple-notarised. If macOS blocks the first opening, follow [Apple’s instructions for opening a downloaded app](https://support.apple.com/en-gb/102445). The approval is in **System Settings → Privacy & Security**. Use it only for the copy downloaded from this release.

Check automatic opening again in **AlphaSync → Settings…** after upgrading. Keep the app and its bundled helper together, and follow any Login Items approval prompt.

## How to use it

Open AlphaSync and connect your Neo with a USB cable. Choose the Neo or an applet in the sidebar. If a connection fails, read its message and choose **Try Again** or **Refresh**.

- **Read:** double-click a file. Choose Regular or Monospaced, use **Copy to Clipboard**, or search through **Edit → Find**.
- **Save to your Mac:** select files and choose **File → Save to Mac…**, or drag their names into Finder. Existing Mac files are kept, and another copy gets a different name.
- **Add text:** choose AlphaWord or the user dictionary, clear the file selection, and choose **File → Import Text Files to Neo…**.
- **Replace text:** select one file and import one text file, or drop it onto the file’s name. Review the named target before continuing.
- **Back up:** click **Backup**. Choose the destination and optional backup log in Settings. Stop keeps files that have already been saved.
- **Clear:** select files for **Clear File…** or **Clear Selected Files…**. With an applet selected and no files selected, **Clear All Files…** clears that applet’s files. Cancel is the default in destructive warnings.

**Save a recovery copy first** is on by default. Choose **Open Recovery Copies** in Settings to find the saved originals. Restore text by importing the saved `.txt` file onto the matching Neo file. Keep its accompanying `.neo` file for recovery or diagnosis; it is not a text import.

Recovery copies are kept for 30 days by default. Settings also offers 7 or 90 days, or no automatic expiry. Expired recognised recovery copies move to Trash when a new copy is made. Keep a separate backup of important writing.

AlphaWord and user dictionary files can be imported and changed. Other applet files can be read, exported, and backed up as XML. For the built-in guide, choose **Help → AlphaSync Help** or press **⌘?**.

Physical Neo transfers, real Login Items approval, and macOS 13 runtime checks remain unverified for this release. The build checks described below cover compilation, simulated transfers, native interfaces, and the packaged apps.

---

## Technical information

### Fixes since 2.0

- **Login-item intent:** save the requested setting before `SMAppService.register()`. Restore it on registration failure, retain it while approval is required, and refresh the actual status when Settings becomes active. ServiceManagement owns the helper’s lifetime; a delayed cross-process preference read cannot make it quit.
- **App-opening retries:** a pure state machine retains pending attachments after failures, uses one- and two-second delays, and limits an app-opening burst to three attempts. Detachment removes pending work. A successful opening or an already running app consumes an attachment.
- **Native attachment events:** IOKit matching and termination notifications replace the two-second polling loop. Observers provide an initial event, coalesce changes, and release ports and iterators on cancellation. Discovery waits for transfers and confirmations to finish.
- **Observer recovery:** the shared watcher retries failures after one and two seconds, then waits thirty seconds before a fresh burst. A minute of healthy monitoring resets its failure history. Wake notifications come from `NSWorkspace.shared.notificationCenter`; wake and explicit retry replace the observer safely. Healthy monitoring has no polling timer.
- **Cancellation before changes:** stop requests reach original-file preparation and the protocol engine’s final original check. Recovery preparation and expiry also check cancellation. Once a change crosses the device-write boundary, writing and read-back verification finish without cancellation between files in that committed change.
- **Orderly shutdown:** the main actor tracks active operations and readers. Checked continuations wait for their completion without a polling sleep. Cancelling a Quit waiter cannot abandon a committed change or turn its wait into a busy loop.
- **Reader lifetime:** initial loading and retry use the same SwiftUI task with a request-and-retry identity. Closing the reader cancels either kind of read. Cancelled results cannot update its displayed text.
- **Backup destinations:** Foundation bookmarks follow moved or renamed folders. First use creates and bookmarks the default destination before writing. Opening the app or Settings does not create it. Failed bookmark resolution stops backups and requested recovery copies without recreating the saved path.
- **Dictionary review:** conversion returns accepted and omitted counts with bounded examples. Consent applies to the exact decoded text. Non-empty sources with no valid words are rejected, and resumed batches preserve earlier verified additions. The wire format is unchanged.
- **Visible connection errors:** warnings and status occupy separate rows outside the native split view. Browser drawing is clipped to its allocated row. Native checks compare rendered pixels and verify the table’s position.

**Build 152 maintenance:** draft creation uses the releases API response and its returned release ID. It no longer depends on a newly created draft appearing immediately in a release list. Exact source, tag, and asset verification still precede publication.

Compact verification results, asset manifests, public notes, and retirement metadata are retained in the [source repository](https://github.com/koralatov/alphasync/tree/master/releases/verification). Full workflow logs and interface captures keep their normal Actions retention.

The app version stays 2.0.2 and the build becomes 152. GitHub prevents reuse of the earlier immutable `v2.0.2` tag, so this reissue uses `v2.0.2-build.152`. Help and licence links use that exact tag. The earlier build 151 listing is retired only after this build and its public downloads are verified; its source tag is preserved.

### Architecture and formats

Compared with [tSoniq’s 1.3 release](https://github.com/tSoniq/alphasync/releases/tag/RELEASE_1_3), this version retains drag-and-drop transfers, backups, text conversion, and automatic opening while replacing the Objective-C implementation with Swift, updating the native interface, supporting Intel and Apple Silicon, and carrying forward the file-protection work from the 1.5 series. The original BSD-style licence and copyright notices remain.

Both app targets and helpers use version 2.0.2, build 152, with a 13.0 deployment target. Universal contains x86_64 and arm64; Apple Silicon contains arm64 only. The shared Swift package contains `AlphaSyncCore`, `AlphaSyncHardware`, and `AlphaSyncUI`, with Swift 6 strict concurrency checking and no third-party runtime dependencies.

Public IOUSBHost bulk pipes carry file transfers. HID output reports switch the Neo into transfer mode; the helper reads attachment metadata only. USB handles and protocol state stay on one serial executor, and connection generations protect requests after reconnection.

Exports and backups use UTF-8 without a byte-order mark, with LF line endings. Imports accept strict UTF-8, BOM-marked UTF-16 in either byte order, and MacASCII (Mac Roman). Unsupported characters, overlong names, invalid limits, and insufficient memory are rejected before writing. Recovery copies retain readable text and exact original `.neo` bytes. Recovery metadata is version 2; optional backup logs are version 3.

### Install and build

Use one complete app bundle in Applications. The helper stays in `Contents/Library/LoginItems`. Both editions share the existing bundle identifiers, so do not install them as separate active copies. Existing preferences are retained.

Canonical builds use Xcode 26.6, pinned in `.xcode-version`. Intel checks use Xcode 16.4. Run `python3 scripts/generate-project.py`, then use the `AlphaSyncUniversal` or `AlphaSyncAppleSilicon` scheme in `AlphaSync/AlphaSync.xcodeproj`. The [technical guide](https://github.com/koralatov/alphasync/blob/v2.0.2-build.152/TECHNICAL.md) gives full commands.

### Verification and publication

The release workflow requires successful Intel and Apple Silicon jobs before publication. It runs core and simulated-device regressions, native observer and interface checks, and disposable packaging, publication, and retirement fixtures. It builds apps and helpers, checks architectures, minimum deployment targets, ad hoc signatures, hardened runtime, and matching crash symbols, then collects twelve assets from both editions.

Publication downloads those exact artifacts again and checks the extracted bundles, symbols, reports, and hashes. It uploads to a draft and verifies every uploaded asset’s size and SHA-256 digest before publishing. Interrupted uploads can resume a matching draft. An already published release is accepted only when its exact source, tag, and all asset hashes match; it is never changed by that check.

Each ZIP has a `.sha256` file and a build-information report recording its source commit. For example, check the Universal download with:

```sh
shasum -a 256 -c AlphaSync-2.0.2-152-macOS-13-universal.zip.sha256
```

After verification, the reviewed retirement plan removes superseded release listings while preserving their Git tags and source history. The supported public releases are **1.5.1 for macOS 11 and 12** and **2.0.2 for macOS 13 and later**. Version 1.5.1’s original source, assets, and legacy branch remain unchanged. The publication record retains the retired listings’ notes, identifiers, and asset hashes.

[Build and verification record](https://github.com/koralatov/alphasync/actions/runs/42816587995).
