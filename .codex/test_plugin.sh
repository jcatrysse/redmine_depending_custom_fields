#!/usr/bin/env bash
# Usage: .codex/test_plugin.sh [<5.1|6.0|6.1|7.0>] [--suite rspec|system|js|lint|all]... [-- <rspec args>]
# rspec args starting with spec/ select files (relative to the plugin root).
# Re-syncs the working tree into the prepared Redmine checkout and runs the
# requested suites (default: rspec js lint). Every suite's full output is kept in
# $DCF_WORK_DIR/logs/ and a summary with exit codes is printed at the end; that
# summary and the logs are the evidence for the quality gates.
source "$(dirname "$0")/lib/common.sh"
VER=""; SUITES=""; RSPEC_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --suite) SUITES="$SUITES $2"; shift 2; continue ;;
    --) shift; RSPEC_ARGS=("$@"); break ;;
    -*) dcf_die 2 "unknown option $1" ;;
    *) VER="$(dcf_version "$1")" || dcf_die 2 "unsupported branch '$1'" ;;
  esac
  shift
done
[ -n "$VER" ] || VER="$(dcf_state_read)" || true
[ -n "$VER" ] || dcf_die 2 "no version given and no previous setup"
SUITES="${SUITES:- rspec js lint}"
[ "$SUITES" = " all" ] && SUITES=" rspec system js lint"
DIR="$(dcf_redmine_dir "$VER")"
[ -f "$DIR/.dcf-setup-ok" ] || dcf_die 6 "Redmine $VER not prepared: run .codex/test_setup.sh $VER"
LOGS="$DCF_WORK_DIR/logs"; mkdir -p "$LOGS"
STAMP="$(date +%Y%m%d-%H%M%S)"
SPEC_DIR="plugins/$DCF_PLUGIN_NAME/spec"
declare -A RESULT

run_suite() { # name, command...
  local name="$1"; shift
  local log="$LOGS/$VER-$name-$STAMP.log"
  dcf_log "suite $name -> $log"
  ( "$@" ) 2>&1 | tee "$log"
  RESULT[$name]="${PIPESTATUS[0]} $log"
}

needs_redmine() {
  dcf_sync_plugin "$DIR"
  dcf_select_ruby "$VER"
  cd "$DIR" || dcf_die 6 "missing $DIR"
  export RAILS_ENV=test
  bundle exec rake redmine:plugins:migrate >/dev/null || dcf_die 13 "plugin migration failed"
}

for s in $SUITES; do
  case "$s" in
    rspec)
      needs_redmine
      # Paths after "--" (relative to the plugin, e.g. spec/models/x_spec.rb)
      # replace the full spec directory, so a subset can be run quickly.
      TARGETS=(); OPTS=()
      for a in "${RSPEC_ARGS[@]}"; do
        case "$a" in
          spec/*) TARGETS+=("plugins/$DCF_PLUGIN_NAME/$a") ;;
          *) OPTS+=("$a") ;;
        esac
      done
      [ ${#TARGETS[@]} -gt 0 ] || TARGETS=("$SPEC_DIR")
      run_suite rspec env -u DCF_SYSTEM_SPECS bundle exec rspec "${TARGETS[@]}" --format progress "${OPTS[@]}" ;;
    system)
      needs_redmine
      # A chromedriver on PATH that does not match the browser breaks Selenium
      # (observed: npm chromedriver 147 vs Chromium 141). Drop such entries and
      # let Selenium Manager resolve a matching browser + driver pair.
      CLEAN_PATH="$(printf '%s' "$PATH" | tr ':' '\n' | while read -r p; do [ -x "$p/chromedriver" ] || echo "$p"; done | paste -sd:)"
      run_suite system env PATH="$CLEAN_PATH" DCF_SYSTEM_SPECS=1 bundle exec rspec "$SPEC_DIR/system" --format documentation "${RSPEC_ARGS[@]}" ;;
    js)
      [ -f "$DCF_PLUGIN_DIR/package.json" ] || { RESULT[js]="0 (no package.json yet)"; continue; }
      ( cd "$DCF_PLUGIN_DIR" && { [ -d node_modules ] || npm ci --no-audit --no-fund --silent; } )
      run_suite js bash -c "cd '$DCF_PLUGIN_DIR' && npm run -s check && npm test" ;;
    lint)
      run_suite lint "$DCF_SCRIPT_DIR/rubocop_ratchet.sh" --redmine "$(dcf_redmine_dir 7.0)" ;;
    *) dcf_die 2 "unknown suite $s" ;;
  esac
done

echo "=== DCF SUMMARY (Redmine $VER) ==="
cat "$DIR/.dcf-setup-ok"
echo "plugin_worktree_sha=$(git -C "$DCF_PLUGIN_DIR" rev-parse HEAD) dirty=$(git -C "$DCF_PLUGIN_DIR" status --porcelain | wc -l)"
STATUS=0
for s in $SUITES; do
  read -r code log <<<"${RESULT[$s]}"
  line=""
  [ -f "$log" ] && line="$(grep -E '^[0-9]+ examples?, [0-9]+ failures?|^# (pass|fail) [0-9]+|RATCHET (PASS|FAIL)' "$log" | tr '\n' ' ')"
  echo "suite=$s exit=$code $line log=$log"
  [ "$code" = "0" ] || STATUS=1
done
exit $STATUS
