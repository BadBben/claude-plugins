#!/usr/bin/env bash
# Bring the durable clone of the memory repository up to date: fetch, then let git merge
# the repository into the local work.
#
# Usage: pull.sh [--dry-run] [scope] [--include <project>]... [--force]
#        pull.sh --conclude [--force]
#        pull.sh --drop <path>
#        pull.sh --abort
#   --dry-run  : show what the pull would change, write nothing
#   --include  : bring one more project into the merge (repeatable), the answer to exit 8
#   --conclude : record the merge once every conflict has been resolved in the files
#   --drop     : during a merge, settle a deletion conflict by removing the file
#   --abort    : cancel the merge in progress and come back to the state before it
#   --force    : let a secret false positive through (never on a real secret)
# Scope (see common.sh): the transverse part always, plus
#   --project <name>    a project, by name (repeatable)
#   --memory-dir <path> the project that holds the auto memory folder of the session
#   --all               every project, on explicit request only
#
# The merge is the merge of the whole repository: git has no other kind. What the scope
# limits is the local work the script commits before merging. Uncommitted work of the scope
# is committed locally, after the secret guard (a secret committed here would travel with
# the history at the next push). Uncommitted work of the other projects is left as it is,
# neither committed nor modified. When the merge would overwrite such work, because the
# repository changed the same files, the script stops before any commit with exit 8 and
# names the projects: --include brings them into the merge.
# Conflicts are not an error: the script exits 0 and lists them, the session resolves them
# with the user in the files, then --conclude records the merge.
#
# Exit codes: 0 ok (conflicts included), 1 usage, 2 git error, 5 secret found,
#             6 merge in progress or conflict markers left, 8 uncommitted work of a project
#             outside the scope would be overwritten, 10 no repository configured,
#             11 the clone belongs to another repository.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

USAGE="usage: pull.sh [--dry-run] [--project <nom>] [--memory-dir <chemin>] [--all] [--include <projet>] [--force] | --conclude [--force] | --drop <chemin> | --abort"
MODE="pull"
DRY_RUN=0
FORCE=0
DROP_PATH=""
# A while loop rather than for: several options consume the argument that follows them.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --force) FORCE=1 ;;
    --all) SCOPE_ALL=1 ;;
    --conclude) MODE="conclude" ;;
    --abort) MODE="abort" ;;
    --drop)
      [[ $# -ge 2 ]] || { echo "--drop attend un chemin" >&2; exit 1; }
      MODE="drop"; DROP_PATH="$2"; shift ;;
    --project|--include)
      [[ $# -ge 2 ]] || { echo "$1 attend un nom de projet" >&2; exit 1; }
      RAW_PROJECTS+="$2"$'\n'; shift ;;
    --memory-dir)
      [[ $# -ge 2 ]] || { echo "--memory-dir attend un chemin" >&2; exit 1; }
      RAW_MEMORY_DIR="$2"; shift ;;
    *) echo "argument inconnu: $1" >&2; echo "$USAGE" >&2; exit 1 ;;
  esac
  shift
done

# Print the unmerged files of the merge in progress, one "label : path" line each. The
# labels say which side did what, in the words the skill uses with the user.
list_conflicts() {
  local entry code path
  while IFS= read -r -d '' entry; do
    code="${entry:0:2}"
    path="${entry:3}"
    case "$code" in
      UU) echo "modifie des deux cotes         : $path" ;;
      AA) echo "cree des deux cotes            : $path" ;;
      UD) echo "modifie ici, supprime au depot : $path" ;;
      DU) echo "supprime ici, modifie au depot : $path" ;;
      AU|UA|DD) echo "deplace ou renomme d'un cote   : $path" ;;
    esac
  done < <(g status --porcelain=v1 --no-renames -z)
}

# Print the summary of what a pull would change, grouped by part of the repository.
# <base> is the common ancestor, <work> the tree of the whole working state, <outside> a
# file of "status<TAB>path" lines: the uncommitted work of projects outside the scope.
# Files identical on both sides are not listed. Sets N_REMOTE, N_BOTH, N_LOCAL, N_REST,
# BOTH_PATHS (changed on both sides) and BLOCKED_PATHS (uncommitted work outside the scope
# that the repository also changed), so call it with a redirection, never in a command
# substitution.
summarize() {
  local base="$1" work="$2" outside="$3" tab=$'\t' lines kind p rank out=""
  N_REMOTE=0
  N_BOTH=0
  N_LOCAL=0
  N_REST=0
  BOTH_PATHS=""
  BLOCKED_PATHS=""
  # Each change is tagged with where it comes from (R repository, L this device, O
  # uncommitted outside the scope), then awk classifies every path. The tag avoids the awk
  # trap of an empty first input.
  lines=$(
    {
      diff_plain "$base" "$UPSTREAM" | sed "s/^/R${tab}/"
      diff_plain "$base" "$work" | sed "s/^/L${tab}/"
      sed "s/^/O${tab}/" "$outside"
    } | awk -F'\t' '
      $1 == "R" { r[$3] = $2 }
      $1 == "L" { l[$3] = $2 }
      $1 == "O" { o[$3] = $2 }
      END {
        for (p in r) {
          # Uncommitted and outside the scope, yet changed by the repository: git would
          # refuse the merge or overwrite the file. Checked before anything else.
          if (p in o) k = "blocked"
          else if (p in l) k = "both"
          else if (r[p] == "A") k = "new"
          else if (r[p] == "D") k = "gone"
          else k = "repo"
          print k "\t" p
        }
        for (p in l) if (!(p in r)) print ((p in o) ? "rest" : "local") "\t" p
        for (p in o) if (!(p in r) && !(p in l)) print "rest\t" p
      }'
  )
  while IFS=$'\t' read -r kind p; do
    [[ -n "$kind" ]] || continue
    case "$kind" in
      both)
        # The same result on both sides (one edit made twice, or deleted twice): nothing to merge.
        if [[ "$(g rev-parse -q --verify "$UPSTREAM:$p" 2>/dev/null || echo absent)" == "$(g rev-parse -q --verify "$work:$p" 2>/dev/null || echo absent)" ]]; then
          continue
        fi
        rank=4; N_BOTH=$((N_BOTH + 1)); BOTH_PATHS+="$p"$'\n' ;;
      new) rank=1; N_REMOTE=$((N_REMOTE + 1)) ;;
      repo) rank=2; N_REMOTE=$((N_REMOTE + 1)) ;;
      gone) rank=3; N_REMOTE=$((N_REMOTE + 1)) ;;
      local) rank=5; N_LOCAL=$((N_LOCAL + 1)) ;;
      rest) rank=6; N_REST=$((N_REST + 1)) ;;
      *) rank=7; BLOCKED_PATHS+="$p"$'\n' ;;
    esac
    scope_of "$p"
    out+="${SCOPE}${tab}${rank}${tab}${p}"$'\n'
  done <<< "$lines"
  printf '%s' "$out" | sort -t "$tab" -k1,1 -k2,2n -k3,3 | awk -F'\t' '
    $1 != scope { scope = $1; print "[" scope "]" }
    $2 == 1 { print "  nouveau           : " $3 }
    $2 == 2 { print "  depot             : " $3 " (seul le depot a change)" }
    $2 == 3 { print "  supprime au depot : " $3 }
    $2 == 4 { print "  les deux          : " $3 " (fusion automatique ou conflit, connu a la fusion)" }
    $2 == 5 { print "  local             : " $3 " (seule cette machine a change, garde, a pousser)" }
    $2 == 6 { print "  reste en local    : " $3 " (autre projet : ni commite ni pousse par cette operation)" }
    $2 == 7 { print "  bloque            : " $3 " (autre projet : travail non commite ici, change aussi au depot)" }'
}

# Print, among the files changed on both sides, the ones git merged by itself: those that
# are not in the list of unmerged files given as argument.
list_auto_merged() {
  local unmerged="$1" p
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    if ! grep -qxF -- "$p" <<< "$unmerged"; then
      echo "fusion automatique             : $p"
    fi
  done <<< "$BOTH_PATHS"
}

# Explain exit 8: which projects hold uncommitted work that the merge would overwrite, and
# the two ways out. Nothing has been committed or merged when this is printed.
explain_blocked() {
  local p last="" projects
  projects=$(printf '%s' "$BLOCKED_PATHS" | scopes_of_paths)
  echo "== Fusion suspendue (code 8) : elle ecraserait du travail non commite d'autres projets =="
  echo "Ces fichiers ont du travail local non commite, hors de la portee, et ont aussi change au depot :"
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    scope_of "$p"
    if [[ "$SCOPE" != "$last" ]]; then
      echo "[$SCOPE]"
      last="$SCOPE"
    fi
    echo "  $p"
  done <<< "$(printf '%s' "$BLOCKED_PATHS" | sort)"
  echo "Projets concernes : $projects"
  echo "Deux facons de continuer :"
  echo "  - relancer avec --include <projet> pour chacun : son travail local sera commite en local, fusionne avec le depot, et partira au prochain push ;"
  echo "  - ou faire d'abord le pull depuis une session de ce projet, puis revenir ici."
  echo "Rien n'a ete commite ni fusionne."
}

make_tmp
ensure_clone

if [[ "$MODE" == "abort" ]]; then
  if ! merge_in_progress; then
    echo "Aucune fusion en cours : rien a annuler."
    exit 0
  fi
  g merge --abort || { echo "git merge --abort a echoue" >&2; exit 2; }
  echo "== Fusion annulee : le clone est revenu a l'etat d'avant la fusion =="
  echo "Le travail local commite avant le pull est garde. Le depot n'a pas ete touche."
  exit 0
fi

if [[ "$MODE" == "drop" ]]; then
  if ! merge_in_progress; then
    echo "Aucune fusion en cours : --drop ne sert qu'a regler un conflit de suppression." >&2
    exit 1
  fi
  # Only a file that is in conflict can be dropped: this is not a general delete command.
  if ! grep -qxF -- "$DROP_PATH" <<< "$(g diff --name-only --diff-filter=U)"; then
    echo "$DROP_PATH n'est pas un fichier en conflit. Fichiers en conflit :" >&2
    list_conflicts >&2
    exit 1
  fi
  rm -f "$CLONE/$DROP_PATH"
  echo "== $DROP_PATH retire : la suppression sera enregistree par pull.sh --conclude =="
  exit 0
fi

if [[ "$MODE" == "conclude" ]]; then
  if ! merge_in_progress; then
    echo "Aucune fusion en cours : rien a conclure."
    exit 0
  fi
  # Only the files that were in conflict are checked and added. The rest of the merge is
  # already staged by git and comes from commits that passed the guards; everything else in
  # the working tree (uncommitted work of other projects, new work written during the
  # merge) must stay out of the merge commit.
  UNMERGED=$(g diff --name-only --diff-filter=U)
  LEFT=$(printf '%s\n' "$UNMERGED" | files_with_markers)
  if [[ -n "$LEFT" ]]; then
    echo "Marqueurs de conflit non resolus dans :" >&2
    printf '%s\n' "$LEFT" >&2
    exit 6
  fi
  HITS=$(printf '%s\n' "$UNMERGED" | files_with_secrets)
  if [[ -n "$HITS" ]]; then
    echo "Motif de secret detecte dans :" >&2
    printf '%s\n' "$HITS" >&2
    [[ "$FORCE" -eq 1 ]] || exit 5
  fi
  ensure_identity
  TITLE="memoire: fusion du depot sur $(host_label) le $(date +%Y-%m-%d)"
  if [[ -n "$UNMERGED" ]]; then
    # -A so that a file removed with --drop is recorded as deleted.
    printf '%s\n' "$UNMERGED" | tr '\n' '\0' > "$TMP/paths-unmerged"
    g --literal-pathspecs add -A --pathspec-from-file="$(display_path "$TMP/paths-unmerged")" --pathspec-file-nul \
      || { echo "git add a echoue sur les fichiers resolus" >&2; exit 2; }
    # One line, so the list of commits shown by revert.sh says what this merge settled.
    RESOLVED=$(printf '%s\n' "$UNMERGED" | paste -sd, - | sed 's/,/, /g')
    g commit -q -m "$TITLE" -m "Conflits resolus : $RESOLVED" || { echo "Le commit de fusion a echoue" >&2; exit 2; }
  else
    g commit -q -m "$TITLE" || { echo "Le commit de fusion a echoue" >&2; exit 2; }
  fi
  echo "== Fusion conclue : $(g log -1 --oneline) =="
  echo "Le resultat est dans le clone, pas encore dans le depot : un push l'enverra."
  exit 0
fi

# Pull mode.
fetch_origin
resolve_branch
require_branch
build_scope
echo "== Depot : $(safe_url "$REPO_URL") (branche $BRANCH) =="
echo "== Portee : $(describe_scope) =="
printf '%s' "$SCOPE_NOTE"

if merge_in_progress; then
  echo "Une fusion est deja en cours dans le clone. Fichiers encore en conflit :" >&2
  list_conflicts >&2
  echo "Resous-les dans les fichiers puis pull.sh --conclude, ou pull.sh --abort pour revenir en arriere." >&2
  exit 6
fi

if [[ "$HAS_UPSTREAM" -eq 0 ]]; then
  echo "== Rien a recuperer : le depot est encore vide =="
  if have_head || [[ -n "$(g status --porcelain)" ]]; then
    echo "Le contenu du clone attend un premier push."
  fi
  exit 0
fi

BASE=""
if have_head; then BASE=$(g merge-base HEAD "$UPSTREAM" 2>/dev/null || true); fi
[[ -n "$BASE" ]] || BASE=$(empty_tree)
# Uncommitted work, split by scope: what this pull may commit, and what it must leave alone.
WORK_ALL=$(work_tree_id)
diff_plain "$(head_tree)" "$WORK_ALL" | split_by_scope "$TMP/pending-in" "$TMP/pending-out"
summarize "$BASE" "$WORK_ALL" "$TMP/pending-out" > "$TMP/summary"

if have_head && g merge-base --is-ancestor "$UPSTREAM" HEAD; then
  echo "== Rien a recuperer : le clone est a jour avec le depot (commit $(g rev-parse --short "$UPSTREAM")) =="
  if [[ "$N_LOCAL" -gt 0 || "$N_REST" -gt 0 ]]; then
    echo "== En attente de push : $N_LOCAL fichier(s) ; restent en local (autres projets) : $N_REST =="
    cat "$TMP/summary"
  fi
  exit 0
fi

echo "== Ce que le pull change, par partie du depot =="
cat "$TMP/summary"
echo "== $N_REMOTE fichier(s) arrivent du depot, $N_BOTH modifie(s) des deux cotes, $N_LOCAL en attente de push, $N_REST restent en local (autres projets) =="

# Guard: uncommitted work outside the scope that the repository also changed. Committing it
# would push another project by side effect, merging over it would lose it: stop here, in
# a simulation too, before anything is written.
if [[ -n "$BLOCKED_PATHS" ]]; then
  explain_blocked >&2
  exit 8
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "== Simulation : rien n'a ete ecrit dans le clone (seule la connaissance du depot a ete rafraichie) =="
  exit 0
fi

# Uncommitted work of the scope is committed first, so git can merge it and nothing is
# lost. The secret guard runs before: a secret committed here would be pushed later with
# the history, even if the file were fixed in between.
if [[ -s "$TMP/pending-in" ]]; then
  WORK=$(scoped_tree_id "$TMP/pending-in")
  HITS=$(awk -F'\t' '$1 != "D" {print $2}' "$TMP/pending-in" | tree_with_secrets "$WORK")
  if [[ -n "$HITS" ]]; then
    echo "Motif de secret detecte dans le travail local :" >&2
    printf '%s\n' "$HITS" >&2
    if [[ "$FORCE" -eq 0 ]]; then
      echo "Corrige ces fichiers puis relance. Rien n'a ete commite ni fusionne." >&2
      exit 5
    fi
  fi
  ensure_identity
  SCOPES=$(cut -f2- "$TMP/pending-in" | scopes_of_paths)
  commit_scoped "$WORK" "$TMP/pending-in" \
    "memoire($SCOPES): travail local sur $(host_label) avant pull du $(date +%Y-%m-%d)" "$(cat "$TMP/pending-in")" \
    || { echo "Le commit du travail local a echoue : rien n'a ete fusionne." >&2; exit 2; }
  echo "(travail local commite avant la fusion : $(g log -1 --format=%h))"
fi

# git refuses to merge while anything is staged. Files of other projects that were staged
# by hand go back to "modified, not staged": their content is not touched, only the index.
if have_head && ! g diff --cached --quiet; then
  g reset -q >/dev/null 2>&1 || true
  echo "(index remis a plat pour la fusion : le contenu des fichiers n'est pas touche)"
fi

ensure_identity
STYLE=$(conflict_style)
# --ff is spelled out so a user setting such as merge.ff=only cannot turn an ordinary merge
# into a failure.
set +e
g -c "merge.conflictStyle=$STYLE" merge --ff --no-edit -m "memoire: fusion du depot sur $(host_label) le $(date +%Y-%m-%d)" "$UPSTREAM" >"$TMP/merge.out" 2>&1
RC=$?
set -e

if [[ "$RC" -ne 0 ]] && ! merge_in_progress; then
  echo "git merge a echoue :" >&2
  cat "$TMP/merge.out" >&2
  exit 2
fi

UNMERGED=$(g diff --name-only --diff-filter=U)
list_auto_merged "$UNMERGED"

if [[ "$RC" -eq 0 ]]; then
  echo "== Pull termine : le clone contient le depot (commit $(g rev-parse --short "$UPSTREAM")) =="
  count_divergence
  if [[ "$AHEAD" -gt 0 ]]; then
    echo "$AHEAD commit(s) locaux attendent un push."
  fi
  if [[ "$N_REST" -gt 0 ]]; then
    echo "$N_REST fichier(s) d'autres projets restent en local, non commites, tels qu'ils etaient."
  fi
  echo "La memoire a jour sera chargee au prochain demarrage de session."
  exit 0
fi

N_CONFLICTS=$(printf '%s\n' "$UNMERGED" | grep -c . || true)
echo "== CONFLITS a resoudre : $N_CONFLICTS fichier(s) =="
list_conflicts
echo "Dans un fichier, chaque conflit est un bloc en trois parties :"
echo "  de <<<<<<< HEAD a |||||||    : la version de cette machine"
echo "  de ||||||| a =======         : l'ancetre commun, avant les deux modifications"
echo "  de ======= a >>>>>>> $UPSTREAM : la version du depot"
echo "Une fois les fichiers resolus, sans aucun marqueur : pull.sh --conclude."
echo "Conflit de suppression : garder le fichier (ne rien faire) ou pull.sh --drop <chemin>."
echo "Pour tout annuler et revenir a l'etat d'avant la fusion : pull.sh --abort."
exit 0
