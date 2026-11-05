#!/usr/bin/env bash
# Builds m51 p51 m61 p61 (checkouts under e2e/, databases dcf_perf_<name>), seeds the main databases and clones them.
# Usage: build.sh [--rebuild]      --rebuild drops and recreates everything (about 5 minutes).
# Needs the Redmine checkouts $DCF_WORK_DIR/redmine-5.1 and redmine-6.1 (.codex/redmine_clone.sh), PostgreSQL on localhost
# (user redmine, password redmine, CREATEDB) and node with playwright for the benches.
set -u
source "$(dirname "$0")/common.sh"
REBUILD=0; [ "${1:-}" = "--rebuild" ] && REBUILD=1
[ -d "$E/src-main" ] && [ -d "$E/src-branch" ] || "$H/refresh_src.sh" || exit 1
pg_isready -q -h localhost || pg_ctlcluster 16 main start
for v in 51 61; do
  ver=$(ver_of $v)
  dcf_select_ruby "$ver" >/dev/null 2>&1 || true
  echo "== Redmine $ver"
  if [ $REBUILD = 1 ] || [ ! -f "$P/data/ids-$v.json" ] || [ ! -d "$E/m$v" ]; then
    # m<v>: Redmine + MAIN plugin, drop/create/migrate/default data (setup.sh), then seed with the main data model.
    bash "$REPO/.codex/e2e/setup.sh" "$ver" "m$v" "dcf_perf_m$v" "$E/src-main" > "$P/logs/setup_m$v.log" 2>&1
    ( cd "$E/m$v" && RAILS_ENV=development bundle exec rails runner "$H/seed_perf.rb" "$P/data/ids-$v.json" ) > "$P/logs/seed_m$v.log" 2>&1
    tail -n 2 "$P/logs/seed_m$v.log"
  fi
  # p<v>: same Redmine, BRANCH plugin, database cloned from the seeded main database, then the plugin migration (upgrade path).
  if [ $REBUILD = 1 ] || [ ! -d "$E/p$v" ]; then
    rm -rf "$E/p$v"; cp -a "$(dcf_redmine_dir "$ver")" "$E/p$v"
    rm -rf "$E/p$v/log/"*.log "$E/p$v/tmp/cache"
    printf 'production:\n  adapter: postgresql\n  database: dcf_perf_p%s\n  host: localhost\n  port: 5432\n  username: redmine\n  password: redmine\n  encoding: unicode\n' $v > "$E/p$v/config/database.yml"
    printf 'development:\n  adapter: postgresql\n  database: dcf_perf_p%s\n  host: localhost\n  port: 5432\n  username: redmine\n  password: redmine\n  encoding: unicode\n' $v >> "$E/p$v/config/database.yml"
    $PSQL -d postgres -c "DROP DATABASE IF EXISTS dcf_perf_p$v" -c "CREATE DATABASE dcf_perf_p$v TEMPLATE dcf_perf_m$v"
  fi
  # main database config: production entry too
  printf 'production:\n  adapter: postgresql\n  database: dcf_perf_m%s\n  host: localhost\n  port: 5432\n  username: redmine\n  password: redmine\n  encoding: unicode\ndevelopment:\n  adapter: postgresql\n  database: dcf_perf_m%s\n  host: localhost\n  port: 5432\n  username: redmine\n  password: redmine\n  encoding: unicode\n' $v $v > "$E/m$v/config/database.yml"
  install_plugin "m$v" "$E/src-main"
  install_plugin "p$v" "$E/src-branch"
  for n in m$v p$v; do
    mkdir -p "$E/$n/tmp/cache" "$E/$n/tmp/pids"
    ( cd "$E/$n"; prod_env; bundle exec rake redmine:plugins:migrate > "$P/logs/migrate_$n.log" 2>&1; tail -n 3 "$P/logs/migrate_$n.log" | sed "s/^/[$n] /" )
    if [ "$ver" = 6.1 ]; then ( cd "$E/$n"; prod_env; bundle exec rake assets:precompile > "$P/logs/assets_$n.log" 2>&1 ) && echo "[$n] assets precompiled"; fi
  done
done
echo "build done"
