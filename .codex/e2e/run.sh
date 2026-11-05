#!/usr/bin/env bash
# Usage: run.sh <5.1|7.0|all> [scenario ...]   (scenario = file name in scenarios/, without .js; default: all scenarios)
# Starts the needed server(s) on b51 (3051) / b70 (3070), runs scenarios, stops the servers.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
E2E_DIR="${E2E_DIR:-${DCF_WORK_DIR:?set DCF_WORK_DIR or E2E_DIR}/e2e}"
DCF_WORK_DIR="${DCF_WORK_DIR:-$(dirname "$E2E_DIR")}"
export E2E_DIR DCF_WORK_DIR
export PATH=/opt/node22/bin:$PATH
VER=${1:-all}; shift
SCEN=("$@")
case "$VER" in 5.1) VERS=(5.1);; 7.0) VERS=(7.0);; all) VERS=(5.1 7.0);; *) echo "usage: run.sh <5.1|7.0|all> [scenario...]"; exit 2;; esac
if [ ${#SCEN[@]} -eq 0 ]; then
  for f in "$HERE"/scenarios/*.js; do SCEN+=("$(basename "$f" .js)"); done
fi
pg_isready -q || pg_ctlcluster 16 main start
declare -A NAME=([5.1]=b51 [7.0]=b70) PORT=([5.1]=3051 [7.0]=3070)
cleanup() { for v in "${VERS[@]}"; do "$HERE/server.sh" stop "${NAME[$v]}" "${PORT[$v]}" >/dev/null 2>&1; done; }
trap cleanup EXIT
rc=0
for v in "${VERS[@]}"; do "$HERE/server.sh" start "${NAME[$v]}" "${PORT[$v]}" || rc=1; done
for v in "${VERS[@]}"; do
  for s in "${SCEN[@]}"; do
    echo "--- $s on $v"
    (cd "$HERE" && node "scenarios/$s.js" "$v") || rc=1
  done
done
exit $rc
