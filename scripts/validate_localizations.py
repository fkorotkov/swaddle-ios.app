#!/usr/bin/env python3
"""Release checks for reviewed copy, protocol literals, plurals and source IDs."""
from collections import Counter
import argparse
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = ['es', 'ar', 'pt-BR', 'fa', 'fr', 'ht', 'hi', 'ko', 'zh-Hans', 'so', 'fil', 'vi', 'ru']
TOKEN = re.compile(r'%(?:(\d+)\$)?(?:[-+#0 ]*\d*(?:\.\d+)?)?(lld|ld|llu|lu|d|u|f|g|@)')
PROTOCOL = re.compile(r'"(?:type|feed|version|pump|occurredAt|breastMilkML|formulaML|totalML|leftML|rightML|durationMinutes|timezone|id|source|notes|jsonl)"')
FIELD = re.compile(r'(?<![A-Za-z0-9_])(?:occurredAt|breastMilkML|formulaML|totalML|leftML|rightML|durationMinutes|caregiverID|childID|sourceID|timeZoneID|externalID|timezone|jsonl|null)(?![A-Za-z0-9_])')
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--allow-unreviewed', action='store_true', help='Preview only; never use for release validation.')
args = parser.parse_args()

def arguments(value):
    next_position = 1
    tokens = []
    for match in TOKEN.finditer(value.replace('%%', '')):
        position = int(match[1]) if match[1] else next_position
        if not match[1]:
            next_position += 1
        tokens.append((position, match[2]))
    return Counter(tokens)

def values(localization):
    if 'stringUnit' in localization:
        yield localization['stringUnit']['value']
    for forms in localization.get('variations', {}).values():
        for form in forms.values():
            yield from values(form)

total = 0
review = Counter()
for filename in ['Localizable.xcstrings', 'LittleLogWidgets/Localizable.xcstrings']:
    catalog = json.loads((ROOT / filename).read_text())
    for key, entry in catalog['strings'].items():
        if entry.get('extractionState') == 'stale' or entry.get('shouldTranslate') is False:
            continue
        en = entry.get('localizations', {}).get('en', {})
        source = next(values(en), key)
        for language in LANGUAGES:
            localization = entry.get('localizations', {}).get(language)
            assert localization, (filename, key, 'missing', language)
            for value in values(localization):
                assert arguments(source) == arguments(value), (filename, language, key, source, value)
                assert Counter(PROTOCOL.findall(source)) == Counter(PROTOCOL.findall(value)), (filename, language, key, 'JSON field changed')
                assert Counter(FIELD.findall(source)) == Counter(FIELD.findall(value)), (filename, language, key, 'import token changed', value)
                assert source.count('%%') == value.count('%%'), (filename, language, key, 'literal percent changed')
                if r'\n' in source:
                    assert source.count(r'\n') == value.count(r'\n'), (filename, language, key, 'JSON newline escape changed')
                assert not re.search(r'ZXQ\d', value), (filename, language, key, 'draft marker leaked')
                assert not re.search(r'<2[a-z]+>|\btl>', value), (filename, language, key, 'model language marker leaked')
                assert not (value.lstrip().startswith('>') and not source.lstrip().startswith('>')), (filename, language, key, 'model markup leaked')
                assert len(value) <= max(180, len(source) * 3.5), (filename, language, key, 'implausible expansion')
            assert list(values(localization)), (filename, language, key, 'empty translation')
            if 'variations' in en:
                forms = localization.get('variations', {}).get('plural', {})
                assert 'other' in forms, (filename, language, key, 'missing plural fallback')
                if language == 'ar':
                    assert set(forms) == {'zero', 'one', 'two', 'few', 'many', 'other'}, (filename, language, key)
                if language == 'ru':
                    assert set(forms) == {'one', 'few', 'many', 'other'}, (filename, language, key)
            serialized = json.dumps(localization)
            review[language] += serialized.count('needs_review')
            assert args.allow_unreviewed or not re.search(r'"state": "(?:needs_review|new|stale)"', serialized), (filename, language, key, 'unreviewed copy')
            total += 1

shortcuts = json.loads((ROOT / 'AppShortcuts.xcstrings').read_text())
for key, entry in shortcuts['strings'].items():
    en = entry['localizations']['en']['stringSet']['values']
    for language in LANGUAGES:
        target_values = entry['localizations'][language]['stringSet']['values']
        assert len(en) == len(target_values), (language, key)
        for source, target in zip(en, target_values):
            assert Counter(re.findall(r'\$\{[^}]+\}', source)) == Counter(re.findall(r'\$\{[^}]+\}', target)), (language, key)
            assert '$' + '{applicationName}' in target, (language, key)

catalog = json.loads((ROOT / 'Milestones.xcstrings').read_text())['strings']
english = json.loads((ROOT / 'ReferenceData/Milestones/cdc-checklists.json').read_text())['skills']
for language in LANGUAGES:
    source = json.loads((ROOT / f'ReferenceData/Milestones/cdc-checklists-{language}.json').read_text())
    skills = source['skills']
    assert len(skills) == 100 and len(catalog) == 106
    assert {skill['id'] for skill in skills} == {skill['id'] for skill in english}
    for skill in skills:
        item = catalog[skill['id']]['localizations']
        assert item['en']['stringUnit']['value'] == skill['sourceTitle']
        assert item[language]['stringUnit']['value'] == skill['title']
    for key, entry in catalog.items():
        assert entry['localizations'][language]['stringUnit']['value'] not in [key, entry['localizations']['en']['stringUnit']['value']]
print(f'Validated {total} app/widget translations across {len(LANGUAGES) + 1} languages, 8 Siri phrase sets per language, and all 106 milestone titles per language.')
print('Unreviewed app-copy forms:', dict(review))
