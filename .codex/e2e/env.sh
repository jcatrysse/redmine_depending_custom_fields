#!/usr/bin/env bash
#
# Shared by start_server.sh, e2e.sh and openai_review.sh. Sourced, not executed.
# Self-contained on purpose: some repos carry an older .codex variant whose
# common.sh uses other names, so this only borrows its Ruby selection when the
# shared variant (rmp_select_ruby) is there.
#
#   REDMINE_DIR   Redmine checkout made by redmine_clone.sh (default: <plugin>/redmine)

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REDMINE_DIR="${REDMINE_DIR:-$PLUGIN_ROOT/redmine}"
case "$REDMINE_DIR" in /*) ;; *) REDMINE_DIR="$PLUGIN_ROOT/$REDMINE_DIR" ;; esac

# The id passed to Redmine::Plugin.register, which is the directory under plugins/.
PLUGIN_NAME="$(sed -n -E "s/^[[:space:]]*Redmine::Plugin\.register[[:space:](]*:?['\"]?([a-z0-9_]+).*/\1/p" "$PLUGIN_ROOT/init.rb" | head -n 1)"
[ -n "$PLUGIN_NAME" ] || PLUGIN_NAME="$(basename "$PLUGIN_ROOT")"

RMP_PORT="${RMP_PORT:-3000}"
RMP_SERVER_ENV="${RMP_SERVER_ENV:-production}"
RMP_ADMIN_PASSWORD="${RMP_ADMIN_PASSWORD:-Redmine7Test!}"
RMP_USER_PASSWORD="${RMP_USER_PASSWORD:-$RMP_ADMIN_PASSWORD}"
RMP_URL="http://127.0.0.1:$RMP_PORT"
RMP_PIDFILE="$REDMINE_DIR/tmp/pids/e2e-$RMP_PORT.pid"
RMP_SERVER_LOG="$REDMINE_DIR/log/e2e-server-$RMP_PORT.log"
export REDMINE_DIR PLUGIN_ROOT PLUGIN_NAME RMP_PORT RMP_SERVER_ENV RMP_ADMIN_PASSWORD RMP_USER_PASSWORD RMP_URL

if [ -f "$PLUGIN_ROOT/.codex/common.sh" ] && grep -q '^rmp_select_ruby()' "$PLUGIN_ROOT/.codex/common.sh"; then
  _rmp_dir="$REDMINE_DIR"
  # shellcheck source=/dev/null
  . "$PLUGIN_ROOT/.codex/common.sh"
  REDMINE_DIR="$_rmp_dir"
  rmp_select_ruby quiet
else
  run() { (cd "$REDMINE_DIR" && "$@"); }
fi

rmp_require_checkout() {
  [ -f "$REDMINE_DIR/config/database.yml" ] && [ -d "$REDMINE_DIR/plugins/$PLUGIN_NAME" ] || {
    echo "ERROR: no prepared Redmine in $REDMINE_DIR. Run ./.codex/redmine_clone.sh and ./.codex/test_setup.sh first." >&2
    exit 1
  }
}
