#!/usr/bin/env bash
# Usage: run-admin.sh [scenario...]  runs admin/project scenarios on c51 (3151) and c70 (3170); servers must be up (server.sh start c51 3151 / c70 3170)
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
E2E_DIR="${E2E_DIR:-${DCF_WORK_DIR:?set DCF_WORK_DIR or E2E_DIR}/e2e}"
DCF_WORK_DIR="${DCF_WORK_DIR:-$(dirname "$E2E_DIR")}"
export E2E_DIR DCF_WORK_DIR
export PATH=/opt/node22/bin:$PATH
SC=("$@"); [ ${#SC[@]} -eq 0 ] && SC=(admin-editor csv large-list project-values project-dependency permissions)
for s in "${SC[@]}"; do
  "$HERE/reseed.sh" c51 5.1 >/dev/null; node "$HERE/scenarios/$s.js" http://127.0.0.1:3151 "$E2E_DIR/out/5.1"
  "$HERE/reseed.sh" c70 7.0 >/dev/null; node "$HERE/scenarios/$s.js" http://127.0.0.1:3170 "$E2E_DIR/out/7.0"
done
