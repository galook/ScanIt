#!/usr/bin/env bash
set -euo pipefail

if command -v brew >/dev/null 2>&1; then
  ruby_prefix="$(brew --prefix ruby 2>/dev/null || true)"
  brew_bundle="${ruby_prefix}/bin/bundle"
  if [[ -n "$ruby_prefix" && -x "$brew_bundle" ]]; then
    exec "$brew_bundle" "$@"
  fi
fi

if command -v ruby >/dev/null 2>&1 && ruby -e 'exit Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.1") ? 0 : 1' && command -v bundle >/dev/null 2>&1; then
  exec bundle "$@"
fi

echo "Ruby 3.1+ with Bundler is required. Run: bash tools/bootstrap-release.sh" >&2
exit 1
