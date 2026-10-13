#!/usr/bin/env python3
"""Extract the published CDC checkbox text from downloaded checklist PDFs.

Requires pdfplumber. PDFs and intermediate text stay under .build/cdc-languages;
only the small, checked source snapshots belong in ReferenceData/Milestones.
Reading order is not a skill ID: several PDFs arrange their columns differently.
"""
import json
from pathlib import Path
import re
import unicodedata
import pdfplumber

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / '.build/cdc-languages'
MONTHS = [2, 4, 6, 9, 12, 15, 18, 24]


def clean(text, locale):
    text = re.sub(r'\s+', ' ', unicodedata.normalize('NFC', text)).strip()
    if locale == 'zh-Hans':
        text = re.sub(r'(?<=[\u4e00-\u9fff]) +(?=[\u4e00-\u9fff])', '', text)
    return text


def rtl_titles(page, locale):
    bullets = [c for c in page.chars if c['text'] == 'o' and 'Wingdings' in c['fontname']]
    last_bullet = max(c['top'] for c in bullets)
    end_of_checklist = min(c['top'] - 1 for c in page.chars
                           if 'Bold' in c['fontname'] and c['size'] >= 12 and c['top'] > last_bullet + 6)
    titles = []
    for bullet in sorted(bullets, key=lambda c: (c['x0'] < 300, c['top'])):
        low, high = (300, 565) if bullet['x0'] > 300 else (30, 280)
        column = [c for c in page.chars if low < c['x0'] < high]
        stops = [c['top'] - 1 for c in column if 'Bold' in c['fontname']
                 and c['size'] >= 13 and c['top'] > bullet['top'] + 6]
        stops += [c['top'] - 1 for c in bullets
                  if low < c['x0'] < high + 4 and c['top'] > bullet['top'] + 6]
        end = min(stops + [end_of_checklist])
        chars = [c for c in column if bullet['top'] - 1 < c['top'] < end
                 and 'Wingdings' not in c['fontname'] and 'Bold' not in c['fontname'] and c['size'] < 12]
        lines = []
        for char in sorted(chars, key=lambda c: c['top']):
            if not lines or abs(char['top'] - lines[-1][0]['top']) > 3:
                lines.append([])
            lines[-1].append(char)
        text = ' '.join(''.join(c['text'] for c in sorted(line, key=lambda c: c['x0'], reverse=True)) for line in lines)
        # The font's combining marks and lam/alef glyph order are not Unicode
        # reading order. Use unvowelled, logical Unicode, never visual RTL text.
        text = ''.join(c for c in unicodedata.normalize('NFKC', text) if not unicodedata.combining(c))
        for bad, good in [('األ', 'الأ'), ('اإل', 'الإ'), ('اآل', 'الآ')]:
            text = text.replace(bad, good)
        titles.append(clean(text, locale))
    return titles


def ltr_titles(page, locale):
    titles, chars, started = [], [], False

    def finish():
        if chars:
            parts = []
            previous = None
            for char in chars:
                if previous and char['x0'] < previous['x0'] - 30 and abs(char['top'] - previous['top']) > 5:
                    parts.append(' ')
                parts.append(char['text'])
                previous = char
            text = ''.join(parts)
            titles.append(clean(text, locale))

    for char in page.chars:
        font = char['fontname']
        body = ('Regular' in font or 'ArialMT' in font) and char['size'] < 12 and 'Wingdings' not in font
        if char['text'] == 'o' and 'Wingdings' in font:
            finish()
            chars, started = [], True
        elif body and started:
            chars.append(char)
        elif 'Bold' in font or 'Wingdings' in font:
            if started:
                finish()
            chars, started = [], False
    finish()
    return titles


if __name__ == '__main__':
    source = json.loads((ROOT / 'ReferenceData/Milestones/cdc-checklists.json').read_text())
    for language in json.loads((WORK / 'sources.json').read_text()):
        locale = language['locale']
        groups = []
        with pdfplumber.open(WORK / f'{locale}.pdf') as document:
            for page_index, months in zip(range(0, 16, 2), MONTHS):
                page = document.pages[page_index]
                titles = rtl_titles(page, locale) if locale in ['ar', 'fa'] else ltr_titles(page, locale)
                expected = sum(s['months'] == months for s in source['skills'])
                assert len(titles) == expected, (locale, months, len(titles), expected)
                groups.append({'months': months, 'titles': titles})
        (WORK / f'{locale}-titles.json').write_text(json.dumps(groups, ensure_ascii=False, indent=2) + '\n')
        print(locale, sum(len(group['titles']) for group in groups))
