# Swaddle JSON Lines import, version 1

Open **Paste care notes → Format tips & missing units → Advanced: JSON Lines** for the in-app guide and separate **Copy feeding export instructions** and **Copy pumping export instructions** buttons.

Paste one complete JSON object per line in the existing Care notes field. The first non-whitespace character being `{` selects JSONL. Blank lines are allowed; do not include headings, code fences, or an enclosing array. Version 1 supports **bottle feeds for one selected child** or **pumping sessions for one selected caregiver**. Import these as separate batches so every record has one unambiguous target.

## Bottle feeds

```jsonl
{"type":"feed","version":1,"occurredAt":"2026-05-10T08:30:00-04:00","breastMilkML":60,"formulaML":15,"totalML":75,"notes":"Finished bottle.","source":"example-app","id":"feed-123","timezone":"America/New_York"}
{"type":"feed","version":1,"occurredAt":"2026-05-10T11:30:00-04:00","breastMilkML":null,"formulaML":null,"totalML":90,"notes":"Split not recorded.\nCaregiver observation."}
```

| Field | Required | Meaning |
| --- | --- | --- |
| type | Yes | Exactly `"feed"` for bottle feeds. |
| version | Yes | Integer `1`. |
| occurredAt | Yes | ISO 8601 date and time, including seconds and an explicit UTC offset or `Z`. Fractional seconds are accepted. |
| breastMilkML | Yes | Nonnegative JSON number in mL, or `null` when the split is unknown. |
| formulaML | Yes | Nonnegative JSON number in mL, or `null` when the split is unknown. |
| totalML | Yes | Positive JSON number in mL. |
| notes | No | Original caregiver wording. Escape embedded newlines as `\n` and quotes as `\"`. |
| timezone | No | IANA zone such as `America/New_York`; its offset at occurredAt must match the timestamp. Without it, the explicit timestamp offset is retained. |
| id | No | Nonempty, stable string identifying the original source entry. |
| source | No | Nonempty exporting-app name. Requires id; defaults to `jsonl` when id is supplied without source. |

Field names are case-sensitive. Unknown fields are rejected so typos cannot silently discard values. Numeric amounts must not be quoted strings, fractions, or unit-labelled text. Preserve the source’s recorded mL whenever available. If a source uses exact US fluid ounces, convert with **1 US fl oz = 29.5735295625 mL**; if it uses Swaddle’s convenient bottle convention, use **1 oz = 30 mL**. Do not reconvert existing mL fields. The import preserves these values even though Swaddle displays ounces using 30 mL per ounce. Pipe-delimited external exports continue to interpret ounce components as exact US fluid ounces.

For a known split, supply both numeric components, using zero for the absent component of a pure milk/formula bottle. Their sum must be positive and match totalML within **0.01 mL** for export rounding. The component sum is the saved intake; the original stated total remains in the saved source text.

For an unknown split, use **null for both components** and keep the known positive totalML. Swaddle retains this as “Split not recorded,” separately from milk and formula. One null component with one known component is rejected; no quantities or composition are inferred.

Explicit timestamps take priority over the First date and family time-zone settings. Invalid dates and mismatched time zones are rejected. Future dates require correction before saving.

## Pumping sessions

Use **Family → caregiver’s pumping → Import pumping**, or paste pump JSONL into **Paste care notes**. The first object’s `"type":"pump"` selects pumping. Choose the pumping profile once for the entire batch; no child, email, or caregiver ID is required in the file. If needed, create a pumping profile before reviewing. You can import history before inviting that caregiver.

```jsonl
{"type":"pump","version":1,"occurredAt":"2026-05-10T08:30:00-04:00","totalML":105,"leftML":60,"rightML":45,"durationMinutes":15,"notes":"Morning session.","source":"example-app","id":"pump-123"}
{"type":"pump","version":1,"occurredAt":"2026-05-10T12:30:00-04:00","totalML":103.50735346875,"leftML":null,"rightML":null,"durationMinutes":null,"source":"example-app","id":"pump-124"}
```

| Field | Required | Meaning |
| --- | --- | --- |
| type | Yes | Exactly `"pump"`. |
| version | Yes | Integer `1`. |
| occurredAt | Yes | Same explicit ISO 8601 timestamp rules as feeds. |
| totalML | Yes | Positive JSON number in mL, or null if both side amounts are known. Decimal precision is retained. |
| leftML, rightML | No | Both nonnegative numbers, or both null/omitted when unknown. Never infer a side from the total. |
| durationMinutes | No | Positive JSON number; null/omitted when unknown. |
| notes, timezone, id, source | No | Same string fields and validation as feeds. |

Known sides must add up to a stated totalML within **0.01 mL**; their sum is the saved volume, and the originally stated total stays in the source text. A null totalML is accepted only when both sides are recorded and have a positive sum. Review labels that total as calculated from the recorded sides. With unknown sides, a positive totalML is required and saved exactly. Display rounding does not change stored precision. Pumped milk is **separate from child intake**, and the importer retains the pumping caregiver independently of the person doing the import.

Source/ID duplicate checks are scoped to the family and pumping caregiver. Existing IDs are excluded even if amounts or notes changed. Without a matching ID, sessions less than 60 seconds apart with total volumes within 0.01 mL start deselected as possible duplicates; they can be selected after review. Feed and pumping IDs are independent.

## Validation, duplicates, and saving

- Up to **50,000 characters or 500 lines** per batch. CRLF line endings and a leading UTF-8 BOM are accepted.
- Every nonempty line must contain one valid object. A malformed or unsupported line stops the entire parse with its line number; the app does not fall back to natural-language interpretation or save a partial batch.
- All objects are parsed locally without Foundation Models. Incidental amounts, symptoms, and times in notes never create extra activities.
- Review the child or pumping caregiver, dates, and amounts before saving. Original JSON and readable note wording are retained.
- Stable source/ID pairs are scoped to the selected family and child. Keep both unchanged between exports. A matching pair is excluded even when amounts changed; imports never overwrite an existing entry. Correct an existing entry through its normal editor.
- Without matching IDs, the existing similarity check flags entries within 60 seconds whose corresponding milk/formula/unknown components differ by no more than 0.01 mL. Those potential duplicates start deselected and can be reviewed.
- The save validates the entire selection and rechecks IDs before writing one transaction. Importing does not alter remembered bottle amounts. One Undo removes the batch; a fresh review can import it again afterward.

Import identity is optional metadata inside the existing encoded activity or pumping payload; no CloudKit schema migration is needed. Older app versions can read ordinary sessions but do not protect new import metadata when editing them. Update family devices before editing imported sessions, and use the updated app for structured imports.
