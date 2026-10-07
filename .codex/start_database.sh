#!/usr/bin/env bash
#
# Starts the one database engine a CI job needs, and waits for it.
#
#   ./.codex/start_database.sh postgresql|mysql|mariadb
#
# This exists because GitHub cannot start a service container conditionally. With
# the engine axis declared as `services:`, every job started all three and pulled
# all three images — so a job testing MariaDB failed when Docker Hub timed out on
# the PostgreSQL image it was never going to use. Three engines is deliberate;
# three containers per job was not.
#
# CI only. A developer either lets test_setup.sh provision a server
# (RMP_PROVISION_DB=1) or points RMP_DB_HOST at one they already run.
set -euo pipefail

ENGINE="${1:?usage: start_database.sh postgresql|mysql|mariadb}"
NAME="${RMP_DB_CONTAINER:-redmine-plugin-db}"
# Throwaway credentials for a throwaway container, matching test_setup.sh's
# defaults. Not secrets.
DB_NAME="${RMP_DB_NAME:-redmine_test}"
DB_USER="${RMP_DB_USER:-redmine}"
DB_PASSWORD="${RMP_DB_PASSWORD:-redmine}"

case "$ENGINE" in
  postgresql)
    image=postgres:16
    port=5432
    env=(-e "POSTGRES_USER=$DB_USER" -e "POSTGRES_PASSWORD=$DB_PASSWORD" -e "POSTGRES_DB=$DB_NAME")
    # -U so the probe uses a role that exists; without it the server logs a FATAL
    # about "root" every couple of seconds and buries anything real.
    ready=(pg_isready -U "$DB_USER" -d "$DB_NAME")
    ;;
  mysql)
    image=mysql:8
    port=3306
    env=(-e "MYSQL_ROOT_PASSWORD=$DB_PASSWORD" -e "MYSQL_DATABASE=$DB_NAME"
         -e "MYSQL_USER=$DB_USER" -e "MYSQL_PASSWORD=$DB_PASSWORD")
    ready=(mysqladmin ping -uroot "-p$DB_PASSWORD")
    ;;
  mariadb)
    image=mariadb:11
    port=3306
    env=(-e "MARIADB_ROOT_PASSWORD=$DB_PASSWORD" -e "MARIADB_DATABASE=$DB_NAME"
         -e "MARIADB_USER=$DB_USER" -e "MARIADB_PASSWORD=$DB_PASSWORD")
    # The image's own script, so this does not depend on which client binaries
    # the tag happens to ship.
    ready=(healthcheck.sh --connect --innodb_initialized)
    ;;
  *)
    echo "ERROR: unknown engine '$ENGINE'." >&2
    exit 1
    ;;
esac

# Docker Hub is the single point of failure here, and it does time out. Retrying
# the pull separately from the run keeps the failure legible when it is fatal.
for attempt in 1 2 3; do
  if docker pull "$image"; then
    break
  fi
  [ "$attempt" = 3 ] && { echo "ERROR: could not pull $image after 3 attempts." >&2; exit 1; }
  echo "pull failed, retrying in $((attempt * 10))s..."
  sleep $((attempt * 10))
done

# test_setup.sh defaults to the same port per adapter, but if someone overrides it
# the container has to follow, or database.yml would point at nothing.
host_port="${RMP_DB_PORT:-$port}"

docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" -p "$host_port:$port" "${env[@]}" "$image" >/dev/null

echo "waiting for $ENGINE to accept connections..."
for _ in $(seq 60); do
  if docker exec "$NAME" "${ready[@]}" >/dev/null 2>&1; then
    echo "$ENGINE is ready on port $host_port."
    exit 0
  fi
  sleep 2
done

echo "ERROR: $ENGINE did not become ready within 120s. Container log:" >&2
docker logs "$NAME" >&2
exit 1
