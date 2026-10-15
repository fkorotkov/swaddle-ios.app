# Care data contract

These rules describe the data boundaries and calculations that changes to Swaddle must preserve. The [README](../README.md) describes the product; domain types and regression tests are the executable contract.

## Family, identity, and access

- One active family contains children, caregivers, and shared care records. Family access covers every current and future child; it is not a separate permission per child.
- Child activity carries explicit family and child UUIDs. Pumping carries family and pumping-caregiver UUIDs, with no child ID. The pumping caregiver and recording author can be different people.
- Names are display values, never identity keys. Renaming a profile must preserve its history, widget configuration, and configured actions.
- Owners manage family access. Editing participants can record and correct shared entries; view-only participants cannot mutate them through the UI, Siri, imports, or widgets.
- Care records are shared. Bottle defaults are private preferences keyed by family, child, and caregiver. Device display preferences do not change family data or permissions.

## Logging and quantities

| Record | Invariant |
| --- | --- |
| Diaper | Pee, poo, or both. Both is **one change** that contributes to both wet and soiled counts. |
| Bottle | Milk and prepared formula consumed are separate nonnegative quantities; at least one is positive. Their sum is bottle intake. |
| Nursing | Active duration and side come from timer segments or manual entry. Pauses do not count. Never infer consumed volume from minutes. |
| Pumping | Expressed volume belongs once to the pumping caregiver. It never contributes to a child's intake or duplicates when switching children. Total-only entries do not imply a left/right split. |
| Measurements | Preserve the original measurement, date, unit, and applicable position/method. Growth comparisons do not rewrite the entry. |
| Care note | Text remains a note; mentioning a bottle or diaper does not silently create structured events. |

Every saved record preserves occurrence time, creation time, source, author, and stable identity. A completed event cannot occur in the future. Confirm success only after durable local save; an upload failure is separate from a failed save. Retried commands retain their IDs, and Undo targets the specific creation.

New manual bottles can use that caregiver's last successfully saved composition for that child. Imports, historical edits, cancelled drafts, and another caregiver's entries do not replace that default. Explicit Siri amounts override defaults; only the usual-bottle action confirms remembered amounts. Pumping drafts use the selected pumping caregiver's latest eligible session by occurrence time. No prior entry means blank amounts, and background updates must not overwrite an open draft.

Canonical volume is decimal mL. App entry and display use **1 oz = 30 mL**, with 0.25 oz or 10 mL step controls; exact entry remains possible. Unit switches and display rounding never rewrite stored amounts. Pipe-delimited imports preserve their declared US-fluid-ounce conversion, and JSONL preserves its numeric mL fields; see [import formats](../IMPORT_FORMAT.md).

Canonical weight is grams, length/head circumference is centimeters, and temperature is Celsius. Weight uses decimal kg or pounds plus ounces; mass ounces are independent of bottle-volume ounces. Sum canonical values before formatting. Volume, weight, and length display preferences remain independent.

## Time and summaries

For reference instant `t`, the rolling window is **`t - 86,400 seconds < occurredAt <= t`**, including across daylight-saving changes. Include eligible completed, nondeleted records for the selected family and child. Pumping summaries instead scope by family and pumping caregiver. Recalculate as records, time, or foreground state change.

```text
changes = peeOnly + pooOnly + both
wet     = peeOnly + both
soiled  = pooOnly + both
```

Wet and soiled overlap; adding them does not give the number of changes. Bottle intake excludes pumping, nursing duration, unfinished drafts, and deleted records.

Calendar charts use the family's shared reporting time zone. An event belongs to its occurrence date, not its entry date. Seven days includes today and the preceding six dates; today is partial. Travel does not silently change the family's reporting calendar. Missing records mean “No entries,” not proof that no care occurred.

Growth comparisons use the measurement date and the recorded birth/reference information. The current implementation uses WHO only, including its corrected/actual-age policy. Keep source provenance, bounds, position adjustments, and independent fixtures with the [weight](../ReferenceData/WHO/README.md) and [length/head](../ReferenceData/GrowthMeasurements/README.md) data. Milestone wording and age bands retain their [source provenance](../ReferenceData/Milestones/README.md); observations support an exact first-noticed date.

## Revisions and profile changes

Records use versioned payloads and immutable revisions with parent links. Independent offline inserts survive together. Concurrent edits retain their competing heads for review; a stale edit must not silently resurrect a deletion. See [iCloud synchronization](icloud-sync.md) for transport and recovery.

Deleting an unlinked caregiver hides the profile from new-entry choices while retaining history and authorship. Current, owner, linked, conflicted, or unfinished-session profiles have additional protections enforced by the caregiver rules. Deleting a profile does not revoke CloudKit access.

Merging profiles preserves the destination ID and resolves the duplicate through a recoverable alias. Original record IDs, quantities, ownership references, and authors remain intact; projections combine the histories. New entries use the canonical caregiver ID. Merging does not deduplicate similar sessions or change share participants. Concurrent account linking must not be discarded by deletion or merge.

Deleting a child preserves siblings and family pumping; it must not delete the family's shared zone. Deleting a family, leaving a share, deleting a record, and removing a caregiver are distinct operations.

## Demo and derived data

Demo records live in an isolated in-memory store with separate disposable preferences. Exiting demo or terminating the process ends that session. Demo changes never sync, publish widget snapshots, or index into Siri, and must not mutate the real family.

Widget snapshots, chart series, summaries, and search indexes are derived data. Rebuild them from current permitted records; never use them as the authoritative care log. Access loss and account changes clear or suspend publication as appropriate. A server acknowledgment does not establish delivery to another caregiver's phone.

## Verification

Run `swift test` for domain, reference, replica, and recovery regressions. Run the app-hosted `LittleLogTests` through the shared Xcode scheme for persistence and UI integration boundaries. Siri and family sharing also need device checks; local tests cannot establish speech recognition or cross-account delivery. Use fictional records for QA.
