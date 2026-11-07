#!/bin/bash
set -euo pipefail

app=${1:-build/DerivedData/Build/Products/Release/AlphaSync.app}
minimum=${2:-11.0}
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
    lipo "$binary" -verify_arch x86_64 arm64
    for architecture in x86_64 arm64; do
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
"$app/Contents/MacOS/AlphaSync" --smoke-test
