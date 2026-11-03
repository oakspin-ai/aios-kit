#!/usr/bin/env python3
"""Build the pipeline page (clients/pipeline.md) from the client cards, and say when it has drifted from them.

  python3 .aios/tools/pipeline.py            # rebuild clients/pipeline.md from clients/*/meta.yml and memory/follow-ups.md
  python3 .aios/tools/pipeline.py --check    # exit 1 when the page does not match the cards (used by check.py)
  python3 .aios/tools/pipeline.py --age      # one line on stderr when the page is older than today, else nothing

The page is generated, never edited by hand. Every row comes from one client card: `stage` picks the section
(client, prospect, partner, past), `waiting_on` moves a prospect to "Waiting on them", `status_updated` is the
row's as-of date, `next_action` its next move. A row is flagged when its card has not been updated for more than
14 days, when `next_action_due` or an open follow-up for that client is overdue, or when the card has no date.

The page records the day it was generated and its flags are as of that day. The check regenerates with that
same day, so a quiet night never fails a save and a card change without a rebuild always does. Autosave rebuilds
the page on the main computer before every save; the session-start hook says when the page is older than today.
"""
import json
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PAGE = 'clients/pipeline.md'
FOLLOWUPS = 'memory/follow-ups.md'
LIMIT = 14
KEY = re.compile(r'([A-Za-z_][\w-]*):(?:[ \t]+(.*))?\Z')
GENERATED = re.compile(r'Generated (\d{4}-\d{2}-\d{2}) from the client cards')
PIPE = '&#124;'
CLOSED = ('done', 'dropped', 'closed', 'cancelled', 'canceled')


def _decode(raw):
    raw = raw.strip()
    if raw[:1] == '"':
        try:
            value, end = json.JSONDecoder().raw_decode(raw)
            if isinstance(value, str) and raw[end:].strip()[:1] in ('', '#'):
                return value
        except ValueError:
            pass
        return raw.strip('"')
    m = re.fullmatch(r"'((?:[^']|'')*)'\s*(?:#.*)?", raw)
    if m:
        return m.group(1).replace("''", "'")
    if raw[:1] == "'":
        return ''
    return re.sub(r'(?:^|\s+)#.*\Z', '', raw)


def parse_card(text):
    card = {}
    for line in text.split('\n'):
        m = KEY.match(line.rstrip('\r'))
        if m:
            card[m.group(1)] = _decode(m.group(2) or '')
    return card


def value(card, key):
    v = (card.get(key) or '').strip()
    return '' if not v or v.startswith('<') or v.upper() in ('UNKNOWN', 'TBD', 'N/A', 'YYYY-MM-DD') else v


def day(text):
    try:
        return date.fromisoformat(text.strip()[:10]).isoformat()
    except (ValueError, AttributeError):
        return None


def cell(text):
    return ' '.join((text or '').split()).replace('|', PIPE) or '—'


def first_sentence(text, limit=170):
    text = ' '.join((text or '').split())
    out = text
    for m in re.finditer(r'[.!?]["”’]?(?=\s|$)', text):
        candidate = text[:m.end()]
        if candidate.count('"') % 2 == 0:
            out = candidate
            break
    return out if len(out) <= limit else out[:limit - 1].rstrip() + '…'


def money(value):
    """A plain dollar figure (`4800`, `$4,800`, `500/mo`), else a dash; a sentence with a number in it is not an amount."""
    m = re.fullmatch(r'\$?\s*(\d[\d,]*(?:\.\d+)?)\s*(?:/mo|/month|per month)?', (value or '').split('#')[0].strip())
    n = int(float(m.group(1).replace(',', ''))) if m else 0
    return f'${n:,}' if n > 0 else '—'


class Source:
    """The brain's files, from the working tree or from the files about to be saved (the git index)."""

    def __init__(self, root, staged=False):
        self.root, self.staged = Path(root), staged

    def read(self, rel):
        if self.staged:
            out = subprocess.run(['git', '-C', str(self.root), 'show', f':{rel}'], capture_output=True)
            if out.returncode == 0:
                return out.stdout.decode('utf-8', 'replace')
            return None
        p = self.root / rel
        return p.read_text(encoding='utf-8', errors='replace') if p.is_file() else None

    def cards(self):
        if self.staged:
            out = subprocess.run(['git', '-C', str(self.root), 'ls-files', '-z', '--', 'clients'], capture_output=True)
            paths = [p for p in out.stdout.decode('utf-8', 'surrogateescape').split('\0') if re.fullmatch(r'clients/[^/]+/meta\.yml', p)]
        else:
            paths = [p.relative_to(self.root).as_posix() for p in self.root.joinpath('clients').glob('*/meta.yml')]
        return [(p.split('/')[1], parse_card(self.read(p) or '')) for p in sorted(paths)]


def section(card):
    stage = value(card, 'stage').lower()
    if not stage or not value(card, 'company'):
        return None  # an unfilled template card
    if stage in ('past', 'parked', 'lost', 'retired', 'archived'):
        return 'past'
    if stage == 'partner':
        return 'partners'
    if stage in ('client', 'active-client'):
        return 'clients'
    if value(card, 'waiting_on'):
        return 'waiting'
    return 'play'


def open_followups(slug, rows):
    tag = f'clients/{slug}/'
    return sorted((r for r in rows if tag in r['what'] or tag in r['source']), key=lambda r: (r['due'] or '9999', r['what']))


def read_followups(text):
    rows = []
    for line in (text or '').split('\n'):
        if not line.startswith('|') or line.startswith('|---'):
            continue
        cells = [c.strip() for c in line.strip().strip('|').split('|')]
        if len(cells) != 5 or cells == ['Owner', 'What', 'Due', 'Source', 'Status']:
            continue
        owner, what, due, source, status = cells
        if status.lower().startswith(CLOSED):
            continue
        rows.append({'owner': owner, 'what': what, 'due': day(due), 'source': source})
    return rows


def flags(card, opens, today, limit=LIMIT):
    out = []
    as_of = day(value(card, 'status_updated'))
    if as_of is None:
        out.append('⚠ no date on the card')
    elif (date.fromisoformat(today) - date.fromisoformat(as_of)).days > limit:
        out.append(f'⚠ not updated since {as_of}, needs your check')
    due = day(value(card, 'next_action_due'))
    if due and due < today:
        out.append(f'⚠ next action was due {due}')
    overdue = [r for r in opens if r['due'] and r['due'] < today]
    if overdue:
        out.append(f"⚠ follow-up overdue since {overdue[0]['due']}")
    return out


def table(header, rows):
    out = ['| ' + ' | '.join(header) + ' |', '|' + '---|' * len(header)]
    out += ['| ' + ' | '.join(r) + ' |' for r in rows]
    return '\n'.join(out)


def summary(flag_cells):
    n = sum(1 for f in flag_cells if '⚠' in f)
    return f'{n} of {len(flag_cells)} rows flagged.' if flag_cells else 'No rows yet.'


def render(today, source):
    followups = read_followups(source.read(FOLLOWUPS))
    by = {'clients': [], 'play': [], 'waiting': [], 'partners': [], 'past': []}
    for slug, card in source.cards():
        s = section(card)
        if s:
            by[s].append((slug, card))
    for k in by:
        by[k].sort(key=lambda sc: (day(value(sc[1], 'status_updated')) or '0000', value(sc[1], 'company').lower()), reverse=True)

    def rows(items, extra=None):
        out, fl = [], []
        for slug, card in items:
            opens = open_followups(slug, followups)
            f = flags(card, opens, today)
            fl.append('; '.join(f) if f else '—')
            name = f"**[{cell(value(card, 'company'))}]({slug}/meta.yml)**"
            contact = cell(value(card, 'contact'))
            cells = [name + (f' ({contact})' if contact != '—' else '')]
            if extra == 'value':
                cells.append(money(value(card, 'value')))
            elif extra == 'waiting':
                cells.append(cell(value(card, 'waiting_on')))
            opens_text = f"{len(opens)} open, next due {opens[0]['due']}" if opens and opens[0]['due'] else (f'{len(opens)} open' if opens else 'none')
            cells += [day(value(card, 'status_updated')) or 'unknown', cell(first_sentence(value(card, 'next_action'))), opens_text, fl[-1]]
            out.append(cells)
        return out, fl

    clients, c_fl = rows(by['clients'], 'value')
    play, p_fl = rows(by['play'], 'value')
    waiting, w_fl = rows(by['waiting'], 'waiting')
    partners, pa_fl = rows(by['partners'])
    past = [[f"**[{cell(value(card, 'company'))}]({slug}/meta.yml)**", cell(first_sentence(value(card, 'note') or value(card, 'next_action') or 'no reason recorded', 220)),
             day(value(card, 'status_updated')) or 'unknown'] for slug, card in by['past']]
    live = ['Who', 'Value', 'As of', 'Next move', 'Follow-ups', 'Flags']
    return '\n'.join([
        '# Pipeline',
        '',
        f'> Generated {today} from the client cards by the brain. **Do not edit this page.** Change the client\'s `meta.yml` (`stage`, '
        '`waiting_on`, `next_action`, `next_action_due`, `status_updated`) or `memory/follow-ups.md`; the page is rebuilt at every save on your main '
        f'computer, and a save fails when it does not match the cards. Flags (⚠) are as of the generated date: a card untouched for more than {LIMIT} days, '
        'an overdue next action or follow-up, or no date at all. **As of** is the card\'s `status_updated`.',
        '',
        '## Clients', '', table(live, clients), '', summary(c_fl), '',
        '## In play', '', table(live, play), '', summary(p_fl), '',
        '## Waiting on them', '', 'The next move is theirs. Clear `waiting_on` on the card when the ball comes back.', '',
        table(['Who', 'Waiting on', 'As of', 'Next move', 'Follow-ups', 'Flags'], waiting), '', summary(w_fl), '',
        '## Partners', '', table(['Who', 'As of', 'Next move', 'Follow-ups', 'Flags'], partners), '', summary(pa_fl), '',
        '## Past', '', 'Stage `past`. No flags: these are closed. Reopen by changing the card.', '',
        table(['Who', 'Why', 'Since'], past), '',
    ])


def generated_on(text):
    m = GENERATED.search(text or '')
    return m.group(1) if m else None


def build(root=ROOT, today=None):
    text = render(today or date.today().isoformat(), Source(root))
    path = Path(root) / PAGE
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding='utf-8')
    return text


def problems(root=ROOT, staged=False):
    """Plain-English reasons the page does not match the cards (empty when it does)."""
    source = Source(root, staged)
    actual = source.read(PAGE)
    if actual is None:
        return [f'{PAGE} is missing: run python3 .aios/tools/pipeline.py to build it from the client cards.']
    generated = generated_on(actual)
    if not generated:
        return [f'{PAGE} was written by hand: run python3 .aios/tools/pipeline.py to rebuild it from the client cards.']
    expected = render(generated, source)
    if expected == actual:
        return []
    exp, act = expected.split('\n'), actual.split('\n')
    at = next((i for i, (e, a) in enumerate(zip(exp, act)) if e != a), min(len(exp), len(act)))
    # the line itself is not quoted: a card can hold something the save check is about to refuse
    return [f'{PAGE} does not match the client cards (line {at + 1} differs). '
            'Change the card, not the page, then run python3 .aios/tools/pipeline.py and save again.']


def age_line(root=ROOT, today=None):
    text = Source(root).read(PAGE)
    generated = generated_on(text)
    if not generated:
        return ''
    days = (date.fromisoformat(today or date.today().isoformat()) - date.fromisoformat(generated)).days
    if days <= 0:
        return ''
    return f'The pipeline page ({PAGE}) was generated {days} day{"s" if days != 1 else ""} ago; its flags are as of {generated}. It is rebuilt at your next save.'


def main(argv):
    if argv[:1] == ['--check']:
        found = problems(staged='--staged' in argv)
        print('\n'.join(found))
        return 1 if found else 0
    if argv[:1] == ['--age']:
        line = age_line()
        if line:
            print(line, file=sys.stderr)
        return 0
    build()
    print(f'{PAGE} rebuilt from the client cards.')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
