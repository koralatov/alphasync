#!/bin/bash
# Source this file with the requested profile before building or checking an app.
profile_repository=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
profile_variant=${1:-universal}
case "$profile_variant" in
    universal)
        profile_scheme=AlphaSync
        profile_debug=Debug
        profile_release=Release
        profile_xcode_file="$profile_repository/.xcode-version"
        profile_configuration="$profile_repository/AlphaSync/Build/Universal.xcconfig"
        profile_label=macOS-11-12-universal
        ;;
    *) printf 'This legacy release only builds the universal macOS 11 and 12 app.\n' >&2; return 1 ;;
esac
profile_supported="11 and 12"
profile_xcode=$(cat "$profile_xcode_file")
profile_architectures=$(sed -n 's/^ARCHS *= *//p' "$profile_configuration")
profile_minimum=$(sed -n 's/^MACOSX_DEPLOYMENT_TARGET *= *//p' "$profile_configuration")
[[ -n "$profile_architectures" && -n "$profile_minimum" ]]
