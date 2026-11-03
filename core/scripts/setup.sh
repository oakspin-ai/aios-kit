#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
[ ! -f .aios/tools/python.sh ] || . .aios/tools/python.sh
python3 -c 'import sys; assert sys.version_info >= (3,9), "Python 3.9+ required"'
git rev-parse --git-dir >/dev/null
chmod +x .aios/hooks/pre-commit .aios/tools/check.py
git config --local core.hooksPath .aios/hooks
# On Windows, saves keep Unix line endings and Git never rewrites files with Windows ones. Git for Windows
# otherwise does, when a save from another device comes in, and sh can no longer run the hooks.
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) git config --local core.autocrlf input; git config --local core.safecrlf false ;;
esac
python3 .aios/tools/check.py
branch=$(git branch --show-current 2>/dev/null || echo main)
[ "$branch" = main ] || printf '%s\n' "Note: this session is on branch '$branch'. /save folds it into main; this brain keeps one line of history."
printf '%s\n' 'Brain checks active.'
