#!/usr/bin/env python3
"""Check the central UI template and translation contracts, using only Python's standard library."""
import ast
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
CATALOGS = ROOT / 'game/assets/localization'
FORMAT = re.compile(r'%[-+0-9.*]*[sdifxXc](?![A-Za-z])')
MARKER = re.compile(r'\{[^{}]+\}')


def read_po(path):
    entries, current, field = [], {}, None
    for line in path.read_text(encoding='utf-8-sig').splitlines() + ['']:
        if not line.strip():
            if 'msgid' in current:
                entries.append(current)
            current, field = {}, None
        elif line.startswith('#'):
            current.setdefault('comments', []).append(line)
        elif line.startswith('"'):
            if field is None:
                raise ValueError(f'{path}: continuation without a field')
            current[field] += ast.literal_eval(line)
        else:
            field, value = line.split(' ', 1)
            current[field] = ast.literal_eval(value)
    return [entry for entry in entries if entry['msgid']]


def key(entry):
    return entry.get('msgctxt', ''), entry['msgid']


def check():
    errors = []
    template = read_po(CATALOGS / 'messages.pot')
    expected = {key(entry): entry for entry in template}
    if len(expected) != len(template):
        errors.append('Duplicate template keys')
    # The language picker is the authority; adding a language extends this check.
    app = (ROOT / 'game/src/ui/shared/app_localization.gd').read_text(encoding='utf8')
    section = app.split('const TRANSLATIONS:', 1)[1].split('}', 1)[0]
    languages = re.findall(r'"([a-zA-Z_]+)": "res://assets/localization/([^"/]+\.po)"', section)
    if not languages:
        errors.append('No registered language catalogs found')
    for locale, filename in languages:
        path = CATALOGS / filename
        if not path.exists():
            errors.append(f'{locale}: missing catalog')
            continue
        entries = read_po(path)
        found = {key(entry): entry for entry in entries}
        if len(found) != len(entries):
            errors.append(f'{locale}: duplicate keys')
        for identity, source in expected.items():
            legacy = locale == 'ko' and any('legacy-ko-fallback:' in c for c in source.get('comments', []))
            if identity not in found and not legacy:
                errors.append(f'{locale}: missing {identity!r}')
        for identity, entry in found.items():
            source = entry['msgid']
            values = [v for k, v in entry.items() if k.startswith('msgstr')]
            if not values or any(not v for v in values) or any(c.startswith('#,') and 'fuzzy' in c for c in entry.get('comments', [])):
                errors.append(f'{locale}: empty or fuzzy {identity!r}')
            for value in values:
                if FORMAT.findall(source) != FORMAT.findall(value):
                    errors.append(f'{locale}: printf placeholders differ: {identity!r}')
                # Original resource IDs identify prose, not format templates.
                if identity[0] != 'original' and sorted(MARKER.findall(source)) != sorted(MARKER.findall(value)):
                    errors.append(f'{locale}: named placeholders differ: {identity!r}')
                if '%%' in source and source.count('%%') != value.count('%%'):
                    errors.append(f'{locale}: escaped percent differs: {identity!r}')
            if identity[0] not in ('original', 'newspaper', 'scenario') and identity not in expected:
                errors.append(f'{locale}: UI key missing from messages.pot: {identity!r}')
        print(f'{locale}: {len(found)} entries; {sum(k in found for k in expected)}/{len(expected)} UI keys')
    patterns = json.loads((CATALOGS / 'formatted_messages.json').read_text(encoding='utf8'))
    if len(patterns) != len(set(patterns)):
        errors.append('Duplicate formatted message keys')
    for source in patterns:
        if ('', source) not in expected:
            errors.append(f'Formatted message absent from template: {source!r}')
    policy = json.loads((CATALOGS / 'source_audit.json').read_text(encoding='utf8'))
    # These features keep display labels in data arrays as well as tr() calls.
    # Inspect their literal text too, so omitting both PO and POT does not pass.
    for glob in policy['paths']:
        for path in ROOT.glob(glob):
            for number, line in enumerate(path.read_text(encoding='utf8').splitlines(), 1):
                if line.lstrip().startswith('#'):
                    continue
                for raw in re.findall(r'"(?:[^"\\]|\\.)*"', line):
                    try:
                        source = json.loads(raw)
                    except ValueError:
                        continue
                    if not re.match(r'^[A-Z][a-z]', source):
                        continue
                    if source in policy['non_display_literals'] or ('', source) in expected:
                        continue
                    errors.append(f'{path.relative_to(ROOT)}:{number}: source absent from template: {source!r}')
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        return 1
    print('PASS: central localization catalogs and placeholders')
    return 0


if __name__ == '__main__':
    sys.exit(check())
