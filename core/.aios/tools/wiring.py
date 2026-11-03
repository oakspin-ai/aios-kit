#!/usr/bin/env python3
"""Does a save from another device change how the brain itself works?

  python3 .aios/tools/wiring.py BASE REF

Looks at what REF changes since it left BASE. Exit 0: only the owner's everyday content (company
facts, clients, memory, inbox), which folds into main on its own. Exit 3: it changes the brain's
wiring (its rules, what runs automatically, the engine, skills, permissions, what stays private,
or anything else), which waits for the owner's yes; the changes are listed in plain words. Any
doubt (git fails, a shortcut or program inside an owner folder) also exits 3: held, never folded.

A phone or cloud session is the easiest place to slip something into a brain. Everyday notes from
there are welcome; changes to how the brain behaves are not taken on trust.
"""
import subprocess
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

CONTENT = ('company/', 'clients/', 'memory/', 'inbox/')
# Inside company/, but they decide what the brain may do and what it must never read.
HELD_IN_CONTENT = {
    'company/permissions.md': 'what the brain may do without asking',
    'company/access.md': 'what stays private',
}
# Claude and Codex read these as instructions in any folder, not only at the top of the brain.
INSTRUCTION_NAMES = {'claude.md', 'claude.local.md', 'agents.md', 'agents.override.md', 'skill.md'}
PLAIN_FILE, NO_FILE = '100644', '000000'
GROUPS = [
    ("the brain's rules", lambda p: Path(p).name in INSTRUCTION_NAMES - {'skill.md'}),
    ('what runs automatically', lambda p: p.startswith(('.aios/hooks/', '.githooks/', '.codex/hooks'))
        or p in ('.claude/settings.json', '.claude/settings.local.json', '.codex/hooks.json')),
    ('skills', lambda p: p.startswith(('.claude/skills/', '.agents/skills/', 'skills/')) or Path(p).name == 'skill.md'),
    ('commands', lambda p: p.startswith(('.claude/commands/', '.codex/'))),
    ('the engine', lambda p: p.startswith('.aios/')),
]


def classify(entries) -> list:
    """entries: (old mode, new mode, status, path). Returns (plain-English group, path) for each
    change that is wiring; an empty list means everyday content only."""
    held = []
    for old, new, _status, path in entries:
        if not path.isprintable():  # a line break or control character in a name is never everyday
            held.append(('a file with an unreadable name', path))
            continue
        # A Mac treats "Permissions.md" and "permissions.md" as one file (and accents written two
        # ways as one letter), so every comparison is made on that folded form.
        key = unicodedata.normalize('NFC', path).casefold()
        if key in HELD_IN_CONTENT:
            held.append((HELD_IN_CONTENT[key], path))
            continue
        parts = key.split('/')
        # an ordinary file added, changed or removed; a shortcut, program or sub-repository is not
        plain = {old, new} <= {PLAIN_FILE, NO_FILE}
        hidden = any(part.startswith('.') for part in parts)  # .claude, .agents, .codex, .git* ...
        if key.startswith(CONTENT) and plain and not hidden and parts[-1] not in INSTRUCTION_NAMES:
            continue
        held.append((next((name for name, match in GROUPS if match(key)), 'other files'), path))
    return held


def shown(path: str, limit: int = 120) -> str:
    """A file name as it is safe to print: no line breaks or control characters, never too long."""
    safe = ''.join(ch if ch.isprintable() else f'\\x{ord(ch):02x}' if ord(ch) < 256 else '?' for ch in path)
    return safe if len(safe) <= limit else safe[:limit - 3] + '...'


def changes(base: str, ref: str) -> list:
    out = subprocess.run(['git', '-C', str(ROOT), 'diff', '--raw', '-z', '--no-renames', '--no-abbrev', f'{base}...{ref}'],
                         capture_output=True, text=True, encoding='utf-8', errors='surrogateescape')
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip() or 'git could not compare the two saves')
    parts, entries = out.stdout.split('\0'), []
    for meta, path in zip(parts[0::2], parts[1::2]):
        fields = meta.lstrip(':').split()
        if len(fields) < 5:
            raise RuntimeError(f'unexpected git output: {meta!r}')
        entries.append((fields[0], fields[1], fields[4], path))
    return entries


def describe(held: list, limit: int = 5) -> str:
    grouped = {}
    for label, path in held:
        grouped.setdefault(label, []).append(path)
    lines = []
    for label, paths in grouped.items():
        names = ', '.join(shown(p) for p in paths[:limit]) + (f' and {len(paths) - limit} more' if len(paths) > limit else '')
        lines.append(f'  - {label}: {names}')
    return '\n'.join(lines)


def main(argv: list) -> int:
    if len(argv) != 2:
        print('usage: wiring.py BASE REF')
        return 3
    try:
        held = classify(changes(*argv))
    except (RuntimeError, OSError) as err:
        print(f'  - could not read what it changes ({err}), so it is held')
        return 3
    if held:
        print(describe(held))
        return 3
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
