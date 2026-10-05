#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-debug}"
source scripts/sdk.sh
bash scripts/build-icon.sh
# Local builds use this Mac's architecture. Releases build both slices.
architectures=()
if [[ -n "${TOBYSHOT_ARCHS:-}" ]]; then
    read -r -a architectures <<< "$TOBYSHOT_ARCHS"
else
    architectures=("$(uname -m)")
fi
binaries=()
for architecture in "${architectures[@]}"; do
    case "$architecture" in arm64|x86_64) ;; *) echo "Unsupported architecture: $architecture" >&2; exit 2 ;; esac
    swift build --sdk "$tobyshot_sdk" -c "$configuration" --arch "$architecture"
    binary_dir="$(swift build --sdk "$tobyshot_sdk" -c "$configuration" --arch "$architecture" --show-bin-path)"
    lipo -verify_arch "$architecture" "$binary_dir/TobyShot"
    # SwiftPM can reuse one product path across architectures. Save each slice
    # before building the next one, so lipo doesn't receive the same file twice.
    slice_dir="build/slices/$configuration/$architecture"
    mkdir -p "$slice_dir"
    cp "$binary_dir/TobyShot" "$slice_dir/TobyShot"
    binaries+=("$(pwd)/$slice_dir/TobyShot")
done
app="$(pwd)/build/TobyShot.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
if [[ ${#binaries[@]} -gt 1 ]]; then
    lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/TobyShot"
else
    cp "${binaries[0]}" "$app/Contents/MacOS/TobyShot"
fi
cp Resources/Info.plist "$app/Contents/Info.plist"
if [[ -n "${TOBYSHOT_VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $TOBYSHOT_VERSION" "$app/Contents/Info.plist"
fi
if [[ -n "${TOBYSHOT_BUILD_NUMBER:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $TOBYSHOT_BUILD_NUMBER" "$app/Contents/Info.plist"
fi
if [[ -n "${TOBYSHOT_FEED_URL:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :SUFeedURL $TOBYSHOT_FEED_URL" "$app/Contents/Info.plist"
fi
cp build/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp build/MenuBarIcon.tiff "$app/Contents/Resources/MenuBarIcon.tiff"
cp -R "$binary_dir/TobyShot_TobyShot.bundle" "$app/Contents/Resources/"
sparkle=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
ditto "$sparkle" "$app/Contents/Frameworks/Sparkle.framework"
cp .build/artifacts/sparkle/Sparkle/LICENSE "$app/Contents/Resources/Sparkle-LICENSE"
bash scripts/sign.sh "$app"
echo "Built $app"
