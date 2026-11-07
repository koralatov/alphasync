# AlphaSync

AlphaSync is a native Mac file manager for AlphaSmart NEO devices.  It copies text files in both directions, backs up named files and file spaces, and can open automatically when a NEO is connected.

The app requires **macOS 11.0 or later**.  One universal app contains native Intel (`x86_64`) and Apple Silicon (`arm64`) executables, including its bundled launcher.  It uses Apple’s public frameworks and the standard C++ library.  There are no third-party libraries, package managers, or separately installed USB drivers.

## Build

Release builds use the Xcode version in [.xcode-version](.xcode-version), currently **26.6**.  CI also checks **Xcode 16.4**.  Install Xcode and its command-line tools, open `AlphaSync/AlphaSync.xcodeproj`, select the shared **AlphaSync** scheme, and build.  The project builds both architectures in Debug and Release.

From the repository root:

```sh
xcodebuild -project AlphaSync/AlphaSync.xcodeproj \
  -scheme AlphaSync -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData build
```

The result is `build/DerivedData/Build/Products/Release/AlphaSync.app`.  Keep the app bundle intact, including `Contents/Library/LoginItems/AlphaSyncLauncher.app`.

Newer Xcode releases can raise their minimum supported deployment target.  Check [Apple’s Xcode requirements](https://developer.apple.com/xcode/system-requirements) before changing the toolchain, and keep the macOS 11 checks passing.

### Testing on macOS 12.7.5

macOS 12.7.5 is within the app’s intended runtime range.  Use a universal development build from a successful workflow run to test it without installing the release compiler.  Apple’s [Xcode 14.2 requirements](https://developer.apple.com/documentation/xcode-release-notes/xcode-14_2-release-notes) allow that version to run on Monterey 12.5 and later, although it is not part of this project’s CI matrix.  Xcode 26.6 needs a newer release Mac.

Testing on 12.7.5 exercises the older login-item implementation shared with macOS 11.  Runtime behaviour on macOS 11 still needs a separate check.  The approval flow on macOS 13 and later also needs its own test.  Record these results with the [manual test checklist](tests/manual-checks.md).

## Check a build

The core tests need a C++17 compiler and make.  They run on macOS and Linux, without a connected NEO:

```sh
make test
make sanitize
```

They cover text conversion, Windows line endings, unsupported characters, dictionary imports, both UTF-16 byte orders, malformed files, settings boundaries, failed buffer operations, and simulated USB replies.  Invalid-reply tests produce expected error messages before the final success message.

On macOS, `make test` also checks exported XML with Foundation’s parser, exclusive file publication, interrupted backup reports, and background queue ordering and responsiveness.  Older backups without a root element remain readable by AlphaSync.

On a Mac, verify the built app with:

```sh
scripts/verify-app.sh
```

This checks both architectures, the executable deployment targets, system-only dependencies, nested signatures, and every interface window.  It does not capture USB devices or change login items.  An alternative app path can be passed as its first argument.

GitHub Actions runs tests and builds Debug and Release on Intel and Apple Silicon runners with macOS 15 and 26.  Each successful matrix job saves a versioned universal development app, with its source commit in the artifact name.  The pinned Apple Silicon job also checks the distribution archive layout.  These checks run on the runners’ macOS versions, so they do not establish that every feature works on macOS 11.

A separate advisory job checks the runner’s default Xcode with a macOS 12 deployment target.  It uploads no app.  This reveals changes needed for newer SDKs while the pinned release toolchain continues to produce macOS 11 builds.

## Automatic launching

Enable automatic launching in Preferences.  The helper stays inside the app bundle:

- macOS 13 and later use `SMAppService`.  Allow the background item in System Settings if approval is required.
- macOS 11 and 12 use `SMLoginItemSetEnabled`, the public API available on those versions.

AlphaSync no longer copies a launcher into Application Support.  If an older installation already starts a separate launcher at login, disable its automatic launching before replacing it.  Move the new app to its final location before enabling automatic launching.

Preferences shows the actual launcher state separately from the automatic-launch setting.  It reports registration errors and approval requests, and provides a Login Items settings button on macOS 13 and later.  The older API cannot query the saved registration state, so macOS 11 and 12 report an unknown state when the helper is not running.

## Imports and backups

Windows line endings become single paragraph breaks.  An import containing characters the NEO cannot store fails with an explanation, leaving the existing file intact.

USB commands and connection callbacks run on one background queue.  The interface uses independent copies of the device’s displayed data.  Cancellation finishes and records the current file before stopping, and quitting waits for pending work without blocking the interface.

Exports are written and synchronised in a hidden temporary file before their final name appears.  Existing files are preserved.  Each backup keeps an atomic property-list report in its destination’s **Backup Reports** folder, recording saved filenames, failures, and pending files.  A cancelled, disconnected, or interrupted backup remains distinguishable from a completed backup.  Hidden temporary files left by an interrupted write can be removed after checking the report.

## Signing and distribution

Local builds use an ad hoc signature and the hardened runtime.  They do not need the original developer’s certificate, a Developer ID, or a notarisation ticket.  Workflow artifacts use ad hoc signatures for development and testing.

For distribution, install your Developer ID Application certificate and create a [notarytool Keychain profile](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).  Then run from a clean checkout on the release Mac:

```sh
ALPHASYNC_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
ALPHASYNC_TEAM_ID=TEAMID \
ALPHASYNC_NOTARY_PROFILE=AlphaSync-notary \
scripts/release.sh
```

The script runs the tests, archives the app, verifies both Developer ID signatures and the signing team, and submits the ZIP to Apple.  It requires an accepted notarisation result, staples and validates the ticket, checks Gatekeeper, and creates the final ZIP and SHA-256 checksum.  Credentials stay in your Keychain.  It keeps the archive log, Apple’s result, and source, compiler, and host details in a new `build/release-*` directory for every attempt.  Signed builds contain time-dependent signatures and notarisation tickets.

The app and helper share **version 1.4.0, build 140** through `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the project settings.  Increase the build number for each distributed revision.  App Store distribution and sandboxing are outside the current scope.

## Hardware checks before a release

A real NEO is needed to verify USB communication.  Test on Intel and Apple Silicon, including macOS 11 where possible:

- Connect and disconnect a NEO, and confirm that its files appear correctly.
- Copy text in both directions, including pound signs, accented letters, and curly quotes.
- Export files and folders to Finder, and drop text files back onto the NEO.
- Back up named files, file spaces, and empty files.  Test an unwritable destination and unplug the device between files.
- Confirm that oversized imports fail clearly and leave the existing device file intact.
- Check launching at login and on USB connection, including approval, disabling it, and moving the app.

Retain known-good backups while testing writes.  Successful builds and simulated transfers cannot establish hardware compatibility, and no binary can be guaranteed to run on every future macOS release.

## Licence

AlphaSync was originally written by tSoniq.  The original copyright notices and BSD-style licence remain in [LICENSE](LICENSE) and the source files.
