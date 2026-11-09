#!/bin/bash
set -euo pipefail
if [[ $# != 1 ]]; then
    printf 'Usage: %s assets-directory\n' "$0" >&2
    exit 1
fi
repository=$(cd "$(dirname "$0")/.." && pwd)
assets=$(cd "$1" && pwd)
cd "$repository"
version=$(sed -n 's/^MARKETING_VERSION *= *//p' AlphaSync/Build/Version.xcconfig)
build_number=$(sed -n 's/^CURRENT_PROJECT_VERSION *= *//p' AlphaSync/Build/Version.xcconfig)
test "$(sed -n 's/^AS_RELEASE_CHANNEL *= *//p' AlphaSync/Build/Version.xcconfig)" = stable
test -s "releases/$version.md"
test "$(git rev-parse HEAD)" = "$GITHUB_SHA"
mkdir -p build/release-verification
python3 scripts/check-release.py "$assets" --version "$version" --build "$build_number" \
    --source "$GITHUB_SHA" --manifest build/release-verification/assets.json
staging=$(mktemp -d "${TMPDIR:-/tmp}/alphasync-release-check.XXXXXX")
trap 'rm -rf "$staging"' EXIT
for profile in universal apple-silicon; do
    source scripts/build-profile.sh "$profile"
    stem="AlphaSync-$version-$build_number-$profile_label"
    destination="$staging/$profile"
    mkdir -p "$destination/app" "$destination/symbols"
    ditto -x -k "$assets/$stem.zip" "$destination/app"
    ditto -x -k "$assets/$stem-symbols.zip" "$destination/symbols"
    app="$destination/app/AlphaSync.app"
    scripts/verify-app.sh "$app" "$profile"
    for name in AlphaSync AlphaSyncLauncher; do
        if [[ "$name" == AlphaSync ]]; then bundle="$app"; else bundle="$app/Contents/Library/LoginItems/AlphaSyncLauncher.app"; fi
        binary_ids=$(xcrun dwarfdump --uuid "$bundle/Contents/MacOS/$name" | awk '{ print $2, $3 }' | LC_ALL=C sort)
        symbol_ids=$(xcrun dwarfdump --uuid "$destination/symbols/$name.app.dSYM" | awk '{ print $2, $3 }' | LC_ALL=C sort)
        test -n "$binary_ids"
        test "$binary_ids" = "$symbol_ids"
        printf 'Verified packaged %s symbols for %s.\n' "$profile" "$name"
    done
done
printf 'Verified both extracted release apps and their matching symbols.\n'
