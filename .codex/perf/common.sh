# Sourced by the perf scripts. Directories (all can be set in the environment):
#   DCF_WORK_DIR  work directory, default ~/.cache/redmine_depending_custom_fields; holds the Redmine checkouts redmine-<ver>
#                 that .codex/redmine_clone.sh makes (same variable as the other .codex scripts)
#   E2E_DIR       the perf checkouts m51 p51 m61 p61 and the exported plugins src-main and src-branch, default $DCF_WORK_DIR/e2e
#   PERF_DIR      data (ids-<ver>.json), logs, run (pid files) and results, default $DCF_WORK_DIR/perf
# H is the directory of the scripts, REPO the plugin repository.
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$H/../.." && pwd)"
source "$REPO/.codex/lib/common.sh"
PERF_DIR="${PERF_DIR:-$DCF_WORK_DIR/perf}"
E2E_DIR="${E2E_DIR:-$DCF_WORK_DIR/e2e}"
export DCF_WORK_DIR PERF_DIR E2E_DIR
P="$PERF_DIR"
E="$E2E_DIR"
export PATH="${NODE_BIN:-/opt/node22/bin}:$PATH"
export PGPASSWORD=redmine
PSQL="psql -q -h localhost -U redmine"
ver_of() { case "$1" in 51) echo 5.1;; 61) echo 6.1;; esac; }
prod_env() {
  export SECRET_KEY_BASE=e2e0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
  export RAILS_ENV=production RAILS_SERVE_STATIC_FILES=1 RAILS_LOG_LEVEL=info
}
# install_plugin <checkout name> <plugin source dir>: replaces the plugin and the mirrored assets, installs the probe.
install_plugin() {
  local name=$1 src=$2 dst=$E/$1
  rm -rf "$dst/plugins/redmine_depending_custom_fields" "$dst/public/plugin_assets/redmine_depending_custom_fields"
  mkdir -p "$dst/plugins/redmine_depending_custom_fields" && cp -a "$src/." "$dst/plugins/redmine_depending_custom_fields/"
  cp "$H/lib/zz_perf_probe.rb" "$dst/config/initializers/zz_perf_probe.rb"
}
mkdir -p "$P/data" "$P/logs" "$P/run" "$P/results" "$E"
