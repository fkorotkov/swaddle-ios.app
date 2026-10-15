# Siri and widgets

Siri and widget actions use the same permission checks, validation, and local persistence as in-app logging. Stable family, child, caregiver, and command identifiers prevent a system action from silently targeting another record or family.

## App Intents and discovery

[`LogIntents.swift`](../BabyActivityRecorder/Intents/LogIntents.swift) defines the custom care actions and eight automatic App Shortcuts. People do not need to construct a personal shortcut to use these registrations. App launch refreshes registration; localized phrase catalogs ship with the app.

| Example phrase | Action |
| --- | --- |
| “Record a diaper in Swaddle” | Ask for contents when omitted; pee, poo, or both saves one change. |
| “Log a wet and dirty diaper in Swaddle” | One combined diaper, never two changes. |
| “Record a bottle in Swaddle” | Ask for missing unit, contents, and amounts. |
| “Record the usual bottle in Swaddle” | Read back remembered amounts and request confirmation. |
| “Log expressed milk in Swaddle” | Pumping for the resolved pumping caregiver. |
| “How much did my baby eat in Swaddle?” | Recalculate intake, keeping nursing and pumping separate. |

An explicit child wins; one available child resolves automatically, and multiple children require disambiguation. Pumping resolves a caregiver rather than a child. Explicit quantities remain authoritative, formula-only input does not ask for milk, and cancellation before saving creates no entry. All actions require authentication and current access.

Siri speech recognition and routing are system-controlled. Valid extracted metadata and a successful Shortcuts execution do not prove a particular spoken phrase, arbitrary one-sentence logging, app-name-free invocation, or remote-device behavior.

## Care content on iOS 27

[`CareContentIntents`](../BabyActivityRecorder/Intents/CareContentIntents.swift) and [`CareContentEntities`](../BabyActivityRecorder/Intents/CareContentEntities.swift) add search/open and Notes schemas behind iOS 27 availability checks. The custom logging actions retain iOS 26 support.

Only actual care notes use the Notes schema. A note mentioning a feed remains text; it cannot create a bottle or diaper implicitly. Records, notes, and feeding reports expose stable identities and permission-checked plain-text export. Feeding reports recalculate when queried or exported and are not indexed as cached rolling totals.

**Settings → Siri → Care history in Siri & Search** controls history discovery and onscreen record awareness. It is enabled by default on supported systems, with a persistent local opt-out. Disabling it clears indexed and visible context. Queries and exports independently recheck consent and current family access. Index cleanup follows detected edits, deletions, account changes, and access loss; an offline phone cannot discover remote revocation immediately.

[`SiriDiscoveryIndex`](../BabyActivityRecorder/Intents/SiriDiscoveryIndex.swift) serializes and coalesces indexing. IDs include the family and record/child identity; a stale or foreign ID must not fall back to the selected child. Demo data never publishes into discovery. Cross-device entity identity is not a remote command relay.

## Widget execution and snapshots

[`LittleLogWidgets`](../LittleLogWidgets/) contains Home and Lock Screen actions, summaries, and the combined care widget. Widget configuration identifies the family and child independently of the app's current selection. Summary data is a derived snapshot with freshness/access information; refresh is system-scheduled and cannot guarantee real-time delivery.

[`WidgetDiaperIntent`](../BabyActivityRecorder/Intents/WidgetDiaperIntent.swift) requires authentication and routes writes to the main app's persistence stack. It uses stable command IDs to avoid duplicate saves; the extension must not pretend that a cache write is a saved care record. Bottle links open an editor rather than saving an assumed amount. Undo retains the original command's identity. Display-unit changes do not rewrite care data.

## Verification

After building or archiving, validate the actual extracted metadata and compiled localized resources:

```sh
python3 scripts/verify_siri_metadata.py '/path/to/Little Log.app'
```

The verifier checks schema associations, availability, authentication, persistent content/export, the eight shortcut registrations, distinct diaper/pumping phrase bindings, translations, and widget execution targets. It reads `assistantDefinedSchemas`; empty legacy top-level schema arrays alone do not establish that an integration is missing.

Run the app-hosted bottle-dialog, Siri discovery, and widget quick-log tests through the shared Xcode scheme. On a device, separately check spoken routing, parameter prompts, cancellation, saved values, and returned answers with one and multiple children, authentication, and foreground/background entry. Use an isolated fictional family. Verify freshness across a reporting boundary and removal after opting out or losing access before making claims about those system experiences.
