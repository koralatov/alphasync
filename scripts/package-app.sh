#!/bin/bash
set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
    printf 'Usage: %s app universal|apple-silicon output-directory [development|notarised]\n' "$0" >&2
    exit 1
fi
repository=$(cd "$(dirname "$0")/.." && pwd)
app=$1
source "$repository/scripts/build-profile.sh" "$2"
output=$3
signing=${4:-development}
case "$signing" in
    development) ;;
    notarised)
        xcrun stapler validate "$app"
        spctl --assess --type execute "$app"
        ;;
    *) printf 'Unknown signing state: %s.\n' "$signing" >&2; exit 1 ;;
esac
"$repository/scripts/verify-app.sh" "$app" "$profile_variant"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
build_number=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")
filename="AlphaSync-$version-$build_number-$profile_label.zip"
mkdir -p "$output"
output=$(cd "$output" && pwd)
for suffix in '' .sha256 .build-information.txt; do
    if [[ -e "$output/$filename$suffix" ]]; then
        printf 'Release file already exists: %s\n' "$output/$filename$suffix" >&2
        exit 1
    fi
done
ditto -c -k --keepParent "$app" "$output/$filename"
(
    cd "$output"
    shasum -a 256 "$filename" > "$filename.sha256"
)
digest=$(awk '{ print $1 }' "$output/$filename.sha256")
{
    printf 'Version: %s\nBuild: %s\nSource commit: %s\n' "$version" "$build_number" "$(git -C "$repository" rev-parse HEAD)"
    printf 'Variant: %s\nMinimum macOS: %s\nArchitectures: %s\n' "$profile_variant" "$profile_minimum" "$profile_architectures"
    printf 'Supported macOS: %s\n' "$profile_supported"
    printf 'Signing: %s\nArchive: %s\nSHA-256: %s\n\n' "$signing" "$filename" "$digest"
    xcodebuild -version
    xcrun --sdk macosx --show-sdk-version
    xcrun swiftc --version
    sw_vers
    uname -m
} > "$output/$filename.build-information.txt"
printf 'Packaged %s\n' "$output/$filename"
