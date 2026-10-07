#!/usr/bin/env bash
#
# Shared helpers for the .codex scripts. Sourced, not executed.
# Derived from the scripts in redmine_parent_child_filters; generic for any plugin.
#
# Environment:
#   REDMINE_DIR     checkout to work in (default: redmine, relative to the plugin root)
#   MISE_BIN        mise executable, used only when it is present
#   RMP_RUBY        pin the Ruby version instead of deriving it from the Gemfile
#   RMP_RUBY_MAX    newest Ruby that actually exists (default: 3.4)

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REDMINE_DIR="${REDMINE_DIR:-$PLUGIN_ROOT/redmine}"
MISE_BIN="${MISE_BIN:-mise}"
RMP_RUBY_MAX="${RMP_RUBY_MAX:-3.4}"

# Redmine loads a plugin from plugins/<id>, where <id> is the name passed to
# Redmine::Plugin.register. That is not always the repository name
# (bless-this-redmine-sso, redmine-view-customize, redmine_tags ...), so read it.
# shellcheck disable=SC2034
PLUGIN_NAME="$(sed -n -E "s/^[[:space:]]*Redmine::Plugin\.register[[:space:](]*:?['\"]?([a-z0-9_]+).*/\1/p" "$PLUGIN_ROOT/init.rb" | head -n 1)"
[ -n "$PLUGIN_NAME" ] || PLUGIN_NAME="$(basename "$PLUGIN_ROOT")"

# Compares two "major.minor" strings. Returns 0 when $1 <= $2.
rmp_version_le() {
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n | head -n 1)" = "$1" ]
}

# Redmine pins a range rather than a version, so derive one just below the upper
# bound, clamped to RMP_RUBY_MAX and floored at the lower bound.
rmp_detect_ruby_version() {
  local gemfile="$REDMINE_DIR/Gemfile" line lower upper major minor candidate

  if [ -n "${RMP_RUBY:-}" ]; then
    echo "$RMP_RUBY"
    return 0
  fi

  [ -f "$gemfile" ] || return 0

  line="$(grep -E "^[[:space:]]*ruby[[:space:]]" "$gemfile" | head -n 1 || true)"
  [ -n "$line" ] || return 0

  lower="$(printf '%s' "$line" | sed -E -n "s/.*>=[[:space:]]*['\"]([0-9]+\.[0-9]+).*/\1/p")"
  upper="$(printf '%s' "$line" | sed -E -n "s/.*<[[:space:]]*['\"]?([0-9]+)\.([0-9]+).*/\1.\2/p")"

  if [ -n "$upper" ]; then
    major="${upper%%.*}"
    minor="${upper##*.}"
    [ "$minor" -gt 0 ] && minor=$((minor - 1))
    candidate="${major}.${minor}"
  else
    candidate="$lower"
  fi

  [ -n "$candidate" ] || return 0
  rmp_version_le "$candidate" "$RMP_RUBY_MAX" || candidate="$RMP_RUBY_MAX"
  if [ -n "$lower" ] && ! rmp_version_le "$lower" "$candidate"; then
    candidate="$lower"
  fi

  echo "$candidate"
}

# Sets RUBY_TARGET and USE_MISE. Pass "install" to let mise fetch the Ruby.
rmp_select_ruby() {
  local mode="${1:-}"

  RUBY_TARGET="$(rmp_detect_ruby_version)"
  USE_MISE=0

  if [ -n "$RUBY_TARGET" ] && command -v "$MISE_BIN" >/dev/null 2>&1; then
    if [ "$mode" = install ]; then
      "$MISE_BIN" install "ruby@$RUBY_TARGET"
      echo "Using Ruby $RUBY_TARGET through mise."
    fi
    USE_MISE=1
  elif [ -n "$RUBY_TARGET" ] && [ "$mode" = install ]; then
    echo "mise not found; using the Ruby already on PATH ($(ruby -e 'print RUBY_VERSION' 2>/dev/null || echo 'none'))."
    echo "This checkout expects Ruby ~$RUBY_TARGET; bundler will complain if it does not fit."
  fi

  # Never let the function's status be the status of its last test (a `[ ] && echo`
  # at the end once killed the callers under set -e without a word).
  return 0
}

# Runs a command inside the Redmine checkout, through mise when it is in use.
run() {
  if [ "${USE_MISE:-0}" = 1 ]; then
    (cd "$REDMINE_DIR" && "$MISE_BIN" exec "ruby@$RUBY_TARGET" -- "$@")
  else
    (cd "$REDMINE_DIR" && "$@")
  fi
}
