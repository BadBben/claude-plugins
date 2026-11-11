#!/usr/bin/env bash
# Configure the memory repository of this device and its durable clone.
#
# Usage: setup.sh <url | owner/repo> [--replace]
#        setup.sh --status
#        setup.sh --list
#        setup.sh --project <name>
#        setup.sh --compare <old-memory-dir> <name>
#   <url>     : write the configuration and clone the repository when the clone is missing
#   --replace : accept to replace a different repository already configured. A clone of
#               another repository is never deleted: it has to be moved away first.
#   --status  : print the configuration and the state of the clone (--show is an alias)
#   --list    : list the projects and the general memory
#   --project : print where the memory of a project lives in the clone, in the two forms
#               the autoMemoryDirectory setting accepts. The script does not write the
#               setting: the skill edits the settings file, which may hold other keys.
#   --compare : compare a memory folder left by the 0.6.x versions with the project in the
#               clone, read-only, to see what a migration would have to bring over
#
# Exit codes: 0 ok, 1 usage, 2 git error or a folder in the way, 10 not configured,
#             11 another repository is configured or cloned.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

USAGE="usage: setup.sh <url> [--replace] | --status | --list | --project <nom> | --compare <ancien-dossier> <nom>"
ARG="${1:-}"
if [[ -z "$ARG" ]]; then
  echo "$USAGE" >&2
  exit 1
fi
shift

# Print the configuration and the state of the clone, without creating anything.
show_status() {
  read_wanted_url
  if ! is_clone "$CLONE"; then
    if [[ -z "$WANTED_URL" ]]; then
      echo "Aucun depot memoire configure sur cet appareil : lance le skill setup avec l'URL du depot." >&2
      exit 10
    fi
    echo "depot=$(safe_url "$WANTED_URL")"
    echo "config=$(display_path "$CONFIG_FILE")"
    if is_occupied "$CLONE"; then
      echo "clone=$(display_path "$CLONE") (present mais ce n'est pas un clone git : a deplacer)"
    else
      echo "clone=$(display_path "$CLONE") (absent : setup.sh <url> le cree)"
    fi
    return 0
  fi
  ensure_clone
  fetch_origin soft
  resolve_branch
  count_divergence
  echo "depot=$(safe_url "$REPO_URL")"
  if [[ -f "$CONFIG_FILE" ]]; then
    echo "config=$(display_path "$CONFIG_FILE")"
  else
    echo "config=(absente : le clone fait foi)"
  fi
  echo "clone=$(display_path "$CLONE")"
  echo "branche=$BRANCH"
  echo "avance=$AHEAD commit(s) locaux a pousser"
  echo "retard=$BEHIND commit(s) du depot a recuperer"
  echo "non_commite=$(g status --porcelain | grep -c . || true) entree(s)"
  if merge_in_progress; then echo "fusion_en_cours=oui"; else echo "fusion_en_cours=non"; fi
  if [[ -d "$LEGACY_GENERAL_DIR" ]]; then
    echo "ancienne_generale=$(display_path "$LEGACY_GENERAL_DIR") (copie des versions 0.6.x, generale.sh --compare-old)"
  fi
}

make_tmp

case "$ARG" in
  --status|--show)
    show_status
    exit 0 ;;

  --list)
    ensure_clone
    fetch_origin soft
    resolve_branch
    count_divergence
    echo "== Depot : $(safe_url "$REPO_URL") =="
    describe_repo
    if [[ "$BEHIND" -gt 0 ]]; then
      echo "(le depot a $BEHIND commit(s) que ce clone n'a pas encore : un pull les recupere)"
    fi
    exit 0 ;;

  --project)
    NAME="${1:-}"
    [[ -n "$NAME" ]] || { echo "--project attend un nom de projet" >&2; exit 1; }
    ensure_clone
    resolve_branch
    resolve_project "$NAME"
    echo "projet=$PROJECT"
    if [[ "$PROJECT_KNOWN" -eq 1 ]]; then
      echo "connu=oui"
    else
      echo "connu=non (nouveau projet : son dossier sera cree avec sa premiere fiche)"
    fi
    echo "memoire=$(display_path "$CLONE/$TARGET/memory")"
    # The ~ form reads the same on every device, which is what a shared setting needs.
    echo "reglage=$(tilde_path "$CLONE/$TARGET/memory")"
    if [[ -f "$CLONE/$TARGET/memory/MEMORY.md" ]]; then echo "index=present"; else echo "index=absent"; fi
    exit 0 ;;

  --compare)
    OLD="${1:-}"
    NAME="${2:-}"
    if [[ -z "$OLD" || -z "$NAME" ]]; then
      echo "--compare attend un ancien dossier de memoire et un nom de projet" >&2
      exit 1
    fi
    [[ -d "$OLD" ]] || { echo "Dossier introuvable : $OLD" >&2; exit 1; }
    ensure_clone
    resolve_branch
    resolve_project "$NAME"
    echo "== Ancienne copie : $(display_path "$OLD") =="
    echo "== Dans le clone  : $(display_path "$CLONE/$TARGET/memory") =="
    compare_dirs "$OLD" "$CLONE/$TARGET/memory"
    echo "Rien n'a ete modifie, ni dans l'ancienne copie ni dans le clone."
    exit 0 ;;

  --*)
    echo "argument inconnu: $ARG" >&2
    echo "$USAGE" >&2
    exit 1 ;;
esac

# Configuration mode: ARG is the repository URL.
REPLACE=0
for a in "$@"; do
  case "$a" in
    --replace) REPLACE=1 ;;
    *) echo "argument inconnu: $a" >&2; echo "$USAGE" >&2; exit 1 ;;
  esac
done

NEW_URL=$(normalize_url "$ARG")
read_config_url
REPLACED=0
if [[ -n "$CURRENT_URL" && "$(url_key "$CURRENT_URL")" != "$(url_key "$NEW_URL")" ]]; then
  if [[ "$REPLACE" -eq 0 ]]; then
    echo "Un autre depot est deja configure : $(safe_url "$CURRENT_URL")" >&2
    echo "Relance avec --replace pour le remplacer par $(safe_url "$NEW_URL")" >&2
    exit 11
  fi
  REPLACED=1
fi

if is_clone "$CLONE"; then
  ORIGIN=$(git -C "$CLONE" remote get-url origin 2>/dev/null || true)
  if [[ "$(url_key "$ORIGIN")" != "$(url_key "$NEW_URL")" ]]; then
    echo "Le clone $(display_path "$CLONE") appartient a un autre depot : $(safe_url "${ORIGIN:-(sans origin)}")" >&2
    echo "Rien n'est supprime, meme avec --replace : deplace ou renomme ce dossier, puis relance." >&2
    exit 11
  fi
  REPO_URL="$NEW_URL"
  echo "== Clone deja en place : $(display_path "$CLONE") =="
  fetch_origin soft
elif is_occupied "$CLONE"; then
  echo "$(display_path "$CLONE") existe et n'est pas un clone git." >&2
  echo "Rien n'est supprime : deplace ou renomme ce dossier, puis relance pour que le depot y soit clone." >&2
  exit 2
else
  # The clone is the probe: a wrong URL or a missing login fails here, before any
  # configuration is written.
  REPO_URL="$NEW_URL"
  clone_repo
  echo "== Depot clone dans $(display_path "$CLONE") =="
fi

mkdir -p "$MEMOIRE_HOME"
printf '{"repo": "%s", "configured": "%s", "from": "%s"}\n' "$NEW_URL" "$(date -Iseconds)" "$(hostname)" > "$CONFIG_FILE"

resolve_branch
describe_repo
if [[ "$REPLACED" -eq 1 ]]; then
  echo "Depot remplace. Ancien : $(safe_url "$CURRENT_URL")"
fi
if [[ -d "$LEGACY_GENERAL_DIR" ]]; then
  echo "Une copie locale de la memoire generale des versions 0.6.x existe encore : $(display_path "$LEGACY_GENERAL_DIR")"
  echo "Elle n'est plus utilisee et n'est pas supprimee : generale.sh --compare-old montre ce qu'elle a de plus que le clone."
fi
echo "== Configuration ecrite dans $(display_path "$CONFIG_FILE") =="
