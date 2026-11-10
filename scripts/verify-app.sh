#!/bin/bash
set -euo pipefail
if [[ $# -lt 2 || $# -gt 3 || ( $# -eq 3 && "$3" != --skip-launch ) ]]; then
    printf 'Usage: %s app universal|apple-silicon [--skip-launch]\n' "$0" >&2
    exit 1
fi
app=$1
repository=$(cd "$(dirname "$0")/.." && pwd)
source "$repository/scripts/build-profile.sh" "$2"
expected_architectures=$(printf '%s\n' $profile_architectures | LC_ALL=C sort | xargs)
helper="$app/Contents/Library/LoginItems/AlphaSyncLauncher.app"
help_book="$app/Contents/Resources/AlphaSync Help"
test -s "$help_book/AlphaSync Help.helpindex"
test -s "$help_book/licence.html"
/usr/bin/grep -q 'alphasync-home' "$help_book/alphasync-help.html"
if find "$app/Contents/Resources" -name '*.nib' -print | /usr/bin/grep -q .; then
    printf 'The SwiftUI app must not contain legacy nibs.\n' >&2; exit 1
fi
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
build_number=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")
[[ "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]
[[ "$build_number" =~ ^[1-9][0-9]*$ ]]
test "$version" = "$(sed -n 's/^MARKETING_VERSION *= *//p' "$repository/AlphaSync/Build/Version.xcconfig")"
test "$build_number" = "$(sed -n 's/^CURRENT_PROJECT_VERSION *= *//p' "$repository/AlphaSync/Build/Version.xcconfig")"
test "$(/usr/libexec/PlistBuddy -c 'Print :ASReleaseChannel' "$app/Contents/Info.plist")" = "$(sed -n 's/^AS_RELEASE_CHANNEL *= *//p' "$repository/AlphaSync/Build/Version.xcconfig")"
test "$(/usr/libexec/PlistBuddy -c 'Print :ASReleaseTag' "$app/Contents/Info.plist")" = "$(sed -n 's/^AS_RELEASE_TAG *= *//p' "$repository/AlphaSync/Build/Version.xcconfig")"
test "$(/usr/libexec/PlistBuddy -c 'Print :ASBuildProfile' "$app/Contents/Info.plist")" = "$profile_variant"
compatibility=$(sed -n 's/^AS_COMPATIBILITY_DESCRIPTION *= *//p' "$profile_configuration")
test "$(/usr/libexec/PlistBuddy -c 'Print :ASCompatibilityDescription' "$app/Contents/Info.plist")" = "$compatibility"
icon=$(sed -n 's/^AS_APP_ICON_NAME *= *//p' "$profile_configuration")
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$app/Contents/Info.plist")" = "$icon"
test -s "$app/Contents/Resources/$icon.icns"
icon_check_directory=$(mktemp -d "${TMPDIR:-/tmp}/alphasync-icon-check.XXXXXX")
trap 'rm -rf "$icon_check_directory"' EXIT
/usr/bin/iconutil --convert iconset --output "$icon_check_directory/selected.iconset" "$app/Contents/Resources/$icon.icns"
for size in 16 32 128 256 512; do
    test -s "$icon_check_directory/selected.iconset/icon_${size}x${size}.png"
    test -s "$icon_check_directory/selected.iconset/icon_${size}x${size}@2x.png"
done
for bundle in "$app" "$helper"; do
    name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle/Contents/Info.plist")
    binary="$bundle/Contents/MacOS/$name"
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist")" = "com.tsoniq.$name"
    test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$bundle/Contents/Info.plist")" = "$profile_minimum"
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$bundle/Contents/Info.plist")" = "$version"
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$bundle/Contents/Info.plist")" = "$build_number"
    actual_architectures=$(lipo -archs "$binary" | tr ' ' '\n' | LC_ALL=C sort | xargs)
    if [[ "$actual_architectures" != "$expected_architectures" ]]; then
        printf 'Wrong architectures in %s: expected %s, found %s.\n' "$bundle" "$expected_architectures" "$actual_architectures" >&2; exit 1
    fi
    for architecture in $profile_architectures; do
        actual_minimum=$(xcrun vtool -arch "$architecture" -show-build "$binary" | awk '$1 == "minos" { print $2 }')
        test "$actual_minimum" = "$profile_minimum"
        libraries=$(otool -arch "$architecture" -L "$binary" | awk 'NR > 1 { print $1 }')
        while IFS= read -r library; do
            case "$library" in
                /System/Library/Frameworks/*|/usr/lib/*|@rpath/libswift*.dylib) ;;
                *) printf 'Unexpected dependency: %s\n' "$library" >&2; exit 1 ;;
            esac
        done <<< "$libraries"
    done
    codesign --verify --strict "$bundle"
    details=$(codesign -d --verbose=4 "$bundle" 2>&1)
    flags=$(printf '%s\n' "$details" | sed -n 's/^CodeDirectory .*flags=0x\([[:xdigit:]]*\).*/\1/p')
    if [[ -z "$flags" ]] || (( (16#$flags & 0x10000) == 0 )); then
        printf 'The hardened runtime is missing from %s.\n' "$bundle" >&2; exit 1
    fi
done
codesign --verify --deep --strict "$app"
if [[ "${3:-}" != --skip-launch ]]; then
    case " $profile_architectures " in
        *" $(uname -m) "*) test "$("$app/Contents/MacOS/AlphaSync" --version)" = "AlphaSync $version (build $build_number)" ;;
        *) printf 'Skipping execution of the other architecture; bundle checks passed.\n' ;;
    esac
fi
printf 'Verified %s, macOS %s minimum, architectures %s.\n' "$profile_variant" "$profile_minimum" "$expected_architectures"
