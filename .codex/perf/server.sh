#!/usr/bin/env bash
# Usage: server.sh start|stop|pid <name> <port>   name: m51 p51 m61 p61 (checkouts under $E2E_DIR)
# One puma process, 1 thread, single mode, production. Pid file in $PERF_DIR/run/<name>.pid, log in <checkout>/log/server.out.
source "$(dirname "$0")/common.sh"
CMD=$1 NAME=$2 PORT=${3:-}
DIR=$E/$NAME
PIDF=$P/run/$NAME.pid
case "$NAME" in *51) VER=5.1;; *61) VER=6.1;; esac
case "$CMD" in
  pid) cat "$PIDF" 2>/dev/null; exit 0;;
  stop)
    if [ -f "$PIDF" ]; then
      pid=$(cat "$PIDF"); kill "$pid" 2>/dev/null
      for i in $(seq 1 30); do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
      kill -9 "$pid" 2>/dev/null; rm -f "$PIDF"
    fi
    echo "stopped $NAME"; exit 0;;
  start)
    "$0" stop "$NAME" >/dev/null
    dcf_select_ruby "$VER" >/dev/null 2>&1
    cd "$DIR" || exit 1
    prod_env
    export RAILS_MAX_THREADS=1
    : > "$DIR/log/perf.log"
    nohup bundle exec puma -e production -t 1:1 -w 0 -b "tcp://127.0.0.1:$PORT" config.ru > "$DIR/log/server.out" 2>&1 &
    echo $! > "$PIDF"
    for i in $(seq 1 120); do
      curl -fs -o /dev/null "http://127.0.0.1:$PORT/login" && { echo "up $NAME :$PORT pid $(cat "$PIDF")"; exit 0; }
      kill -0 "$(cat "$PIDF")" 2>/dev/null || break
      sleep 1
    done
    echo "FAILED to start $NAME"; tail -30 "$DIR/log/server.out"; exit 1;;
esac
