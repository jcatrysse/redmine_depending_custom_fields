#!/usr/bin/env bash
# Shared helpers for the .codex scripts. Sourced, never executed directly.
# Exit codes (shared by all scripts):
#   0 ok | 1 checks/tests failed | 2 usage | 3 unmanaged target dir
#   4 system dependency missing | 5 database unreachable | 6 setup missing
#   10 clone/fetch failed | 11 bundle install failed | 12 db setup failed
#   13 plugin migration failed
set -o pipefail

DCF_PLUGIN_NAME="redmine_depending_custom_fields"
DCF_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DCF_PLUGIN_DIR="$(cd "$DCF_SCRIPT_DIR/.." && pwd)"
DCF_WORK_DIR="${DCF_WORK_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/$DCF_PLUGIN_NAME}"
DCF_REDMINE_REPO="${DCF_REDMINE_REPO:-https://github.com/redmine/redmine.git}"
DCF_MARKER=".dcf-managed"

dcf_log() { printf '[dcf %s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
dcf_die() { local code="$1"; shift; dcf_log "ERROR: $*"; exit "$code"; }

# 5.1 | 5.1-stable -> 5.1 ; refuses anything outside the supported matrix
# unless DCF_ALLOW_ANY_BRANCH=1.
dcf_version() {
  local v="${1%-stable}"
  case "$v" in
    5.1|6.0|6.1|7.0) printf '%s' "$v" ;;
    *) if [ "${DCF_ALLOW_ANY_BRANCH:-0}" = "1" ]; then printf '%s' "$v"; else return 1; fi ;;
  esac
}

dcf_redmine_dir() { printf '%s/redmine-%s' "$DCF_WORK_DIR" "$1"; }

# Preferred Ruby per Redmine version: CI pins (3.2.5 / 3.3.9 / 3.4.5) first,
# then the versions proven locally (3.2.6 for 5.1, 3.3.6 for 6.x/7.0).
dcf_ruby_candidates() {
  case "$1" in
    5.1) echo "3.2.5 3.2.6 3.2" ;;
    6.0) echo "3.3.9 3.3.6 3.3" ;;
    6.1) echo "3.3.9 3.3.6 3.4.5 3.4 3.3" ;;
    7.0) echo "3.4.5 3.3.6 3.4 3.3" ;;
    *)   echo "3.3" ;;
  esac
}

# Selects Ruby via rbenv when available; otherwise accepts the ruby on PATH
# if its version starts with one of the candidates. Exports RBENV_VERSION.
dcf_select_ruby() {
  local ver="$1" c installed
  # Never trust an inherited RBENV_VERSION (a previous suite may have set it for
  # another Redmine version); only DCF_RUBY_VERSION pins the choice.
  unset RBENV_VERSION
  if [ -n "${DCF_RUBY_VERSION:-}" ]; then export RBENV_VERSION="$DCF_RUBY_VERSION"; fi
  if [ -d /opt/rbenv ]; then export PATH="/opt/rbenv/shims:/opt/rbenv/bin:$PATH"; fi
  if [ -z "${RBENV_VERSION:-}" ] && command -v rbenv >/dev/null 2>&1; then
    installed="$(rbenv versions --bare 2>/dev/null)"
    for c in $(dcf_ruby_candidates "$ver"); do
      local hit; hit="$(printf '%s\n' "$installed" | grep -E "^${c//./\\.}(\.|$)" | sort -V | tail -1)"
      if [ -n "$hit" ]; then export RBENV_VERSION="$hit"; break; fi
    done
  fi
  command -v ruby >/dev/null 2>&1 || dcf_die 4 "no ruby found for Redmine $ver"
  local rv; rv="$(ruby -e 'print RUBY_VERSION')" || dcf_die 4 "ruby not runnable (RBENV_VERSION=${RBENV_VERSION:-unset})"
  for c in $(dcf_ruby_candidates "$ver"); do
    case "$rv" in "$c"*) dcf_log "Ruby $rv for Redmine $ver"; return 0 ;; esac
  done
  # Not fatal: bundler enforces core's Gemfile `ruby` constraint anyway.
  dcf_log "WARNING: Ruby $rv is not a usual pick for Redmine $ver ($(dcf_ruby_candidates "$ver"))"
}

# Reads MAJOR.MINOR from a Redmine checkout (directory names are not trusted).
dcf_detect_version() {
  ruby -e 'src = File.read(ARGV[0]); print src[/MAJOR\s*=\s*(\d+)/, 1], ".", src[/MINOR\s*=\s*(\d+)/, 1]' \
    "$1/lib/redmine/version.rb" 2>/dev/null
}

# Remembers the last version used so later scripts work without arguments.
dcf_state_write() { mkdir -p "$DCF_WORK_DIR"; printf '%s\n' "$1" > "$DCF_WORK_DIR/current"; }
dcf_state_read() { [ -f "$DCF_WORK_DIR/current" ] && cat "$DCF_WORK_DIR/current"; }

# Copies the working tree (not only commits) into the Redmine plugin dir. The
# copy stays exact (removed files disappear), like a fresh CI checkout. Uses
# rsync when available, otherwise a clean tar copy.
dcf_sync_plugin() {
  local rdir="$1" dest="$1/plugins/$DCF_PLUGIN_NAME"
  if command -v rsync >/dev/null 2>&1; then
    mkdir -p "$dest"
    rsync -a --delete --exclude .git/ --exclude node_modules/ --exclude coverage/ \
          --exclude tmp/ --exclude log/ "$DCF_PLUGIN_DIR/" "$dest/"
  else
    rm -rf "$dest" && mkdir -p "$dest"
    (cd "$DCF_PLUGIN_DIR" && tar --exclude=./.git --exclude=./node_modules --exclude=./coverage \
       --exclude=./tmp --exclude=./log -cf - .) | (cd "$dest" && tar -xf -)
  fi
}
