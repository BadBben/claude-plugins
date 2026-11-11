#!/usr/bin/env bash
# Push the local auto memory of a project into the memory repository.
#
# Usage: push.sh <project> <local-memory-dir> [--dry-run|--commit] [--force] [--accept-loss] [--message "texte"]
#   --dry-run     : show what would change in the repository, write nothing (default)
#   --commit      : copy, commit and push
#   --force       : skip the "repository moved since last sync" and secret guards
#   --accept-loss : commit even when files disappear or far more lines are removed than added
#   --message     : short recap written into the commit body, before the file list
#
# Exit codes: 0 ok, 1 usage, 2 git error, 4 repository moved, 5 secret found,
#             6 unresolved conflict markers, 7 loss refused, 10 no repository configured.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

PROJECT="${1:-}"
LOCAL="${2:-}"
MODE="--dry-run"
FORCE=0
ACCEPT_LOSS=0
MESSAGE=""
if [[ -z "$PROJECT" || -z "$LOCAL" ]]; then
  echo "usage: push.sh <project> <local-memory-dir> [--dry-run|--commit] [--force] [--accept-loss] [--message \"texte\"]" >&2
  exit 1
fi
shift 2
# A while loop rather than for: --message consumes the argument that follows it.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|--commit) MODE="$1" ;;
    --force) FORCE=1 ;;
    --accept-loss) ACCEPT_LOSS=1 ;;
    --message)
      [[ $# -ge 2 ]] || { echo "--message attend un texte" >&2; exit 1; }
      MESSAGE="$2"; shift ;;
    *) echo "argument inconnu: $1" >&2; exit 1 ;;
  esac
  shift
done

read_repo_url
clone_repo ""
resolve_project "$PROJECT"
push_to_repo "$TARGET" "$LOCAL" "$PROJECT" "$MODE" "$FORCE" "$MESSAGE" "$ACCEPT_LOSS"
