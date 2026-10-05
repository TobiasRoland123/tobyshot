#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift package resolve
tool=".build/artifacts/sparkle/Sparkle/bin/generate_keys"
account="app.tobyshot.mac"
plist="Resources/Info.plist"

# The private key stays in the login Keychain. Only its public half goes in Git.
existing_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist" 2>/dev/null || true)"
if [[ -n "$existing_key" ]]; then
    if ! public_key="$("$tool" --account "$account" -p)"; then
        echo "This app already has an update signing key. Import its original private key into this Mac's Keychain (account: $account) before releasing." >&2
        exit 1
    fi
else
    "$tool" --account "$account" >/dev/null
    public_key="$("$tool" --account "$account" -p)"
fi
if [[ -n "$existing_key" && "$existing_key" != "$public_key" ]]; then
    echo "This Mac's update signing key differs from the app's key. Import the original key; do not replace the public key in an already released app." >&2
    exit 1
fi
if [[ -z "$existing_key" ]]; then
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $public_key" "$plist"
fi
echo "Update signing is ready. The private key is in your login Keychain (account: $account)."
