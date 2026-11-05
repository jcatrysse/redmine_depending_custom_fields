#!/bin/bash
# usage: reseed.sh c51 5.1

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
E2E_DIR="${E2E_DIR:-${DCF_WORK_DIR:?set DCF_WORK_DIR or E2E_DIR}/e2e}"
DCF_WORK_DIR="${DCF_WORK_DIR:-$(dirname "$E2E_DIR")}"
export E2E_DIR DCF_WORK_DIR
cd "$E2E_DIR/$1" || exit 1
source "$REPO/.codex/lib/common.sh" && dcf_select_ruby "$2" >/dev/null 2>&1 && RAILS_ENV=development bundle exec rails runner "$HERE/seed.rb" 2>&1 | tail -3
