#!/usr/bin/env bash
# Shared helpers for the memoire plugin scripts. Source it, do not run it.
#
# The memory repository is never kept on disk: every script clones it into a temporary
# directory, works there, and removes it on exit. The only persistent files are
#   $CLAUDE_MEMOIRE_HOME/config.json   the repository URL, written by setup.sh
#   $CLAUDE_MEMOIRE_HOME/general/      the local working copy of the general memory
# CLAUDE_MEMOIRE_HOME defaults to ~/.claude/memoire.
#
# Environment overrides, meant for sandboxes without persistent configuration (claude.ai):
#   CLAUDE_MEMOIRE_REPO   repository URL, takes precedence over config.json
#   CLAUDE_MEMOIRE_HOST   name written in commit titles instead of the hostname
#
# Exit codes shared by the scripts:
#   1 usage, 2 git error, 3 project unknown, 4 repository moved since last sync,
#   5 secret pattern found, 6 unresolved conflict markers, 7 large loss refused (--accept-loss),
#   10 no repository configured, 11 another repository is configured (setup.sh without --replace).

MEMOIRE_HOME="${CLAUDE_MEMOIRE_HOME:-$HOME/.claude/memoire}"
CONFIG_FILE="$MEMOIRE_HOME/config.json"
GENERAL_DIR="$MEMOIRE_HOME/general"
# Real secret patterns only (values, not words), to avoid false positives.
SECRET_RE='ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|BEGIN [A-Z ]*PRIVATE KEY|(password|passwd|mot de passe)[[:space:]]*[:=][[:space:]]*[^[:space:]]+'
MARKER_RE='^(<<<<<<< |=======$|>>>>>>> )'

# Print a path the way the host tools expect it: mixed form (C:/Users/...) on Git Bash.
display_path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi
}

# Turn "owner/repo" into a GitHub HTTPS URL; leave full URLs untouched.
normalize_url() {
  local url="$1"
  if [[ "$url" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    echo "https://github.com/$url.git"
  else
    echo "$url"
  fi
}

# Read the repository URL from config.json into CURRENT_URL (empty when absent).
read_config_url() {
  CURRENT_URL=""
  [[ -f "$CONFIG_FILE" ]] || return 0
  CURRENT_URL=$(sed -n 's/.*"repo"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CONFIG_FILE" | head -1)
}

# Load the repository URL into REPO_URL: the environment first, then config.json,
# or exit 10 when neither is set (setup has not been run).
read_repo_url() {
  if [[ -n "${CLAUDE_MEMOIRE_REPO:-}" ]]; then
    REPO_URL=$(normalize_url "$CLAUDE_MEMOIRE_REPO")
    return 0
  fi
  read_config_url
  if [[ -z "$CURRENT_URL" ]]; then
    echo "Aucun depot memoire configure sur cet appareil : lance le skill setup avec l'URL du depot." >&2
    exit 10
  fi
  REPO_URL="$CURRENT_URL"
}

# Clone REPO_URL into a temporary directory (CLONE), removed when the script exits.
# A partial clone keeps the whole history, needed for the merge base, but fetches file
# contents only for the sparse path, so the cost does not grow with the memory.
# Usage: clone_repo [sparse-path]
clone_repo() {
  local sparse="${1:-}"
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  CLONE="$TMP/repo"
  if ! git clone --quiet --filter=blob:none --sparse "$REPO_URL" "$CLONE" 2>"$TMP/clone.err"; then
    # Older git or a server without partial clone support: fall back to a plain clone.
    rm -rf "$CLONE"
    if ! git clone --quiet "$REPO_URL" "$CLONE" 2>"$TMP/clone.err"; then
      echo "Impossible de cloner $REPO_URL" >&2
      cat "$TMP/clone.err" >&2
      echo "Verifie l'URL et l'authentification GitHub (une fenetre de connexion a pu s'ouvrir)." >&2
      echo "Sur claude.ai : le depot doit d'abord etre attache a la session (outil d'ajout de depot)." >&2
      exit 2
    fi
    return 0
  fi
  if [[ -n "$sparse" ]]; then
    git -C "$CLONE" sparse-checkout set "$sparse" 2>/dev/null || true
  fi
  # Keep the user's autocrlf behaviour (the repository stays LF) but drop the per-file warnings.
  git -C "$CLONE" config core.safecrlf false
}

# Print the names of the projects that have a shared memory in the repository.
list_projects() {
  git -C "$CLONE" ls-tree -d --name-only HEAD projets/ 2>/dev/null | sed 's#^projets/##' | grep -v '^$' || true
}

# Resolve a project name against the repository without regard to case, and set PROJECT
# and TARGET. On a case-insensitive filesystem a wrongly cased name still finds the files,
# but git paths are case-sensitive: the sync marker would silently come out empty and the
# guards would be blind. Call after clone_repo, before any git path is used.
resolve_project() {
  local given="$1" match
  match=$(list_projects | grep -ix -- "$given" | head -1 || true)
  if [[ -n "$match" && "$match" != "$given" ]]; then
    echo "(projet '$given' connu dans le depot sous le nom '$match' : nom du depot utilise)"
  fi
  PROJECT="${match:-$given}"
  TARGET="projets/$PROJECT/memory"
  git -C "$CLONE" sparse-checkout set "$TARGET" 2>/dev/null || true
}

# Load the sync marker of a local directory into MARK (commit of the last sync).
# MARK is emptied when the marker is missing, belongs to another repository, or names a
# commit the clone does not have: the merge then runs without a base.
read_marker() {
  local marker="$1/.memoire-sync" repo
  MARK=""
  [[ -f "$marker" ]] || return 0
  repo=$(grep '^repo=' "$marker" | cut -d= -f2- || true)
  MARK=$(grep '^commit=' "$marker" | cut -d= -f2- || true)
  if [[ -n "$repo" && "$repo" != "$REPO_URL" ]]; then
    echo "(marqueur d'un autre depot : $repo, fusion sans base)"
    MARK=""
    return 0
  fi
  if [[ -n "$MARK" ]] && ! git -C "$CLONE" cat-file -e "$MARK" 2>/dev/null; then
    echo "(marqueur ${MARK:0:12} inconnu du depot : fusion sans base)"
    MARK=""
  fi
}

# Print what the repository holds: projects with a shared memory, and the general memory.
describe_repo() {
  local projects entries
  echo "Projets avec une memoire partagee :"
  projects=$(list_projects)
  if [[ -n "$projects" ]]; then
    printf '%s\n' "$projects" | sed 's/^/  - /'
  else
    echo "  (aucun pour l'instant : le premier push en creera un)"
  fi
  if git -C "$CLONE" cat-file -e HEAD:general/MEMORY.md 2>/dev/null; then
    entries=$(git -C "$CLONE" show HEAD:general/MEMORY.md | grep -c '^- \[' || true)
    echo "Memoire generale : oui, $entries entree(s) dans l'index"
  else
    echo "Memoire generale : pas encore (dossier general/ absent)"
  fi
}

# Record which commit of the repository the local directory now matches (LAST_COMMIT).
# An empty commit means the git path is wrong: refuse rather than write a blind marker.
write_marker() {
  local local_dir="$1" target="$2" label="$3"
  LAST_COMMIT=$(git -C "$CLONE" log -1 --format=%H -- "$target")
  if [[ -z "$LAST_COMMIT" ]]; then
    echo "Aucun commit du depot ne touche $target : marqueur non ecrit, verifie le nom du projet." >&2
    exit 2
  fi
  printf 'project=%s\nrepo=%s\ncommit=%s\ndate=%s\n' "$label" "$REPO_URL" "$LAST_COMMIT" "$(date -Iseconds)" > "$local_dir/.memoire-sync"
}

# Strip carriage returns: with core.autocrlf the working copies are CRLF while `git show`
# yields LF, which would make every line look changed on both sides of a merge.
norm() { tr -d '\r' < "$1" > "$2"; }

# Synchronise $CLONE/<target> into <local_dir>, file by file, with a three-way merge
# against the base (the repository at the marker commit). Fills the CONFLICTS array.
#   nouveau   : absent locally, copied
#   identique : nothing to do
#   depot     : only the repository changed since the base, copied
#   local     : only the local copy changed since the base, kept
#   fusion    : both changed without overlap, merged by git merge-file
#   CONFLIT   : both changed with overlap, conflict markers written locally
# Usage: sync_from_repo <target> <local_dir> <label> <dry_run 0|1> <mirror 0|1>
sync_from_repo() {
  local target="$1" local_dir="$2" label="$3" dry_run="$4" mirror="$5"
  local shared_dir="$CLONE/$target"
  local path rel shared local_file base merged rc only_local f
  CONFLICTS=()
  mkdir -p "$local_dir"
  read_marker "$local_dir"

  echo "== Fichiers du depot, compares a la copie locale =="
  while IFS= read -r -d '' path; do
    rel="${path#"$shared_dir"/}"
    shared="$shared_dir/$rel"
    local_file="$local_dir/$rel"

    if [[ ! -f "$local_file" ]]; then
      echo "nouveau   : $rel"
      [[ "$dry_run" -eq 1 ]] || { mkdir -p "$(dirname "$local_file")"; cp "$shared" "$local_file"; }
      continue
    fi
    norm "$shared" "$TMP/shared"
    norm "$local_file" "$TMP/local"
    if cmp -s "$TMP/shared" "$TMP/local"; then
      echo "identique : $rel"
      continue
    fi

    base="$TMP/base"
    : > "$base"
    if [[ -n "$MARK" ]]; then
      git -C "$CLONE" show "$MARK:$target/$rel" 2>/dev/null | tr -d '\r' > "$base" || : > "$base"
    fi
    if cmp -s "$TMP/local" "$base"; then
      echo "depot     : $rel (seul le depot a change, copie)"
      [[ "$dry_run" -eq 1 ]] || cp "$shared" "$local_file"
      continue
    fi
    if cmp -s "$TMP/shared" "$base"; then
      echo "local     : $rel (seule la copie locale a change, gardee)"
      continue
    fi

    # Both sides changed: three-way merge. merge-file returns the number of conflicts.
    merged="$TMP/merged"
    set +e
    git merge-file -p -L local -L base -L depot "$TMP/local" "$base" "$TMP/shared" > "$merged"
    rc=$?
    set -e
    if [[ "$rc" -gt 127 ]]; then
      echo "git merge-file a echoue sur $rel" >&2
      exit 2
    fi
    if [[ "$rc" -eq 0 ]]; then
      echo "fusion    : $rel (les deux ont change, fusion automatique)"
    else
      echo "CONFLIT   : $rel ($rc zone(s) a resoudre, marqueurs <<<<<<< local / >>>>>>> depot)"
      CONFLICTS+=("$rel")
    fi
    [[ "$dry_run" -eq 1 ]] || cp "$merged" "$local_file"
  done < <(find "$shared_dir" -type f ! -name .gitkeep -print0)

  echo "== Fichiers presents seulement en local (gardes sans --mirror) =="
  only_local=$( (cd "$local_dir" && find . -type f ! -name .memoire-sync | sed 's#^\./##') | while IFS= read -r f; do [[ -f "$shared_dir/$f" ]] || echo "$f"; done )
  echo "${only_local:-(aucun)}"

  if [[ "$dry_run" -eq 1 ]]; then
    echo "== Simulation : rien n'a ete ecrit =="
    return 0
  fi
  if [[ "$mirror" -eq 1 && -n "$only_local" ]]; then
    # Mirror mode: the repository copy becomes the whole truth.
    while IFS= read -r f; do rm -f "$local_dir/$f"; done <<< "$only_local"
  fi

  write_marker "$local_dir" "$target" "$label"
  echo "== $label synchronise dans $(display_path "$local_dir") (commit ${LAST_COMMIT:0:12}) =="
  if [[ ${#CONFLICTS[@]} -gt 0 ]]; then
    echo "== CONFLITS a resoudre avant tout push =="
    printf '%s\n' "${CONFLICTS[@]}"
  fi
}

# Push <local_dir> into $CLONE/<target>: guards, mirror copy, commit, push, marker.
# Usage: push_to_repo <target> <local_dir> <label> <--dry-run|--commit> <force 0|1> <message> [accept_loss 0|1]
push_to_repo() {
  local target="$1" local_dir="$2" label="$3" mode="$4" force="$5" message="$6" accept_loss="${7:-0}"
  local shared_dir="$CLONE/$target" last last_short title body deleted_files added deleted loss=0
  # Reference commit, shown in every outcome so the user can always point at the state before.
  last_short=$(git -C "$CLONE" log -1 --format=%h -- "$target" 2>/dev/null || true)

  if [[ ! -f "$local_dir/MEMORY.md" ]]; then
    echo "Pas de MEMORY.md dans $(display_path "$local_dir") : rien a pousser" >&2
    exit 1
  fi
  # Guard: conflict markers left by a previous pull must be resolved first.
  if grep -rEl --exclude=.memoire-sync "$MARKER_RE" "$local_dir" >/dev/null 2>&1; then
    echo "Marqueurs de conflit non resolus dans :" >&2
    grep -rEl --exclude=.memoire-sync "$MARKER_RE" "$local_dir" >&2
    exit 6
  fi
  # Guard: refuse when the repository folder moved since this device last synced it.
  if git -C "$CLONE" cat-file -e "HEAD:$target" 2>/dev/null; then
    last=$(git -C "$CLONE" log -1 --format=%H -- "$target")
    read_marker "$local_dir"
    if [[ "$force" -eq 0 && "$MARK" != "$last" ]]; then
      echo "Le depot a avance depuis la derniere synchro de cet appareil." >&2
      echo "  derniere synchro ici : ${MARK:-jamais}" >&2
      echo "  dernier commit depot : $last" >&2
      echo "Fais un pull d'abord, ou --force pour ecraser en connaissance de cause." >&2
      exit 4
    fi
  fi
  # Guard: secrets never reach the repository.
  if grep -rEil --exclude=.memoire-sync "$SECRET_RE" "$local_dir" >/dev/null 2>&1; then
    echo "Motif de secret detecte dans :" >&2
    grep -rEil --exclude=.memoire-sync "$SECRET_RE" "$local_dir" >&2
    [[ "$force" -eq 1 ]] || exit 5
  fi

  # Mirror copy: the repository folder becomes identical to the local directory.
  rm -rf "$shared_dir"
  mkdir -p "$shared_dir"
  cp -r "$local_dir"/. "$shared_dir"/
  rm -f "$shared_dir/.memoire-sync"
  git -C "$CLONE" add -A -- "$target"
  if git -C "$CLONE" diff --cached --quiet; then
    echo "== Rien a pousser : le depot est deja a jour (dernier commit du dossier : ${last_short:-aucun}) =="
    return 0
  fi
  title="memoire($label): synchro depuis ${CLAUDE_MEMOIRE_HOST:-$(hostname)} le $(date +%Y-%m-%d)"
  # Body: optional recap first, then the file list, so the history reads without opening the diff.
  body="$(git -C "$CLONE" diff --cached --name-status -- "$target")"
  # The proposed message is printed as it will be committed, so the skill can show it verbatim.
  echo "== Message de commit =="
  echo "$title"
  echo
  if [[ -n "$message" ]]; then echo "$message"; else echo "(recap a rediger par la session)"; fi
  echo
  echo "$body"
  echo "== Etat d'avant : commit ${last_short:-aucun (premier push)} =="
  # Guard: a memory should grow or get reorganised, rarely shrink. A deleted file, or far more
  # lines removed than added, is flagged and needs an explicit --accept-loss to be committed.
  deleted_files=$(printf '%s\n' "$body" | grep -c '^D' || true)
  read -r added deleted < <(git -C "$CLONE" diff --cached --numstat -- "$target" | awk '{a+=$1; d+=$2} END {print a+0, d+0}')
  if [[ "$deleted_files" -gt 0 || ( "$deleted" -ge 30 && "$deleted" -gt $((added * 2)) ) ]]; then
    loss=1
    echo "== Attention : perte possible. $deleted_files fichier(s) supprime(s), $deleted ligne(s) retiree(s) pour $added ajoutee(s) =="
  fi
  if [[ "$mode" == "--dry-run" ]]; then
    [[ "$loss" -eq 0 ]] || echo "Le commit demandera --accept-loss."
    echo "== Simulation : rien n'a ete commite =="
    return 0
  fi
  if [[ "$loss" -eq 1 && "$accept_loss" -eq 0 ]]; then
    echo "Perte possible : relance avec --accept-loss si l'utilisateur l'a confirmee en connaissance de cause." >&2
    exit 7
  fi
  # A sandbox may have no git identity: give the temporary clone a neutral one rather than fail.
  if [[ -z "$(git -C "$CLONE" config user.email || true)" ]]; then
    git -C "$CLONE" config user.name "memoire"
    git -C "$CLONE" config user.email "memoire@users.noreply.github.com"
  fi
  if [[ -n "$message" ]]; then
    git -C "$CLONE" commit -q -m "$title" -m "$message" -m "$body"
  else
    git -C "$CLONE" commit -q -m "$title" -m "$body"
  fi
  git -C "$CLONE" push --quiet origin HEAD || { echo "git push a echoue" >&2; exit 2; }
  echo "== Pousse : $(git -C "$CLONE" log -1 --oneline) =="
  write_marker "$local_dir" "$target" "$label"
}
