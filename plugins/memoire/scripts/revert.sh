#!/usr/bin/env bash
# Put a local memory directory back to the state of a given commit of the repository (mirror).
#
# Usage: revert.sh <project | generale> <local-dir | -> --list [--count N]
#        revert.sh <project | generale> <local-dir | -> --commit <sha> [--dry-run]
#   --list     : print the last commits that touched the memory folder (default 10)
#   --commit   : restore the folder as it was at that commit, into the local directory
#   --dry-run  : show what the restore would change, write nothing
#   "-" as local directory means the local copy of the general memory (project "generale").
#
# The repository is not modified. The sync marker is set to the current head of the folder,
# so the next push is an ordinary push that sends this older state as a new commit (the loss
# guard will ask for --accept-loss). History stays linear and the newer commits stay readable.
#
# Exit codes: 0 ok, 1 usage, 2 git error, 3 project or commit unknown, 10 no repository configured.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

PROJECT="${1:-}"
LOCAL="${2:-}"
MODE=""
SHA=""
COUNT=10
DRY_RUN=0
if [[ -z "$PROJECT" || -z "$LOCAL" ]]; then
  echo "usage: revert.sh <project|generale> <local-dir|-> --list [--count N] | --commit <sha> [--dry-run]" >&2
  exit 1
fi
shift 2
while [[ $# -gt 0 ]]; do
  case "$1" in
    --list) MODE="list" ;;
    --commit)
      [[ $# -ge 2 ]] || { echo "--commit attend un identifiant" >&2; exit 1; }
      MODE="restore"; SHA="$2"; shift ;;
    --count)
      [[ $# -ge 2 ]] || { echo "--count attend un nombre" >&2; exit 1; }
      COUNT="$2"; shift ;;
    --dry-run) DRY_RUN=1 ;;
    *) echo "argument inconnu: $1" >&2; exit 1 ;;
  esac
  shift
done
if [[ -z "$MODE" ]]; then
  echo "precise --list ou --commit <sha>" >&2
  exit 1
fi

read_repo_url
clone_repo ""
if [[ "$PROJECT" == "generale" ]]; then
  TARGET="general"
  LABEL="general"
  [[ "$LOCAL" == "-" ]] && LOCAL="$GENERAL_DIR"
  git -C "$CLONE" sparse-checkout set general 2>/dev/null || true
else
  resolve_project "$PROJECT"
  LABEL="$PROJECT"
fi
if ! git -C "$CLONE" cat-file -e "HEAD:$TARGET" 2>/dev/null; then
  echo "Pas de dossier $TARGET dans le depot" >&2
  exit 3
fi

if [[ "$MODE" == "list" ]]; then
  echo "== Derniers commits de $TARGET (du plus recent au plus ancien) =="
  # One block per commit: hash, date, title, then the first line of the recap when there is one.
  git -C "$CLONE" log -n "$COUNT" --date=short --format='%h %ad %s%n%b' -- "$TARGET" \
    | awk 'NF==0 {next} /^[0-9a-f]{7,} [0-9]{4}-/ {print; getline body; if (body ~ /^[0-9a-f]{7,} [0-9]{4}-/) {print body} else if (body != "") {print "    " body}; next} {print "    " $0}' \
    | awk '!/^    [AMD]\t/'
  exit 0
fi

# Restore mode.
if ! git -C "$CLONE" cat-file -e "$SHA^{commit}" 2>/dev/null; then
  echo "Commit inconnu dans le depot : $SHA" >&2
  exit 3
fi
if ! git -C "$CLONE" cat-file -e "$SHA:$TARGET" 2>/dev/null; then
  echo "Le dossier $TARGET n'existe pas au commit $SHA" >&2
  exit 3
fi
FULL=$(git -C "$CLONE" rev-parse --short "$SHA")
mkdir -p "$TMP/restore"
# git archive fetches the blobs of that commit on demand in a partial clone.
git -C "$CLONE" archive "$SHA" "$TARGET" | tar -x -C "$TMP/restore"
RESTORED="$TMP/restore/$TARGET"
mkdir -p "$LOCAL"

echo "== Etat au commit $FULL compare a la copie locale =="
( cd "$RESTORED" && find . -type f ! -name .gitkeep | sed 's#^\./##' | sort ) > "$TMP/files_then"
( cd "$LOCAL" && find . -type f ! -name .memoire-sync | sed 's#^\./##' | sort ) > "$TMP/files_now"
restored_n=0; removed_n=0; same_n=0
while IFS= read -r f; do
  if [[ ! -f "$LOCAL/$f" ]]; then
    echo "a restaurer : $f"; restored_n=$((restored_n + 1))
  elif cmp -s <(tr -d '\r' < "$RESTORED/$f") <(tr -d '\r' < "$LOCAL/$f"); then
    same_n=$((same_n + 1))
  else
    echo "a remettre  : $f (contenu different)"; restored_n=$((restored_n + 1))
  fi
done < "$TMP/files_then"
while IFS= read -r f; do
  if ! grep -qx -- "$f" "$TMP/files_then"; then
    echo "a retirer   : $f (absent a ce commit)"; removed_n=$((removed_n + 1))
  fi
done < "$TMP/files_now"
echo "== $restored_n fichier(s) a restaurer, $removed_n a retirer, $same_n identique(s) =="

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "== Simulation : rien n'a ete ecrit =="
  exit 0
fi

# Mirror: the local directory becomes the folder as it was at that commit.
find "$LOCAL" -mindepth 1 ! -name .memoire-sync -delete
cp -r "$RESTORED"/. "$LOCAL"/
write_marker "$LOCAL" "$TARGET" "$LABEL"
echo "== $LABEL restaure au commit $FULL dans $(display_path "$LOCAL") (marqueur sur ${LAST_COMMIT:0:12}, tete actuelle) =="
echo "La memoire sera chargee au prochain demarrage de session. Pour renvoyer cet etat dans le depot : push (la perte sera signalee)."
