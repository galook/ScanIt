#!/usr/bin/env bash
set -euo pipefail

IOS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export IOS_ROOT
cd "$IOS_ROOT"

# shellcheck source=tools/load-app-store-env.sh
source tools/load-app-store-env.sh

# shellcheck source=tools/use-xcode.sh
source tools/use-xcode.sh
command -v xcodegen >/dev/null 2>&1 || { echo "Install XcodeGen first." >&2; exit 1; }

unsigned=0
if [[ "${1:-}" == "--unsigned" ]]; then
  unsigned=1
elif [[ -n "${1:-}" ]]; then
  echo "usage: $0 [--unsigned]" >&2
  exit 2
fi

bash tools/validate_app_store.sh

version="${MARKETING_VERSION:-2.0}"
build_number="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
if (( unsigned )); then
  archive_path="$IOS_ROOT/build/FruitySelia-unsigned.xcarchive"
else
  archive_path="$IOS_ROOT/build/FruitySelia.xcarchive"
fi
export_path="$IOS_ROOT/build/export"

mkdir -p "$IOS_ROOT/build"
xcodegen generate

archive_command=(
  xcodebuild -project SeliaScan.xcodeproj -scheme SeliaScan
  -configuration Release -destination 'generic/platform=iOS'
  -archivePath "$archive_path"
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number"
  DEVELOPMENT_TEAM="${APPLE_TEAM_ID:-MTYBUX7QS6}"
)
export_command=(
  xcodebuild -exportArchive
  -archivePath "$archive_path"
  -exportPath "$export_path"
  -exportOptionsPlist ExportOptions.plist
)
if (( ! unsigned )); then
  # Use the Apple account already signed into Xcode to create or refresh
  # development provisioning needed for the archive. Export uses the exact
  # App Store profiles declared in ExportOptions.plist.
  archive_command+=(-allowProvisioningUpdates)
fi
if [[ -n "${APP_STORE_CONNECT_KEY_FILE:-}" && -n "${APP_STORE_CONNECT_KEY_ID:-}" && -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
  ruby tools/sync_app_store_profiles.rb
  authentication_args=(
    -authenticationKeyPath "$APP_STORE_CONNECT_KEY_FILE"
    -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID"
    -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID"
  )
  archive_command+=("${authentication_args[@]}")
fi

if (( unsigned )); then
  archive_command+=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
fi

"${archive_command[@]}" archive

if (( unsigned )); then
  echo "Unsigned archive validated: $archive_path"
  exit 0
fi

"${export_command[@]}"

echo "Exported: $export_path"
