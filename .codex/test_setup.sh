#!/usr/bin/env bash
# Usage: .codex/test_setup.sh [<5.1|6.0|6.1|7.0>] [--keep-db] [--no-apt] [--no-js]
# Mirrors the CI steps after the clone: system packages, database.yml,
# bundle install, db:drop db:create db:migrate, redmine:plugins:migrate, npm ci.
# Idempotent: safe to re-run; drops and recreates the test database unless --keep-db.
# Database: PostgreSQL via DCF_DB_HOST/PORT/USER/PASSWORD (default localhost:5432
# redmine/redmine, as in CI). It never creates roles or starts services.
source "$(dirname "$0")/lib/common.sh"
VER=""; KEEP_DB=0; APT=1; JS=1
while [ $# -gt 0 ]; do
  case "$1" in
    --keep-db) KEEP_DB=1 ;;
    --no-apt) APT=0 ;;
    --no-js) JS=0 ;;
    -*) dcf_die 2 "unknown option $1" ;;
    *) VER="$(dcf_version "$1")" || dcf_die 2 "unsupported branch '$1'" ;;
  esac
  shift
done
[ -n "$VER" ] || VER="$(dcf_state_read)" || true
[ -n "$VER" ] || dcf_die 2 "no version given and no previous clone; run .codex/redmine_clone.sh <ver> first"
DIR="$(dcf_redmine_dir "$VER")"
[ -f "$DIR/$DCF_MARKER" ] || "$DCF_SCRIPT_DIR/redmine_clone.sh" "$VER" || exit $?

# 1. System packages (pg gem needs libpq-dev / pg_config; observed on 5.1 and 6.x).
if ! command -v pg_config >/dev/null 2>&1; then
  if [ "$APT" = "1" ] && command -v apt-get >/dev/null 2>&1; then
    SUDO=""; [ "$(id -u)" = "0" ] || SUDO="sudo"
    dcf_log "installing build-essential libpq-dev (apt-get update first: stale indexes return 404)"
    $SUDO apt-get update -qq && $SUDO apt-get install -y -qq build-essential libpq-dev \
      || dcf_die 4 "apt-get install libpq-dev failed"
  else
    dcf_die 4 "pg_config not found: install libpq-dev (or rerun without --no-apt)"
  fi
fi

# 2. Database reachability (never creates roles: that needs the owner's consent).
DB_HOST="${DCF_DB_HOST:-localhost}"; DB_PORT="${DCF_DB_PORT:-5432}"
DB_USER="${DCF_DB_USER:-redmine}"; DB_PASS="${DCF_DB_PASSWORD:-redmine}"
DB_NAME="${DCF_DB_NAME:-dcf_test_${VER//./}}"
if command -v pg_isready >/dev/null 2>&1; then
  pg_isready -q -h "$DB_HOST" -p "$DB_PORT" || dcf_die 5 "PostgreSQL not ready on $DB_HOST:$DB_PORT"
fi
PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -Atc 'select 1' >/dev/null 2>&1 \
  || dcf_die 5 "cannot log in as $DB_USER on $DB_HOST:$DB_PORT (role with CREATEDB required, see README Development)"

# 3. Plugin copy + database.yml.
dcf_sync_plugin "$DIR"
cat > "$DIR/config/database.yml" <<YML
test:
  adapter: postgresql
  database: $DB_NAME
  host: $DB_HOST
  port: $DB_PORT
  username: $DB_USER
  password: $DB_PASS
  encoding: unicode
YML

# 4. Ruby + gems.
dcf_select_ruby "$VER"
cd "$DIR" || dcf_die 6 "missing $DIR"
export RAILS_ENV=test
bundle config set --local build.pg "--with-pg-config=$(command -v pg_config)" >/dev/null
bundle install --jobs 4 --quiet || dcf_die 11 "bundle install failed"

# 5. Database.
if [ "$KEEP_DB" = "1" ]; then
  bundle exec rake db:create db:migrate || dcf_die 12 "db setup failed"
else
  bundle exec rake db:drop db:create db:migrate || dcf_die 12 "db setup failed"
fi
bundle exec rake redmine:plugins:migrate || dcf_die 13 "plugin migration failed"

# 6. JS tooling (plugin repo, independent of Redmine).
if [ "$JS" = "1" ] && [ -f "$DCF_PLUGIN_DIR/package-lock.json" ]; then
  if command -v npm >/dev/null 2>&1; then
    (cd "$DCF_PLUGIN_DIR" && npm ci --no-audit --no-fund --silent) || dcf_die 4 "npm ci failed"
  else
    dcf_log "WARNING: npm not found, JS suite will be unavailable"
  fi
fi

dcf_state_write "$VER"
{
  echo "plugin_sha=$(git -C "$DCF_PLUGIN_DIR" rev-parse HEAD 2>/dev/null)"
  echo "redmine_sha=$(git -C "$DIR" rev-parse HEAD)"
  echo "ruby=$(ruby -e 'print RUBY_VERSION')"
  echo "db=$DB_NAME"
  echo "at=$(date -u +%FT%TZ)"
} > "$DIR/.dcf-setup-ok"
cat "$DIR/.dcf-setup-ok"
