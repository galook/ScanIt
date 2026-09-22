#!/usr/bin/env bash
set -euo pipefail

IOS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$IOS_ROOT"

ruby_command=""
if command -v brew >/dev/null 2>&1; then
  brew_ruby="$(brew --prefix ruby 2>/dev/null)/bin/ruby"
  [[ -x "$brew_ruby" ]] && ruby_command="$brew_ruby"
fi
if [[ -z "$ruby_command" ]]; then
  candidate="$(command -v ruby || true)"
  if [[ -n "$candidate" ]] && "$candidate" -e 'exit Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.1") ? 0 : 1'; then
    ruby_command="$candidate"
  fi
fi
if [[ -z "$ruby_command" ]]; then
  command -v brew >/dev/null 2>&1 || { echo "Ruby 3.1+ is required. Install it, then rerun." >&2; exit 1; }
  brew install ruby
  ruby_command="$(brew --prefix ruby)/bin/ruby"
fi

gem_command="$(dirname "$ruby_command")/gem"
bundle_command="$(dirname "$ruby_command")/bundle"
if [[ ! -x "$bundle_command" ]]; then
  "$gem_command" install bundler --no-document
fi

"$bundle_command" config set --local path vendor/bundle
"$bundle_command" install
echo "Copy .env.appstore.example to .env.appstore, then fill App Store Connect values."
