# Technical guide

Build, test, and implementation details for developers and advanced users. For installation and everyday use, see the [README](README.md).

## Supported builds

Each release provides two downloads built from the same source and version:

| Download | Supported macOS | Processors |
|---|---|---|
| Universal | 11 through 26 | Intel and Apple Silicon |
| Modern | 27 and later | Apple Silicon |

Both include the matching bundled launcher and use Apple’s public frameworks and the standard C++ library. There are no third-party runtime libraries, package managers, or separately installed USB drivers. Deployment targets set the minimum system; the download labels describe the supported range.

## Development downloads

GitHub Actions provides development downloads. To get one:

1. Sign in to GitHub and open the repository’s [Actions page](https://github.com/koralatov/alphasync/actions).
2. Choose a successful **Build and test** run for the branch or commit you want.
3. In **Artifacts**, download `AlphaSync-release-<source commit>`. It contains both app downloads, their checksums, and build information.
4. Double-click the downloaded archive to extract it, then double-click the **Universal** or **Modern** app ZIP for your Mac.

See GitHub’s [artifact download instructions](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts) if you need help finding the download.

## Build

The universal build uses the Xcode version in [.xcode-version](.xcode-version), currently **26.6**. The modern build uses [.xcode-version-modern](.xcode-version-modern), currently **27.1**. CI also checks the universal app with **Xcode 16.4**.

Install Xcode and its command-line tools, open `AlphaSync/AlphaSync.xcodeproj`, and select the shared **AlphaSync** or **AlphaSync-Modern** scheme. The schemes share their sources and version settings. The modern scheme uses `DebugModern` and `ReleaseModern`, and builds only `arm64` in both the app and launcher.

From the repository root:

```sh
xcodebuild -project AlphaSync/AlphaSync.xcodeproj \
  -scheme AlphaSync -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData build
```

The universal result is `build/DerivedData/Build/Products/Release/AlphaSync.app`.

For the modern app:

```sh
xcodebuild -project AlphaSync/AlphaSync.xcodeproj \
  -scheme AlphaSync-Modern -configuration ReleaseModern \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build/ModernData build
```

The modern result is `build/ModernData/Build/Products/ReleaseModern/AlphaSync.app`. Launch it on macOS 27 or later. Keep either app bundle intact, including `Contents/Library/LoginItems/AlphaSyncLauncher.app`.

Newer Xcode releases can raise their minimum supported deployment target. Check [Apple’s Xcode requirements](https://developer.apple.com/xcode/system-requirements) before changing the toolchain, and keep the macOS 11 checks passing.

### Testing on macOS 12.7.5

macOS 12.7.5 is within the app’s intended runtime range. Use a universal development build from a successful workflow run to test it without installing the release compiler. Apple’s [Xcode 14.2 requirements](https://developer.apple.com/documentation/xcode-release-notes/xcode-14_2-release-notes) allow that version to run on Monterey 12.5 and later, although it is not part of this project’s CI matrix. Xcode 26.6 needs a newer release Mac.

Testing on 12.7.5 exercises the older login-item implementation shared with macOS 11. Runtime behaviour on macOS 11 still needs a separate check. The approval flow on macOS 13 and later also needs its own test. Record these results with the [manual test checklist](tests/manual-checks.md).

## Check a build

The core tests need a C++17 compiler and make. They run on macOS and Linux, without a connected Neo:

```sh
make test
make sanitize
python3 tests/release-tests.py
```

They cover text conversion, Windows line endings, unsupported characters, dictionary imports, both UTF-16 byte orders, malformed files, settings boundaries, failed buffer operations, and simulated USB replies. Invalid-reply tests produce expected error messages before the final success message.

On macOS, `make test` also checks exported XML with Foundation’s parser, exclusive file publication, interrupted backup reports, and background queue ordering and responsiveness. Native filesystem tests check UTF-8 export bytes for every saved encoding preference, plus MacASCII, UTF-8, and UTF-16 imports. Older backups without a root element remain readable by AlphaSync.

On a Mac, verify the built app with:

```sh
scripts/verify-app.sh
```

For the modern build, run on macOS 27 or later:

```sh
scripts/verify-app.sh build/ModernData/Build/Products/ReleaseModern/AlphaSync.app modern
```

This checks the exact architectures, executable deployment targets, system-only dependencies, matching app and helper versions, nested signatures, and every interface window. It first starts the shipping executable with `--version`, then builds a separate native interface-check host from the real application classes and the exact bundle resources being verified. Hardware detection and login-item changes are disabled at compile time in that host. Its code is cached within the build job, but its resources are refreshed for each app or archive. The harness in `tests/interface-checks.m` is never compiled into the shipping app.

An alternative app path can be passed as the first argument. An explicit `--skip-launch` third argument permits binary inspection on an older host; it does not establish runtime compatibility.

The interface uses standard AppKit controls and follows the macOS appearance automatically, including changes while the app is running. Toolbar symbols, file rows, the Inspector, About, and Apple Help use system styling and adaptive colours. To check both appearances and save screenshots of each window and Help page on a Mac, run:

```sh
scripts/check-appearance.sh build/DerivedData/Build/Products/Release/AlphaSync.app build/appearance
```

This check uses cached sample rows without connecting to a Neo or changing login items. It checks native row components, rename permissions and cancellation, text contrast, appearance inheritance, and switching from Light to Dark and back to Light. Help pages are rendered with the system WebKit. CI retains the screenshots separately from the app downloads.

The file list, Inspector summaries, device memory, and available-memory status share `NSByteCountFormatter` in file style, using bytes below 1,000 and decimal KB from 1,000 upwards. Exact byte counts in the Inspector and file-size warning use `NSNumberFormatter` with grouping separators, for example `51,200 bytes`. Both formatters follow the Mac’s regional settings. Appearance captures include compact sizes and grouped byte counts in the Inspector and status bar.

The Inspector is built with a standard `NSWindow`, stack and grid views, native separators, and selectable wrapping labels. Its Preview and More Info sections remain open, with semibold accessible headings and right-aligned detail labels. A read-only `NSTextView` in an `NSScrollView` supports long text previews; other items use an `NSImageView`. The window fits its selected detail grid while preserving its top edge. Empty and multiple selections clear the previous item’s values and preview. Appearance captures cover device, applet, and file layouts, including wrapped copyright text and a long preview, and check for clipped fields. The legacy Inspector nib is no longer loaded or bundled.

The file list’s native double-click action opens an independent `ASFileViewWindowController` for each file. Its resizable standard `NSWindow` starts at 640 × 480 points, with a 400 × 300 minimum. A selectable, non-editable `NSTextView` wraps inside an `NSScrollView`. Full text is read through `performTaskForNode:refresh:task:completion:` on the existing serial device queue, with no refresh or file writes. The loaded text remains in the window after disconnection. Closing a pending window prevents its completion from updating or reopening it, and closed controllers are removed from the application’s window list.

The status bar pairs Read-only with Apple’s `pencil.slash` SF Symbol, with a built-in AppKit lock-template fallback. The adjacent text supplies the accessibility description. A standard Copy to Clipboard button copies the complete loaded text through `NSPasteboard`, preserving selection and scroll position. It uses cached text after disconnection and stays unavailable while loading, after a failed read, for empty files, and after closing. Native checks use a private pasteboard, without changing the user’s clipboard, and exercise the minimum window size.

A native segmented control selects the regular or monospaced system font at AppKit’s default size. Its mutually exclusive choices use equal-width segments and individual tooltips, following [Apple’s segmented-control guidance](https://developer.apple.com/design/human-interface-guidelines/segmented-controls). `FileViewerMonospaced` remembers the choice for new windows; existing windows keep their own selection. The standard responder-chain Edit menu supplies Copy, Select All, and Find commands. The reader uses AppKit’s find bar and incremental search while staying non-editable. Interface checks cover complete background reads, copying to a private pasteboard, system fonts, independent windows, empty files, read errors, minimum sizing, and closing during a read. Appearance captures include both font choices in Light, Dark, and Light-again modes. Physical double-clicks, keyboard commands, and USB disconnection remain in the manual checklist.

Replace and Clear warnings use asynchronous, window-attached `NSAlert` sheets. Cancel is the Return default. The other button explicitly says Replace, Clear File, or Clear All Files and has no Return shortcut. Interface checks operate the real native buttons on display-only nodes and check both cancellation and confirmation without changing device data. Hosted CI does not reliably grant the test app keyboard focus, so physical Return, keypad Enter, and Escape remain in the manual checklist.

Without a Neo, the main window shows a compact connection view built with native AppKit labels, a stack view, and Apple’s `cable.connector` SF Symbol loaded by `NSImage`. The same window restores its file viewer, toolbar, and chosen size when a Neo connects, and shrinks after the last Neo disconnects. Connection progress and errors remain visible. A sheet can finish before its parent shrinks; full-screen windows keep their Space until the user leaves full screen. Resizing respects Reduce Motion. Native checks cover these connection transitions, multiple Neos, sizing, errors, and sheet deferral, and appearance captures include the disconnected view.

Interface validation logs each startup and window-check stage. Smoke checks have a three-minute deadline, and app appearance captures have five minutes. If a check stalls on macOS, the runner records a process sample before stopping it and failing the check. These deadlines retain the normal validation requirements and leave useful diagnostics instead of waiting for the whole CI job to be cancelled.

The macOS 26 Intel CI job uses the workaround for [runner image issue 14751](https://github.com/actions/runner-images/issues/14751): it unloads the crashing per-user icon agent so AppKit can use generic native icons. This is confined to that disposable build machine. All window, control, and appearance checks still run; the other Mac jobs use the normal icon service.

The backup sheet uses native AppKit controls and Auto Layout at a width of 520 points. Its height fits the result message and selectable, wrapping folder paths. Completion shows the number of files saved and each dated backup folder; the Finder button opens those folders rather than the general backup destination. Failed, cancelled, and empty backups have separate wording. Interface checks cover these results, singular wording, default buttons, unclipped text, and multiple long paths. Appearance captures include successful and incomplete backups, plus two Neo locations, in each mode. Opening the folders in Finder remains a manual check.

Backup logs are opt-in through **Save a backup log** in Preferences. `SaveBackupLogs` defaults to false, including for existing installations, and is captured when a backup starts. When enabled, each Neo’s dated destination contains `AlphaSync Backup Log.plist`, an XML property list covering only that Neo’s files. Initial publication is atomic and exclusive; subsequent updates are atomic. Each device’s log is finished when its files have been processed, so a later cancellation does not change an earlier Neo’s completed log. In-progress logs retain pending files after an interruption. Empty backups create no log. Existing logs are left in place. Native checks exercise logging off and on, option changes during a backup, separate Neos, cancellation, failed exports, empty backups, and filename collisions.

Preferences uses a standard `NSWindow` with native stack and grid views, a folder path control, and Auto Layout. A standard vertical `NSScrollView` keeps the form accessible when its content would exceed the screen’s visible height. Interface checks verify saved settings, closing and reopening the window, native button sizing, unclipped status messages, and a window bounded by the screen. Appearance captures include a long folder path and registration error in each mode. The manual checklist covers smaller screens and selecting and cancelling a backup folder in the system file panel, whose remote service can be unavailable on unattended runners.

About uses native AppKit controls, the bundled app icon, and the shared version and build values. Each build profile supplies its compatibility wording through `ASCompatibilityDescription` in the app’s property list. Verification checks this against the selected profile. The window is opened through its menu action during smoke checks and included in the Light, Dark, and Light-again captures.

The main toolbar uses matching standard fixed spacers between its commands and a leading flexible spacer. The previous default arrangement is migrated through native toolbar item insertion and removal; deliberate custom layouts are preserved. A native `NSStackView` lays out the existing status controls, with progress beside the connection message, a flexible gap, and a right-aligned available-memory label at the trailing edge. Appearance captures include the normal and wider main windows and the progress state in each mode.

GitHub Actions builds the universal app on Intel and Apple Silicon runners with macOS 15 and 26. A required macOS 27 Apple Silicon job builds and launches the modern app. Both profiles receive Debug, Release, archive, dependency, signature, and window checks. These checks run on the runners’ macOS versions, so they do not establish that every feature works on macOS 11.

A final job collects the two canonical development downloads into the `AlphaSync-release-<source commit>` artifact, with checksums, build reports, and shared release notes. It rejects missing packages and mismatched versions, build numbers, source commits, profiles, and signing states. The collector uses Python 3’s standard library; Python is not required to run AlphaSync.

A separate advisory job checks the modern app with the runner’s default Xcode. It uploads no app. This reveals changes needed for newer SDKs while release builds retain their pinned compilers.

Release configurations remove unused code and strip executable symbols after generating matching dSYM bundles. `scripts/verify-symbols.sh` compares the executable and dSYM UUIDs. CI keeps these symbols as separate `AlphaSync-symbols-<runner>-<source commit>` artifacts, outside the public app ZIPs. Debug settings remain unchanged. Obsolete toolbar and status PDFs, Backup nibs, and the Inspector nib have been removed; current views use native components and system symbols.

A small Linux job checks build scope before starting the Mac matrix. Only changes confined to `README.md`, `TECHNICAL.md`, `AGENTS.md`, `tests/manual-checks.md`, and `releases/*.md` skip Mac builds. It compares actual Git paths, including deleted sides of renames. Unknown comparisons, new branches, bundled Help, licences, scripts, resources, source, and build settings require builds. A `Release AlphaSync <version>` request always builds, even if it changes only release notes.

## Automatic launching

Enable automatic launching in Preferences. The helper stays inside the app bundle:

- macOS 13 and later use `SMAppService`. Allow the background item in System Settings if approval is required.
- macOS 11 and 12 use `SMLoginItemSetEnabled`, the public API available on those versions.

AlphaSync no longer copies a launcher into Application Support. If an older installation already starts a separate launcher at login, disable its automatic launching before replacing it. Move the new app to its final location before enabling automatic launching.

Preferences shows the actual launcher state separately from the automatic-launch setting. It reports registration errors and approval requests, and provides a Login Items settings button on macOS 13 and later. The older API cannot query the saved registration state, so macOS 11 and 12 report an unknown state when the helper is not running.

The Universal build keeps the original icon in `application.iconset`. The modern build uses the preferred macOS 27 mockup in `Graphics/application-modern.png` as a flattened icon. Each profile sets `AS_APP_ICON_NAME`; Xcode uses macOS’s `sips` and `iconutil` tools to create the selected `.icns` file at standard and Retina sizes in its derived files directory. Only that icon is copied into the main app. Verification checks the selected name, the absence of the other variant, and every icon size. The bundled launch helper retains its own icon.

## Imports and backups

USB requests now check the expected response command before using reply data. Applet header reads reject invalid counts and partial headers, and system-version fields are parsed only within the received payload. Malformed replies fail without constructing strings outside the buffer. Existing small simulated-reply tests cover these cases.

Exports and backups always use UTF-8 without a byte-order mark. Preferences shows the fixed output format, and encoding preferences saved by older versions do not affect it. Imports still accept MacASCII (Mac Roman), UTF-8 with or without a byte-order mark, and UTF-16 with a byte-order mark in either byte order.

Windows line endings become single paragraph breaks. An import containing characters the Neo cannot store fails with an explanation, leaving the existing file intact.

Before reading a local import, AlphaSync queries the Neo’s maximum size. It reads in chunks of up to 65,536 bytes, stopping at `min(maximum × 4 + 65,536, 64 MiB)` plus one detection byte. This allows encoding and newline overhead while bounding memory use for oversized or growing files. A successful file-size query can reject an oversized source immediately; a failed optional query falls back to the bounded read. Conversion and the exact device-format size and memory checks still follow.

Creating and replacing files share validation in `ASDevice`, after conversion into the Neo’s format and before file attributes or contents are written. Each write reads AlphaWord’s current maximum rather than relying on the cached display value. An unreadable, missing, truncated, zero, or inconsistent limit stops the import; the Inspector shows an unavailable maximum rather than an unlimited one. The protocol’s 24-bit length field is also enforced.

Memory validation keeps 1,024 bytes in reserve and credits an existing file’s allocation for replacements. Files that do not grow can still be replaced when free memory is low. Failed memory and file-size queries stop the import. User warnings distinguish a per-file limit, insufficient memory, and unavailable information, show grouped exact byte counts, and suggest how to proceed. Protocol regression tests verify both write routes, exact limits, a 2 MB rejection, memory boundaries, failed queries, and that rejected imports issue no file-writing commands. Native text tests exercise the actual import paths and their error messages; real USB behaviour remains in the manual checklist.

USB commands and connection callbacks run on one background queue. The interface uses independent copies of the device’s displayed data. Cancellation finishes and records the current file before stopping, and quitting waits for pending work without blocking the interface.

Display snapshots no longer download all file contents or partial previews. Full reads happen on demand for the reader, visible text Inspector, backups, and exports. Plain-text pasteboard data is offered only when the complete text is cached; file-promise exports always read the complete file. The file list uses `localizedStandardCompare:` for Finder-style natural name ordering. Renames validate the supported encoding and length, check the write result, and confirm the returned name before reporting success.

File creation, replacement, and single-file clearing read the bytes back and compare them after writing. Clear All reloads the file list, checks its count against a successful resource query, and confirms each file’s text is empty. Verification failures say that data may already have changed. They do not claim that a failed write left the original untouched.

`SaveRecoveryCopies` defaults to true. A Replace or Clear sheet can override the choice, and Preferences offers retention of 7, 30, or 90 days, or no automatic expiry. The default is 30 days. Protected tasks save fresh original text in private, uniquely named folders under `Recovery Copies` in the selected backup folder before performing any destructive command. A complete applet enumeration is required before saving all its originals. Failure to finish the requested copy blocks the change. Later device-operation errors include the saved recovery location.

Recovery folders start with an incomplete suffix and are published with an exclusive rename only after their files and identification metadata are saved. Retention moves only recognised version 1 recovery folders older than the selected period to the Mac’s Trash when a new copy is made. It skips incomplete folders and directory symlinks, and never permanently deletes files. A retention failure also blocks the pending destructive task. Recovery is a manual restore by importing the saved text, not an atomic USB rollback or an Edit → Undo action.

Exports are written and synchronised in a hidden temporary file before their final name appears. Existing files are preserved. Each dated backup folder starts with ` (Incomplete)` and loses that suffix through an exclusive rename only after that Neo’s files finish successfully. Failed, stopped, or interrupted sessions retain the marker even with logs off. Optional **AlphaSync Backup Log.plist** files use format version 2 with paths relative to that folder, so completing the folder does not invalidate its entries. Hidden temporary files left by an interrupted write can be removed after checking the saved files and any log.

## Help and support

The Help menu uses native `NSMenu` and `NSMenuItem` objects and is assigned to `NSApplication.helpMenu`, which supplies system Help search. It remains last in the menu bar, with AlphaSync Help first among the app’s commands and the standard ⌘? shortcut. Separators group the guide, release notes and licence, and support links. Labels follow [Apple’s menu guidance](https://developer.apple.com/design/human-interface-guidelines/menus), with ellipses only on the issue and contact commands that need further input.

Release Notes uses the running bundle’s `CFBundleShortVersionString` to link to that exact GitHub release. Report Issue opens GitHub’s new-issue form, and Contact Us opens `mailto:mike@koralatov.com` through the user’s default mail app. Their editable forms include app version, build, edition, macOS version, and process architecture. No file contents, paths, device identifiers, or attachments are included. Choosing either command opens a form; submission remains with the user. A native alert offers to copy the link if macOS cannot open its handler.

The Build Help phase generates an offline licence page directly from the original `LICENSE`, then uses macOS’s `hiutil` to rebuild the Help index, including anchors. It runs after copying the Help resources and before signing, for both variants and archives. The obsolete prebuilt index is no longer kept in source control. The Licence command opens the generated `alphasync-licence` anchor in Help Viewer. Interface checks validate menu wiring and destinations without launching browsers or mail, and the WebKit checks compare the displayed licence text with the original notice in each appearance mode. Native Help-popup screenshots are collected when the runner permits screen capture; interactive Help search and external handlers remain in the manual checklist.

## Versioning

Both downloads and their helpers share the version and build in [Version.xcconfig](AlphaSync/Build/Version.xcconfig). Versions can have two or three numeric components, such as `1.5` or `1.5.1`. Increase the build number for each distributed revision, independently of the release version, and set the version before creating its release tag. The separate build reports record the full source commit for both downloads.

To publish a testing release, commit its notes as `releases/<version>.md`, then push a version update with the exact commit subject `Release AlphaSync <version>`. The version must match `Version.xcconfig`. The **Build and test** workflow builds both downloads, completes the required checks, and verifies the version, source commit, and checksums before creating a fresh tag. It uploads both ZIPs, their checksums, and build reports to one draft, verifies all six uploaded files, then publishes it as a prerelease. Existing tags and releases are not overwritten. Only the publication job has release-writing permission. Other pushes and pull requests produce build artifacts as before.

## Hardware checks before a release

A real Neo is needed to verify USB communication. Test on Intel and Apple Silicon, including macOS 11 where possible:

- Connect and disconnect a Neo, and confirm that its files appear correctly.
- Copy text in both directions, including pound signs, accented letters, and curly quotes.
- Export files and folders to Finder, and drop text files back onto the Neo.
- Back up named files, file spaces, and empty files. Test an unwritable destination and unplug the device between files.
- Confirm that oversized imports fail clearly and leave the existing device file intact.
- Check launching at login and on USB connection, including approval, disabling it, and moving the app.

Retain known-good backups while testing writes. Successful builds and simulated transfers cannot establish hardware compatibility, and no binary can be guaranteed to run on every future macOS release.

