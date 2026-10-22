#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -ne 2 ]]; then
    echo "Usage: bash scripts/release.sh <version X.Y.Z> <positive build number>" >&2
    exit 2
fi

version="$1"
build_number="$2"
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "Version must be a stable X.Y.Z version (for example, 1.2.3)." >&2
    exit 2
fi
if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
    echo "Build number must be a positive integer." >&2
    exit 2
fi

sparkle_key_args=()
if [[ -n "${TOBYSHOT_SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
    if [[ ! -r "$TOBYSHOT_SPARKLE_PRIVATE_KEY_FILE" ]]; then
        echo "TOBYSHOT_SPARKLE_PRIVATE_KEY_FILE must point to a readable Sparkle EdDSA private key file." >&2
        exit 2
    fi
    sparkle_key_args=(--ed-key-file "$TOBYSHOT_SPARKLE_PRIVATE_KEY_FILE")
else
    sparkle_key_args=(--account app.tobyshot.mac)
fi

release_repository="${TOBYSHOT_RELEASE_REPOSITORY:-TobiasRoland123/tobyshot}"
if [[ ! "$release_repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    echo "TOBYSHOT_RELEASE_REPOSITORY must be in owner/repository form." >&2
    exit 2
fi
feed_url="https://github.com/${release_repository}/releases/latest/download/appcast.xml"
download_url_prefix="https://github.com/${release_repository}/releases/download/v${version}/"

export TOBYSHOT_VERSION="$version"
export TOBYSHOT_BUILD_NUMBER="$build_number"
export TOBYSHOT_FEED_URL="$feed_url"
export TOBYSHOT_ARCHS="${TOBYSHOT_ARCHS:-arm64 x86_64}"
export TOBYSHOT_REQUIRE_PERSISTENT_SIGNING=1

dmg_python="${TOBYSHOT_PYTHON:-python3}"
if ! "$dmg_python" -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2>/dev/null; then
    echo "Building the DMG requires Python 3.10 or newer; set TOBYSHOT_PYTHON to its path." >&2
    exit 2
fi

bash scripts/build.sh release

app="$(pwd)/build/TobyShot.app"
release_dir="$(pwd)/build/release"
zip="$release_dir/TobyShot-${version}.zip"
dmg="$release_dir/TobyShot-${version}.dmg"
mkdir -p "$release_dir"

work_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/tobyshot-release.XXXXXX")"
cleanup() {
    rm -rf "$work_dir"
}
trap cleanup EXIT

make_zip() {
    /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$1"
}

if [[ -n "${TOBYSHOT_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    notary_args=(--keychain-profile "$TOBYSHOT_NOTARY_KEYCHAIN_PROFILE" --wait)
    if [[ -n "${TOBYSHOT_SIGNING_KEYCHAIN:-}" ]]; then
        notary_args+=(--keychain "$TOBYSHOT_SIGNING_KEYCHAIN")
    fi
    notarization_zip="$work_dir/notarization.zip"
    make_zip "$notarization_zip"
    /usr/bin/xcrun notarytool submit "$notarization_zip" "${notary_args[@]}"
    /usr/bin/xcrun stapler staple "$app"
    /usr/bin/xcrun stapler validate "$app"
fi

make_zip "$zip"

# The DMG opens as a fixed-size Finder window with an instruction background,
# TobyShot.app on the left, and an Applications link on the right.
source scripts/sdk.sh
dmg_background="$work_dir/dmg-background"
/usr/bin/xcrun swift -sdk "$tobyshot_sdk" scripts/dmg-background.swift "$dmg_background"
dmg_tools="$work_dir/dmg-tools"
"$dmg_python" -m venv "$dmg_tools"
"$dmg_tools/bin/python" -m pip install --quiet --disable-pip-version-check \
    --only-binary=:all: --require-hashes -r scripts/dmg-requirements.txt
rm -f "$dmg"
"$dmg_tools/bin/dmgbuild" -s scripts/dmg-settings.py \
    -D app="$app" -D background="$dmg_background/background.png" \
    "TobyShot ${version}" "$dmg"
/usr/bin/hdiutil verify -quiet "$dmg"

if [[ -n "${TOBYSHOT_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    /usr/bin/xcrun notarytool submit "$dmg" "${notary_args[@]}"
    /usr/bin/xcrun stapler staple "$dmg"
    /usr/bin/xcrun stapler validate "$dmg"
fi

sparkle_bin="$(pwd)/.build/artifacts/sparkle/Sparkle/bin"
if [[ ! -x "$sparkle_bin/generate_appcast" ]]; then
    echo "Could not find Sparkle's generate_appcast under .build/artifacts/sparkle; resolve the Sparkle package first." >&2
    exit 1
fi

appcast_input="$work_dir/appcast"
mkdir -p "$appcast_input"
cp "$zip" "$appcast_input/"
"$sparkle_bin/generate_appcast" "${sparkle_key_args[@]}" \
    --download-url-prefix "$download_url_prefix" "$appcast_input"
if ! /usr/bin/grep -Eq 'sparkle:edSignature="[^"]+"' "$appcast_input/appcast.xml"; then
    echo "Sparkle generated no signed enclosure; check that the private key matches SUPublicEDKey." >&2
    exit 1
fi
mv "$appcast_input/appcast.xml" "$release_dir/appcast.xml"

if [[ "${TOBYSHOT_GENERATE_SHA256SUMS:-1}" == "1" ]]; then
    (cd "$release_dir" && /usr/bin/shasum -a 256 "TobyShot-${version}.zip" "TobyShot-${version}.dmg" > SHA256SUMS)
fi

echo "Release artifacts written to $release_dir"
