#!/usr/bin/env python3
"""Freeze checked PDF titles under stable English skill IDs, not PDF positions."""
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / '.build/cdc-languages'
SOURCE = json.loads((ROOT / 'ReferenceData/Milestones/cdc-checklists.json').read_text())
CORRECTIONS = json.loads((ROOT / 'ReferenceData/Milestones/cdc-pdf-transcription-corrections.json').read_text())
# These permutations were matched by meaning against the English skills. Do not
# apply them to revised PDFs without re-checking the published checkboxes.
ORDERS = {
    ('fa', 2): [6, 7, 8, 9, 10, 0, 1, 2, 3, 4, 5],
    ('fa', 4): [6, 7, 8, 9, 10, 11, 12, 0, 1, 2, 3, 4, 5],
    ('fa', 6): [6, 7, 8, 9, 10, 11, 0, 1, 2, 3, 4, 5],
    ('ht', 18): [7, 8, 9, 10, 11, 12, 13, 14, 0, 1, 2, 3, 4, 5, 6],
}
for locale in ['fr', 'ko', 'zh-Hans', 'vi']:
    ORDERS[(locale, 24)] = [7, 8, 9, 10, 11, 12, 0, 1, 2, 3, 4, 5, 6]
for locale in ['ht', 'hi', 'so']:
    ORDERS[(locale, 24)] = [6, 7, 8, 9, 10, 11, 12, 0, 1, 2, 3, 4, 5]

INTRODUCTIONS = {
    'fr': 'Les étapes ont leur importance', 'ht': 'Etap enpòtan yo gen enpòtans',
    'so': 'Marxaladaha muhiimka ah!', 'vi': 'Các mốc phát triển rất quan trọng!',
}
RTL_LAST = {
    ('ar', 18): 'يتسلق صعودا على الأريكة ونزولا منها من دون مساعدة',
    ('ar', 24): 'يتناول الطعام بملعقة',
    ('fa', 18): 'بالا و پایین رفتن از کاناپه یا صندلی، بدون کمک',
    ('fa', 24): 'غذا خوردن با قاشق',
}

for language in json.loads((WORK / 'sources.json').read_text()):
    locale = language['locale']
    skills = []
    for group in json.loads((WORK / f'{locale}-titles.json').read_text()):
        months = group['months']
        titles = CORRECTIONS.get(locale, {}).get(str(months), group['titles'])
        originals = [skill for skill in SOURCE['skills'] if skill['months'] == months]
        order = ORDERS.get((locale, months), list(range(len(originals))))
        assert sorted(order) == list(range(len(originals))) and len(titles) == len(originals)
        for index, (title, source_index) in enumerate(zip(titles, order)):
            if locale in INTRODUCTIONS:
                title = title.split(INTRODUCTIONS[locale])[0].strip()
            if index == len(titles) - 1 and (locale, months) in RTL_LAST:
                title = RTL_LAST[(locale, months)]
            if locale == 'fa':
                for bad, good in [('اسبا بباز یها', 'اسباب‌بازی‌ها'), ('اسبا ببازی', 'اسباب‌بازی'),
                                  ('ثانی های', 'ثانیه‌ای'), ('هیجا نزده', 'هیجان‌زده'), ('می یشود', 'می‌شود'),
                                  ('م یشود', 'می‌شود'), ('م یگویید', 'می‌گویید'), ('م یپرسید', 'می‌پرسید'),
                                  ('خ طخطی', 'خط‌خطی'), ('تک-مرحل های', 'تک‌مرحله‌ای'), ('در حال یکه', 'در حالی که')]:
                    title = title.replace(bad, good)
            assert title and len(title) < 350, (locale, months, index, title)
            source = originals[source_index]
            skills.append({**source, 'sourceTitle': source['title'], 'title': title,
                           'sourceURL': language['sourceURL'], 'pdfPage': 1 + 2 * [2, 4, 6, 9, 12, 15, 18, 24].index(months),
                           'pdfCheckboxIndex': index})
    assert len(skills) == 100 and len({s['id'] for s in skills}) == 100
    snapshot = {'version': f'cdc-{locale}-2026-10-12', 'language': locale,
                'publisher': 'CDC', 'retrieved': '2026-10-12', **language,
                'transcription': 'published checkbox wording; Unicode/line-wrap normalization; Hindi font-map spelling corrected',
                'skills': sorted(skills, key=lambda skill: (skill['months'], next(i for i, s in enumerate(SOURCE['skills']) if s['id'] == skill['id'])))}
    path = ROOT / f'ReferenceData/Milestones/cdc-checklists-{locale}.json'
    path.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + '\n')
    print(locale, '100 source-mapped CDC titles')
