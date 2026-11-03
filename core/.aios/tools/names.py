#!/usr/bin/env python3
"""Write the owner's names into a JSON file of the engine (the interview), as JSON.

  python3 .aios/tools/names.py FILE COMPANY PRIVATE DOCUMENTS

Replaces %%COMPANY%%, %%PRIVATE%% and %%DOCUMENTS%% inside every string of FILE. The file is read
and written as JSON, so a name with quotes or backslashes (Joe "The Pipe" Café & Co) stays valid.
Used by install.sh and upgrade.sh. Exits 1, changing nothing, when FILE is not valid JSON.
"""
import json
import sys
from pathlib import Path


def fill(value, names):
    if isinstance(value, str):
        for key, name in names.items():
            value = value.replace(key, name)
        return value
    if isinstance(value, list):
        return [fill(v, names) for v in value]
    if isinstance(value, dict):
        return {k: fill(v, names) for k, v in value.items()}
    return value


def main(argv):
    if len(argv) != 4:
        sys.exit(__doc__)
    path = Path(argv[0])
    names = {'%%COMPANY%%': argv[1], '%%PRIVATE%%': argv[2], '%%DOCUMENTS%%': argv[3]}
    try:
        data = json.loads(path.read_text(encoding='utf-8'))
    except (OSError, ValueError) as err:
        print(f'{path} could not be read as JSON ({err}).')
        return 1
    path.write_text(json.dumps(fill(data, names), ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
