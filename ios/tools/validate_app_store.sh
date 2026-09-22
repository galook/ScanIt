#!/usr/bin/env bash
set -euo pipefail

IOS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export IOS_ROOT
cd "$IOS_ROOT"

# shellcheck source=tools/load-app-store-env.sh
source tools/load-app-store-env.sh

submission=0
if [[ "${1:-}" == "--submission" ]]; then
  submission=1
elif [[ -n "${1:-}" ]]; then
  echo "usage: $0 [--submission]" >&2
  exit 2
fi

failures=0
fail() { echo "error: $*" >&2; failures=$((failures + 1)); }
need_command() { command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"; }

need_command plutil
need_command jq
need_command ruby
need_command sips
need_command xcodegen

plutil -lint SeliaScan/Resources/Info.plist SeliaScanControls/Info.plist SeliaScan/Resources/PrivacyInfo.xcprivacy >/dev/null || fail "invalid plist"
jq empty SeliaScan/Resources/InfoPlist.xcstrings SeliaScan/Resources/Localizable.xcstrings fastlane/metadata/app_rating_config.json AppStore/submission-data.json || fail "invalid release JSON"
ruby tools/validate_app_store.rb || failures=$((failures + 1))

[[ "$(plutil -extract ITSAppUsesNonExemptEncryption raw SeliaScan/Resources/Info.plist)" == "false" ]] || fail "export-compliance flag must be false"
grep -q 'NSPrivacyAccessedAPICategoryUserDefaults' SeliaScan/Resources/PrivacyInfo.xcprivacy || fail "UserDefaults required-reason declaration missing"
grep -q 'NSPrivacyAccessedAPICategoryFileTimestamp' SeliaScan/Resources/PrivacyInfo.xcprivacy || fail "file timestamp required-reason declaration missing"

icon="SeliaScan/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
[[ -f "$icon" ]] || fail "1024px App Store icon missing"
if [[ -f "$icon" ]]; then
  icon_info="$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$icon" 2>/dev/null)"
  grep -q 'pixelWidth: 1024' <<<"$icon_info" || fail "App Store icon width must be 1024"
  grep -q 'pixelHeight: 1024' <<<"$icon_info" || fail "App Store icon height must be 1024"
  grep -q 'hasAlpha: no' <<<"$icon_info" || fail "App Store icon must not contain alpha"
fi

if rg -n 'SeliaScan' SeliaScan/Resources/InfoPlist.xcstrings SeliaScan/Resources/Localizable.xcstrings >/dev/null; then
  fail "old user-facing SeliaScan brand remains in String Catalogs"
fi

xcodegen generate --spec project.yml >/dev/null || fail "XcodeGen generation failed"

for page in index.html privacy.html support.html; do
  page_path="$IOS_ROOT/../docs/fruityselia/$page"
  [[ -s "$page_path" ]] || { fail "missing public page source: docs/fruityselia/$page"; continue; }
  grep -q '<title>.*FruitySelia.*</title>' "$page_path" || fail "FruitySelia title missing: docs/fruityselia/$page"
done

if [[ "${REQUIRE_SCREENSHOTS:-1}" == "1" ]]; then
  screens=(01-result 02-viewer 03-actions 04-sign-stamp 05-file-details 06-recent)
  for locale in en-US cs de-DE es-ES zh-Hans; do
    count="$(find "fastlane/screenshots/$locale" -maxdepth 1 -type f -name '*.png' 2>/dev/null | wc -l | tr -d ' ')"
    [[ "$count" -eq 12 ]] || fail "need exactly 12 screenshots for $locale; found $count"
    for form_factor in iphone-6.9 ipad-13; do
      if [[ "$form_factor" == "iphone-6.9" ]]; then
        expected_width=1320
        expected_height=2868
      else
        expected_width=2064
        expected_height=2752
      fi
      for screen in "${screens[@]}"; do
        screenshot="fastlane/screenshots/$locale/$form_factor-$screen.png"
        if [[ ! -f "$screenshot" ]]; then
          fail "missing screenshot: $screenshot"
          continue
        fi
        screenshot_info="$(sips -g pixelWidth -g pixelHeight "$screenshot" 2>/dev/null)"
        grep -q "pixelWidth: $expected_width" <<<"$screenshot_info" || fail "wrong width: $screenshot"
        grep -q "pixelHeight: $expected_height" <<<"$screenshot_info" || fail "wrong height: $screenshot"
      done
    done
  done
fi

if (( submission )); then
  phone_file="fastlane/metadata/review_information/phone_number.txt"
  [[ -s "$phone_file" ]] || fail "create $phone_file from its .example with real App Review phone"
  [[ -n "${APP_STORE_CONNECT_KEY_ID:-}" ]] || fail "APP_STORE_CONNECT_KEY_ID missing"
  [[ -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]] || fail "APP_STORE_CONNECT_ISSUER_ID missing"
  [[ -f "${APP_STORE_CONNECT_KEY_FILE:-/missing}" ]] || fail "APP_STORE_CONNECT_KEY_FILE missing or unreadable"
  [[ -n "${APP_STORE_APP_ID:-}" ]] || fail "APP_STORE_APP_ID missing"
  need_command curl
  while IFS= read -r url; do
    curl --fail --silent --show-error --location --max-time 20 "$url" >/dev/null || fail "public URL unavailable: $url"
  done < <(find fastlane/metadata/en-US -type f -name '*_url.txt' -exec sed -e 's/[[:space:]]*$//' {} + | sort -u)
fi

if (( failures > 0 )); then
  echo "$failures release validation check(s) failed." >&2
  exit 1
fi

echo "App Store release validation: OK"
