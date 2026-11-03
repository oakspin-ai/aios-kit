#!/bin/sh
# OakSpin AI-OS installer.
#
# The one line a customer pastes, from their welcome kit (it names the release, the industry pack
# and OakSpin's key), once OakSpin publishes its first release (none yet; see KIT_REPO below). This
# script runs before it can check any signature, so the line checks the script's own SHA-256 first
# (python3 tools/aios_release.py prints the line at each publish):
#
#   curl -fsSLo aios-install.sh https://raw.githubusercontent.com/<repo>/v0.1.1/install.sh \
#     && echo "<sha256>  aios-install.sh" | shasum -a 256 -c - && sh aios-install.sh "Acme Clinic" --industry medical --key SHA256:...
#
# It asks for the business name if none is given, and makes the short name from it. The short
# name can be given too: ... && sh aios-install.sh "Acme Clinic" acme-clinic --key SHA256:...
#
# A kit is this folder: install.sh, core/ (the brain every install gets) and industries/<pack>/.
# With --industry <pack>, the pack's starter/ files are copied on top of the core once, its engine/
# files go into .aios/industry/ (its checks run on every save), and the Rules section of its
# rules.md is pasted into the brain's rules.md under "Industry rules".
#
# Or, with a local copy of the kit (a design-partner setup session), which must carry its signed release
# list (releases.json, releases.json.sig) and release-key.pub:
#
#   AIOS_SOURCE=./aios sh aios/install.sh "Acme Clinic" --industry medical --key SHA256:...
#
# Before anything is written it checks three things: the key it downloads has the fingerprint the
# owner was given (so it is OakSpin's), the release list is signed by that key, and the engine
# matches the digest in that list. The key is then pinned in the brain, and every later upgrade is
# checked against it. Without --key nothing is installed, except with AIOS_DEV=1 (OakSpin's tests, and
# hand installs until the first release is published), which gives a brain marked "verify: none": it
# installs no engine update until the owner confirms OakSpin's key once.
#
# Creates a private company brain for the named business, wires the checks, makes the private
# folder and the documents drop folder outside the repository, and opens the kickoff interview.
# Safe to run twice: every step checks before it acts.
#
# Where the kit comes from, in order:
#   1. AIOS_SOURCE=/path/to/aios             a local copy (its .git, if any, is never kept)
#   2. AIOS_SHELF=<folder address>            releases.json, its signature, release-key.pub and the
#      AIOS_ARCHIVE=<folder address>          release archives (<tag>.tar.gz), for OakSpin's tests
#   3. the public kit repository (AIOS_REPO, default KIT_REPO below)
set -eu

# Where OakSpin publishes releases, as owner/name on GitHub (set up 2026-10-30; nothing published
# yet). Keep it equal to the repo= line in core/.aios/release.conf (a test checks).
KIT_REPO="oakspin-ai/aios-kit"

COMPANY=""; SLUG=""; KEY_FP=""; INDUSTRY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --key) [ $# -ge 2 ] || { echo "--key needs the fingerprint from your welcome kit (SHA256:...)."; exit 2; }; KEY_FP=$2; shift ;;
    --key=*) KEY_FP=${1#--key=} ;;
    --industry) [ $# -ge 2 ] || { echo "--industry needs a pack name, such as medical. Nothing was installed."; exit 2; }; INDUSTRY=$2; shift ;;
    --industry=*) INDUSTRY=${1#--industry=} ;;
    -*) echo "Unknown option $1. Nothing was installed."; exit 2 ;;
    *) if [ -z "$COMPANY" ]; then COMPANY=$1; elif [ -z "$SLUG" ]; then SLUG=$1; else echo "Too many names given. Nothing was installed."; exit 2; fi ;;
  esac
  shift
done
# Piped into sh, the script itself is on standard input, so the question is asked on the terminal.
TTY="${AIOS_TTY:-/dev/tty}"
if [ -z "$COMPANY" ] && (: < "$TTY") 2>/dev/null; then
  printf 'What is your business called? ' >&2
  IFS= read -r COMPANY < "$TTY" || COMPANY=""
fi
# Python names on Windows: the same block as core/.aios/tools/python.sh (see there; a test keeps them
# equal), repeated because the brain does not exist yet. A Mac is left alone: running its python3
# placeholder would open Apple's install window (see real_python below).
# >>> python names
aios_python_ok() { "$@" -c 'import sys; sys.exit(0 if sys.version_info >= (3,9) else 1)' >/dev/null 2>&1; }
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) export PYTHONUTF8=1 ;;
esac
if [ "$(uname -s 2>/dev/null)" != Darwin ] && ! aios_python_ok python3; then
  if aios_python_ok python; then
    python3() { python "$@"; }
  elif aios_python_ok py -3; then
    python3() { py -3 "$@"; }
  fi
fi
# <<< python names
# Python is really installed (on a Mac without Apple's command line tools, /usr/bin/python3 is a
# placeholder that opens an install window; the machine check below handles that, not this step).
real_python() {
  command -v python3 >/dev/null 2>&1 || return 1
  [ "$(uname -s 2>/dev/null)" != Darwin ] || [ "$(command -v python3)" != /usr/bin/python3 ] || xcode-select -p >/dev/null 2>&1
}
if [ -z "$SLUG" ] && [ -n "$COMPANY" ]; then
  # Accents become plain letters (Café -> cafe) where Python is already here; quotes and apostrophes
  # vanish (O'Brien's -> obriens) instead of splitting the name.
  SLUG=$(printf '%s' "$COMPANY" \
    | { real_python && python3 -c 'import sys, unicodedata; sys.stdout.write(unicodedata.normalize("NFKD", sys.stdin.buffer.read().decode("utf-8", "ignore")).encode("ascii", "ignore").decode())' 2>/dev/null || cat; } \
    | tr '[:upper:]' '[:lower:]' | sed "s/[\"']//g; s/&/and/g; s/[^a-z0-9][^a-z0-9]*/-/g; s/^-//; s/-\$//")
fi
if [ -z "$COMPANY" ] || [ -z "$SLUG" ]; then
  echo "usage: AIOS_SOURCE=<kit folder> sh <kit folder>/install.sh \"Company Name\" [--industry <pack>] --key SHA256:<fingerprint from your welcome kit>"; exit 2
fi
if [ -z "$KEY_FP" ] && [ "${AIOS_DEV:-0}" != 1 ]; then
  echo "This install needs OakSpin's key fingerprint, the --key SHA256:... part of the line in your welcome kit. Nothing was installed."
  exit 2
fi
case "$KEY_FP" in ""|SHA256:*) ;; *) echo "The key fingerprint should look like SHA256:... (it is in your welcome kit). Nothing was installed."; exit 2 ;; esac
case "$INDUSTRY" in -*|*[!a-z0-9-]*) echo "The industry pack name should be plain lowercase letters, digits and dashes, such as medical. Nothing was installed."; exit 2 ;; esac
# The short name becomes folder names: plain lowercase letters, digits and dashes only, never a path.
case "$SLUG" in -*|*[!a-z0-9-]*) echo "The short name '$SLUG' should be plain lowercase letters, digits and dashes, such as acme-clinic. Nothing was installed."; exit 2 ;; esac
# The name goes into files through sed, where & and | have special meanings.
COMPANY_SED=$(printf '%s' "$COMPANY" | sed 's/[&|\\]/\\&/g')
# In aios.yml the name sits inside double quotes, so its own quotes and backslashes are escaped.
COMPANY_YAML=$(printf '%s' "$COMPANY" | sed 's/[\\"]/\\&/g')
# AIOS_HERE=1: build the brain in the folder we are standing in (the owner chose it in Claude), with
# the private and documents folders beside it, so the same Claude session carries straight on.
if [ "${AIOS_HERE:-0}" = 1 ]; then
  HERE_DIR=$(pwd)
  HERE_PARENT=$(dirname "$HERE_DIR")
  if [ ! -d "$HERE_DIR/.aios" ] && [ -n "$(ls -A "$HERE_DIR" 2>/dev/null | grep -v -e '^\.DS_Store$' -e '^\.localized$')" ]; then
    echo "This folder already has files in it: $HERE_DIR"
    echo "The brain needs an empty folder of its own. Make a new empty folder, choose it in Claude, and say the sentence again."
    exit 2
  fi
  DEST="${AIOS_DEST:-$HERE_DIR}"
  PRIVATE="${AIOS_PRIVATE:-$HERE_PARENT/$SLUG-private}"
  DOCUMENTS="${AIOS_DOCUMENTS:-$HERE_PARENT/$SLUG-documents}"
else
  DEST="${AIOS_DEST:-$HOME/$SLUG-brain}"
  PRIVATE="${AIOS_PRIVATE:-$HOME/$SLUG-private}"
  DOCUMENTS="${AIOS_DOCUMENTS:-$HOME/$SLUG-documents}"
fi
# Every folder is made absolute now, against the folder this was run from: the install later works
# from inside the brain, where a relative private or documents folder would land inside it.
absolute() { case "$1" in /*) printf '%s' "$1" ;; "~"|"~/"*) printf '%s%s' "$HOME" "${1#\~}" ;; *) printf '%s/%s' "$(pwd)" "$1" ;; esac; }
DEST=$(absolute "$DEST"); PRIVATE=$(absolute "$PRIVATE"); DOCUMENTS=$(absolute "$DOCUMENTS")
TODAY=$(date +%Y-%m-%d)
PRIVATE_SED=$(printf '%s' "$PRIVATE" | sed 's/[&|\\]/\\&/g')
DOCUMENTS_SED=$(printf '%s' "$DOCUMENTS" | sed 's/[&|\\]/\\&/g')
# The documents folder is read (after screening); the private folder never is. Keep the brain, the
# private folder and the documents folder apart: none inside another, compared as real paths
# (relative paths, "..", and symlinks resolved), so nothing private is ever saved to the history.
case "$DOCUMENTS/" in
  "$PRIVATE/"|"$PRIVATE/"*|"$DEST/"|"$DEST/"*) echo "The documents folder must be its own folder, outside the brain and outside the private folder: $DOCUMENTS"; exit 2 ;;
esac
if python3 -c 'import sys' 2>/dev/null; then
  overlap=$(python3 - "$DEST" "$PRIVATE" "$DOCUMENTS" <<'PY'
import os, sys
names = ('brain', 'private folder', 'documents folder')
paths = [os.path.realpath(os.path.expanduser(p)) for p in sys.argv[1:4]]
inside = lambda a, b: a == b or a.startswith(b.rstrip(os.sep) + os.sep)
for i in range(3):
    for j in range(3):
        if i != j and inside(paths[i], paths[j]):
            print(f'The {names[i]} ({paths[i]}) is inside the {names[j]} ({paths[j]}).')
            raise SystemExit
PY
)
  if [ -n "$overlap" ]; then
    case "$overlap" in *"documents folder ("*) echo "The documents folder must be its own folder, outside the brain and outside the private folder: $DOCUMENTS" ;; esac
    echo "$overlap Each needs its own place. Nothing was installed."
    exit 2
  fi
fi
# A brain is only ever built in an empty folder (or one that is already this kind of brain).
occupied() { [ -d "$1" ] && [ -n "$(ls -A "$1" 2>/dev/null | grep -v -e '^\.DS_Store$' -e '^\.localized$')" ]; }
EXISTING=0; DEST_EXISTED=0
[ ! -d "$DEST" ] || DEST_EXISTED=1
if [ -d "$DEST/.aios" ]; then
  EXISTING=1
elif occupied "$DEST"; then
  echo "This folder already has files in it: $DEST"
  echo "The brain needs an empty folder of its own. Choose a new one (AIOS_DEST) and run this again. Nothing was installed."
  exit 2
elif [ -e "$DEST" ] && [ ! -d "$DEST" ]; then
  echo "$DEST is a file, not a folder. Nothing was installed."
  exit 2
fi
if [ "$EXISTING" = 1 ]; then
  have=$(sed -n 's/^industry:[[:space:]]*//p' "$DEST/aios.yml" 2>/dev/null | head -1 | sed 's/#.*//; s/[[:space:]]//g')
  [ -n "$have" ] || have=none
  if [ -n "$INDUSTRY" ] && [ "$INDUSTRY" != "$have" ]; then
    echo "A brain already exists at $DEST, installed with the '$have' industry pack, not '$INDUSTRY'. Nothing was changed."
    exit 2
  fi
fi

say() { printf '\n== %s\n' "$*"; }
need() { command -v "$1" >/dev/null 2>&1; }

say "Checking the machine"
OS=$(uname -s 2>/dev/null || echo unknown)
missing=""
# Git and Python: on a Mac both arrive with Apple's command line tools, one prompt.
if ! need git; then
  if [ "$OS" = Darwin ]; then
    echo "Git is not installed yet. Apple will show a window asking to install its command line tools."
    echo "Click Install, wait for it to finish (a few minutes), then paste the same line again."
    xcode-select --install >/dev/null 2>&1 || true
    exit 0
  fi
  missing="$missing\n- Git: install from https://git-scm.com then paste the same line again."
fi
if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3,9) else 1)' 2>/dev/null; then
  if [ "$OS" = Darwin ]; then
    echo "Python is not ready yet. Apple will show a window asking to install its command line tools."
    echo "Click Install, wait for it to finish, then paste the same line again."
    xcode-select --install >/dev/null 2>&1 || true
    exit 0
  fi
  case "$OS" in
    MINGW*|MSYS*|CYGWIN*) missing="$missing\n- Python 3.9 or newer: install from https://python.org, tick \"Add python.exe to PATH\" on the first screen, then close this window, open a new one and paste the same line again." ;;
    *) missing="$missing\n- Python 3.9 or newer: install from https://python.org then paste the same line again." ;;
  esac
fi
if [ -n "$missing" ]; then
  printf 'Before the brain can be built:%b\n' "$missing"
  exit 1
fi
if [ -n "$KEY_FP" ] && ! need openssl; then
  echo "openssl is missing, so OakSpin's signature cannot be checked. It ships with macOS; on Linux install it, then paste the same line again."
  exit 1
fi
# Which AI app the owner uses: AIOS_HARNESS=codex|claude overrides; otherwise Codex only when it is
# installed and Claude is not. A Codex-only owner is never sent to install Claude.
if [ -n "${AIOS_HARNESS:-}" ]; then HARNESS=$AIOS_HARNESS
elif need claude; then HARNESS=claude
elif need codex || [ -n "${CODEX_HOME:-}${CODEX_SANDBOX:-}" ]; then HARNESS=codex
else HARNESS=claude; fi
# Claude Code: install it if we can, otherwise say exactly where to get it.
# AIOS_INSTALL_CLAUDE=0 skips this (the kit's tests use it so they never download anything).
if [ "$HARNESS" = claude ] && ! need claude && [ "${AIOS_INSTALL_CLAUDE:-1}" = 1 ]; then
  if need npm; then
    echo "Installing Claude Code (one minute)."
    npm install -g @anthropic-ai/claude-code >/dev/null 2>&1 && echo "Claude Code installed." || echo "Could not install Claude Code automatically. Get it at https://claude.ai/code and paste the same line again when it is in."
  elif [ "$OS" = Darwin ] && need brew; then
    echo "Installing Claude Code (one minute)."
    brew install --quiet node >/dev/null 2>&1 && npm install -g @anthropic-ai/claude-code >/dev/null 2>&1 && echo "Claude Code installed." || echo "Could not install Claude Code automatically. Get it at https://claude.ai/code and paste the same line again when it is in."
  elif need curl; then
    echo "Installing Claude Code with Anthropic's installer (one minute)."
    curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1 && echo "Claude Code installed." || echo "Could not install Claude Code automatically. Get it at https://claude.ai/code and paste the same line again when it is in."
  else
    echo "Claude Code is not installed yet. The brain will still be built. Get Claude Code at https://claude.ai/code, then open the brain folder and type /start."
  fi
  # Anthropic's installer puts it in ~/.local/bin, which this shell may not search yet.
  need claude || PATH="$HOME/.local/bin:$PATH"
fi
# GitHub is optional at install: it is the online backup and the phone link, connected during the session.
need gh && GH=1 || GH=0

# The same digest OakSpin's release list names: every file sorted by path, "sha256  path" lines,
# then the sha256 of those lines (.git, caches, the list and its signature left out). This copy
# lives here because the kit's own copy (.aios/tools/kitdigest.py) has not been verified yet.
kit_digest() {
  python3 - "$1" <<'PY'
import hashlib, sys
from pathlib import Path
root = Path(sys.argv[1]); lines = []
for p in sorted(root.rglob('*'), key=lambda q: q.relative_to(root).as_posix()):
    rel = p.relative_to(root)
    if any(part in ('.git', '__pycache__') for part in rel.parts) or not p.is_file():
        continue
    if p.name in ('.DS_Store', 'releases.json', 'releases.json.sig') or p.name.endswith('.pyc'):
        continue
    h = hashlib.sha256()
    with p.open('rb') as f:
        for chunk in iter(lambda: f.read(1 << 16), b''):
            h.update(chunk)
    lines.append(f'{h.hexdigest()}  {rel.as_posix()}\n')
print(hashlib.sha256(''.join(lines).encode()).hexdigest())
PY
}
key_fingerprint() {
  python3 - "$1" <<'PY'
import base64, hashlib, sys
body = ''.join(l.strip() for l in open(sys.argv[1]).read().splitlines() if not l.startswith('-----'))
print('SHA256:' + hashlib.sha256(base64.b64decode(body)).hexdigest()[:32])
PY
}
fetch() {  # fetch <address> <file>
  case "$1" in
    file://*) cp "${1#file://}" "$2" 2>/dev/null ;;
    http://*|https://*) curl -fsSL --max-time 20 "$1" -o "$2" 2>/dev/null ;;
    *) cp "$1" "$2" 2>/dev/null ;;
  esac
}
# verify_kit <kit folder> <folder holding releases.json, releases.json.sig and release-key.pub>
# Fails, with nothing written, unless the key, the signature and the digest all check.
verify_kit() {
  kit=$1; shelf=$2
  [ -f "$shelf/releases.json" ] || { echo "No release list (releases.json) came with the kit, so it cannot be checked. Nothing was installed. Tell OakSpin."; return 1; }
  set -- $(python3 -c 'import json,sys
try:
    m=json.load(open(sys.argv[1])); v=str(m["latest"]); print(v, m.get("tag","v"+v), m["sha256"])
except Exception: print("bad bad bad")' "$shelf/releases.json")
  [ "$1" != bad ] || { echo "OakSpin's release list could not be read. Nothing was installed. Tell OakSpin."; return 1; }
  if [ -n "$KEY_FP" ]; then
    [ -f "$shelf/release-key.pub" ] || { echo "OakSpin's key did not come with the kit, so the release cannot be checked. Nothing was installed. Tell OakSpin."; return 1; }
    got=$(key_fingerprint "$shelf/release-key.pub" 2>/dev/null || echo none)
    [ "$got" = "$KEY_FP" ] || { echo "The key that came with the kit ($got) is not the one in your welcome kit ($KEY_FP). Nothing was installed. Tell OakSpin before trying again."; return 1; }
    openssl dgst -sha256 -verify "$shelf/release-key.pub" -signature "$shelf/releases.json.sig" "$shelf/releases.json" >/dev/null 2>&1 \
      || { echo "OakSpin's release list is not signed by OakSpin's key. Nothing was installed. Tell OakSpin."; return 1; }
  fi
  [ "$(kit_digest "$kit")" = "$3" ] || { echo "The engine does not match OakSpin's release list, so it was not installed. Paste the same line again; if it happens twice, tell OakSpin."; return 1; }
  [ "$(tr -d '[:space:]' < "$kit/core/.aios/VERSION")" = "$1" ] || { echo "The engine says it is $(cat "$kit/core/.aios/VERSION") but the release list says $1. Nothing was installed. Tell OakSpin."; return 1; }
  KIT_TAG=$2
  return 0
}

# place_kit <kit folder>: the core, then the industry pack on top. Checks before it writes anything;
# every step is checked (errexit does not apply inside a function called with ||), and a failure
# removes what was written so a rerun starts clean.
unplace() {
  if [ "$DEST_EXISTED" = 0 ]; then rm -rf "$DEST"
  else find "$DEST" -mindepth 1 -maxdepth 1 ! -name .DS_Store ! -name .localized -exec rm -rf {} + 2>/dev/null; fi
  echo "Copying the kit failed, so nothing was installed."
  return 1
}
place_kit() {
  [ -f "$1/core/.aios/VERSION" ] || { echo "That is not an OakSpin AI-OS kit (no core/.aios/VERSION). Nothing was installed."; return 1; }
  if [ -n "$INDUSTRY" ] && [ ! -f "$1/industries/$INDUSTRY/rules.md" ]; then
    echo "The kit has no '$INDUSTRY' industry pack. Nothing was installed."
    return 1
  fi
  mkdir -p "$DEST" && cp -R "$1/core"/. "$DEST"/ || { unplace; return 1; }
  rm -rf "$DEST/.git"
  if [ -n "$INDUSTRY" ]; then
    if [ -d "$1/industries/$INDUSTRY/starter" ]; then cp -R "$1/industries/$INDUSTRY/starter"/. "$DEST"/ || { unplace; return 1; }; fi
    if [ -d "$1/industries/$INDUSTRY/engine" ]; then
      mkdir -p "$DEST/.aios/industry" && cp -R "$1/industries/$INDUSTRY/engine"/. "$DEST/.aios/industry"/ || { unplace; return 1; }
    fi
  fi
  # Python caches are never part of a release and are not covered by its digest: none may run.
  find "$DEST" \( -name __pycache__ -type d -prune -exec rm -rf {} + \) -o \( -name '*.pyc' -type f -exec rm -f {} + \) 2>/dev/null
  if find "$DEST" -name '*.pyc' -o -name __pycache__ | grep -q .; then unplace; return 1; fi
  [ -n "$INDUSTRY" ] || return 0
  # The pack's "## Rules" section goes under "## Industry rules" in the brain's rules.md.
  python3 - "$1/industries/$INDUSTRY/rules.md" "$DEST/rules.md" "$INDUSTRY" <<'PY'
import re, sys
from pathlib import Path
pack, brain, name = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
found = re.search(r'^## Rules\n(.*?)(?=^## |\Z)', pack.read_text(), re.S | re.M)
if not found or not found.group(1).strip():
    sys.exit(f'The {name} pack has no Rules section in its rules.md. Nothing more was installed.')
text = brain.read_text()
heading = re.search(r'^## Industry rules\n.*?(?=^## |\Z)', text, re.S | re.M)
if not heading:
    sys.exit("The brain's rules.md has no Industry rules section. Nothing more was installed.")
block = heading.group(0).rstrip('\n') + f'\n\nFrom the {name} pack:\n\n' + found.group(1).strip() + '\n\n'
brain.write_text(text[:heading.start()] + block + text[heading.end():])
PY
  [ $? -eq 0 ] || { unplace; return 1; }
}

say "Creating the brain at $DEST"
if [ "$EXISTING" = 1 ]; then
  echo "Already exists; keeping it. Nothing in it was checked or replaced now."
elif [ -n "${AIOS_SOURCE:-}" ]; then
  if [ -n "$KEY_FP" ] || [ -f "$AIOS_SOURCE/releases.json" ]; then
    verify_kit "$AIOS_SOURCE" "$AIOS_SOURCE" || exit 1
  fi
  # A copy of the kit may be a clone of OakSpin's public repository. Its history and its "origin"
  # must never become this brain's: only core/ and the pack are copied, never the kit's .git.
  place_kit "$AIOS_SOURCE" || exit 1
  [ -z "$KEY_FP" ] || { mkdir -p "$DEST/.oakspin" && cp "$AIOS_SOURCE/release-key.pub" "$DEST/.oakspin/release-key.pub"; }
  (cd "$DEST" && git init -q -b main)
else
  need curl || { echo "curl is missing. Install it (it ships with macOS) and run this again."; exit 1; }
  need tar || { echo "tar is missing. Install it and run this again."; exit 1; }
  REPO="${AIOS_REPO:-$KIT_REPO}"
  if [ -z "$REPO" ] && [ -z "${AIOS_SHELF:-}" ]; then
    echo "OakSpin has not published online releases yet. Install from a local copy of the kit:"
    echo "  AIOS_SOURCE=<kit folder> sh <kit folder>/install.sh \"$COMPANY\" --industry <pack>"
    echo "Nothing was installed."
    exit 2
  fi
  SHELF="${AIOS_SHELF:-https://raw.githubusercontent.com/$REPO/main}"
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  echo "Reading OakSpin's release list"
  if ! fetch "$SHELF/releases.json" "$TMP/releases.json"; then
    code=$(curl -s -o /dev/null -w '%{http_code}' "$SHELF/releases.json" 2>/dev/null || echo 000)
    case "$code" in
      404) echo "OakSpin's release list is not published at $SHELF yet. That is on OakSpin's side, not yours: nothing on this computer is wrong. Tell OakSpin." ;;
      000) echo "Could not reach GitHub. Check the internet connection and paste the same line again." ;;
      *)   echo "GitHub answered $code while fetching the release list. Paste the same line again in a minute; if it keeps happening, tell OakSpin." ;;
    esac
    exit 1
  fi
  fetch "$SHELF/releases.json.sig" "$TMP/releases.json.sig" || true
  TAG=$(python3 -c 'import json,sys; m=json.load(open(sys.argv[1])); print(m.get("tag","v"+str(m["latest"])))' "$TMP/releases.json" 2>/dev/null || echo "")
  [ -n "$TAG" ] || { echo "OakSpin's release list could not be read. Nothing was installed. Tell OakSpin."; exit 1; }
  if [ -n "$KEY_FP" ]; then
    if [ -n "${AIOS_SHELF:-}" ]; then KEY_URL="$SHELF/release-key.pub"; else KEY_URL="https://raw.githubusercontent.com/$REPO/$TAG/release-key.pub"; fi
    fetch "$KEY_URL" "$TMP/release-key.pub" || { echo "Could not fetch OakSpin's key ($KEY_URL). Paste the same line again; if it keeps happening, tell OakSpin."; exit 1; }
  fi
  ARCHIVE="${AIOS_ARCHIVE:-https://github.com/$REPO/archive/refs/tags}/$TAG.tar.gz"
  echo "Fetching engine $TAG"
  fetch "$ARCHIVE" "$TMP/kit.tar.gz" || { echo "Could not download the engine ($ARCHIVE). Paste the same line again in a minute; if it keeps happening, tell OakSpin."; exit 1; }
  mkdir -p "$TMP/kit"
  if ! tar -xzf "$TMP/kit.tar.gz" -C "$TMP/kit" 2>/dev/null; then
    echo "The kit download was damaged, so nothing was installed. Paste the same line again; if it happens twice, tell OakSpin."
    exit 1
  fi
  SRC=$(find "$TMP/kit" -maxdepth 4 -path '*/core/.aios' -type d | head -1)
  [ -n "$SRC" ] || { echo "The downloaded kit is not an OakSpin AI-OS kit (no core/.aios folder)."; exit 1; }
  SRC=$(dirname "$(dirname "$SRC")")
  verify_kit "$SRC" "$TMP" || exit 1
  place_kit "$SRC" || exit 1
  [ -z "$KEY_FP" ] || { mkdir -p "$DEST/.oakspin" && cp "$TMP/release-key.pub" "$DEST/.oakspin/release-key.pub"; }
  (cd "$DEST" && git init -q -b main)
  rm -rf "$TMP"
fi
cd "$DEST"

say "Naming it"
ENGINE=$(cat .aios/VERSION)
for f in AGENTS.md README.md CLAUDE.md company/identity.md company/access.md guide.md; do
  [ -f "$f" ] && sed -i.bak "s|%%COMPANY%%|$COMPANY_SED|g; s|%%ENGINE_VERSION%%|$ENGINE|g; s|%%PRIVATE%%|$PRIVATE_SED|g; s|%%DOCUMENTS%%|$DOCUMENTS_SED|g" "$f" && rm -f "$f.bak"
done
# The interview is JSON: names go in as JSON strings, so quotes and backslashes in them stay valid.
python3 .aios/tools/names.py .aios/interview.json "$COMPANY" "$PRIVATE" "$DOCUMENTS" || { echo "Could not write the names into the interview. Nothing more was installed."; exit 1; }
if grep -q '%%COMPANY%%' aios.yml 2>/dev/null || [ ! -f aios.yml ]; then
  if [ -n "$KEY_FP" ]; then VERIFY=signed; else VERIFY=none; fi
  cat > aios.yml <<EOF
company: "$COMPANY_YAML"
slug: $SLUG
engine: $ENGINE
harness: $([ "$HARNESS" = codex ] && echo codex || echo claude-code)
installed: $TODAY
private_folder: $PRIVATE
documents_folder: $DOCUMENTS
industry: ${INDUSTRY:-none}
upgrade: auto
verify: $VERIFY
EOF
  [ -z "$KEY_FP" ] || printf 'release_key: %s\n' "$KEY_FP" >> aios.yml
fi
grep -q '^documents_folder:' aios.yml || printf 'documents_folder: %s\n' "$DOCUMENTS" >> aios.yml

say "Making the private folder outside the brain: $PRIVATE"
mkdir -p "$PRIVATE"
[ -f "$PRIVATE/README.md" ] || cat > "$PRIVATE/README.md" <<EOF
# $COMPANY private folder

This folder is outside the company brain on purpose. Bank and card details, passwords, contracts you
have not chosen to share, personal matters, and payroll if you want it kept out: they live here. The brain never opens this folder. Nothing here is
backed up by the brain; back it up the way you back up any private document.
EOF

say "Making the documents folder: $DOCUMENTS"
mkdir -p "$DOCUMENTS"
[ -f "$DOCUMENTS/ABOUT THIS FOLDER.md" ] || cat > "$DOCUMENTS/ABOUT THIS FOLDER.md" <<EOF
# Documents for the $COMPANY brain

Drop copies of anything you want the brain to know about in here: price lists, brochures,
proposals and quotes, how-we-do-it notes, meeting notes, a ChatGPT or Claude export. PDFs and
Word files and spreadsheets are fine, and so are your business numbers: sales, costs, margins,
invoices. Keep bank statements and anything personal out; those go in $PRIVATE.

Check every file before you drop it in: PDFs, Word files, spreadsheets, notes. Open each one and
make sure it has none of these:

- bank or card numbers, account or routing numbers
- passwords or logins
- tax, social security or ID numbers
- staff home addresses, personal phone numbers or health details

If a file has any of them, delete that part or black it out and save a new copy, or leave it out.
The brain catches some of this in text and Word files, but not all of it, and it cannot look
inside most PDFs at all. You are the main check.

The brain never opens this folder on its own. When you say "read my new documents", it checks each
file for passwords and card or bank numbers first, reads only what passes, and tells you what it
left behind. Files it cannot check, like most PDFs, it names and asks before reading; it reads
those here and never copies them into the brain.
EOF

say "Wiring the checks"
chmod +x scripts/setup.sh .aios/hooks/pre-commit .aios/tools/check.py .aios/tools/gather.py .aios/tools/frontpage.py
chmod +x .aios/tools/*.py .aios/tools/*.sh .aios/hooks/*.sh 2>/dev/null || true
./scripts/setup.sh

say "First save"
git add -A
git -c user.name="${GIT_AUTHOR_NAME:-$COMPANY}" -c user.email="${GIT_AUTHOR_EMAIL:-owner@$SLUG.local}" \
  commit -q -m "Install OakSpin AI-OS $ENGINE for $COMPANY" >/dev/null 2>&1 \
  || { git diff --cached --quiet && echo "Nothing new to save."; } \
  || { echo "The first save could not be recorded, so the brain is not saved yet. Run this again, or tell OakSpin."; exit 1; }

if ! git remote get-url origin >/dev/null 2>&1; then
  if [ "$GH" = 1 ] && gh auth status >/dev/null 2>&1; then
    say "Creating the private GitHub copy"
    if gh_out=$(gh repo create "$SLUG-brain" --private --source . --push 2>&1 >/dev/null); then
      echo "Pushed to GitHub (private)."
      echo "Check two-factor login is on for this GitHub account before the session ends."
    else
      case "$gh_out" in
        *"already exists"*)
          echo "Could not create the GitHub copy: this GitHub account already has a project called $SLUG-brain, maybe from an earlier try. Nothing was changed on it. The brain works on this computer; in your setup session we check that project and either connect to it or pick a new name." ;;
        *)
          echo "Could not create the GitHub copy. The brain works locally; connect GitHub later with: gh repo create $SLUG-brain --private --source . --push" ;;
      esac
    fi
  else
    say "GitHub not connected yet"
    echo "The brain is built and works on this computer. GitHub is the online backup and what links your phone."
    echo "We connect it during your setup session. If you want to do it yourself: install GitHub's tool (https://cli.github.com), run 'gh auth login', then in the brain folder run: gh repo create $SLUG-brain --private --source . --push"
  fi
fi

if [ "$EXISTING" = 0 ]; then
say "Install receipt"
mkdir -p memory
printf -- '- %s installed OakSpin AI-OS %s on this machine (harness: %s, private folder: %s, engine verified: %s)\n' \
  "$TODAY" "$ENGINE" "$(if [ "$HARNESS" = codex ]; then echo codex; elif need claude; then echo claude-code; else echo none-yet; fi)" "$PRIVATE" "$([ -n "$KEY_FP" ] && echo "yes, key $KEY_FP" || echo "no, unsigned test install")" >> memory/install-receipts.md
git add memory/install-receipts.md && git commit -q -m "Install receipt $TODAY" 2>/dev/null || true
fi

say "Done."
echo "Your brain: $DEST"
echo "Private folder (never read by the brain): $PRIVATE"
echo "Documents folder (put the files you want the brain to know here): $DOCUMENTS"
echo "Talk, do not type: click the microphone in your AI app's message box and speak your answers."
if [ "$HARNESS" = codex ]; then
  # Codex has no session hooks: say so, and start the interview in Codex when it is installed.
  echo "Using Codex: it does not save by itself. Before you close it, say \"save\"."
  if [ -n "${CODEX_HOME:-}${CODEX_SANDBOX:-}" ] || [ "${AIOS_NO_LAUNCH:-0}" = 1 ]; then
    echo "NEXT STEP: in Codex, open the folder $DEST and say hello (or type \$start). The interview begins there. For Codex: read AGENTS.md in that folder, then run .aios/playbooks/start.md, starting with the greeting."
  elif need codex; then
    echo "Opening the interview."
    cd "$DEST" && exec codex "Read AGENTS.md, then run .aios/playbooks/start.md now, starting with the greeting."
  else
    echo "Install Codex, open $DEST, and say hello (or type \$start)."
  fi
elif { [ -n "${CLAUDECODE:-}" ] || [ "${AIOS_NO_LAUNCH:-0}" = 1 ]; } && [ -n "${HERE_DIR:-}" ] && [ "$DEST" = "$HERE_DIR" ]; then
  # Claude ran this inside the folder that is now the brain: carry straight on in the same session.
  echo "YOUR BRAIN IS READY, in this folder: $DEST"
  echo "NEXT, FOR CLAUDE: read AGENTS.md in this folder, then run .aios/playbooks/start.md now, starting with the greeting. The owner does not need to open anything."
elif [ -n "${CLAUDECODE:-}" ] || [ "${AIOS_NO_LAUNCH:-0}" = 1 ]; then
  # Claude itself ran this (desktop app or CLI). Do not start a second Claude inside it.
  echo "NEXT STEP FOR THE OWNER: in Claude, open the folder $DEST and say hello (or type /start). The interview begins there."
elif need claude; then
  echo "Opening the interview."
  exec claude "/start"
else
  echo "Install Claude Code, open $DEST, and type /start."
fi
