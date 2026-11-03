#!/usr/bin/env python3
"""Content digest and key fingerprint for an OakSpin AI-OS engine kit.

  python3 kitdigest.py DIR                 # sha256 digest of every file in a kit folder
  python3 kitdigest.py --tracked DIR       # same, over the files Git tracks in DIR (the release tool)
  python3 kitdigest.py --fingerprint KEY   # fingerprint of a public key (.pub, PEM)

The digest is what the release list (releases.json) names and what the updater checks before it
installs anything: the files sorted by path, one line "sha256  path" each, then the sha256 of those
lines. Both sides use this one script so they can never disagree. Left out on purpose: `.git`,
Python caches, `.DS_Store`, and the release list and its signature themselves, which cannot contain
their own digest. Standard library only; the same answer on a Mac and in the cloud.
"""
import base64
import hashlib
import subprocess
import sys
from pathlib import Path

SKIP_DIRS = {'.git', '__pycache__'}
SKIP_FILES = {'.DS_Store', 'releases.json', 'releases.json.sig'}


def _lines(root: Path, paths):
    out = []
    for rel in sorted(paths):
        p = root / rel
        if not p.is_file():
            continue
        h = hashlib.sha256()
        with p.open('rb') as f:
            for chunk in iter(lambda: f.read(1 << 16), b''):
                h.update(chunk)
        out.append(f'{h.hexdigest()}  {rel}\n')
    return out


def digest(root: Path) -> str:
    root = Path(root)
    paths = []
    for p in root.rglob('*'):
        if any(part in SKIP_DIRS for part in p.relative_to(root).parts):
            continue
        if p.is_file() and p.name not in SKIP_FILES and not p.name.endswith('.pyc'):
            paths.append(p.relative_to(root).as_posix())
    return hashlib.sha256(''.join(_lines(root, paths)).encode()).hexdigest()


def tracked_digest(root: Path) -> str:
    root = Path(root)
    out = subprocess.run(['git', '-C', str(root), 'ls-files', '-z'], capture_output=True, text=True, check=True).stdout
    paths = [rel for rel in out.split('\0') if rel and Path(rel).name not in SKIP_FILES]
    return hashlib.sha256(''.join(_lines(root, paths)).encode()).hexdigest()


def fingerprint(key_path: Path) -> str:
    """SHA256: plus the first 32 hex digits of the sha256 of the key's DER bytes."""
    body = ''.join(line.strip() for line in Path(key_path).read_text().splitlines() if not line.startswith('-----'))
    der = base64.b64decode(body)
    return 'SHA256:' + hashlib.sha256(der).hexdigest()[:32]


def main(argv):
    if len(argv) == 2 and argv[0] == '--fingerprint':
        print(fingerprint(Path(argv[1])))
    elif len(argv) == 2 and argv[0] == '--tracked':
        print(tracked_digest(Path(argv[1])))
    elif len(argv) == 1 and not argv[0].startswith('-'):
        print(digest(Path(argv[0])))
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main(sys.argv[1:])
