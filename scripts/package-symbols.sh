#!/bin/bash
set -euo pipefail
repository=$(cd "$(dirname "$0")/.." && pwd)
if [[ $# != 2 ]]; then
    printf 'Usage: %s products-directory output-directory\n' "$0" >&2
    exit 1
fi
products=$1
output=$2
"$repository/scripts/verify-symbols.sh" "$products"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$products/AlphaSync.app/Contents/Info.plist")
build_number=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$products/AlphaSync.app/Contents/Info.plist")
source "$repository/scripts/build-profile.sh" universal
filename="AlphaSync-$version-$build_number-$profile_label-symbols.zip"
mkdir -p "$output"
output=$(cd "$output" && pwd)
for suffix in '' .sha256 .build-information.txt; do
    test ! -e "$output/$filename$suffix"
done
staging=$(mktemp -d "${TMPDIR:-/tmp}/alphasync-symbols.XXXXXX")
trap 'rm -rf "$staging"' EXIT
for name in AlphaSync AlphaSyncLauncher; do
    ditto "$products/$name.app.dSYM" "$staging/$name.app.dSYM"
done
ditto -c -k "$staging" "$output/$filename"
(
    cd "$output"
    shasum -a 256 "$filename" > "$filename.sha256"
)
digest=$(awk '{ print $1 }' "$output/$filename.sha256")
{
    printf 'Version: %s\nBuild: %s\nSource commit: %s\n' "$version" "$build_number" "$(git -C "$repository" rev-parse HEAD)"
    printf 'Archive: %s\nSHA-256: %s\n\n' "$filename" "$digest"
    for name in AlphaSync AlphaSyncLauncher; do
        xcrun dwarfdump --uuid "$products/$name.app.dSYM"
    done
} > "$output/$filename.build-information.txt"
printf 'Packaged matching crash symbols: %s\n' "$output/$filename"
