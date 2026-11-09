# Technical guide

Build, test, and implementation details for developers and advanced users. For installation and everyday use, see the [README](README.md).

## Legacy release

**AlphaSync 1.5.1, build 147** is the final supported release for **macOS 11 and 12**, on Intel and Apple Silicon. It produces one Universal app and its matching bundled launcher. There is no macOS 13–26 or macOS 27 app download in this release.

The public [v1.5.1 release](https://github.com/koralatov/alphasync/releases/tag/v1.5.1) retains the app ZIP, its SHA-256 checksum and build report, and a separate matching crash-symbol ZIP with its own checksum and report. These are release assets, rather than expiring Actions artifacts. GitHub also provides source archives for the tag.

The exact release commit is preserved as `v1.5.1` and `legacy-macos-11-12`. Freeze finalisation locks the branch against updates, deletion, and force pushes, including administrators; an active ruleset blocks updates and deletion of this tag without bypass actors. GitHub release immutability is enabled before publishing the draft, protecting its assets and tag. Repository owners can still change repository policies or remove the repository; these controls do not constitute an independent archival service. Keep an independent copy when long-term retention matters.

Development continues on **master** for 1.6. Do not merge later changes into the frozen branch, move the tag, or replace its downloads. Do not raise this legacy build’s deployment target or introduce a macOS 13 dependency.

The deployment target is **11.0** in both executable slices and both bundles. Apple’s deployment target specifies a minimum, not an upper runtime limit; the supported range and download label are 11 and 12. The app is not deliberately disabled on newer systems. No separate newer-system app is built or released for 1.5.1.

The app uses Apple’s public frameworks and the standard C++ library. There are no third-party runtime libraries, package managers, or separately installed USB drivers.

## Build the preserved source

Check out `v1.5.1` or `legacy-macos-11-12`. Use the pinned Xcode version in [.xcode-version](.xcode-version), **26.6**, and the shared **AlphaSync** scheme. CI also compiles and tests with **Xcode 16.4** on an Intel host. These newer build hosts are separate from the app’s supported runtime systems.

```sh
xcodebuild -project AlphaSync/AlphaSync.xcodeproj \
  -scheme AlphaSync -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData build
```

The result is `build/DerivedData/Build/Products/Release/AlphaSync.app`. Keep the bundle intact, including `Contents/Library/LoginItems/AlphaSyncLauncher.app`. The legacy packaging scripts accept only the `universal` profile. The dormant Modern project configurations and icon source are retained for development history; they are not built by the 1.5.1 workflow.

### Older-system verification

Mike reports that the earlier build works on **macOS 12**. The exact build, architecture, and individual checks were not recorded, so this is not a completed manual test of the final 1.5.1 ZIP. macOS 11 runtime testing remains unverified. Both systems use the existing `SMLoginItemSetEnabled` implementation. Record final-download and physical Neo results in the [manual checklist](tests/manual-checks.md).

## Development artifacts

The [Actions page](https://github.com/koralatov/alphasync/actions) provides temporary artifacts for successful build runs. `AlphaSync-release-<source commit>` contains the legacy app, symbols, checksums, and build reports. Use the public v1.5.1 release for the preserved download. Actions artifact retention is not permanent.

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

Replace and Clear warnings use asynchronous, window-attached `NSAlert` sheets. Cancel is the Return default and receives initial keyboard focus, so Space also cancels when the sheet opens. The other button explicitly says Replace, Clear File, or Clear All Files and has no Return shortcut. Native Tab navigation remains available for deliberate selection. Interface checks operate the real native buttons on display-only nodes and check both cancellation and confirmation without changing device data. Hosted CI does not reliably grant the test app keyboard focus, so physical Return, keypad Enter, and Escape remain in the manual checklist.

Without a Neo, the main window shows a compact connection view built with native AppKit labels, a stack view, and Apple’s `cable.connector` SF Symbol loaded by `NSImage`. The same window restores its file viewer, toolbar, and chosen size when a Neo connects, and shrinks after the last Neo disconnects. Connection progress and errors remain visible. A sheet can finish before its parent shrinks; full-screen windows keep their Space until the user leaves full screen. Resizing respects Reduce Motion. Native checks cover these connection transitions, multiple Neos, sizing, errors, and sheet deferral, and appearance captures include the disconnected view.

Interface validation logs each startup and window-check stage. Smoke checks have a three-minute deadline, and app appearance captures have five minutes. If a check stalls on macOS, the runner records a process sample before stopping it and failing the check. These deadlines retain the normal validation requirements and leave useful diagnostics instead of waiting for the whole CI job to be cancelled.

The backup sheet uses native AppKit controls and Auto Layout at a width of 520 points. Its height fits the result message and selectable, wrapping folder paths. Completion shows the number of files saved and each dated backup folder; the Finder button opens those folders rather than the general backup destination. Failed, cancelled, and empty backups have separate wording. Interface checks cover these results, singular wording, default buttons, unclipped text, and multiple long paths. Appearance captures include successful and incomplete backups, plus two Neo locations, in each mode. Opening the folders in Finder remains a manual check.

Backup logs are opt-in through **Save a backup log** in Preferences. `SaveBackupLogs` defaults to false, including for existing installations, and is captured when a backup starts. When enabled, each Neo’s dated destination contains `AlphaSync Backup Log.plist`, an XML property list covering only that Neo’s files. Initial publication is atomic and exclusive; subsequent updates are atomic. Each device’s log is finished when its files have been processed, so a later cancellation does not change an earlier Neo’s completed log. In-progress logs retain pending files after an interruption. Empty backups create no log. Existing logs are left in place. Native checks exercise logging off and on, option changes during a backup, separate Neos, cancellation, failed exports, empty backups, and filename collisions.

Preferences uses a standard `NSWindow` with native stack and grid views, a folder path control, and Auto Layout. A standard vertical `NSScrollView` keeps the form accessible when its content would exceed the screen’s visible height. Interface checks verify saved settings, closing and reopening the window, native button sizing, unclipped status messages, and a window bounded by the screen. Appearance captures include a long folder path and registration error in each mode. The manual checklist covers smaller screens and selecting and cancelling a backup folder in the system file panel, whose remote service can be unavailable on unattended runners.

About uses native AppKit controls, the bundled app icon, and the shared version and build values. Each build profile supplies its compatibility wording through `ASCompatibilityDescription` in the app’s property list. Verification checks this against the selected profile. The window is opened through its menu action during smoke checks and included in the Light, Dark, and Light-again captures.

The main toolbar uses matching standard fixed spacers between its commands and a leading flexible spacer. The previous default arrangement is migrated through native toolbar item insertion and removal; deliberate custom layouts are preserved. A native `NSStackView` lays out the existing status controls, with progress beside the connection message, a flexible gap, and a right-aligned available-memory label at the trailing edge. Appearance captures include the normal and wider main windows and the progress state in each mode.

GitHub Actions compiles the legacy Universal app on an Intel macOS 15 host with Xcode 16.4 and an Apple Silicon macOS 26 host with pinned Xcode 26.6. Both receive core and native regression tests, bounded sanitizer checks, Debug and Release builds, dependencies, signatures, and native window and appearance checks. The pinned host also checks the archive layout. No Modern or macOS 27 build runs for 1.5.1. These host checks do not establish runtime or USB behaviour on macOS 11 or 12.

`scripts/verify-symbols.sh` checks that the separate dSYM UUIDs match each executable. `scripts/package-symbols.sh` retains the app and helper symbols outside the installable ZIP. The collector validates all six release assets, including hashes, the legacy profile, version, build, source commit, and matching symbol metadata. Unexpected assets are rejected. It uses Python’s standard library; Python is not needed to run AlphaSync.

Release configurations strip executable symbols after producing the dSYMs. Debug settings remain unchanged. Unused toolbar and status PDFs and obsolete window nibs stay out of the app.

A small Linux job checks build scope before starting the Mac matrix. Only changes confined to `README.md`, `TECHNICAL.md`, `AGENTS.md`, `tests/manual-checks.md`, and `releases/*.md` skip Mac builds. It compares actual Git paths, including deleted sides of renames. Unknown comparisons, new branches, bundled Help, licences, scripts, resources, source, and build settings require builds. A `Release AlphaSync <version>` request always builds, even if it changes only release notes.

## Automatic launching

Enable automatic launching in Preferences. The helper stays inside the app bundle:

- macOS 13 and later use `SMAppService`. Allow the background item in System Settings if approval is required.
- macOS 11 and 12 use `SMLoginItemSetEnabled`, the public API available on those versions.

AlphaSync no longer copies a launcher into Application Support. If an older installation already starts a separate launcher at login, disable its automatic launching before replacing it. Move the new app to its final location before enabling automatic launching.

Preferences shows the actual launcher state separately from the automatic-launch setting. It reports registration errors and approval requests, and provides a Login Items settings button on macOS 13 and later. The older API cannot query the saved registration state, so macOS 11 and 12 report an unknown state when the helper is not running.

The legacy Universal build keeps the original icon in `application.iconset`. The unused Modern icon source is retained for later work. Each profile sets `AS_APP_ICON_NAME`; Xcode uses macOS’s `sips` and `iconutil` tools to create the selected `.icns` file at standard and Retina sizes in its derived files directory. Only that icon is copied into the main app. Verification checks the selected name, the absence of the other variant, and every icon size. The bundled launch helper retains its own icon.

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

Before Quick Backup starts, cached applet enumeration must be complete, and each included applet must have a successful resource query whose file count matches its listed files. This status is copied into the display tree without main-thread USB reads. A partial applet list, missing files, or unreadable count blocks the backup with a reconnect explanation, including when logs are off.

Exports are written and synchronised in a hidden temporary file before their final name appears. Existing files are preserved. Each dated backup folder starts with ` (Incomplete)` and loses that suffix through an exclusive rename only after that Neo’s files finish successfully. Failed, stopped, or interrupted sessions retain the marker even with logs off. Optional **AlphaSync Backup Log.plist** files use format version 2 with paths relative to that folder, so completing the folder does not invalidate its entries. Hidden temporary files left by an interrupted write can be removed after checking the saved files and any log.

## Help and support

The Help menu uses native `NSMenu` and `NSMenuItem` objects and is assigned to `NSApplication.helpMenu`, which supplies system Help search. It remains last in the menu bar, with AlphaSync Help first among the app’s commands and the standard ⌘? shortcut. Separators group the guide, release notes and licence, and support links. Labels follow [Apple’s menu guidance](https://developer.apple.com/design/human-interface-guidelines/menus), with ellipses only on the issue and contact commands that need further input.

Release Notes uses the running bundle’s `CFBundleShortVersionString` to link to that exact GitHub release. Report Issue opens GitHub’s new-issue form, and Contact Us opens `mailto:mike@koralatov.com` through the user’s default mail app. Their editable forms include app version, build, edition, macOS version, and process architecture. No file contents, paths, device identifiers, or attachments are included. Choosing either command opens a form; submission remains with the user. A native alert offers to copy the link if macOS cannot open its handler.

The Build Help phase generates an offline licence page directly from the original `LICENSE`, then uses macOS’s `hiutil` to rebuild the Help index, including anchors. It runs after copying the Help resources and before signing, for the app and archives. The obsolete prebuilt index is no longer kept in source control. The Licence command opens the generated `alphasync-licence` anchor in Help Viewer. Interface checks validate menu wiring and destinations without launching browsers or mail, and the WebKit checks compare the displayed licence text with the original notice in each appearance mode. Native Help-popup screenshots are collected when the runner permits screen capture; interactive Help search and external handlers remain in the manual checklist.

## Release and freeze procedure

The app and helper share `MARKETING_VERSION = 1.5.1` and `CURRENT_PROJECT_VERSION = 147` in [Version.xcconfig](AlphaSync/Build/Version.xcconfig). The full source commit is recorded separately in both build reports.

The exact subject `Release AlphaSync 1.5.1` triggers a complete build. Only after both Mac jobs pass does the publication job validate the six assets against that commit and version, create a fresh `v1.5.1` tag, upload a stable release draft, verify its asset names and sizes, and create `legacy-macos-11-12` at the same commit. It never replaces an existing tag or branch. Creating a draft allows every asset to be checked before immutability takes effect.

The owner then runs:

```sh
scripts/freeze-legacy.sh <verified-release-commit>
```

This requires GitHub CLI authentication with repository administration access, which the Actions `GITHUB_TOKEN` does not provide. The script downloads and verifies all assets again, locks the exact legacy branch with administrator enforcement, protects only the release tag, enables immutable releases, and publishes the draft as a stable release. It verifies the resulting controls, exact source pointers, and immutable release state. It does not lock master or the whole repository. A failed administrative step leaves the prepared draft unpublished rather than claiming the source has been frozen.

For manual finalisation, apply those same controls in GitHub Settings before publishing the draft, then verify them through GitHub’s API. Do not publish first and enable immutability afterwards: immutability applies to future publications only. See [GitHub’s immutable-release guidance](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases).

## Hardware checks before a release

A real Neo is needed to verify USB communication. Test on Intel and Apple Silicon, including macOS 11 where possible:

- Connect and disconnect a Neo, and confirm that its files appear correctly.
- Copy text in both directions, including pound signs, accented letters, and curly quotes.
- Export files and folders to Finder, and drop text files back onto the Neo.
- Back up named files, file spaces, and empty files. Test an unwritable destination and unplug the device between files.
- Confirm that oversized imports fail clearly and leave the existing device file intact.
- Check launching at login and on USB connection, including approval, disabling it, and moving the app.

Retain known-good backups while testing writes. Successful builds and simulated transfers cannot establish hardware compatibility, and no binary can be guaranteed to run on every future macOS release.

