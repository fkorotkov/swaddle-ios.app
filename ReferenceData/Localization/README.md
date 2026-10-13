# App languages and milestone translations

Swaddle has native app, widget, and milestone String Catalog resources for all 13 languages listed on CDC's [checklist resource page](https://www.cdc.gov/act-early/resources/milestone-checklists.html): English (`en`), Spanish (`es`), Arabic (`ar`), Brazilian Portuguese (`pt-BR`), Farsi/Persian (`fa`), French (`fr`), Haitian Creole (`ht`), Hindi (`hi`), Korean (`ko`), Chinese/Simplified (`zh-Hans`), Somali (`so`), Tagalog/Filipino (`fil`), and Vietnamese (`vi`). Foundation resolves `tl-PH` to `fil`, `fr-CA` to `fr`, and Portuguese preferences to the provided Brazilian Portuguese resources.

Russian (`ru`) is also supported throughout the app, widgets, and milestones. It is a Swaddle translation of the CDC English checklist, not an official CDC Russian publication.

Language follows iOS preferred/per-app language. The App language row opens native app settings. Region controls numeric/date formatting; language never changes quantities, reporting time zones, raw JSON keys, profile names, notes, record IDs, source versions, or frozen milestone wording. Arabic/Farsi navigation and the decorative milestone ribbon/fold mirror for right-to-left reading.

## Editorial review — October 12, 2026

At the user's request, Codex reviewed the complete source-key inventory in all 14 languages and authored the Russian translation. Corrections cover care terminology, destructive actions, account sharing, import instructions, clinical explanations, accessibility descriptions, and short controls. Full localized count phrases replace English noun fragments; Russian has one/few/many/other plural forms. All 100 Russian CDC-based titles, six WHO titles per language, and the Siri phrase sets were reviewed separately. This is an AI editorial review, not a claim of native-speaker certification or CDC endorsement.

`editorial-review.json` records corrections. `reviewed-source-keys.json` and the per-language content hashes in `review-progress.json` pin the reviewed draft values so future machine-generated changes cannot inherit approval from a coverage count. The release validator rejects unreviewed copy, missing resources, invalid placeholders, changed import tokens, and missing plural forms. Native tests check compiled resources, Russian plural selection, and exact decimal round trips. Simulator layouts are checked separately; actual spoken Siri recognition still depends on the device's Siri language and Apple's support.

`Drafts/*.json` contains app-authored copy only, generated locally with the Apache-2.0 `google/madlad400-3b-mt` checkpoint (revision `fa184c675da0b5c9e1c8694fccd4e12e2d422094`) through CTranslate2. Neither models nor translation libraries are app dependencies or bundled resources. No care records are translated or sent to a translation service. Format/protocol rejections are repaired separately; draft generation must not invent quantities, drop parameters, change JSON field names, or silently substitute English. Shortcuts have native phrase resources; spoken Siri availability depends on Apple's supported Siri languages and the device's Siri settings.

## Maintenance

- `python3 scripts/sync_spanish_catalogs.py`: apply existing reviewed Spanish.
- `python3 scripts/sync_multilingual_catalogs.py`: apply the new locales; fail if any active copy is missing. `--allow-incomplete` is for intermediate previews only, never final verification.
- `python3 scripts/validate_localizations.py`: check every active app/widget entry, argument position/type, plural fallback, Siri parameter, and all milestone mappings. It rejects remaining app-copy review states. `--allow-unreviewed` is only for intermediate previews.
- `scripts/prepare_language_drafts.py`: optional, resumable offline preparation; requires local model files under `.build`, not a shipping runtime.

Build to extract new keys before applying/validating copy. Brand names, universal unit symbols, and punctuation-only formatting templates are kept unchanged. The SwiftSyntax inventory helper supports audits of computed strings that the compiler cannot automatically extract.

## Milestone provenance

`../Milestones/cdc-checklists-<locale>.json` freezes each language's **100 CDC skills currently included in Swaddle**, for 2, 4, 6, 9, 12, 15, 18, and 24 months. CDC also publishes older-child checklists; this change retains the app's existing age coverage. The six WHO motor skills remain separate, with their own titles and source links. All 106 illustration IDs and offline vector scenes are intact.

Spanish wording comes from the official CDC Spanish pages. The 11 additional CDC languages come from the PDFs linked on CDC's resource page, retrieved October 12, 2026; snapshots retain source URLs, SHA-256 hashes, checkbox/page provenance, and the corresponding English ID/title. PDF column order varies: Farsi, French, Haitian Creole, Hindi, Korean, Chinese, Somali, and Vietnamese have explicit permutations matched by meaning. Arabic/Persian text is stored in logical Unicode order; PDF line wraps/font mapping are normalized. The Hindi font's broken text mapping required spelling transcription corrections, recorded separately and checked against rendered official pages.

`extract_cdc_language_checklists.py` reads downloaded PDFs under `.build/cdc-languages`; `freeze_cdc_language_titles.py` applies checked mappings and transcription corrections. Re-check permutations against revised PDFs; matching counts alone do not prove that a translation belongs to the right ID.

The Russian snapshot identifies Swaddle as `translationPublisher` and sets `officialTranslation: false`; its source links open the official English checklist.

Existing check-ins keep their original title/version. Display substitutes the current localized title only when the frozen wording matches the current English skill; different historical wording stays verbatim. CDC links open the translated age page/PDF page, while WHO links continue to WHO.
