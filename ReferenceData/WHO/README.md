# WHO weight-for-age reference

Swaddle uses numerical LMS coefficients from the **WHO Child Growth Standards (2006)**. These are reference comparisons, not diagnoses, nutritional recommendations, or targets. WHO does not endorse this app.

## Provenance and reproduction

- [WHO weight-for-age: original charts and expanded daily workbooks](https://www.who.int/tools/child-growth-standards/standards/weight-for-age).
- [WHO expanded-table instructions](https://cdn.who.int/media/docs/default-source/child-growth/child-growth-standards/indicators/instructions-en.pdf?sfvrsn=5cec8c61_23): the expanded age-based tables use days and centile weights to three decimal places. WHO recommends verifying reproduced curves against its tables.
- `sources.json` records the exact official download URLs, retrieval date, and SHA-256 for each unmodified workbook.
- Run `python3 scripts/generate_who_weight_reference.py` to check all source hashes and reproduce the checked-in daily LMS constants and independent test fixtures. The script uses Python's standard library. It performs no network requests.
- The app ships generated numerical coefficients for days 0–731, not the Excel workbooks, official artwork, or WHO software. No runtime scraping or health-data upload is involved.

The calculation uses `z = ((kg/M)^L - 1)/(L*S)` (logarithmic limit when L = 0) and the standard normal cumulative distribution to convert z to percentile. The plotted 3rd, 50th, and 97th curves use inverse LMS. The first postnatal day's actual coefficients are preserved; we do not interpolate monthly values or smooth early weight change away.

The UI rounds percentiles to whole ordinals and presents the tails only as **below 1st** or **above 99th**. It does not report extreme z-scores; WHO's extended-tail z-score procedure is therefore not exposed as a clinical result. Reference calculations use kilograms independently of bottle volume units.

## Age and scope

The calculation uses the measurement date, birth date, and family reporting calendar, never the child's age when viewing the chart. Daily ages cross midnight in that calendar, including DST. The explicitly entered child gender supplies a default Boys/Girls reference. An optional `growthReferenceSex` field overrides that default, and existing overrides always win. The editor keeps this option under Advanced growth settings. An independent optional `colorTheme` controls appearance and never participates in the calculation. These travel in the existing versioned child-profile payload. Older profiles decode with both optional fields absent; profiles without gender or an override still need a reference before percentiles are shown.

This release covers measurements before the child's second calendar birthday. Calendar boundaries, rather than rounded months or a hardcoded 730-day cutoff, handle leap years. WHO tables use 30.4375 days/month for drawing a monthly axis; our chart instead uses calendar dates and integer day-of-age rows.

Swaddle now uses WHO only for all growth comparisons. For a known preterm birth (before 37 weeks), primary weight comparisons use corrected age from the estimated 40-week due date, and the detail also shows WHO at actual age since birth. Both use the measurement date and the same resolved Boys/Girls reference. The primary percentile is not repeated above the paired comparison. Before the due date, corrected-age WHO is unavailable; the original measurement and actual-age comparison remain visible. The table is never extrapolated or clamped to day zero. Term and unknown-gestation profiles retain a single actual-age WHO result.

This is the product's WHO-only comparison policy, chosen October 12, 2026. It does not claim that WHO replaces a clinician's separate preterm growth reference. The app no longer includes INTERGROWTH calculations or curves. Historical source files remain in `ReferenceData/Preterm` for provenance, outside the app target.

- [WHO Child Growth Standards](https://www.who.int/tools/child-growth-standards/standards/weight-for-age) supplies the reference data.
- [AAP corrected age for premature babies](https://www.healthychildren.org/English/ages-stages/baby/preemie/Pages/Corrected-Age-For-Preemies.aspx) explains counting from the estimated due date.

## Verification

One hundred reference fixtures come from WHO's independently published **percentile** workbooks, while production coefficients come from its **z-score** workbooks. Boys and girls are checked at days 0, 1, 7, 30, 60, 90, 180, 365, 730, and 731 for the 3rd, 15th, 50th, 85th, and 97th centiles. Tests allow 0.08 percentile points for WHO's gram rounding and 0.51 g for inverse-curve comparisons. Tests also cover missing data, appearance independence, invalid values, corrected-age due-date boundaries, leap years, DST, same-day measurements, sibling isolation, and persistence without modifying care history.
