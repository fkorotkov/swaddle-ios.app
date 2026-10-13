#!/usr/bin/env python3
"""Apply source snapshots, drafts, and editorial corrections to String Catalogs.

Editorial corrections take precedence over generated drafts. Coverage and
format checks are separate from the recorded, source-by-source language review.
"""
import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = ['ar', 'pt-BR', 'fa', 'fr', 'ht', 'hi', 'ko', 'zh-Hans', 'so', 'fil', 'vi', 'ru']
CORE = json.loads((ROOT / 'ReferenceData/Localization/core-copy.json').read_text())
UI_COPY = json.loads((ROOT / 'ReferenceData/Localization/ui-copy.json').read_text())
ADDITIONS = json.loads((ROOT / 'ReferenceData/Localization/reviewed-additions.json').read_text())
SHORTCUTS = json.loads((ROOT / 'ReferenceData/Localization/shortcut-copy.json').read_text())
PLURALS = json.loads((ROOT / 'ReferenceData/Localization/plural-copy.json').read_text())
EDITORIAL = json.loads((ROOT / 'ReferenceData/Localization/editorial-review.json').read_text())
PROGRESS = json.loads((ROOT / 'ReferenceData/Localization/review-progress.json').read_text())
REVIEWED_KEYS = json.loads((ROOT / 'ReferenceData/Localization/reviewed-source-keys.json').read_text())


def copy_digest(copy):
    reviewed_copy = {key: copy[key] for key in REVIEWED_KEYS if key in copy}
    return hashlib.sha256(json.dumps(reviewed_copy, ensure_ascii=False, sort_keys=True).encode()).hexdigest()


def unit(value, reviewed=False):
    # MT training corpora sometimes contain the textual form of a Unicode
    # escape. Decode Unicode scalars only; keep JSON's literal \\n unchanged.
    value = re.sub(r'\\u([0-9a-fA-F]{4})', lambda match: chr(int(match[1], 16)), value)
    return {'stringUnit': {'state': 'translated' if reviewed else 'needs_review', 'value': value}}


def plural_forms(language, one, other):
    if language in ['ko', 'zh-Hans', 'vi']:
        return {'other': unit(other)}
    if language == 'ar':
        return {form: unit(one if form in ['one', 'two', 'many'] else other)
                for form in ['zero', 'one', 'two', 'few', 'many', 'other']}
    return {'one': unit(one), 'other': unit(other)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--allow-incomplete', action='store_true', help='Preview only; final validation still rejects missing translations.')
    args = parser.parse_args()
    missing = []
    drafts = {locale: json.loads(path.read_text()) if (path := ROOT / f'ReferenceData/Localization/Drafts/{locale}.json').exists() else {}
              for locale in LANGUAGES}
    reviewed = {locale: {**dict(zip(CORE['keys'], CORE.get(locale, []))), **dict(zip(UI_COPY['keys'], UI_COPY.get(locale, []))), **ADDITIONS.get(locale, {}), **EDITORIAL.get(locale, {})} for locale in LANGUAGES}
    copy = {locale: {**drafts[locale], **reviewed[locale]} for locale in LANGUAGES}
    # Coverage counts alone must never approve a newly generated translation.
    sealed = {locale: copy_digest(copy[locale]) == PROGRESS.get('reviewedAppCopySHA256', {}).get(locale)
              for locale in LANGUAGES}
    shortcut_copy = {locale: dict(zip(SHORTCUTS['sources'], SHORTCUTS[locale])) for locale in LANGUAGES}
    for filename in ['Localizable.xcstrings', 'LittleLogWidgets/Localizable.xcstrings']:
        path = ROOT / filename
        catalog = json.loads(path.read_text())
        shared_strings = json.loads((ROOT / 'Localizable.xcstrings').read_text())['strings'] if filename.startswith('LittleLogWidgets/') else {}
        for key, entry in catalog['strings'].items():
            if entry.get('extractionState') == 'stale' or entry.get('shouldTranslate') is False:
                continue
            if filename.startswith('LittleLogWidgets/'):
                shared = shared_strings.get(key, {})
                for locale in ['en', 'es']:
                    if locale not in entry.get('localizations', {}) and locale in shared.get('localizations', {}):
                        entry.setdefault('localizations', {})[locale] = deepcopy(shared['localizations'][locale])
            en_plural = entry.get('localizations', {}).get('en', {}).get('variations', {}).get('plural')
            for locale in LANGUAGES:
                if key not in copy[locale]:
                    missing.append((locale, key))
                    continue
                value = copy[locale][key]
                if escape := re.search(r'\\+n', key):
                    value = re.sub(r'\\+n', lambda _: escape[0], value)
                translated = unit(value, key in reviewed[locale] or (key in REVIEWED_KEYS and sealed[locale]))
                if en_plural:
                    if forms := PLURALS.get(locale, {}).get(key):
                        entry.setdefault('localizations', {})[locale] = {
                            'variations': {'plural': {form: unit(text, reviewed=True) for form, text in forms.items()}}}
                        continue
                    one_key = en_plural['one']['stringUnit']['value']
                    other_key = en_plural['other']['stringUnit']['value']
                    if one_key not in copy[locale] or other_key not in copy[locale]:
                        missing.append((locale, one_key))
                        continue
                    translated = {'variations': {'plural': plural_forms(locale, copy[locale][one_key], copy[locale][other_key])}}
                entry.setdefault('localizations', {})[locale] = translated
            for locale in ['en', 'es']:
                if key in EDITORIAL.get(locale, {}):
                    entry.setdefault('localizations', {})[locale] = unit(EDITORIAL[locale][key], reviewed=True)
        path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + '\n')
    path = ROOT / 'AppShortcuts.xcstrings'
    catalog = json.loads(path.read_text())
    for key, entry in catalog['strings'].items():
        sources = entry['localizations']['en']['stringSet']['values']
        for locale in LANGUAGES:
            if any(source not in shortcut_copy[locale] for source in sources):
                missing.extend((locale, source) for source in sources if source not in shortcut_copy[locale])
                continue
            entry['localizations'][locale] = {'stringSet': {'state': 'translated', 'values': [shortcut_copy[locale][source] for source in sources]}}
    path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + '\n')
    path = ROOT / 'Milestones.xcstrings'
    catalog = json.loads(path.read_text())
    for locale in LANGUAGES:
        source = json.loads((ROOT / f'ReferenceData/Milestones/cdc-checklists-{locale}.json').read_text())
        for skill in source['skills']:
            catalog['strings'][skill['id']]['localizations'][locale] = unit(skill['title'], reviewed=True)
        for key, entry in catalog['strings'].items():
            if key.startswith('who-'):
                value = entry['localizations']['en']['stringUnit']['value']
                if value not in copy[locale]:
                    missing.append((locale, value))
                    continue
                entry['localizations'][locale] = unit(copy[locale][value], value in EDITORIAL.get(locale, {}))
    path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + '\n')
    print(f'Applied {len(LANGUAGES)} locales; {len(missing)} missing copy entries.')
    (ROOT / '.build/cdc-languages/missing-copy.json').write_text(json.dumps(missing, ensure_ascii=False, indent=2))
    if missing and not args.allow_incomplete:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
