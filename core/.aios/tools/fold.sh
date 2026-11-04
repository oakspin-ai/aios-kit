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

aios_git() {  # git, naming the owner when this computer's Git has no name or email (a new computer
  # often has none, and Git then refuses to merge or save)
  git -c user.name="${GIT_AUTHOR_NAME:-$(git config user.name || echo owner)}" \
      -c user.email="${GIT_AUTHOR_EMAIL:-$(git config user.email || echo owner@brain.local)}" "$@"
}

aios_fetch() {  # git fetch, quiet. The Claude app downloads from GitHub when a session opens too; the
  # second of two downloads finds GitHub's line locked and gives up, so a locked line is tried up to
  # three times in all
  n=0
  while ! out=$(git fetch -q "$@" 2>&1); do
    n=$((n + 1))
    [ "$n" -lt 3 ] && printf '%s' "$out" | grep -q 'lock' || return 1
    sleep 1
  done
}

aios_union_logs() {  # Logs that only ever gain rows keep both sides' rows when two devices each added
  # one, instead of clashing. Set in this computer's own Git (.git/info/attributes), never in a save.
  # A row corrected here while another device adds one keeps both, so these logs are corrected by
  # adding a row, never by editing one (AGENTS.md).
  attrs=$(git rev-parse --git-path info/attributes 2>/dev/null) || return 0
  grep -qs '^# aios logs 1$' "$attrs" && return 0
  mkdir -p "$(dirname "$attrs")" || return 0
  # never glue the block onto a last line someone left without its newline
  [ ! -s "$attrs" ] || [ -z "$(tail -c 1 "$attrs")" ] || echo >> "$attrs"
  printf '%s\n' '# aios logs 1' 'memory/decisions.md merge=union' \
    'memory/actions.md merge=union' 'memory/filed-meetings.md merge=union' 'memory/install-receipts.md merge=union' >> "$attrs"
}

aios_checked_merge() {  # $1 ref. Stage what $1 brings into main and run the secret check on it.
  # 0 staged and clean (commit or abort next); 1 it changes the same lines as this copy; 2 it holds a
  # secret, or the check could not run; 3 Git could not merge here for another reason
  # (AIOS_MERGE_ERROR holds Git's own words). On 1, 2 or 3 main and the working copy are left as they were.
  # The check runs from a copy of this brain's engine taken before the merge, so a save that changes
  # the checker (or the industry checks) is judged by the checker it would replace.
  aios_union_logs
  trusted=$(mktemp -d) || return 2
  if ! cp -R .aios "$trusted/.aios" 2>/dev/null; then rm -rf "$trusted"; return 2; fi
  if ! out=$(aios_git merge -q --no-ff --no-commit "$1" 2>&1); then
    clashes=$(git diff --name-only --diff-filter=U 2>/dev/null)
    git merge --abort 2>/dev/null || git reset -q --hard main
    rm -rf "$trusted"
    [ -n "$clashes" ] && return 1
    AIOS_MERGE_ERROR=$(printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | tail -1)
    return 3
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
  if ! out=$(aios_git commit -q -m "$1" 2>&1); then
    printf '%s\n' "$out"
    return 1
  fi
}

aios_join_main() {  # Bring GitHub's main line into main, checked, when both have moved (a save made on
  # GitHub itself, or on another computer, while this one saved too). 0 joined or nothing to join;
  # 1 not joined, and it says why. A change to how the brain works still waits for the owner's yes.
  theirs=$(git rev-parse -q --verify refs/remotes/origin/main) || return 0
  git merge-base --is-ancestor "$theirs" main 2>/dev/null && return 0
  if ! python3 .aios/tools/wiring.py main "$theirs" >/dev/null 2>&1; then
    echo "GitHub's main line has saves waiting for your yes, so they were not brought in. The next session on this computer names them."
    return 1
  fi
  aios_checked_merge "$theirs" >/dev/null
  case $? in
    0) ;;
    1) echo "GitHub's main line and this computer changed the same lines, so they were not joined. Tell OakSpin."; return 1 ;;
    2) echo "GitHub's main line holds something that must not go in the brain, so it was not brought in. Fix it on the device that saved it."; return 1 ;;
    *) echo "Git could not join GitHub's main line here. Git said: ${AIOS_MERGE_ERROR:-nothing}. Tell OakSpin."; return 1 ;;
  esac
  if git merge-base --is-ancestor main "$theirs"; then
    git merge --abort 2>/dev/null
    git merge -q --ff-only "$theirs" 2>/dev/null && return 0
    echo "Could not bring in GitHub's main line. Tell OakSpin."
    return 1
  fi
  if ! aios_commit "Bring in saves from GitHub's main line" >/dev/null; then
    git merge --abort 2>/dev/null || git reset -q --hard main
    echo "GitHub's main line could not be joined here: the save could not be recorded. Tell OakSpin."
    return 1
  fi
}

aios_fold() {  # $1 remote ref (origin/x), $2 branch name. 0 folded, 1 not.
  aios_checked_merge "$1"
  case $? in
    1) echo "Could not fold the save from another device ('$2') automatically: it changes the same lines as this copy. Run /save and read the message."; return 1 ;;
    2) echo "Not folded: the save from another device ('$2') holds something that must not go in the brain. Fix it on that device, then start again."; return 1 ;;
    0) ;;
    *) echo "Not folded: Git could not bring in the save from another device ('$2') here. Git said: ${AIOS_MERGE_ERROR:-nothing}. Tell OakSpin."; return 1 ;;
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
  aios_fetch --prune origin || fail "Nothing changed: could not reach GitHub. Try again when online."
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
      0) ;;
      *) fail "Nothing changed: Git could not bring in the saves waiting on GitHub's main line here. Git said: ${AIOS_MERGE_ERROR:-nothing}. They stay held. Tell OakSpin." ;;
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
