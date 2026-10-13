# Siri AI integration: implementation and validation

## October 4 bottle invocation investigation

A user reported that asking to record a bottle only opened Swaddle. Build 20's extracted metadata still defines `RecordBottleIntent` as a background action (`openAppWhenRun: false`) that provides a dialog, requires authentication, and registers “Record a bottle in Swaddle.” Its implementation does not navigate to the app's home screen. The physical-device failure is not yet reproduced, so neither a speech-routing failure nor an intent-execution failure is established as the cause.

Computer QA on the iPhone 17e / iOS 27.2 simulator invoked the built-in action from the system Shortcuts app, without constructing a personal shortcut. It asked for units, contents, and quantity, then saved a fictional 3.5 oz formula bottle for the only child, Casey, without asking for the child's name or opening Swaddle. The system displayed the successful result; subsequently opening Swaddle showed exactly one feed, 105 mL formula, and 0 mL milk. A preceding cancelled invocation saved nothing. This verifies system action execution and persistence, **not Siri speech recognition**. Evidence is in `.build/siri-bottle-investigation/`.

The follow-up source change refreshes App Shortcut registration at every app launch independently of family-list changes, adds “Record the bottle,” “Log a bottle in,” and “Log a bottle with” variants, and supplies the explicit unit question “Milliliters or ounces?” The compiler still extracts 18 actions and eight shortcuts, with four bottle phrases and background execution. The three existing bottle-dialog regression tests pass. A repeat system-action run on the updated simulator displayed the new unit question and was cancelled before amounts were entered. These are discovery and prompt improvements, not proof that the reported iPhone symptom is fixed. They have not been released.

Next physical check: unlock the iPhone, invoke “Record a bottle in Swaddle,” and capture Siri's first response. If no parameter question appears, compare direct execution of the built-in bottle action with spoken invocation on that same device. Cancel before submitting amounts to avoid test entries in the family's log. Apple's [App Intents sample](https://developer.apple.com/documentation/appintents/acceleratingappinteractionswithappintents) documents launch-time registration and the distinction between an intent and its phrase-based discovery.

## September 24 integration audit

Updated September 24, 2026 against Apple's current documentation and the installed iOS 27.2 SDK/Xcode 27.2. This describes **current source and simulator evidence**, not a released TestFlight build or verified speech recognition.

Swaddle now implements Siri AI schemas for real care notes and search/open navigation, permission-aware persistent content entities, Spotlight indexing, text transfer, and onscreen context. Custom bottle, diaper, pumping, and feeding-total actions remain registered through App Intents and eight App Shortcuts. People can use those registrations through Siri without constructing a shortcut.

## Verified compiled contract

`Metadata.appintents/extract.actionsdata` in the current simulator build contains:

| Item | Result |
| --- | --- |
| App Intent actions | 18 |
| Existing automatic App Shortcut registrations | 8, preserved |
| Schema actions | `SearchCareHistoryIntent`: `system.searchInApp`; `OpenCareRecordIntent`, `OpenCareNoteIntent`, `OpenFeedingReportIntent`: `system.open`; `CreateCareNoteIntent`: `notes.createNote` |
| Schema entities | `CareNoteEntity`: `notes.note`; `CareNotesFolder`: `notes.folder`; `CareNotesAccount`: `notes.account` |
| Other persistent content | `CareRecordEntity`, `FeedingReportEntity` |
| Content export | Plain text, with current access checked and report totals recalculated |
| New schema visibility | Assistant-only; hidden from the Shortcuts action picker |
| Availability | New schemas require iOS 27; original logging and answer actions retain iOS 26 support |
| Authentication | All actions require authentication; system search/open require local-device authentication |

Run `python3 scripts/verify_siri_metadata.py '/path/to/Little Log.app'` after building or archiving. Current schema associations are in each action/entity's **`assistantDefinedSchemas`**. The old top-level `assistantIntents` and `assistantEntities` arrays remain empty in this SDK and must not be used alone to infer absence of Siri AI schemas. The script also checks the App Intent description restriction that caused the earlier ITMS-90626 rejection.

## Implemented behavior

### Real care notes

Only `.careNote` records conform to the Notes schema. A child is a note collection; the family is the account. The first line of plain text is the note title. A new note is saved through the same validation and persistence path as UI entries, preserving family permissions and authorship. One child resolves without a child question; multiple children require a collection choice. Unsupported attachments or pinning return an explicit error.

A note mentioning “90 mL and a wet diaper” remains one text note. It cannot silently create a bottle or diaper. Feeds, measurements, and pumping are custom care-record entities, not disguised notes. See Apple's [Notes domain](https://developer.apple.com/documentation/appintents/app-schema-domain-notes) and [create-note schema](https://developer.apple.com/documentation/appintents/appschema/notesintent/createnote).

### Content discovery and access

**Family → Siri → Care history in Siri & Search** is a local preference for the current family, enabled by default on iOS 27. It indexes the current family's completed, nonconflicting records, including shared pumping. The same preference controls onscreen record awareness. Explicit opt-outs survive reloads and future launches; disabling it clears the index and visible context. No family or unavailable access keeps discovery off. It does not change family sharing permissions. The index uses the name `SwaddleCareHistory` and complete file protection. Import bookkeeping appended as original JSON is excluded from searchable prose; original saved records are untouched.

Index writes are serialized and coalesced. Edits replace indexed content; deletion of records or their child/caregiver removes content. Observed account changes, unavailable family state, or disabling the setting clear the index. A reindex delegate rebuilds from current permitted data. A failure requests a clear and leaves a retry status. This cannot promise immediate recognition of a remote revocation on an offline or suspended phone.

Entity queries, reading, opening, note creation, and content export independently check current readiness and consent. Stable IDs contain family plus record/child identifiers; another family's ID never falls back to the selected child. A stale system result is rejected if its record no longer exists or is no longer eligible. Apple's [indexing guide](https://developer.apple.com/documentation/appintents/making-app-entities-available-in-spotlight) distinguishes entity indexing and custom item association; Swaddle uses custom `CSSearchableItem` IDs with `associateAppEntity` and the corresponding delegate.

### Search, context, and data answers

The [search-in-app schema](https://developer.apple.com/documentation/appintents/appschema/systemintent/searchinapp) opens matching care history. Search uses word prefixes, case/diacritic folding, and current data. The [open schema](https://developer.apple.com/documentation/appintents/appschema/systemintent/open) navigates to a record, note, or report. Spotlight user activities are handled on warm and cold entry. These routes read data; opening a result does not edit it.

Visible history records and feeding summaries carry their actual entity identifiers. Text transfer resolves a current record or recalculates a report instead of exporting a captured total. This follows Apple's [onscreen-context guidance](https://developer.apple.com/documentation/appintents/providing-contextual-cues-to-apple-intelligence-and-siri). `SyncableEntity` identifies the same shared content across devices; `OwnershipProvidingEntity` marks records/reports as shared. Neither replaces access checks.

Feeding reports keep stable family/child/period IDs and expose separate numeric properties for milk, formula, unknown split, total bottle intake, bottle count, and nursing minutes, plus reporting zone and calculation time. They are **not indexed in Spotlight**. Queries, export, and the existing `GetFeedingIntakeIntent` recalculate from `FeedingReport`. Pumping never enters child intake. A result already shown by the system still describes its stated calculation time; Swaddle cannot force Siri to discard an earlier conversation answer.

### Voice-first interface and bottle dialogue

Today leads with **Just ask Siri**. The settings screen is named **Siri**, with native controls, example phrases, and the discovery opt-out near the top. The app no longer links into Shortcuts setup.

“Record a bottle in Swaddle” asks breast milk, formula, or both when quantities are absent, then asks only for missing components. Formula-only logging does not request milk. Explicit quantities remain authoritative and conflicting contents are rejected. Only the explicit usual-bottle action uses remembered values, after confirmation. Existing action IDs and amount parameters are preserved; the new contents parameter is optional.

## What this does not establish

- Apple still has no public newborn-care, bottle, diaper, or pumping schema in the [current domain catalog](https://developer.apple.com/documentation/appintents/app-schema-domains). There is no supported API found for registering our own arbitrary domain with Siri's orchestrator. Native schemas describe recognized actions; adding unrelated optional parameters does not teach bottle logging. See [schema adoption](https://developer.apple.com/documentation/appintents/making-actions-and-content-discoverable-by-apple-intelligence).
- The eight App Shortcuts remain the discovery/phrase layer for custom logging. They are app-supplied registrations, not a requirement to use the Shortcuts app. Removing them would remove the established route for these custom voice commands. See [App Shortcuts](https://developer.apple.com/documentation/appintents/app-shortcuts) and Apple's [Siri design guidance](https://developer.apple.com/design/human-interface-guidelines/siri/).
- `SyncableEntity` supports identities across synced devices; it is not a remote command relay. `IntentExecutionTargets` selects a process, not a remote device. This change adds no watchOS companion, web endpoint, or HomePod relay. Actual Apple Watch/HomePod invocation and authentication remain unverified. See [SyncableEntity](https://developer.apple.com/documentation/appintents/syncableentity) and [execution targets](https://developer.apple.com/documentation/appintents/intentexecutiontargets).
- UI interaction donations and broader structured property queries are not implemented. Existing system-invoked actions may be donated by the system. Do not infer arbitrary conversational logging from the new note/search capabilities.
- No public release, physical-device installation, two-account Siri test, or actual iOS 27 Siri AI conversation was performed for this change. No live family records or system discovery settings were changed.

## Verification

- **73 domain tests** pass, covering care-record identity, family isolation, completed/current projections, notes vs feed semantics, source preservation, search matching, and rolling report freshness, alongside all import/logging regressions.
- **38 app tests** pass through Xcode MCP, including index edit/delete/clear/rebuild, in-flight opt-out, family replacement, failure/retry, default-on discovery, persistent opt-out, deep-link access, note writes, single/multiple/deleted children, and guided formula/mixed-bottle input. Index lifecycle tests inject an isolated backend; they do not prove that the system has retrieved a record through Siri.
- Compiled metadata passes the schema/availability/authentication/content-export/description checks above.
- Native previews were checked on iOS 27.2 and iOS 26.2, including dark mode, Accessibility 3, a narrow iPhone, search results, and record detail. All fixtures are fictional and disable system publication.

## Physical-device acceptance before marketing or release claims

Use an isolated fictional family; avoid creating test records in the real care log.

| Prompt or action | Expected result |
| --- | --- |
| “Record a diaper in Swaddle” | Ask contents when needed, then save exactly one change; no child question with one child. |
| “Record a bottle in Swaddle”; choose formula and 130 mL | Ask only necessary details; milk zero, formula 130 mL. |
| “Record 130 mL of formula 30 minutes ago in Swaddle” | Correct type, quantity, unit, and time, or clarification. This one-sentence variation is not yet verified. |
| “How much did Robin eat in Swaddle?” | Current deterministic totals with milk/formula/unknown split and separate nursing time. |
| “Create a note in Swaddle called Evening observation: Robin settled after feeding” | A single care note for the resolved child; no structured feed. |
| “Find Robin's note about settling in Swaddle” | A permitted care note, correct content and date. |
| “Search Swaddle for Robin bottle” | Open matching care history. |
| Open a found record; refer to “this” | Onscreen context resolves the actual visible record; no sibling leakage. |
| Delete/edit a record, disable discovery, change account, revoke access | Removed content no longer resolves; index cleanup follows observed state. |
| Ask again after an entry crosses the 24-hour boundary | Fresh total from the query/export path; no cached indexed rolling total. |

Repeat typed and spoken, with app foreground/background/terminated, authentication required, Apple Intelligence available/unavailable, and one/multiple children. Check the query/action used, saved data, and spoken answer separately. Test other devices only after selecting the intended Apple Watch/HomePod configuration. Siri routing and available experiences remain system-controlled.
