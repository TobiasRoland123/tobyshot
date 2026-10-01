#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

source_icon="Resources/Branding/tobyshot-dark-glass-app-icon.png"
iconset="build/AppIcon.iconset"
mkdir -p "$iconset"

for size in 16 32 128 256 512; do
    sips --resampleHeightWidth "$size" "$size" "$source_icon" \
        --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips --resampleHeightWidth "$retina_size" "$retina_size" "$source_icon" \
        --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil --convert icns "$iconset" --output build/AppIcon.icns

menu_bar_source="Resources/Branding/tobyshot-dark-glass-menubar.png"
menu_bar_images="build/MenuBarIcon"
mkdir -p "$menu_bar_images"
sips --resampleHeightWidth 18 18 "$menu_bar_source" \
    --out "$menu_bar_images/MenuBarIcon.png" >/dev/null
sips --resampleHeightWidth 36 36 "$menu_bar_source" \
    --out "$menu_bar_images/MenuBarIcon@2x.png" >/dev/null
tiffutil -cathidpicheck "$menu_bar_images/MenuBarIcon.png" \
    "$menu_bar_images/MenuBarIcon@2x.png" -out build/MenuBarIcon.tiff >/dev/null
