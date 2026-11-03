#!/bin/sh
# OakSpin AI-OS: bring a save from another device (a phone or cloud session) into main.
#
#   sh .aios/tools/fold.sh --yes BRANCH SHA   the owner said yes to that held save, as it was shown
#   sh .aios/tools/fold.sh --yes main SHA     the owner said yes to the held saves on GitHub's main
#                                             (merged with any saves made here while they waited)
#   sh .aios/tools/fold.sh --no BRANCH        the owner said no: drop that save, nothing comes in
#
# Everyday saves fold on their own at session start. A save that changes how the brain itself works
# (.aios/tools/wiring.py) is held and named until the owner answers. A yes covers the save exactly
# as the owner saw it (SHA): if the branch has moved since, nothing folds. Every fold, held or not,
# goes through the same secret check as a save. session-start.sh sources this file for aios_fold
# and aios_held (AIOS_FOLD_LIB=1), so there is one way in.

aios_checked_merge() {  # $1 ref. Stage what $1 brings into main and run the secret check on it.
  # 0 staged and clean (commit or abort next); 1 it changes the same lines as this copy; 2 it holds a
  # secret, or the check could not run. On 1 or 2 main and the working copy are left as they were.
  # The check runs from a copy of this brain's engine taken before the merge, so a save that changes
  # the checker (or the industry checks) is judged by the checker it would replace.
  trusted=$(mktemp -d) || return 2
  if ! cp -R .aios "$trusted/.aios" 2>/dev/null; then rm -rf "$trusted"; return 2; fi
  if ! git merge -q --no-ff --no-commit "$1" 2>/dev/null; then
    git merge --abort 2>/dev/null || git reset -q --hard main
    rm -rf "$trusted"
    return 1
  fi
  if ! AIOS_BRAIN_ROOT="$(pwd)" PYTHONDONTWRITEBYTECODE=1 python3 "$trusted/.aios/tools/check.py" --staged; then
    git merge --abort 2>/dev/null || git reset -q --hard main
    rm -rf "$trusted"
    return 2
  fi
  rm -rf "$trusted"
  return 0
}

aios_commit() {  # $1 message. Fails (and says why) when the save could not be recorded.
  if ! out=$(git -c user.name="${GIT_AUTHOR_NAME:-$(git config user.name || echo owner)}" \
      -c user.email="${GIT_AUTHOR_EMAIL:-$(git config user.email || echo owner@brain.local)}" \
      commit -q -m "$1" 2>&1); then
    printf '%s\n' "$out"
    return 1
  fi
}

aios_fold() {  # $1 remote ref (origin/x), $2 branch name. 0 folded, 1 not.
  aios_checked_merge "$1"
  case $? in
    1) echo "Could not fold the save from another device ('$2') automatically: it changes the same lines as this copy. Run /save and read the message."; return 1 ;;
    2) echo "Not folded: the save from another device ('$2') holds something that must not go in the brain. Fix it on that device, then start again."; return 1 ;;
  esac
  if ! aios_commit "Fold save from another device ($2)"; then
    git merge --abort 2>/dev/null || git reset -q --hard main
    echo "Not folded: the save from another device ('$2') could not be recorded here. It stays on GitHub."
    return 1
  fi
  aios_push -q origin --delete "$2" 2>/dev/null || true
  return 0
}

aios_held() {  # $1 branch, $2 commit, $3 the plain-English list from wiring.py
  if [ "$1" = main ]; then
    echo "Waiting for your yes: your GitHub copy has saves from another device ('main', $2) that change how the brain itself works:"
  else
    echo "Waiting for your yes: a save from another device ('$1', $2) changes how the brain itself works:"
  fi
  printf '%s\n' "$3"
  echo "  Nothing from it is in your brain yet. Ask me what it changes. Say yes to bring it in, or no to drop it."
}

if [ "${AIOS_FOLD_LIB:-}" != 1 ]; then
  set -u
  fail() { echo "$1"; exit 1; }
  cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1
  . .aios/tools/kit_home.sh 2>/dev/null || { aios_kit_home() { return 1; }; aios_push() { git push "$@"; }; }
  [ ! -f .aios/tools/python.sh ] || . .aios/tools/python.sh
  answer=${1:-} branch=${2:-} sha=${3:-}
  case "$answer" in --yes|--no) ;; *) fail "usage: fold.sh --yes BRANCH SHA | --no BRANCH" ;; esac
  [ -n "$branch" ] || fail "usage: fold.sh --yes BRANCH SHA | --no BRANCH"
  printf '%s' "$branch" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._/-]{0,79}$' || fail "Nothing changed: that is not the name of a save."
  aios_kit_home && fail "This folder's GitHub copy is OakSpin's public kit, not your brain. Nothing was changed. Tell OakSpin."
  [ "$(git branch --show-current 2>/dev/null)" = main ] || fail "Nothing changed: this copy is not on the main line. Start a session on the main computer and answer there."
  [ -z "$(git status --porcelain)" ] || fail "Nothing changed: there is unsaved work here. Save first (/save), then answer again."
  git fetch -q --prune origin 2>/dev/null || fail "Nothing changed: could not reach GitHub. Try again when online."
  now=$(git rev-parse -q --verify "refs/remotes/origin/$branch") || fail "There is no save called '$branch' on GitHub any more. Nothing changed."

  if [ "$answer" = --no ]; then
    [ "$branch" != main ] || fail "The saves already on GitHub's main line cannot be dropped from here. They stay held. Tell OakSpin."
    aios_push -q origin --delete "$branch" 2>/dev/null || fail "Could not remove '$branch' from GitHub. Nothing came in; it will be asked about again next time."
    git update-ref -d "refs/remotes/origin/$branch" 2>/dev/null
    echo "Dropped the save from another device ('$branch'). Nothing from it came into your brain."
    exit 0
  fi

  case "$sha" in
    ''|*[!0-9a-f]*) fail "Nothing changed: say yes to a save as it was shown, with its code (for example 1a2b3c4d5e6f)." ;;
  esac
  [ ${#sha} -ge 7 ] || fail "Nothing changed: the code for the save is too short to be sure which one you mean."
  case "$now" in
    "$sha"*) ;;
    *) fail "Nothing changed: the save '$branch' changed after you saw it. Start a new session to see it again before saying yes." ;;
  esac

  if [ "$branch" = main ]; then
    # the same check as any other fold, then GitHub's line as it is, or merged with saves made here
    aios_checked_merge "$now"
    case $? in
      1) fail "Nothing changed: the saves waiting on GitHub's main line change the same lines as a save on this computer, so they cannot come in on their own. They stay held. Tell OakSpin." ;;
      2) fail "Nothing changed: the saves waiting on GitHub's main line hold something that must not go in the brain. They stay out. Tell OakSpin." ;;
    esac
    if git merge-base --is-ancestor main "$now"; then
      git merge --abort 2>/dev/null
      git merge -q --ff-only "$now" 2>/dev/null || fail "Could not bring in GitHub's main line. Nothing changed. Tell OakSpin."
      echo "Brought in the saves waiting on GitHub's main line."
      exit 0
    fi
    if ! aios_commit "Bring in held saves from GitHub's main line"; then
      git merge --abort 2>/dev/null || git reset -q --hard main
      fail "Nothing changed: the saves waiting on GitHub's main line could not be recorded here. They stay held."
    fi
    if aios_push -q origin main 2>/dev/null; then
      echo "Brought in the saves waiting on GitHub's main line, kept the saves made here, and backed them up to GitHub."
    else
      echo "Brought in the saves waiting on GitHub's main line and kept the saves made here. Could not push to GitHub yet; it will push at the next save."
    fi
    exit 0
  fi
  git merge-base --is-ancestor origin/main main 2>/dev/null || fail "Nothing changed: answer the saves waiting on GitHub's main line first."
  aios_fold "origin/$branch" "$branch" || exit 1
  if git remote get-url origin >/dev/null 2>&1 && aios_push -q origin main 2>/dev/null; then
    echo "Brought in the save from another device ('$branch') and backed it up to GitHub."
  else
    echo "Brought in the save from another device ('$branch'). Could not push to GitHub yet; it will push at the next save."
  fi
fi
