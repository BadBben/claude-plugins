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
# The guided path of the setup skill, five steps per device (repository and clone, project
# of the working folder, block of the user instruction file, AGENTS.md, scheduled routine):
#        setup.sh --etapes [--workdir <dir>]
#        setup.sh --bloc [--write]
#        setup.sh --cron <jour> <HH:MM>
#        setup.sh --routine [--all | --project <name>]... [--host <name>]
#   --etapes  : print the state of the five steps and the version of the plugin. Read-only
#               and offline: nothing is cloned, fetched or written, and the exit code is 0
#               whatever the state. One "etape" record per step, tab-separated: number,
#               code (depot, projet, bloc, agents, routine), state, detail. States: fait,
#               a-faire, a-mettre-a-jour, sans-objet, non-verifiable. The routine lives on
#               the account, not on the device: its state is always non-verifiable here,
#               the skill looks it up with the routine tool of the session.
#               --workdir is the working folder whose project is checked (default: the
#               current directory).
#   --bloc    : show the block the plugin keeps in the user instruction file
#               (~/.claude/CLAUDE.md): its state, the text to write, the text in place and
#               what would change. States: absent, a-jour, a-mettre-a-jour (between the
#               markers, different), sans-marqueurs (written by hand, recognised),
#               marqueurs-abimes. With --write, write it between its two markers; the rest
#               of the file is kept byte for byte, line endings included, and a copy of the
#               file as it was is left in the configuration folder of the plugin.
#   --cron    : turn a local day and time into the UTC cron expression a cloud routine
#               takes, and tell whether daylight saving time will move the local time.
#               <jour> is a French day name, a number (0 or 7 for Sunday) or "tous".
#   --routine : print the prompt of the routine that plays the optimiser skill, from the
#               template of the plugin, filled with the repository, the scope and the name
#               written in commit titles. Nothing is created: routines belong to the tools
#               of the session.
#
# Exit codes: 0 ok, 1 usage, 2 git error or a folder in the way, 10 not configured,
#             11 another repository is configured or cloned, 12 the block cannot be
#             written safely (damaged markers).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

USAGE="usage: setup.sh <url> [--replace] | --status | --list | --project <nom> | --compare <ancien-dossier> <nom> | --etapes [--workdir <dossier>] | --bloc [--write] | --cron <jour> <HH:MM> | --routine [--all | --project <nom>] [--host <nom>]"
ARG="${1:-}"
if [[ -z "$ARG" ]]; then
  echo "$USAGE" >&2
  exit 1
fi
shift

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BLOCK_TEMPLATE="$PLUGIN_ROOT/skills/setup/assets/bloc-claude-md.md"
ROUTINE_TEMPLATE="$PLUGIN_ROOT/skills/optimiser/assets/consigne-routine.md"
CLAUDE_MD="${CLAUDE_MEMOIRE_CLAUDE_MD:-$HOME/.claude/CLAUDE.md}"
# The block lives between two marker lines, an HTML comment each, like the routing table of
# AGENTS.md: Claude Code drops such comments before it loads the file, so they cost nothing.
BLOCK_BEGIN='<!-- memoire:debut -->'
BLOCK_END='<!-- memoire:fin -->'
TAB=$'\t'

# awk function that replaces every occurrence of a key by a value, both taken literally: a
# path or a URL may hold "&" or a backslash, which sub() and -v would interpret.
AWK_FILL='
function fill(s, key, val,   i, out) {
  out = ""
  while ((i = index(s, key)) > 0) {
    out = out substr(s, 1, i - 1) val
    s = substr(s, i + length(key))
  }
  return out s
}'

# Print the version of the plugin, read from its manifest.
plugin_version() {
  local v=""
  if [[ -f "$PLUGIN_ROOT/.claude-plugin/plugin.json" ]]; then
    v=$(tr -d '\r' < "$PLUGIN_ROOT/.claude-plugin/plugin.json" | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  fi
  echo "${v:-inconnue}"
}

# Write the block as it should stand in the user instruction file, markers included, to
# $TMP/block.new. The import line names the real clone, in its ~ form when it can.
render_block() {
  local body where
  [[ -f "$BLOCK_TEMPLATE" ]] || { echo "Modele du bloc introuvable : $(display_path "$BLOCK_TEMPLATE")" >&2; exit 2; }
  # An import path takes a backslash in front of each space.
  where=$(tilde_path "$CLONE")
  where="${where// /\\ }"
  # Through a command substitution on purpose: it drops the blank lines a template may end
  # with, so the closing marker always follows the last line of text.
  body=$(tr -d '\r' < "$BLOCK_TEMPLATE" | FILL_CLONE="$where" LC_ALL=C awk "$AWK_FILL"'
    { print fill($0, "{{CLONE}}", ENVIRON["FILL_CLONE"]) }')
  printf '%s\n' "$BLOCK_BEGIN" "$body" "$BLOCK_END" > "$TMP/block.new"
}

# Lines of the instruction file that belong to the plugin, read on $TMP/claude.lf: the
# import of AGENTS.md (kept only when it points at the clone, checked by the caller), a
# line that names a skill of the plugin, the rule about pull, push and commit. Fenced code
# is skipped, as Claude Code does for imports. Prints "import<TAB>line<TAB>path" and
# "signal<TAB>line" records.
AWK_SIGNALS='
{ t = $0; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t) }
t ~ /^(```|~~~)/ { fence = !fence; next }
fence { next }
t ~ /^@.*AGENTS\.md$/ { print "import\t" NR "\t" substr(t, 2); next }
t ~ /\/memoire:[a-z]/ { print "signal\t" NR; next }
{
  low = tolower(t)
  if (low ~ /pull/ && low ~ /push/ && low ~ /commit/) print "signal\t" NR
}'

# Find the span of a block written by hand, without markers. Input: $TMP/claude.lf.
# ENVIRON["SIGNALS"] holds the signal line numbers, separated by spaces. The block is the
# whole section of the heading above the first signal when that section is mostly made of
# signals; otherwise only the lines from the first signal to the last one of the section,
# so that unrelated rules sharing the heading are left alone. Prints "<from> <to>".
AWK_SPAN='
BEGIN { n = split(ENVIRON["SIGNALS"], s, " "); for (i = 1; i <= n; i++) sig[s[i] + 0] = 1; first = s[1] + 0 }
{ t = $0; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t); blank[NR] = (t == "") }
t ~ /^(```|~~~)/ { fence = !fence }
!fence && $0 ~ /^#+[ \t]/ { head[NR] = 1 }
END {
  h = 0
  for (i = first; i >= 1; i--) if (head[i]) { h = i; break }
  end = NR
  for (i = (h ? h : first) + 1; i <= NR; i++) if (head[i]) { end = i - 1; break }
  while (end > first && blank[end]) end--
  last = first
  for (i = (h ? h + 1 : 1); i <= end; i++) {
    if (blank[i]) continue
    if (i > h) total++
    if (sig[i]) { hits++; last = i }
  }
  if (h && hits * 2 >= total) print h, end
  else print first, last
}'

# Look at the user instruction file and tell where the block stands. Sets BLOCK_STATE
# (absent, a-jour, a-mettre-a-jour, sans-marqueurs, marqueurs-abimes), BLOCK_FILE (oui or
# non: whether the file exists), BLOCK_FROM and BLOCK_TO (lines of the block in place) and
# BLOCK_STRAY (plugin lines left outside the block). Writes $TMP/block.new, and
# $TMP/block.old when a block is in place. Read-only.
inspect_block() {
  local nb ne b e kind line path signals="" wanted n
  BLOCK_STATE="absent"
  BLOCK_FILE="non"
  BLOCK_FROM=0
  BLOCK_TO=0
  BLOCK_STRAY=""
  render_block
  [[ -f "$CLAUDE_MD" ]] || return 0
  BLOCK_FILE="oui"
  tr -d '\r' < "$CLAUDE_MD" > "$TMP/claude.lf"
  read -r nb ne b e < <(LC_ALL=C awk -v B="$BLOCK_BEGIN" -v E="$BLOCK_END" '
    { t = $0; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t) }
    t == B { nb++; if (!b) b = NR }
    t == E { ne++; e = NR }
    END { print nb + 0, ne + 0, b + 0, e + 0 }' "$TMP/claude.lf")
  wanted=$(norm_path "$CLONE/AGENTS.md")
  while IFS=$'\t' read -r kind line path; do
    [[ -n "$kind" ]] || continue
    # The escaped spaces of an import path are plain spaces on disk.
    if [[ "$kind" == "import" && "$(norm_path "${path//\\ / }")" != "$wanted" ]]; then continue; fi
    signals+="$line "
  done < <(LC_ALL=C awk "$AWK_SIGNALS" "$TMP/claude.lf")
  if [[ "$nb" -eq 0 && "$ne" -eq 0 ]]; then
    [[ -n "$signals" ]] || return 0
    BLOCK_STATE="sans-marqueurs"
    read -r BLOCK_FROM BLOCK_TO < <(SIGNALS="$signals" LC_ALL=C awk "$AWK_SPAN" "$TMP/claude.lf")
  elif [[ "$nb" -eq 1 && "$ne" -eq 1 && "$b" -lt "$e" ]]; then
    BLOCK_FROM="$b"
    BLOCK_TO="$e"
  else
    BLOCK_STATE="marqueurs-abimes"
    return 0
  fi
  sed -n "${BLOCK_FROM},${BLOCK_TO}p" "$TMP/claude.lf" > "$TMP/block.old"
  for n in $signals; do
    if [[ "$n" -lt "$BLOCK_FROM" || "$n" -gt "$BLOCK_TO" ]]; then BLOCK_STRAY+="${BLOCK_STRAY:+,}$n"; fi
  done
  [[ "$BLOCK_STATE" == "sans-marqueurs" ]] && return 0
  if cmp -s "$TMP/block.old" "$TMP/block.new"; then BLOCK_STATE="a-jour"; else BLOCK_STATE="a-mettre-a-jour"; fi
}

# Print the state of the block in key=value lines, the form the skill reads.
print_block_state() {
  echo "fichier=$(display_path "$CLAUDE_MD")"
  echo "fichier_present=$BLOCK_FILE"
  echo "etat=$BLOCK_STATE"
  if [[ "$BLOCK_FROM" -gt 0 ]]; then echo "lignes=$BLOCK_FROM-$BLOCK_TO"; fi
  if [[ -n "$BLOCK_STRAY" ]]; then echo "hors_bloc=$BLOCK_STRAY"; fi
}

# Show the block: its state, the text to write, the text in place and the difference.
show_block() {
  inspect_block
  print_block_state
  if [[ "$BLOCK_STATE" == "marqueurs-abimes" ]]; then
    echo "Les marqueurs $BLOCK_BEGIN et $BLOCK_END doivent figurer une fois chacun, dans cet ordre : a reparer a la main."
  fi
  echo "== Bloc a ecrire =="
  cat "$TMP/block.new"
  if [[ "$BLOCK_STATE" == "a-mettre-a-jour" || "$BLOCK_STATE" == "sans-marqueurs" ]]; then
    echo "== Bloc en place (lignes $BLOCK_FROM a $BLOCK_TO) =="
    cat "$TMP/block.old"
    echo "== Ce qui change =="
    # diff answers 1 when the two texts differ, which is the expected case here.
    { diff -u "$TMP/block.old" "$TMP/block.new" || true; } | tail -n +3
  fi
}

# Write the block into the user instruction file: appended when there is none, in place of
# the block found otherwise. Everything outside the block is copied as it is.
write_block() {
  local keep="" saved=""
  inspect_block
  case "$BLOCK_STATE" in
    a-jour)
      print_block_state
      echo "== Bloc deja a jour : rien a ecrire =="
      return 0 ;;
    marqueurs-abimes)
      print_block_state
      echo "Les marqueurs $BLOCK_BEGIN et $BLOCK_END ne figurent pas une fois chacun, dans cet ordre." >&2
      echo "Rien n'est ecrit : repare les marqueurs a la main dans $(display_path "$CLAUDE_MD"), puis relance." >&2
      exit 12 ;;
  esac
  echo "etat_avant=$BLOCK_STATE"
  if [[ "$BLOCK_FILE" == "non" ]]; then
    mkdir -p "$(dirname "$CLAUDE_MD")"
    cat "$TMP/block.new" > "$CLAUDE_MD"
  else
    mkdir -p "$MEMOIRE_HOME"
    saved="$MEMOIRE_HOME/CLAUDE.md.avant-bloc"
    cp "$CLAUDE_MD" "$saved"
    if [[ "$BLOCK_STATE" == "absent" ]]; then
      # Appended after a blank line, unless the file is empty or already ends with one.
      LC_ALL=C awk '{ print; last = $0 } END { if (NR > 0 && last !~ /^[ \t]*$/) print "" }' "$TMP/claude.lf" > "$TMP/claude.new"
      cat "$TMP/block.new" >> "$TMP/claude.new"
    else
      keep="keep-end"
      {
        if [[ "$BLOCK_FROM" -gt 1 ]]; then sed -n "1,$((BLOCK_FROM - 1))p" "$TMP/claude.lf"; fi
        cat "$TMP/block.new"
        sed -n "$((BLOCK_TO + 1)),\$p" "$TMP/claude.lf"
      } > "$TMP/claude.new"
    fi
    # The line endings are settled on a copy, then the content is written through the
    # existing file rather than moved over it: a link to a file kept elsewhere stays a link.
    cp "$CLAUDE_MD" "$TMP/claude.target"
    install_text "$TMP/claude.new" "$TMP/claude.target" $keep
    cat "$TMP/claude.target" > "$CLAUDE_MD"
  fi
  inspect_block
  print_block_state
  if [[ -n "$saved" ]]; then echo "sauvegarde=$(display_path "$saved")"; fi
  echo "== Bloc ecrit dans $(display_path "$CLAUDE_MD") (lignes $BLOCK_FROM a $BLOCK_TO) =="
}

# Print the value of autoMemoryDirectory in a settings file, with its JSON escapes undone,
# or nothing when the key is absent.
setting_value() {
  tr -d '\r' < "$1" | tr '\n' ' ' \
    | sed -nE 's/.*"autoMemoryDirectory"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' \
    | sed -e 's/\\\\/\\/g' -e 's#\\/#/#g'
}

# Print one step of the guided path: step <number> <code> <state> <detail>.
step() {
  printf 'etape\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"
  case "$3" in
    fait) STEPS_DONE=$((STEPS_DONE + 1)) ;;
    a-faire) STEPS_TODO=$((STEPS_TODO + 1)); [[ "$STEPS_NEXT" -gt 0 ]] || STEPS_NEXT="$1" ;;
    a-mettre-a-jour) STEPS_UPDATE=$((STEPS_UPDATE + 1)); [[ "$STEPS_NEXT" -gt 0 ]] || STEPS_NEXT="$1" ;;
  esac
}

# Print the state of the five steps for this device and a working folder. Nothing is
# cloned, fetched or written: this is the view the user steers the setup from.
show_steps() {
  local workdir="$1" origin="" repo_ok=0 nwd nclone f value="" src="" name raw lines detail
  STEPS_DONE=0
  STEPS_TODO=0
  STEPS_UPDATE=0
  STEPS_NEXT=0
  echo "== Mise en place =="
  echo "version=$(plugin_version)"

  # 1. Repository configured and cloned.
  read_wanted_url
  if is_clone "$CLONE"; then
    origin=$(git -C "$CLONE" remote get-url origin 2>/dev/null || true)
    if [[ -z "$origin" ]]; then
      step 1 depot a-faire "le clone $(display_path "$CLONE") n'a pas de depot distant (origin)"
    elif [[ -n "$WANTED_URL" && "$(url_key "$WANTED_URL")" != "$(url_key "$origin")" ]]; then
      step 1 depot a-faire "le clone $(display_path "$CLONE") appartient a un autre depot que celui configure ($(safe_url "$WANTED_URL"))"
    else
      repo_ok=1
      step 1 depot fait "$(safe_url "$origin") clone dans $(display_path "$CLONE")"
    fi
  elif is_occupied "$CLONE"; then
    step 1 depot a-faire "$(display_path "$CLONE") existe et n'est pas un clone git : a deplacer"
  elif [[ -n "$WANTED_URL" ]]; then
    step 1 depot a-faire "depot configure ($(safe_url "$WANTED_URL")), clone absent de $(display_path "$CLONE")"
  else
    step 1 depot a-faire "aucun depot memoire configure sur cet appareil"
  fi

  # 2. Project of the working folder plugged on the clone.
  nwd=$(norm_path "$workdir")
  nclone=$(norm_path "$CLONE")
  if [[ "$nwd" == "$nclone" || "$nwd" == "$nclone"/* ]]; then
    step 2 projet sans-objet "ce dossier est le clone : il n'est le dossier de travail d'aucun projet"
  else
    # The local file wins over the shared one, as in Claude Code.
    for f in "$workdir/.claude/settings.local.json" "$workdir/.claude/settings.json"; do
      [[ -f "$f" ]] || continue
      value=$(setting_value "$f")
      if [[ -n "$value" ]]; then src=".claude/${f##*/}"; break; fi
    done
    if [[ -z "$value" ]]; then
      step 2 projet a-faire "aucun reglage autoMemoryDirectory dans $(display_path "$workdir")/.claude/"
    else
      project_of_memory_dir "$value"
      if [[ -n "$MEMDIR_PROJECT" && "$(norm_path "$value")" == "$nclone/projets/$MEMDIR_PROJECT/memory" ]]; then
        # The name as the setting spells it: norm_path lowered it where the filesystem
        # ignores case.
        raw="${value//\\//}"
        raw="${raw%/}"
        raw="${raw%/*}"
        name="${raw##*/}"
        detail="$name ($src)"
        if [[ "$repo_ok" -eq 1 ]]; then
          RESOLVE_QUIET=1 resolve_project "$name"
          detail="$PROJECT ($src)"
          if [[ ! -f "$CLONE/$TARGET/memory/MEMORY.md" ]]; then detail+=", index MEMORY.md pas encore cree"; fi
        fi
        step 2 projet fait "$detail"
      elif [[ "$MEMDIR_INSIDE" -eq 1 ]]; then
        step 2 projet a-faire "le reglage de $src pointe dans le clone, mais pas sur projets/<nom>/memory : $value"
      else
        step 2 projet a-faire "le reglage de $src pointe hors du clone : $value"
      fi
    fi
  fi

  # 3. Block of the user instruction file.
  inspect_block
  case "$BLOCK_STATE" in
    a-jour)
      detail="$(display_path "$CLAUDE_MD"), lignes $BLOCK_FROM a $BLOCK_TO"
      if [[ -n "$BLOCK_STRAY" ]]; then detail+=" ; des lignes du plugin restent hors du bloc ($BLOCK_STRAY)"; fi
      step 3 bloc fait "$detail" ;;
    a-mettre-a-jour)
      step 3 bloc a-mettre-a-jour "$(display_path "$CLAUDE_MD") : le bloc entre marqueurs differe de celui de cette version" ;;
    sans-marqueurs)
      step 3 bloc a-mettre-a-jour "$(display_path "$CLAUDE_MD") : bloc pose a la main, sans marqueurs (lignes $BLOCK_FROM a $BLOCK_TO)" ;;
    marqueurs-abimes)
      step 3 bloc a-mettre-a-jour "$(display_path "$CLAUDE_MD") : marqueurs du bloc abimes, a reparer a la main" ;;
    *)
      if [[ "$BLOCK_FILE" == "oui" ]]; then
        step 3 bloc a-faire "$(display_path "$CLAUDE_MD") n'a pas le bloc du plugin"
      else
        step 3 bloc a-faire "$(display_path "$CLAUDE_MD") n'existe pas encore"
      fi ;;
  esac

  # 4. Routing table in the repository.
  if [[ "$repo_ok" -eq 0 ]]; then
    step 4 agents a-faire "se verifie dans le clone : etape 1 d'abord"
  elif [[ -f "$CLONE/AGENTS.md" ]]; then
    lines=$(tr -d '\r' < "$CLONE/AGENTS.md" | wc -l | tr -d ' ')
    step 4 agents fait "AGENTS.md a la racine du clone ($lines lignes)"
  else
    step 4 agents a-faire "AGENTS.md absent du clone : le skill reindex le cree depuis son modele"
  fi

  # 5. Scheduled routine: it lives on the account, no script can see it.
  step 5 routine non-verifiable "une routine vit sur le compte : a verifier avec l'outil de routines de la session"

  echo "== Bilan =="
  echo "faites=$STEPS_DONE"
  echo "a_faire=$STEPS_TODO"
  echo "a_mettre_a_jour=$STEPS_UPDATE"
  echo "suivante=$STEPS_NEXT"
  if [[ "$repo_ok" -eq 1 ]]; then
    # As known at the last exchange with the repository: this view stays offline.
    resolve_branch
    count_divergence
    echo "clone=avance $AHEAD, retard $BEHIND (au dernier echange), $(g status --porcelain | grep -c . || true) entree(s) non commitee(s)"
  fi
}

# Print the offset of the local time zone at a given moment ("YYYY-MM-DD HH:MM") in the
# +HHMM form, or nothing when this date command cannot compute it.
offset_at() {
  date -d "$1" +%z 2>/dev/null || date -j -f "%Y-%m-%d %H:%M" "$1" +%z 2>/dev/null || true
}

# Turn an offset written +HHMM into signed minutes.
offset_minutes() {
  local off="$1" m
  m=$((10#${off:1:2} * 60 + 10#${off:3:2}))
  if [[ "${off:0:1}" == "-" ]]; then m=$((-m)); fi
  echo "$m"
}

# Print an offset in minutes the way people read it: UTC+01:00.
offset_label() {
  local m="$1" sign="+"
  if [[ "$m" -lt 0 ]]; then sign="-"; m=$((-m)); fi
  printf 'UTC%s%02d:%02d\n' "$sign" $((m / 60)) $((m % 60))
}

# Turn a local day and time into the UTC cron expression of a cloud routine, whose
# schedule is read in UTC, and tell what daylight saving time will do to the local time.
cron_utc() {
  local day hhmm dow hh mm off offmin total dshift=0 udow year o1 o2 other othermin localmin
  local -a names=(dimanche lundi mardi mercredi jeudi vendredi samedi)
  day=$(printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z')
  hhmm="${2//h/:}"
  case "$day" in
    dimanche|0|7) dow=0 ;;
    lundi|1) dow=1 ;;
    mardi|2) dow=2 ;;
    mercredi|3) dow=3 ;;
    jeudi|4) dow=4 ;;
    vendredi|5) dow=5 ;;
    samedi|6) dow=6 ;;
    tous|"*") dow="*" ;;
    *) echo "Jour inconnu : '$1' (lundi a dimanche, 0 a 7, ou tous)." >&2; exit 1 ;;
  esac
  if [[ "$hhmm" =~ ^[0-9]{1,2}:?$ ]]; then hhmm="${hhmm%:}:00"; fi
  if [[ ! "$hhmm" =~ ^([01]?[0-9]|2[0-3]):([0-5][0-9])$ ]]; then
    echo "Heure invalide : '$2' (attendu HH:MM, de 00:00 a 23:59)." >&2
    exit 1
  fi
  hh=$((10#${BASH_REMATCH[1]}))
  mm=$((10#${BASH_REMATCH[2]}))
  off=$(date +%z)
  if [[ ! "$off" =~ ^[+-][0-9]{4}$ ]]; then
    echo "Fuseau horaire de l'appareil illisible (date +%z a repondu '$off')." >&2
    exit 2
  fi
  offmin=$(offset_minutes "$off")
  total=$((hh * 60 + mm - offmin))
  if [[ "$total" -lt 0 ]]; then total=$((total + 1440)); dshift=-1; fi
  if [[ "$total" -ge 1440 ]]; then total=$((total - 1440)); dshift=1; fi
  if [[ "$dow" == "*" ]]; then
    udow="*"
    echo "local=tous les jours $(printf '%02d:%02d' "$hh" "$mm") $(offset_label "$offmin")"
    echo "utc=tous les jours $(printf '%02d:%02d' $((total / 60)) $((total % 60)))"
  else
    udow=$(((dow + dshift + 7) % 7))
    echo "local=${names[$dow]} $(printf '%02d:%02d' "$hh" "$mm") $(offset_label "$offmin")"
    echo "utc=${names[$udow]} $(printf '%02d:%02d' $((total / 60)) $((total % 60)))"
  fi
  echo "cron=$((total % 60)) $((total / 60)) * * $udow"
  # The offsets of mid-January and mid-July: when they differ, the zone changes its clocks
  # and a fixed UTC time moves by that much in local time, twice a year.
  year=$(date +%Y)
  o1=$(offset_at "$year-01-15 12:00")
  o2=$(offset_at "$year-07-15 12:00")
  if [[ ! "$o1" =~ ^[+-][0-9]{4}$ || ! "$o2" =~ ^[+-][0-9]{4}$ ]]; then
    echo "saison=inconnu (cet appareil ne sait pas dire si son fuseau change d'heure)"
  elif [[ "$o1" == "$o2" ]]; then
    echo "saison=non (ce fuseau ne change pas d'heure)"
  else
    other="$o1"
    if [[ "$off" == "$o1" ]]; then other="$o2"; fi
    othermin=$(offset_minutes "$other")
    localmin=$(((total + othermin + 2880) % 1440))
    echo "saison=oui (au changement d'heure, en $(offset_label "$othermin"), la routine passera a $(printf '%02d:%02d' $((localmin / 60)) $((localmin % 60))) heure locale : le cron est a corriger a ce moment-la pour garder $(printf '%02d:%02d' "$hh" "$mm"))"
  fi
}

# Print the prompt of the routine that plays the optimiser skill, from the template of the
# plugin. Arguments: the scope options and --host. The repository is the configured one,
# printed without the credentials its URL may embed.
routine_prompt() {
  local all=0 projects="" host="routine" url origin name scope=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all) all=1 ;;
      --project)
        [[ -n "${2:-}" ]] || { echo "--project attend un nom de projet" >&2; exit 1; }
        projects+="$2"$'\n'
        shift ;;
      --host)
        [[ -n "${2:-}" ]] || { echo "--host attend un nom" >&2; exit 1; }
        host="$2"
        shift ;;
      *) echo "argument inconnu: $1" >&2; echo "$USAGE" >&2; exit 1 ;;
    esac
    shift
  done
  if [[ ! "$host" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "Nom invalide pour --host : '$host' (lettres, chiffres, point, tiret)." >&2
    exit 1
  fi
  [[ -f "$ROUTINE_TEMPLATE" ]] || { echo "Modele de consigne introuvable : $(display_path "$ROUTINE_TEMPLATE")" >&2; exit 2; }
  read_wanted_url
  url="$WANTED_URL"
  if is_clone "$CLONE"; then
    origin=$(git -C "$CLONE" remote get-url origin 2>/dev/null || true)
    url="${url:-$origin}"
    resolve_branch
  fi
  if [[ -z "$url" ]]; then
    echo "Aucun depot memoire configure sur cet appareil : lance le skill setup avec l'URL du depot." >&2
    exit 10
  fi
  url=$(safe_url "$url")
  if [[ "$all" -eq 1 ]]; then
    scope="--all"
  else
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      # Names are checked, and spelled as the repository spells them when the clone is there.
      if is_clone "$CLONE"; then
        resolve_project "$name"
      else
        PROJECT="$name"
        if [[ "$name" == "." || "$name" == ".." || "$name" == */* || "$name" == *\\* || "$name" == -* ]]; then
          echo "Nom de projet invalide : '$name' (un simple nom de dossier, sans barre oblique)." >&2
          exit 1
        fi
      fi
      scope+="${scope:+ }--project \"$PROJECT\""
    done <<< "$projects"
  fi
  echo "depot=$url"
  echo "hote=$host"
  echo "portee=${scope:-(aucune option : partie transverse seule)}"
  if [[ ! "$url" =~ ^https:// ]]; then
    echo "(adresse non HTTPS : une routine cloud prend l'adresse HTTPS du depot, a corriger dans la consigne)"
  fi
  echo "== Consigne =="
  tr -d '\r' < "$ROUTINE_TEMPLATE" | FILL_URL="$url" FILL_HOST="$host" \
    FILL_SCOPE="${scope:-aucune option de portee (partie transverse seule)}" LC_ALL=C awk "$AWK_FILL"'
    {
      line = fill($0, "{{DEPOT}}", ENVIRON["FILL_URL"])
      line = fill(line, "{{HOTE}}", ENVIRON["FILL_HOST"])
      print fill(line, "{{PORTEE}}", ENVIRON["FILL_SCOPE"])
    }'
}

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

  --etapes)
    WORKDIR="$PWD"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --workdir)
          [[ -n "${2:-}" ]] || { echo "--workdir attend un dossier" >&2; exit 1; }
          WORKDIR="$2"
          shift ;;
        *) echo "argument inconnu: $1" >&2; echo "$USAGE" >&2; exit 1 ;;
      esac
      shift
    done
    [[ -d "$WORKDIR" ]] || { echo "Dossier introuvable : $WORKDIR" >&2; exit 1; }
    show_steps "$WORKDIR"
    exit 0 ;;

  --bloc)
    case "${1:-}" in
      "") show_block ;;
      --write) write_block ;;
      *) echo "argument inconnu: $1" >&2; echo "$USAGE" >&2; exit 1 ;;
    esac
    exit 0 ;;

  --cron)
    if [[ $# -ne 2 ]]; then
      echo "--cron attend un jour et une heure (dimanche 19:00)" >&2
      exit 1
    fi
    cron_utc "$1" "$2"
    exit 0 ;;

  --routine)
    routine_prompt "$@"
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
