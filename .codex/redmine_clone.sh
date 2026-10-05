#!/usr/bin/env bash
# Usage: .codex/redmine_clone.sh <5.1|6.0|6.1|7.0>[-stable] [--repo URL] [--force]
# Clones (or refreshes) a shallow Redmine checkout into $DCF_WORK_DIR/redmine-<ver>.
# Idempotent: a managed checkout is fetched and hard-reset to the branch tip.
# Never touches a directory it did not create (exit 3) unless --force.
source "$(dirname "$0")/lib/common.sh"
[ $# -ge 1 ] || dcf_die 2 "usage: $0 <5.1|6.0|6.1|7.0>[-stable] [--repo URL] [--force]"
VER="$(dcf_version "$1")" || dcf_die 2 "unsupported branch '$1' (5.1, 6.0, 6.1, 7.0; DCF_ALLOW_ANY_BRANCH=1 to override)"
shift
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) DCF_REDMINE_REPO="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    *) dcf_die 2 "unknown option $1" ;;
  esac
done
BRANCH="$VER-stable"
DIR="$(dcf_redmine_dir "$VER")"
mkdir -p "$DCF_WORK_DIR"
if [ -d "$DIR/.git" ] && [ -f "$DIR/$DCF_MARKER" ]; then
  dcf_log "refreshing $DIR ($BRANCH from $DCF_REDMINE_REPO)"
  git -C "$DIR" remote set-url origin "$DCF_REDMINE_REPO"
  git -C "$DIR" fetch --depth 1 origin "$BRANCH" || dcf_die 10 "fetch failed"
  git -C "$DIR" reset --hard FETCH_HEAD >/dev/null || dcf_die 10 "reset failed"
elif [ -e "$DIR" ] && [ "$FORCE" != "1" ]; then
  dcf_die 3 "$DIR exists but is not managed by these scripts (use --force to replace it)"
else
  rm -rf "$DIR"
  dcf_log "cloning $BRANCH from $DCF_REDMINE_REPO into $DIR"
  git clone --quiet --depth 1 --branch "$BRANCH" "$DCF_REDMINE_REPO" "$DIR" || dcf_die 10 "clone failed"
fi
printf 'repo=%s\nbranch=%s\n' "$DCF_REDMINE_REPO" "$BRANCH" > "$DIR/$DCF_MARKER"
dcf_state_write "$VER"
echo "REDMINE_DIR=$DIR"
echo "REDMINE_COMMIT=$(git -C "$DIR" rev-parse HEAD) $(git -C "$DIR" log -1 --format=%s)"
