#!/usr/bin/env bash
#
# Clones (or updates) a Redmine checkout and installs this plugin into it.
#
#   ./.codex/redmine_clone.sh [5.1-stable|6.1-stable|7.0-stable|7.0-stable-GEOxyz|master]
#
# A branch ending in -GEOxyz comes from GEOxyz's fork (what production runs);
# everything else from the official repository.
#
# Environment:
#   REDMINE_DIR   where to put the checkout (default: <plugin>/redmine)
#   REDMINE_REPO  repository to clone from (overrides the choice above)
#   RMP_EXTRA_PLUGINS  other plugins this one needs, space separated
#                 "<git url>@<branch>", e.g. for helpdesk:
#                 "https://github.com/jcatrysse/redmine_contacts.git@redmine70-migration"
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

REDMINE_VERSION="${1:-7.0-stable-GEOxyz}"
case "$REDMINE_VERSION" in
  *-GEOxyz) default_repo=https://github.com/jcatrysse/redmine.git ;;
  *)        default_repo=https://github.com/redmine/redmine.git ;;
esac
REDMINE_REPO="${REDMINE_REPO:-$default_repo}"

for tool in git rsync; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "ERROR: '$tool' is required but not installed." >&2
    exit 1
  }
done

if ! git ls-remote --heads "$REDMINE_REPO" "$REDMINE_VERSION" | grep -q "refs/heads/$REDMINE_VERSION\$"; then
  echo "ERROR: branch '$REDMINE_VERSION' not found on $REDMINE_REPO" >&2
  exit 1
fi

if [ ! -d "$REDMINE_DIR/.git" ]; then
  git clone --depth 1 --branch "$REDMINE_VERSION" "$REDMINE_REPO" "$REDMINE_DIR"
else
  git -C "$REDMINE_DIR" fetch --depth 1 "$REDMINE_REPO" "$REDMINE_VERSION"
  git -C "$REDMINE_DIR" checkout -B "$REDMINE_VERSION" FETCH_HEAD
fi

# --delete so that a file removed from the plugin also disappears from the
# checkout. The Redmine checkout itself is excluded when it sits inside the plugin.
excludes=(--exclude '/.git/')
case "$REDMINE_DIR" in
  "$PLUGIN_ROOT"/*) excludes+=(--exclude "/${REDMINE_DIR#"$PLUGIN_ROOT"/}/") ;;
esac
mkdir -p "$REDMINE_DIR/plugins/$PLUGIN_NAME"
rsync -a --delete "${excludes[@]}" "$PLUGIN_ROOT/" "$REDMINE_DIR/plugins/$PLUGIN_NAME/"

for extra in ${RMP_EXTRA_PLUGINS:-}; do
  url="${extra%@*}"; branch="${extra##*@}"
  tmp="$(mktemp -d)"
  git clone --depth 1 --branch "$branch" "$url" "$tmp/p"
  id="$(sed -n -E "s/^[[:space:]]*Redmine::Plugin\.register[[:space:](]*:?['\"]?([a-z0-9_]+).*/\1/p" "$tmp/p/init.rb" | head -n 1)"
  rm -rf "$REDMINE_DIR/plugins/$id"
  mv "$tmp/p" "$REDMINE_DIR/plugins/$id"
  rm -rf "$REDMINE_DIR/plugins/$id/.git" "$tmp"
  echo "Installed dependency $id from $url@$branch"
done

echo "Installed $PLUGIN_NAME into $REDMINE_DIR at $REDMINE_VERSION ($REDMINE_REPO)"
