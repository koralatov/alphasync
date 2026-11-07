# AlphaSync

AlphaSync is a native Mac file manager for AlphaSmart NEO devices.  It copies text files in both directions, backs up named files and file spaces, and can open automatically when a NEO is connected.

Each release provides two downloads built from the same source and version:

| Download | Supported macOS | Processors |
|---|---|---|
| Universal | 11 through 26 | Intel and Apple Silicon |
| Modern | 27 and later | Apple Silicon |

Both include the matching bundled launcher and use Apple’s public frameworks and the standard C++ library.  There are no third-party runtime libraries, package managers, or separately installed USB drivers.  Deployment targets set the minimum system; the download labels describe the supported range.

Install the app for your Mac.  Both downloads contain **AlphaSync.app** and use the same preferences and bundle identifiers, so replace the existing app when changing versions.

## Build

The universal build uses the Xcode version in [.xcode-version](.xcode-version), currently **26.6**.  The modern build uses [.xcode-version-modern](.xcode-version-modern), currently **27.1**.  CI also checks the universal app with **Xcode 16.4**.

Install Xcode and its command-line tools, open `AlphaSync/AlphaSync.xcodeproj`, and select the shared **AlphaSync** or **AlphaSync-Modern** scheme.  The schemes share their sources and version settings.  The modern scheme uses `DebugModern` and `ReleaseModern`, and builds only `arm64` in both the app and launcher.

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

The modern result is `build/ModernData/Build/Products/ReleaseModern/AlphaSync.app`.  Launch it on macOS 27 or later.  Keep either app bundle intact, including `Contents/Library/LoginItems/AlphaSyncLauncher.app`.

Newer Xcode releases can raise their minimum supported deployment target.  Check [Apple’s Xcode requirements](https://developer.apple.com/xcode/system-requirements) before changing the toolchain, and keep the macOS 11 checks passing.

### Testing on macOS 12.7.5

macOS 12.7.5 is within the app’s intended runtime range.  Use a universal development build from a successful workflow run to test it without installing the release compiler.  Apple’s [Xcode 14.2 requirements](https://developer.apple.com/documentation/xcode-release-notes/xcode-14_2-release-notes) allow that version to run on Monterey 12.5 and later, although it is not part of this project’s CI matrix.  Xcode 26.6 needs a newer release Mac.

Testing on 12.7.5 exercises the older login-item implementation shared with macOS 11.  Runtime behaviour on macOS 11 still needs a separate check.  The approval flow on macOS 13 and later also needs its own test.  Record these results with the [manual test checklist](tests/manual-checks.md).

## Check a build

The core tests need a C++17 compiler and make.  They run on macOS and Linux, without a connected NEO:

```sh
make test
make sanitize
python3 tests/release-tests.py
```

They cover text conversion, Windows line endings, unsupported characters, dictionary imports, both UTF-16 byte orders, malformed files, settings boundaries, failed buffer operations, and simulated USB replies.  Invalid-reply tests produce expected error messages before the final success message.

On macOS, `make test` also checks exported XML with Foundation’s parser, exclusive file publication, interrupted backup reports, and background queue ordering and responsiveness.  Older backups without a root element remain readable by AlphaSync.

On a Mac, verify the built app with:

```sh
scripts/verify-app.sh
```

For the modern build, run on macOS 27 or later:

```sh
scripts/verify-app.sh build/ModernData/Build/Products/ReleaseModern/AlphaSync.app modern
```

This checks the exact architectures, executable deployment targets, system-only dependencies, matching app and helper versions, nested signatures, and every interface window.  It does not capture USB devices or change login items.  An alternative app path can be passed as its first argument.  An explicit `--skip-launch` third argument permits binary inspection on an older host; it does not establish runtime compatibility.

GitHub Actions builds the universal app on Intel and Apple Silicon runners with macOS 15 and 26.  A required macOS 27 Apple Silicon job builds and launches the modern app.  Both profiles receive Debug, Release, archive, dependency, signature, and window checks.  These checks run on the runners’ macOS versions, so they do not establish that every feature works on macOS 11.

A final job collects the two canonical development downloads into the **AlphaSync-release-<source commit>** artifact, with checksums, build reports, and shared release notes.  It rejects missing packages and mismatched versions, build numbers, source commits, profiles, and signing states.  The collector uses Python 3’s standard library; Python is not required to run AlphaSync.

A separate advisory job checks the modern app with the runner’s default Xcode.  It uploads no app.  This reveals changes needed for newer SDKs while release builds retain their pinned compilers.

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

For a local signed build, install your Developer ID Application certificate and create a [notarytool Keychain profile](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).  Run from a clean checkout on a Mac compatible with the chosen compiler and app:

```sh
ALPHASYNC_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
ALPHASYNC_TEAM_ID=TEAMID \
ALPHASYNC_NOTARY_PROFILE=AlphaSync-notary \
scripts/release.sh universal build/release-universal
```

Use `modern build/release-modern` for the other download, with the same environment variables and source commit, on macOS 27 or later.  Each output directory must be new.  Omitting the output directory creates a fresh directory under `build`.

The script runs the tests, archives the app, verifies both Developer ID signatures and the signing team, and submits the ZIP to Apple.  It requires an accepted notarisation result, staples and validates the ticket, checks Gatekeeper, and creates the final ZIP, SHA-256 checksum, and build report in its **assets** subdirectory.  Credentials stay in your Keychain.  The parent directory retains the archive log and Apple’s result.  Signed builds contain time-dependent signatures and notarisation tickets.

Bring the two assets directories to one checkout, then collect them:

```sh
python3 scripts/collect-release.py \
  --universal build/release-universal/assets \
  --modern build/release-modern/assets \
  --output build/release-assets --require-notarised --tag v1.4.0
```

### One GitHub release

The **Prepare a release** workflow builds and notarises both downloads on their respective Mac runners, then creates **one draft GitHub release** containing both ZIPs, their checksums, and build reports.  It resolves the selected tag to one commit before either build starts and checks that both packages match it.  It leaves publication to the maintainer.

Once the workflow is on the default branch, create and push a tag matching the shared version, such as `v1.4.0`, then run **Prepare a release** with that existing tag.  The tagged commit must contain the two-build release tooling.  Configure these repository secrets first:

| Secret | Value |
|---|---|
| `ALPHASYNC_CERTIFICATE_P12` | Base64-encoded Developer ID Application certificate and private key, exported as `.p12` |
| `ALPHASYNC_CERTIFICATE_PASSWORD` | Password for that `.p12` file |
| `ALPHASYNC_SIGNING_IDENTITY` | Full Developer ID Application certificate name |
| `ALPHASYNC_TEAM_ID` | Apple developer team identifier |
| `ALPHASYNC_APPLE_ID` | Apple account used for notarisation |
| `ALPHASYNC_APP_PASSWORD` | Its app-specific password |

See GitHub’s [certificate setup instructions](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications).  The workflow imports credentials into a temporary Keychain on each runner and removes it after the build.  Only its final job has permission to write a release.  Existing releases are not overwritten.

Both downloads and their helpers share **version 1.4.0, build 140**, read from [Version.xcconfig](AlphaSync/Build/Version.xcconfig).  Increase the build number for each distributed revision and set the version before creating its release tag.  App Store distribution and sandboxing are outside the current scope.

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
