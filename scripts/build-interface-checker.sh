#!/bin/bash
set -euo pipefail
if [[ $# -ne 1 ]]; then
    printf 'Usage: %s app\n' "$0" >&2
    exit 1
fi
repository=$(cd "$(dirname "$0")/.." && pwd)
app=$1
minimum=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist")
[[ "$minimum" =~ ^[0-9]+\.[0-9]+$ ]]
cache="$repository/build/interface-checker-$minimum-$(uname -m)"
mkdir -p "$cache/objects"
sdk=$(xcrun --sdk macosx --show-sdk-path)
compiler_version=$(xcrun clang --version)
fingerprint=$(python3 - "$repository" "$minimum" "$sdk" "$compiler_version" <<'PY'
import hashlib, sys
from pathlib import Path
root = Path(sys.argv[1])
digest = hashlib.sha256("\0".join(sys.argv[2:]).encode())
patterns = ["AlphaSync/Application/*", "AlphaSync/Driver/*", "AlphaSync/Library/*",
            "AlphaSync/Launcher/aq_launcher.*", "AlphaSync/AlphaSync_Prefix.pch",
            "tests/interface-checks.m", "scripts/build-interface-checker.sh"]
files = sorted({p for pattern in patterns for p in root.glob(pattern)
                if p.is_file() and p.suffix in {".cc", ".m", ".mm", ".h", ".pch", ".sh"}})
for path in files:
    digest.update(str(path.relative_to(root)).encode() + b"\0" + path.read_bytes())
print(digest.hexdigest())
PY
)
if [[ ! -f "$cache/fingerprint" || "$(cat "$cache/fingerprint")" != "$fingerprint" || ! -x "$cache/InterfaceChecks" ]]; then
    sources=("$repository"/AlphaSync/Application/*.mm "$repository"/AlphaSync/Driver/*.cc
             "$repository"/AlphaSync/Library/*.m "$repository/AlphaSync/Launcher/aq_launcher.m"
             "$repository/tests/interface-checks.m")
    flags=(-isysroot "$sdk" "-mmacosx-version-min=$minimum" -Os -g -fblocks -Wall -Wextra -Werror
           -Wno-unknown-pragmas -DAS_INTERFACE_CHECKS=1
           -I"$repository/AlphaSync/Application" -I"$repository/AlphaSync/Driver"
           -I"$repository/AlphaSync/Library" -I"$repository/AlphaSync/Launcher"
           -include "$repository/AlphaSync/AlphaSync_Prefix.pch")
    objects=()
    for source in "${sources[@]}"; do
        object="$cache/objects/$(basename "${source%.*}").o"
        compiler=clang
        extra=()
        case "$source" in *.cc|*.mm) compiler=clang++; extra=(-std=c++17);; esac
        xcrun "$compiler" "${flags[@]}" "${extra[@]}" -c "$source" -o "$object"
        objects+=("$object")
    done
    xcrun clang++ "-mmacosx-version-min=$minimum" -isysroot "$sdk" "${objects[@]}" \
        -framework Cocoa -framework Foundation -framework IOKit -framework ServiceManagement \
        -framework UniformTypeIdentifiers -o "$cache/InterfaceChecks"
    printf '%s\n' "$fingerprint" > "$cache/fingerprint"
fi
# Recreate the host from the exact resources being verified, without changing the app.
host="$cache/AlphaSyncInterfaceChecks.app"
rm -rf "$host"
mkdir -p "$host/Contents/MacOS"
ditto "$app/Contents/Resources" "$host/Contents/Resources"
if [[ -d "$app/Contents/Library" ]]; then ditto "$app/Contents/Library" "$host/Contents/Library"; fi
cp "$app/Contents/Info.plist" "$host/Contents/Info.plist"
cp "$cache/InterfaceChecks" "$host/Contents/MacOS/AlphaSyncInterfaceChecks"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable AlphaSyncInterfaceChecks' "$host/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.tsoniq.AlphaSync.InterfaceChecks' "$host/Contents/Info.plist"
helper="$host/Contents/Library/LoginItems/AlphaSyncLauncher.app"
if [[ -d "$helper" ]]; then codesign --force --sign - "$helper" >&2; fi
codesign --force --sign - "$host" >&2
printf '%s\n' "$host/Contents/MacOS/AlphaSyncInterfaceChecks"
