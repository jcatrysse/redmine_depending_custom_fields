#!/usr/bin/env bash
# Usage: .codex/rubocop_ratchet.sh [--base <ref>] [--redmine <dir>]
# G3 gate. Three checks, all against the plugin working tree:
#  1. Ruby 2.7 syntax: Lint/Syntax with TargetRubyVersion 2.7 on ALL Ruby files (must be 0).
#  2. Compat check: added lines using APIs that parse on 2.7 but fail at runtime on
#     Ruby 2.7 / Rails 6.1 / Rack 2.2, inline script tags, or en/em dashes.
#  3. Ratchet: per changed Ruby file, offense count per cop (core config, plugins
#     un-excluded, plugin .rubocop.yml overlay) must not exceed the count at the base.
# Uses the RuboCop pinned by the given Redmine checkout (default: 7.0, rubocop ~> 1.88).
source "$(dirname "$0")/lib/common.sh"
BASE_REF="${DCF_BASE_REF:-origin/main}"; RDIR="$(dcf_redmine_dir 7.0)"
while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE_REF="$2"; shift 2 ;;
    --redmine) RDIR="$2"; shift 2 ;;
    *) dcf_die 2 "unknown option $1" ;;
  esac
done
[ -f "$RDIR/.rubocop.yml" ] && [ -f "$RDIR/Gemfile.lock" ] || dcf_die 6 "no prepared Redmine checkout at $RDIR (run .codex/test_setup.sh 7.0)"
[ -f "$DCF_PLUGIN_DIR/.rubocop.yml" ] || dcf_die 6 "plugin .rubocop.yml missing"
dcf_select_ruby "$(dcf_detect_version "$RDIR")"
export BUNDLE_GEMFILE="$RDIR/Gemfile"
BASE="$(git -C "$DCF_PLUGIN_DIR" merge-base HEAD "$BASE_REF" 2>/dev/null)" || dcf_die 2 "cannot resolve base '$BASE_REF'"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# Same overlay for base and head; only inherit_from is made absolute.
sed "s#^inherit_from: .*#inherit_from: $RDIR/.rubocop.yml#" "$DCF_PLUGIN_DIR/.rubocop.yml" > "$TMP/rubocop.yml"
mkdir -p "$TMP/base"; git -C "$DCF_PLUGIN_DIR" archive "$BASE" | tar -x -C "$TMP/base"

cd "$DCF_PLUGIN_DIR" || exit 6
CHANGED="$( { git diff --name-only --diff-filter=ACMR "$BASE"; git ls-files --others --exclude-standard; } \
  | grep -E '(\.rb|\.rake|(^|/)Gemfile)$' | grep -v '^node_modules/' | sort -u)"
ALL_RB="$(git ls-files --cached --others --exclude-standard | grep -E '(\.rb|\.rake|(^|/)Gemfile)$' | sort -u)"
STATUS=0

echo "--- 1. Ruby 2.7 syntax (all files)"
# shellcheck disable=SC2086
bundle exec rubocop -c "$TMP/rubocop.yml" --cache false --only Lint/Syntax --format simple $ALL_RB > "$TMP/syntax.txt" 2>&1
[ $? -le 1 ] || { cat "$TMP/syntax.txt"; dcf_die 6 "rubocop failed (syntax run)"; }
grep -q 'Lint/Syntax' "$TMP/syntax.txt" && { grep -B1 'Lint/Syntax' "$TMP/syntax.txt" | grep -v '^--$'; STATUS=1; echo "SYNTAX FAIL"; } || echo "SYNTAX PASS"

echo "--- 2. Compat check (lines added since base)"
# Constructs that parse on 2.7 but fail at runtime on Ruby 2.7 / Rails 6.1 /
# Rack 2.2, or break repository rules (see .codex/lib/compat_check.rb). Only
# added lines count, so existing code is fixed by the WP that owns it.
git diff -U0 "$BASE" -- app lib config db init.rb spec assets ':!*.md' ':!spec/quality/**' \
  | ruby "$DCF_SCRIPT_DIR/lib/compat_check.rb" || STATUS=1

echo "--- 3. Ratchet (changed files vs $BASE)"
if [ -z "$CHANGED" ]; then
  echo "RATCHET PASS (no changed Ruby files)"
else
  # shellcheck disable=SC2086
  bundle exec rubocop -c "$TMP/rubocop.yml" --cache false --force-exclusion --format json $CHANGED > "$TMP/head.json" 2>"$TMP/head.err"
  # RuboCop: 0 clean, 1 offenses, 2+ error (bad config, wrong Ruby, crash).
  [ $? -le 1 ] || { cat "$TMP/head.err"; dcf_die 6 "rubocop failed on head"; }
  INBASE="$(for f in $CHANGED; do [ -f "$TMP/base/$f" ] && echo "$f"; done)"
  if [ -n "$INBASE" ]; then
    # shellcheck disable=SC2086
    (cd "$TMP/base" && bundle exec rubocop -c "$TMP/rubocop.yml" --cache false --force-exclusion --format json $INBASE > "$TMP/base.json" 2>"$TMP/base.err")
    [ $? -le 1 ] || { cat "$TMP/base.err"; dcf_die 6 "rubocop failed on base"; }
  else
    echo '{"files":[]}' > "$TMP/base.json"
  fi
  ruby "$DCF_SCRIPT_DIR/lib/rubocop_ratchet.rb" "$TMP/base.json" "$TMP/head.json" || STATUS=1
fi
exit $STATUS
