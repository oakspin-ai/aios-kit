#!/usr/bin/env python3
"""Block commits that look like they contain patient data.

Installed as .aios/industry/patient_data_guard.py. The brain's check (.aios/tools/check.py) calls
scan_text on every save, on saves folded in from other devices and on documents gather.py screens.
It also runs alone: `patient_data_guard.py --staged`, or on files: `patient_data_guard.py a.md b.md`. Exits 1 and lists each finding when something
matches. It catches numbers and labelled fields, not names written in free text, so the rule
"no patient data" still applies in full. Add `guard: allow` to a line that is a deliberate,
non-patient exception, such as the hospital's public phone number.
"""
import re
import subprocess
import sys

ALLOW = 'guard: allow'
# A labelled value is a placeholder, not data, only when the whole value is one: nothing at all,
# blanks (___), a lowercase field name in brackets or braces ([name], {{uhid}}, <date of birth>),
# or the word placeholder. A field name has letters only: "[2024/0457]", "[Robin Example]", "_Robin_"
# or "<b>Robin</b>" are data.
PLACEHOLDER = re.compile(r'\s*(?:'
                         r'|_+'
                         r'|\[[a-z _-]*\]'
                         r'|\{\{?[a-z _-]*\}?\}'
                         r'|<[a-z _-]*>'
                         r'|\(?placeholder\)?'
                         r')\s*[.,;]?\s*$')

# A number inside a hex code (a key fingerprint, a commit id) is not a phone or ID number: see in_code.
NUMBER_CHECKS = [
    ('phone number', re.compile(r'(?<![\d-])(?:\+91[\s-]?|0)?[6-9]\d{4}[\s-]?\d{5}(?![\d-])')),
    ('Aadhaar-like number', re.compile(r'(?<![\d-])[2-9]\d{3}[\s-]\d{4}[\s-]\d{4}(?![\d-])|(?<!\d)[2-9]\d{11}(?!\d)')),
    ('ABHA number', re.compile(r'(?<![\d-])\d{2}-\d{4}-\d{4}-\d{4}(?![\d-])|(?<!\d)\d{14}(?!\d)')),
    ('ABHA address', re.compile(r'\b[\w.]+@(?:abdm|sbx)\b', re.I)),
]

LABELS = [
    ('hospital ID', r'UHID|MRN|CR\s*No|IP\s*No|OP\s*No|IPD\s*No|OPD\s*No|Reg(?:istration)?\s*No|Bed\s*No'),
    ('patient name', r"Patient(?:'s)?\s+name|Pt\.?\s+name|Name\s+of\s+(?:the\s+)?patient"),
    ('date of birth', r'DOB|D\.O\.B\.?|Date\s+of\s+birth'),
    ('patient phone', r'(?:Patient|Attendant|Relative)(?:\'s)?\s+(?:phone|mobile|contact)'),
]
LABEL_CHECKS = [(what, re.compile(rf'\b(?:{pattern})(?!\w)\s*[:#.\-=]\s*(?P<value>.*)', re.I))
                for what, pattern in LABELS]


def in_code(text, start, end):
    """True when the match sits inside a hex code (a key fingerprint, a commit id): the whole run of
    letters and digits around it is 16 or more hex characters with at least one letter."""
    while start > 0 and text[start - 1].isascii() and text[start - 1].isalnum():
        start -= 1
    while end < len(text) and text[end].isascii() and text[end].isalnum():
        end += 1
    token = text[start:end]
    return len(token) >= 16 and re.fullmatch(r'[0-9A-Fa-f]+', token) is not None and re.search(r'[A-Fa-f]', token) is not None


def mask(text):
    return re.sub(r'[A-Za-z0-9]', '•', text[:24])


def scan_text(text):
    """Return (line number, what, masked match) for each finding."""
    findings = []
    for number, line in enumerate(text.splitlines(), 1):
        if ALLOW in line:
            continue
        for what, check in NUMBER_CHECKS:
            for match in check.finditer(line):
                if not in_code(line, match.start(), match.end()):
                    findings.append((number, what, mask(match.group(0))))
        for what, check in LABEL_CHECKS:
            match = check.search(line)
            if match and not PLACEHOLDER.fullmatch(match.group('value')):
                findings.append((number, what, mask(match.group('value').strip())))
    return findings


def staged_files():
    out = subprocess.run(['git', 'diff', '--cached', '--name-only', '--diff-filter=ACMR', '-z'],
                         capture_output=True, check=True).stdout
    for name in filter(None, out.decode().split('\0')):
        blob = subprocess.run(['git', 'show', f':{name}'], capture_output=True, check=True).stdout
        yield name, blob


def disk_files(paths):
    for path in paths:
        with open(path, 'rb') as handle:
            yield path, handle.read()


def main(argv):
    files = staged_files() if argv[:1] == ['--staged'] else disk_files(argv)
    found = 0
    for name, blob in files:
        if b'\0' in blob[:8000]:
            continue  # binary files are out of scope here; never commit scans or photos
        for number, what, shown in scan_text(blob.decode('utf-8', 'replace')):
            print(f'{name}:{number}: looks like a {what} ({shown})')
            found += 1
    if found:
        print(f'\nBlocked: {found} possible patient detail(s). Remove them and save again. '
              f'Patient records belong in the hospital system, not in this brain.')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
