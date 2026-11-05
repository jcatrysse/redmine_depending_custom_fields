#!/usr/bin/env bash
# End to end measurement: main (0.0.15) against branch on Redmine 5.1 and 6.1.
#   measure.sh [N]            N measured server rounds (default 30), browser repetitions BROWSER_REPS (default 10)
#   measure.sh --smoke        N=2, 1 warm-up, mixed run 20, 2 browser repetitions, results in results/smoke (for checking the harness)
# Steps: refresh the branch plugin from e2e/src-branch into p51 and p61 (plugin migration, assets), per version: mapping check,
# server bench, browser bench (servers restarted for every block, wait for a 1 minute load average below 1.0 before each block),
# summary. Raw JSON per page, variant and version: results/raw/{server,browser}_<ver>_<variant>_<page>.json, meta files
# *_meta.json, mapping_check_<ver>.json; summary: results/summary.json and results/summary.md. Servers are stopped on exit.
# To measure a newer branch state first run .codex/perf/refresh_src.sh.
# Environment: HEAVY_TIMEOUT_S (45), HEAVY_ROUNDS (3), HEAVY_NORMAL_ROUNDS (15), SEC_ROUNDS (8), WARMUP (5), MIXED (300),
#              BROWSER_REPS (10), PROFILE_REPS (2), BROWSER_TIMEOUT_S (30),
#              LOAD_MAX (1.0), LOAD_WAIT_MAX seconds (900, then it proceeds and records the load), VERSIONS ("51 61").
source "$(dirname "$0")/common.sh"
N=30
SMOKE=0
if [ "${1:-}" = "--smoke" ]; then SMOKE=1; N=2; elif [ -n "${1:-}" ]; then N=$1; fi
WARMUP=${WARMUP:-5}; MIXED=${MIXED:-300}; BROWSER_REPS=${BROWSER_REPS:-10}; PROFILE_REPS=${PROFILE_REPS:-2}
RESULTS=$P/results
if [ $SMOKE = 1 ]; then
  WARMUP=1; MIXED=20; BROWSER_REPS=2; PROFILE_REPS=1; RESULTS=$P/results/smoke
  export HEAVY_TIMEOUT_S=${HEAVY_TIMEOUT_S:-15} BROWSER_TIMEOUT_S=${BROWSER_TIMEOUT_S:-15}; LOAD_WAIT_MAX=${LOAD_WAIT_MAX:-0}
fi
LOAD_MAX=${LOAD_MAX:-1.0}; LOAD_WAIT_MAX=${LOAD_WAIT_MAX:-900}
VERSIONS=${VERSIONS:-"51 61"}
mkdir -p "$RESULTS/raw" "$P/logs"
# earlier results of the same directory are kept in results/archive-<time>
if [ -n "$(ls -A "$RESULTS/raw" 2>/dev/null)" ]; then
  A=$RESULTS/archive-$(date +%Y%m%d-%H%M%S); mkdir -p "$A"
  mv "$RESULTS/raw" "$A/" ; mv "$RESULTS"/summary.* "$RESULTS"/mapping_check_* "$RESULTS"/branch_commit.txt "$A/" 2>/dev/null
  mkdir -p "$RESULTS/raw"
fi
export SEC_ROUNDS=${SEC_ROUNDS:-8}
T0=$(date +%s)
say() { echo "[measure $(date +%H:%M:%S) +$(( ($(date +%s) - T0) / 60 ))m] $*"; }
stop_all() { for n in m51 p51 m61 p61; do "$H/server.sh" stop $n >/dev/null 2>&1; done; }
trap stop_all EXIT
wait_load() {
  local waited=0 l
  while :; do
    l=$(cut -d' ' -f1 /proc/loadavg)
    if awk -v l="$l" -v m="$LOAD_MAX" 'BEGIN{exit !(l < m)}'; then return; fi
    if [ $waited -ge "$LOAD_WAIT_MAX" ]; then say "WARNING: load average $l still above $LOAD_MAX after ${waited}s, continuing (recorded in the meta files)"; return; fi
    say "waiting for load average below $LOAD_MAX (now $l)"; sleep 15; waited=$((waited + 15))
  done
}

stop_all
pg_isready -q -h localhost || pg_ctlcluster 16 main start
# 1. refresh the branch plugin into p51 and p61
for v in $VERSIONS; do
  ver=$(ver_of $v)
  [ -d "$E/p$v" ] && [ -d "$E/m$v" ] && [ -f "$P/data/ids-$v.json" ] || { say "checkout or data for $v missing: run .codex/perf/build.sh first"; exit 3; }
  if ! diff -rq "$E/src-branch" "$E/p$v/plugins/redmine_depending_custom_fields" >/dev/null 2>&1 || [ ! -f "$E/p$v/config/initializers/zz_perf_probe.rb" ]; then
    say "refreshing the branch plugin in p$v"
    dcf_select_ruby "$ver" >/dev/null 2>&1 || true
    install_plugin "p$v" "$E/src-branch"
    ( cd "$E/p$v"; prod_env; bundle exec rake redmine:plugins:migrate > "$P/logs/migrate_p$v.log" 2>&1 || { say "plugin migration failed, see logs/migrate_p$v.log"; exit 4; }
      if [ "$ver" = 6.1 ]; then bundle exec rake assets:precompile > "$P/logs/assets_p$v.log" 2>&1; fi )
  fi
  cmp -s "$H/lib/zz_perf_probe.rb" "$E/m$v/config/initializers/zz_perf_probe.rb" || cp "$H/lib/zz_perf_probe.rb" "$E/m$v/config/initializers/zz_perf_probe.rb"
  cmp -s "$H/lib/zz_perf_probe.rb" "$E/p$v/config/initializers/zz_perf_probe.rb" || cp "$H/lib/zz_perf_probe.rb" "$E/p$v/config/initializers/zz_perf_probe.rb"
  grep -m1 "version '" "$E/p$v/plugins/redmine_depending_custom_fields/init.rb" | sed "s/^/[p$v plugin] /"
done
# the branch commit, for the record
git -C "$REPO" rev-parse --short HEAD > "$RESULTS/branch_commit.txt" 2>/dev/null
# 2. per version
for v in $VERSIONS; do
  wait_load; say "mapping check $v"
  node "$H/verify_mapping.js" --version $v --out "$RESULTS" || say "MAPPING CHECK FAILED for $v (see $RESULTS/mapping_check_$v.json)"
  wait_load; say "server bench $v (rounds $N)"
  node "$H/server_bench.js" --version $v --rounds "$N" --warmup "$WARMUP" --mixed "$MIXED" --out "$RESULTS/raw" 2>&1 | tee "$P/logs/server_bench_$v.log" | sed -n '/round \|done in\|FAILED\|timeout/p'
  wait_load; say "browser bench $v (reps $BROWSER_REPS)"
  node "$H/browser_bench.js" --version $v --reps "$BROWSER_REPS" --profile "$PROFILE_REPS" --out "$RESULTS/raw" 2>&1 | tee "$P/logs/browser_bench_$v.log" | sed -n '/done in\|FAILED\|timeout/p'
done
node "$H/summarize.js" --dir "$RESULTS" --out "$RESULTS"
say "finished"
