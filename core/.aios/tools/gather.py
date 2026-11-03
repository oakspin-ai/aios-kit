#!/usr/bin/env python3
"""Screen a folder the owner points at, BEFORE the AI reads any of it.

  python3 .aios/tools/gather.py /path/to/folder [--label quotes]

The AI never opens a chosen folder directly. It runs this first. The tool walks the folder, runs the
same secret scan as a save over every file it can read as text, and then:

  kept          copied into inbox/<label>/ for the AI to read and file
  screened out  NOT copied, NOT read; named (never quoted) in the read-back and in a note in the
                owner's private folder, so the owner knows what stayed behind and why
  unscreened    files the tool cannot read as text (scanned PDFs, images, unknown types): NOT
                copied, NOT read; named so the owner can approve them, all at once or one by one
  skipped       shortcuts (symlinks) and hidden files: NOT followed, NOT copied, NOT read; named. A
                shortcut can point anywhere, including the private folder, so it is never opened.

PDFs are screened like any other file: their text is pulled out first (with the Mac's own PDF
reader, pdftotext if installed, or a built-in reader for ordinary PDFs), and the file's own bytes
and fields (its title, author and the like) are screened with it. Only a PDF with no text in it at
all, such as a photo or scan of paper, is left unscreened. Every file's bytes are also read every
way they could be written (UTF-8, UTF-16 either way round, Latin-1), whatever mark they start with.

A file already kept in an earlier run, and unchanged since (same folder, same name, same content), is
skipped and only counted, so the owner can keep adding to the same folder and say "read my new
documents". A file that could not be screened is never counted as looked at: it is named again until
the owner decides. The folder's own note to the owner (ABOUT THIS FOLDER.md) is never gathered. The
private folder and the brain itself are never walked into, even from a folder above them. A file whose
name looks private (a phone number, a date of birth) is screened out like one whose text does.

Prints a plain-words read-back and writes a receipt to memory/receipts/. Never prints file contents.
The receipt is saved in the brain, so it names only the files that were kept; files left behind are
counted there and named only in the read-back and in the note in the private folder.
This is a backstop for keys, tokens, passwords and card or bank numbers. It cannot recognise every
kind of private information; the owner chooses the folder and hears every file name before it is
kept.
"""
import base64
import datetime
import hashlib
import io
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import zipfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from check import as_text, scan_readings, scan_text, SCAN_SUFFIXES  # noqa: E402

TEXT_SUFFIXES = (SCAN_SUFFIXES | {'.rtf', '.tsv', '.xml', '.eml', '.ics', '.vcf'}) - {'.py', '.sh', '.env'}
OFFICE_SUFFIXES = {'.docx', '.xlsx', '.pptx'}
MAX_BYTES = 5 * 1024 * 1024
SKIP_DIRS = {'.git', 'node_modules', '__pycache__', '.Trash'}
FOLDER_NOTE = 'ABOUT THIS FOLDER.md'


def local_path(raw: str, windows: bool = os.name == 'nt') -> Path:
    """A folder as this computer's Python names it. Git Bash on Windows writes C:\\Users\\ana as
    /c/Users/ana, which Windows Python reads as a folder on the current drive, so the private-folder
    guard below would never match. Both the folder asked for and the private folder go through here."""
    m = re.match(r'/([A-Za-z])(?=/|$)', raw) if windows else None
    if m:
        raw = f'{m.group(1).upper()}:/' + raw[3:]
    return Path(raw).expanduser()


def private_folder() -> Path:
    for line in (ROOT / 'aios.yml').read_text(encoding='utf-8').splitlines():
        if line.startswith('private_folder:'):
            return local_path(line.split(':', 1)[1].strip())
    return ROOT.parent / 'private'


def office_text(path: Path):
    """Word, Excel and PowerPoint files are zips of XML; pull the text out of every part, without any
    library. A file that carries anything else (a picture, an embedded file) cannot be screened in
    full, so it is None: it is asked about and read where it is, never copied into the brain."""
    parts = []
    with zipfile.ZipFile(path) as z:
        for info in z.infolist():   # each entry read by itself: two parts may share a name
            name = info.filename
            if name.endswith('/'):
                continue
            if not name.endswith(('.xml', '.rels')):
                return None
            # spreadsheet cells are kept apart with a tab, so two neighbouring numbers never read as one
            parts.append(re.sub(r'<[^>]+>', '\t' if 'xl/' in name else ' ', z.read(info).decode('utf-8', errors='ignore')))
    return '\n'.join(parts)


def office_readings(data: bytes) -> list:
    """Every part of an Office file read every way, tags, attributes, comments and UTF-16 parts
    included, and the zip wrapper's own bytes (names, notes) with the compressed parts blanked:
    those were just read decompressed, and as raw bytes they are noise."""
    out = bytearray(data)
    readings = []
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        for info in z.infolist():
            readings += as_text(z.read(info))
            if info.compress_type != zipfile.ZIP_STORED:
                name_len, extra_len = struct.unpack('<HH', data[info.header_offset + 26:info.header_offset + 30])
                start = info.header_offset + 30 + name_len + extra_len
                out[start:start + info.compress_size] = b' ' * info.compress_size
    return readings + as_text(bytes(out))


PDF_NAME = rb'/[^\s/<>\[\]()%{}]+'
PDF_STREAM = rb'(?<![A-Za-z])stream\r?\n'   # the keyword that starts a stream, never the end of "endstream"
PDF_FILTERS = (b'ASCII85Decode', b'FlateDecode', b'ASCIIHexDecode')
PICTURE_FILTERS = (b'DCTDecode', b'JPXDecode', b'JBIG2Decode', b'CCITTFaxDecode')   # decode to pixels only
# Runs of digits a PDF writes about itself that are not phone, card or ID numbers, blanked in every
# reading of a PDF except its pages: document ids (a uuid, or 32 hex characters, a length no card,
# phone, ID number or IBAN has) and real numbers (coordinates such as 1.46826472411522). In its syntax, outside strings and comments, so are names
# (/uni0915094D0937) and arrays of numbers (/Color [65535 20224 20224]). A string that is a whole,
# valid date (D:20261030120000+05'30') is the PDF's own date and is left out.
PDF_IDS = re.compile(r'\b[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\b|\b[0-9A-Fa-f]{32}\b|(?<!\d)\d+\.\d+')
PDF_SYNTAX = re.compile(r'/[^\s/<>\[\]()%{}]+|\[[\d.\s+-]*\]')
PDF_DATE = re.compile(r"[﻿\xfe\xff]*D:(?:19|20)\d\d(?:(?:0[1-9]|1[0-2])(?:(?:0[1-9]|[12]\d|3[01])(?:(?:[01]\d|2[0-3])"
                      r"(?:[0-5]\d(?:[0-5]\d)?)?)?)?)?(?:Z(?:00'?00'?)?|[+-](?:[01]\d|2[0-3])'?(?:[0-5]\d'?)?)?\s*")


def _pdf_name(name: bytes) -> bytes:
    """A name with its #xx escapes undone: /Fl#61teDecode is /FlateDecode."""
    return re.sub(rb'#([0-9A-Fa-f]{2})', lambda m: bytes([int(m.group(1), 16)]), name)


def _pdf_lex(data: bytes) -> list:
    """Split PDF syntax into ('syntax', bytes), ('string', its bytes) and ('comment', bytes). Strings
    are undone whole: nested brackets, escapes, line continuations and <hex> strings."""
    out, i, n = [], 0, len(data)
    while i < n:
        m = re.compile(rb'[%(<]').search(data, i)
        if not m:
            out.append(('syntax', data[i:]))
            break
        out.append(('syntax', data[i:m.start()]))
        i, c = m.end(), m.group(0)
        if c == b'%':
            end = re.compile(rb'[\r\n]').search(data, i)
            out.append(('comment', data[i:end.start() if end else n]))
            i = end.start() if end else n
        elif c == b'<':
            if data[i:i + 1] == b'<':
                out.append(('syntax', b'<<'))
                i += 1
                continue
            end = data.find(b'>', i)
            end = n if end < 0 else end
            digits = re.sub(rb'[^0-9A-Fa-f]', b'', data[i:end])
            out.append(('string', bytes.fromhex((digits + b'0' * (len(digits) % 2)).decode())))
            i = end + 1
        else:
            depth, buf = 1, bytearray()
            while i < n:
                m = re.compile(rb'[()\\]').search(data, i)
                if not m:
                    buf += data[i:]
                    i = n
                    break
                buf += data[i:m.start()]
                i, c = m.end(), m.group(0)
                if c == b'(':
                    depth += 1
                    buf += c
                elif c == b')':
                    depth -= 1
                    if not depth:
                        break
                    buf += c
                else:
                    e = data[i:i + 1]
                    i += 1
                    if e and e in b'01234567':
                        octal = re.match(rb'[0-7]{1,3}', data[i - 1:i + 2]).group(0)
                        buf.append(int(octal, 8) & 255)
                        i += len(octal) - 1
                    elif e == b'\r':
                        i += data[i:i + 1] == b'\n'   # a line continuation
                    elif e != b'\n':
                        buf += {b'n': b'\n', b'r': b'\r', b't': b'\t', b'b': b'\b', b'f': b'\f'}.get(e, e)
            out.append(('string', bytes(buf)))
    return out


def _pdf_syntax(raw: bytes) -> bytes:
    """The syntax alone, for reading keys: each string left as an empty (), comments taken out, and
    names' escapes undone."""
    plain = b' '.join(part if kind == 'syntax' else b'()' for kind, part in _pdf_lex(raw) if kind != 'comment')
    return re.sub(PDF_NAME, lambda m: _pdf_name(m.group(0)), plain)


def _binary(data: bytes) -> bool:
    """Mostly bytes that no text is written in: a picture, a font program, a colour table."""
    sample = data[:65536]
    return len(re.sub(rb'[\x20-\x7e\t\r\n\f]', b'', sample)) > len(sample) // 4


def _ramp(data: bytes) -> bool:
    """A colour gradient: 32 or more bytes, almost each one step from the last. Text never is one."""
    return len(data) >= 32 and sum(abs(a - b) <= 1 for a, b in zip(data, data[1:])) >= 0.8 * (len(data) - 1)


def _pdf_syntax_readings(raw: bytes) -> list:
    """Readings of PDF syntax: every string read every way (a whole date left out), the comments, and
    the syntax itself with names and arrays of numbers blanked. Strings a key marks as bytes, not text,
    are left out: document ids (/ID), colour tables (/Indexed) and encryption values (/O, /U, /Perms),
    and so are a colour gradient, and a string of bytes that are mostly not text (glyph numbers) unless
    it starts with a byte-order mark."""
    strings, comments, syntax, ids = [], [], [], False
    for kind, part in _pdf_lex(raw):
        if kind == 'string':
            before = _pdf_name(syntax[-1] if syntax else b'')
            ids = ids or re.search(rb'/ID\s*\[\s*$', before) is not None
            if not (ids or re.search(rb'/Indexed\b.*\d\s*$|/(?:O|U|OE|UE|Perms)\s*$', before, re.S)):
                if not _ramp(part) and (part[:2] in (b'\xfe\xff', b'\xff\xfe') or part[:3] == b'\xef\xbb\xbf' or not _binary(part)):
                    strings += [s for s in as_text(part) if not PDF_DATE.fullmatch(s)]
            syntax.append(b'')
        else:
            if kind == 'syntax' and part.strip():
                ids = False
            (comments if kind == 'comment' else syntax).append(part)
    return ['\n'.join(strings)] + as_text(b'\n'.join(comments)) + [PDF_SYNTAX.sub(' ', r) for r in as_text(b' '.join(syntax))]


def _pdf_dict(syntax: bytes) -> dict:
    """The keys of a dictionary itself, never those of a dictionary inside it, each with its value as
    written (a name, a number, a reference, or a whole array or dictionary). A key written twice with
    two values raises, so a second /Filter or /Columns can never decide what is read. A word where a
    key should be (a name written with a space in it) joins the value before it."""
    start = syntax.find(b'<<')
    if start < 0:
        return {}
    t = re.findall(rb'<<|>>|\[|\]|\(\)|' + PDF_NAME + rb'|[^\s/<>\[\]()]+', syntax[start + 2:])
    out, i, last = {}, 0, None
    while i < len(t) and t[i] != b'>>':
        key, i = t[i], i + 1
        if not key.startswith(b'/') and last is not None:
            out[last] += b' ' + key
            continue
        if not key.startswith(b'/') or i >= len(t) or t[i] in (b'>>', b']'):
            raise ValueError('a dictionary this reader cannot read')
        j, depth = i, 0
        while j < len(t):
            depth += t[j] in (b'<<', b'[')
            depth -= t[j] in (b'>>', b']')
            j += 1
            if depth == 0:
                break
        if j - i == 1 and j + 1 < len(t) and t[j + 1] == b'R':
            j += 2   # a reference: number, generation, R
        value = b' '.join(t[i:j])
        if out.get(key, value) != value:
            raise ValueError('a key written twice with two values')
        out[key], i, last = value, j, key
    return out


def _pdf_filters(head: bytes):
    """The names in a stream's own /Filter, or None when it is not a name or a list of names."""
    value = _pdf_dict(head).get(b'/Filter')
    if value is None:
        return []
    if re.sub(PDF_NAME + rb'|[\s\[\]]', b'', value) or value.count(b'[') > 1:
        return None
    return [x[1:] for x in re.findall(PDF_NAME, value)]


def _number(value, default: int) -> int:
    """A whole number of 1 or more, as a predictor's settings must be; anything else raises."""
    if value is None:
        return default
    if not re.fullmatch(rb'\+?\d+', value) or int(value) < 1:
        raise ValueError('a predictor setting this reader cannot read')
    return int(value)


def _predictor_params(parms: dict):
    return _number(parms.get(b'/Colors'), 1), _number(parms.get(b'/BitsPerComponent'), 8), _number(parms.get(b'/Columns'), 1)


def _tiff_undo(data: bytes, parms: dict) -> bytes:
    """Undo a TIFF predictor (/Predictor 2) for 8-bit components: each byte is added to the one a
    pixel before it in its row."""
    colors, bits, columns = _predictor_params(parms)
    if bits != 8:
        raise ValueError('a predictor this reader cannot undo')
    width, out = colors * columns, bytearray(data)
    for i in range(len(out)):
        if i % width >= colors:
            out[i] = (out[i] + out[i - colors]) & 255
    return bytes(out)


def _png_undo(data: bytes, parms: dict) -> bytes:
    """Undo a PNG predictor (/Predictor 10 to 15) row by row."""
    colors, bits, columns = _predictor_params(parms)
    step, width = max(1, colors * bits // 8), (colors * bits * columns + 7) // 8
    out, prev = bytearray(), bytearray(width)
    for i in range(0, len(data), width + 1):
        kind, row = data[i], bytearray(data[i + 1:i + 1 + width].ljust(width, b'\0'))
        for j in range(width):
            left, up, corner = row[j - step] if j >= step else 0, prev[j], prev[j - step] if j >= step else 0
            if kind == 1:
                row[j] = (row[j] + left) & 255
            elif kind == 2:
                row[j] = (row[j] + up) & 255
            elif kind == 3:
                row[j] = (row[j] + (left + up) // 2) & 255
            elif kind == 4:
                p = left + up - corner
                near = left if abs(p - left) <= abs(p - up) and abs(p - left) <= abs(p - corner) else up if abs(p - up) <= abs(p - corner) else corner
                row[j] = (row[j] + near) & 255
            elif kind:
                raise ValueError('a predictor row this reader cannot undo')
        out += row
        prev = row
    return bytes(out)


def _pdf_decode(head: bytes, body: bytes) -> bytes:
    """A stream's bytes with its filters undone. Raises on anything this reader cannot undo, so part
    of a PDF is never screened as all of it."""
    start = re.search(PDF_STREAM, body).end()
    own = _pdf_dict(head)   # the stream's own keys: a key inside a dictionary within it decides nothing
    length = re.fullmatch(rb'\d+', own.get(b'/Length', b''))
    if length and re.match(rb'\s*endstream', body[start + int(length.group(0)):]):
        raw = body[start:start + int(length.group(0))]   # its stated length, when that ends where the stream ends
    else:
        m = re.search(PDF_STREAM + rb'(.*?)\s*endstream', body, re.S)
        if not m:
            raise ValueError('a stream cut short')
        raw = m.group(1)
    filters = _pdf_filters(head)
    if filters is None:
        raise ValueError('a filter this reader cannot read')   # by reference, or not a list of names
    if any(x not in PDF_FILTERS for x in filters):
        raise ValueError('a stream this reader cannot decode')
    parms = own.get(b'/DecodeParms')
    if parms is not None and not parms.startswith(b'<<'):
        raise ValueError('decoding settings this reader cannot read')   # by reference, or one per filter
    parms = _pdf_dict(parms) if parms else {}
    predictor = _number(parms.get(b'/Predictor'), 1)
    if predictor != 1 and (not (predictor == 2 or 10 <= predictor <= 15) or filters[-1:] != [b'FlateDecode']):
        raise ValueError('a predictor this reader cannot undo')
    for f in filters:
        try:
            if f == b'ASCII85Decode':
                raw = base64.a85decode(raw.strip().removesuffix(b'~>').removeprefix(b'<~'), adobe=False)
            elif f == b'FlateDecode':
                raw = zlib.decompressobj().decompress(raw)   # as PDF readers do, a missing checksum at the end is no error
            else:
                raw = bytes.fromhex(re.sub(rb'[^0-9A-Fa-f]', b'', raw).decode())
        except Exception as err:
            raise ValueError('a stream that would not decode') from err
    return raw if predictor == 1 else _tiff_undo(raw, parms) if predictor == 2 else _png_undo(raw, parms)


def _pdf_parse(data: bytes) -> list:
    """Every object of every generation, earlier copies too, as (number, generation, its dictionary's
    syntax, its whole body). Raises when the file holds a stream outside those objects, or is encrypted."""
    found = [(m.group(1), m.group(2), _pdf_syntax(re.split(PDF_STREAM, m.group(3), 1)[0]), m.group(3))
             for m in re.finditer(rb'(?<!\d)(\d+)\s+(\d+)\s+obj\b(.*?)endobj', data, re.S)]
    if sum(re.search(PDF_STREAM, body) is not None for _, _, _, body in found) != len(re.findall(PDF_STREAM, data)):
        raise ValueError('a stream outside the objects this reader found')
    trailers = [_pdf_syntax(t) for t in re.findall(rb'trailer(.*?)(?:startxref|$)', data, re.S)]
    if any(re.search(rb'/Encrypt\b', d) for d in trailers + [h for _, _, h, _ in found if re.search(rb'/Type\s*/XRef\b', h)]):
        raise ValueError('an encrypted PDF cannot be read by this reader')
    return found


def _pdf_streams(found: list) -> list:
    """(dictionary, decoded bytes) for every stream that can hold text. A stream marked as a picture,
    font program, colour profile or table, sampled function or cross-reference table is passed over
    when it decodes to bytes that are not text; a mark alone never hides text, because a page drawn
    from a stream so marked is still scanned. A stream that cannot be decoded is passed over only
    when a picture codec packs it; otherwise it raises, as a file attached inside the PDF does."""
    streams = [(num, gen, head, body) for num, gen, head, body in found if re.search(PDF_STREAM, body)]
    packed = [_pdf_syntax(_pdf_decode(head, body)) for _, _, head, body in streams if re.search(rb'/Type\s*/ObjStm\b', head)]
    pointers = b'\n'.join([head for _, _, head, _ in found] + packed)
    pointed = set(re.findall(rb'/(?:FontFile[23]?|ICCBased|Function)\s*\[?\s*(\d+)\s+(\d+)\s+R', pointers)
                  + re.findall(rb'/Indexed\s*(?:/\w+|\[[^\]]*\]|\d+\s+\d+\s+R)\s*\d+\s+(\d+)\s+(\d+)\s+R', pointers))
    # Illustrator's private copy of the artwork, which no viewer shows: its hex dumps and curve tables
    # read as ID numbers in about 1 in 35 such PDFs, so it is passed over, as it was before
    private = set(re.findall(rb'/AIPDFPrivateData\d*\s*(\d+)\s+(\d+)\s+R', pointers))
    out = []
    for num, gen, head, body in streams:
        if re.search(rb'/Type\s*/EmbeddedFile\b', head):
            raise ValueError('a file attached inside the PDF')
        if (num, gen) in private:
            continue
        marked = (num, gen) in pointed or re.search(rb'/Subtype\s*/(?:Image|Type1C|CIDFontType0C|OpenType)\b|/Type\s*/XRef\b'
                                                    rb'|/FunctionType\b|/Length[123]\b|/Width\s*\d', head)
        try:
            decoded = _pdf_decode(head, body)
        except ValueError:
            # a mark is only a key; a picture codec (JPEG, JPEG 2000, JBIG2, fax) as the stream's own last
            # filter, on a stream that says it is a picture, is proof: it decodes to pixels and nothing
            # else. Any other stream that cannot be decoded raises.
            own, filters = _pdf_dict(head), _pdf_filters(head) or [b'']
            if (own.get(b'/Subtype') == b'/Image' or {b'/Width', b'/Height'} <= set(own)) \
                    and filters[-1] in PICTURE_FILTERS and all(f in PDF_FILTERS for f in filters[:-1]):
                continue
            raise
        if not (marked and _binary(decoded)):
            out.append((head, decoded))
    return out


def pdf_readings(data: bytes) -> list:
    """Every reading of a PDF besides its pages: the syntax outside its streams (the title, author
    and other fields, form values, bookmarks, comments) and every stream that can hold text, decoded.
    Metadata streams are read as text; every other stream as PDF syntax. Raises when part of the
    file cannot be read."""
    found = _pdf_parse(data)
    out = _pdf_syntax_readings(re.sub(PDF_STREAM + rb'.*?endstream', b'\n', data, flags=re.S))
    for head, decoded in _pdf_streams(found):
        if re.search(rb'/Type\s*/Metadata\b|/Subtype\s*/XML\b', head):
            out += as_text(decoded)
        else:
            out += _pdf_syntax_readings(decoded)
    return [PDF_IDS.sub(' ', r) for r in out]


def _pdf_strings(ops: bytes, cmap):
    """Pull the text shown by a PDF content stream: (literal) and <hex> strings under Tj, TJ, ' and \"."""
    out = []
    for kind, part in _pdf_lex(ops):
        if kind != 'string':
            out += [' ' if op != b'ET' else '\n' for op in re.findall(rb'\]\s*TJ|T\*|Td|TD|ET', part)]
            continue
        if cmap:
            width = 2 if max(len(k) for k in cmap) >= 2 and len(part) % 2 == 0 else 1
            out.append(''.join(cmap.get(part[i:i + width], '') for i in range(0, len(part), width)))
        else:
            out.append(part.decode('cp1252', errors='ignore'))
    return ''.join(out)


def _pdf_text_builtin(data: bytes) -> str:
    """A small reader for ordinary text PDFs (the kind invoicing and quoting tools make). No library.
    It reads every object of every generation, earlier copies too, and raises on anything it cannot
    account for (see _pdf_parse and _pdf_decode; objects packed in object streams too)."""
    found = _pdf_parse(data)
    if any(re.search(rb'/Type\s*/ObjStm\b', head) for _, _, head, _ in found):
        raise ValueError('objects packed in object streams cannot be reached by this reader')
    objs = {(num, gen): (head, body) for num, gen, head, body in found}   # a reference reaches the last copy
    cmaps = {}
    for key, (head, _) in objs.items():
        m = re.search(rb'/ToUnicode\s+(\d+)\s+(\d+)\s+R', head)
        if m and (m.group(1), m.group(2)) in objs:
            cm, s = {}, _pdf_decode(*objs[(m.group(1), m.group(2))])
            for blk in re.findall(rb'beginbfchar(.*?)endbfchar', s, re.S):
                for a, b in re.findall(rb'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>', blk):
                    cm[bytes.fromhex(a.decode())] = bytes.fromhex(b.decode()).decode('utf-16-be', errors='ignore')
            for blk in re.findall(rb'beginbfrange(.*?)endbfrange', s, re.S):
                for a, b, c in re.findall(rb'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>', blk):
                    lo, hi, start, n = int(a, 16), int(b, 16), int(c, 16), len(a) // 2
                    for i in range(min(hi - lo, 65535) + 1):
                        cm[(lo + i).to_bytes(n, 'big')] = chr(start + i)
            cmaps[key] = cm
    fonts = {}
    for head, _ in objs.values():
        for name, num, gen in re.findall(rb'/([^\s/<>\[\]()%{}]+)\s+(\d+)\s+(\d+)\s+R', head):
            if (num, gen) in cmaps:
                fonts[name] = cmaps[(num, gen)]
    text, cur = [], None
    for _, s in _pdf_streams(found):
        if b'BT' not in s:
            continue
        for part in re.split(rb'(/[^\s/<>\[\]()%{}]+\s+[\d.]+\s+Tf)', s):
            m = re.match(rb'/([^\s/<>\[\]()%{}]+)\s+[\d.]+\s+Tf', part)
            if m:
                cur = fonts.get(_pdf_name(m.group(1)))
                continue
            text.append(_pdf_strings(part, cur))
    return ''.join(text)


def pdf_text(path: Path):
    """Text inside a PDF, or None if it has none we can reach (a photo or scan of paper)."""
    tries = []
    if shutil.which('pdftotext'):
        tries.append(['pdftotext', '-q', '-layout', str(path), '-'])
    if sys.platform == 'darwin' and shutil.which('osascript'):
        tries.append(['osascript', '-l', 'JavaScript', '-e', 'ObjC.import("PDFKit");'
                      'var d=$.PDFDocument.alloc.initWithURL($.NSURL.fileURLWithPath(%s));'
                      'd.isNil()?"":ObjC.unwrap(d.string)' % json.dumps(str(path))])
    for cmd in tries:
        try:
            out = subprocess.run(cmd, capture_output=True, text=True, timeout=60).stdout
        except (OSError, subprocess.SubprocessError):
            continue
        if out.strip():
            return out
    try:
        out = _pdf_text_builtin(path.read_bytes())
    except Exception:
        return None
    return out if len(re.sub(r'\s', '', out)) >= 20 else None


def readable_text(path: Path):
    """Return the file's text, or None when it cannot be screened."""
    if path.stat().st_size > MAX_BYTES:
        return None
    suffix = path.suffix.lower()
    if suffix in TEXT_SUFFIXES:
        return path.read_text(errors='ignore')
    if suffix == '.pdf':
        return pdf_text(path)
    if suffix in OFFICE_SUFFIXES:
        try:
            return office_text(path)
        except (zipfile.BadZipFile, OSError, KeyError, RuntimeError, ValueError):
            return None
    return None


def readings(path: Path):
    """Every text the scan reads for a file, or None when it cannot be screened: its text (a PDF's
    pages, an Office file's text) and every other reading of it, because a PDF's title or metadata,
    an Office file's comments and attributes, and text in an unexpected encoding are not in that text."""
    text = readable_text(path)
    if text is None:
        return None
    data = path.read_bytes()
    suffix = path.suffix.lower()
    try:
        if suffix == '.pdf':
            return [text] + pdf_readings(data)
        if suffix in OFFICE_SUFFIXES:
            return [text] + office_readings(data)
    except Exception:   # any part that cannot be read leaves the whole file unscreened
        return None
    return [text] + as_text(data)


def walk(folder: Path, protected=()):
    """Yield (path, rel, kind) for every entry, never stepping through a shortcut or into a protected
    folder (the private folder, the brain)."""
    stack = [folder]
    while stack:
        current = stack.pop()
        for path in sorted(current.iterdir()):
            rel = path.relative_to(folder)
            if path.name in SKIP_DIRS:
                continue
            if not path.is_symlink() and any(path.resolve() == p for p in protected):
                yield path, rel, 'protected'
                continue
            if path.is_symlink():
                yield path, rel, 'shortcut'
            elif path.name.startswith('.'):
                if path.name not in ('.DS_Store', '.localized'):
                    yield path, rel, 'hidden'
            elif path.is_dir():
                stack.append(path)
            elif path.is_file():
                yield path, rel, 'file'


def fingerprint(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1 << 16), b''):
            h.update(chunk)
    return h.hexdigest()


def gather(folder: Path, label: str, seen: dict, protected=()) -> dict:
    kept, screened, unscreened, earlier, skipped = [], [], [], [], []
    dest = ROOT / 'inbox' / label
    for path, rel, kind in sorted(walk(folder, protected), key=lambda item: str(item[1])):
        if str(rel) == FOLDER_NOTE:
            continue
        if kind == 'protected':
            skipped.append(f'{rel} (the private folder or the brain itself)')
            continue
        if kind != 'file':
            skipped.append(str(rel))
            continue
        key = f'{folder}/{rel}'
        stamp = fingerprint(path)
        if seen.get(key) == stamp:
            earlier.append(str(rel))
            continue
        named = scan_text(str(rel), str(rel))
        if named:
            reason = re.sub(r'^.*looks like (an? .+?)\. Remove it.*$', r'\1', named[0])
            screened.append({'file': str(rel), 'reason': f'{reason} in its name'})
            continue
        found = readings(path)
        if found is None:
            unscreened.append(str(rel))
            continue
        problems = scan_readings(found, str(rel))
        if problems:
            # keep the reason, never the value: "looks like a card number"
            reason = re.sub(r'^.*looks like (an? .+?)\. Remove it.*$', r'\1', problems[0])
            screened.append({'file': str(rel), 'reason': reason})
            continue
        target = dest / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        kept.append(str(rel))
        seen[key] = stamp
    return {'kept': kept, 'screened_out': screened, 'unscreened': unscreened, 'skipped': skipped, 'looked_at_before': earlier}


def main(argv: list) -> int:
    if not argv or argv[0] in ('-h', '--help'):
        print(__doc__)
        return 2
    folder = local_path(argv[0]).resolve()
    label = folder.name
    if '--label' in argv:
        label = argv[argv.index('--label') + 1]
    label = re.sub(r'[^a-z0-9-]+', '-', label.lower()).strip('-') or 'files'
    if not folder.is_dir():
        print(f'Not a folder: {folder}')
        return 1
    if ROOT in folder.parents or folder == ROOT:
        print('That folder is inside the brain already; point me at where the files live now.')
        return 1
    private = private_folder().resolve()
    if folder == private or private in folder.parents:
        print('That is your private folder. The brain never reads it; point me at a different folder.')
        return 1
    protected = (private, ROOT.resolve())
    now = datetime.datetime.now()
    today = now.date().isoformat()
    receipts = ROOT / 'memory/receipts'
    receipts.mkdir(parents=True, exist_ok=True)
    seen_file = receipts / f'seen-{label}.json'
    seen = json.loads(seen_file.read_text(encoding='utf-8')) if seen_file.exists() else {}
    result = gather(folder, label, seen, protected)
    seen_file.write_text(json.dumps(seen, indent=2, sort_keys=True) + '\n', encoding='utf-8')
    # saved in the brain: only kept files are named; what stayed behind is counted
    receipt = {'date': today, 'folder': str(folder), 'label': label, 'kept': result['kept'],
               'looked_at_before': len(result['looked_at_before']), 'screened_out': len(result['screened_out']),
               'unscreened': len(result['unscreened']), 'skipped': len(result['skipped'])}
    (receipts / f'gather-{label}-{now:%Y-%m-%d-%H%M%S}.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')

    if result['screened_out']:
        note = private_folder() / 'screened-out.md'
        note.parent.mkdir(parents=True, exist_ok=True)
        with note.open('a', encoding='utf-8') as f:
            f.write(f'\n## {today}: screened out of "{label}" ({folder})\n\n')
            f.write('These files were not copied into the brain and were not read by the AI. Each one looked like it held something that must not go in the brain. They are still where they were.\n\n')
            for item in result['screened_out']:
                f.write(f"- {item['file']}: looks like {item['reason']}\n")

    k, s_, u = len(result['kept']), len(result['screened_out']), len(result['unscreened'])
    print(f'Looked at "{folder.name}".')
    if result['looked_at_before']:
        print(f"Skipped {len(result['looked_at_before'])} file(s) already looked at before and unchanged since.")
    print(f'Kept {k} file(s) for reading, now in inbox/{label}/.' if k else 'Kept nothing: no readable files found.')
    if s_:
        names = ', '.join(i['file'] for i in result['screened_out'])
        print(f'Left {s_} file(s) where they were, unread, because they look like they hold private numbers or passwords: {names}. Listed in your private folder.')
    if u:
        names = ', '.join(result['unscreened'])
        print(f'Could not screen {u} file(s), so I did not copy or read them: {names}. Say "read them all" or name the ones you want read; I read those where they are and never copy them into the brain.')
    if result['skipped']:
        names = ', '.join(result['skipped'])
        print(f"Passed over {len(result['skipped'])} shortcut(s) or hidden file(s) without opening them: {names}. A shortcut can point at your private folder, so I never follow one. If you want one of these read, put a real copy in the folder instead.")
    print(f'Receipt: memory/receipts/gather-{label}-{now:%Y-%m-%d-%H%M%S}.json')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
