#!/bin/sh
# OakSpin AI-OS autosave. Runs when a session ends (Claude Code SessionEnd hook) and on /save.
# Safe by design: if the checks find something private, nothing is saved and the reason is printed.
# It pushes to the owner's own GitHub copy and never to OakSpin's public kit (.aios/tools/kit_home.sh).
set -u
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0
# A save from another device that was being brought in when the app closed is left half done: saving
# now would record it unfinished (clash markers and all). Stop and say so; nothing is lost.
if git rev-parse -q --verify MERGE_HEAD >/dev/null || [ -n "$(git diff --name-only --diff-filter=U 2>/dev/null)" ]; then
  echo "Not saved: bringing in a save from another device was interrupted and is not finished, so nothing is saved until it is sorted out. Nothing was lost. Tell OakSpin."
  exit 0
fi
. .aios/tools/kit_home.sh 2>/dev/null || { aios_kit_home() { return 1; }; aios_push() { git push "$@"; }; }
[ ! -f .aios/tools/python.sh ] || . .aios/tools/python.sh
# the same checked merge session start and fold.sh use; without it nothing from GitHub comes in here
AIOS_FOLD_LIB=1
. .aios/tools/fold.sh 2>/dev/null || { aios_checked_merge() { return 2; }; aios_join_main() { return 0; }; aios_git() { git "$@"; }
  aios_fetch() { git fetch -q "$@" 2>/dev/null; }; aios_union_logs() { :; }; }
# GitHub's main line moved too (a save made on GitHub itself, or on another computer): join it, checked,
# before pushing, so the two never wait on each other. 0 go ahead and push, 1 stop (it said why).
join_github() {
  git remote get-url origin >/dev/null 2>&1 && ! aios_kit_home || return 0
  aios_fetch origin main || return 0
  aios_join_main
}
branch=$(git branch --show-current 2>/dev/null || echo main)
if [ -z "$(git status --porcelain)" ] && [ "$branch" = main ]; then
  # nothing new locally; still join GitHub's main line and push anything unpushed
  if ! join_github; then
    echo "Saved on this computer only, not yet backed up to GitHub."
    exit 0
  fi
  git remote get-url origin >/dev/null 2>&1 && { aios_push -q origin main 2>/dev/null || true; }
  exit 0
fi
# The pipeline page (clients/pipeline.md) is client content, so it is rebuilt before every save on every
# branch; the check below would otherwise refuse a phone or cloud save that changed a card.
# The front page (README.md) is rebuilt on main only. On a phone or cloud side branch it would count as
# a change to how the brain works and hold every save; the main computer rebuilds it at its next save.
python3 .aios/tools/pipeline.py >/dev/null 2>&1 || true
[ "$branch" = main ] && { python3 .aios/tools/frontpage.py >/dev/null 2>&1 || true; }
git add -A
if ! python3 .aios/tools/check.py --staged; then
  echo "Not saved: the checks above found something that must not go in the brain. Fix it, then /save."
  git reset -q
  exit 0
fi
if ! git diff --cached --quiet; then
  if ! out=$(git -c user.name="${GIT_AUTHOR_NAME:-$(git config user.name || echo owner)}" \
      -c user.email="${GIT_AUTHOR_EMAIL:-$(git config user.email || echo owner@brain.local)}" \
      commit -q -m "Session save $(date +%Y-%m-%d\ %H:%M)" 2>&1); then
    git reset -q
    printf '%s\n' "$out"
    echo "Not saved: the save could not be recorded (see above). Nothing was lost; /save again once it is fixed."
    exit 0
  fi
fi
if [ "$branch" != main ]; then
  # A save that changes how the brain itself works (.aios/tools/wiring.py) stays on its side branch
  # and waits for the owner's yes on the main computer (session start names it there).
  base=main
  git rev-parse -q --verify refs/remotes/origin/main >/dev/null && base=origin/main
  if ! changes=$(python3 .aios/tools/wiring.py "$base" "$branch" 2>&1); then
    if git remote get-url origin >/dev/null 2>&1 && ! aios_kit_home && aios_push -q origin "$branch" 2>/dev/null; then
      echo "Saved on this device. It changes how the brain itself works, so it waits for your yes on your main computer before it joins the rest:"
    else
      echo "Saved on this device only. It changes how the brain itself works, so it waits for your yes on your main computer:"
    fi
    printf '%s\n' "$changes"
    exit 0
  fi
  # everyday content from a cloud or phone session: fold it into main, one line of history. GitHub's
  # main comes in first, but only when it is everyday content too; otherwise the save stays on its
  # branch, pushed, and the main computer brings both in.
  keep_branch() {
    git checkout -q "$branch" 2>/dev/null
    if git remote get-url origin >/dev/null 2>&1 && ! aios_kit_home && aios_push -q origin "$branch" 2>/dev/null; then
      echo "Saved on this device as '$branch'. $1 Your main computer brings it in at its next session."
    else
      echo "Saved on this device only, as '$branch'. $1"
    fi
    exit 0
  }
  git checkout -q main 2>/dev/null || git checkout -q -b main
  if git remote get-url origin >/dev/null 2>&1 && ! aios_kit_home; then
    aios_fetch origin main || keep_branch "GitHub could not be reached, so it was not folded into main."
    if git rev-parse -q --verify refs/remotes/origin/main >/dev/null && ! git merge-base --is-ancestor origin/main main; then
      python3 .aios/tools/wiring.py main origin/main >/dev/null 2>&1 || keep_branch "GitHub's main line has saves waiting for your yes, so this one waits with them."
      # everyday saves on GitHub's main still go through the check before main moves here
      aios_checked_merge origin/main >/dev/null || keep_branch "GitHub's main line holds something the checks refuse, so this save waits on its own."
      git merge --abort 2>/dev/null
      git merge -q --ff-only origin/main 2>/dev/null || keep_branch "GitHub's main line and this copy both moved, so it was not folded here."
    fi
  fi
  aios_union_logs
  if ! aios_git merge -q --no-edit "$branch" 2>/dev/null; then
    git merge --abort 2>/dev/null
    keep_branch "It could not be folded into main automatically."
  fi
  git branch -q -D "$branch" 2>/dev/null
  git remote get-url origin >/dev/null 2>&1 && { aios_push -q origin --delete "$branch" 2>/dev/null || true; }
fi
if [ "$branch" = main ] && ! join_github; then
  echo "Saved on this computer only, not yet backed up to GitHub."
  exit 0
fi
if git remote get-url origin >/dev/null 2>&1; then
  if aios_kit_home; then
    echo "Saved locally. This folder's GitHub copy is OakSpin's public kit, not your brain, so nothing was pushed. Tell OakSpin."
  else
    git push -q origin main 2>/dev/null && echo "Saved and backed up to GitHub." || echo "Saved locally. Could not reach GitHub; it will push next time."
  fi
else
  echo "Saved locally (no GitHub copy connected yet)."
fi
