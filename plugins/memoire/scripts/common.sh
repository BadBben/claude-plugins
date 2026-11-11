#!/usr/bin/env bash
# Shared helpers for the memoire plugin scripts. Source it, do not run it.
#
# The memory repository lives in one durable clone per device, $CLAUDE_MEMOIRE_DIR
# (default ~/claude-memory). Git does the transport and the merges; these helpers add what
# the plugin promises on top (no secret, no conflict marker and no silent loss reach the
# repository) and the summaries the skills show to the user. The only other persistent
# file is $CLAUDE_MEMOIRE_HOME/config.json (default ~/.claude/memoire/config.json), which
# holds the repository URL written by setup.sh.
#
# Environment overrides, meant for sandboxes without persistent configuration (claude.ai)
# and for the tests:
#   CLAUDE_MEMOIRE_DIR    where the clone lives
#   CLAUDE_MEMOIRE_HOME   where config.json lives
#   CLAUDE_MEMOIRE_REPO   repository URL, takes precedence over config.json
#   CLAUDE_MEMOIRE_HOST   name written in commit titles instead of the hostname
#
# Scope of a pull or a push. An operation covers the transverse part of the repository
# (everything outside projets/<name>/: the general memory and the root files) plus the
# projects it was given, usually the one of the session. The other projects are never
# committed or pushed as a side effect. The scope options, read by pull.sh and push.sh:
#   --project <name>      a project, by name (repeatable)
#   --memory-dir <path>   the auto memory folder of the session; when it lies inside
#                         <clone>/projets/<name>/, that project joins the scope
#   --all                 the whole repository, on explicit request only
#
# Exit codes shared by the scripts:
#   1 usage, 2 git error, 3 project or commit unknown, 4 repository ahead of the clone
#   (pull first), 5 secret pattern found, 6 conflict markers left or merge in progress,
#   7 large loss refused (--accept-loss), 8 a merge would overwrite uncommitted work of a
#   project outside the scope (pull.sh --include), 10 no repository configured,
#   11 another repository is configured or cloned.

MEMOIRE_HOME="${CLAUDE_MEMOIRE_HOME:-$HOME/.claude/memoire}"
CONFIG_FILE="$MEMOIRE_HOME/config.json"
# Local copy of the general memory kept by the 0.6.x versions. It is never written any
# more: generale.sh --compare-old only compares it with the clone.
LEGACY_GENERAL_DIR="$MEMOIRE_HOME/general"
CLONE="${CLAUDE_MEMOIRE_DIR:-$HOME/claude-memory}"
# Real secret patterns only (values, not words), to avoid false positives.
SECRET_RE='ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|BEGIN [A-Z ]*PRIVATE KEY|(password|passwd|mot de passe)[[:space:]]*[:=][[:space:]]*[^[:space:]]+'
# Conflict markers written by git, including the ancestor marker of the diff3 styles.
MARKER_RE='^(<<<<<<< |\|\|\|\|\|\|\|( |$)|=======$|>>>>>>> )'
# The same markers for content read from a tree, where a line may still end with a carriage
# return when a file was committed with Windows line endings.
CR=$'\r'
MARKER_TREE_RE="^(<<<<<<< |\|\|\|\|\|\|\|( |${CR}?\$)|=======${CR}?\$|>>>>>>> )"
TMP=""
# Scope of the operation, filled by build_scope from the options the script collected.
SCOPE_ALL=0
SCOPE_PROJECTS=$'\n'
SCOPE_NOTE=""
RAW_PROJECTS=""
RAW_MEMORY_DIR=""

# Print a path the way the host tools expect it: mixed form (C:/Users/...) on Git Bash.
display_path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi
}

# Print a path with the home directory written as ~, the portable form for a setting that
# should read the same on every device; a path outside the home directory is printed in full.
tilde_path() {
  if [[ "$1" == "$HOME"/* ]]; then echo "~/${1#"$HOME"/}"; else display_path "$1"; fi
}

# Create the temporary directory of the script on first use (TMP), removed on exit.
# Call it from the main shell, not from a command substitution: a subshell would create
# and remove its own directory.
make_tmp() {
  [[ -z "$TMP" ]] || return 0
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
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

# Reduce a repository URL to a comparable key, so that two spellings of one repository
# compare equal: HTTPS or SSH, with or without the .git suffix, any letter case.
url_key() {
  local u="$1"
  if [[ -d "$u" ]]; then
    # A local repository: compare physical paths, because the same folder is spelled
    # /c/x by the shell and C:/x by git on Windows.
    (cd "$u" && pwd -P) | tr '[:upper:]' '[:lower:]'
    return 0
  fi
  u="${u%/}"
  u="${u%.git}"
  u="${u#*://}"
  u="${u#*@}"
  # scp-like syntax (host:owner/repo) becomes host/owner/repo.
  u="${u/://}"
  printf '%s\n' "$u" | tr '[:upper:]' '[:lower:]'
}

# Print a repository URL without the credentials it may embed (https://user:token@host/...):
# what a script prints ends up in a conversation, and a token must never travel that way.
safe_url() {
  printf '%s\n' "$1" | sed -E 's#^([A-Za-z][A-Za-z0-9+.-]*://)[^/@]*@#\1#'
}

# Read the repository URL from config.json into CURRENT_URL (empty when absent).
read_config_url() {
  CURRENT_URL=""
  [[ -f "$CONFIG_FILE" ]] || return 0
  CURRENT_URL=$(sed -n 's/.*"repo"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CONFIG_FILE" | head -1)
}

# Load the repository URL the user asked for into WANTED_URL: the environment first, then
# config.json. Empty when neither is set.
read_wanted_url() {
  WANTED_URL=""
  if [[ -n "${CLAUDE_MEMOIRE_REPO:-}" ]]; then
    WANTED_URL=$(normalize_url "$CLAUDE_MEMOIRE_REPO")
    return 0
  fi
  read_config_url
  WANTED_URL="$CURRENT_URL"
}

# Run git inside the clone. core.safecrlf=false drops the per-file line-ending warnings of
# Windows setups, core.quotepath=false prints accented file names as they are. Both are
# passed on the command line so the configuration of the clone is left untouched.
g() {
  git -C "$CLONE" -c core.safecrlf=false -c core.quotepath=false "$@"
}

# Tell whether a folder is the root of a git clone.
is_clone() {
  [[ -e "$1/.git" ]]
}

# Tell whether a path exists and holds something: a file, or a folder that is not empty.
is_occupied() {
  [[ -e "$1" ]] || return 1
  [[ -d "$1" ]] || return 0
  [[ -n "$(ls -A "$1" 2>/dev/null)" ]]
}

# Clone REPO_URL into $CLONE, or exit 2 with the usual causes. Nothing is left behind on
# failure: git removes what it started to write.
clone_repo() {
  make_tmp
  mkdir -p "$(dirname "$CLONE")"
  if ! git clone --quiet "$REPO_URL" "$CLONE" 2>"$TMP/clone.err"; then
    echo "Impossible de cloner $(safe_url "$REPO_URL") dans $(display_path "$CLONE")" >&2
    cat "$TMP/clone.err" >&2
    echo "Verifie l'URL et l'authentification GitHub (une fenetre de connexion a pu s'ouvrir)." >&2
    echo "Sur claude.ai : le depot doit d'abord etre attache a la session (outil d'ajout de depot)." >&2
    exit 2
  fi
}

# Make sure the durable clone exists and belongs to the repository the user configured;
# clone it on first use. Sets REPO_URL. Nothing is ever deleted: a folder that is in the
# way, or a clone of another repository, is reported and left as it is.
ensure_clone() {
  local origin
  read_wanted_url
  if is_clone "$CLONE"; then
    origin=$(git -C "$CLONE" remote get-url origin 2>/dev/null || true)
    if [[ -z "$origin" ]]; then
      echo "Le clone $(display_path "$CLONE") n'a pas de depot distant (origin) : impossible de synchroniser." >&2
      exit 2
    fi
    if [[ -n "$WANTED_URL" && "$(url_key "$WANTED_URL")" != "$(url_key "$origin")" ]]; then
      echo "Le clone $(display_path "$CLONE") appartient a un autre depot." >&2
      echo "  depot du clone    : $(safe_url "$origin")" >&2
      echo "  depot configure   : $(safe_url "$WANTED_URL")" >&2
      echo "Rien n'est supprime : deplace ou renomme ce dossier, puis relance." >&2
      exit 11
    fi
    REPO_URL="$origin"
    return 0
  fi
  if is_occupied "$CLONE"; then
    echo "$(display_path "$CLONE") existe et n'est pas un clone git." >&2
    echo "Rien n'est supprime : deplace ou renomme ce dossier, puis relance pour que le depot y soit clone." >&2
    exit 2
  fi
  if [[ -z "$WANTED_URL" ]]; then
    echo "Aucun depot memoire configure sur cet appareil : lance le skill setup avec l'URL du depot." >&2
    exit 10
  fi
  REPO_URL="$WANTED_URL"
  clone_repo
  # On stderr: some commands print a single value on stdout (generale.sh path).
  echo "(depot clone dans $(display_path "$CLONE"))" >&2
}

# Refresh what the clone knows about the repository. A failure is fatal (exit 2) unless the
# caller passes "soft": read-only commands must keep working offline, on the state known at
# the last exchange. Sets FETCHED (1 when the repository answered).
fetch_origin() {
  local mode="${1:-hard}"
  make_tmp
  if g fetch --quiet origin 2>"$TMP/fetch.err"; then
    FETCHED=1
    return 0
  fi
  FETCHED=0
  if [[ "$mode" == "soft" ]]; then
    echo "(depot injoignable : etat connu au dernier echange)"
    return 0
  fi
  echo "Impossible de joindre le depot $(safe_url "$REPO_URL")" >&2
  cat "$TMP/fetch.err" >&2
  echo "Verifie la connexion et l'authentification GitHub (une fenetre de connexion a pu s'ouvrir)." >&2
  echo "Sur claude.ai : le depot doit etre attache a la session (outil d'ajout de depot)." >&2
  exit 2
}

# Find the branch the repository works on: the default branch of origin, else main. Sets
# BRANCH, UPSTREAM (origin/<branch>) and HAS_UPSTREAM (0 while the repository is still
# empty). Call it after fetch_origin when fresh information matters.
resolve_branch() {
  local ref
  ref=$(g symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)
  if [[ -n "$ref" ]]; then
    BRANCH="${ref#origin/}"
  elif g show-ref --verify -q refs/remotes/origin/main; then
    BRANCH="main"
  elif g show-ref --verify -q refs/remotes/origin/master; then
    BRANCH="master"
  else
    # Empty repository: the first push will create the branch the clone is on.
    BRANCH=$(g symbolic-ref -q --short HEAD 2>/dev/null || true)
    BRANCH="${BRANCH:-main}"
  fi
  UPSTREAM="origin/$BRANCH"
  if g show-ref --verify -q "refs/remotes/$UPSTREAM"; then HAS_UPSTREAM=1; else HAS_UPSTREAM=0; fi
}

# Refuse to work when the clone is not on the branch of the repository: merging or pushing
# from another branch would send the memory somewhere unexpected.
require_branch() {
  local cur
  cur=$(g symbolic-ref -q --short HEAD 2>/dev/null || true)
  if [[ "$cur" != "$BRANCH" ]]; then
    echo "Le clone est sur '${cur:-une tete detachee}' au lieu de '$BRANCH'." >&2
    echo "Reviens sur $BRANCH (git -C \"$(display_path "$CLONE")\" switch $BRANCH), puis relance." >&2
    exit 2
  fi
}

# Tell whether the clone has at least one commit (false in a freshly cloned empty repository).
have_head() {
  g rev-parse -q --verify HEAD >/dev/null 2>&1
}

# Tell whether a merge was started and not concluded yet.
merge_in_progress() {
  g rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1
}

# Print the id of the empty tree: the "before" side of a first push to an empty repository.
empty_tree() {
  printf '' | g mktree
}

# Print the tree to compare the working state with: HEAD, or the empty tree before the
# first commit.
head_tree() {
  if have_head; then echo "HEAD"; else empty_tree; fi
}

# Print the name written in commit titles for this device.
host_label() {
  echo "${CLAUDE_MEMOIRE_HOST:-$(hostname)}"
}

# A sandbox may have no git identity: commit under a neutral one rather than fail. It goes
# through the environment, so the configuration of the clone is left untouched and a real
# identity set later takes over by itself.
ensure_identity() {
  if [[ -z "$(g config user.email || true)" && -z "${GIT_AUTHOR_EMAIL:-}" ]]; then
    export GIT_AUTHOR_NAME="memoire" GIT_AUTHOR_EMAIL="memoire@users.noreply.github.com"
    export GIT_COMMITTER_NAME="memoire" GIT_COMMITTER_EMAIL="memoire@users.noreply.github.com"
  fi
}

# Print the conflict style to merge with. zdiff3 shows the common ancestor between the two
# versions, which is what lets the session explain a conflict; git older than 2.35 only
# knows diff3.
conflict_style() {
  local v major minor
  v=$(git version | awk '{print $3}')
  major="${v%%.*}"
  minor="${v#*.}"
  minor="${minor%%.*}"
  if [[ ! "$major" =~ ^[0-9]+$ || ! "$minor" =~ ^[0-9]+$ ]]; then
    echo "diff3"
  elif [[ "$major" -gt 2 || ( "$major" -eq 2 && "$minor" -ge 35 ) ]]; then
    echo "zdiff3"
  else
    echo "diff3"
  fi
}

# Write the tree of the working state (tracked changes and untracked files included)
# through a temporary index, and print its id. The real index, the working tree and the
# branches are not touched, which is what lets a simulation promise that nothing was
# written. Requires make_tmp to have been called by the main shell.
work_tree_id() {
  local gitdir idx
  gitdir=$(g rev-parse --absolute-git-dir)
  idx=$(display_path "$TMP/index")
  # Start from the real index when there is one: unchanged files are not hashed again.
  if [[ -f "$gitdir/index" ]]; then cp "$gitdir/index" "$TMP/index"; else rm -f "$TMP/index"; fi
  GIT_INDEX_FILE="$idx" g add -A >/dev/null
  GIT_INDEX_FILE="$idx" g write-tree
}

# List the files that differ between two trees as "status<TAB>path" lines. Renames are shown
# as a deletion and an addition, so every line names exactly one file.
diff_plain() {
  g diff --no-renames --name-status "$1" "$2"
}

# Set SCOPE to the label of the part of the repository a path belongs to (the project name
# for projets/<nom>/..., "general" for general/..., "racine" for everything else) and
# SCOPE_KIND to project, general or racine. Variables rather than an echo: this runs once
# per file, and a subshell per file is slow on Windows.
scope_of() {
  local rest
  case "$1" in
    projets/*/*) rest="${1#projets/}"; SCOPE="${rest%%/*}"; SCOPE_KIND="project" ;;
    general/*) SCOPE="general"; SCOPE_KIND="general" ;;
    *) SCOPE="racine"; SCOPE_KIND="racine" ;;
  esac
}

# Read repository paths on stdin and print the scopes they touch as one line: the projects
# in alphabetical order, then general, then racine, separated by a comma and a space.
scopes_of_paths() {
  local p projects="" has_general=0 has_root=0
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    scope_of "$p"
    case "$SCOPE_KIND" in
      general) has_general=1 ;;
      racine) has_root=1 ;;
      *) projects+="$SCOPE"$'\n' ;;
    esac
  done
  {
    printf '%s' "$projects" | sort -u
    if [[ "$has_general" -eq 1 ]]; then echo "general"; fi
    if [[ "$has_root" -eq 1 ]]; then echo "racine"; fi
  } | paste -sd, - | sed 's/,/, /g'
}

# Print a filesystem path in one comparable spelling: forward slashes, ~ expanded, a drive
# letter written /c/..., no trailing slash, and lower case where the filesystem ignores
# case (Windows, macOS). The session reports its memory folder as C:\x\y, the shell says
# /c/x/y and a setting may say ~/y: all three must compare equal.
norm_path() {
  local p="$1"
  p="${p//\\//}"
  if [[ "$p" == "~" ]]; then
    p="$HOME"
  elif [[ "$p" == "~/"* ]]; then
    p="$HOME/${p#"~/"}"
  fi
  p="${p//\\//}"
  # On Git Bash a folder can have two names (/tmp is the Windows temporary folder): let
  # cygpath give the one Windows name before comparing.
  if command -v cygpath >/dev/null 2>&1; then
    p=$(cygpath -m "$p" 2>/dev/null || printf '%s\n' "$p")
  fi
  if [[ "$p" =~ ^([A-Za-z]):(/.*)?$ ]]; then
    p="/${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
  fi
  while [[ "$p" == *//* ]]; do p="${p//\/\//\/}"; done
  if [[ "$p" != "/" ]]; then p="${p%/}"; fi
  case "${OSTYPE:-}" in
    msys*|cygwin*|win32*|darwin*) printf '%s\n' "$p" | tr '[:upper:]' '[:lower:]' ;;
    *) printf '%s\n' "$p" ;;
  esac
}

# Set MEMDIR_PROJECT to the project whose folder holds the given memory folder, or to the
# empty string when the folder is not under <clone>/projets/<name>/. MEMDIR_INSIDE tells
# whether the folder is in the clone at all: a session opened on the clone itself has no
# project, and that is not a mistake to report.
project_of_memory_dir() {
  local dir clone rest
  MEMDIR_PROJECT=""
  MEMDIR_INSIDE=0
  dir=$(norm_path "$1")
  clone=$(norm_path "$CLONE")
  case "$dir" in
    "$clone"/projets/?*)
      rest="${dir#"$clone"/projets/}"
      MEMDIR_PROJECT="${rest%%/*}"
      MEMDIR_INSIDE=1 ;;
    "$clone"|"$clone"/*)
      MEMDIR_INSIDE=1 ;;
  esac
}

# Add a project to the scope, under the name the repository uses for it. A name that
# matches nothing is kept, since a first push may be about to create the project, but it is
# reported: a typo would otherwise look like "nothing to push".
scope_add_project() {
  resolve_project "$1"
  if [[ "$PROJECT_KNOWN" -eq 0 ]]; then
    SCOPE_NOTE+="(projet '$PROJECT' inconnu du clone et du depot : rien a couvrir pour lui, setup.sh --list donne les noms)"$'\n'
  fi
  case "$SCOPE_PROJECTS" in
    *$'\n'"$PROJECT"$'\n'*) ;;
    *) SCOPE_PROJECTS+="$PROJECT"$'\n' ;;
  esac
}

# Turn the scope options collected by the script (RAW_PROJECTS, RAW_MEMORY_DIR, SCOPE_ALL)
# into SCOPE_PROJECTS. Call it once the clone and its branch are known: names are resolved
# against the projects of the repository. Fills SCOPE_NOTE, one line per remark, with what
# the skills must tell the user: a memory folder that is not in the clone, an unknown name.
build_scope() {
  local name
  SCOPE_NOTE=""
  if [[ "$SCOPE_ALL" -eq 1 ]]; then return 0; fi
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    scope_add_project "$name"
  done <<< "$RAW_PROJECTS"
  if [[ -n "$RAW_MEMORY_DIR" ]]; then
    project_of_memory_dir "$RAW_MEMORY_DIR"
    if [[ -n "$MEMDIR_PROJECT" ]]; then
      RESOLVE_QUIET=1 scope_add_project "$MEMDIR_PROJECT"
    elif [[ "$MEMDIR_INSIDE" -eq 0 ]]; then
      SCOPE_NOTE+="(--memory-dir hors du clone : ce dossier de travail n'est pas branche sur le clone, il n'ajoute aucun projet a la portee)"$'\n'
    fi
  fi
}

# Tell whether a repository path is covered by the scope: always for the transverse part,
# for a project only when it was put in the scope.
in_scope() {
  if [[ "$SCOPE_ALL" -eq 1 ]]; then return 0; fi
  scope_of "$1"
  if [[ "$SCOPE_KIND" != "project" ]]; then return 0; fi
  case "$SCOPE_PROJECTS" in
    *$'\n'"$SCOPE"$'\n'*) return 0 ;;
  esac
  return 1
}

# Print the scope in words, for the first line of a pull or a push.
describe_scope() {
  local names
  if [[ "$SCOPE_ALL" -eq 1 ]]; then
    echo "tout le depot (--all)"
    return 0
  fi
  names=$(printf '%s' "$SCOPE_PROJECTS" | grep -v '^$' | paste -sd, - | sed 's/,/, /g' || true)
  if [[ -n "$names" ]]; then
    echo "$names + partie transverse (general/ et racine)"
  else
    echo "partie transverse seule (general/ et racine), aucun projet indique"
  fi
}

# Read "status<TAB>path" lines on stdin and split them into two files: the lines the scope
# covers, and the others.
split_by_scope() {
  local inside="$1" outside="$2" status path
  : > "$inside"
  : > "$outside"
  while IFS=$'\t' read -r status path; do
    [[ -n "$status" ]] || continue
    if in_scope "$path"; then
      printf '%s\t%s\n' "$status" "$path" >> "$inside"
    else
      printf '%s\t%s\n' "$status" "$path" >> "$outside"
    fi
  done
}

# Print the uncommitted work that an operation leaves alone, from a file of
# "status<TAB>path" lines. It is written in words, so the block cannot be mistaken for the
# file list of a commit message.
print_rest() {
  local list="$1" status path
  [[ -s "$list" ]] || return 0
  echo "== Restent en local (autres projets, non pousses) =="
  while IFS=$'\t' read -r status path; do
    case "$status" in
      A) echo "  nouveau  : $path" ;;
      D) echo "  supprime : $path" ;;
      *) echo "  modifie  : $path" ;;
    esac
  done < "$list"
}

# Write a file of "status<TAB>path" lines as a NUL-separated list of paths, the form git
# takes with --pathspec-from-file. Read literally (--literal-pathspecs), such a list names
# files exactly, whatever characters they hold and however many they are.
write_pathspec_file() {
  cut -f2- "$1" | tr '\n' '\0' > "$2"
}

# Print the id of the tree made of the last commit plus the given changes, taken from the
# working tree. <list> is a file of "status<TAB>path" lines. This tree is what a scoped
# commit will hold: nothing outside the listed paths can enter it, whatever the real index
# or the rest of the working tree holds. Requires make_tmp.
scoped_tree_id() {
  local list="$1" idx
  idx=$(display_path "$TMP/index-scope")
  rm -f "$TMP/index-scope"
  if have_head; then
    GIT_INDEX_FILE="$idx" g read-tree HEAD
  else
    GIT_INDEX_FILE="$idx" g read-tree --empty
  fi
  if [[ -s "$list" ]]; then
    write_pathspec_file "$list" "$TMP/paths-scope"
    GIT_INDEX_FILE="$idx" g --literal-pathspecs add -A --pathspec-from-file="$(display_path "$TMP/paths-scope")" --pathspec-file-nul >/dev/null
  fi
  GIT_INDEX_FILE="$idx" g write-tree
}

# Record a tree as a new commit on top of the branch, then make the index agree with it for
# the listed paths. commit-tree on purpose, rather than git commit: the commit holds exactly
# the tree that was shown and checked, whatever is staged in the index, and nothing outside
# the listed paths is staged, committed or modified. The working tree is never written.
# Usage: commit_scoped <tree> <list of "status<TAB>path" lines> <message paragraph>...
commit_scoped() {
  local tree="$1" list="$2" old new m
  local -a paragraphs=()
  shift 2
  for m in "$@"; do
    if [[ -n "$m" ]]; then paragraphs+=(-m "$m"); fi
  done
  # Every step is checked by hand: callers run this function in a condition, where the
  # shell does not stop on errors by itself.
  if have_head; then
    old=$(g rev-parse HEAD) || return 1
    new=$(g commit-tree "$tree" -p "$old" "${paragraphs[@]}") || return 1
    [[ -n "$new" ]] || return 1
    # The old value is checked: if anything moved the branch in between, nothing is updated.
    g update-ref -m "memoire: commit" "refs/heads/$BRANCH" "$new" "$old" || return 1
  else
    new=$(g commit-tree "$tree" "${paragraphs[@]}") || return 1
    [[ -n "$new" ]] || return 1
    g update-ref -m "memoire: commit" "refs/heads/$BRANCH" "$new" "" || return 1
  fi
  # Index entries of the committed paths now describe the previous commit: reset them to the
  # new one. Entries of other paths, staged or not, are left as they are.
  write_pathspec_file "$list" "$TMP/paths-commit"
  g --literal-pathspecs reset -q --pathspec-from-file="$(display_path "$TMP/paths-commit")" --pathspec-file-nul >/dev/null 2>&1 || true
}

# Read repository paths on stdin and print those whose working copy matches <pattern>
# (extra grep options may follow). Carriage returns are stripped first: on Windows the
# working copies can be CRLF, and "=======\r" would escape the marker pattern. Binary files
# are skipped. grep reads its whole input on purpose (no -q): with pipefail, an early exit
# would kill tr on a large file and turn a match into a miss.
files_matching() {
  local pattern="$1" p
  shift
  while IFS= read -r p; do
    [[ -n "$p" && -f "$CLONE/$p" ]] || continue
    if tr -d '\r' < "$CLONE/$p" | grep -IE "$@" -- "$pattern" >/dev/null; then echo "$p"; fi
  done
}

# Read repository paths on stdin and print those that still hold a conflict marker.
files_with_markers() {
  files_matching "$MARKER_RE"
}

# Read repository paths on stdin and print those that hold a secret pattern.
files_with_secrets() {
  files_matching "$SECRET_RE" -i
}

# Read candidate paths on stdin and print those whose content in <tree> matches <pattern>
# (extra git grep options may follow). One git grep over the tree: what is checked is
# exactly what will be committed or pushed, not what the working tree happens to hold for
# files outside the scope, and it stays fast with many files. Binary files are skipped.
# Requires make_tmp.
tree_paths_matching() {
  local tree="$1" pattern="$2"
  shift 2
  cat > "$TMP/candidates"
  [[ -s "$TMP/candidates" ]] || return 0
  { g grep -I -l -z -E "$@" -e "$pattern" "$tree" 2>/dev/null || true; } \
    | tr '\0' '\n' | sed "s#^${tree}:##" > "$TMP/matches"
  awk 'NR == FNR { c[$0] = 1; next } ($0 in c)' "$TMP/candidates" "$TMP/matches"
}

# Read candidate paths on stdin and print those that hold a conflict marker in <tree>.
tree_with_markers() {
  tree_paths_matching "$1" "$MARKER_TREE_RE"
}

# Read candidate paths on stdin and print those that hold a secret pattern in <tree>.
tree_with_secrets() {
  tree_paths_matching "$1" "$SECRET_RE" -i
}

# Print the short ids of the local commits, not yet in the repository, whose added lines
# hold a secret pattern. Such a commit would travel with the history at the next push even
# if a later edit removed the secret from the file.
commits_with_secrets() {
  local range c
  have_head || return 0
  if [[ "$HAS_UPSTREAM" -eq 1 ]]; then range="$UPSTREAM..HEAD"; else range="HEAD"; fi
  for c in $(g rev-list "$range"); do
    if g show --format= --unified=0 "$c" | grep '^+' | grep -IiE -- "$SECRET_RE" >/dev/null; then
      g rev-parse --short "$c"
    fi
  done
}

# Decide whether going from one tree to another looks like a loss: a deleted file, or far
# more lines removed than added. A memory grows or gets reorganised, it rarely shrinks.
# Renames are followed, so moving a file is not a deletion.
# Sets LOSS (0|1), LOSS_FILES, LOSS_ADDED and LOSS_DELETED.
measure_loss() {
  local from="$1" to="$2"
  LOSS=0
  LOSS_FILES=$(g diff -M --name-status "$from" "$to" | grep -c '^D' || true)
  read -r LOSS_ADDED LOSS_DELETED < <(g diff -M --numstat "$from" "$to" | awk '{a+=$1; d+=$2} END {print a+0, d+0}')
  if [[ "$LOSS_FILES" -gt 0 || ( "$LOSS_DELETED" -ge 30 && "$LOSS_DELETED" -gt $((LOSS_ADDED * 2)) ) ]]; then
    LOSS=1
  fi
}

# Set AHEAD (local commits the repository does not have) and BEHIND (the reverse), as known
# at the last fetch.
count_divergence() {
  AHEAD=0
  BEHIND=0
  if ! have_head; then
    if [[ "$HAS_UPSTREAM" -eq 1 ]]; then BEHIND=$(g rev-list --count "$UPSTREAM"); fi
    return 0
  fi
  if [[ "$HAS_UPSTREAM" -eq 0 ]]; then
    AHEAD=$(g rev-list --count HEAD)
    return 0
  fi
  AHEAD=$(g rev-list --count "$UPSTREAM..HEAD")
  BEHIND=$(g rev-list --count "HEAD..$UPSTREAM")
}

# Print the names of the projects that have a folder, in the clone or in the repository as
# known at the last fetch (a project pushed by another device and not pulled yet counts).
list_projects() {
  local d
  {
    if [[ -d "$CLONE/projets" ]]; then
      for d in "$CLONE"/projets/*/; do
        [[ -d "$d" ]] || continue
        d="${d%/}"
        echo "${d##*/}"
      done
    fi
    if [[ "${HAS_UPSTREAM:-0}" -eq 1 ]]; then
      g ls-tree -d --name-only "$UPSTREAM" projets/ 2>/dev/null | sed 's#^projets/##'
    fi
  } | grep -v '^$' | sort -u || true
}

# Resolve a project name against the clone without regard to case. Sets PROJECT (the name
# as the repository spells it), TARGET (its folder in the repository) and PROJECT_KNOWN.
# On a case-insensitive filesystem a wrongly cased name still finds the files, but git
# paths are case-sensitive: the spelling of the repository is the one to use everywhere.
resolve_project() {
  local given="$1" match="" name wanted
  if [[ -z "$given" || "$given" == "." || "$given" == ".." || "$given" == */* || "$given" == *\\* || "$given" == -* ]]; then
    echo "Nom de projet invalide : '$given' (un simple nom de dossier, sans barre oblique)." >&2
    exit 1
  fi
  # Compared in lower case with tr rather than grep -iFx: the name is not a pattern, and
  # that combination of options crashes some grep builds shipped with Git for Windows.
  wanted=$(printf '%s' "$given" | tr '[:upper:]' '[:lower:]')
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    if [[ "$name" == "$given" ]]; then
      match="$name"
      break
    fi
    if [[ -z "$match" && "$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')" == "$wanted" ]]; then
      match="$name"
    fi
  done < <(list_projects)
  # RESOLVE_QUIET=1 when the name was derived from a path, not typed by the user: telling
  # them about a spelling they never wrote would only be noise.
  if [[ -n "$match" && "$match" != "$given" && "${RESOLVE_QUIET:-0}" -eq 0 ]]; then
    echo "(projet '$given' connu dans le depot sous le nom '$match' : nom du depot utilise)"
  fi
  PROJECT="${match:-$given}"
  if [[ -n "$match" ]]; then PROJECT_KNOWN=1; else PROJECT_KNOWN=0; fi
  TARGET="projets/$PROJECT"
}

# Print what the memory holds: projects with a folder, and the general memory.
describe_repo() {
  local projects entries
  echo "Projets avec une memoire partagee :"
  projects=$(list_projects)
  if [[ -n "$projects" ]]; then
    printf '%s\n' "$projects" | sed 's/^/  - /'
  else
    echo "  (aucun pour l'instant : le premier push en creera un)"
  fi
  if [[ -f "$CLONE/general/MEMORY.md" ]]; then
    entries=$(grep -c '^- \[' "$CLONE/general/MEMORY.md" || true)
    echo "Memoire generale : oui, $entries entree(s) dans l'index"
  else
    echo "Memoire generale : pas encore (dossier general/ absent)"
  fi
}

# Compare an old local memory folder with its counterpart in the clone, file by file, on
# LF copies. Prints what exists only in the old folder, what differs, and the counts.
# Read-only on both sides: the old folder is evidence, it is never modified or deleted.
compare_dirs() {
  local old="$1" new="$2" f only=0 differ=0 same=0
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    if [[ ! -f "$new/$f" ]]; then
      echo "seulement dans l'ancienne copie : $f"
      only=$((only + 1))
    elif cmp -s <(tr -d '\r' < "$old/$f") <(tr -d '\r' < "$new/$f"); then
      same=$((same + 1))
    else
      echo "different                       : $f"
      differ=$((differ + 1))
    fi
  done < <(cd "$old" && find . -type f ! -name .memoire-sync | sed 's#^\./##' | sort)
  echo "== $only fichier(s) seulement dans l'ancienne copie, $differ different(s), $same identique(s) =="
}
