#!/usr/bin/env bash
set -euo pipefail

IOS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$IOS_ROOT"

# shellcheck source=tools/use-xcode.sh
source tools/use-xcode.sh
command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; exit 1; }

device_id="$(xcrun simctl list devices available --json | jq -r 'first(.devices[] | .[] | select(.isAvailable and (.name | startswith("iPhone"))) | .udid) // empty')"
[[ -n "$device_id" ]] || { echo "No available iPhone simulator found." >&2; exit 1; }

destination="platform=iOS Simulator,id=$device_id"
xcrun simctl boot "$device_id" 2>/dev/null || true
xcrun simctl bootstatus "$device_id" -b

xcodebuild -project SeliaScan.xcodeproj -scheme SeliaScan \
  -destination "$destination" CODE_SIGNING_ALLOWED=NO \
  test -only-testing:SeliaScanTests

ui_log="$(mktemp -t fruityselia-ui-tests.XXXXXX)"
trap 'rm -f "$ui_log"' EXIT

set +e
xcodebuild -project SeliaScan.xcodeproj -scheme SeliaScan \
  -destination "$destination" CODE_SIGNING_ALLOWED=NO \
  test -only-testing:SeliaScanUITests 2>&1 | tee "$ui_log"
ui_status="${PIPESTATUS[0]}"
set -e

if [[ "$ui_status" -eq 0 ]]; then
  exit 0
fi

if ! grep -Eq 'failed to initialize for UI testing|XCTDaemonErrorDomain Code=19|kAXErrorCannotComplete' "$ui_log"; then
  exit "$ui_status"
fi

echo "UI test runner initialization failed; rebooting the simulator and retrying once." >&2
xcrun simctl shutdown "$device_id" || true
xcrun simctl boot "$device_id"
xcrun simctl bootstatus "$device_id" -b

xcodebuild -project SeliaScan.xcodeproj -scheme SeliaScan \
  -destination "$destination" CODE_SIGNING_ALLOWED=NO \
  test -only-testing:SeliaScanUITests
