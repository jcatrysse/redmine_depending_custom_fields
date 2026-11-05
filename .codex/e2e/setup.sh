#!/usr/bin/env bash
# Usage: setup.sh <5.1|7.0|6.1> <name> <db> <plugin-src-dir>
# Copies the test checkout $DCF_WORK_DIR/redmine-<ver> to $E2E_DIR/<name>, points development and production at <db>,
# creates the database, loads default data and syncs the plugin from <plugin-src-dir>.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
E2E_DIR="${E2E_DIR:-${DCF_WORK_DIR:?set DCF_WORK_DIR or E2E_DIR}/e2e}"
DCF_WORK_DIR="${DCF_WORK_DIR:-$(dirname "$E2E_DIR")}"
export E2E_DIR DCF_WORK_DIR
VER=$1 NAME=$2 DB=$3 SRC=$4
DST=$E2E_DIR/$NAME
source "$REPO/.codex/lib/common.sh"
dcf_select_ruby "$VER"
[ -d "$DST" ] || cp -a "$DCF_WORK_DIR/redmine-$VER" "$DST"
rm -rf "$DST/plugins/redmine_depending_custom_fields" "$DST/log/"*.log "$DST/tmp/cache"
mkdir -p "$DST/plugins/redmine_depending_custom_fields" && cp -a "$SRC/." "$DST/plugins/redmine_depending_custom_fields/"
for env in development production; do printf '%s:\n  adapter: postgresql\n  database: %s\n  host: localhost\n  port: 5432\n  username: redmine\n  password: redmine\n  encoding: unicode\n' $env $DB; done > "$DST/config/database.yml"
cd "$DST"
export RAILS_ENV=development
bundle exec rake db:drop db:create db:migrate >/dev/null 2>&1 || bundle exec rake db:create db:migrate >/dev/null
REDMINE_LANG=en bundle exec rake redmine:load_default_data >/dev/null
bundle exec rake redmine:plugins:migrate >/dev/null
echo "ready $DST ($(ruby -e 'print RUBY_VERSION'), db $DB)"
