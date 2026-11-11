#!/usr/bin/env bash
# Put the folder of a project, or the general memory, back to the state of a given commit,
# inside the durable clone.
#
# Usage: revert.sh <project | general> [--count N]
#        revert.sh <project | general> <commit> [--dry-run] [--force]
#   without a commit : list the last commits that touched the folder (default 10)
#   with a commit    : restore the folder as it was at that commit
#   --dry-run        : show what the restore would change, write nothing
#   --force          : let a secret false positive through when local work is committed first
#
# The repository is not modified and no history is rewritten. Work of the folder that is
# not committed yet is committed locally first, so nothing is lost. The folder then becomes
# what it was at that commit; the next push sends this older state as a new commit (the
# loss guard will ask for --accept-loss). The newer commits stay readable.
#
# Exit codes: 0 ok, 1 usage, 2 git error, 3 project or commit unknown, 5 secret found,
#             6 merge in progress, 10 no repository configured,
#             11 the clone belongs to another repository.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

USAGE="usage: revert.sh <projet|general> [--count N] | revert.sh <projet|general> <commit> [--dry-run] [--force]"
NAME="${1:-}"
SHA=""
COUNT=10
DRY_RUN=0
FORCE=0
if [[ -z "$NAME" || "$NAME" == --* ]]; then
  echo "$USAGE" >&2
  exit 1
fi
shift
# A while loop rather than for: --count consumes the argument that follows it.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --count)
      [[ $# -ge 2 ]] || { echo "--count attend un nombre" >&2; exit 1; }
      COUNT="$2"; shift ;;
    --dry-run) DRY_RUN=1 ;;
    --force) FORCE=1 ;;
    --*) echo "argument inconnu: $1" >&2; echo "$USAGE" >&2; exit 1 ;;
    *)
      [[ -z "$SHA" ]] || { echo "un seul commit a la fois" >&2; exit 1; }
      SHA="$1" ;;
  esac
  shift
done

make_tmp
ensure_clone
resolve_branch

# "generale" is the name of the skill: accept it for the general memory too.
if [[ "$NAME" == "general" || "$NAME" == "generale" ]]; then
  TARGET="general"
  LABEL="general"
else
  resolve_project "$NAME"
  LABEL="$PROJECT"
fi
if ! have_head || { ! g cat-file -e "HEAD:$TARGET" 2>/dev/null && [[ ! -d "$CLONE/$TARGET" ]]; }; then
  echo "Pas de dossier $TARGET dans le clone. Projets connus :" >&2
  list_projects | sed 's/^/  - /' >&2
  exit 3
fi

if [[ -z "$SHA" ]]; then
  TAB=$'\t'
  echo "== Derniers commits de $TARGET (du plus recent au plus ancien) =="
  for h in $(g log -n "$COUNT" --format=%h -- "$TARGET"); do
    g show -s --date=short --format='%h %ad %s' "$h"
    # First line of the recap, when the commit has one: skip the file list of the body.
    recap=$(g show -s --format=%b "$h" | grep -v '^[[:space:]]*$' | grep -vE "^[AMDRCT][0-9]*${TAB}" | head -1 || true)
    if [[ -n "$recap" ]]; then echo "    $recap"; fi
  done
  count_divergence
  if [[ "$BEHIND" -gt 0 ]]; then
    echo "(le depot a $BEHIND commit(s) que ce clone n'a pas encore : un pull les ajoutera a cette liste)"
  fi
  exit 0
fi

# Restore mode.
if ! g cat-file -e "$SHA^{commit}" 2>/dev/null; then
  echo "Commit inconnu dans le clone : $SHA" >&2
  exit 3
fi
if ! g cat-file -e "$SHA:$TARGET" 2>/dev/null; then
  echo "Le dossier $TARGET n'existe pas au commit $SHA" >&2
  exit 3
fi
SHORT=$(g rev-parse --short "$SHA")
WORK=$(work_tree_id)

# From the working state to the commit: A exists only at the commit, D exists only now.
CHANGES=$(g diff --no-renames --name-status "$WORK" "$SHA" -- "$TARGET")
RESTORE_N=0
REMOVE_N=0
echo "== Etat au commit $SHORT compare au dossier actuel =="
while IFS=$'\t' read -r status path; do
  [[ -n "$status" ]] || continue
  case "$status" in
    A) echo "a restaurer : $path"; RESTORE_N=$((RESTORE_N + 1)) ;;
    D) echo "a retirer   : $path (absent a ce commit)"; REMOVE_N=$((REMOVE_N + 1)) ;;
    *) echo "a remettre  : $path (contenu different)"; RESTORE_N=$((RESTORE_N + 1)) ;;
  esac
done <<< "$CHANGES"
TOTAL=$(g ls-tree -r --name-only "$SHA" -- "$TARGET" | grep -c . || true)
echo "== $RESTORE_N fichier(s) a restaurer, $REMOVE_N a retirer, $((TOTAL - RESTORE_N)) identique(s) =="

if [[ -z "$CHANGES" ]]; then
  echo "Le dossier est deja dans l'etat de ce commit : rien a faire."
  exit 0
fi
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "== Simulation : rien n'a ete ecrit =="
  exit 0
fi

if merge_in_progress; then
  echo "Une fusion est en cours dans le clone : conclus-la (pull.sh --conclude) ou annule-la (pull.sh --abort) avant un retour en arriere." >&2
  exit 6
fi

# Work of the folder that is not committed yet goes into a local commit first: the restore
# overwrites the files, and this commit is what keeps the current state reachable.
PENDING=$(g diff --no-renames --name-status "$(head_tree)" "$WORK" -- "$TARGET")
if [[ -n "$PENDING" ]]; then
  HITS=$(printf '%s\n' "$PENDING" | awk -F'\t' '$1 != "D" {print $2}' | files_with_secrets)
  if [[ -n "$HITS" ]]; then
    echo "Motif de secret detecte dans le travail local :" >&2
    printf '%s\n' "$HITS" >&2
    if [[ "$FORCE" -eq 0 ]]; then
      echo "Corrige ces fichiers puis relance. Rien n'a ete commite ni restaure." >&2
      exit 5
    fi
  fi
  ensure_identity
  g add -A -- "$TARGET"
  g commit -q -m "memoire($LABEL): travail local sur $(host_label) avant revert du $(date +%Y-%m-%d)" -m "$PENDING" -- "$TARGET" \
    || { echo "Le commit du travail local a echoue : rien n'a ete restaure." >&2; exit 2; }
  echo "(travail local du dossier commite avant le retour en arriere : $(g log -1 --format=%h))"
fi

# Mirror: tracked files that did not exist at that commit are removed, the others get the
# content they had. Everything under the folder is tracked at this point.
g restore --source="$SHA" --staged --worktree -- "$TARGET" || { echo "git restore a echoue" >&2; exit 2; }
echo "== $LABEL remis dans l'etat du commit $SHORT, dans $(display_path "$CLONE/$TARGET") =="
echo "Le depot n'est pas modifie. Pour y renvoyer cet etat : push (la perte sera signalee, c'est attendu)."
echo "La memoire sera chargee au prochain demarrage de session."
