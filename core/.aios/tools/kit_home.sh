# Sourced by the hooks and the updater, from the brain's root.
#
# A brain's GitHub copy is the owner's private repository. It is never OakSpin's public kit, the
# place the engine is downloaded from. A brain built inside a clone of the public kit could
# otherwise push itself there through its own auto-save. These two guards make that impossible:
# nothing in a brain pushes when "origin" is the kit's home.
#
# The kit's home is AIOS_REPO, or the repo= line in .aios/release.conf. While neither is set
# (OakSpin has not set up releases yet) there is no public kit to protect.

aios_kit_repo() {
  printf '%s' "${AIOS_REPO:-$(sed -n 's/^repo=//p' .aios/release.conf 2>/dev/null | head -1 | tr -d '[:space:]')}"
}

aios_kit_home() {  # true when any fetch or push address of origin is the kit's home
  git remote get-url origin >/dev/null 2>&1 || return 1
  home=$(aios_kit_repo | tr '[:upper:]' '[:lower:]')
  [ -n "$home" ] || return 1
  for url in $( { git remote get-url --all origin; git remote get-url --push --all origin; } 2>/dev/null | tr '[:upper:]' '[:lower:]'); do
    case "$url" in
      *"$home"|*"$home.git"|*"$home/"|*"$home.git/") return 0 ;;
    esac
  done
  return 1
}

# aios_github_login_failure <git's error text>: true when GitHub turned this computer's login away,
# as opposed to GitHub being out of reach. A Git with no GitHub login fails every save the same way a
# lost connection does unless the two are told apart (Mac test, 2026-11-05).
aios_github_login_failure() {
  printf '%s' "$1" | grep -qiE 'could not read (username|password)|terminal prompts disabled|authentication failed|invalid username or password|permission to .* denied|returned error: 40[13]|permission denied \(publickey\)'
}

AIOS_LOGIN_FIX="GitHub did not accept this computer's login. Fix: run gh auth setup-git, then /save."

# aios_github_tell <git's error text>: when it was the login, note it in AIOS_LOGIN_SEEN, say so once per
# run (unless AIOS_LOGIN_QUIET=1: the caller's own last line says it) and return true.
aios_github_tell() {
  aios_github_login_failure "$1" || return 1
  if [ "${AIOS_LOGIN_SEEN:-0}" != 1 ] && [ "${AIOS_LOGIN_QUIET:-0}" != 1 ]; then
    echo "Saves stay on this computer until this is fixed. $AIOS_LOGIN_FIX"
  fi
  AIOS_LOGIN_SEEN=1
  return 0
}

# aios_git_reason: the cause of the last failed GitHub call, for a message's brackets: Git's first
# fatal: or error: line (it adds advice after it), else its last line.
aios_git_reason() {
  { printf '%s\n' "${AIOS_GIT_ERR:-}" | grep -iE -m1 '^(fatal|error):' || printf '%s\n' "${AIOS_GIT_ERR:-}" | sed '/^[[:space:]]*$/d' | tail -1; } \
    | sed 's/^[Ff]atal: //; s/^[Ee]rror: //' | cut -c1-200
}

# aios_push <git push arguments>: pushes, unless origin is the kit's home. A failure keeps Git's own
# words in AIOS_GIT_ERR (and on stderr), and a refused login is named.
aios_push() {
  if aios_kit_home; then
    echo "This folder's GitHub copy is OakSpin's public kit, not your brain. Nothing was pushed. Tell OakSpin."
    return 1
  fi
  AIOS_GIT_ERR=$(git push "$@" 2>&1) && return 0
  aios_github_tell "$AIOS_GIT_ERR" || true
  printf '%s\n' "$AIOS_GIT_ERR" >&2
  return 1
}
