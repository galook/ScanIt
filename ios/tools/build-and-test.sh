#!/usr/bin/env bash
set -euo pipefail

IOS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$IOS_ROOT"

# shellcheck source=tools/use-xcode.sh
source tools/use-xcode.sh
command -v xcodegen >/dev/null 2>&1 || { echo "Install XcodeGen first." >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; exit 1; }

xcodegen generate
xcodebuild -project SeliaScan.xcodeproj -scheme SeliaScan \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

device_id="$(xcrun simctl list devices available -j | jq -r '[.devices[][] | select(.isAvailable == true and (.name | startswith("iPhone")))] | first | .udid // empty')"
[[ -n "$device_id" ]] || { echo "No available iPhone simulator found." >&2; exit 1; }
xcodebuild -project SeliaScan.xcodeproj -scheme SeliaScan \
  -destination "platform=iOS Simulator,id=$device_id" CODE_SIGNING_ALLOWED=NO test
