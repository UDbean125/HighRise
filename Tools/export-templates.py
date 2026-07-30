#!/usr/bin/env python3
"""Export the Swift starter-template catalog to Windows/templates.json.

The Mac/iOS apps read `HighRise/Models/StarterTemplate.swift` directly; the
Windows companion is PowerShell and can't, so it reads this generated JSON
instead. Regenerate whenever the catalog changes:

    python3 Tools/export-templates.py

CI runs this with --check, which fails if the committed JSON has drifted from
the Swift source — the two can't silently disagree about what ships.

Output is ASCII-only (non-ASCII escaped as \\uXXXX) because Windows PowerShell
5.1 misreads UTF-8 files without a BOM.
"""
import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SWIFT = os.path.join(ROOT, 'HighRise', 'Models', 'StarterTemplate.swift')
OUT = os.path.join(ROOT, 'Windows', 'templates.json')

# Enum case -> display label, kept in sync with TemplateIndustry/TemplateAudience.
def enum_labels(source, enum_name):
    block = re.search(rf'enum {enum_name}: String[^{{]*\{{(.*?)\n\}}', source, re.S)
    if not block:
        raise SystemExit(f'could not find enum {enum_name}')
    return dict(re.findall(r'case (\w+) = "([^"]+)"', block.group(1)))


def parse(source):
    industries = enum_labels(source, 'TemplateIndustry')
    audiences = enum_labels(source, 'TemplateAudience')
    order = re.search(r'categoryOrder = \[([^\]]+)\]', source).group(1)
    categories = re.findall(r'"([^"]+)"', order)

    templates = []
    for raw in re.findall(r'StarterTemplate\(\n(.*?)\n        \)', source, re.S):
        def field(name):
            m = re.search(rf'{name}: "((?:[^"\\]|\\.)*)"', raw)
            return m.group(1) if m else ''

        body = re.search(r'body: """\n(.*?)\n            """', raw, re.S)
        if not body:
            continue
        lines = [ln[12:] if ln.startswith(' ' * 12) else ln
                 for ln in body.group(1).split('\n')]
        tags = lambda key: re.findall(r'\.(\w+)', (re.search(rf'{key}: \[([^\]]*)\]', raw) or
                                                   re.match('', '')).group(1)) \
            if re.search(rf'{key}: \[([^\]]*)\]', raw) else []

        templates.append({
            'id': field('id'),
            'name': field('name'),
            'category': field('category'),
            'blurb': field('blurb'),
            'subject': field('subject'),
            'body': '\n'.join(lines),
            'audiences': [audiences[a] for a in tags('audiences') if a in audiences],
            'industries': [industries[i] for i in tags('industries') if i in industries],
        })
    return {
        'categories': categories,
        'industries': list(industries.values()),
        'audiences': list(audiences.values()),
        'templates': templates,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', action='store_true',
                    help='exit non-zero if the committed JSON is out of date')
    args = ap.parse_args()

    data = parse(open(SWIFT, encoding='utf-8').read())
    if not data['templates']:
        raise SystemExit('parsed zero templates - the Swift layout probably changed')
    rendered = json.dumps(data, indent=2, ensure_ascii=True) + '\n'

    if args.check:
        current = open(OUT, encoding='utf-8').read() if os.path.exists(OUT) else ''
        if current != rendered:
            print('Windows/templates.json is out of date. Run: python3 Tools/export-templates.py',
                  file=sys.stderr)
            return 1
        print(f'up to date ({len(data["templates"])} templates)')
        return 0

    with open(OUT, 'w', encoding='ascii', newline='\n') as f:
        f.write(rendered)
    print(f'wrote {OUT} ({len(data["templates"])} templates, '
          f'{len(data["industries"])} industries, {len(data["audiences"])} audiences)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
