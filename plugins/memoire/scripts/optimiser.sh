#!/usr/bin/env bash
# Keep the memory healthy: check the memory files themselves, on top of what reindex.sh
# checks (AGENTS.md and the indexes), repair the part that is purely mechanical, and give a
# health score. Works on the durable clone. A repair pass makes one local commit of its own,
# which the revert skill can undo. Nothing is ever pushed here: push.sh sends the result.
#
# Usage: optimiser.sh [--check|--fix|--planifie|--commit] [scope] [options]
#   --check    : report, write nothing (default)
#   --fix      : repair what the closed list below allows, in the scope, commit it locally,
#                then report what is left
#   --planifie : --fix for a scheduled pass, with nobody in front of the screen: git never
#                prompts, the report is also written to a file, and whatever stops the
#                script ends up in that file
#   --commit   : commit the uncommitted work of the scope as "proposals applied", after the
#                session edited the files the user chose. No check is run.
# Scope (see common.sh): the transverse part always, plus
#   --project <name>    a project, by name (repeatable)
#   --memory-dir <path> the project that holds the auto memory folder of the session
#   --all               every project, on explicit request only
# Options:
#   --message "texte"   recap written into the commit body (--commit)
#   --date YYYY-MM-DD   the day ages are counted from (default: today). The score is a pure
#                       function of the state of the clone and of this date.
#   --rapport <file>    also write the report to this file, and one line to historique.tsv
#                       beside it. Default with --planifie:
#                       $CLAUDE_MEMOIRE_HOME/optimiser/dernier-rapport.txt
#   --force             let a secret false positive through when local work is committed
#
# The whole repository is always read and reported, like reindex.sh does. The scope decides
# what may be written, what is committed, and which findings count for the exit code.
#
# What is checked. reindex.sh is run first and its findings are passed on as they are; it
# also gives the list of the files to index (reindex.sh --fiches), so both scripts see the
# same memory. On top of it, for every memory file:
#   - its header: status under metadata, the three status values, the type, keys left
#     outside metadata;
#   - its [[links]] to other memory files, code spans and fenced blocks left out;
#   - its size, its age, relative dates in its text, a name shared with another file.
#
# What --fix writes, and nothing else (the closed list):
#   - the indexes, by reindex.sh --fix;
#   - headers: "status: actif" added under metadata when a file has no status, a status
#     written in a known variant (accents, spaces, capitals) set to its canonical value, a
#     key other than name and description moved under metadata. Never the text;
#   - a [[link]] to a file that disappeared (it exists in the history of the clone and not
#     any more) replaced by the name in plain text. A link to a name that never existed is
#     only reported: it may announce a file to write. A [[journal]] link becomes the path
#     of the journal when the project keeps one where it belongs (see below).
# Everything else is a proposal: the script reports it, the session and the user decide.
#
# The journal of a project is not a memory file: it lives in projets/<name>/journal.md,
# beside memory/, has no line in MEMORY.md, and memory files point to it by its path. A
# journal.md found in memory/ is reported (journal-dans-memory) and none of the checks
# above is run on it: it is an archive, copied as it was.
#
# Commits. Work of the scope that is not committed yet is committed first, on its own, so
# the commit of the pass holds the repairs and nothing else. --commit does the same for the
# proposals the session applied. The revert skill takes the commit printed as "Etat d'avant".
#
# Health score: the share of the memory files of the scope without any finding, as a whole
# percentage rounded down, so 100 means every file is clean. Findings that belong to no
# file (the routing table, a dead line of an index) are counted by type, not in the score.
#
# Output, in the form of reindex.sh: sections introduced by "== ... ==", tab-separated
# records that start with a keyword, key=value lines.
#   corrige     <code> <file> <detail>                           (--fix only)
#   ecart       <code> <dans|hors> <auto|session> <file> <detail>
#   proposition <n> <haute|moyenne|faible> <code> <file> <detail>
#   type        <code> dans=<n> hors=<n>
# "auto" is what --fix repairs, "session" is a proposal. The "Propositions" section numbers
# the proposals of the scope, most serious first. Finding codes added to those of reindex.sh:
#   entete-sans-status, entete-format, entete-status-inconnu, entete-type-inconnu,
#   lien-mort, lien-sans-cible, fiche-a-verifier, fiche-perimee, fiche-ancienne,
#   fiche-trop-longue, date-relative, fiche-nom-en-double, journal-dans-memory,
#   projet-sans-fiche
#
# Exit codes: 0 nothing left to do in the scope, 1 usage, 2 git error, 5 secret found in the
#             local work to commit, 6 merge in progress, 9 findings left in the scope,
#             10 no repository configured, 11 the clone belongs to another repository.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

USAGE="usage: optimiser.sh [--check|--fix|--planifie|--commit] [--project <nom>] [--memory-dir <chemin>] [--all] [--message \"texte\"] [--date AAAA-MM-JJ] [--rapport <fichier>] [--force]"
MODE="--check"
PLANNED=0
FORCE=0
MESSAGE=""
REF_DATE=""
REPORT_FILE=""
REPORT_DONE=0
# The scope options, kept as given: reindex.sh receives the same ones.
SCOPE_ARGS=()
# A while loop rather than for: several options consume the argument that follows them.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check|--fix|--commit) MODE="$1" ;;
    --planifie) MODE="--fix"; PLANNED=1 ;;
    --force) FORCE=1 ;;
    --all) SCOPE_ALL=1; SCOPE_ARGS+=(--all) ;;
    --project)
      [[ $# -ge 2 ]] || { echo "--project attend un nom de projet" >&2; exit 1; }
      RAW_PROJECTS+="$2"$'\n'; SCOPE_ARGS+=(--project "$2"); shift ;;
    --memory-dir)
      [[ $# -ge 2 ]] || { echo "--memory-dir attend un chemin" >&2; exit 1; }
      RAW_MEMORY_DIR="$2"; SCOPE_ARGS+=(--memory-dir "$2"); shift ;;
    --message)
      [[ $# -ge 2 ]] || { echo "--message attend un texte" >&2; exit 1; }
      MESSAGE="$2"; shift ;;
    --date)
      [[ $# -ge 2 ]] || { echo "--date attend une date AAAA-MM-JJ" >&2; exit 1; }
      REF_DATE="$2"; shift ;;
    --rapport)
      [[ $# -ge 2 ]] || { echo "--rapport attend un chemin de fichier" >&2; exit 1; }
      REPORT_FILE="$2"; shift ;;
    *)
      echo "argument inconnu: $1" >&2
      echo "$USAGE" >&2
      exit 1 ;;
  esac
  shift
done
TODAY=$(date +%Y-%m-%d)
REF_DATE="${REF_DATE:-$TODAY}"
if [[ ! "$REF_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "--date attend une date AAAA-MM-JJ, recu : $REF_DATE" >&2
  exit 1
fi

# A memory file is read whole by the session that needs it. 8 kB is about 2000 tokens:
# beyond that, a file usually holds several subjects, or history that belongs in a journal.
FICHE_MAX_BYTES=8000
# Days without a change after which an active file is proposed for "a-verifier", by type.
# The state of a project moves fast, a fact about the environment more slowly. Preferences
# and feedback do not expire with time: 0 means never.
AGE_PROJECT_DAYS=90
AGE_REFERENCE_DAYS=180
EXIT_FINDINGS=9
# How serious a proposal is, by finding code: 1 haute (a session is misled or cannot find
# its way), 2 moyenne (the memory says something doubtful or is filed in the wrong place),
# 3 faible (wording and upkeep). A code that is not listed is taken as moyenne.
GRAVITY="agents-absent=1 agents-bloc-invalide=1 agents-entree-sans-chemin=1 agents-chemin-sans-entree=1 agents-hors-limites=1 index-absent=1 index-trop-long=1 index-ligne-morte=1 index-ligne-en-double=1 index-lien-casse=1 index-ligne-manquante=1 fiche-sans-entete=1 fiche-entete-incomplet=1 fiche-nom-en-double=1 agents-entree-illisible=2 memoire-hors-fiche=2 journal-dans-memory=2 fiche-perimee=2 fiche-a-verifier=2 entete-format=2 entete-status-inconnu=2 entete-type-inconnu=2 fiche-trop-longue=2 fiche-ancienne=3 date-relative=3 lien-sans-cible=3 projet-sans-fiche=3"

# awk function shared by the two programs below: put it in front of the program text.
AWK_LOWER='
# Lower case for the 26 unaccented letters only. tolower is not used: with some awk builds
# (the one of Git for Windows in the C locale) it also changes the bytes of accented
# letters, which turns UTF-8 text into something else.
function lower(s,   i) {
  if (s !~ /[A-Z]/) return s
  for (i = 1; i <= 26; i++) gsub(substr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", i, 1), substr("abcdefghijklmnopqrstuvwxyz", i, 1), s)
  return s
}'

# Check every memory file. Main input: one line per file, <path> <dans|hors> <folder of its
# index>, with the clone as current directory. Variables: gone (names of the files that
# disappeared, in lower case), lastmod (<path> <date of its last commit>), projects (the
# project names), journals (the projects that keep a journal beside memory/), ref (the day
# ages are counted from), maxbytes, age_project, age_reference, ops (a file to write).
# Prints the findings; writes into ops what --fix has to do in the files of the scope, as
# <path> <add|set|move|link> <argument> [<text that replaces the link>].
AWK_FICHES="$AWK_UNQUOTE$AWK_LOWER"'
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
# Keep a finding for the END block, where the findings of a file are printed together.
function note(f, code, how, detail) {
  gsub(/\t/, " ", detail)
  nfind++
  ffile[nfind] = f; fcode[nfind] = code; fhow[nfind] = how; fdet[nfind] = detail
}
# Append an item to a comma-separated list.
function join(list, item) { return (list == "") ? item : list ", " item }
# Days from 1970-01-01 to a date of the Gregorian calendar. mktime is not POSIX awk.
function days(y, m, d,   era, yoe, doy, doe) {
  if (m <= 2) y--
  era = int((y >= 0 ? y : y - 399) / 400)
  yoe = y - era * 400
  doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
  doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
  return era * 146097 + doe - 719468
}
# Day number of a text that starts with YYYY-MM-DD, or -1.
function daynum(s) {
  if (s !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) return -1
  return days(substr(s, 1, 4) + 0, substr(s, 6, 2) + 0, substr(s, 9, 2) + 0)
}
# Reduce a status to the spelling the three values are compared in: lower case, no accent,
# a hyphen for a space or an underscore.
function canon(s,   t) {
  t = lower(s)
  gsub("\303\240|\303\200", "a", t)
  gsub("\303\251|\303\250|\303\252|\303\211|\303\210", "e", t)
  gsub(/[ _]+/, "-", t)
  if (t == "perimee") t = "perime"
  return t
}
# Tell whether a character can be part of a word: a letter, a digit, a hyphen, an
# underscore, or any byte of an accented letter (the locale is C, so bytes are compared).
function wordchar(c) { return (c ~ /[A-Za-z0-9_-]/ || c > "\177") }
# Print the relative dates of a line (hier, la semaine derniere...), comma-separated. A line
# that also holds a date written in full is taken as anchored.
function reldates(s,   t, out, w, pre, post, at) {
  t = lower(s)
  if (t ~ /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) return ""
  out = ""
  while (match(t, RELRX)) {
    at = RSTART
    w = substr(t, RSTART, RLENGTH)
    pre = (at == 1) ? " " : substr(t, at - 1, 1)
    post = substr(t, at + RLENGTH, 1)
    if (!wordchar(pre) && (post == "" || !wordchar(post))) out = join(out, w)
    t = substr(t, at + RLENGTH)
  }
  return out
}
# Record the [[links]] of a piece of text that is neither a code span nor a fenced block.
function scanlinks(seg, f, lineno,   tgt) {
  while (match(seg, /\[\[[^][]+\]\]/)) {
    tgt = substr(seg, RSTART + 2, RLENGTH - 4)
    seg = substr(seg, RSTART + RLENGTH)
    sub(/[|#].*$/, "", tgt)
    tgt = trim(tgt)
    # [[...]] and the like are examples, not links.
    if (tgt !~ /[A-Za-z0-9]/) continue
    nl++
    ltgt[nl] = tgt; lfile[nl] = f; lline[nl] = lineno
  }
}
BEGIN {
  FS = "\t"; OFS = "\t"
  A = "(\047|\342\200\231)"
  RELRX = "avant-hier|apr\303\250s-demain|hier|demain|ce matin|ce soir|cet apr\303\250s-midi|cette semaine|ce mois-ci|la semaine (derni\303\250re|prochaine|pass\303\251e)|le mois (dernier|prochain)|l" A "an (dernier|prochain)|l" A "ann\303\251e (derni\303\250re|prochaine)|il y a [0-9]+ (jours?|semaines?|mois|ans?)|dans [0-9]+ (jours?|semaines?|mois)|yesterday|tomorrow|last (week|month|year)|next (week|month|year)"
  while ((getline l < gone) > 0) isgone[l] = 1
  close(gone)
  while ((getline l < lastmod) > 0) { split(l, a, "\t"); if (!(a[1] in committed)) committed[a[1]] = a[2] }
  close(lastmod)
  while ((getline l < journals) > 0) sidejournal[l] = 1
  close(journals)
  refday = daynum(ref)
  printf "" > ops
}
{
  f = $1
  nfi++
  fl[nfi] = f; portee[f] = $2; holder[f] = $3
  stem = f
  sub(/^.*\//, "", stem)
  sub(/\.[mM][dD]$/, "", stem)
  known[lower(stem)] = 1
  journal = (f ~ /^projets\/[^\/]+\/memory\/[^\/]+$/ && lower(stem) == "journal")
  hdr = 0; closed = 0; inhdr = 0; n = 0; bytes = 0; fence = 0
  cur = ""; inline = 0; cindent = -1; nstray = 0
  name = ""; relw = ""; rell = ""
  split("", hastop); split("", top); split("", hasmeta); split("", meta)
  while ((getline line < f) > 0) {
    n++
    sub(/\r$/, "", line)
    # Bytes as the repository stores them: line endings count for one.
    bytes += length(line) + 1
    if (n == 1) {
      first = line
      # A byte order mark may precede the first dashes.
      sub(/^\357\273\277/, "", first)
      if (first ~ /^---[ \t]*$/) { hdr = 1; inhdr = 1; continue }
    }
    if (inhdr) {
      if (line ~ /^(---|\.\.\.)[ \t]*$/) { inhdr = 0; closed = 1; continue }
      if (line ~ /^[A-Za-z_][A-Za-z0-9_-]*[ \t]*:/) {
        key = line
        sub(/[ \t]*:.*$/, "", key)
        val = line
        sub(/^[^:]*:[ \t]*/, "", val)
        cur = key
        if (key == "metadata") {
          # A value on the line of the key is a mapping written in flow style: it is read
          # by YAML, not by this script, which only edits the block form.
          if (trim(val) != "" && trim(val) !~ /^#/) inline = 1
        } else if (key == "name") {
          name = unquote(val)
        } else if (key != "description") {
          stray[++nstray] = key
          hastop[key] = 1; top[key] = unquote(val)
        }
      } else if (cur == "metadata" && line ~ /^[ \t]+[A-Za-z_][A-Za-z0-9_-]*[ \t]*:/) {
        ind = line
        sub(/[^ \t].*$/, "", ind)
        if (cindent < 0) cindent = length(ind)
        # Only the direct children of metadata: a deeper key belongs to one of them.
        if (length(ind) == cindent) {
          key = trim(line)
          sub(/[ \t]*:.*$/, "", key)
          val = line
          sub(/^[^:]*:[ \t]*/, "", val)
          hasmeta[key] = 1; meta[key] = unquote(val)
        }
      }
      continue
    }
    if (journal) continue
    if (line ~ /^[ \t]*(```|~~~)/) { fence = !fence; continue }
    if (fence) continue
    # What stands between two backticks is shown, not said: odd pieces are the text.
    m = split(line, seg, "`")
    text = ""
    for (k = 1; k <= m; k += 2) {
      scanlinks(seg[k], f, n)
      text = text " " seg[k]
    }
    w = reldates(text)
    if (w != "") { rell = join(rell, n); relw = join(relw, w) }
  }
  close(f)
  if (name != "") {
    known[lower(name)] = 1
    nk = holder[f] SUBSEP lower(name)
    if (nk in nameof) {
      note(f, "fiche-nom-en-double", "session", "name \"" name "\" porte aussi par " nameof[nk])
      # The first file that carried the name is told once, whatever the number of copies.
      if (!(nk in told)) { told[nk] = 1; note(nameof[nk], "fiche-nom-en-double", "session", "name \"" name "\" porte aussi par " f) }
    } else nameof[nk] = f
  }
  if (f ~ /^general\/projets\//) gp[++ngp] = lower(stem) " " lower(name)
  if (journal) {
    injournal[holder[f]] = 1
    note(f, "journal-dans-memory", "session", "un journal n\047est pas une fiche : a ranger a cote de memory/, dans " substr(f, 1, length(f) - length("memory/" stem ".md")) ", sans ligne d\047index")
    next
  }
  # No header at all: reindex.sh reports it, and there is nothing to read in it.
  if (!hdr) status = "actif"
  else if (!closed) {
    note(f, "entete-format", "session", "en-tete sans ligne de fermeture ---")
    next
  } else {
    fixable = (portee[f] == "dans" && !inline)
    autod = ""; sessd = ""
    if (inline) sessd = join(sessd, "metadata ecrit sur une ligne : a reecrire en bloc")
    status = "actif"
    if (("status" in hasmeta) || ("status" in hastop)) {
      val = ("status" in hasmeta) ? meta["status"] : top["status"]
      c = canon(val)
      if (c == "actif" || c == "a-verifier" || c == "perime") {
        status = c
        if (c != val) {
          if (inline) sessd = join(sessd, "status: " val " -> " c)
          else { autod = join(autod, "status: " val " -> " c); if (fixable) print f, "set", c > ops }
        }
      } else {
        status = ""
        note(f, "entete-status-inconnu", "session", "status: " (val == "" ? "(vide)" : val) " (attendu : actif, a-verifier, perime)")
      }
    } else if (!inline) {
      note(f, "entete-sans-status", "auto", "status: actif a ajouter sous metadata")
      if (fixable) print f, "add", "-" > ops
    }
    for (k = 1; k <= nstray; k++) {
      key = stray[k]
      if (key in hasmeta) sessd = join(sessd, "cle " key " a la racine et sous metadata")
      else if (inline) sessd = join(sessd, "cle " key " a ranger sous metadata")
      else { autod = join(autod, "cle " key " a ranger sous metadata"); if (fixable) print f, "move", key > ops }
    }
    if (autod != "") note(f, "entete-format", "auto", autod)
    if (sessd != "") note(f, "entete-format", "session", sessd)
    type = ("type" in hasmeta) ? meta["type"] : (("type" in hastop) ? top["type"] : "")
    if (type != "user" && type != "feedback" && type != "project" && type != "reference")
      note(f, "entete-type-inconnu", "session", "type: " (type == "" ? "(absent)" : type) " (attendu : user, feedback, project, reference)")
    if (status == "a-verifier") note(f, "fiche-a-verifier", "session", "status a-verifier : confirmer le contenu ou le corriger")
    if (status == "perime") note(f, "fiche-perimee", "session", "status perime : a retirer ou a verser au journal")
    limit = (type == "project") ? age_project : ((type == "reference") ? age_reference : 0)
    if (status == "actif" && limit > 0 && refday >= 0) {
      when = ("modified" in hasmeta) ? meta["modified"] : (("modified" in hastop) ? top["modified"] : "")
      if (daynum(when) < 0 && (f in committed)) when = committed[f]
      d = daynum(when)
      if (d >= 0 && refday - d > limit)
        note(f, "fiche-ancienne", "session", "derniere modification le " substr(when, 1, 10) " (" (refday - d) " jours, seuil " limit " pour le type " type ") : proposer a-verifier")
    }
  }
  if (bytes > maxbytes) note(f, "fiche-trop-longue", "session", bytes " octets (seuil " maxbytes ")")
  if (relw != "") note(f, "date-relative", "session", "ligne(s) " rell " : " relw)
}
END {
  for (k = 1; k <= nl; k++) {
    t = lower(ltgt[k])
    f = lfile[k]
    # The journal of a project is kept beside memory/ and is not a memory file: a file
    # points to it by its path, never by a link.
    side = ""
    if (t == "journal" && f ~ /^projets\/[^\/]+\/memory\// && !(holder[f] in injournal)) {
      p = f
      sub(/^projets\//, "", p)
      sub(/\/.*$/, "", p)
      if (p in sidejournal) side = "`projets/" p "/journal.md`"
    }
    if (side == "" && (t in known)) continue
    if (side != "" || (t in isgone)) {
      dead[f] = join(dead[f], "[[" ltgt[k] "]] ligne " lline[k] " -> " (side != "" ? side : ltgt[k]))
      if (portee[f] == "dans" && !((f, t) in dseen)) { dseen[f, t] = 1; print f, "link", ltgt[k], (side != "" ? side : "-") > ops }
    } else {
      open[f] = join(open[f], "[[" ltgt[k] "]] ligne " lline[k])
    }
  }
  for (i = 1; i <= nfi; i++) {
    f = fl[i]
    for (k = 1; k <= nfind; k++) if (ffile[k] == f) print "ecart", fcode[k], portee[f], fhow[k], f, fdet[k]
    if (f in dead) print "ecart", "lien-mort", portee[f], "auto", f, dead[f] " : la cible n\047est plus une fiche, le lien devient du texte"
    if (f in open) print "ecart", "lien-sans-cible", portee[f], "session", f, open[f] " : aucune fiche de ce nom"
  }
  # A project without a file in general/projets/ is missing from the list of projects the
  # routing table points to. Only where that folder is in use.
  if (ngp > 0) {
    while ((getline p < projects) > 0) {
      found = 0
      for (k = 1; k <= ngp && !found; k++) if (index(gp[k], lower(p)) > 0) found = 1
      if (!found) print "ecart", "projet-sans-fiche", "dans", "session", "general/projets/", "projet " p " : aucune fiche dans general/projets/"
    }
    close(projects)
  }
}'

# Rewrite one memory file. Main input: the file. Variables: path (its repository path) and
# ops (the file written by AWK_FICHES). Prints the new content with LF line endings: the
# header put in order, the dead links of the text replaced by their name, and every other
# byte of the text as it was.
AWK_REWRITE="$AWK_LOWER"'
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
# Replace the dead links of a piece of text by their plain name, or by their label when
# the link is written [[name|label]]. A link to the journal becomes the path of the journal.
function plain(seg,   out, whole, tgt, shown, bar, low) {
  out = ""
  while (match(seg, /\[\[[^][]+\]\]/)) {
    whole = substr(seg, RSTART, RLENGTH)
    tgt = substr(whole, 3, RLENGTH - 4)
    shown = tgt
    bar = index(tgt, "|")
    if (bar > 0) { shown = substr(tgt, bar + 1); tgt = substr(tgt, 1, bar - 1) }
    sub(/#.*$/, "", tgt)
    low = lower(trim(tgt))
    if (low in dead) whole = (dead[low] != "-") ? dead[low] : trim(shown)
    out = out substr(seg, 1, RSTART - 1) whole
    seg = substr(seg, RSTART + RLENGTH)
  }
  return out seg
}
# Print the metadata block: its own lines, the keys moved into it, and the status. <g> is
# the group of the existing block, or 0 when the header has none.
function emit_meta(g,   i, j, nc, c, ind, seen, nt, t, at, line) {
  ind = "  "
  nc = 0; nt = 0; seen = 0
  if (g > 0) {
    print L[gstart[g]]
    for (i = gstart[g] + 1; i <= gend[g]; i++) {
      if (!seen && L[i] ~ /^[ \t]+[^ \t]/) { ind = L[i]; sub(/[^ \t].*$/, "", ind); seen = 1 }
      c[++nc] = L[i]
    }
    # Blank lines that close the block stay after what is added.
    while (nc > 0 && c[nc] ~ /^[ \t]*$/) { t[++nt] = c[nc]; nc-- }
  } else {
    print "metadata:"
  }
  if (newstatus != "") for (i = 1; i <= nc; i++) if (c[i] ~ ("^" ind "status[ \t]*:")) c[i] = ind "status: " newstatus
  for (j = 1; j <= ng; j++) {
    if (gkey[j] == "" || !(gkey[j] in move)) continue
    for (i = gstart[j]; i <= gend[j]; i++) {
      line = L[i]
      if (line ~ /^[ \t]*$/) continue
      if (gkey[j] == "status" && i == gstart[j] && newstatus != "") line = "status: " newstatus
      c[++nc] = ind line
    }
  }
  if (addstatus) {
    # After the type when there is one: the order the format of a memory file shows.
    at = nc
    for (i = 1; i <= nc; i++) if (c[i] ~ ("^" ind "type[ \t]*:")) at = i
    for (i = nc; i > at; i--) c[i + 1] = c[i]
    c[at + 1] = ind "status: actif"
    nc++
  }
  for (i = 1; i <= nc; i++) print c[i]
  for (i = nt; i >= 1; i--) print t[i]
}
BEGIN {
  while ((getline l < ops) > 0) {
    split(l, a, "\t")
    if (a[1] != path) continue
    if (a[2] == "add") addstatus = 1
    else if (a[2] == "set") newstatus = a[3]
    else if (a[2] == "move") { move[a[3]] = 1; nmove++ }
    else if (a[2] == "link") { dead[lower(a[3])] = (a[4] == "") ? "-" : a[4]; ndead++ }
  }
  close(ops)
}
{ sub(/\r$/, ""); L[NR] = $0 }
END {
  n = NR
  last = 0
  first = L[1]
  sub(/^\357\273\277/, "", first)
  if (n >= 1 && first ~ /^---[ \t]*$/) for (i = 2; i <= n && !last; i++) if (L[i] ~ /^(---|\.\.\.)[ \t]*$/) last = i
  if (last > 0 && (addstatus || newstatus != "" || nmove > 0)) {
    # The header as groups: a key with the lines that continue it. Anything else (a comment)
    # is a group of its own and stays where it is.
    ng = 0
    for (i = 2; i < last; i++) {
      if (L[i] ~ /^[A-Za-z_][A-Za-z0-9_-]*[ \t]*:/) {
        key = L[i]
        sub(/[ \t]*:.*$/, "", key)
        ng++; gkey[ng] = key; gstart[ng] = i; gend[ng] = i
      } else if (ng > 0 && (L[i] ~ /^[ \t]/ || L[i] == "")) {
        gend[ng] = i
      } else {
        ng++; gkey[ng] = ""; gstart[ng] = i; gend[ng] = i
      }
    }
    print L[1]
    done = 0
    for (g = 1; g <= ng; g++) {
      if (gkey[g] != "" && (gkey[g] in move)) continue
      if (gkey[g] == "metadata") { emit_meta(g); done = 1 }
      else for (i = gstart[g]; i <= gend[g]; i++) print L[i]
    }
    if (!done) emit_meta(0)
    print L[last]
  } else {
    for (i = 1; i <= last; i++) print L[i]
  }
  fence = 0
  for (i = last + 1; i <= n; i++) {
    line = L[i]
    if (line ~ /^[ \t]*(```|~~~)/) { fence = !fence; print line; continue }
    if (fence || ndead == 0 || index(line, "[[") == 0) { print line; continue }
    m = split(line, seg, "`")
    out = ""
    for (k = 1; k <= m; k++) out = out (k > 1 ? "`" : "") ((k % 2 == 1) ? plain(seg[k]) : seg[k])
    print out
  }
}'

# Leave the script, in an unattended pass, with a report file that says what happened even
# when nothing went as planned: a pass that fails in silence is the worst outcome. Also
# gives back what the script wrote on stderr, which was kept aside for that file.
finish() {
  local rc=$?
  if [[ "$PLANNED" -eq 1 ]]; then
    exec 2>&3
    if [[ -s "$TMP/stderr" ]]; then cat "$TMP/stderr" >&2; fi
    if [[ "$REPORT_DONE" -eq 0 ]]; then
      {
        echo "== Passage planifie du $(date '+%Y-%m-%d %H:%M') sur $(host_label) : interrompu, code $rc =="
        cat "$TMP/stderr" 2>/dev/null || true
        echo "== Rien n'a ete corrige ni commite par ce passage =="
      } > "$REPORT_FILE" 2>/dev/null || true
      write_history "interrompu" "-" "-" "-" "-" || true
    fi
  fi
  rm -rf "$TMP"
}

# Append one line to the history kept beside the report: date, device, mode, scope, score,
# findings left in the scope, repairs, commit. One line per pass, so the score can be
# followed over time.
write_history() {
  local file
  file="$(dirname "$REPORT_FILE")/historique.tsv"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%d %H:%M')" "$(host_label)" "$1" "$(describe_scope)" "$2" "$3" "$4" "$5" >> "$file"
}

# Print what the last pass with a report left, when there is one on this device: the
# session opens on it instead of starting from nothing.
last_pass_note() {
  local file="$MEMOIRE_HOME/optimiser/historique.tsv" line
  [[ -f "$file" ]] || return 0
  line=$(tail -n 1 "$file")
  [[ -n "$line" ]] || return 0
  printf '%s\n' "$line" | LC_ALL=C awk -F'\t' -v report="$(display_path "$MEMOIRE_HOME/optimiser/dernier-rapport.txt")" \
    '{ print "(dernier passage avec rapport : " $1 ", " $3 ", score " $5 ", " $6 " ecart(s) dans sa portee ; rapport : " report ")" }'
}

# Split the uncommitted work of the clone by scope, into $TMP/pending-in and
# $TMP/pending-out ("status<TAB>path" lines).
collect_pending() {
  local work
  work=$(work_tree_id)
  diff_plain "$(head_tree)" "$work" | split_by_scope "$TMP/pending-in" "$TMP/pending-out"
}

# Guard: local work is about to be committed, and a commit travels with the next push.
guard_secrets() {
  local hits
  hits=$(awk -F'\t' '$1 != "D" { print $2 }' "$TMP/pending-in" | files_with_secrets)
  [[ -n "$hits" ]] || return 0
  echo "Motif de secret detecte dans le travail local :" >&2
  printf '%s\n' "$hits" >&2
  if [[ "$FORCE" -eq 0 ]]; then
    echo "Corrige ces fichiers puis relance. Rien n'a ete commite ni corrige." >&2
    exit 5
  fi
}

# Commit the uncommitted work of the scope listed in $TMP/pending-in, and nothing else.
# Usage: commit_pending <title> [message paragraph]...
commit_pending() {
  local tree
  tree=$(scoped_tree_id "$TMP/pending-in")
  ensure_identity
  commit_scoped "$tree" "$TMP/pending-in" "$@" "$(cat "$TMP/pending-in")" \
    || { echo "Le commit a echoue : rien n'a ete pousse, les fichiers restent tels quels dans le clone." >&2; exit 2; }
}

# Print the parts of the repository the uncommitted work of the scope touches.
pending_scopes() {
  cut -f2- "$TMP/pending-in" | scopes_of_paths
}

# Run reindex.sh with the scope of this script and keep its output in $TMP/reindex.out.
# Codes 0 and 9 are its two normal outcomes; anything else stops this script the same way.
run_reindex() {
  local rc=0
  bash "$SCRIPT_DIR/reindex.sh" "$1" --fiches ${SCOPE_ARGS[@]+"${SCOPE_ARGS[@]}"} > "$TMP/reindex.out" || rc=$?
  case "$rc" in
    0|9) ;;
    *) cat "$TMP/reindex.out"; exit "$rc" ;;
  esac
}

# Sort the output of reindex.sh into the files the rest of the script works from:
# preamble (what it says before its inventory), fiches (<path> <dans|hors> <folder of the
# index>), r-ecarts, r-corrige, projects (one project name per line) and journals (the
# projects that have a journal.md beside memory/).
split_reindex() {
  : > "$TMP/preamble"; : > "$TMP/fiches"; : > "$TMP/r-ecarts"; : > "$TMP/r-corrige"; : > "$TMP/projects"
  : > "$TMP/journals"
  LC_ALL=C awk -F'\t' -v OFS='\t' -v pre="$TMP/preamble" -v fiches="$TMP/fiches" \
    -v ecarts="$TMP/r-ecarts" -v fixed="$TMP/r-corrige" -v projects="$TMP/projects" -v journals="$TMP/journals" '
    /^== Inventaire ==$/ { body = 1; next }
    !body { print > pre; next }
    $1 == "fiche" {
      dir = $3; sub(/^index=/, "", dir); sub(/\/[^\/]*$/, "", dir)
      por = $5; sub(/^portee=/, "", por)
      print $2, por, dir > fiches
    }
    $1 == "ecart" { print > ecarts }
    $1 == "corrige" { print > fixed }
    ($1 == "dossier" || $1 == "fichier") && $2 ~ /^projets\/[^\/]+\// {
      p = $2; sub(/^projets\//, "", p); sub(/\/.*$/, "", p)
      if (!(p in seen)) { seen[p] = 1; print p > projects }
      if ($1 == "fichier" && $2 == "projets/" p "/journal.md") print p > journals
    }' "$TMP/reindex.out"
}

# Read from git what the files alone cannot tell: the names of the memory files that
# disappeared ($TMP/gone, lower case, one per line), and the date of the last commit of
# every path ($TMP/lastmod). A file deleted in the working tree and not committed yet has
# disappeared too.
read_history() {
  local work
  : > "$TMP/gone-raw"; : > "$TMP/lastmod"
  if have_head; then
    g log --diff-filter=D --no-renames --name-only --format= HEAD >> "$TMP/gone-raw"
    g log --format='@%cs' --name-only HEAD | LC_ALL=C awk -v OFS='\t' \
      '/^@/ { d = substr($0, 2); next } $0 != "" && !($0 in seen) { seen[$0] = 1; print $0, d }' > "$TMP/lastmod"
  fi
  work=$(work_tree_id)
  diff_plain "$(head_tree)" "$work" | awk -F'\t' '$1 == "D" { print $2 }' >> "$TMP/gone-raw"
  { grep -iE '\.md$' "$TMP/gone-raw" || true; } | sed -e 's#^.*/##' -e 's/\.[mM][dD]$//' \
    | LC_ALL=C tr 'A-Z' 'a-z' | LC_ALL=C sort -u > "$TMP/gone"
}

# Check the memory files and write the findings into <out>, and into $TMP/ops what a
# repair has to do.
scan_fiches() {
  (cd "$CLONE" && LC_ALL=C awk -v gone="$TMP/gone" -v lastmod="$TMP/lastmod" -v projects="$TMP/projects" \
    -v journals="$TMP/journals" \
    -v ref="$REF_DATE" -v maxbytes="$FICHE_MAX_BYTES" -v age_project="$AGE_PROJECT_DAYS" \
    -v age_reference="$AGE_REFERENCE_DAYS" -v ops="$TMP/ops" "$AWK_FICHES" "$TMP/fiches") > "$1"
}

# Rewrite the files of the scope that $TMP/ops names. Each one keeps its line endings and
# the way it ends.
apply_fixes() {
  local path
  cut -f1 "$TMP/ops" | LC_ALL=C sort -u > "$TMP/ops-files"
  while IFS= read -r path; do
    [[ -n "$path" && -f "$CLONE/$path" ]] || continue
    LC_ALL=C awk -v path="$path" -v ops="$TMP/ops" "$AWK_REWRITE" "$CLONE/$path" > "$TMP/new-fiche"
    install_text "$TMP/new-fiche" "$CLONE/$path" keep-end \
      || { echo "Impossible d'ecrire $(display_path "$CLONE/$path")" >&2; exit 2; }
  done < "$TMP/ops-files"
}

# Print the health of the memory from a file of findings: the files of the scope, those
# without any finding, the score, then the same for the whole repository. A finding belongs
# to a memory file when it names it; a missing index line belongs to the file it is
# missing for.
health() {
  LC_ALL=C awk -F'\t' -v fiches="$TMP/fiches" '
    BEGIN {
      while ((getline l < fiches) > 0) { split(l, a, "\t"); n++; path[n] = a[1]; por[a[1]] = a[2] }
      close(fiches)
    }
    $1 == "ecart" {
      f = $5
      if ($2 == "index-ligne-manquante") { sub(/\/[^\/]*$/, "", f); f = f "/" $6 }
      if (f in por) bad[f] = 1
    }
    END {
      for (i = 1; i <= n; i++) {
        p = path[i]
        all++
        if (!(p in bad)) allok++
        if (por[p] == "dans") { inside++; if (!(p in bad)) insideok++ }
      }
      print "fiches=" inside + 0
      print "fiches_sans_ecart=" insideok + 0
      print "score=" (inside ? int(100 * insideok / inside) : "-")
      print "fiches_depot=" all + 0
      print "depot_sans_ecart=" allok + 0
      print "score_depot=" (all ? int(100 * allok / all) : "-")
    }' "$1"
}

# Print the proposals of the scope from a file of findings, most serious first, numbered.
proposals() {
  LC_ALL=C awk -F'\t' -v OFS='\t' -v map="$GRAVITY" '
    BEGIN { n = split(map, a, " "); for (i = 1; i <= n; i++) { split(a[i], kv, "="); rank[kv[1]] = kv[2] } }
    $1 == "ecart" && $3 == "dans" && $4 == "session" { print (($2 in rank) ? rank[$2] : 2), NR, $2, $5, $6 }' "$1" \
    | LC_ALL=C sort -t "$(printf '\t')" -k1,1n -k2,2n \
    | LC_ALL=C awk -F'\t' -v OFS='\t' 'BEGIN { g[1] = "haute"; g[2] = "moyenne"; g[3] = "faible" }
        { print "proposition", NR, g[$1], $3, $4, $5 }'
}

# Print how many findings there are of each type, in the scope and outside it.
by_type() {
  LC_ALL=C awk -F'\t' '$1 == "ecart" { c[$2] = 1; if ($3 == "dans") a[$2]++; else b[$2]++ }
    END { for (k in c) print "type\t" k "\tdans=" a[k] + 0 "\thors=" b[k] + 0 }' "$1" | LC_ALL=C sort
}

# Print the first lines of a report made by this script alone: the clone and the scope.
own_preamble() {
  echo "== Clone : $(display_path "$CLONE") =="
  echo "== Portee : $(describe_scope) =="
  printf '%s' "$SCOPE_NOTE"
}

make_tmp
if [[ "$PLANNED" -eq 1 ]]; then
  REPORT_FILE="${REPORT_FILE:-$MEMOIRE_HOME/optimiser/dernier-rapport.txt}"
  # Nobody is there to answer a prompt: git and its credential helper must fail instead of
  # waiting. The soft fetch of reindex.sh then works on the state of the last exchange.
  export GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never
fi
if [[ -n "$REPORT_FILE" ]]; then
  mkdir -p "$(dirname "$REPORT_FILE")" || { echo "Impossible de creer le dossier du rapport : $(dirname "$REPORT_FILE")" >&2; exit 2; }
fi
if [[ "$PLANNED" -eq 1 ]]; then
  exec 3>&2 2>"$TMP/stderr"
  trap finish EXIT
fi
ensure_clone

# Guard: during a merge the files may hold conflict markers, and a commit made here would
# get in the way of its conclusion.
if merge_in_progress; then
  echo "Une fusion est en cours dans le clone : rien ne peut etre corrige ni commite avant sa conclusion." >&2
  echo "Conclus-la (pull.sh --conclude) ou annule-la (pull.sh --abort), puis relance." >&2
  exit 6
fi

resolve_branch
# The remarks of the scope are printed by reindex.sh, which builds the same one: keep the
# ones of this call for the mode that does not run it.
build_scope > /dev/null

if [[ "$MODE" == "--commit" ]]; then
  require_branch
  own_preamble
  collect_pending
  if [[ ! -s "$TMP/pending-in" ]]; then
    echo "== Rien a commiter dans la portee : aucun fichier n'a change depuis le dernier commit =="
    print_rest "$TMP/pending-out"
    exit 0
  fi
  guard_secrets
  BEFORE="aucun"
  if have_head; then BEFORE=$(g rev-parse --short HEAD); fi
  TITLE="memoire($(pending_scopes)): optimisation, propositions appliquees depuis $(host_label) le $TODAY"
  echo "== Message de commit =="
  echo "$TITLE"
  echo
  if [[ -n "$MESSAGE" ]]; then echo "$MESSAGE"; echo; fi
  cat "$TMP/pending-in"
  commit_pending "$TITLE" "$MESSAGE"
  echo "== Commit local : $(g log -1 --format='%h %s') =="
  echo "== Etat d'avant : commit $BEFORE =="
  print_rest "$TMP/pending-out"
  echo "== Rien n'est pousse : un push enverra ce commit =="
  exit 0
fi

PRE_COMMIT=""
BEFORE=""
if [[ "$MODE" == "--fix" ]]; then
  require_branch
  # The commit of the pass must hold the repairs and nothing else: what the scope has in
  # progress is committed first, on its own. It stays local, like everything done here.
  collect_pending
  if [[ -s "$TMP/pending-in" ]]; then
    guard_secrets
    commit_pending "memoire($(pending_scopes)): travail local sur $(host_label) avant optimisation du $TODAY"
    PRE_COMMIT=$(g rev-parse --short HEAD)
  fi
  BEFORE="aucun"
  if have_head; then BEFORE=$(g rev-parse --short HEAD); fi
fi

if [[ "$MODE" == "--fix" ]]; then run_reindex --fix; else run_reindex --check; fi
split_reindex
read_history

FIXED=0
COMMIT=""
SCORE_BEFORE=""
: > "$TMP/fixed"
scan_fiches "$TMP/own"
if [[ "$MODE" == "--fix" ]]; then
  cp "$TMP/own" "$TMP/own-before"
  # What the scope held before the pass: what reindex.sh repaired, what it left, and what
  # this script found in the files.
  {
    LC_ALL=C awk -F'\t' -v OFS='\t' '$1 == "corrige" { print "ecart", $2, "dans", "auto", $3, $4 }' "$TMP/r-corrige"
    cat "$TMP/r-ecarts" "$TMP/own-before"
  } > "$TMP/ecarts-before"
  SCORE_BEFORE=$(health "$TMP/ecarts-before" | sed -n 's/^score=//p')
  apply_fixes
  # What the pass found in the scope and could repair is what it repaired.
  {
    cat "$TMP/r-corrige"
    LC_ALL=C awk -F'\t' -v OFS='\t' '$1 == "ecart" && $3 == "dans" && $4 == "auto" { print "corrige", $2, $5, $6 }' "$TMP/own-before"
  } > "$TMP/fixed"
  FIXED=$(count_where 1 "$TMP/fixed")
  # The report always comes from a fresh reading: after a repair, it shows what is left.
  scan_fiches "$TMP/own"
fi

cat "$TMP/r-ecarts" "$TMP/own" > "$TMP/ecarts"
health "$TMP/ecarts" > "$TMP/health"
SCORE=$(sed -n 's/^score=//p' "$TMP/health")

if [[ "$MODE" == "--fix" ]]; then
  collect_pending
  if [[ -s "$TMP/pending-in" ]]; then
    RECAP="Corrections automatiques : $FIXED. Score de sante de la portee : $SCORE_BEFORE -> $SCORE (sur 100)."
    LIST=$(LC_ALL=C awk -F'\t' '{ print "- " $2 " : " $3 }' "$TMP/fixed")
    commit_pending "memoire($(pending_scopes)): optimisation depuis $(host_label) le $TODAY" "$RECAP" "$LIST"
    COMMIT=$(g rev-parse --short HEAD)
  fi
fi

TOTAL=$(count_where 1 "$TMP/ecarts")
INSIDE=$(count_where '$3 == "dans"' "$TMP/ecarts")
AUTO=$(count_where '$3 == "dans" && $4 == "auto"' "$TMP/ecarts")
SESSION=$(count_where '$3 == "dans" && $4 == "session"' "$TMP/ecarts")
OUTSIDE=$(count_where '$3 == "hors"' "$TMP/ecarts")
OUTSIDE_AUTO=$(count_where '$3 == "hors" && $4 == "auto"' "$TMP/ecarts")
OFF_FILES=$(LC_ALL=C awk -F'\t' -v fiches="$TMP/fiches" '
  BEGIN { while ((getline l < fiches) > 0) { split(l, a, "\t"); is[a[1]] = 1 } }
  $1 == "ecart" && $3 == "dans" {
    f = $5
    if ($2 == "index-ligne-manquante") { sub(/\/[^\/]*$/, "", f); f = f "/" $6 }
    if (!(f in is)) n++
  }
  END { print n + 0 }' "$TMP/ecarts")

{
  cat "$TMP/preamble"
  if [[ "$PLANNED" -eq 1 ]]; then
    echo "== Passage planifie du $(date '+%Y-%m-%d %H:%M') sur $(host_label) =="
  else
    last_pass_note
  fi
  if [[ -n "$PRE_COMMIT" ]]; then
    echo "(travail local de la portee commite a part avant le passage : $PRE_COMMIT)"
  fi
  if [[ "$MODE" == "--fix" ]]; then
    echo "== Corrections =="
    cat "$TMP/fixed"
  fi
  echo "== Ecarts =="
  cat "$TMP/ecarts"
  echo "== Propositions =="
  proposals "$TMP/ecarts"
  echo "== Sante (au $REF_DATE) =="
  cat "$TMP/health"
  if [[ -n "$SCORE_BEFORE" ]]; then echo "score_avant=$SCORE_BEFORE"; fi
  echo "ecarts_hors_fiches=$OFF_FILES"
  by_type "$TMP/ecarts"
  echo "== Bilan =="
  echo "ecarts=$TOTAL"
  echo "dans_portee=$INSIDE"
  echo "corrigeables=$AUTO"
  echo "propositions=$SESSION"
  echo "hors_portee=$OUTSIDE"
  echo "corriges=$FIXED"
  echo "commit=${COMMIT:--}"
  if [[ "$OUTSIDE" -gt 0 ]]; then
    echo "($OUTSIDE ecart(s) dans des projets hors de la portee, dont $OUTSIDE_AUTO corrigeable(s) : signales, pas modifies. Ils se traitent depuis une session de ces projets, ou avec --all sur demande explicite)"
  fi
  if [[ "$MODE" == "--fix" && -n "$COMMIT" ]]; then
    echo "== $FIXED correction(s) ecrite(s) et commitee(s) en local : $(g log -1 --format='%h %s') =="
    echo "== Etat d'avant : commit $BEFORE =="
    echo "== Rien n'est pousse : un push enverra ce commit =="
  elif [[ "$MODE" == "--fix" ]]; then
    echo "== Rien a corriger dans la portee : rien n'a ete ecrit ni commite par ce passage =="
  else
    if [[ "$AUTO" -gt 0 ]]; then echo "($AUTO ecart(s) corrigeable(s) par --fix avec la meme portee)"; fi
    echo "== Verification seule : rien n'a ete ecrit =="
  fi
} > "$TMP/report"
cat "$TMP/report"

if [[ -n "$REPORT_FILE" ]]; then
  cp "$TMP/report" "$REPORT_FILE" || { echo "Impossible d'ecrire le rapport : $(display_path "$REPORT_FILE")" >&2; exit 2; }
  REPORT_DONE=1
  LABEL="controle"
  if [[ "$PLANNED" -eq 1 ]]; then LABEL="planifie"; elif [[ "$MODE" == "--fix" ]]; then LABEL="correction"; fi
  write_history "$LABEL" "$SCORE" "$INSIDE" "$FIXED" "${COMMIT:--}"
  echo "(rapport ecrit dans $(display_path "$REPORT_FILE"))"
fi
if [[ "$INSIDE" -gt 0 ]]; then exit "$EXIT_FINDINGS"; fi
exit 0
