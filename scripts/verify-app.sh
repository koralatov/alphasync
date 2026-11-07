#!/bin/bash
set -euo pipefail

app=${1:-build/DerivedData/Build/Products/Release/AlphaSync.app}
helper="$app/Contents/Library/LoginItems/AlphaSyncLauncher.app"

for bundle in "$app" "$helper"; do
    name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle/Contents/Info.plist")
    binary="$bundle/Contents/MacOS/$name"
    test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$bundle/Contents/Info.plist")" = 11.0
    lipo "$binary" -verify_arch x86_64 arm64
    for architecture in x86_64 arm64; do
        # Check the executable itself, because a plist alone cannot lower its deployment target.
        minimum=$(xcrun vtool -arch "$architecture" -show-build "$binary" | awk '$1 == "minos" { print $2 }')
        test "$minimum" = 11.0
        while IFS= read -r library; do
            case "$library" in
                /System/Library/Frameworks/*|/usr/lib/*) ;;
                *) printf 'Unexpected dependency: %s\n' "$library" >&2; exit 1 ;;
            esac
        done < <(otool -arch "$architecture" -L "$binary" | awk 'NR > 1 { print $1 }')
    done
done

codesign --verify --deep --strict "$app"
"$app/Contents/MacOS/AlphaSync" --smoke-test
