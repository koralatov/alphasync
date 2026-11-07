#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    printf 'Usage: %s app screenshot-folder\n' "$0" >&2
    exit 1
fi

"$1/Contents/MacOS/AlphaSync" --smoke-test --appearance-snapshots "$2"

repository=$(cd "$(dirname "$0")/.." && pwd)
checker="$2/../help-appearance"
xcrun clang -fblocks -Wall -Wextra -Werror "$repository/tests/help-appearance.m" \
    -framework Cocoa -framework WebKit -o "$checker"
"$checker" "$1/Contents/Resources/AlphaSync Help" "$2"
