#!/bin/bash
set -euo pipefail

repository=$(cd "$(dirname "$0")/.." && pwd)
source "$repository/scripts/build-profile.sh" "${1:-universal}"
expected=$profile_xcode
if ! command -v xcodebuild >/dev/null; then
    printf 'Install Xcode %s and select it with DEVELOPER_DIR.\n' "$expected" >&2
    exit 1
fi
actual=$(xcodebuild -version | awk 'NR == 1 { print $2 }')
if [[ "$actual" != "$expected" ]]; then
    printf 'Release builds require Xcode %s; the selected version is %s.\n' "$expected" "$actual" >&2
    exit 1
fi
xcodebuild -version
xcrun --sdk macosx --show-sdk-version
xcrun clang --version
