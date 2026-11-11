#!/usr/bin/env bash
# Pull the shared memory of a project from the memory repository into the local auto
# memory directory of the current Claude Code session.
#
# Usage: pull.sh <project> <local-memory-dir> [--dry-run] [--mirror]
#   --dry-run : classify each file, write nothing
#   --mirror  : also delete local files that are absent from the repository
#
# Each file is classified nouveau, identique, depot, local, fusion or CONFLIT (see common.sh).
# Exit codes: 0 ok, 1 usage, 2 git error, 3 project unknown, 10 no repository configured.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

PROJECT="${1:-}"
LOCAL="${2:-}"
DRY_RUN=0
MIRROR=0
if [[ -z "$PROJECT" || -z "$LOCAL" ]]; then
  echo "usage: pull.sh <project> <local-memory-dir> [--dry-run] [--mirror]" >&2
  exit 1
fi
shift 2
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --mirror) MIRROR=1 ;;
    *) echo "argument inconnu: $arg" >&2; exit 1 ;;
  esac
done

read_repo_url
clone_repo ""
resolve_project "$PROJECT"

if ! git -C "$CLONE" cat-file -e "HEAD:$TARGET" 2>/dev/null; then
  echo "Pas de memoire partagee pour le projet '$PROJECT' dans $REPO_URL" >&2
  echo "Projets disponibles :" >&2
  list_projects | sed 's/^/  - /' >&2
  exit 3
fi

sync_from_repo "$TARGET" "$LOCAL" "$PROJECT" "$DRY_RUN" "$MIRROR"
if [[ "$DRY_RUN" -eq 0 && ${#CONFLICTS[@]} -eq 0 ]]; then
  echo "La memoire sera chargee au prochain demarrage de session."
fi
