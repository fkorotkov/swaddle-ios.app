# Length / height and head circumference references

Retrieved October 11, 2026. `sources.json` pins the URLs and SHA-256 of eight WHO workbooks and four Oxford preterm tables. Original documents stay outside the application target; the app bundles numeric reference data, not chart artwork or PDFs.

## WHO

- [Length/height-for-age standards](https://www.who.int/tools/child-growth-standards/standards/length-height-for-age)
- [Head-circumference-for-age standards](https://www.who.int/tools/child-growth-standards/standards/head-circumference-for-age)
- [WHO Anthro manual](https://www.who.int/docs/default-source/child-growth/child-growth-standards/software/anthro-pc-manual-v322.pdf), section 3.2.3, for measurement position.

Expanded z-score workbooks supply sex-specific daily LMS coefficients, days 0–1856, for each indicator. No monthly interpolation is used. Percentiles are the normal cumulative distribution of the LMS z-score. Comparisons cover birth through the fifth calendar birthday, on the measurement date in the family's reporting calendar. Missing reference data, invalid values, dates before birth, and future measurements do not produce a percentile. Saved measurements remain visible outside the reference range.

WHO uses lying-down length through day 730 and standing height from day 731. If the entered position differs, the comparison adds 0.7 cm to standing height at the younger age or subtracts 0.7 cm from lying-down length at the older age. The comparison and plotted point disclose that adjustment; the original entry is never rewritten. Head circumference needs no position conversion. Curve IDs separate length and height at day 730/731.

The percentile workbooks provide 260 independent fixtures across both sexes and indicators, including birth, day 730/731/732, and five years. They are not generated from the app's calculation; tolerances accommodate published rounding to 0.001 cm.

## Prematurity and WHO-only policy

For a known birth before 37 weeks, WHO uses corrected age from the estimated 40-week due date until the second calendar birthday, then actual age. Under two, paired WHO details show the same measurement at corrected and actual ages. Before the due date, corrected-age WHO is unavailable; the measurement and actual-age comparison are retained. No preterm reference is bundled or used in the current app. Lying-down/standing position adjustments remain visible even in the paired-age presentation.

The four Oxford PDFs and their 456 independent centile fixtures remain archived for historical provenance. The generator verifies them, but they do not feed production data or current percentile calculations. Previously used equations and scope are recorded in [the archived preterm notes](../Preterm/README.md).

## Regeneration and storage

Run `python3 scripts/generate_growth_measurement_reference.py --check` in an environment with `pypdf` (or `pdftotext` installed). Omit `--check` to regenerate the checked-in Swift data and independent fixtures. The generator verifies all source hashes before writing.

Records preserve canonical centimeters, original cm/in choice, position for length, date/time zone, child, author, and note. One inch is exactly 2.54 cm. Both payloads use version 5 of the existing immutable revision envelope and existing CloudKit family sharing. No CloudKit schema deployment is required. Family members need the updated app to interpret these new payloads.
