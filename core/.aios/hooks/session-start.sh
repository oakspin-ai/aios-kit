#!/bin/sh
# Runs when a session starts (Claude Code SessionStart hook).
# 1. Pull the latest saves from the other device.
# 2. Fold any side branch another device left behind (a phone or cloud session pushes to a side
#    branch, and cloud sessions cannot delete remote branches). Each fold goes through the same
#    checks as a save: if a branch holds something that must not go in the brain, it is left
#    alone and named, never merged.
#    Everyday saves (company facts, clients, memory, inbox) fold on their own. A save that changes
#    how the brain itself works (its rules, what runs automatically, the engine, skills,
#    permissions, what stays private) is held and named until the owner says yes or no
#    (.aios/tools/wiring.py decides; .aios/tools/fold.sh takes the answer). The same goes for such
#    changes pushed straight to GitHub's main line: main does not move until the owner says yes.
# 3. Keep the engine current: at most once a day, ask the updater. With "upgrade: auto" it installs
#    a newer signed engine when the tree is clean; with "upgrade: ask" (or no setting) it only says
#    one is available. The updater itself decides; this hook never installs anything.
# Quiet when there is nothing to do. Never touches a dirty tree or a session not on main, and never
# pushes to OakSpin's public kit (see .aios/tools/kit_home.sh).
set -u
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 0
. .aios/tools/kit_home.sh 2>/dev/null || { aios_kit_home() { return 1; }; aios_push() { git push "$@"; }; }
[ ! -f .aios/tools/python.sh ] || . .aios/tools/python.sh
AIOS_FOLD_LIB=1
# without the fold tool nothing folds; held saves are still named, and the updater can repair it
. .aios/tools/fold.sh 2>/dev/null || { aios_fold() { echo "Not folded: the save from another device ('$2') waits until the brain's engine is whole again."; return 1; }
  aios_held() { echo "Waiting for your yes: a save from another device ('$1', $2) changes how the brain itself works:"; printf '%s\n' "$3"; }; }
yml_value() { sed -n "s/^$1:[[:space:]]*//p" aios.yml 2>/dev/null | head -1 | sed 's/#.*//; s/["'"'"' 	]//g' | tr -d '\r' | tr '[:upper:]' '[:lower:]'; }

sync_from_other_devices() {
git remote get-url origin >/dev/null 2>&1 || return 0
if aios_kit_home; then
  echo "This folder's GitHub copy is OakSpin's public kit, not your brain. Not syncing with it. Tell OakSpin."
  return 0
fi
[ "$(git branch --show-current 2>/dev/null)" = main ] || return 0
[ -z "$(git status --porcelain)" ] || return 0

git fetch -q --prune origin 2>/dev/null || { echo "Could not reach GitHub for the latest saves. Working with the local copy."; return 0; }
# GitHub's main line has saves this copy does not: bring them in only if they are everyday content
if git rev-parse -q --verify refs/remotes/origin/main >/dev/null && ! git merge-base --is-ancestor origin/main main 2>/dev/null; then
  if changes=$(python3 .aios/tools/wiring.py main origin/main 2>&1); then
    # everyday saves still go through the same check as a fold before main moves
    aios_checked_merge origin/main
    case $? in
      0) git merge --abort 2>/dev/null
         if git merge-base --is-ancestor main origin/main; then
           git merge -q --ff-only origin/main 2>/dev/null || echo "Could not pull the latest saves from GitHub. Working with the local copy."
         else
           echo "Your GitHub copy and this computer both have new saves. Run /save to bring them together."
           return 0
         fi ;;
      1) echo "Could not pull the latest saves from GitHub: they change the same lines as this copy. Run /save and read the message."; return 0 ;;
      *) echo "Not pulled: the latest saves on GitHub hold something that must not go in the brain. Fix it on the device that saved it."; return 0 ;;
    esac
  else
    # held whether or not saves were made here meanwhile; fold.sh --yes main merges them, checked
    aios_held main "$(git rev-parse --short=12 origin/main)" "$changes"
    return 0  # nothing else folds onto a main line that is waiting for an answer
  fi
fi

folded=0
# branch names only: GitHub's HEAD pointer (origin/HEAD, short name "origin") is not a save
for branch in $(git for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin | grep -v -e '^main$' -e '^HEAD$'); do
  # a branch name is written by whoever saved it: an unusual one is never folded or repeated here
  if ! printf '%s' "$branch" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._/-]{0,79}$'; then
    echo "A save from another device has a name with unusual characters, so it was left alone and is not named here. Tell OakSpin."
    continue
  fi
  ref=origin/$branch
  # already in main? then only the leftover branch needs removing
  if git merge-base --is-ancestor "$ref" main 2>/dev/null; then
    aios_push -q origin --delete "$branch" 2>/dev/null || true
    continue
  fi
  if ! changes=$(python3 .aios/tools/wiring.py main "$ref" 2>&1); then
    aios_held "$branch" "$(git rev-parse --short=12 "$ref")" "$changes"
    continue
  fi
  aios_fold "$ref" "$branch" && folded=$((folded + 1))
done
if [ "$folded" -gt 0 ]; then
  aios_push -q origin main 2>/dev/null && echo "Brought in $folded save(s) from another device." || echo "Brought in $folded save(s) from another device. Could not push to GitHub yet; it will push at the next save."
fi
}

keep_engine_current() {
  [ -f .aios/tools/upgrade.sh ] || return 0
  [ "$(git branch --show-current 2>/dev/null)" = main ] || return 0
  if [ "$(yml_value verify)" = none ]; then
    echo "This brain was installed without OakSpin's signing key (verify: none in aios.yml), so it takes no engine update until you confirm that key once. If OakSpin did not tell you this, tell OakSpin."
  fi
  stamp=memory/receipts/upgrade-check.json
  if [ -f "$stamp" ] && [ -n "$(find "$stamp" -mmin -1440 2>/dev/null)" ]; then return 0; fi
  # The updater says what matters and nothing else: silent when current or offline, one line when a
  # newer engine waits for the owner, the change list when it installed one, a warning when something
  # on the shelf did not check out.
  log=$(sh .aios/tools/upgrade.sh --auto 2>/dev/null || true)
  [ -z "$log" ] || printf '%s\n' "$log"
}

sync_from_other_devices
keep_engine_current
[ -f .aios/tools/pipeline.py ] && python3 .aios/tools/pipeline.py --age 2>&1 || true
exit 0
