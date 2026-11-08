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
        profile_label=macOS-11-26-universal
        ;;
    modern)
        profile_scheme=AlphaSync-Modern
        profile_debug=DebugModern
        profile_release=ReleaseModern
        profile_xcode_file="$profile_repository/.xcode-version-modern"
        profile_configuration="$profile_repository/AlphaSync/Build/Modern.xcconfig"
        profile_label=macOS-27-apple-silicon
        ;;
    *) printf 'Unknown build profile: %s.  Use universal or modern.\n' "$profile_variant" >&2; return 1 ;;
esac
profile_xcode=$(cat "$profile_xcode_file")
profile_architectures=$(sed -n 's/^ARCHS *= *//p' "$profile_configuration")
profile_minimum=$(sed -n 's/^MACOSX_DEPLOYMENT_TARGET *= *//p' "$profile_configuration")
[[ -n "$profile_architectures" && -n "$profile_minimum" ]]
