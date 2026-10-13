# Archived preterm growth reference

**Historical implementation only.** As of October 12, 2026, Swaddle uses WHO only. INTERGROWTH calculations, curves, and product attribution have been removed from the app. These source documents and historical implementation notes are kept outside the app target for reproducibility. The description below documents the retired implementation; it does not describe current behavior.

# Preterm weight-for-age

The retired implementation used the **INTERGROWTH-21st (2015) postnatal preterm weight standard**. This is a named reference comparison, not a diagnosis, treatment target, fetal-weight chart, or birth-size classification. Oxford does not endorse Swaddle. A pediatrician may use Fenton or another reference and obtain different percentiles.

## Sources and implementation

- [Oxford's official preterm resources](https://intergrowth21.com/tools-resources/postnatal-growth-preterm-infants), checked October 11, 2026.
- [Villar et al., 2015, Lancet Global Health](https://intergrowth21.com/node/142), DOI `10.1016/S2214-109X(15)00163-1`. The longitudinal study comprised 201 preterm singletons born at 26 to <37 weeks, without major complications affecting growth. Weight uses a natural-log transformation, fractional-polynomial mean and SD, and a sex adjustment. The authors describe transitioning to WHO after 64 weeks postmenstrual age.
- The numerical equations in `PretermWeightForAge.swift` are adapted from **growthstandards**, `R/standard_igprepost.R`, at [commit d06a4898c286a3ab9111a5e3525c3b9d0e9ae8aa](https://github.com/ki-tools/growthstandards/blob/d06a4898c286a3ab9111a5e3525c3b9d0e9ae8aa/R/standard_igprepost.R), under its [MIT license](https://github.com/ki-tools/growthstandards/blob/d06a4898c286a3ab9111a5e3525c3b9d0e9ae8aa/LICENSE.md). The full notice is included in the app under About growth percentiles → Calculation credits and in the source constant `codeLicense`.
- Independent expected values come from Oxford's [Boys centile table](https://intergrowth21.com/sites/default/files/2023-02/grow_preterm-ct-boys_bw_table.pdf) and [Girls centile table](https://intergrowth21.com/sites/default/files/2023-02/grow_preterm-ct-girls_bw_table.pdf). Their PDF SHA-256 values are `7d9bab87610ce93c81538a5104f8bc4f481f448299bb550d367454d1b13b347c` and `cd1f368fd1f21045f1295f7217b31220162ada25ab1935a51521d5d5ed36cf4c` respectively.
- We do not redistribute official chart artwork, the paper, patient-level research data, or GPL implementations. All app calculations are offline; opening a source link does not include a child's data.

For exact postmenstrual age `w` in weeks (`integer calendar days / 7`), the mean of log(weight in kg) is `2.591277 - 0.01155 * sqrt(w) - 2201.705 / w² + 0.0911639 * isBoy`. SD is `0.1470258 + 505.92394 / w² - 140.0576 * ln(w) / w²`. The standardized value is `(ln(kg) - mean) / SD`. The normal CDF supplies percentiles; the inverse `exp(mean + z * SD)` supplies reference curves.

## Bounds and transition

The app limits this reference to **27w0d through 64w0d postmenstrual age**, the exact domain of the official tables, and **birth gestation 26w0d through 36w6d**. It deliberately does not use the wider extrapolation guards found in the older R implementation. Unsupported earlier weights remain visible without invented percentiles.

PMA = gestational age at birth + calendar days since birth **on the measurement date**, in the family's reporting timezone. For a known preterm birth, after 64w0d, `WeightForAge` routes to WHO using corrected age (PMA minus 40 weeks). Term or unknown gestation continues to use WHO with chronological age. All comparisons stop at the second calendar birthday. Unknown gestation cannot be inferred from a name, due date guess, color, or weight.

Each chart detail and accessible measurement names the reference, sex reference, and age basis. A chart spanning the transition uses separate curve identities, never a continuous line implying one standard. The UI explains the change because it can alter a percentile without a sudden change in the child's weight. The legacy WHO-specific evaluator retains its 50-week minimum; the combined chart policy uses the INTERGROWTH-specific 64-week transition.

No new profile field, stored percentile, care-record migration, or CloudKit schema is required. Existing gender defaults and explicit sex-reference overrides apply to both standards; appearance does not affect calculations.

## Verification

`Tests/PretermWeightReferenceFixtures.swift` transcribes the 3rd, 50th and 97th numerical weights for every exact week 27–64, both sexes: 228 independent comparisons. Oxford's tables round to 10 g and the equation coefficients are rounded; all comparisons are within 6 g (observed maximum 5.4 g). Percentile tests also bracket each published value by that tolerance. The UI presents whole percentiles and labels the tails below 1st / above 99th.

Additional tests cover PMA from weeks plus days, measurement date rather than current date, DST, the 26/27/37/64-week boundaries, WHO corrected-age transition, missing data, invalid weights, future measurements, second birthdays, and separated chart curves. Run `swift test` for these and the existing WHO reference tests.

## Fenton research and remaining distinction

[Fenton's official University of Calgary page](https://ucalgary.ca/resource/preterm-growth-chart/preterm-growth-chart) identifies the 2025 third-generation charts and directs commercial app developers to its licensing manager for numerical data. The [2025 study's Data Availability statement](https://pmc.ncbi.nlm.nih.gov/articles/PMC12391854/) describes a separate commercial-use arrangement. Fenton data is **not** bundled, reconstructed from chart pixels, or copied from third-party calculators. Matching a clinician's Fenton percentiles would require obtaining that reference's authorized data and validating a separate implementation. INTERGROWTH is explicitly named in the product; it is not presented as Fenton or as a guaranteed match for the pediatrician's chart.
