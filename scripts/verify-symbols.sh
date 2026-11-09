#!/bin/bash
set -euo pipefail
if [[ $# -ne 1 ]]; then
    printf 'Usage: %s products-directory\n' "$0" >&2
    exit 1
fi
for name in AlphaSync AlphaSyncLauncher; do
    binary="$1/$name.app/Contents/MacOS/$name"
    symbols="$1/$name.app.dSYM"
    test -s "$symbols/Contents/Resources/DWARF/$name"
    binary_ids=$(xcrun dwarfdump --uuid "$binary" | awk '{ print $2, $3 }' | LC_ALL=C sort)
    symbol_ids=$(xcrun dwarfdump --uuid "$symbols" | awk '{ print $2, $3 }' | LC_ALL=C sort)
    test -n "$binary_ids"
    test "$binary_ids" = "$symbol_ids"
    printf 'Verified separate symbols for %s (%s bytes).\n' "$name" "$(stat -f '%z' "$binary")"
done
