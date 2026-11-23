#!/usr/bin/env bash
# Check what lets a session find its way in the memory repository, and repair the part of
# it that is mechanical: AGENTS.md, the routing table at the root of the repository, and
# the MEMORY.md index of every memory folder. Works on the durable clone. Nothing is ever
# committed or pushed here: push.sh sends the result, with its own guards.
#
# Usage: reindex.sh [--check|--fix] [--fiches] [scope]
#   --check  : report, write nothing (default)
#   --fix    : repair the indexes of the scope, then report what is left
#   --fiches : also list every file to index in the inventory, one "fiche" record each.
#              Meant for optimiser.sh, which checks the files themselves from this list.
# Scope (see common.sh): the transverse part always, plus
#   --project <name>    a project, by name (repeatable)
#   --memory-dir <path> the project that holds the auto memory folder of the session
#   --all               every project, on explicit request only
# The whole repository is always read and reported. The scope decides what --fix may write
# and which findings count for the exit code: the other projects are reported and left
# exactly as they are.
#
# What is read. The files of the working state as git would commit them (ignored files are
# left out, names are spelled as the repository spells them), so every device sees the same
# inventory. Hidden files and folders are never memory.
#   general/                 a memory folder: one index, general/MEMORY.md, for every .md
#                            file below it. Each direct sub-folder is a place to route.
#   projets/<name>/memory/   the memory of a project: one index for the .md files directly
#                            inside. Anything else found there (a sub-folder, a file that is
#                            not a .md) is reported: it belongs beside memory/.
#   projets/<name>/<other>   what is kept beside memory/ (a journal, a snapshot): never
#                            indexed, but a place to route.
#   <other top-level folder> a place to route; indexed like general/ when it holds a
#                            MEMORY.md at its root.
#
# AGENTS.md. Its routing table lives between two marker lines, an HTML comment each:
#   <!-- reindex:debut -->   and   <!-- reindex:fin -->
# Only what stands between them is generated, by the reindex skill. The rest of the file
# (introduction, rules, file format) is written by the user and is never rewritten: the
# script only reads it, to count lines and bytes and to tell whether it changed since the
# last commit (agents_hors_bloc). Inside the block, every table row names in its first cell
# the path it describes, between backticks. A segment written <...> stands for any one
# name, so `projets/<nom>/memory/` covers every project. A place is routed when an entry
# names it or one of its parents; an entry is dead when no path of the repository matches.
# The script never writes AGENTS.md, in either mode: its entries are prose.
#
# Indexes. One line per file, no dead line. A line of the index is a line that holds a
# Markdown link to a .md file; links shown inside a code span or a fenced block are
# examples and are not read. --fix adds the missing lines, built from the
# header of the files (- [name](path) : description), removes the lines whose every link is
# dead and the exact copies of a line, creates a missing index (with its title alone when
# no file has a header to build a line from), and gives a link the letter case of the file
# it names. Added lines go to the end of the index, under the heading
# "## Lignes reconstruites" when the index is organised in sections: filing them is left to
# the session.
#
# Output, meant to be read by a session and parsed by another script. Sections are
# introduced by "== ... ==" lines. Records are tab-separated and start with a keyword:
#   dossier|fichier <path> type=<generale|memoire|a-cote|projet|autre> [fiches=<n>]
#                   routage=<oui|non|-> [entree=<entry>] portee=<dans|hors>
#   index   <path> etat=<present|absent> lignes=<n> fiches=<n> portee=<dans|hors>
#   fiche   <path> index=<path of its index> entete=<oui|non> portee=<dans|hors>  (--fiches only)
#   ecart   <code> <dans|hors> <auto|session> <file> <detail>
#   corrige <code> <file> <detail>                      (--fix only)
# "auto" is what --fix repairs, "session" needs a decision or some writing. The AGENTS.md
# and "Bilan" sections hold key=value lines. Finding codes:
#   agents-absent, agents-hors-limites, agents-bloc-invalide, agents-entree-illisible,
#   agents-entree-sans-chemin, agents-chemin-sans-entree,
#   index-absent, index-trop-long, index-lien-casse, index-ligne-morte,
#   index-ligne-en-double, index-ligne-manquante,
#   fiche-sans-entete, fiche-entete-incomplet, memoire-hors-fiche
#
# Exit codes: 0 nothing left to do in the scope, 1 usage, 2 git error, 6 merge in progress,
#             9 findings left in the scope, 10 no repository configured,
#             11 the clone belongs to another repository.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

USAGE="usage: reindex.sh [--check|--fix] [--fiches] [--project <nom>] [--memory-dir <chemin>] [--all]"
MODE="--check"
LIST_FICHES=0
# A while loop rather than for: several options consume the argument that follows them.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check|--fix) MODE="$1" ;;
    --fiches) LIST_FICHES=1 ;;
    --all) SCOPE_ALL=1 ;;
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

AGENTS_FILE="AGENTS.md"
INDEX_NAME="MEMORY.md"
# AGENTS.md is imported into every session: it has to stay small. 200 lines is the size the
# Claude Code documentation aims at for an instruction file, 16 kB the smallest limit known
# among the tools that read AGENTS.md.
AGENTS_MAX_LINES=200
AGENTS_MAX_BYTES=16000
# Claude Code loads the first 200 lines of a MEMORY.md at session start, or its first 25 kB
# when they come sooner: a longer index hides its last lines from the session.
INDEX_MAX_LINES=200
INDEX_MAX_BYTES=25000
REBUILT_HEADING="## Lignes reconstruites"
NEW_INDEX_TITLE="# Memory index"
EXIT_FINDINGS=9

# Sort the files of the working state into what the checks need. Input: repository paths,
# sorted. Writes four tab-separated files:
#   holders : <folder> <rec|flat> <has an index: 0|1> <number of files to index>
#   fiches  : <folder that indexes it> <path>
#   units   : <d|f> <kind> <path> <number of files, or ->     the places to route
#   extra   : <code> <path> <detail>                         findings read off the tree
AWK_TREE='
BEGIN { FS = "/"; OFS = "\t" }
{
  n = NF
  # Nothing under a hidden folder is memory (.git is not listed, .claude and the like are).
  for (i = 1; i < n; i++) if (substr($i, 1, 1) == ".") next
  if (n == 1) next
  base = $n
  hidden = (substr(base, 1, 1) == ".")
  md = (tolower(base) ~ /\.md$/)
  top = $1
  if (top == "projets") {
    if (n == 2) next
    p = "projets/" $2
    if (!(p in pseen)) { pseen[p] = 1; plist[++np] = p }
    if (n == 3) {
      if (!hidden) { pside[p]++; sidetype[p, pside[p]] = "f"; sidepath[p, pside[p]] = $0 }
      next
    }
    if ($3 == "memory") {
      m = p "/memory"
      pmem[p] = 1
      if (n == 4) {
        if (hidden) next
        if (base == index_name) pidx[p] = 1
        else if (md) { pfiches[p]++; print m, $0 > fiches }
        else print "memoire-hors-fiche", $0, "fichier qui n\047est pas une fiche, a ranger a cote de memory/" > extra
      } else {
        d = m "/" $4
        if (!(d in dseen)) { dseen[d] = 1; print "memoire-hors-fiche", d "/", "sous-dossier, a ranger a cote de memory/" > extra }
      }
      next
    }
    d = p "/" $3
    if (!(d in dseen)) { dseen[d] = 1; pside[p]++; sidetype[p, pside[p]] = "d"; sidepath[p, pside[p]] = d }
    next
  }
  if (!(top in tseen)) { tseen[top] = 1; tlist[++nt] = top }
  if (n == 2) {
    if (hidden) next
    if (base == index_name) tidx[top] = 1
    else if (md) { tloose[top]++; tcand[top] = tcand[top] $0 "\n" }
    next
  }
  s = top "/" $2
  if (!(s in sseen)) { sseen[s] = 1; tsub[top]++; subpath[top, tsub[top]] = s }
  # A MEMORY.md deeper than the root of the folder is neither its index nor a file to index.
  if (!hidden && md && base != index_name) { sfiches[s]++; tcand[top] = tcand[top] $0 "\n" }
}
END {
  for (i = 1; i <= nt; i++) {
    t = tlist[i]
    kind = (t == "general") ? "generale" : "autre"
    if (t == "general" || (t in tidx)) {
      total = tloose[t] + 0
      for (j = 1; j <= tsub[t]; j++) total += sfiches[subpath[t, j]]
      print t, "rec", ((t in tidx) ? 1 : 0), total > holders
      m = split(tcand[t], c, "\n")
      for (j = 1; j < m; j++) print t, c[j] > fiches
      # The folder itself is a place to route when files sit directly in it, or when it has
      # no sub-folder to stand for it.
      if (tloose[t] > 0 || tsub[t] == 0) print "d", kind, t, tloose[t] + 0 > units
      for (j = 1; j <= tsub[t]; j++) print "d", kind, subpath[t, j], sfiches[subpath[t, j]] + 0 > units
    } else {
      print "d", kind, t, "-" > units
    }
  }
  for (i = 1; i <= np; i++) {
    p = plist[i]
    if (p in pmem) {
      print p "/memory", "flat", ((p in pidx) ? 1 : 0), pfiches[p] + 0 > holders
      print "d", "memoire", p "/memory", pfiches[p] + 0 > units
    }
    for (j = 1; j <= pside[p]; j++) print sidetype[p, j], "a-cote", sidepath[p, j], "-" > units
    if (!(p in pmem) && pside[p] == 0) print "d", "projet", p, "-" > units
  }
}'

# Read the header of every file to index. Input: the fiches file (<folder> <path>), with the
# clone as current directory. Prints <folder> <path> <has a header: 0|1> <name> <description>.
# Only the header is read, and only the two keys an index line is built from: a value on
# the line of its key, quoted or not, or folded on the indented lines that follow.
AWK_HEAD="$AWK_UNQUOTE"'
BEGIN { FS = "\t"; OFS = "\t" }
{
  f = $2
  fm = 0; name = ""; desc = ""; key = ""; n = 0
  while ((getline line < f) > 0) {
    n++
    sub(/\r$/, "", line)
    if (n == 1) {
      # A byte order mark may precede the first dashes.
      sub(/^\357\273\277/, "", line)
      if (line !~ /^---[ \t]*$/) break
      fm = 1
      continue
    }
    if (line ~ /^(---|\.\.\.)[ \t]*$/) break
    if (line ~ /^[A-Za-z_][A-Za-z0-9_-]*[ \t]*:/) {
      key = line
      sub(/[ \t]*:.*$/, "", key)
      val = line
      sub(/^[^:]*:[ \t]*/, "", val)
      # A block scalar (> or |) announces a value written on the lines that follow.
      if (val ~ /^[>|][+-]?[0-9]?[ \t]*$/) val = ""
      if (key == "name") name = val
      else if (key == "description") desc = val
    } else if (line ~ /^[ \t]+[^ \t]/ && (key == "name" || key == "description")) {
      sub(/^[ \t]+/, "", line)
      if (key == "name") name = (name == "") ? line : name " " line
      else desc = (desc == "") ? line : desc " " line
    }
  }
  close(f)
  print $1, f, fm, unquote(name), unquote(desc)
}'

# Check one index, and write its repaired content when asked to. Main input: the index (or
# /dev/null when there is none). Variables: dir (the folder), present, portee, heads (output
# of AWK_HEAD), files (every path of the repository), maxlines, maxbytes, heading, title, and, to
# repair, fix=1 with out, the file that receives the new content. Prints the findings and
# one "index" record.
AWK_INDEX='
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function emit(code, how, file, detail) { print "ecart", code, portee, how, file, detail }
# Resolve a link target against the folder of the index, "." and ".." included.
function resolve(base, rel,   parts, n, i, m, stack, out) {
  n = split(base "/" rel, parts, "/")
  m = 0
  for (i = 1; i <= n; i++) {
    if (parts[i] == "" || parts[i] == ".") continue
    if (parts[i] == "..") { if (m > 0) m--; continue }
    stack[++m] = parts[i]
  }
  out = ""
  for (i = 1; i <= m; i++) out = out (i > 1 ? "/" : "") stack[i]
  return out
}
# Count one more line of the index for a file, once per line.
function hitline(p) {
  if (lasthit[p] == NR) return
  lasthit[p] = NR
  cnt[p]++
  hit[p] = hit[p] (hit[p] == "" ? "" : " ") NR
}
BEGIN {
  OFS = "\t"
  while ((getline l < heads) > 0) {
    split(l, a, "\t")
    if (a[1] != dir) continue
    fl[++nf] = a[2]; fm[a[2]] = a[3]; nm[a[2]] = a[4]; ds[a[2]] = a[5]
  }
  close(heads)
  while ((getline l < files) > 0) { exist[l] = 1; low[tolower(l)] = l }
  close(files)
  ipath = dir "/" index_name
}
{
  sub(/\r$/, "")
  raw[NR] = $0
  # Bytes as the repository stores them: the locale is C, and line endings count for one.
  nbytes += length($0) + 1
  links[NR] = 0
  dead[NR] = 0
  # A fenced block or a code span shows what a line looks like: its links are examples,
  # not lines of the index.
  if ($0 ~ /^[ \t]*(```|~~~)/) { fence = !fence; next }
  if (fence) next
  s = $0
  gsub(/`[^`]*`/, "", s)
  nl = 0; nd = 0
  # Every Markdown link of the line whose target is a .md path of the repository.
  while (match(s, /\]\([^)]*\)/)) {
    t = trim(substr(s, RSTART + 2, RLENGTH - 3))
    s = substr(s, RSTART + RLENGTH)
    angle = 0
    if (substr(t, 1, 1) == "<") { angle = 1; t = substr(t, 2); sub(/>.*$/, "", t) }
    else sub(/[ \t]+["\047(].*$/, "", t)
    sub(/#.*$/, "", t)
    if (t == "" || t ~ /^[A-Za-z][A-Za-z0-9+.-]*:/ || substr(t, 1, 1) == "/") continue
    if (tolower(t) !~ /\.md$/) continue
    written = t
    gsub(/%20/, " ", t)
    p = resolve(dir, t)
    nl++
    if (p in fm) hitline(p)
    else if (p in exist) nl = nl
    else if (tolower(p) in low) {
      # The file exists under another letter case: the link works on Windows and macOS and
      # breaks everywhere else.
      real = low[tolower(p)]
      cur = (NR in newraw) ? newraw[NR] : raw[NR]
      needle = (angle ? "](<" : "](") written
      at = index(cur, needle)
      if (at > 0 && substr(real, 1, length(dir) + 1) == dir "/") {
        good = substr(real, length(dir) + 2)
        shown = good
        if (!angle) gsub(/ /, "%20", good)
        newraw[NR] = substr(cur, 1, at + length(needle) - length(written) - 1) good substr(cur, at + length(needle))
        ncase++
        cdet[ncase] = "ligne " NR " : " written " -> " shown; chow[ncase] = "auto"
      } else {
        nsess++
        cdet2[nsess] = "ligne " NR " : " written " -> " real
      }
      if (real in fm) hitline(real)
    } else {
      nd++
      deadt[NR] = deadt[NR] (deadt[NR] == "" ? "" : ", ") written
    }
  }
  links[NR] = nl
  dead[NR] = nd
}
END {
  n = present ? NR : 0
  if (!present) {
    if (nf > 0) emit("index-absent", "auto", ipath, nf " fiche(s) sans index")
  } else {
    if (n > maxlines) emit("index-trop-long", "session", ipath, n " lignes (limite " maxlines ")")
    if (nbytes > maxbytes) emit("index-trop-long", "session", ipath, nbytes " octets (limite " maxbytes ")")
    for (k = 1; k <= ncase; k++) emit("index-lien-casse", "auto", ipath, cdet[k])
    for (k = 1; k <= nsess; k++) emit("index-lien-casse", "session", ipath, cdet2[k])
    for (i = 1; i <= n; i++) {
      if (dead[i] == 0) continue
      if (dead[i] == links[i]) {
        drop[i] = 1; ndrop++
        emit("index-ligne-morte", "auto", ipath, "ligne " i " : " trim(raw[i]))
      } else {
        # Other links of the line are alive: removing it would lose them.
        emit("index-ligne-morte", "session", ipath, "ligne " i " (" deadt[i] " introuvable, le reste de la ligne est vivant) : " trim(raw[i]))
      }
    }
    for (j = 1; j <= nf; j++) {
      p = fl[j]
      if (cnt[p] < 2) continue
      m = split(hit[p], h, " ")
      same = 1
      nums = h[1]
      for (k = 2; k <= m; k++) {
        nums = nums ", " h[k]
        if (trim(raw[h[k]]) != trim(raw[h[1]])) same = 0
      }
      rel = substr(p, length(dir) + 2)
      if (same) {
        for (k = 2; k <= m; k++) if (!drop[h[k]]) { drop[h[k]] = 1; ndrop++ }
        emit("index-ligne-en-double", "auto", ipath, rel " : lignes " nums ", identiques")
      } else {
        emit("index-ligne-en-double", "session", ipath, rel " : lignes " nums ", differentes")
      }
    }
  }
  for (j = 1; j <= nf; j++) {
    p = fl[j]
    if (cnt[p] > 0) continue
    # No header, nothing to build a line from: the header finding below covers the file.
    if (fm[p] != 1 || (nm[p] == "" && ds[p] == "")) continue
    rel = substr(p, length(dir) + 2)
    t = nm[p]
    if (t == "") { t = rel; sub(/^.*\//, "", t); sub(/\.[mM][dD]$/, "", t) }
    add[++na] = "- [" t "](" ((rel ~ /[ ()]/) ? "<" rel ">" : rel) ")" ((ds[p] != "") ? " : " ds[p] : "")
    if (present) emit("index-ligne-manquante", "auto", ipath, rel)
  }
  for (j = 1; j <= nf; j++) {
    p = fl[j]
    has = (cnt[p] > 0) ? "presente" : "absente"
    if (fm[p] != 1) emit("fiche-sans-entete", "session", p, "ligne d\047index " has)
    else if (nm[p] == "" && ds[p] == "") emit("fiche-entete-incomplet", "session", p, "sans name ni description, ligne d\047index " has)
    else if (nm[p] == "") emit("fiche-entete-incomplet", "session", p, "sans name")
    else if (ds[p] == "") emit("fiche-entete-incomplet", "session", p, "sans description")
  }
  print "index", ipath, "etat=" (present ? "present" : "absent"), "lignes=" n, "fiches=" nf, "portee=" portee

  # A missing index is created even when no line can be built for it yet (no file has a
  # usable header): the finding says "auto", so the repair must leave an index behind.
  create = (!present && nf > 0)
  if (fix && (ndrop > 0 || na > 0 || ncase > 0 || create)) {
    printf "" > out
    last = 0; sections = 0; lasthead = ""; nk = 0
    for (i = 1; i <= n; i++) {
      if (drop[i]) continue
      cur = (i in newraw) ? newraw[i] : raw[i]
      keep[++nk] = cur
      if (cur ~ /[^ \t]/) last = nk
      if (cur ~ /^##[ \t]/) { sections = 1; lasthead = trim(cur) }
    }
    # Trailing blank lines only go when lines are appended after them.
    if (na == 0) last = nk
    for (i = 1; i <= last; i++) print keep[i] > out
    if (last == 0 && (na > 0 || create)) {
      print title > out
      if (na > 0) print "" > out
    } else if (na > 0) {
      if (sections && lasthead != heading) { print "" > out; print heading > out; print "" > out }
      else if (keep[last] ~ /^#/) print "" > out
    }
    for (k = 1; k <= na; k++) print add[k] > out
    close(out)
  }
}'

# Check AGENTS.md against the tree. Main input: AGENTS.md. Variables: files (every file path
# of the repository), units (the places to route), bytes, maxlines, maxbytes, agents (its
# path), cover and state (two files to write). Prints the findings; writes into cover one
# line per place (<path> <oui|non|-> <entry that covers it>) and into state the key=value
# lines of the AGENTS.md section.
AWK_AGENTS='
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function emit(code, detail) { nfind++; fcode[nfind] = code; fdet[nfind] = detail }
# Turn an entry into a regular expression: a segment written <...> matches any one name.
function torx(s,   r) {
  r = s
  gsub(/<[^<>\/]*>/, "\001", r)
  gsub(/[][\\.^$*+?(){}|]/, "\\\\&", r)
  gsub(/\001/, "[^/]+", r)
  return r
}
# Record the path of an entry in one spelling: forward slashes, no "./", no trailing slash.
function addentry(e, line,   k) {
  k = trim(e)
  gsub(/\\/, "/", k)
  sub(/^\.\//, "", k)
  sub(/\/+$/, "", k)
  if (k == "") return 0
  ne++
  ent[ne] = k; entraw[ne] = trim(e); entline[ne] = line
  return 1
}
BEGIN {
  while ((getline l < files) > 0) {
    m = split(l, seg, "/")
    p = ""
    # Folders exist through the files they hold: record every parent of every file.
    for (i = 1; i <= m; i++) {
      p = (i == 1) ? seg[i] : p "/" seg[i]
      if (!(p in exist)) { exist[p] = 1; plist[++np] = p; low[tolower(p)] = p }
    }
  }
  close(files)
  while ((getline l < units) > 0) { split(l, a, "\t"); utype[++nu] = a[1]; upath[nu] = a[3] }
  close(units)
}
{
  sub(/\r$/, "")
  if ($0 ~ /^[ \t]*<!--[ \t]*reindex:debut/) { nstart++; if (nstart == 1) startl = NR; inblock = 1; sep = 0; next }
  if ($0 ~ /^[ \t]*<!--[ \t]*reindex:fin/) { nend++; if (nend == 1) endl = NR; inblock = 0; next }
  if (!inblock) next
  # A line that is not a table row ends the table: the next one brings its own heading row.
  if ($0 !~ /^[ \t]*\|/) { sep = 0; next }
  cell = $0
  sub(/^[ \t]*\|/, "", cell)
  sub(/\|.*$/, "", cell)
  if (cell ~ /^[ \t]*:?-+:?[ \t]*$/) { sep = 1; next }
  if (!sep) next
  found = 0
  c = cell
  while (match(c, /`[^`]+`/)) {
    if (addentry(substr(c, RSTART + 1, RLENGTH - 2), NR)) found = 1
    c = substr(c, RSTART + RLENGTH)
  }
  if (!found) {
    # Tolerate a path written without backticks, as long as the cell holds nothing else.
    c = trim(cell)
    if (c != "" && c !~ /[ \t]/ && addentry(c, NR)) found = 1
  }
  if (!found) bad[++nbad] = "ligne " NR " : " trim($0)
}
END {
  if (nstart == 0 && nend == 0) bloc = "absent"
  else if (nstart == 1 && nend == 1 && startl < endl) bloc = "ok"
  else bloc = "invalide"
  if (NR > maxlines) emit("agents-hors-limites", NR " lignes (limite " maxlines ")")
  if (bytes + 0 > maxbytes) emit("agents-hors-limites", bytes " octets (limite " maxbytes ")")
  if (bloc == "absent") emit("agents-bloc-invalide", "marqueurs reindex:debut et reindex:fin absents")
  else if (bloc == "invalide") emit("agents-bloc-invalide", nstart " marqueur(s) reindex:debut et " nend " reindex:fin : un de chaque, dans cet ordre")
  # Entries are only trusted inside a well-formed block.
  if (bloc != "ok") ne = 0
  for (k = 1; k <= nbad && bloc == "ok"; k++) emit("agents-entree-illisible", bad[k])
  for (k = 1; k <= ne; k++) {
    rx[k] = torx(ent[k])
    alive = 0
    if (ent[k] !~ /</) alive = (ent[k] in exist)
    else for (i = 1; i <= np && !alive; i++) if (plist[i] ~ ("^" rx[k] "$")) alive = 1
    if (!alive) {
      hint = ""
      if (ent[k] !~ /</ && (tolower(ent[k]) in low)) hint = " (casse differente : " low[tolower(ent[k])] ")"
      emit("agents-entree-sans-chemin", "ligne " entline[k] " : " entraw[k] hint)
    }
  }
  for (u = 1; u <= nu; u++) {
    if (bloc != "ok") { print upath[u] "\t-\t" > cover; continue }
    cov = ""
    for (k = 1; k <= ne && cov == ""; k++) if (upath[u] ~ ("^" rx[k] "(/.*)?$")) cov = entraw[k]
    if (cov == "") emit("agents-chemin-sans-entree", upath[u] (utype[u] == "d" ? "/" : ""))
    print upath[u] "\t" (cov == "" ? "non" : "oui") "\t" cov > cover
  }
  for (k = 1; k <= nfind; k++) print "ecart\t" fcode[k] "\tdans\tsession\t" agents "\t" fdet[k]
  print "agents_etat=present" > state
  print "agents_lignes=" NR > state
  print "agents_octets=" bytes > state
  print "agents_bloc=" bloc > state
  print "agents_entrees=" ne > state
}'

# Print the inventory lines. Main input: the units with their scope as fifth column.
# Variable: cover, the file written by AWK_AGENTS (missing when there is no AGENTS.md).
AWK_INVENTORY='
BEGIN {
  FS = "\t"
  while ((getline l < cover) > 0) { split(l, a, "\t"); cv[a[1]] = a[2]; ce[a[1]] = a[3] }
  close(cover)
}
{
  line = (($1 == "d") ? "dossier" : "fichier") "\t" $3 (($1 == "d") ? "/" : "") "\ttype=" $2
  if ($4 != "-") line = line "\tfiches=" $4
  line = line "\troutage=" (($3 in cv) ? cv[$3] : "-")
  if (($3 in ce) && ce[$3] != "") line = line "\tentree=" ce[$3]
  print line "\tportee=" $5
}'

# Print the files of the working state of the clone, one repository path per line, sorted.
# They are read from the tree git would commit (work_tree_id), not from the disk: ignored
# files are left out, deleted ones too, and a name is spelled as the repository spells it,
# which is what the other devices get. Requires make_tmp.
list_files() {
  local tree
  tree=$(work_tree_id)
  g ls-tree -r --name-only "$tree" | LC_ALL=C sort
}

# Print AGENTS.md (read on stdin) without what stands between its two markers: the part
# written by hand, the one no script and no skill may rewrite.
outside_block() {
  tr -d '\r' | LC_ALL=C awk '
    /^[ \t]*<!--[ \t]*reindex:debut/ { print; skip = 1; next }
    /^[ \t]*<!--[ \t]*reindex:fin/ { skip = 0 }
    !skip { print }'
}

# Print whether the hand-written part of AGENTS.md differs from the last commit: inchange,
# modifie, or nouveau when the file is not committed yet. A change is not a fault, the user
# edits their rules as they like; the skill uses it to prove that its own edit stayed
# inside the block.
hand_written_state() {
  if ! have_head || ! g cat-file -e "HEAD:$AGENTS_FILE" 2>/dev/null; then
    echo "nouveau"
    return 0
  fi
  if cmp -s <(g show "HEAD:$AGENTS_FILE" | outside_block) <(outside_block < "$CLONE/$AGENTS_FILE"); then
    echo "inchange"
  else
    echo "modifie"
  fi
}

# Check the index of one memory folder and append what is found to <findings>.
# With <apply> set and the index in the scope, also write the repaired index.
# Usage: scan_index <folder> <has an index: 0|1> <apply: 0|1> <findings file>
scan_index() {
  local dir="$1" present="$2" apply="$3" findings="$4" ipath portee input fix=0
  ipath="$dir/$INDEX_NAME"
  if in_scope "$ipath"; then portee="dans"; else portee="hors"; fi
  if [[ "$present" -eq 1 ]]; then input="$CLONE/$ipath"; else input="/dev/null"; fi
  if [[ "$apply" -eq 1 && "$portee" == "dans" ]]; then
    fix=1
    rm -f "$TMP/new-index"
  fi
  LC_ALL=C awk -v dir="$dir" -v present="$present" -v portee="$portee" -v index_name="$INDEX_NAME" \
    -v heads="$TMP/heads" -v files="$TMP/files" -v maxlines="$INDEX_MAX_LINES" -v maxbytes="$INDEX_MAX_BYTES" \
    -v heading="$REBUILT_HEADING" -v title="$NEW_INDEX_TITLE" -v fix="$fix" -v out="$TMP/new-index" \
    "$AWK_INDEX" "$input" >> "$findings"
  if [[ "$fix" -eq 1 && -e "$TMP/new-index" ]]; then
    install_text "$TMP/new-index" "$CLONE/$ipath" \
      || { echo "Impossible d'ecrire $(display_path "$CLONE/$ipath")" >&2; exit 2; }
  fi
}

# Read the whole repository and fill the files the report is made of: $TMP/units (with the
# scope as last column), $TMP/findings (ecart and index records), $TMP/cover and
# $TMP/state. With <apply> set, the indexes of the scope are repaired on the way, and the
# findings describe what was found before the repair.
scan() {
  local apply="$1" dir mode present count type kind path code file detail portee bytes
  list_files > "$TMP/files"
  : > "$TMP/holders"; : > "$TMP/fiches"; : > "$TMP/units-raw"; : > "$TMP/extra"
  : > "$TMP/findings"; : > "$TMP/state"
  rm -f "$TMP/cover"
  LC_ALL=C awk -v index_name="$INDEX_NAME" -v holders="$TMP/holders" -v fiches="$TMP/fiches" \
    -v units="$TMP/units-raw" -v extra="$TMP/extra" "$AWK_TREE" "$TMP/files"
  (cd "$CLONE" && LC_ALL=C awk "$AWK_HEAD" "$TMP/fiches") > "$TMP/heads"

  # AGENTS.md first: its findings open the report. It is looked up in the list of files,
  # not on the disk, where a name in another letter case would answer on Windows.
  if grep -qxF -- "$AGENTS_FILE" "$TMP/files"; then
    bytes=$(tr -d '\r' < "$CLONE/$AGENTS_FILE" | wc -c | tr -d ' ')
    LC_ALL=C awk -v files="$TMP/files" -v units="$TMP/units-raw" -v bytes="$bytes" \
      -v maxlines="$AGENTS_MAX_LINES" -v maxbytes="$AGENTS_MAX_BYTES" -v agents="$AGENTS_FILE" \
      -v cover="$TMP/cover" -v state="$TMP/state" "$AWK_AGENTS" "$CLONE/$AGENTS_FILE" >> "$TMP/findings"
    echo "agents_hors_bloc=$(hand_written_state)" >> "$TMP/state"
  else
    printf 'ecart\tagents-absent\tdans\tsession\t%s\t%s\n' "$AGENTS_FILE" "pas de table de routage a la racine du depot" >> "$TMP/findings"
    echo "agents_etat=absent" >> "$TMP/state"
  fi

  while IFS=$'\t' read -r dir mode present count; do
    [[ -n "$dir" ]] || continue
    scan_index "$dir" "$present" "$apply" "$TMP/findings"
  done < "$TMP/holders"

  while IFS=$'\t' read -r code file detail; do
    [[ -n "$code" ]] || continue
    if in_scope "$file"; then portee="dans"; else portee="hors"; fi
    printf 'ecart\t%s\t%s\tsession\t%s\t%s\n' "$code" "$portee" "$file" "$detail" >> "$TMP/findings"
  done < "$TMP/extra"

  : > "$TMP/units"
  while IFS=$'\t' read -r type kind path count; do
    [[ -n "$type" ]] || continue
    # A trailing component, so the folder of a project is seen as part of that project.
    if in_scope "$path/x"; then portee="dans"; else portee="hors"; fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$type" "$kind" "$path" "$count" "$portee" >> "$TMP/units"
  done < "$TMP/units-raw"
}

# Print one record per file to index, for the scripts that go on from this inventory
# (optimiser.sh). Input: $TMP/heads. Only the first three columns are read: the last two may
# be empty, and the shell folds empty tab-separated fields.
print_fiches() {
  local dir file fm rest entete portee
  while IFS=$'\t' read -r dir file fm rest; do
    [[ -n "$file" ]] || continue
    if [[ "$fm" == "1" ]]; then entete="oui"; else entete="non"; fi
    if in_scope "$file"; then portee="dans"; else portee="hors"; fi
    printf 'fiche\t%s\tindex=%s\tentete=%s\tportee=%s\n' "$file" "$dir/$INDEX_NAME" "$entete" "$portee"
  done < "$TMP/heads"
}

make_tmp
ensure_clone

# Guard: during a merge the indexes may hold conflict markers, and writing into them would
# get in the way of the resolution.
if merge_in_progress; then
  echo "Une fusion est en cours dans le clone : les index peuvent contenir des marqueurs de conflit." >&2
  echo "Conclus-la (pull.sh --conclude) ou annule-la (pull.sh --abort), puis relance." >&2
  exit 6
fi

# Reading works offline, on the state of the last exchange; the fetch only serves to say
# when the repository holds commits this clone does not have yet.
fetch_origin soft
resolve_branch
build_scope
count_divergence
echo "== Clone : $(display_path "$CLONE") =="
echo "== Portee : $(describe_scope) =="
printf '%s' "$SCOPE_NOTE"
if [[ "$BEHIND" -gt 0 ]]; then
  echo "(le depot a $BEHIND commit(s) que ce clone n'a pas encore : un pull d'abord evite de corriger un etat perime)"
fi

FIXED=0
if [[ "$MODE" == "--fix" ]]; then
  scan 1
  # What the repair pass found in the scope and could repair is what it repaired.
  LC_ALL=C awk -F'\t' -v OFS='\t' '$1 == "ecart" && $3 == "dans" && $4 == "auto" { print "corrige", $2, $5, $6 }' \
    "$TMP/findings" > "$TMP/fixed"
  FIXED=$(count_where 1 "$TMP/fixed")
fi
# The report always comes from a fresh reading: after a repair, it shows what is left.
scan 0

echo "== Inventaire =="
LC_ALL=C awk -v cover="$TMP/cover" "$AWK_INVENTORY" "$TMP/units"
LC_ALL=C awk -F'\t' '$1 == "index"' "$TMP/findings"
if [[ "$LIST_FICHES" -eq 1 ]]; then print_fiches; fi

echo "== $AGENTS_FILE (limites : $AGENTS_MAX_LINES lignes, $AGENTS_MAX_BYTES octets) =="
cat "$TMP/state"

if [[ "$MODE" == "--fix" ]]; then
  echo "== Corrections =="
  cat "$TMP/fixed"
fi

echo "== Ecarts =="
LC_ALL=C awk -F'\t' '$1 == "ecart"' "$TMP/findings" > "$TMP/ecarts"
cat "$TMP/ecarts"

TOTAL=$(count_where 1 "$TMP/ecarts")
INSIDE=$(count_where '$3 == "dans"' "$TMP/ecarts")
AUTO=$(count_where '$3 == "dans" && $4 == "auto"' "$TMP/ecarts")
SESSION=$(count_where '$3 == "dans" && $4 == "session"' "$TMP/ecarts")
OUTSIDE=$(count_where '$3 == "hors"' "$TMP/ecarts")
OUTSIDE_AUTO=$(count_where '$3 == "hors" && $4 == "auto"' "$TMP/ecarts")
echo "== Bilan =="
echo "ecarts=$TOTAL"
echo "dans_portee=$INSIDE"
echo "corrigeables=$AUTO"
echo "pour_la_session=$SESSION"
echo "hors_portee=$OUTSIDE"
echo "corriges=$FIXED"
if [[ "$OUTSIDE" -gt 0 ]]; then
  echo "($OUTSIDE ecart(s) dans des projets hors de la portee, dont $OUTSIDE_AUTO corrigeable(s) : signales, pas modifies. Ils se traitent depuis une session de ces projets, ou avec --all sur demande explicite)"
fi
if [[ "$MODE" == "--fix" && "$FIXED" -gt 0 ]]; then
  echo "== $FIXED correction(s) ecrite(s) dans le clone. Rien n'est commite ni pousse : un push les enverra =="
elif [[ "$MODE" == "--fix" ]]; then
  echo "== Rien a corriger dans la portee : rien n'a ete ecrit =="
else
  if [[ "$AUTO" -gt 0 ]]; then echo "($AUTO ecart(s) corrigeable(s) par --fix avec la meme portee)"; fi
  echo "== Verification seule : rien n'a ete ecrit =="
fi
if [[ "$INSIDE" -gt 0 ]]; then exit "$EXIT_FINDINGS"; fi
exit 0
