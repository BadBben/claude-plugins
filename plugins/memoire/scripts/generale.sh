#!/usr/bin/env bash
# Keep a local working copy of the general memory (general/ in the repository) and push it back.
#
# Usage: generale.sh path
#        generale.sh pull [--dry-run] [--mirror]
#        generale.sh push [--dry-run|--commit] [--force] [--accept-loss] [--message "texte"]
#   path : print the local directory of the general memory
#   pull : synchronise general/ from the repository into that directory (three-way merge)
#   push : commit and push that directory into general/ (--accept-loss when files disappear)
#
# Exit codes: 0 ok, 1 usage, 2 git error, 4 repository moved, 5 secret found,
#             6 unresolved conflict markers, 7 loss refused, 10 no repository configured.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

CMD="${1:-}"
shift || true
DRY_RUN=0
MIRROR=0
MODE="--dry-run"
FORCE=0
ACCEPT_LOSS=0
MESSAGE=""

case "$CMD" in
  path)
    display_path "$GENERAL_DIR"
    exit 0 ;;
  pull)
    for arg in "$@"; do
      case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --mirror) MIRROR=1 ;;
        *) echo "argument inconnu: $arg" >&2; exit 1 ;;
      esac
    done
    read_repo_url
    clone_repo general
    if [[ ! -d "$CLONE/general" ]]; then
      mkdir -p "$GENERAL_DIR"
      echo "Le depot n'a pas encore de dossier general/ : rien a charger, un push le creera."
      echo "Copie locale : $(display_path "$GENERAL_DIR")"
      exit 0
    fi
    sync_from_repo general "$GENERAL_DIR" general "$DRY_RUN" "$MIRROR"
    echo "Copie locale : $(display_path "$GENERAL_DIR")" ;;
  push)
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
    clone_repo general
    push_to_repo general "$GENERAL_DIR" general "$MODE" "$FORCE" "$MESSAGE" "$ACCEPT_LOSS" ;;
  *)
    echo "usage: generale.sh path | pull [--dry-run] [--mirror] | push [--dry-run|--commit] [--force] [--accept-loss] [--message \"texte\"]" >&2
    exit 1 ;;
esac
