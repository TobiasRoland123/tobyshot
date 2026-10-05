#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -ne 1 || ! -e "$1" ]]; then
    echo "Usage: bash scripts/sign.sh <app-or-binary>" >&2
    exit 2
fi

target="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
identifier="app.tobyshot.mac"

sign_components() {
    local signing_identity="$1"
    local signing_keychain="${2:-}"
    local options=(--force --sign "$signing_identity")
    [[ -z "$signing_keychain" ]] || options+=(--keychain "$signing_keychain")
    if [[ "${TOBYSHOT_DISTRIBUTION:-0}" == 1 && "$signing_identity" != - ]]; then
        options+=(--options runtime --timestamp)
    fi
    local framework="$target/Contents/Frameworks/Sparkle.framework"
    if [[ -d "$framework" ]]; then
        local component
        for component in \
            "$framework/Versions/B/XPCServices/Downloader.xpc" \
            "$framework/Versions/B/XPCServices/Installer.xpc" \
            "$framework/Versions/B/Autoupdate" \
            "$framework/Versions/B/Updater.app" \
            "$framework"; do
            /usr/bin/codesign "${options[@]}" --preserve-metadata=entitlements "$component"
        done
    fi
    /usr/bin/codesign "${options[@]}" --identifier "$identifier" "$target"
}

if [[ -n "${TOBYSHOT_SIGNING_IDENTITY:-}" ]]; then
    sign_components "$TOBYSHOT_SIGNING_IDENTITY" "${TOBYSHOT_SIGNING_KEYCHAIN:-}"
else
    signing_dir="$(pwd)/.local-signing"
    keychain="$signing_dir/tobyshot-signing.keychain-db"
    password_file="$signing_dir/keychain-password"
    label="TobyShot Local Development"
    mkdir -p "$signing_dir"
    chmod 700 "$signing_dir"

    if [[ ! -e "$keychain" && ! -e "$password_file" ]]; then
        password="$(/usr/bin/openssl rand -hex 32)"
        umask 077
        printf '%s' "$password" > "$password_file"
        chmod 600 "$password_file"
        /usr/bin/security create-keychain -p "$password" "$keychain"
        chmod 600 "$keychain"
        /usr/bin/security set-keychain-settings -lut 21600 "$keychain"

        temporary_dir="$(/usr/bin/mktemp -d "$signing_dir/certificate.XXXXXX")"
        chmod 700 "$temporary_dir"
        trap 'rm -rf "$temporary_dir"' EXIT
        /usr/bin/openssl req -new -x509 -nodes -newkey rsa:3072 -sha256 -days 36500 \
            -subj "/CN=$label" \
            -addext "keyUsage=critical,digitalSignature" \
            -addext "extendedKeyUsage=critical,codeSigning" \
            -keyout "$temporary_dir/private-key.pem" \
            -out "$temporary_dir/certificate.pem" >/dev/null 2>&1
        chmod 600 "$temporary_dir/private-key.pem" "$temporary_dir/certificate.pem"
        /usr/bin/openssl pkcs12 -export \
            -inkey "$temporary_dir/private-key.pem" \
            -in "$temporary_dir/certificate.pem" \
            -out "$temporary_dir/identity.p12" \
            -name "$label" \
            -passout "pass:$password" >/dev/null 2>&1
        chmod 600 "$temporary_dir/identity.p12"
        /usr/bin/security import "$temporary_dir/identity.p12" -k "$keychain" \
            -P "$password" -T /usr/bin/codesign >/dev/null
        /usr/bin/security set-key-partition-list -S apple-tool: -s -k "$password" "$keychain" >/dev/null
        cp "$temporary_dir/certificate.pem" "$signing_dir/certificate.pem"
        rm -rf "$temporary_dir"
        trap - EXIT
    elif [[ ! -f "$keychain" || ! -f "$password_file" ]]; then
        echo "Local signing setup is incomplete in $signing_dir; preserve it and inspect it before repairing." >&2
        exit 1
    fi

    password="$(cat "$password_file")"
    /usr/bin/security unlock-keychain -p "$password" "$keychain"
    identity="$(/usr/bin/security find-identity -v -p codesigning "$keychain" | awk -v label="$label" '$0 ~ label { print $2; exit }')"
    if [[ -z "$identity" ]]; then
        echo "The local certificate exists, but macOS has not trusted it for code signing." >&2
        echo "See README.md for the one-time local signing setup, or set TOBYSHOT_SIGNING_IDENTITY to an existing Apple identity." >&2
        exit 1
    fi

    # codesign also needs the keychain on the search list to resolve its private
    # key, even with --keychain. Remove only our temporary entry on exit.
    keychains=()
    already_listed=false
    while IFS= read -r entry; do
        entry="${entry#*\"}"; entry="${entry%\"*}"
        keychains+=("$entry")
        [[ "$entry" != "$keychain" ]] || already_listed=true
    done < <(/usr/bin/security list-keychains -d user)
    if [[ "$already_listed" == false ]]; then
        restore_search_list() {
            remaining=()
            while IFS= read -r entry; do
                entry="${entry#*\"}"; entry="${entry%\"*}"
                [[ "$entry" == "$keychain" ]] || remaining+=("$entry")
            done < <(/usr/bin/security list-keychains -d user)
            /usr/bin/security list-keychains -d user -s "${remaining[@]}"
        }
        trap restore_search_list EXIT
        /usr/bin/security list-keychains -d user -s "${keychains[@]}" "$keychain"
    fi
    sign_components "$identity" "$keychain"
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$target"
