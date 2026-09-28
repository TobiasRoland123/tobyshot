#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/sdk.sh
tobyshot_testing_plugins="$tobyshot_developer/usr/lib/swift/host/plugins/testing"
if [[ -d "$tobyshot_testing_plugins" ]]; then
    swift test --sdk "$tobyshot_sdk" --disable-xctest \
        -Xswiftc -external-plugin-path \
        -Xswiftc "$tobyshot_testing_plugins#$tobyshot_developer/usr/bin/swift-plugin-server"
else
    swift test --sdk "$tobyshot_sdk" --disable-xctest
fi
