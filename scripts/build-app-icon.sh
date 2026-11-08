#!/bin/bash
set -euo pipefail

# Xcode supplies these paths for the main app target.  Keep generated files out
# of the source tree, and use only the image tools that ship with macOS.
: "${SRCROOT:?}"
: "${DERIVED_FILE_DIR:?}"
: "${AS_APP_ICON_NAME:?}"
work="$DERIVED_FILE_DIR/AppIconBuild"
mkdir -p "$work"

case "$AS_APP_ICON_NAME" in
    application)
        iconset="$SRCROOT/application.iconset"
        ;;
    application-modern)
        source_image="$SRCROOT/Graphics/application-modern.png"
        iconset="$work/application-modern.iconset"
        mkdir -p "$iconset"
        for size in 16 32 128 256 512; do
            /usr/bin/sips --setProperty format png --resampleHeightWidth "$size" "$size" \
                "$source_image" --out "$iconset/icon_${size}x${size}.png" >/dev/null
            retina=$((size * 2))
            /usr/bin/sips --setProperty format png --resampleHeightWidth "$retina" "$retina" \
                "$source_image" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
        done
        ;;
    *) printf 'Unsupported app icon: %s\n' "$AS_APP_ICON_NAME" >&2; exit 1 ;;
esac

/usr/bin/iconutil --convert icns --output "$DERIVED_FILE_DIR/$AS_APP_ICON_NAME.icns" "$iconset"
printf 'Built %s.icns\n' "$AS_APP_ICON_NAME"
