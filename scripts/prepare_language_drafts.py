#!/usr/bin/env python3
"""Prepare resumable, OFFLINE app-copy drafts; never translate care records.

For local QA only. Requires CTranslate2 + sentencepiece and the Apache-2.0
google/madlad400-3b-mt checkpoint converted to int8 under .build/madlad-int8.
No model, service, SDK, or network call is added to the app. Native-speaker
review remains separate from automated coverage/format/layout verification.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import time
import ctranslate2
import sentencepiece

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = {'ar': 'ar', 'pt-BR': 'pt', 'fa': 'fa', 'fr': 'fr', 'ht': 'ht', 'hi': 'hi',
             'ko': 'ko', 'zh-Hans': 'zh', 'so': 'so', 'fil': 'fil', 'vi': 'vi', 'ru': 'ru'}
PROTECTED = re.compile(r'"(?:type|feed|version|pump|occurredAt|breastMilkML|formulaML|totalML|leftML|rightML|durationMinutes|timezone|id|source|notes|jsonl)"|\$\{[^}]+\}|%(?:\d+\$)?(?:[-+#0 ]*\d*(?:\.\d+)?)?(?:lld|ld|llu|lu|d|u|f|g|@)|%%|https?://\S+|\bSwaddle\b|\biCloud\b|\bCloudKit\b|\bTestFlight\b|\b[0-9]+(?:[.,][0-9]+)*(?:%)?')


def protect(text):
    tokens = []

    def replace(match):
        tokens.append(match[0])
        return f'ZXQ{len(tokens):03d}'

    return PROTECTED.sub(replace, text), tokens


def childcare_context(text):
    # A general-domain MT model otherwise interprets "formula" as mathematics
    # and "pump" as machinery. Context is for draft preparation only.
    for pattern, replacement in [
        (r'\bformula\b(?! milk)', 'formula milk'),
        (r'\bpumping\b', 'expressing breast milk'),
        (r'\bpumped\b', 'breast milk expressed'),
        (r'(?<!")\bpump\b', 'express breast milk'),
        (r'\bbottle\b', 'baby bottle'),
        (r'\bmilestones\b', 'developmental milestones'),
        (r'\bmilestone\b', 'developmental milestone'),
    ]:
        text = re.sub(pattern, replacement, text, flags=re.I)
    if text == 'Used to do this':
        text = 'The baby used to do this'
    return text


def restore(text, tokens):
    markers = re.findall(r'ZXQ\s*\d{3}', text, flags=re.I)
    wanted = [f'ZXQ{i:03d}' for i in range(1, len(tokens) + 1)]
    normalized = [re.sub(r'\s+', '', marker).upper() for marker in markers]
    if Counter(normalized) != Counter(wanted):
        return None
    for index, token in enumerate(tokens, 1):
        text = re.sub(rf'ZXQ\s*{index:03d}', lambda _: token, text, flags=re.I)
    return text.strip()


def plausible(source, target, language):
    if not target or len(target) > max(180, len(source) * 3.5):
        return False
    if len(target) > 80 and re.search(r'(.{4,40})\1\1', target):
        return False
    if re.search(r'<2[a-z]+>|\btl>', target) or (target.lstrip().startswith('>') and not source.lstrip().startswith('>')):
        return False
    if len(source) > 25 and source == target:
        return False
    prose = PROTECTED.sub('', source)
    if len(re.findall('[A-Za-z]', prose)) > 12:
        scripts = {'ar': '[\u0600-\u06ff]', 'fa': '[\u0600-\u06ff]', 'hi': '[\u0900-\u097f]',
                   'ko': '[\uac00-\ud7a3]', 'zh-Hans': '[\u4e00-\u9fff]'}
        if language in scripts and not re.search(scripts[language], target):
            return False
    return True


def intact(source, target):
    # This deliberately includes protocol keys, quantities, names of Apple
    # services, and Siri parameters. An MT draft may not change their meaning.
    return Counter(PROTECTED.findall(source)) == Counter(PROTECTED.findall(target))


def translate_fragments(keys, language, translator, tokenizer):
    """Fallback for rejected templates: keep structural tokens byte-for-byte.

    Fragment-built copy is still marked needs_review, including grammar/word
    order. It never fabricates/drops a parameter or truncates an export prompt.
    """
    assemblies, prose = [], []
    for key in keys:
        pieces, start = [], 0
        for match in PROTECTED.finditer(key):
            pieces.append(key[start:match.start()])
            pieces.append(('literal', match[0]))
            start = match.end()
        pieces.append(key[start:])
        assembly = []
        for piece in pieces:
            if isinstance(piece, tuple):
                assembly.append(piece[1])
            elif not any(c.isalpha() for c in piece):
                assembly.append(piece)
            else:
                # Translate sentences independently to keep long technical
                # instructions inside the model's verified decoding window.
                for fragment in re.split(r'(?<=[.!?])(?=\s+[A-Z])|(?<=\n)', piece):
                    if not any(c.isalpha() for c in fragment):
                        assembly.append(fragment)
                        continue
                    leading = re.match(r'\s*', fragment)[0]
                    trailing = re.search(r'\s*$', fragment)[0]
                    assembly.append(('prose', len(prose), leading, trailing))
                    prose.append(fragment.strip())
        assemblies.append(assembly)
    inputs = [tokenizer.encode(f'<2{LANGUAGES[language]}> {childcare_context(text)}', out_type=str) + ['</s>'] for text in prose]
    results = translator.translate_batch(inputs, beam_size=2, max_decoding_length=512,
                                         max_input_length=0, repetition_penalty=1.12,
                                         no_repeat_ngram_size=6, max_batch_size=1024, batch_type='tokens')
    translated = [tokenizer.decode(result.hypotheses[0]).strip() for result in results]
    return [''.join(piece if isinstance(piece, str) else piece[2] + translated[piece[1]] + piece[3]
                    for piece in assembly) for assembly in assemblies]


def source_copy():
    sources = {'Choose your preferred app language in iPhone Settings.': 'Choose your preferred app language in iPhone Settings.'}
    for filename in ['Localizable.xcstrings', 'LittleLogWidgets/Localizable.xcstrings']:
        for key, entry in json.loads((ROOT / filename).read_text())['strings'].items():
            if entry.get('extractionState') == 'stale' or entry.get('shouldTranslate') is False:
                continue
            sources[key] = key
            plural = entry.get('localizations', {}).get('en', {}).get('variations', {}).get('plural', {})
            for form in plural.values():
                value = form['stringUnit']['value']
                sources[value] = value
    for entry in json.loads((ROOT / 'AppShortcuts.xcstrings').read_text())['strings'].values():
        for value in entry['localizations']['en']['stringSet']['values']:
            sources[value] = value
    for entry in json.loads((ROOT / 'Milestones.xcstrings').read_text())['strings'].values():
        # The 100 CDC titles come from the official PDFs, never this model.
        if entry['localizations']['en']['stringUnit']['value'] and entry.get('comment', '').startswith('WHO'):
            value = entry['localizations']['en']['stringUnit']['value']
            sources[value] = value
    for key, entry in json.loads((ROOT / 'Milestones.xcstrings').read_text())['strings'].items():
        if key.startswith('who-'):
            value = entry['localizations']['en']['stringUnit']['value']
            sources[value] = value
    return sorted(sources, key=lambda value: (len(value), value))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--language', choices=LANGUAGES, action='append')
    parser.add_argument('--batch-size', type=int, default=48)
    parser.add_argument('--threads', type=int, default=10)
    args = parser.parse_args()
    tokenizer = sentencepiece.SentencePieceProcessor(model_file=str(ROOT / '.build/madlad-int8/spiece.model'))
    for language in args.language or LANGUAGES:
        assert f'<2{LANGUAGES[language]}>' in tokenizer.encode(f'<2{LANGUAGES[language]}>', out_type=str), language
    translator = ctranslate2.Translator(str(ROOT / '.build/madlad-int8'), device='cpu',
                                       compute_type='int8', inter_threads=1, intra_threads=args.threads)
    all_sources = source_copy()
    target_dir = ROOT / 'ReferenceData/Localization/Drafts'
    target_dir.mkdir(exist_ok=True)
    for language in args.language or LANGUAGES:
        path = target_dir / f'{language}.json'
        copy = json.loads(path.read_text()) if path.exists() else {}
        copy = {key: value for key, value in copy.items() if plausible(key, value, language) and intact(key, value)
                and not key.startswith('Export bottle feeds') and not key.startswith('Export pumping sessions')}
        pending = [key for key in all_sources if key not in copy]
        start = time.monotonic()
        rejected = {}
        for offset in range(0, len(pending), args.batch_size):
            keys = pending[offset:offset + args.batch_size]
            inputs = [tokenizer.encode(f'<2{LANGUAGES[language]}> {childcare_context(key)}', out_type=str) + ['</s>'] for key in keys]
            results = translator.translate_batch(inputs, beam_size=2, max_decoding_length=768,
                                                 max_input_length=0, length_penalty=1,
                                                 repetition_penalty=1.12, no_repeat_ngram_size=6,
                                                 max_batch_size=1024, batch_type='tokens')
            retry = []
            for key, result in zip(keys, results):
                raw = tokenizer.decode(result.hypotheses[0])
                if intact(key, raw) and plausible(key, raw, language):
                    copy[key] = raw.strip()
                else:
                    retry.append(key)
            if retry:
                fallback = translate_fragments(retry, language, translator, tokenizer)
                for key, value in zip(retry, fallback):
                    if intact(key, value) and plausible(key, value, language):
                        copy[key] = value
                    else:
                        rejected[key] = value
            temporary = path.with_suffix('.tmp')
            temporary.write_text(json.dumps(copy, ensure_ascii=False, indent=2, sort_keys=True) + '\n')
            temporary.replace(path)
            print(f'{language}: {min(offset + len(keys), len(pending))}/{len(pending)} drafts; {len(rejected)} format rejections; {time.monotonic() - start:.0f}s', flush=True)
        if rejected:
            (ROOT / '.build/cdc-languages' / f'{language}-format-review.json').write_text(json.dumps(rejected, ensure_ascii=False, indent=2))
    print('Draft preparation finished. This does not mark copy as reviewed or release it.', flush=True)


if __name__ == '__main__':
    main()
