#!/usr/bin/env bash

# Source this file from another script. It loads ignored local credentials when present.
set -o allexport
if [[ -f "${IOS_ROOT}/.env.appstore" ]]; then
  # shellcheck disable=SC1091
  source "${IOS_ROOT}/.env.appstore"
fi
set +o allexport
