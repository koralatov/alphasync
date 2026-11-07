#!/bin/bash
set -euo pipefail

app=${1:-build/DerivedData/Build/Products/Release/AlphaSync.app}
repository=$(cd "$(dirname "$0")/.." && pwd)
source "$repository/scripts/build-profile.sh" "${2:-universal}"
if [[ $# -gt 3 || ( $# -eq 3 && "$3" != --skip-launch ) ]]; then
    printf 'Usage: %s [app] [universal|modern] [--skip-launch]\n' "$0" >&2
    exit 1
fi
minimum=$profile_minimum
expected_architectures=$(printf '%s\n' $profile_architectures | LC_ALL=C sort | xargs)
helper="$app/Contents/Library/LoginItems/AlphaSyncLauncher.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
build_number=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ "$build_number" =~ ^[1-9][0-9]*$ ]]

for bundle in "$app" "$helper"; do
    name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle/Contents/Info.plist")
    binary="$bundle/Contents/MacOS/$name"
    test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$bundle/Contents/Info.plist")" = "$minimum"
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$bundle/Contents/Info.plist")" = "$version"
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$bundle/Contents/Info.plist")" = "$build_number"
    actual_architectures=$(lipo -archs "$binary" | tr ' ' '\n' | LC_ALL=C sort | xargs)
    if [[ "$actual_architectures" != "$expected_architectures" ]]; then
        printf 'Wrong architectures in %s: expected %s, found %s.\n' "$bundle" "$expected_architectures" "$actual_architectures" >&2
        exit 1
    fi
    for architecture in $profile_architectures; do
        # Check the executable itself, because a plist alone cannot lower its deployment target.
        actual_minimum=$(xcrun vtool -arch "$architecture" -show-build "$binary" | awk '$1 == "minos" { print $2 }')
        test "$actual_minimum" = "$minimum"
        libraries=$(otool -arch "$architecture" -L "$binary" | awk 'NR > 1 { print $1 }')
        while IFS= read -r library; do
            case "$library" in
                /System/Library/Frameworks/*|/usr/lib/*) ;;
                *) printf 'Unexpected dependency: %s\n' "$library" >&2; exit 1 ;;
            esac
        done <<< "$libraries"
    done
done

codesign --verify --deep --strict "$app"
if [[ "${3:-}" != --skip-launch ]]; then
    "$app/Contents/MacOS/AlphaSync" --smoke-test
fi
printf 'Verified %s app, macOS %s minimum, architectures %s.\n' "$profile_variant" "$minimum" "$expected_architectures"
