# AlphaSync

AlphaSync is a native Mac file manager for AlphaSmart NEO devices.  It copies text files in both directions, backs up named files and file spaces, and can open automatically when a NEO is connected.

The app requires **macOS 11.0 or later**.  One universal app contains native Intel (`x86_64`) and Apple Silicon (`arm64`) executables, including its bundled launcher.  It uses Apple’s public frameworks and the standard C++ library.  There are no third-party libraries, package managers, or separately installed USB drivers.

## Build

The recommended build uses **Xcode 26.6**.  CI also checks **Xcode 16.4** for builds made on an older Mac.  Install Xcode and its command-line tools, open `AlphaSync/AlphaSync.xcodeproj`, select the shared **AlphaSync** scheme, and build.  The project builds both architectures in Debug and Release.

From the repository root:

```sh
xcodebuild -project AlphaSync/AlphaSync.xcodeproj \
  -scheme AlphaSync -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData build
```

The result is `build/DerivedData/Build/Products/Release/AlphaSync.app`.  Keep the app bundle intact, including `Contents/Library/LoginItems/AlphaSyncLauncher.app`.

Newer Xcode releases can raise their minimum supported deployment target.  Check [Apple’s Xcode requirements](https://developer.apple.com/xcode/system-requirements) before changing the toolchain, and keep the macOS 11 checks passing.

## Check a build

The core tests need a C++17 compiler and make.  They run on macOS and Linux, without a connected NEO:

```sh
make test
make sanitize
```

They cover text conversion, dictionary imports, both UTF-16 byte orders, malformed files, settings boundaries, failed buffer operations, and simulated USB replies.  Invalid-reply tests produce expected error messages before the final success message.

On macOS, `make test` also checks exported XML with Foundation’s parser.  Older backups without a root element remain readable by AlphaSync.

On a Mac, verify the built app with:

```sh
scripts/verify-app.sh
```

This checks both architectures, the executable deployment targets, system-only dependencies, nested signatures, and every interface window.  It does not capture USB devices or change login items.  An alternative app path can be passed as its first argument.

GitHub Actions runs tests and builds Debug and Release on Intel and Apple Silicon runners with macOS 15 and 26.  Each successful job saves a zipped universal app as a build artifact.  These checks run on the runners’ macOS versions, so they do not establish that every feature works on macOS 11.

## Automatic launching

Enable automatic launching in Preferences.  The helper stays inside the app bundle:

- macOS 13 and later use `SMAppService`.  Allow the background item in System Settings if approval is required.
- macOS 11 and 12 use `SMLoginItemSetEnabled`, the public API available on those versions.

AlphaSync no longer copies a launcher into Application Support.  If an older installation already starts a separate launcher at login, disable its automatic launching before replacing it.  Move the new app to its final location before enabling automatic launching.

## Signing and distribution

Local builds use an ad hoc signature and the hardened runtime.  They do not need the original developer’s certificate, a Developer ID, or a notarisation ticket.  Workflow artifacts use ad hoc signatures for development and testing.

For distribution, supply your own identity and team when archiving:

```sh
xcodebuild -project AlphaSync/AlphaSync.xcodeproj \
  -scheme AlphaSync -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath build/AlphaSync.xcarchive \
  CODE_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
  DEVELOPMENT_TEAM=TEAMID OTHER_CODE_SIGN_FLAGS='--timestamp' archive
```

Sign the app and helper with the same identity, follow [Apple’s notarisation instructions](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), and staple the ticket before sharing the app.  Recheck the final signed bundle.  App Store distribution and sandboxing are outside the current scope.

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
