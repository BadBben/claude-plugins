#!/usr/bin/env bash
# Send local work of the durable clone to the memory repository: guards, one commit for what
# is not committed yet in the scope, then git push.
#
# Usage: push.sh [--dry-run|--commit] [scope] [--message "texte"] [--accept-loss] [--force]
#   --dry-run     : show what would reach the repository, write nothing (default)
#   --commit      : commit what is not committed yet in the scope, then push
#   --message     : short recap written into the commit body, before the file list
#   --accept-loss : go on even when files disappear or far more lines are removed than added
#   --force       : let a secret false positive through. It never forces the push itself:
#                   a repository that moved ahead always asks for a pull first.
# Scope (see common.sh): the transverse part always, plus
#   --project <name>    a project, by name (repeatable)
#   --memory-dir <path> the project that holds the auto memory folder of the session
#   --all               every project, on explicit request only
# Without a scope option only the transverse part leaves, and the script says so.
#
# What leaves is the difference between the repository and the last commit of the clone,
# plus the uncommitted work of the scope. Uncommitted work of the other projects is neither
# committed nor pushed: it is listed apart and left exactly as it is. Local commits that are
# already ahead (work committed by a pull, a concluded merge) leave with the push whatever
# they touch, and the script names the other projects they carry. The guards look at the
# content that leaves, read from the tree that will be committed.
#
# Exit codes: 0 ok, 1 usage, 2 git error, 4 repository ahead of the clone (pull first),
#             5 secret found, 6 conflict markers left or merge in progress, 7 loss refused,
#             10 no repository configured, 11 the clone belongs to another repository.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

USAGE="usage: push.sh [--dry-run|--commit] [--project <nom>] [--memory-dir <chemin>] [--all] [--message \"texte\"] [--accept-loss] [--force]"
MODE="--dry-run"
FORCE=0
ACCEPT_LOSS=0
MESSAGE=""
# A while loop rather than for: several options consume the argument that follows them.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|--commit) MODE="$1" ;;
    --force) FORCE=1 ;;
    --accept-loss) ACCEPT_LOSS=1 ;;
    --all) SCOPE_ALL=1 ;;
    --message)
      [[ $# -ge 2 ]] || { echo "--message attend un texte" >&2; exit 1; }
      MESSAGE="$2"; shift ;;
    --project)
      [[ $# -ge 2 ]] || { echo "--project attend un nom de projet" >&2; exit 1; }
      RAW_PROJECTS+="$2"$'\n'; shift ;;
    --memory-dir)
      [[ $# -ge 2 ]] || { echo "--memory-dir attend un chemin" >&2; exit 1; }
      RAW_MEMORY_DIR="$2"; shift ;;
    *)
      echo "argument inconnu: $1" >&2
      echo "$USAGE" >&2
      exit 1 ;;
  esac
  shift
done

make_tmp
ensure_clone

# Guard: a merge left open by a pull must be concluded first.
if merge_in_progress; then
  echo "Une fusion est en cours dans le clone : rien ne peut partir avant sa conclusion." >&2
  echo "Resous les conflits puis pull.sh --conclude, ou pull.sh --abort pour revenir en arriere." >&2
  exit 6
fi

fetch_origin
resolve_branch
require_branch
build_scope
echo "== Portee : $(describe_scope) =="
printf '%s' "$SCOPE_NOTE"

# Guard: never push over commits this clone does not have. There is no way to force it:
# a pull merges them, and nothing of either side is lost.
if [[ "$HAS_UPSTREAM" -eq 1 ]]; then
  if ! have_head || ! g merge-base --is-ancestor "$UPSTREAM" HEAD; then
    count_divergence
    echo "Le depot a avance : $BEHIND commit(s) que ce clone n'a pas encore." >&2
    echo "Fais un pull d'abord (il fusionne avec le travail local), puis relance le push." >&2
    exit 4
  fi
  FROM="$UPSTREAM"
  BEFORE=$(g rev-parse --short "$UPSTREAM")
  RANGE="$UPSTREAM..HEAD"
else
  # Empty repository: everything in the clone is new.
  FROM=$(empty_tree)
  BEFORE=""
  RANGE="HEAD"
fi

# Uncommitted work, split by scope. WORK is the tree a commit of the scope would hold:
# the last commit plus the uncommitted work of the scope, and nothing else.
WORK_ALL=$(work_tree_id)
diff_plain "$(head_tree)" "$WORK_ALL" | split_by_scope "$TMP/pending-in" "$TMP/pending-out"
WORK=$(scoped_tree_id "$TMP/pending-in")
BODY=$(g diff -M --name-status "$FROM" "$WORK")
count_divergence
DIRTY=0
if [[ -s "$TMP/pending-in" ]]; then DIRTY=1; fi

if [[ -z "$BODY" && "$AHEAD" -eq 0 ]]; then
  echo "== Rien a pousser : le depot est deja a jour pour cette portee (dernier commit : ${BEFORE:-aucun}) =="
  print_rest "$TMP/pending-out"
  exit 0
fi

# The files that would reach the repository and still exist in the tree that leaves.
LEAVING=$(diff_plain "$FROM" "$WORK" | awk -F'\t' '$1 != "D" {print $2}')

# Guard: conflict markers left by a careless resolution.
LEFT=$(printf '%s\n' "$LEAVING" | tree_with_markers "$WORK")
if [[ -n "$LEFT" ]]; then
  echo "Marqueurs de conflit non resolus dans :" >&2
  printf '%s\n' "$LEFT" >&2
  exit 6
fi

# Guard: secrets never reach the repository, neither in the files nor in the local commits
# that would travel with them.
HITS=$(printf '%s\n' "$LEAVING" | tree_with_secrets "$WORK")
OLD_HITS=$(commits_with_secrets)
if [[ -n "$HITS" || -n "$OLD_HITS" ]]; then
  if [[ -n "$HITS" ]]; then
    echo "Motif de secret detecte dans :" >&2
    printf '%s\n' "$HITS" >&2
  fi
  if [[ -n "$OLD_HITS" ]]; then
    echo "Motif de secret dans des commits locaux pas encore pousses :" >&2
    printf '%s\n' "$OLD_HITS" >&2
    echo "Corriger le fichier ne suffit pas pour ceux-la : ces commits partiraient avec le push." >&2
  fi
  [[ "$FORCE" -eq 1 ]] || exit 5
fi

SCOPES=$(diff_plain "$FROM" "$WORK" | awk -F'\t' '{print $2}' | scopes_of_paths)
TITLE="memoire($SCOPES): synchro depuis $(host_label) le $(date +%Y-%m-%d)"

if [[ "$DIRTY" -eq 1 ]]; then
  # The proposed message is printed as it will be committed, so the skill can show it verbatim.
  echo "== Message de commit =="
  echo "$TITLE"
  echo
  if [[ -n "$MESSAGE" ]]; then echo "$MESSAGE"; else echo "(recap a rediger par la session)"; fi
  echo
  echo "$BODY"
else
  # Only commits made earlier (work committed by a pull, a concluded merge): they leave as
  # they are, no new commit is written and no recap is needed.
  echo "== Rien de nouveau a commiter : $AHEAD commit(s) locaux deja prets partent tels quels =="
  g log --format='%h %s' "$RANGE"
  if [[ -n "$MESSAGE" ]]; then echo "(--message ignore : aucun nouveau commit n'est ecrit)"; fi
  if [[ -n "$BODY" ]]; then
    echo
    echo "$BODY"
  fi
fi
echo "== Etat d'avant : commit ${BEFORE:-aucun (premier push)} =="
if [[ "$DIRTY" -eq 1 && "$AHEAD" -gt 0 ]]; then
  echo "== Partent aussi $AHEAD commit(s) locaux deja prets =="
  g log --format='%h %s' "$RANGE"
fi

# Commits that are already made leave whole, even where they touch a project outside the
# scope: say it, the user asked for one project and must know what goes with it.
if [[ "$AHEAD" -gt 0 && "$SCOPE_ALL" -eq 0 ]]; then
  CARRIED=$(g diff --no-renames --name-only "$FROM" HEAD | while IFS= read -r p; do
    if ! in_scope "$p"; then echo "$p"; fi
  done | scopes_of_paths)
  if [[ -n "$CARRIED" ]]; then
    echo "Attention : ces commits deja faits touchent aussi d'autres projets, qui partent avec eux : $CARRIED"
  fi
fi

# Uncommitted work of the other projects stays where it is.
print_rest "$TMP/pending-out"

# Guard: a memory should grow or get reorganised, rarely shrink. A deleted file, or far more
# lines removed than added, is flagged and needs an explicit --accept-loss.
measure_loss "$FROM" "$WORK"
if [[ "$LOSS" -eq 1 ]]; then
  echo "== Attention : perte possible. $LOSS_FILES fichier(s) supprime(s), $LOSS_DELETED ligne(s) retiree(s) pour $LOSS_ADDED ajoutee(s) =="
fi

if [[ "$MODE" == "--dry-run" ]]; then
  if [[ "$LOSS" -eq 1 ]]; then echo "Le commit demandera --accept-loss."; fi
  echo "== Simulation : rien n'a ete commite =="
  exit 0
fi

if [[ "$LOSS" -eq 1 && "$ACCEPT_LOSS" -eq 0 ]]; then
  echo "Perte possible : relance avec --accept-loss si l'utilisateur l'a confirmee en connaissance de cause." >&2
  exit 7
fi

ensure_identity
if [[ "$DIRTY" -eq 1 ]]; then
  # The commit is the tree that was just shown and checked: the scope, and nothing else.
  commit_scoped "$WORK" "$TMP/pending-in" "$TITLE" "$MESSAGE" "$BODY" \
    || { echo "Le commit a echoue : rien n'a ete pousse." >&2; exit 2; }
fi

set +e
g push --quiet origin "HEAD:refs/heads/$BRANCH" 2>"$TMP/push.err"
RC=$?
set -e
if [[ "$RC" -ne 0 ]]; then
  cat "$TMP/push.err" >&2
  # A rejection means another device pushed between the fetch and the push.
  if grep -qiE 'rejected|non-fast-forward|fetch first' "$TMP/push.err"; then
    echo "Le depot a avance pendant le push. Le commit est garde dans le clone, rien n'est perdu." >&2
    echo "Fais un pull puis relance le push." >&2
    exit 4
  fi
  echo "git push a echoue. Le commit est garde dans le clone, rien n'est perdu : relance le push quand le depot repond." >&2
  exit 2
fi
echo "== Pousse : $(g log -1 --oneline) =="
