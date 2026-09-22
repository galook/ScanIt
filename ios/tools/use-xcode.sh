#!/usr/bin/env bash

# Source this helper. Prefer the active developer directory, then standard Xcode.
if ! xcodebuild -version >/dev/null 2>&1; then
  if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  else
    echo "Full Xcode is required." >&2
    return 1
  fi
fi
