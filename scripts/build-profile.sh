#!/bin/bash
# Source this file before building or checking either app edition.
profile_repository=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
profile_variant=${1:-universal}
case "$profile_variant" in
    universal)
        profile_scheme=AlphaSyncUniversal
        profile_configuration="$profile_repository/AlphaSync/Build/Universal.xcconfig"
        profile_label=macOS-13-universal
        ;;
    apple-silicon)
        profile_scheme=AlphaSyncAppleSilicon
        profile_configuration="$profile_repository/AlphaSync/Build/AppleSilicon.xcconfig"
        profile_label=macOS-13-apple-silicon
        ;;
    *) printf 'Choose universal or apple-silicon.\n' >&2; return 1 ;;
esac
profile_debug=Debug
profile_release=Release
profile_supported='13 and later'
profile_xcode=$(cat "$profile_repository/.xcode-version")
profile_architectures=$(sed -n 's/^ARCHS *= *//p' "$profile_configuration")
profile_minimum=$(sed -n 's/^MACOSX_DEPLOYMENT_TARGET *= *//p' "$profile_configuration")
[[ -n "$profile_architectures" && -n "$profile_minimum" ]]
