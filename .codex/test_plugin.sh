#!/usr/bin/env bash
#
# Runs the plugin's own tests: minitest (test/**/*_test.rb, without system/ and
# ui/, all in one process the way Redmine's rake task loads them) and rspec
# (spec/). Run ./.codex/test_setup.sh first.
#
#   ./.codex/test_plugin.sh                 # everything
#   ./.codex/test_plugin.sh test/unit/x_test.rb spec/models/y_spec.rb
#   ./.codex/test_plugin.sh --system        # also test/system (needs Chrome)
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

P="plugins/$PLUGIN_NAME"
[ -d "$REDMINE_DIR/$P" ] || {
  echo "ERROR: '$REDMINE_DIR/$P' not found. Run ./.codex/redmine_clone.sh first." >&2
  exit 1
}

rmp_select_ruby quiet
export RAILS_ENV=test
export LANG="${LANG:-C.UTF-8}" LC_ALL="${LC_ALL:-C.UTF-8}"

system=0
minitest=()
specs=()
for arg in "$@"; do
  case "$arg" in
    --system) system=1 ;;
    test/*)   minitest+=("$P/$arg") ;;
    spec/*)   specs+=("$P/$arg") ;;
    *) echo "ERROR: unknown argument '$arg'" >&2; exit 2 ;;
  esac
done

if [ ${#minitest[@]} -eq 0 ] && [ ${#specs[@]} -eq 0 ]; then
  if [ -d "$REDMINE_DIR/$P/test" ]; then
    filter=(! -path '*/ui/*')
    [ "$system" = 1 ] || filter+=(! -path '*/system/*')
    mapfile -t minitest < <(cd "$REDMINE_DIR" && find "$P/test" -name '*_test.rb' "${filter[@]}" | sort)
  fi
  [ -d "$REDMINE_DIR/$P/spec" ] && specs=("$P/spec")
fi

status=0
if [ ${#minitest[@]} -gt 0 ]; then
  echo "== minitest: ${#minitest[@]} files"
  run bundle exec ruby -Itest -e 'ARGV.each { |f| require File.expand_path(f) }' "${minitest[@]}" || status=1
fi
if [ ${#specs[@]} -gt 0 ]; then
  echo "== rspec: ${specs[*]}"
  # through the gem, because a Ruby manager may provide no rspec binstub
  run bundle exec ruby -e 'load Gem.bin_path("rspec-core", "rspec")' -- -I "$P/spec" "${specs[@]}" || status=1
fi
[ ${#minitest[@]} -gt 0 ] || [ ${#specs[@]} -gt 0 ] || echo "This plugin has no tests."
exit $status
