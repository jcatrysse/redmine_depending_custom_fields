#!/usr/bin/env bash
#
# Browser end-to-end checks against the server from ./.codex/start_server.sh:
#   1. .codex/e2e/smoke.mjs: every page the plugin adds, as admin (HTTP status,
#      JavaScript errors, missing assets, a screenshot of each page);
#   2. .codex/e2e/core.mjs: creating and editing an issue, the context menu
#      and a refusal, with the plugin installed;
#   3. every test/e2e/*.mjs in this repo: the plugin's own scenarios, one
#      screenshot per function, with and without the plugin's permissions.
# Screenshots and one <scenario>.md per script go to docs/e2e/ (RMP_E2E_OUT):
# commit them, they are the evidence. For "before" pictures run the same
# against Redmine 5.1 with RMP_E2E_OUT=docs/e2e/before.
#
#   ./.codex/e2e.sh                 # smoke + all scenarios
#   ./.codex/e2e.sh test/e2e/x.mjs  # one scenario
#   RMP_E2E_SMOKE=0 RMP_E2E_CORE=0 ./.codex/e2e.sh   # the plugin's scenarios only
#
# Needs Node and Playwright with Chromium
# (npm install -g playwright && npx playwright install --with-deps chromium).
set -euo pipefail

# shellcheck source=e2e/env.sh
. "$(dirname "${BASH_SOURCE[0]}")/e2e/env.sh"
rmp_require_checkout

code="$(curl -s -o /dev/null -w '%{http_code}' "$RMP_URL/login" || true)"
[ "$code" = 200 ] || { echo "ERROR: no Redmine on $RMP_URL (HTTP $code). Run ./.codex/start_server.sh first." >&2; exit 1; }

export RMP_E2E_OUT="${RMP_E2E_OUT:-$PLUGIN_ROOT/docs/e2e}"
case "$RMP_E2E_OUT" in /*) ;; *) RMP_E2E_OUT="$PLUGIN_ROOT/$RMP_E2E_OUT" ;; esac
mkdir -p "$RMP_E2E_OUT"

status=0
scripts=()
if [ $# -gt 0 ]; then
  for s in "$@"; do scripts+=("$PLUGIN_ROOT/$s"); done
else
  if [ "${RMP_E2E_SMOKE:-1}" != 0 ]; then
    export RMP_ROUTES_FILE="$REDMINE_DIR/tmp/e2e-routes-$PLUGIN_NAME.txt"
    RAILS_ENV="$RMP_SERVER_ENV" run bundle exec rails runner "$PLUGIN_ROOT/.codex/e2e/routes.rb" "$PLUGIN_NAME" > "$RMP_ROUTES_FILE"
    echo "== smoke: $(wc -l < "$RMP_ROUTES_FILE") plugin GET route(s)"
    (cd "$PLUGIN_ROOT" && node .codex/e2e/smoke.mjs) || status=1
  fi
  if [ "${RMP_E2E_CORE:-1}" != 0 ]; then
    echo "== core flows"
    (cd "$PLUGIN_ROOT" && node .codex/e2e/core.mjs) || status=1
  fi
  if [ -d "$PLUGIN_ROOT/test/e2e" ]; then
    while IFS= read -r f; do scripts+=("$f"); done < <(find "$PLUGIN_ROOT/test/e2e" -name '*.mjs' | sort)
  fi
fi

for s in "${scripts[@]}"; do
  echo "== ${s#"$PLUGIN_ROOT"/}"
  (cd "$PLUGIN_ROOT" && node "$s") || status=1
done
[ ${#scripts[@]} -gt 0 ] || echo "No scenarios in test/e2e/ yet: write one per feature (see .codex/e2e/lib.mjs)."
echo "Screenshots: ${RMP_E2E_OUT#"$PLUGIN_ROOT"/}"
exit $status
