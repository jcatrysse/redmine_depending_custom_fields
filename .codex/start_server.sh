#!/usr/bin/env bash
#
# Starts a real Redmine with this plugin, for end-to-end checks in a browser:
# production mode by default (eager loading, compiled assets, caching: the way
# GEOxyz runs it), on its own database next to the test database, seeded with
# users, roles, two projects, issues, a wiki and an attachment. Mail is written
# to files instead of sent. Run ./.codex/redmine_clone.sh and
# ./.codex/test_setup.sh first (same RMP_DB).
#
#   ./.codex/start_server.sh            # start, idempotent; prints URL and logins
#   ./.codex/start_server.sh --stop
#   ./.codex/start_server.sh --reset    # stop, drop the e2e database, start fresh
#
# Environment:
#   RMP_PORT            default 3000
#   RMP_SERVER_ENV      production (default) | development
#   RMP_SERVER_DB_NAME  default redmine_e2e
#   RMP_ADMIN_PASSWORD  default Redmine7Test! (also used for the other users)
#   RMP_SEED=0          skip the seed (an existing database you filled yourself)
#
# Plugin-specific data: put it in test/e2e/seed.rb in this repo; it is run with
# `rails runner` after the generic seed (.codex/e2e/seed.rb), so it can use the
# users and projects that one creates.
set -euo pipefail

# shellcheck source=e2e/env.sh
. "$(dirname "${BASH_SOURCE[0]}")/e2e/env.sh"

RMP_SERVER_DB_NAME="${RMP_SERVER_DB_NAME:-redmine_e2e}"

stop_server() {
  local pid
  [ -f "$RMP_PIDFILE" ] || return 0
  pid="$(cat "$RMP_PIDFILE")"
  kill "$pid" 2>/dev/null || true
  for _ in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
  kill -9 "$pid" 2>/dev/null || true
  rm -f "$RMP_PIDFILE"
  echo "Stopped the server on port $RMP_PORT."

}

case "${1:-}" in
  --stop) stop_server; exit 0 ;;
  --reset) stop_server; reset=1 ;;
  "") reset=0 ;;
  *) echo "ERROR: unknown argument '$1'" >&2; exit 2 ;;
esac

rmp_require_checkout
export LANG="${LANG:-C.UTF-8}" LC_ALL="${LC_ALL:-C.UTF-8}"

# Add (or replace) the server environment in database.yml, copied from the test
# connection test_setup.sh wrote, so both run on the same engine.
run ruby -ryaml -e '
  path, env, name = ARGV
  conf = YAML.load_file(path, aliases: true)
  base = conf.fetch("test") { abort "database.yml has no test section; run ./.codex/test_setup.sh" }
  conf[env] = base.merge("database" => name)
  File.write(path, conf.to_yaml)
' config/database.yml "$RMP_SERVER_ENV" "$RMP_SERVER_DB_NAME"

adapter="$(run ruby -ryaml -e 'print YAML.load_file("config/database.yml", aliases: true)["test"]["adapter"]')"
if [ "$adapter" = mysql2 ] && command -v mysql >/dev/null 2>&1; then
  # test_setup.sh grants the test database only. Best effort for the e2e one: a local
  # server through the socket, or the container from start_database.sh, whose root
  # password is the same as the user's.
  read -r user password host port < <(run ruby -ryaml -e '
    c = YAML.load_file("config/database.yml", aliases: true)["test"]
    puts [c["username"], c["password"], c["host"] || "127.0.0.1", c["port"] || 3306].join(" ")')
  grant="GRANT ALL ON \`${RMP_SERVER_DB_NAME}\`.* TO '$user'@'%'; GRANT ALL ON \`${RMP_SERVER_DB_NAME}\`.* TO '$user'@'localhost'; FLUSH PRIVILEGES;"
  SUDO=""; [ "$(id -u)" = 0 ] || SUDO="sudo -n"
  $SUDO mysql -e "$grant" 2>/dev/null ||
    mysql -h "$host" -P "$port" -uroot -p"$password" -e "$grant" 2>/dev/null || true
fi

if [ ! -f "$REDMINE_DIR/config/configuration.yml" ]; then
  mkdir -p "$REDMINE_DIR/tmp/mails"
  cat > "$REDMINE_DIR/config/configuration.yml" <<YAML
default:
  email_delivery:
    delivery_method: :file
    file_settings:
      location: $REDMINE_DIR/tmp/mails
YAML
  echo "config/configuration.yml: mail goes to tmp/mails"
fi

[ -f "$REDMINE_DIR/config/initializers/secret_token.rb" ] || run bundle exec rake generate_secret_token

export RAILS_ENV="$RMP_SERVER_ENV"
if [ "$reset" = 1 ]; then
  DISABLE_DATABASE_ENVIRONMENT_CHECK=1 run bundle exec rake db:drop || true
fi
# Redmine ships no schema.rb; one left by another adapter would be loaded instead of migrating.
rm -f "$REDMINE_DIR/db/schema.rb"
run bundle exec rake db:create db:migrate redmine:plugins:migrate
rm -f "$REDMINE_DIR/db/schema.rb"

if ! run bundle exec rails runner 'exit(Tracker.any? ? 0 : 1)' >/dev/null 2>&1; then
  REDMINE_LANG=en run bundle exec rake redmine:load_default_data
fi

if [ "${RMP_SEED:-1}" != 0 ]; then
  run bundle exec rails runner "$PLUGIN_ROOT/.codex/e2e/seed.rb"
  if [ -f "$PLUGIN_ROOT/test/e2e/seed.rb" ]; then
    echo "Plugin seed: test/e2e/seed.rb"
    run bundle exec rails runner "$PLUGIN_ROOT/test/e2e/seed.rb"
  fi
fi

if [ -f "$RMP_PIDFILE" ] && kill -0 "$(cat "$RMP_PIDFILE")" 2>/dev/null; then
  echo "Server already running (pid $(cat "$RMP_PIDFILE")); restarting so it sees the current code."
  stop_server
fi
mkdir -p "$REDMINE_DIR/tmp/pids" "$REDMINE_DIR/log"
if [ "${USE_MISE:-0}" = 1 ]; then prefix=("$MISE_BIN" exec "ruby@$RUBY_TARGET" --); else prefix=(); fi
(cd "$REDMINE_DIR" && nohup "${prefix[@]}" bundle exec ruby bin/rails server -e "$RMP_SERVER_ENV" \
  -b 127.0.0.1 -p "$RMP_PORT" -P "$RMP_PIDFILE" > "$RMP_SERVER_LOG" 2>&1 &)

# The first production start compiles the assets, so give it time.
code=000
for _ in $(seq 1 90); do
  code="$(curl -s -o /dev/null -w '%{http_code}' "$RMP_URL/login" || true)"
  [ "$code" = 200 ] && break
  sleep 2
done
if [ "$code" != 200 ]; then
  echo "ERROR: the server did not answer 200 on /login (last: $code). Log: $RMP_SERVER_LOG" >&2
  tail -n 30 "$RMP_SERVER_LOG" >&2 || true
  exit 1
fi

cat <<TXT

Redmine is running: $RMP_URL  ($RMP_SERVER_ENV, database $RMP_SERVER_DB_NAME)
  admin    / $RMP_ADMIN_PASSWORD   administrator
  manager  / $RMP_USER_PASSWORD   member of both projects, role "E2E full" (every permission, plugin ones included)
  reporter / $RMP_USER_PASSWORD   member of e2e-project, core role "Reporter" (no plugin permissions)
  outsider / $RMP_USER_PASSWORD   no membership (e2e-private must stay invisible)
Projects: e2e-project (public, every module enabled), e2e-private (private)
Mail: $REDMINE_DIR/tmp/mails   Log: $REDMINE_DIR/log/$RMP_SERVER_ENV.log
Next: ./.codex/e2e.sh        Stop: ./.codex/start_server.sh --stop
TXT
