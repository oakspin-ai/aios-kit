#!/usr/bin/env python3
"""OakSpin AI-OS checks for a company brain.

  python3 .aios/tools/check.py            # structure + fact status + secret scan of tracked files
  python3 .aios/tools/check.py --staged   # same, on the files about to be committed (pre-commit)
  python3 .aios/tools/check.py --scan FILE [FILE ...]   # secret scan only, on given files

Exit 0 when clean, 1 with a plain-English list of problems. This is a backstop, not the privacy
promise: the private folder lives outside the repository and the interview screens material before
it is read. Patterns here catch the obvious leaks (keys, tokens, cards, private keys, passwords, bank
account and routing numbers next to a bank word, IBANs, social security numbers).

An industry pack adds its own checks as .aios/industry/*.py, each with a scan_text(text) function
that returns (line number, what it looks like, masked value) for every finding. They run wherever
this scan runs: on every save, when a save from another device is folded in, after an upgrade, and
when gather.py screens documents. When aios.yml names a pack, its checks must load; a missing,
broken or incomplete pack check is a problem, never a pass. A file that cannot be read is a problem
too. Every file is scanned, whatever its name or encoding; only the engine's own code is skipped.

AIOS_BRAIN_ROOT names the brain when this script runs from a copy of the engine taken before a
merge (fold.sh does this, so an incoming save cannot bring the checker that judges it).
"""
import os
import importlib.util
import json
import re
import subprocess
import sys
from pathlib import Path

ENGINE = Path(__file__).resolve().parents[1]   # the .aios folder this check came from
ROOT = Path(os.environ.get('AIOS_BRAIN_ROOT') or ENGINE.parent).resolve()
sys.dont_write_bytecode = True  # importing a sibling tool must not leave a cache file in the engine folder for the save to pick up
sys.path.insert(0, str(Path(__file__).resolve().parent))

REQUIRED = [
    'AGENTS.md', 'CLAUDE.md', '.agents/skills/start/SKILL.md', 'README.md', 'aios.yml', '.aios/VERSION', '.aios/interview.json',
    'profile.md', 'rules.md', 'feedback.md',
    'company/identity.md', 'company/services.md', 'company/customers.md', 'company/people.md',
    'company/access.md', 'company/tools.md', 'clients/README.md', 'skills/README.md',
    'memory/README.md', 'inbox/README.md', 'inbox/review/README.md',
]
STATUSES = {'confirmed', 'imported', 'inferred', 'example'}
SCAN_SUFFIXES = {'.md', '.yml', '.yaml', '.json', '.txt', '.csv', '.html', '.py', '.sh', '.env'}
DOCUMENTS = ('.pdf', '.docx', '.xlsx', '.pptx')   # compressed: read through gather.readings

SECRET_PATTERNS = [
    ('private key block', re.compile(r'-----BEGIN [A-Z ]*PRIVATE KEY-----')),
    ('AWS access key', re.compile(r'\bAKIA[0-9A-Z]{16}\b')),
    ('GitHub token', re.compile(r'\bgh[pousr]_[A-Za-z0-9]{30,}\b')),
    ('Slack token', re.compile(r'\bxox[abprs]-[A-Za-z0-9-]{10,}\b')),
    ('API key (sk-...)', re.compile(r'\bsk-(?:ant-|proj-|live-)?[A-Za-z0-9_-]{20,}\b')),
    ('Stripe key', re.compile(r'\b(?:pk|rk)_(?:live|test)_[A-Za-z0-9]{16,}\b')),
    ('Google API key', re.compile(r'\bAIza[0-9A-Za-z_-]{35}\b')),
    ('password assignment', re.compile(r'(?i)\b(?:password|passwd|pwd)\s*[:=]\s*\S{6,}')),
    ('bearer token', re.compile(r'(?i)\bbearer\s+[A-Za-z0-9._-]{20,}')),
    # A card is written as one run of digits or in the usual groups (4-4-4-4, 4-6-5). Any spacing
    # looser than that joins neighbouring spreadsheet cells into false alarms.
    ('card number', re.compile(r'(?<![\d.,])(?:[3-6]\d{12,18}|[3-6]\d{3}(?:[ -]\d{4}){2}[ -]\d{1,7}|3\d{3}[ -]\d{6}[ -]\d{5})(?![\d.,])')),
    # Bank numbers only next to a bank word. A blocked save blocks the whole session, so a bare
    # "account 10023456" (a customer or supplier account) is left alone.
    ('bank routing number', re.compile(r'(?i)\b(?:routing|aba)\s*(?:number|no\.?|#)?\s*[:#]?\s*\d{9}\b')),
    ('bank account number', re.compile(r'(?i)\b(?:bank\s+account|account\s+(?:number|no\.?|#)|acct\.?|a/c)\s*(?:number|no\.?|#)?\s*[:#]?\s*\d{8,17}\b')),
    ('IBAN', re.compile(r'\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){3,7}(?: ?[A-Z0-9]{1,3})?\b')),
    ('social security number', re.compile(r'\b(?!000|666|9\d\d)\d{3}-(?!00)\d{2}-(?!0000)\d{4}\b')),
]


def in_code(text, start, end):
    """True when the match sits inside a hex code (a key fingerprint, a commit id): the whole run of
    letters and digits around it is 16 or more hex characters with at least one letter."""
    while start > 0 and text[start - 1].isascii() and text[start - 1].isalnum():
        start -= 1
    while end < len(text) and text[end].isascii() and text[end].isalnum():
        end += 1
    token = text[start:end]
    return len(token) >= 16 and re.fullmatch(r'[0-9A-Fa-f]+', token) is not None and re.search(r'[A-Fa-f]', token) is not None


def luhn_ok(digits: str) -> bool:
    total, alt = 0, False
    for ch in reversed(digits):
        d = int(ch)
        if alt:
            d = d * 2 - 9 if d * 2 > 9 else d * 2
        total += d
        alt = not alt
    return total % 10 == 0


def declared_industry() -> str:
    try:
        text = (ROOT / 'aios.yml').read_text(encoding='utf-8', errors='replace')
    except OSError:
        return ''
    m = re.search(r'^industry:[ \t]*([^#\r\n]*)', text, re.M)
    value = (m.group(1) if m else '').strip().strip('"\'').lower()
    return '' if value in ('', 'none', '%%industry%%') else value


def industry_checks():
    """(scan functions, problems). Problems mean the pack's checks are not all running."""
    checks, problems = [], []
    folder = ENGINE / 'industry'
    modules = sorted(folder.glob('*.py'))
    pack = declared_industry()
    if pack and not modules:
        problems.append(f'the {pack} industry checks are missing from .aios/industry: run the install or upgrade again.')
    for path in modules:
        try:
            spec = importlib.util.spec_from_file_location(f'aios_industry_{path.stem}', path)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
        except Exception as err:  # any failure to load is a check that is not running
            problems.append(f'the industry check {path.name} could not load ({type(err).__name__}): run the upgrade again.')
            continue
        if not callable(getattr(module, 'scan_text', None)):
            problems.append(f'the industry check {path.name} has no scan_text: run the upgrade again.')
            continue
        checks.append(module.scan_text)
    return checks, problems


INDUSTRY_CHECKS, INDUSTRY_PROBLEMS = industry_checks()


def scan_text(text: str, name: str) -> list:
    problems = [f'{name}: not screened, because {p}' for p in INDUSTRY_PROBLEMS]
    for scan in INDUSTRY_CHECKS:
        for line, what, _ in scan(text):
            article = 'an' if what[0].lower() in 'aeiou' else 'a'
            problems.append(f'{name} line {line}: looks like {article} {what}. Remove it; it never belongs in the brain.')
    for label, pattern in SECRET_PATTERNS:
        for match in pattern.finditer(text):
            if label == 'card number':
                digits = re.sub(r'\D', '', match.group(0))
                if not (13 <= len(digits) <= 19 and luhn_ok(digits)) or in_code(text, match.start(), match.end()):
                    continue   # digits inside a hex code (a key fingerprint, a commit id) are not a card
            line = text.count('\n', 0, match.start()) + 1
            article = 'an' if label[0].lower() in 'aeiou' or label.startswith('IBAN') else 'a'
            problems.append(f'{name} line {line}: looks like {article} {label}. Remove it; it never belongs in the brain.')
            break
    return problems


def tracked_files(staged: bool) -> list:
    # -z gives every name whole: spaces and accents ("Client Notes.md", "Café.md") are neither split
    # nor quoted. --no-renames lists a moved-and-edited file as added, so its new content is read.
    args = ['git', '-C', str(ROOT), 'diff', '--cached', '--name-only', '-z', '--no-renames', '--diff-filter=ACM'] if staged \
        else ['git', '-C', str(ROOT), 'ls-files', '-z']
    out = subprocess.run(args, capture_output=True, text=True, encoding='utf-8', errors='surrogateescape')
    if out.returncode != 0:
        return None
    return [name for name in out.stdout.split('\0') if name]


def read_bytes(name: str, staged: bool):
    """The bytes the save would record (the staged copy when staged), or None when they cannot be read."""
    if staged:
        out = subprocess.run(['git', '-C', str(ROOT), 'show', f':{name}'], capture_output=True)
        return out.stdout if out.returncode == 0 else None
    try:
        return (ROOT / name).read_bytes()
    except OSError:
        return None


def read(name: str, staged: bool) -> str:
    data = read_bytes(name, staged)
    return '' if data is None else data.decode('utf-8', 'replace')


def as_text(data: bytes) -> list:
    """Every reading of a file's bytes; each is scanned and a finding in any one counts. A byte-order
    mark is never trusted, because what follows it may be written another way. UTF-8 and Latin-1
    with NUL bytes taken out (text hidden among binary or UTF-16 bytes) are always read; when the
    file has NUL bytes or a mark, both UTF-16 byte orders are read too."""
    readings = [data.decode('utf-8', 'replace'), data.replace(b'\0', b'').decode('latin-1')]
    if b'\0' in data or data[:2] in (b'\xff\xfe', b'\xfe\xff'):
        readings += [data.decode('utf-16-le', 'replace'), data.decode('utf-16-be', 'replace')]
    return list(dict.fromkeys(readings))


def document_readings(name: str, staged: bool):
    """A PDF's or Office file's readings, the same ones gather.py screens, or None when its text
    cannot all be read."""
    import tempfile
    from gather import readings   # gather imports this module; imported here, when it is needed
    data = read_bytes(name, staged)
    if data is None:
        return None
    with tempfile.TemporaryDirectory() as tmp:
        copy = Path(tmp) / ('file' + Path(name).suffix.lower())
        copy.write_bytes(data)
        try:
            return readings(copy)
        except Exception:
            return None


def scan_readings(readings: list, name: str) -> list:
    """scan_text over every reading of one file, each finding said once."""
    return list(dict.fromkeys(p for text in readings for p in scan_text(text, name)))


def engine_code(name: str) -> bool:
    """The engine's own scripts hold the patterns they look for; everything else is scanned."""
    return name.startswith(('.aios/tools/', '.aios/industry/', '.aios/hooks/')) and Path(name).suffix in ('.py', '.sh', '')


def check_structure() -> list:
    return [f'missing {name}: the brain is incomplete; run the install again.' for name in REQUIRED if not (ROOT / name).exists()]


def check_fact_tables(names: list, staged: bool) -> list:
    """Every fact row in company/*.md must carry a status the engine understands."""
    problems = []
    row = re.compile(r'^\|(?!\s*-)(?!\s*Fact\b)([^|]*)\|([^|]*)\|([^|]*)\|([^|]*)\|([^|]*)\|\s*$')
    for name in names:
        if not (name.startswith('company/') and name.endswith('.md')):
            continue
        fact_table = False
        for i, line in enumerate(read(name, staged).splitlines(), 1):
            if re.match(r'^\|\s*Fact\s*\|\s*Value\s*\|\s*Source\s*\|\s*Date\s*\|\s*Status\s*\|\s*$', line):
                fact_table = True   # rows below belong to a fact table until the table ends
                continue
            if not line.startswith('|'):
                fact_table = False
            m = row.match(line)
            if not m:
                continue
            status = m.group(5).strip().lower()
            if status == 'status':  # table header row
                continue
            if fact_table and not status and any(m.group(k).strip() for k in (2, 3, 4)):
                problems.append(f'{name} line {i}: a filled fact with no status. Mark it confirmed, imported or inferred.')
                continue
            if status and status not in STATUSES:
                problems.append(f'{name} line {i}: status "{status}" is not one of confirmed, imported, inferred.')
    return problems


def check_pipeline(staged: bool) -> list:
    """clients/pipeline.md is generated from the client cards; a page that does not match them is stale and must not be saved."""
    try:
        import pipeline
    except ImportError:
        return ['.aios/tools/pipeline.py is missing: the brain is incomplete; run the install again.']
    return pipeline.problems(ROOT, staged)


def check_onboarding() -> list:
    path = ROOT / 'memory/onboarding.json'
    if not path.exists():
        return []
    try:
        json.loads(path.read_text(encoding='utf-8'))
    except ValueError as err:
        return [f'memory/onboarding.json is not valid: {err}. The interview cannot resume until it is fixed.']
    return []


def main(argv: list) -> int:
    if argv[:1] == ['--scan']:
        from gather import readings
        problems = []
        for f in argv[1:]:
            found = readings(Path(f)) if Path(f).suffix.lower() in DOCUMENTS else as_text(Path(f).read_bytes())
            if found is None:
                problems.append(f'{f}: its text could not all be read, so it was not checked.')
            else:
                problems += scan_readings(found, f)
    else:
        staged = argv[:1] == ['--staged']
        names = tracked_files(staged)
        if names is None:
            print('Could not list the files to check, so nothing was checked. Nothing may be saved until it can.')
            return 1
        problems = check_structure() + check_onboarding() + INDUSTRY_PROBLEMS
        texts = {}
        for name in names:
            if not staged and not os.path.lexists(ROOT / name):
                continue   # tracked but deleted here: a deletion is not content to scan
            data = read_bytes(name, staged)
            if data is None:
                problems.append(f'{name}: could not be read, so it was not checked. Nothing was saved.')
            else:
                texts[name] = as_text(data)
        problems += check_fact_tables([n for n in texts], staged) + check_pipeline(staged)
        # PDFs and Office files are compressed: their text is pulled out the same way gather.py does it
        # and scanned with the file's own bytes, and a file whose text cannot all be read is a problem,
        # never a pass
        for name in [n for n in texts if Path(n).suffix.lower() in DOCUMENTS]:
            found = document_readings(name, staged)
            if found is None:
                problems.append(f'{name}: its text could not all be read, so it was not checked. Keep it outside the brain and read it where it is.')
                del texts[name]
            else:
                texts[name] = found
        for name, readings in texts.items():
            if engine_code(name):
                continue
            problems += [p for p in scan_readings(readings, name) if 'not screened, because' not in p]
    if problems:
        print('\n'.join(problems))
        return 1
    print('brain check passed')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
