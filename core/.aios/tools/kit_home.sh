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

# aios_push <git push arguments>: pushes, unless origin is the kit's home.
aios_push() {
  if aios_kit_home; then
    echo "This folder's GitHub copy is OakSpin's public kit, not your brain. Nothing was pushed. Tell OakSpin."
    return 1
  fi
  git push "$@"
}
