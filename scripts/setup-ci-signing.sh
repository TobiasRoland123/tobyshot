#!/bin/bash
set +x
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."

signing_dir="$(pwd)/.local-signing"
keychain="$signing_dir/tobyshot-signing.keychain-db"
password_file="$signing_dir/keychain-password"
certificate="$signing_dir/certificate.pem"
repository="${TOBYSHOT_RELEASE_REPOSITORY:-TobiasRoland123/tobyshot}"

for command in gh security openssl base64 awk mktemp tr; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Required command not found: $command" >&2
        exit 1
    fi
done

if [[ ! -f "$keychain" || ! -s "$keychain" || ! -f "$password_file" || ! -s "$password_file" || ! -f "$certificate" || ! -s "$certificate" ]]; then
    echo "Local signing setup is missing or incomplete in $signing_dir; initialize it with scripts/sign.sh first." >&2
    exit 1
fi

if [[ ! "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    echo "Invalid GitHub repository: $repository (expected OWNER/REPO)." >&2
    exit 1
fi
if ! gh repo view "$repository" --json nameWithOwner --jq .nameWithOwner >/dev/null; then
    echo "Cannot access GitHub repository $repository; check gh authentication and repository access." >&2
    exit 1
fi

password="$(cat "$password_file")"
if [[ -z "$password" ]]; then
    echo "The local signing Keychain password is empty." >&2
    exit 1
fi
/usr/bin/security unlock-keychain -p "$password" "$keychain" >/dev/null

fingerprint="$(/usr/bin/openssl x509 -in "$certificate" -noout -fingerprint -sha1 | awk -F= '{ gsub(/:/, "", $2); print toupper($2) }')"
if [[ ! "$fingerprint" =~ ^[[:xdigit:]]{40}$ ]]; then
    echo "Could not read a SHA-1 fingerprint from $certificate." >&2
    exit 1
fi
configured_fingerprint="$(printf '%s' "${TOBYSHOT_SIGNING_IDENTITY:-}" | tr '[:lower:]' '[:upper:]')"
if [[ -n "$configured_fingerprint" && "$configured_fingerprint" != "$fingerprint" ]]; then
    echo "TOBYSHOT_SIGNING_IDENTITY does not match the local public certificate." >&2
    exit 1
fi

certificates="$(/usr/bin/security find-certificate -a -Z "$keychain" 2>/dev/null)"
certificate_count="$(printf '%s\n' "$certificates" | awk '/^SHA-1 hash:/ { count++ } END { print count+0 }')"
certificate_fingerprints="$(printf '%s\n' "$certificates" | awk '/^SHA-1 hash:/ { print toupper($3) }')"
codesigning_identities="$(/usr/bin/security find-identity -v -p codesigning "$keychain" 2>/dev/null)"
codesigning_count="$(printf '%s\n' "$codesigning_identities" | awk '/^[[:space:]]*[0-9]+\)/ { count++ } END { print count+0 }')"
codesigning_fingerprints="$(printf '%s\n' "$codesigning_identities" | awk '/^[[:space:]]*[0-9]+\)/ { print toupper($2) }')"
if [[ "$certificate_count" != 1 || "$certificate_fingerprints" != "$fingerprint" || "$codesigning_count" != 1 || "$codesigning_fingerprints" != "$fingerprint" ]]; then
    echo "The dedicated local signing Keychain must contain exactly the TobyShot signing identity ($fingerprint); refusing to export it." >&2
    exit 1
fi

temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/tobyshot-ci-signing.XXXXXX")"
trap 'rm -rf "$temporary_dir"' EXIT
chmod 700 "$temporary_dir"
p12_path="$temporary_dir/tobyshot-signing.p12"
export_password="$(/usr/bin/openssl rand -hex 32)"
echo "If macOS asks for this signing Keychain's password, use the saved value in $password_file." >&2
export_errors="$temporary_dir/export-errors.log"
if ! /usr/bin/security export -t identities -f pkcs12 -k "$keychain" -P "$export_password" -o "$p12_path" >/dev/null 2>"$export_errors"; then
    echo "Could not export the TobyShot signing identity from its local Keychain." >&2
    cat "$export_errors" >&2
    exit 1
fi
chmod 600 "$p12_path"

/usr/bin/base64 < "$p12_path" | tr -d '\n' | gh secret set TOBYSHOT_CERTIFICATE_P12_BASE64 --repo "$repository"
printf '%s' "$export_password" | gh secret set TOBYSHOT_CERTIFICATE_PASSWORD --repo "$repository"
printf '%s' "$fingerprint" | gh secret set TOBYSHOT_SIGNING_IDENTITY --repo "$repository"

echo "GitHub Actions signing secrets are set for $repository."
