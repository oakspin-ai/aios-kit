#!/usr/bin/env python3
"""Rewrite the front page of the brain (README.md) from the files, so the owner always has one place
to look: what it knows, what is ready for review, what it is handling, what it needs from them.

  python3 .aios/tools/frontpage.py

Runs before every save (autosave.sh) and at the end of /start, so the page is as current as the last
save. Only the block between the frontpage markers is touched; the rest of README.md is the owner's.
Plain words, no file paths the owner has to decode, nothing private: it reads the brain only.
"""
import datetime
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

BEGIN, END = '<!-- aios:frontpage-begin -->', '<!-- aios:frontpage-end -->'
FACT_FILES = ['company/identity.md', 'company/services.md', 'company/customers.md', 'company/people.md']
ROW = re.compile(r'^\|(?!\s*-)(?!\s*Fact\b)([^|]*)\|([^|]*)\|([^|]*)\|([^|]*)\|([^|]*)\|\s*$')


def fact_rows():
    """Yield (file, fact, value, source, date, status) for every filled row in the company fact tables."""
    for name in FACT_FILES:
        path = ROOT / name
        if not path.exists():
            continue
        for line in path.read_text(encoding='utf-8').splitlines():
            m = ROW.match(line)
            if not m:
                continue
            fact, value, source, date, status = (g.strip() for g in m.groups())
            if not value or status.lower() in ('', 'status', 'example'):
                continue
            yield name, fact, value, source, date, status.lower()


def what_i_know():
    confirmed = [r for r in fact_rows() if r[5] == 'confirmed']
    lines = []
    for name, fact, value, source, date, status in confirmed[:6]:
        lines.append(f'- {fact}: {value} (you confirmed this{", " + date if date else ""}).')
    if len(confirmed) > 6:
        lines.append(f'- And {len(confirmed) - 6} more confirmed facts across the company pages.')
    clients = sorted(p.name for p in (ROOT / 'clients').iterdir() if p.is_dir()) if (ROOT / 'clients').exists() else []
    if clients:
        lines.append(f'- {len(clients)} client or prospect folder(s): {", ".join(clients[:8])}{", ..." if len(clients) > 8 else ""}.')
    skills = sorted(p.stem for p in (ROOT / 'skills').glob('*.md')) if (ROOT / 'skills').exists() else []
    if skills:
        lines.append(f'- Tasks I have been taught: {", ".join(skills)}.')
    return lines or ['- Nothing yet. Say "set up my company brain" or type `/start`.']


def ready_for_review():
    folder = ROOT / 'inbox/review'
    if not folder.exists():
        return ['- Nothing waiting.']
    drafts = sorted((p for p in folder.glob('*.md') if p.name != 'README.md'), key=lambda p: p.name, reverse=True)
    lines = []
    for p in drafts[:10]:
        first = next((l.lstrip('# ').strip() for l in p.read_text(encoding='utf-8').splitlines() if l.strip()), p.stem)
        lines.append(f'- {first} (in the review folder as {p.name}).')
    if len(drafts) > 10:
        lines.append(f'- And {len(drafts) - 10} more in the review folder.')
    return lines or ['- Nothing waiting.']


def work_in_hand():
    """No scheduled jobs ship with this engine yet, so nothing runs while the owner is away."""
    return ['- No recurring jobs set up yet.'], []


def questions_for_you(extra):
    lines = list(extra)
    unconfirmed = [r for r in fact_rows() if r[5] in ('imported', 'inferred')]
    for name, fact, value, source, date, status in unconfirmed[:8]:
        where = f' (from {source}{", " + date if date else ""})' if source else ''
        lines.append(f'- Is this right? {fact}: {value}{where}. Say yes or correct it.')
    if len(unconfirmed) > 8:
        lines.append(f'- And {len(unconfirmed) - 8} more unconfirmed facts; ask me to read them out.')
    inbox = sorted(p for p in (ROOT / 'inbox').glob('*.md') if p.name != 'README.md') if (ROOT / 'inbox').exists() else []
    for p in inbox[:5]:
        lines.append(f'- Something in the inbox needs a home: {p.stem}.')
    return lines or ['- None.']


def render():
    handling, job_questions = work_in_hand()
    stamp = datetime.datetime.now().astimezone().strftime('%Y-%m-%d %H:%M')
    parts = [BEGIN,
             '## What I know', *what_i_know(), '',
             '## Ready for your review', *ready_for_review(), '',
             '## Work I am handling for you', *handling, '',
             '## Questions for you', *questions_for_you(job_questions), '',
             f'_Updated {stamp} from the files in this brain._',
             END]
    return '\n'.join(parts)


def main() -> int:
    readme = ROOT / 'README.md'
    text = readme.read_text(encoding='utf-8')
    if BEGIN not in text or END not in text:
        print('README.md has no front page block; nothing changed.')
        return 1
    head, rest = text.split(BEGIN, 1)
    _, tail = rest.split(END, 1)
    readme.write_text(head + render() + tail, encoding='utf-8')
    print('Front page updated.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
