#!/usr/bin/env bash
# Exports the plugin of MAIN_REF (default origin/main) to $E2E_DIR/src-main and of BRANCH_REF (default HEAD) to
# $E2E_DIR/src-branch. measure.sh copies src-branch into p51 and p61 when it differs; build.sh uses src-main for m51 and m61.
#   [MAIN_REF=origin/main] [BRANCH_REF=HEAD] refresh_src.sh
source "$(dirname "$0")/common.sh"
MAIN_REF="${MAIN_REF:-origin/main}"
BRANCH_REF="${BRANCH_REF:-HEAD}"
for pair in "main:$MAIN_REF" "branch:$BRANCH_REF"; do
  n="${pair%%:*}"; ref="${pair#*:}"
  rm -rf "${E:?}/src-$n" && mkdir -p "$E/src-$n" && git -C "$REPO" archive "$ref" | tar -x -C "$E/src-$n" || exit 1
  echo "src-$n exported from $ref ($(git -C "$REPO" rev-parse --short "$ref"))"
done
