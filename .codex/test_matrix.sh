#!/usr/bin/env bash
# Usage: .codex/test_matrix.sh [--versions "5.1 6.0 6.1 7.0"] [--setup] [--suite ...]...
# G10 helper: runs test_plugin.sh for every supported Redmine version (optionally
# clone + setup first) and prints one summary line per version. Exit 1 if any fails.
source "$(dirname "$0")/lib/common.sh"
VERSIONS="5.1 6.0 6.1 7.0"; SETUP=0; PASS_ARGS=(); LINT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --versions) VERSIONS="$2"; shift 2 ;;
    --setup) SETUP=1; shift ;;
    --suite) if [ "$2" = "lint" ]; then LINT=1; else PASS_ARGS+=(--suite "$2"); fi; shift 2 ;;
    *) dcf_die 2 "unknown option $1" ;;
  esac
done
STATUS=0; LINES=()
for v in $VERSIONS; do
  if [ "$SETUP" = "1" ]; then
    "$DCF_SCRIPT_DIR/redmine_clone.sh" "$v" >/dev/null && "$DCF_SCRIPT_DIR/test_setup.sh" "$v" --no-js >/dev/null 2>&1 \
      || { LINES+=("version=$v SETUP FAILED"); STATUS=1; continue; }
  fi
  out="$("$DCF_SCRIPT_DIR/test_plugin.sh" "$v" "${PASS_ARGS[@]}" 2>&1)"; code=$?
  LINES+=("version=$v exit=$code $(printf '%s\n' "$out" | grep '^suite=' | sed 's/ log=.*//' | tr '\n' ' ')")
  [ "$code" = "0" ] || STATUS=1
done
# Lint is version independent (pinned to the 7.0 RuboCop): run it once.
if [ "$LINT" = "1" ]; then
  "$DCF_SCRIPT_DIR/rubocop_ratchet.sh" > "$DCF_WORK_DIR/logs/matrix-lint.log" 2>&1; code=$?
  LINES+=("lint exit=$code $(grep -E 'SYNTAX|COMPAT|RATCHET' "$DCF_WORK_DIR/logs/matrix-lint.log" | tr '\n' ' ')")
  [ "$code" = "0" ] || STATUS=1
fi
echo "=== DCF MATRIX ==="
printf '%s\n' "${LINES[@]}"
exit $STATUS
