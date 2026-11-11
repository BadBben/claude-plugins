#!/usr/bin/env bash
# Locate the general memory (general/ in the durable clone) and show its index.
#
# Usage: generale.sh [show]
#        generale.sh path
#        generale.sh --compare-old
#   show          : print the folder of the general memory and its index (default)
#   path          : print only the folder, for a session that already knows the index
#   --compare-old : compare the local copy kept by the 0.6.x versions with the clone,
#                   read-only, to see what a migration would have to bring over
#
# The general memory is no longer a separate copy: it is a folder of the clone, read in
# place and synchronised with everything else by pull.sh and push.sh. Reading works offline,
# on the state of the last pull.
#
# Exit codes: 0 ok, 1 usage, 2 git error, 10 no repository configured,
#             11 the clone belongs to another repository.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

CMD="${1:-show}"
GENERAL_DIR="$CLONE/general"

make_tmp

case "$CMD" in
  path)
    ensure_clone
    display_path "$GENERAL_DIR" ;;

  show)
    ensure_clone
    fetch_origin soft
    resolve_branch
    count_divergence
    echo "== Memoire generale : $(display_path "$GENERAL_DIR") =="
    if [[ "$BEHIND" -gt 0 ]]; then
      echo "(le depot a $BEHIND commit(s) que ce clone n'a pas encore : un pull mettrait cette memoire a jour)"
    fi
    if [[ -f "$GENERAL_DIR/MEMORY.md" ]]; then
      echo "== MEMORY.md =="
      cat "$GENERAL_DIR/MEMORY.md"
    else
      echo "Pas encore de memoire generale dans le clone : la premiere fiche, et son index MEMORY.md, la creeront."
    fi ;;

  --compare-old|compare-old)
    ensure_clone
    if [[ ! -d "$LEGACY_GENERAL_DIR" ]]; then
      echo "Pas d'ancienne copie locale ($(display_path "$LEGACY_GENERAL_DIR")) : rien a comparer."
      exit 0
    fi
    echo "== Ancienne copie : $(display_path "$LEGACY_GENERAL_DIR") =="
    echo "== Dans le clone  : $(display_path "$GENERAL_DIR") =="
    compare_dirs "$LEGACY_GENERAL_DIR" "$GENERAL_DIR"
    echo "Rien n'a ete modifie, ni dans l'ancienne copie ni dans le clone." ;;

  pull|push)
    echo "generale.sh $CMD n'existe plus : la memoire generale suit le reste du depot, par pull.sh et push.sh." >&2
    exit 1 ;;

  *)
    echo "usage: generale.sh [show] | path | --compare-old" >&2
    exit 1 ;;
esac
