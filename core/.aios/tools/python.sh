# Sourced by the hooks, the updater and setup, from the brain's root.
#
# The brain's tools run as python3. A Mac and Linux have that name; Windows usually does not. The
# python.org installer for Windows gives `python` and `py`, and Windows puts a python3 placeholder
# on the path that only offers to install Python from the Microsoft Store. Where python3 is missing
# or is that placeholder, python3 here means the first real Python 3.9 or newer of `python` and
# `py -3`. Where python3 works, nothing changes.
#
# On Windows the tools also read and write text as UTF-8 (PYTHONUTF8): Windows Python otherwise
# uses the old Windows code page, and a Hindi or accented note would stop every save.
#
# On a Mac this does nothing: there a missing python3 opens Apple's install window when it is run,
# so it is never tried here (the installer's machine check handles that case).
# install.sh carries the same block, because it runs before the brain exists. A test keeps them equal.

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
