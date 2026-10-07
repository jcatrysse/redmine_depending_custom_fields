#!/usr/bin/env bash
#
# Prepares the Redmine checkout for the plugin's tests: database.yml, bundle,
# migrations. Run ./.codex/redmine_clone.sh first.
#
#   ./.codex/test_setup.sh
#
# Environment:
#   RMP_DB            postgresql (default) | mysql | mariadb
#   RMP_DB_NAME       default redmine_test
#   RMP_DB_USER       default redmine
#   RMP_DB_PASSWORD   default redmine
#   RMP_DB_HOST       default 127.0.0.1
#   RMP_DB_PORT       default 5432 / 3306
#   RMP_PROVISION_DB  1 = install and start a local server with apt (default
#                     outside CI), 0 = a server is already there (CI, docker)
#   RMP_TEST_GEMS     extra test gems for Gemfile.local, space separated. Default:
#                     rspec-rails and rails-controller-testing when the plugin has
#                     a spec/ directory, because several plugins deliberately keep
#                     test gems out of their own Gemfile (it lands in production).
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

RMP_DB="${RMP_DB:-postgresql}"
RMP_DB_NAME="${RMP_DB_NAME:-redmine_test}"
RMP_DB_USER="${RMP_DB_USER:-redmine}"
RMP_DB_PASSWORD="${RMP_DB_PASSWORD:-redmine}"
RMP_DB_HOST="${RMP_DB_HOST:-127.0.0.1}"

case "$RMP_DB" in
  postgresql|postgres|pg) RMP_ENGINE=postgresql; RMP_ADAPTER=postgresql; RMP_DB_PORT="${RMP_DB_PORT:-5432}" ;;
  mysql|mysql2)           RMP_ENGINE=mysql;      RMP_ADAPTER=mysql2;     RMP_DB_PORT="${RMP_DB_PORT:-3306}" ;;
  mariadb)                RMP_ENGINE=mariadb;    RMP_ADAPTER=mysql2;     RMP_DB_PORT="${RMP_DB_PORT:-3306}" ;;
  *) echo "ERROR: RMP_DB must be postgresql, mysql or mariadb, got '$RMP_DB'." >&2; exit 1 ;;
esac

if [ -z "${RMP_PROVISION_DB:-}" ]; then
  if [ "${CI:-}" = "true" ]; then RMP_PROVISION_DB=0; else RMP_PROVISION_DB=1; fi
fi

[ -d "$REDMINE_DIR" ] || {
  echo "ERROR: '$REDMINE_DIR' not found. Run ./.codex/redmine_clone.sh first." >&2
  exit 1
}

rmp_select_ruby install

SUDO=""
[ "$(id -u)" = 0 ] || SUDO=sudo

if [ "$RMP_PROVISION_DB" = 1 ]; then
  echo "Provisioning a local $RMP_ENGINE server (set RMP_PROVISION_DB=0 to skip)."
  $SUDO apt-get update -qq
  if [ "$RMP_ENGINE" = postgresql ]; then
    $SUDO apt-get install -y -qq build-essential libpq-dev postgresql postgresql-contrib
    $SUDO service postgresql start
    $SUDO -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$RMP_DB_USER'" | grep -q 1 ||
      $SUDO -u postgres psql -c "CREATE ROLE $RMP_DB_USER WITH LOGIN CREATEDB PASSWORD '$RMP_DB_PASSWORD';"
  else
    if [ "$RMP_ENGINE" = mysql ]; then
      $SUDO apt-get install -y -qq build-essential default-libmysqlclient-dev mysql-server
    else
      $SUDO apt-get install -y -qq build-essential default-libmysqlclient-dev mariadb-server
    fi
    $SUDO service mariadb start 2>/dev/null || $SUDO service mysql start
    $SUDO mysql -e "CREATE USER IF NOT EXISTS '$RMP_DB_USER'@'%' IDENTIFIED BY '$RMP_DB_PASSWORD';"
    $SUDO mysql -e "CREATE USER IF NOT EXISTS '$RMP_DB_USER'@'localhost' IDENTIFIED BY '$RMP_DB_PASSWORD';"
    $SUDO mysql -e "GRANT ALL ON \`${RMP_DB_NAME}\`.* TO '$RMP_DB_USER'@'%'; GRANT ALL ON \`${RMP_DB_NAME}\`.* TO '$RMP_DB_USER'@'localhost'; FLUSH PRIVILEGES;"
  fi
fi

cat > "$REDMINE_DIR/config/database.yml" <<EOF
test:
  adapter: $RMP_ADAPTER
  database: $RMP_DB_NAME
  host: $RMP_DB_HOST
  port: $RMP_DB_PORT
  username: $RMP_DB_USER
  password: "$RMP_DB_PASSWORD"
  encoding: $([ "$RMP_ENGINE" = postgresql ] && echo unicode || echo utf8mb4)
EOF

# Test gems the plugin does not declare itself.
gems="${RMP_TEST_GEMS-}"
if [ -z "${RMP_TEST_GEMS+x}" ] && [ -d "$REDMINE_DIR/plugins/$PLUGIN_NAME/spec" ] &&
   ! grep -qE "rspec" "$REDMINE_DIR"/plugins/*/{Gemfile,PluginGemfile} 2>/dev/null; then
  gems="rspec-rails rails-controller-testing"
fi
rm -f "$REDMINE_DIR/Gemfile.local"
if [ -n "$gems" ]; then
  { echo "group :test do"; for g in $gems; do echo "  gem '$g'"; done; echo "end"; } > "$REDMINE_DIR/Gemfile.local"
  echo "Gemfile.local: $gems"
fi

export RAILS_ENV=test

(cd "$REDMINE_DIR" && bundle config set --local without 'development')
(cd "$REDMINE_DIR" && bundle config set --local path 'vendor/bundle')

run bundle install

# Redmine ships no schema.rb, but a previous run may have dumped one for another
# adapter, which db:migrate would then try to load into the empty database.
rm -f "$REDMINE_DIR/db/schema.rb"

run bundle exec rake db:create db:migrate
run bundle exec rake redmine:plugins:migrate
rm -f "$REDMINE_DIR/db/schema.rb"

reported="$(run bundle exec rails runner \
  'print ActiveRecord::Base.connection.select_value("SELECT VERSION()")' 2>/dev/null || true)"
echo "Server reports: ${reported:-unknown}"

case "$RMP_ENGINE:$reported" in
  mysql:*MariaDB*|mysql:*mariadb*)
    echo "WARNING: RMP_DB=mysql but the server is MariaDB. They do not behave the same;" >&2
    echo "         install mysql-server, or use RMP_DB=mariadb and mean it." >&2
    ;;
esac

echo "Ready. Run ./.codex/test_plugin.sh"
