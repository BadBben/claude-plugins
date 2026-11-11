#!/usr/bin/env bash
# Configure the memory repository used by the memoire plugin on this device.
#
# Usage: setup.sh --show
#        setup.sh --list
#        setup.sh <url | owner/repo> [--replace] [--reset-general]
#   --show          : print the current configuration
#   --list          : list the projects and the general memory of the configured repository
#   --replace       : accept to overwrite a different repository already configured
#   --reset-general : delete the local copy of the general memory (it came from the old repository)
#
# The script probes the repository with a temporary clone and lists what it contains.
# Exit codes: 0 ok, 1 usage, 2 clone failed, 10 not configured (--show),
#             11 another repository is configured (use --replace).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ARG="${1:-}"
REPLACE=0
RESET_GENERAL=0
if [[ -z "$ARG" ]]; then
  echo "usage: setup.sh --show | setup.sh --list | setup.sh <url> [--replace] [--reset-general]" >&2
  exit 1
fi
shift
for a in "$@"; do
  case "$a" in
    --replace) REPLACE=1 ;;
    --reset-general) RESET_GENERAL=1 ;;
    *) echo "argument inconnu: $a" >&2; exit 1 ;;
  esac
done

if [[ "$ARG" == "--show" ]]; then
  read_repo_url
  echo "repo=$REPO_URL"
  echo "config=$(display_path "$CONFIG_FILE")"
  if [[ -d "$GENERAL_DIR" ]]; then
    echo "general=$(display_path "$GENERAL_DIR")"
  else
    echo "general=(pas encore de copie locale)"
  fi
  exit 0
fi

if [[ "$ARG" == "--list" ]]; then
  read_repo_url
  clone_repo ""
  echo "== Depot : $REPO_URL =="
  describe_repo
  exit 0
fi

NEW_URL=$(normalize_url "$ARG")
read_config_url
if [[ -n "$CURRENT_URL" && "$CURRENT_URL" != "$NEW_URL" && "$REPLACE" -eq 0 ]]; then
  echo "Un autre depot est deja configure : $CURRENT_URL" >&2
  echo "Relance avec --replace pour le remplacer par $NEW_URL" >&2
  exit 11
fi

# Probe before writing anything: a wrong URL or a missing login must not leave a broken config.
REPO_URL="$NEW_URL"
clone_repo ""
echo "== Depot accessible : $REPO_URL =="
describe_repo

mkdir -p "$MEMOIRE_HOME"
printf '{"repo": "%s", "configured": "%s", "from": "%s"}\n' "$REPO_URL" "$(date -Iseconds)" "$(hostname)" > "$CONFIG_FILE"

if [[ -n "$CURRENT_URL" && "$CURRENT_URL" != "$NEW_URL" ]]; then
  echo "Depot remplace. Ancien : $CURRENT_URL"
  echo "Les marqueurs .memoire-sync des memoires locales viennent de l'ancien depot : le prochain pull fusionnera sans base."
  if [[ -d "$GENERAL_DIR" ]]; then
    if [[ "$RESET_GENERAL" -eq 1 ]]; then
      rm -rf "$GENERAL_DIR"
      echo "Copie locale de la memoire generale supprimee."
    else
      echo "Copie locale de la memoire generale conservee : un push la versera dans le nouveau depot."
    fi
  fi
fi
echo "== Configuration ecrite dans $(display_path "$CONFIG_FILE") =="
