#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-debug}"
source scripts/sdk.sh
bash scripts/build-icon.sh
swift build --sdk "$tobyshot_sdk" -c "$configuration"
binary_dir="$(swift build --sdk "$tobyshot_sdk" -c "$configuration" --show-bin-path)"
app="$(pwd)/build/TobyShot.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/TobyShot" "$app/Contents/MacOS/TobyShot"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp build/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp build/MenuBarIcon.tiff "$app/Contents/Resources/MenuBarIcon.tiff"
cp -R "$binary_dir/TobyShot_TobyShot.bundle" "$app/Contents/Resources/"
bash scripts/sign.sh "$app"
echo "Built $app"
