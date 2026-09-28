#!/bin/bash
# Source this file from build/test scripts. TOBYSHOT_SDK can override SDK selection.
tobyshot_sdk="${TOBYSHOT_SDK:-$(xcrun --show-sdk-path)}"
tobyshot_developer="$(xcode-select -p)"
# Some preview Command Line Tools ship the macOS 27 SDK without SwiftUI's macro
# plugin. Prefer the complete stable SDK when it is installed alongside it.
if [[ -z "${TOBYSHOT_SDK:-}" && "$(xcrun --show-sdk-version)" == 27* && ! -f "$tobyshot_developer/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib" && -d "$tobyshot_developer/SDKs/MacOSX26.5.sdk" ]]; then
    tobyshot_sdk="$tobyshot_developer/SDKs/MacOSX26.5.sdk"
fi
