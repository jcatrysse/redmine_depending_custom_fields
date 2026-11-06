#!/usr/bin/env bash
# Builds the variant `none`: Redmine without the plugin, for the comparison "what does the plugin cost on top of Redmine".
# Per version: checkout n<ver> = copy of m<ver> without plugins/redmine_depending_custom_fields (same production config and perf
# probe), database dcf_perf_n<ver> = clone (CREATE DATABASE ... TEMPLATE) of the BRANCH database dcf_perf_p<ver>, made valid
# without the plugin: depending_list -> list, depending_enumeration -> enumeration, extended_user -> user (possible values,
# enumerations, issues and values stay; the plugin format_store with the dependency mapping, the plugin settings, its
# schema_migrations row and its audit table are removed). Run after build.sh. Redmine 6.1: the assets are precompiled again
# without the plugin. Usage: build_none.sh [51] [61]   (default both)
set -u
source "$(dirname "$0")/common.sh"
PROBE="${H:-$P}/lib/zz_perf_probe.rb"
VERS=("$@"); [ ${#VERS[@]} -eq 0 ] && VERS=(51 61)
pg_isready -q -h localhost || pg_ctlcluster 16 main start
for v in "${VERS[@]}"; do
  ver=$(ver_of "$v")
  dcf_select_ruby "$ver" >/dev/null 2>&1 || true
  echo "== none $ver"
  [ -d "$E/m$v" ] && $PSQL -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='dcf_perf_p$v'" | grep -q 1 || { echo "run build.sh first"; exit 3; }
  rm -rf "${E:?}/n$v"; cp -a "$E/m$v" "$E/n$v"
  rm -rf "$E/n$v/plugins/redmine_depending_custom_fields" "$E/n$v/public/plugin_assets/redmine_depending_custom_fields" "$E/n$v/tmp/cache"
  rm -f "$E/n$v/log/"*.log
  sed -i "s/dcf_perf_m$v/dcf_perf_n$v/" "$E/n$v/config/database.yml"
  cp "$PROBE" "$E/n$v/config/initializers/zz_perf_probe.rb"
  $PSQL -d postgres -c "DROP DATABASE IF EXISTS dcf_perf_n$v" -c "CREATE DATABASE dcf_perf_n$v TEMPLATE dcf_perf_p$v"
  $PSQL -d "dcf_perf_n$v" <<'SQL'
UPDATE custom_fields SET field_format='list', format_store=NULL WHERE field_format='depending_list';
UPDATE custom_fields SET field_format='enumeration', format_store=NULL WHERE field_format='depending_enumeration';
UPDATE custom_fields SET field_format='user' WHERE field_format='extended_user';
DELETE FROM settings WHERE name='plugin_redmine_depending_custom_fields';
DELETE FROM schema_migrations WHERE version LIKE '%redmine_depending_custom_fields';
DROP TABLE IF EXISTS dcf_config_audit_events;
SQL
  mkdir -p "$E/n$v/tmp/cache" "$E/n$v/tmp/pids"
  if [ "$ver" = 6.1 ]; then ( cd "$E/n$v" && rm -rf public/assets && prod_env && bundle exec rake assets:precompile > "$P/logs/assets_n$v.log" 2>&1 ) && echo "[n$v] assets precompiled"; fi
  $PSQL -d "dcf_perf_n$v" -tA -c "SELECT field_format, count(*) FROM custom_fields GROUP BY 1 ORDER BY 1"
done
echo "build_none done"
