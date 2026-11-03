#!/bin/sh
# OakSpin AI-OS engine upgrade. Runs from the brain's root.
#
#   sh .aios/tools/upgrade.sh --check    say whether a newer engine exists and what changed. Changes nothing.
#   sh .aios/tools/upgrade.sh --auto     the session-start hook. Quiet when current
#                                        or offline. Installs only when aios.yml says "upgrade: auto"; with
#                                        "upgrade: ask" (or no setting at all) it only reports.
#   sh .aios/tools/upgrade.sh --yes      install now. The /upgrade playbook runs this after the owner's yes.
#                                        The first signed install also needs --pin-key SHA256:... , the
#                                        fingerprint the owner confirmed.
#
# Every install is verified before anything is written: OakSpin's release list (releases.json) must carry
# a signature that checks against the key pinned in this brain, the version must be newer than this one,
# and the downloaded kit must match the digest in that list. A brain with no pinned key (verify: none,
# an unsigned test install) never installs anything until the owner confirms a key with --pin-key. If anything fails after the apply
# begins, every file in the brain is put back exactly as it was.
#
# What it replaces: the .aios folder (with the industry pack's engine files in .aios/industry), the
# command adapters that came from the kit, the hook settings, and the fenced engine block inside AGENTS.md. What it never touches: company/, clients/, memory/,
# skills/, inbox/, the owner's own commands, the pinned key in .oakspin/, or anything outside that block.
#
# Where the engine comes from: AIOS_SOURCE (a local kit folder carrying its own signed releases.json)
# > AIOS_SHELF (a folder address holding releases.json, releases.json.sig and the release archives)
# > github.com/<repo> (the release list on main, the kit from its tag), where <repo> is AIOS_REPO or the
# repo= line in .aios/release.conf. While that is empty (releases not set up) nothing is fetched online.
# A kit is the folder holding install.sh, core/ (the brain every install gets) and industries/.
set -eu
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
[ -f .aios/VERSION ] || { echo "This folder is not an OakSpin AI-OS brain (no .aios/VERSION)."; exit 1; }
. .aios/tools/kit_home.sh
[ ! -f .aios/tools/python.sh ] || . .aios/tools/python.sh

usage() {
  echo "usage: sh .aios/tools/upgrade.sh --check | --auto | --yes [--pin-key SHA256:...]"
  echo "Nothing was changed."
}
ACTION=""; PIN_KEY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check|--auto|--yes) [ -z "$ACTION" ] || { usage; exit 2; }; ACTION=${1#--} ;;
    --pin-key) [ $# -ge 2 ] || { usage; exit 2; }; PIN_KEY=$2; shift ;;
    *) usage; exit 2 ;;
  esac
  shift
done
[ -n "$ACTION" ] || ACTION=check

CURRENT=$(tr -d '[:space:]' < .aios/VERSION)
HOME_REPO=$(aios_kit_repo)
SHELF="${AIOS_SHELF:-https://raw.githubusercontent.com/$HOME_REPO/main}"
PINNED=.oakspin/release-key.pub
RECEIPT=memory/receipts/upgrade-check.json
TMP=$(mktemp -d)
APPLYING=0
SNAP_HEAD=""
LOCK=""
SIGNED_BY=""   # an unpinned brain: the fingerprint of the key the list really is signed by, unconfirmed

# aios.yml values, forgiving of quotes, inline comments, stray spaces, Windows line endings and case.
yml_value() { sed -n "s/^$1:[[:space:]]*//p" aios.yml 2>/dev/null | head -1 | sed 's/#.*//; s/["'"'"' 	]//g' | tr -d '\r' | tr '[:upper:]' '[:lower:]'; }
PREF=$(yml_value upgrade); case "$PREF" in auto|ask) ;; *) PREF=ask ;; esac          # unknown means ask
VERIFY=$(yml_value verify); case "$VERIFY" in signed) ;; *) VERIFY=legacy ;; esac  # none or no setting: no key pinned yet
INDUSTRY=$(yml_value industry); case "$INDUSTRY" in ""|none|%%industry%%) INDUSTRY="" ;; esac

receipt() { mkdir -p memory/receipts; printf '{"checked_at":"%s","installed":"%s","available":"%s","result":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$CURRENT" "$1" "$2" > "$RECEIPT"; }
quiet_or() { [ "$ACTION" = auto ] && exit 0; echo "$1"; exit 1; }
newer() { python3 -c 'import sys; a=[int(x) for x in sys.argv[1].split(".")]; b=[int(x) for x in sys.argv[2].split(".")]; sys.exit(0 if b > a else 1)' "$1" "$2"; }
changelog() { awk -v v="$1" '$0 ~ "^## "v"$" {f=1; next} /^## / {f=0} f' "$2" 2>/dev/null | sed 's/^/  /'; }

# Before the apply: every file in the brain is listed, and every file Git does not track (the owner's
# untracked and ignored files) is copied aside. A failure puts tracked files back from the snapshot
# commit, removes every file that was not there before, and copies the set-aside files back.
snapshot() {
  python3 - "$TMP/snapshot" "$TMP/keep" <<'PY'
import os, shutil, subprocess, sys
listing, keep = sys.argv[1], sys.argv[2]
tracked = set(subprocess.run(['git', 'ls-files', '-z'], capture_output=True, check=True).stdout.decode('utf-8', 'surrogateescape').split('\0'))
paths = []
for top, dirs, files in os.walk('.'):
    dirs[:] = [d for d in dirs if not (top == '.' and d == '.git')]
    for d in dirs:
        if not os.path.islink(os.path.join(top, d)):
            paths.append(os.path.relpath(os.path.join(top, d), '.') + '/')
    for name in files + [d for d in dirs if os.path.islink(os.path.join(top, d))]:
        rel = os.path.relpath(os.path.join(top, name), '.')
        paths.append(rel)
        if rel not in tracked:
            dest = os.path.join(keep, rel)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            shutil.copy2(rel, dest, follow_symlinks=False)
with open(listing, 'wb') as f:
    f.write('\0'.join(paths).encode('utf-8', 'surrogateescape'))
PY
}
rollback() {
  git reset -q --hard "$SNAP_HEAD" 2>/dev/null || return 1
  python3 - "$TMP/snapshot" "$TMP/keep" <<'PY'
import os, shutil, sys
listing, keep = sys.argv[1], sys.argv[2]
before = set(open(listing, 'rb').read().decode('utf-8', 'surrogateescape').split('\0'))
for top, dirs, files in os.walk('.', topdown=False):
    if top == '.git' or top.startswith('./.git' + os.sep) or top == './.git':
        continue
    for name in files:
        rel = os.path.relpath(os.path.join(top, name), '.')
        if rel not in before:
            os.remove(rel)
    for name in dirs:
        rel = os.path.relpath(os.path.join(top, name), '.')
        if rel == '.git':
            continue
        if os.path.islink(rel):
            if rel not in before:
                os.remove(rel)
        elif rel + '/' not in before and not os.listdir(rel):
            os.rmdir(rel)
for top, dirs, files in os.walk(keep):
    for name in files:
        src = os.path.join(top, name)
        rel = os.path.relpath(src, keep)
        os.makedirs(os.path.dirname(rel) or '.', exist_ok=True)
        if os.path.lexists(rel):
            os.remove(rel)
        shutil.copy2(src, rel, follow_symlinks=False)
PY
}
finish() {
  rc=$?
  if [ "$APPLYING" = 1 ] && [ "$rc" -ne 0 ]; then
    if rollback; then
      receipt "${NEW:-unknown}" "failed-rolled-back"
      echo "The upgrade to ${NEW:-the new engine} failed partway, so every file was put back as it was. Nothing was saved. Tell OakSpin."
    else
      receipt "${NEW:-unknown}" "failed-not-restored"
      echo "The upgrade to ${NEW:-the new engine} failed partway and the files could not all be put back. Do not save. Tell OakSpin now."
    fi
  fi
  [ -z "$LOCK" ] || rm -rf "$LOCK"
  rm -rf "$TMP"
}
trap finish EXIT

fetch() {  # fetch <url> <file>: curl, or a local path
  case "$1" in
    file://*) cp "${1#file://}" "$2" 2>/dev/null ;;
    http://*|https://*) curl -fsSL --max-time 12 "$1" -o "$2" 2>/dev/null ;;
    *) cp "$1" "$2" 2>/dev/null ;;
  esac
}

# 1. The release list, and where the engine and the key come from.
if [ -z "${AIOS_SOURCE:-}" ] && [ -z "${AIOS_SHELF:-}" ] && [ -z "$HOME_REPO" ]; then
  receipt unknown not-set-up
  quiet_or "OakSpin has not set up online engine releases yet, so there is nothing to check. Nothing was changed."
fi
if [ -n "$INDUSTRY" ] && ! printf '%s' "$INDUSTRY" | grep -Eq '^[a-z0-9][a-z0-9-]*$'; then
  receipt unknown bad-industry
  quiet_or "aios.yml names the industry pack '$INDUSTRY', which is not a pack name. Nothing was changed. Tell OakSpin."
fi
if [ -n "${AIOS_SOURCE:-}" ]; then
  cp "$AIOS_SOURCE/releases.json" "$TMP/releases.json" 2>/dev/null || { receipt unknown unsigned-source; quiet_or "The local kit at $AIOS_SOURCE carries no release list (releases.json), so it cannot be checked. Nothing was changed."; }
  cp "$AIOS_SOURCE/releases.json.sig" "$TMP/releases.json.sig" 2>/dev/null || true
  KEY_FROM="$AIOS_SOURCE/release-key.pub"
else
  if ! fetch "$SHELF/releases.json" "$TMP/releases.json"; then
    # A shelf that answers "not found" was reached but holds no release list: nothing is published
    # yet, or it was taken down. A brain that has taken signed releases warns, even when quiet.
    case "$SHELF" in http://*|https://*) code=$(curl -s -o /dev/null --max-time 12 -w '%{http_code}' "$SHELF/releases.json" 2>/dev/null || true) ;; *) code="" ;; esac
    if [ "$code" = 404 ] && [ "$VERIFY" = signed ]; then
      receipt unknown release-list-missing
      echo "OakSpin's release list is missing from its shelf ($SHELF), though this brain has taken signed releases from it. Nothing was changed. Tell OakSpin."
      [ "$ACTION" = auto ] && exit 0
      exit 1
    fi
    if [ "$code" = 404 ]; then
      receipt unknown no-release-list
      quiet_or "OakSpin's shelf has no release list: nothing is published yet, or it was taken down. Nothing was changed."
    fi
    receipt unknown offline
    quiet_or "Could not reach OakSpin's shelf ($SHELF). Try again later; nothing was changed."
  fi
  fetch "$SHELF/releases.json.sig" "$TMP/releases.json.sig" || true
fi
set -- $(python3 -c 'import json,sys
try:
    m=json.load(open(sys.argv[1])); v=str(m["latest"]); print(v, m.get("tag","v"+v), m["sha256"])
except Exception: print("bad bad bad")' "$TMP/releases.json")
NEW=$1; TAG=$2; DIGEST=$3
if [ "$NEW" = bad ] || ! printf '%s' "$NEW" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  receipt unknown damaged-release-list
  quiet_or "OakSpin's release list could not be read, so nothing was installed. Try again later; if it keeps happening, tell OakSpin."
fi
if [ -z "${AIOS_SOURCE:-}" ]; then
  if [ -n "${AIOS_SHELF:-}" ]; then KEY_FROM="$SHELF/release-key.pub"; else KEY_FROM="https://raw.githubusercontent.com/$HOME_REPO/$TAG/release-key.pub"; fi
fi

# 2. Is it OakSpin's? The signature must check against the pinned key (or, the first time, against
#    the key whose fingerprint the owner just confirmed with --pin-key).
KEY=""
case "$VERIFY" in
  signed) KEY=$PINNED; [ -f "$KEY" ] || { receipt "$NEW" key-missing; quiet_or "This brain is set to install only signed engines, but OakSpin's key is missing from .oakspin/. Tell OakSpin."; } ;;
  legacy)
    if [ -n "$PIN_KEY" ] && [ "$ACTION" = yes ]; then
      fetch "$KEY_FROM" "$TMP/release-key.pub" || { receipt "$NEW" key-unreachable; echo "Could not fetch OakSpin's key ($KEY_FROM). Nothing was changed."; exit 1; }
      FP=$(python3 .aios/tools/kitdigest.py --fingerprint "$TMP/release-key.pub" 2>/dev/null || echo none)
      [ "$FP" = "$PIN_KEY" ] || { receipt "$NEW" key-mismatch; echo "The key on the shelf ($FP) is not the one the owner confirmed ($PIN_KEY). Nothing was installed. Tell OakSpin."; exit 1; }
      KEY=$TMP/release-key.pub
    elif fetch "$KEY_FROM" "$TMP/release-key.pub" 2>/dev/null && [ -s "$TMP/releases.json.sig" ] \
        && openssl dgst -sha256 -verify "$TMP/release-key.pub" -signature "$TMP/releases.json.sig" "$TMP/releases.json" >/dev/null 2>&1; then
      SIGNED_BY=$(python3 .aios/tools/kitdigest.py --fingerprint "$TMP/release-key.pub" 2>/dev/null || echo "")
    fi ;;
esac
if [ -n "$KEY" ]; then
  if [ ! -s "$TMP/releases.json.sig" ] || ! openssl dgst -sha256 -verify "$KEY" -signature "$TMP/releases.json.sig" "$TMP/releases.json" >/dev/null 2>&1; then
    receipt "$NEW" bad-signature
    echo "WARNING: the engine on OakSpin's shelf is not signed by OakSpin's key, so it was not installed. Tell OakSpin."
    [ "$ACTION" = auto ] && exit 0; exit 1
  fi
fi

# 3. Only a newer engine, and only as the owner allows.
# An unpinned brain has not confirmed whose list this is, so it never calls the answer verified.
UNVERIFIED=""
[ -n "$KEY" ] || UNVERIFIED=" (OakSpin's release list is not verified until you confirm OakSpin's key once)"
if [ "$NEW" = "$CURRENT" ]; then
  receipt "$NEW" current; [ "$ACTION" = auto ] || echo "Engine $CURRENT is current$UNVERIFIED. Nothing to do."; exit 0
fi
if ! newer "$CURRENT" "$NEW"; then
  receipt "$NEW" shelf-older; [ "$ACTION" = auto ] || echo "OakSpin's shelf has engine $NEW; this brain already runs $CURRENT, which is newer$UNVERIFIED. Nothing to do."; exit 0
fi
if [ "$ACTION" = auto ] && [ "$VERIFY" = legacy ]; then
  receipt "$NEW" needs-key
  echo "Engine $NEW is available. This brain has not confirmed OakSpin's signing key yet: say 'upgrade' and I will read you the key fingerprint to confirm once."
  exit 0
fi
if [ "$ACTION" = auto ] && [ "$PREF" = ask ]; then
  receipt "$NEW" available
  echo "Engine $NEW is available (you have $CURRENT). Say 'upgrade' when you want it."
  exit 0
fi

# 4. The engine itself, checked against the digest in the release list.
if [ -n "${AIOS_SOURCE:-}" ]; then
  mkdir -p "$TMP/kit/src" && cp -R "$AIOS_SOURCE"/. "$TMP/kit/src"/ && rm -rf "$TMP/kit/src/.git"
else
  ARCHIVE="${AIOS_ARCHIVE:-https://github.com/$HOME_REPO/archive/refs/tags}/$TAG.tar.gz"
  if ! fetch "$ARCHIVE" "$TMP/kit.tar.gz"; then
    receipt "$NEW" offline; quiet_or "Could not download engine $NEW ($ARCHIVE). Try again later; nothing was changed."
  fi
  mkdir -p "$TMP/kit"
  tar -xzf "$TMP/kit.tar.gz" -C "$TMP/kit" 2>/dev/null || { receipt "$NEW" damaged-download; quiet_or "The engine download from OakSpin's shelf was damaged. Try again later; nothing was changed."; }
fi
SRC=$(find "$TMP/kit" -maxdepth 4 -path '*/core/.aios' -type d | head -1)
[ -n "$SRC" ] || { receipt "$NEW" damaged-download; quiet_or "The downloaded kit is not an OakSpin AI-OS kit. Nothing was changed."; }
SRC=$(dirname "$SRC")          # the kit's core/: the brain every install gets
KITDIR=$(dirname "$SRC")       # the whole kit, which the release list's digest covers
GOT=$(python3 .aios/tools/kitdigest.py "$KITDIR" 2>/dev/null || echo none)
if [ "$GOT" != "$DIGEST" ]; then
  receipt "$NEW" digest-mismatch
  echo "WARNING: the downloaded engine $NEW does not match OakSpin's release list, so it was not installed. Tell OakSpin."
  [ "$ACTION" = auto ] && exit 0; exit 1
fi
# Python caches are never part of a release and the digest does not cover them: none may ever run.
find "$KITDIR" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
find "$KITDIR" -name '*.pyc' -type f -exec rm -f {} + 2>/dev/null
if find "$KITDIR" -name __pycache__ -o -name '*.pyc' | grep -q .; then
  receipt "$NEW" damaged-download
  echo "The downloaded engine carries files that are not part of the release and could not be removed, so it was not installed. Tell OakSpin."
  [ "$ACTION" = auto ] && exit 0; exit 1
fi
if [ "$(tr -d '[:space:]' < "$SRC/.aios/VERSION")" != "$NEW" ]; then
  receipt "$NEW" digest-mismatch
  echo "WARNING: the downloaded engine says it is $(cat "$SRC/.aios/VERSION") but the release list says $NEW, so it was not installed. Tell OakSpin."
  [ "$ACTION" = auto ] && exit 0; exit 1
fi

if [ -n "$INDUSTRY" ] && [ ! -d "$KITDIR/industries/$INDUSTRY" ]; then
  receipt "$NEW" pack-missing
  echo "Engine $NEW has no '$INDUSTRY' industry pack, which this brain uses, so it was not installed. Tell OakSpin."
  [ "$ACTION" = auto ] && exit 0; exit 1
fi

if [ "$ACTION" = check ]; then
  receipt "$NEW" available
  echo "Engine $NEW is available (you have $CURRENT). What changed:"
  changelog "$NEW" "$SRC/.aios/CHANGELOG.md"
  if [ "$VERIFY" = legacy ] && [ -n "$SIGNED_BY" ]; then
    echo "Its release list is signed by a key with fingerprint $SIGNED_BY, which this brain has not confirmed yet. Confirm it once with the owner against the one OakSpin gave them, then install with --yes --pin-key <that fingerprint>."
  elif [ "$VERIFY" = legacy ]; then
    echo "Its release list could not be checked against any key, so nothing about it is verified. Do not install it; tell OakSpin."
  else
    echo "Say yes to /upgrade to install it."
  fi
  exit 0
fi
if [ "$ACTION" = yes ] && [ "$VERIFY" = legacy ] && [ -z "$KEY" ]; then
  receipt "$NEW" needs-key
  if [ -n "$SIGNED_BY" ]; then
    echo "Engine $NEW's release list is signed by a key with fingerprint $SIGNED_BY. To install it the first time, the owner confirms that fingerprint against the one OakSpin gave them."
    echo "After their yes, run again with: --yes --pin-key $SIGNED_BY. Nothing was changed."
  else
    echo "Engine $NEW's release list could not be checked against any key. Nothing was changed. Tell OakSpin."
  fi
  exit 1
fi

# 5. One upgrade at a time, and never over unsaved work: the owner's files must be safe first.
LOCK_DIR="$(git rev-parse --git-dir)/aios-upgrade.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  holder=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "")
  if [ -n "$holder" ] && kill -0 "$holder" 2>/dev/null; then
    receipt "$NEW" busy; quiet_or "Another upgrade is running in this brain. Nothing was changed; try again when it finishes."
  fi
  rm -rf "$LOCK_DIR"; mkdir "$LOCK_DIR" 2>/dev/null || { receipt "$NEW" busy; quiet_or "Another upgrade is running in this brain. Nothing was changed."; }
fi
LOCK=$LOCK_DIR
echo $$ > "$LOCK/pid"
if [ -n "$(git status --porcelain)" ]; then
  receipt "$NEW" deferred-unsaved-work
  quiet_or "There is unsaved work. Run /save first, then /upgrade."
fi

echo "Upgrading engine $CURRENT -> $NEW"
SNAP_HEAD=$(git rev-parse HEAD)
mkdir -p "$TMP/home" "$TMP/tmp" "$TMP/keep"
snapshot || { receipt "$NEW" failed; echo "Could not set the brain's files aside before upgrading, so nothing was changed. Tell OakSpin."; exit 1; }
APPLYING=1

# The name is written quoted with its own quotes escaped; brains installed before 0.3.2 may hold it
# with bare inner quotes, which is read back whole too.
COMPANY=$(python3 - <<'PY'
import json, re, sys
for line in open('aios.yml', encoding='utf-8'):
    m = re.match(r'company:\s*(.*?)\s*$', line)
    if m:
        value = m.group(1)
        if value.startswith('"'):
            try:
                value = json.loads(value)
            except ValueError:
                value = value[1:-1] if value.endswith('"') else value[1:]
        sys.stdout.buffer.write(value.encode('utf-8'))
        break
PY
)
PRIVATE=$(sed -n 's/^private_folder: *//p' aios.yml | head -1)
DOCUMENTS=$(sed -n 's/^documents_folder: *//p' aios.yml | head -1)

# a. Engine folder, replaced whole, then the owner's names put back into the interview.
OLD_ADAPTERS=$(cat .aios/adapters.txt 2>/dev/null || true)
rm -rf .aios && cp -R "$SRC/.aios" .aios
if [ -n "$INDUSTRY" ] && [ -d "$KITDIR/industries/$INDUSTRY/engine" ]; then
  mkdir -p .aios/industry && cp -R "$KITDIR/industries/$INDUSTRY/engine"/. .aios/industry/
fi
chmod +x .aios/hooks/*.sh .aios/hooks/pre-commit .aios/tools/*.py .aios/tools/*.sh 2>/dev/null || true
python3 .aios/tools/names.py .aios/interview.json "$COMPANY" "$PRIVATE" "$DOCUMENTS"

# b. Command adapters and hook settings from the kit: exactly the paths in .aios/adapters.txt. A path
#    the old engine did not own is the owner's: if a new adapter would replace a different file there,
#    the upgrade stops and everything is put back.
while IFS= read -r rel; do
  case "$rel" in ""|/*|*..*) continue ;; esac
  [ -f "$SRC/$rel" ] || { echo "The new engine lists $rel but does not carry it."; false; }
  if [ -e "$rel" ] && ! printf '%s\n' "$OLD_ADAPTERS" | grep -qxF "$rel" && ! cmp -s "$SRC/$rel" "$rel"; then
    echo "The new engine has a command at $rel, where the owner already has one of their own. Nothing was replaced. Tell OakSpin."
    false
  fi
  mkdir -p "$(dirname "$rel")" && cp "$SRC/$rel" "$rel"
done < .aios/adapters.txt

# c. The fenced engine block inside AGENTS.md, and nothing outside it.
python3 - "$SRC/AGENTS.md" "$COMPANY" "$NEW" "$PRIVATE" <<'PY'
import re, sys
from pathlib import Path
src, company, version, private = sys.argv[1:5]
found = re.search(r'<!-- aios:engine-begin -->.*?<!-- aios:engine-end -->', Path(src).read_text(), re.S)
if not found:
    sys.exit('The downloaded engine has no engine block in its AGENTS.md.')
block = found.group(0)
block = block.replace('%%COMPANY%%', company).replace('%%ENGINE_VERSION%%', version).replace('%%PRIVATE%%', private)
p = Path('AGENTS.md'); s = p.read_text()
if '<!-- aios:engine-begin -->' in s:
    s = re.sub(r'<!-- aios:engine-begin -->.*?<!-- aios:engine-end -->', lambda m: block, s, count=1, flags=re.S)
else:
    s = s.rstrip('\n') + '\n\n' + block + '\n'
p.write_text(s)
PY

# d. Migrations between the old and the new version, oldest first, from the verified engine only,
#    with a throwaway home so none can write into the owner's own folders.
if [ -d .aios/migrations ]; then
  for m in $(ls .aios/migrations/*.sh 2>/dev/null | python3 -c 'import sys; print("\n".join(sorted((l.strip() for l in sys.stdin), key=lambda p: [int(x) for x in p.split("/")[-1][:-3].split(".")])))'); do
    v=$(basename "$m" .sh)
    if newer "$CURRENT" "$v" && ! newer "$NEW" "$v"; then
      echo "Applying migration $v"; HOME="$TMP/home" TMPDIR="$TMP/tmp" sh "$m"
    fi
  done
fi

# e. Record, check and save.
sed -i.bak "s/^engine: .*/engine: $NEW/" aios.yml && rm -f aios.yml.bak
if [ "$VERIFY" = legacy ] && [ -n "$KEY" ]; then
  mkdir -p .oakspin && cp "$KEY" "$PINNED"
  grep -v '^verify:' aios.yml > "$TMP/aios.yml" || true
  cat "$TMP/aios.yml" > aios.yml
  printf 'verify: signed\n' >> aios.yml
fi
git config --local core.hooksPath .aios/hooks
python3 .aios/tools/check.py >/dev/null 2>&1 || { python3 .aios/tools/check.py; false; }
receipt "$NEW" installed
printf -- '- %s upgraded engine %s -> %s\n' "$(date +%Y-%m-%d)" "$CURRENT" "$NEW" >> memory/install-receipts.md
git add -A
# The pre-commit hook runs the checks again and says so; that line is noise in a session log.
if ! out=$(git -c user.name="${GIT_AUTHOR_NAME:-$(git config user.name || echo owner)}" -c user.email="${GIT_AUTHOR_EMAIL:-$(git config user.email || echo owner@brain.local)}" \
  commit -q -m "Upgrade OakSpin AI-OS engine $CURRENT -> $NEW" 2>&1); then printf '%s\n' "$out"; false; fi
APPLYING=0
git remote get-url origin >/dev/null 2>&1 && { aios_push -q origin main 2>/dev/null || true; }
if [ "$ACTION" = auto ]; then echo "Engine updated to $NEW. What changed:"; else echo "Engine $NEW installed. What changed:"; fi
changelog "$NEW" .aios/CHANGELOG.md
# The "what's new" page for this version, when the engine ships one: say it, and tell the owner one thing to try.
if [ -s .aios/whats-new.url ]; then echo "  Something new arrived. Read what it does and one thing to try: $(head -1 .aios/whats-new.url)"; fi
