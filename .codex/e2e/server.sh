#!/usr/bin/env bash
# Usage: server.sh start|stop <name> <port> [env]   (Redmine version derived from name: b51/m51 -> 5.1, b70 -> 7.0, b61 -> 6.1)
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
E2E_DIR="${E2E_DIR:-${DCF_WORK_DIR:?set DCF_WORK_DIR or E2E_DIR}/e2e}"
DCF_WORK_DIR="${DCF_WORK_DIR:-$(dirname "$E2E_DIR")}"
export E2E_DIR DCF_WORK_DIR
CMD=$1 NAME=$2 PORT=$3 ENVN=${4:-development}
DIR=$E2E_DIR/$NAME
case "$NAME" in *51) VER=5.1;; *60) VER=6.0;; *61) VER=6.1;; *70) VER=7.0;; esac
if [ "$CMD" = stop ]; then
  [ -f "$DIR/tmp/pids/server.pid" ] && kill "$(cat "$DIR/tmp/pids/server.pid")" 2>/dev/null; sleep 2; rm -f "$DIR/tmp/pids/server.pid"; echo stopped; exit 0
fi
source "$REPO/.codex/lib/common.sh"
dcf_select_ruby "$VER" 2>/dev/null
cd "$DIR" || exit 1
export SECRET_KEY_BASE=e2e0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
[ "$ENVN" = production ] && export RAILS_SERVE_STATIC_FILES=1 RAILS_LOG_LEVEL=${RAILS_LOG_LEVEL:-info}
RAILS_ENV=$ENVN nohup bundle exec rails server -b 127.0.0.1 -p "$PORT" -e "$ENVN" > "$DIR/log/server.out" 2>&1 &
for i in $(seq 1 90); do curl -fs -o /dev/null "http://127.0.0.1:$PORT/login" && { echo "up $NAME :$PORT ($ENVN)"; exit 0; }; sleep 1; done
echo "FAILED to start $NAME"; tail -20 "$DIR/log/server.out"; exit 1
