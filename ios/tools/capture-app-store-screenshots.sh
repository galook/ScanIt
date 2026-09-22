#!/usr/bin/env bash
set -euo pipefail

IOS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$IOS_ROOT"

# shellcheck source=tools/use-xcode.sh
source tools/use-xcode.sh
command -v xcodegen >/dev/null 2>&1 || { echo "Install XcodeGen first." >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; exit 1; }

find_device() {
  local family_regex="$1"
  local override="${2:-}"
  xcrun simctl list devices available -j | jq -r --arg regex "$family_regex" --arg override "$override" '
    [.devices[][] | select(.isAvailable == true) | select(
      (if $override == "" then (.name | test($regex)) else .name == $override end)
    )] | last | .udid // empty
  '
}

iphone_udid="$(find_device 'iPhone .*Pro Max$' "${IPHONE_SCREENSHOT_DEVICE:-}")"
ipad_udid="$(find_device 'iPad Pro 13-inch' "${IPAD_SCREENSHOT_DEVICE:-}")"
[[ -n "$iphone_udid" ]] || { echo "No 6.9-inch Pro Max simulator found. Set IPHONE_SCREENSHOT_DEVICE." >&2; exit 1; }
[[ -n "$ipad_udid" ]] || { echo "No 13-inch iPad Pro simulator found. Set IPAD_SCREENSHOT_DEVICE." >&2; exit 1; }

xcodegen generate
mkdir -p build/screenshots fastlane/screenshots

locales=(en-US cs-CZ de-DE es-ES zh-Hans)
if [[ -n "${SCREENSHOT_LOCALES:-}" ]]; then
  read -r -a locales <<<"$SCREENSHOT_LOCALES"
fi

capture() {
  local store_locale="$1"
  local test_language="$2"
  local test_region="$3"
  local form_factor="$4"
  local udid="$5"
  local result_bundle="$IOS_ROOT/build/screenshots/${store_locale}-${form_factor}.xcresult"
  local raw_dir="$IOS_ROOT/build/screenshots/${store_locale}-${form_factor}-attachments"
  local output_dir="$IOS_ROOT/fastlane/screenshots/$store_locale"

  rm -rf "$result_bundle" "$raw_dir"
  mkdir -p "$raw_dir" "$output_dir"
  find "$output_dir" -maxdepth 1 -type f -name "${form_factor}-*.png" -delete

  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b
  xcrun simctl uninstall "$udid" com.majkeylab.seliascan 2>/dev/null || true
  xcrun simctl status_bar "$udid" override \
    --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4
  SCREENSHOT_LABEL="${store_locale}-${form_factor}" xcodebuild \
    -project SeliaScan.xcodeproj -scheme SeliaScan \
    -destination "platform=iOS Simulator,id=$udid" \
    -only-testing:SeliaScanUITests/AppStoreScreenshotTests/testStoreScreenshots \
    -testLanguage "$test_language" -testRegion "$test_region" \
    -resultBundlePath "$result_bundle" CODE_SIGNING_ALLOWED=NO test

  xcrun xcresulttool export attachments --path "$result_bundle" --output-path "$raw_dir"
  local count=0
  while IFS=$'\t' read -r index slug exported_name; do
    [[ -n "$index" && -n "$slug" && -n "$exported_name" ]] || continue
    cp "$raw_dir/$exported_name" "$output_dir/${form_factor}-${index}-${slug}.png"
    count=$((count + 1))
  done < <(
    jq -r '
      .[].attachments[]
      | select(.exportedFileName | endswith(".png"))
      | .suggestedHumanReadableName as $name
      | ($name | capture("(?<index>[0-9]{2})-(?<slug>[A-Za-z0-9-]+)_")) as $label
      | [$label.index, $label.slug, .exportedFileName]
      | @tsv
    ' "$raw_dir/manifest.json" | sort
  )
  [[ "$count" -eq 6 ]] || {
    echo "Expected 6 named screenshots for $store_locale/$form_factor; exported $count." >&2
    exit 1
  }
}

for locale in "${locales[@]}"; do
  case "$locale" in
    en-US) language=en; region=US; store_locale=en-US ;;
    cs|cs-CZ) language=cs; region=CZ; store_locale=cs ;;
    de-DE) language=de; region=DE; store_locale=de-DE ;;
    es-ES) language=es; region=ES; store_locale=es-ES ;;
    zh-Hans) language=zh-Hans; region=CN; store_locale=zh-Hans ;;
    *) echo "Unsupported locale: $locale" >&2; exit 2 ;;
  esac
  capture "$store_locale" "$language" "$region" iphone-6.9 "$iphone_udid"
  capture "$store_locale" "$language" "$region" ipad-13 "$ipad_udid"
done

echo "Screenshots saved under $IOS_ROOT/fastlane/screenshots"
