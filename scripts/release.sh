#!/bin/bash
set -euo pipefail

repository=$(cd "$(dirname "$0")/.." && pwd)
cd "$repository"
: "${ALPHASYNC_SIGNING_IDENTITY:?Set the Developer ID Application certificate name.}"
: "${ALPHASYNC_TEAM_ID:?Set the Apple developer team identifier.}"
: "${ALPHASYNC_NOTARY_PROFILE:?Set a notarytool keychain profile name.}"
case "$ALPHASYNC_SIGNING_IDENTITY" in
    'Developer ID Application: '*) ;;
    *) printf 'Use a Developer ID Application certificate.\n' >&2; exit 1 ;;
esac
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
    printf 'Commit or set aside source changes before making a release.\n' >&2
    exit 1
fi
expected_xcode=$(cat .xcode-version)
if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode_$expected_xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode_$expected_xcode.app/Contents/Developer"
fi
scripts/check-toolchain.sh
make test sanitize

mkdir -p build
output=$(mktemp -d "$repository/build/release-XXXXXX")
archive="$output/AlphaSync.xcarchive"
xcodebuild -project AlphaSync/AlphaSync.xcodeproj -scheme AlphaSync \
    -configuration Release -destination 'generic/platform=macOS' \
    -archivePath "$archive" -derivedDataPath "$output/DerivedData" \
    CODE_SIGN_IDENTITY="$ALPHASYNC_SIGNING_IDENTITY" \
    DEVELOPMENT_TEAM="$ALPHASYNC_TEAM_ID" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    OTHER_CODE_SIGN_FLAGS='--timestamp' archive > "$output/archive.log" 2>&1 || {
        printf 'Archive failed.  See %s\n' "$output/archive.log" >&2
        tail -n 60 "$output/archive.log" >&2
        exit 1
    }
app="$archive/Products/Applications/AlphaSync.app"
scripts/verify-app.sh "$app"
for bundle in "$app" "$app/Contents/Library/LoginItems/AlphaSyncLauncher.app"; do
    details=$(codesign -d --verbose=4 "$bundle" 2>&1)
    actual_team=$(printf '%s\n' "$details" | sed -n 's/^TeamIdentifier=//p')
    if [[ "$actual_team" != "$ALPHASYNC_TEAM_ID" ]]; then
        printf 'The signing team does not match for %s.\n' "$bundle" >&2
        exit 1
    fi
    codesign --verify --strict -R='anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' "$bundle"
    if [[ "$details" != *'(runtime)'* ]]; then
        printf 'The hardened runtime is missing from %s.\n' "$bundle" >&2
        exit 1
    fi
done

# Submit an intact, signed bundle.  The final download is made after stapling.
ditto -c -k --keepParent "$app" "$output/notarisation-upload.zip"
xcrun notarytool submit "$output/notarisation-upload.zip" \
    --keychain-profile "$ALPHASYNC_NOTARY_PROFILE" --wait --output-format plist \
    > "$output/notarisation.plist"
status=$(/usr/libexec/PlistBuddy -c 'Print :status' "$output/notarisation.plist")
if [[ "$status" != Accepted ]]; then
    printf 'Notarisation was not accepted.  See %s\n' "$output/notarisation.plist" >&2
    exit 1
fi
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
codesign --verify --deep --strict "$app"

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
build_number=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")
filename="AlphaSync-$version-$build_number.zip"
ditto -c -k --keepParent "$app" "$output/$filename"
(
    cd "$output"
    shasum -a 256 "$filename" > "$filename.sha256"
)
{
    printf 'Source commit: %s\n' "$(git rev-parse HEAD)"
    printf 'Version: %s\nBuild: %s\nMinimum macOS: 11.0\n' "$version" "$build_number"
    scripts/check-toolchain.sh
    sw_vers
    uname -m
} > "$output/build-information.txt"
printf 'Signed and notarised app: %s\n' "$output/$filename"
