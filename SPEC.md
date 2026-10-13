# Swaddle — newborn activity recorder

## Length / height and head circumference

Record both measurements from Today → More or the Add measurement button on their Trends chart. Entries support cm/in, date, note, and the existing child/author/edit/history/delete behavior. Length also records lying-down versus standing position. Canonical centimeters and original unit/position are preserved; one inch is exactly 2.54 cm. The cm/in preference is shared by these Trends metrics and their editors.

Trends adds Length / height and Head circumference alongside Weight, with the same selected-child and reporting-period rules. Native charts show dated measurements, offline reference curves, exact selected details, explicit dismissal, a dated accessible list, and a source/explanation disclosure. Existing motion/value transitions and reduced-motion behavior apply. Missing reference information offers child profile setup; out-of-range measurements remain visible with a specific explanation instead of an invented percentile.

Weight Trends has a device-local kg/lb + oz switch, remembered across visits. Kilograms use decimal values (up to three fractional digits); imperial values use whole pounds and ounces (up to two fractional digits). Ounce rounding carries into the next pound at 16 oz. The readout, selected measurement, list, chart axis, recorded points and reference curves all use the chosen unit. One pound is exactly 0.45359237 kg and contains 16 ounces. Switching units retains the selected date and leaves canonical weights and percentile calculations unchanged; volume and length-unit choices remain independent.

WHO daily sex-specific references cover birth through the fifth calendar birthday for length/head circumference and until the second birthday for weight. For a known preterm birth, all charts use WHO corrected age from the estimated due date until two, then actual age where the reference permits. Under two, details compare corrected and actual age; corrected-age WHO is unavailable before the due date while measurements and actual-age comparisons remain visible. WHO length/height position adjustments are disclosed and affect only the comparison/plotted point. [Sources, bounds, and independent validation](ReferenceData/GrowthMeasurements/README.md).

Both payloads use version 5 of the existing revision envelope, existing family permissions, and existing CloudKit record fields. No data migration or schema deployment is needed. Family members must update to interpret these new measurements. Intake, diapers, and pumping totals exclude body measurements.

**Status:** product specification with native development implementation, September 24, 2026. See [README.md](README.md) and [QA.md](QA.md) for verified behavior and remaining device checks.
**Brand:** Swaddle. App Store listing: Swaddle: Newborn Log (created September 20, 2026).

**Platform:** native iPhone app, with WidgetKit and App Intents. The first App Store release targets iPhone only (confirmed October 12, 2026). App, widget, and test targets use the iPhone device family; native iPad, Mac, and Vision support are outside this release. Mac/Vision availability must also be disabled separately in App Store Connect.  
**Deliverables:** this specification, the [native app](README.md), [ImageGen screenshot gallery](design/index.html), [screen inventory](design/README.md), [exact generation prompts](design/PROMPTS.md), [native previews](artifacts/previews/README.md), and [actual Simulator screenshots](artifacts/simulator-qa/README.md).

## 1. Product intent

Help tired parents record an event with one hand or their voice, and answer three questions quickly: **What happened last? What has been recorded in the last 24 hours? What is changing over time?**

The log is a record of care, not a measure of how well someone is parenting. Use factual language, generous touch targets, quiet colors, and no streaks, scores, normative targets, or unsolicited advice.

### Confirmed requirements

- Diapers: pee, poo, or both in **one event**.
- Bottle feeding: separate milk and prepared formula volumes, including both in one feed. Remember previous amounts and offer them on the next feed.
- Direct breastfeeding: timed or manually entered sessions and breast side.
- Pumping: mother's expressed milk, recorded once for the mother within the family, independently of any child's consumed milk.
- Weight entries; temperature entries are lower priority.
- One family with multiple children, including twins, supported in the first release. Each child has separate activity, measurements, summaries, and remembered feeding amounts.
- A shared family space between parents/caregivers, synchronized through iCloud. One family invitation covers all current and future children in that family.
- Hands-free logging through Siri, including amounts, units, and past times. Child input is optional; with exactly one child, intents resolve that child automatically without asking for a name or selection.
- Siri answers feeding questions directly: total recorded bottle intake, milk/formula split, separate breastfeeding duration, and last feed. Return structured data as well as spoken answers.
- Paste or type a caregiver's free-form notes, review editable proposed entries, and import the selected batch. Preserve observations as optional plain care notes.
- Optimize frequent entry for roughly eight daily uses: logging actions above the summaries, one-tap diaper choices with Undo, remembered bottles, and visible hands-free discovery.
- Last-24-hours widget showing diaper composition and milk/formula consumed.
- Tap a widget's volume area to switch its displayed volumes between mL and oz without opening the app.
- Longer-term dashboard with **both trends and daily routine patterns**.
- Native charts implemented with Swift Charts.

### Decisions still open

1. Whether pumping is visible to all caregivers or private to the mother; this affects the sharing boundary. The mocks currently illustrate shared pumping. The person entering a session can be someone other than the mother.
2. Final app name, supported launch languages, minimum iOS version, and commercial model. None blocks design review.
3. Whether launch includes a pediatrician-friendly export. Recommended next increment: CSV plus a simple printable summary.

### Family and child scope

The product has **one family containing one or more child profiles**. A caregiver belongs to one active family in v1; managing multiple independent families is outside this release. Family membership and permissions apply to all of its children. There is no separate invitation or access list for each child.

Child-scoped records always store an explicit child ID after resolution, even when the person did not need to supply a child in the UI or to Siri. Names are display/lookup values, never database keys. Pumping is mother-scoped within the family and has no child ID; having twins must not duplicate a pumping session or its volume.

## 2. Scope and delivery

| Stage | Outcome |
| --- | --- |
| Capability spike | Prove Siri routing, automatic single-child resolution, multiple-child disambiguation, spoken quantities and past times on physical devices; prove two-account family sharing and cross-process writes; validate widget updates. |
| Core logging | One family with multiple child profiles; diaper, bottle, breastfeeding, mother-scoped pumping, weight, editable history, units, offline storage, accessible light/dark UI. |
| Shared first release | Family-level caregiver invitations, author attribution, offline sync, concurrent edit handling, child-configurable medium/small widgets, Siri baseline, trends and routine view. Sharing and multiple children are part of v1, not postponed optional extras. |
| Small follow-up | Temperature if it delays core quality, export, additional widget families and Live Activities for breastfeeding. |

Not in the first release: sleep tracking, medication, feeding recommendations, inferred breastmilk intake, formula preparation instructions, milk inventory/expiry, predictive schedules, advertising, or a general medical-advice chatbot. The care-note form below is a supported entry workflow. WHO weight-for-age comparisons and sourced milestone check-ins are separately validated additions described below.

## 3. Information architecture

Three tabs: **Today**, **Trends**, **Family**.

- **Today:** compact child name with Today/age beneath it, a hands-free Siri entry point, and a fixed iCloud status button. Show a child switcher when the family has multiple children; with one child, show the name without a selection step. Bottle, Pump, Nurse, and More form one quick-action row. More includes care-note import, backdated diapers, notes, weight, and temperature. A calendar-day view is available but is never mislabeled as “last 24 hours.”
- **Trends:** 7 days / 30 days / custom period; Trends and Routine subviews. The trend metrics are **Bottles, Diapers, Pumping, Weight**. Bottles, diapers, weight, and routine patterns use the selected child. Pumping replaces the nursing-duration chart and shows daily pumped volume and session counts for a named pumping caregiver, with a profile picker when more than one is configured. Its totals are independent of the selected child, use the family reporting time zone and preferred mL/oz display, and remain available when the child has no activity. The list alternative and selected-day details include volume and session count; unrecorded days say **No entries**. An empty period or missing pumping profile has explicit guidance. Direct breastfeeding recording and nursing events in Routine remain available.
- **Family:** family profile, list of children and Add child, caregivers, mother's pumping history, units, Siri setup, widget privacy, export/data settings. Place less frequent Weight and Temperature entry actions in an accessible More sheet as well as their history pages.
- Primary log actions: Bottle, Diaper, Breastfeed, Pump. Each opens a focused sheet with a persistent bottom action.
- Tap a history item to inspect, edit, or delete it. Show event time prominently; author and source are secondary.

The approved compact dashboard (layout A) combines bottle intake and diaper counts in one card beneath the period and mL/oz controls. Place this summary first, then keep both logging rows together beneath it: Bottle / Pump / Nurse / More, followed by the quick diaper choices and Custom. Recent activity follows these controls. This puts frequent logging within easier thumb reach while keeping the overview visible. Keep the milk/formula/unclassified split, bottle count, unique diaper changes, overlapping wet/soiled counts, and pee-only/poo-only/both breakdown. Expressed pumping remains separate from child intake. Group recent history by the family calendar day and show compact rows with amounts, time, author, mixed-feed details, and any notes or edit conflicts. Accessibility text sizes reflow quick actions and summary metrics and use the full history-row layout; touch targets remain at least 44 points. Allow scrolling at large text sizes instead of shrinking fonts or touch targets.

Siri and iCloud status occupy separate native toolbar groups so their independent actions are clear. Ordinary uploading and checking use a fixed-size progress indicator, delayed 400 milliseconds to avoid flashing for quick work. Reduce Motion uses a static sync symbol. A completed server check with no queued uploads shows a green checkmark badge; actual account or sync failures show an amber exclamation badge. Color is paired with a symbol and an accessible status label. Tapping opens pending-upload counts, last upload/check times, recovery information, and Sync now. A successful server check does not claim another caregiver has downloaded changes. Saved/Undo appears as an overlay above the native tab bar; appearing or disappearing must not change the scroll viewport or move dashboard content. Reserve constant bottom scroll space so history can be brought above the overlay.

For a signed-in caregiver with an active pumping profile, place a compact **Your pumping** card immediately below the combined intake/diaper summary and above the logging actions. Show the caregiver's recorded pumped volume and session count for the same **Last 24 hours / Today** period, using the same mL/oz preference. Today starts at midnight in the family's reporting time zone; Last 24 hours is an elapsed 24-hour window. Count sessions logged by other caregivers for this pumper, honor merged profiles and deleted/edited sessions, and exclude other pumpers and future records. Changing children does not change this caregiver's pumping total or add it to bottle intake. An empty period says **No sessions recorded**. Tapping opens this caregiver's pumping history. Hide this card for non-pumping caregivers; their existing ability to record pumping for others remains available. The card uses the neutral pumping palette, adapts to large text, and updates after local saves, Undo, and incoming sync.

Onboarding creates or joins a family. When creating one, ask for the first child's name, optional birth date, and preferred units; offer Add another child without making it mandatory. Family owners and editors can add more children later. Offer family sharing next; local recording must work if iCloud is unavailable. A recipient joins the invited family without first creating duplicate child profiles. Do not require a photo, full legal name, gender, or birth weight to start.

**Baby age and gestational age.** Settings → child profile optionally records the birth date and completed gestational weeks plus additional days at birth. Unknown gestation stays unset; enabling it requires choosing weeks, and additional days are 0–6. Today shows chronological age only: weeks and days before the first calendar month, then calendar months and remaining days. The profile and Milestones use the same chronological-age format. Current gestational age remains in the profile in exact weeks/days; it is gestation at birth plus chronological age (postmenstrual age). The profile previews these ages and the estimated 40-week due date. For births before 37 completed weeks, it also shows corrected age from that due date; before the due date it says “Due in…” and on the date “Due today,” never a negative age. Calculation uses calendar days and months in the family's reporting time zone, so daylight saving does not shorten an age day and months are not treated as fixed 30-day intervals. Ages update as the day changes and when the app resumes. These are date calculations, not feeding targets or developmental assessments. Definitions follow the [AAP's corrected-age explanation](https://www.healthychildren.org/English/ages-stages/baby/preemie/pages/Corrected-Age-For-Preemies.aspx) and [ASHA's neonatal age terminology](https://www.asha.org/practice-portal/clinical-topics/neonatal-intensive-care-unit/common-terminology-and-diagnoses-in-the-neonatal-intensive-care-unit/).

The optional `gestationalAgeAtBirthDays` integer lives in the existing shared child revision payload. Legacy profiles decode with no gestational value; no CloudKit schema deployment or record migration is required. Changing or removing birth details never edits care activity or its totals. Both caregivers should use the current build when editing the new profile fields.

**Milestone illustrations.** Profiles do not collect ethnicity or illustration skin/hair choices. Each of the 106 offline scenes has a fixed cast, selected through a deterministic shuffle with roughly equal representation of six skin palettes, four child hairstyles/hair colors and five adult hair colors. Child, caregiver and incidental appearances are assigned independently. Reopening a scene keeps its cast. Optional caregiver sex selects female/male adult silhouettes, with neutral artwork when unspecified; pumping is an independent choice. Child gender, app colors, growth references and care permissions retain their existing behavior. Older profiles decode safely, and new profile saves omit retired ethnicity/appearance fields without rewriting historical revisions.

Optional caregiver sex remains part of the shared family profile and uses revision-envelope **version 6** when set. All prior envelope versions remain readable. No server schema deployment or Core Data migration is required. Caregiver merges keep an explicit destination sex and fill it from the source only when missing; separation preserves the original duplicate profile. Artwork appearances themselves are bundled scene data rather than shared profile data.

Every child-scoped sheet shows its target child. Opening a draft captures that child ID; switching the app's selected child must not silently move an in-progress draft or timer. Switching children changes the timeline, charts, measurements, and that caregiver's saved feeding defaults together. The current screenshots illustrate Robin; a future visual revision needs the multiple-child switcher and the family child list.

## 4. Logging behavior

### Common event rules

Every event records the family, occurrence time, creation time, author, entry source, and stable ID. Diapers, bottle feeds, breastfeeding, weight, and temperature also require exactly one child ID from that family. Pumping instead records the mother's caregiver/profile ID, which can differ from the person who entered it, and has no child ID. Default occurrence time is now; allow a date/time picker and quick offsets of Now / 30 / 45 minutes ago for bottles and manual breastfeeding, and Now / 15 / 30 for other activities. Show the resolved date/time before saving a backdated event. A future occurrence time is invalid for a completed event; ask the person to correct it.

Save to durable local storage first. Only then show success, update aggregates, request a widget reload, and schedule cloud sync. “Saved on this iPhone” is different from “Shared via iCloud.” A failed local write must not produce a success confirmation.

Prevent repeated taps while saving. Offer an Undo action for the last local creation for 10 seconds, with history editing available afterwards. Undo targets the specific record ID, never an ambiguous global “last event.” Deletion creates a tombstone so it can synchronize safely. For a new bottle, immediate Undo also removes the remembered amounts written by that creation, restoring the previous defaults or a blank draft if none existed. It must leave other children’s defaults and unrelated later preferences intact.

### Diaper

Today shows **Pee / Poo / Both / Custom** across a full-width button row without a separate Diaper label. Custom opens the form to choose the time, contents, and an optional note before saving. Each button's accessibility label identifies the diaper action and child. At accessibility text sizes, stack all four buttons vertically. All buttons retain at least a 44-point touch target.

Two independent controls: **Pee** and **Poo**. Neither is preselected. Save is enabled once at least one is selected. Also offer three explicit quick actions through Shortcuts: pee only, poo only, both.

- Pee only: `hasPee=true, hasPoo=false`.
- Poo only: `hasPee=false, hasPoo=true`.
- Both: `hasPee=true, hasPoo=true` — **one change, not two**.
- “Record only pee” explicitly clears poo; do not reuse a previous combination.
- Optional note belongs behind More details; no mandatory stool color/consistency questionnaire.

### Bottle feeding

Capture amounts **consumed**, rather than prepared bottle size. Two fields: **Milk** and **Formula**. Milk means human milk in a bottle, including expressed/donor milk; formula means prepared formula volume, not powder or water used to prepare it. Both fields are nonnegative; at least one must exceed zero.

Allow Milk / Formula / Both presets. Selecting one source clears the other source and makes the change visible. In Both, record milk and formula components of one feeding event; this can describe the same bottle or consecutive bottles in one session. The app does not give mixing instructions.

**Previous values:**

1. On a new manual bottle draft, restore that caregiver's most recently saved bottle composition for this baby, including both amounts and unit. Explain it with “From your last bottle.”
2. First use starts blank, not with an invented newborn feeding quantity.
3. Cache a successful new entry by `createdAt`; a historical edit, imported record, canceled draft, or another caregiver's entry does not replace the default. A new backdated entry does update the cache because the person deliberately saved that composition.
4. Key the preference by family, child, and caregiver, keeping it private to that caregiver and synchronized across their own devices. A new child starts with blank amounts; another child's saved composition must never populate its first bottle. The feed itself belongs to that child's history inside the shared family.
5. Switching units converts values; it never reinterprets the numeric amount. Do not round the stored quantity on every switch.
6. Never save automatically just because amounts were restored. The primary action says, for example, “Save 120 mL feed.”
7. For Siri, an explicit amount/source overrides defaults. “3 oz of milk” records milk only, with formula zero. Missing amounts prompt for clarification; only an explicit “usual bottle” action uses saved defaults and reads them back before saving.

**Quick adjustments:** Each visible amount has separate 48 pt minus/plus buttons, stepping by **0.25 oz** in ounce mode or **10 mL** in milliliter mode. These are convenient entry increments, not feeding recommendations or a restriction on exact values. Touch and hold repeats. The decrement stops at zero, and an invalid typed amount must be corrected before either adjustment is available.

Keep the keyboard closed when opening a remembered bottle. Tap the amount for precise decimal entry; provide Next: Formula and Done above the keyboard. Update the save total immediately. A matching bottle takes two taps from Today (Bottle → Save); changing one component by one step takes three (Bottle → plus/minus → Save). Changes remain a draft until Save. In compact-height landscape, show only the keyboard controls while editing so the focused amount remains readable; Done restores Save. Portrait keeps Save visible above the keyboard.

Apply step deltas to canonical decimal mL, never to the rounded display text. Unit switching preserves the exact amount; incrementing and decrementing a nonzero value across unit changes must not introduce rounding drift. Milk and formula remain independent. Pumping uses the same amount control. Pairing adjustments with exact text entry follows Apple's stepper guidance [A17].

### Direct breastfeeding

Support left/right timer segments, side switching, pause/resume, and manual duration entry. Each session identifies its child and feeding caregiver. Only one side may run at once within that session. Switching sides closes the current segment and starts another; pausing adds no active time. Separate sessions for different children may overlap, including tandem feeding on different sides. Persist segments, target IDs, and the running start timestamp so backgrounding, force quit, restart, or changing the selected child does not reset or retarget a timer.

The primary value is active feeding duration; elapsed wall time can be longer because of pauses. Finishing creates one session containing all segments. Preserve a recoverable draft before final save. If a timer was left running, offer to correct its end time without asserting what actually happened.

Show each child's session count and total time separately from bottle volume. The last-used-side reminder belongs to the feeding caregiver across their children's sessions; label whose history it describes, and show both/unknown when that is what the records establish. **Never convert minutes into mL or add sessions to consumed volume.** A side reminder is descriptive, not a directive.

If caregivers start overlapping timers for the same child offline, retain both sessions and surface a possible overlap after sync. Do not flag simultaneous sessions for different children as duplicates solely because their times overlap. Never automatically combine or delete them.

### Pumping

Capture expressed volume with either **Total** or **Left + Right** entry. Total mode does not invent a side split. If switching to side mode, ask for the split; if switching back, derive the total from the sides. Optional duration and note; use occurrence time rather than requiring a running timer.

New pumping forms prefill volume from the selected caregiver’s latest non-deleted, non-conflicting session by occurrence time, regardless of who recorded it. Restore both sides only when both were recorded and sum to the total; otherwise prefill Total without inventing a split. Use the current display-unit preference and retain exact stored mL. Show the source session’s amount and date. Selecting another caregiver loads that person’s preset; opening from a caregiver’s pumping history selects that profile. No prior session means blank amounts. The new occurrence time remains Now, with blank duration and notes. Existing-session edits use that session’s own values, and background updates never overwrite an open draft. Prefilling and cancelling do not save a session.

Any caregiver with family editing access may record a session for a pumping caregiver; the recorder does not need a pumping profile. The form identifies **Pumping for** separately from **Recorded by**. Select the sole pumping profile automatically, including when it arrives from iCloud after the form opens; preserve any amount already entered. With multiple pumping profiles, require a choice. With none, offer **Add pumping profile** directly in the form. If the selected profile disappears, require selection again before saving. Explain whether Save needs a pumping profile or a positive volume. Keep pumping ownership, recording authorship, and edit history distinct; retain view-only family permissions.

Label everywhere as **Pumped**, with the mother's name. A session belongs to the mother within the family, regardless of which child is selected in Today, and is recorded **once**. A 105 mL session stays 105 mL when the family has twins; do not create copies or attribute the volume to either child's intake. Pumping entry and intents never require a child. If more than one pumping caregiver is configured, resolve the mother explicitly or ask when ambiguous; the author may be someone else logging for her.

Pumping totals and history remain mother-scoped in Trends, with All pumping sessions opening the full history and import flow. Hide the child selector while the pumping trend is selected and identify the pumping caregiver instead. Today’s Recent activity interleaves the selected child’s events with shared family pumping, newest occurrence first. Pumping rows identify the pumping caregiver, expressed volume, time, and recording author; tapping opens the existing session. Switching children shows the same family sessions without creating copies or adding expressed volume to child intake. Deleted sessions stay hidden, and edits retain one stable row. Apply the 100-row display limit after combining activities and pumping. Feeding either child later creates its own independent consumption event. Deleting a child does not delete maternal pumping records. No automatic milk stock deduction in v1.

### Weight and temperature

- Weight: value in kg/g or lb + oz, occurrence time, optional note. Positive values only; preserve precision. History shows recorded measurements and dates. Trends adds WHO weight-for-age percentiles as specified below; there is no “healthy” badge or inferred daily measurement.
- Temperature: °C/°F, occurrence time, optional measurement method (rectal, axillary, ear, forehead, oral, other/unknown) and note. Method is never assumed from a previous entry. Validate parseability and physically valid absolute temperature; do not hardcode clinical cutoffs or generate advice. Deprioritize in navigation.
- Unusual amounts or dates can trigger a neutral “Check this entry” confirmation. Do not silently clamp, reinterpret, or discard a plausible entered value.

## 5. Metrics, units, and time

### Rolling 24 hours

First scope queries by family and the selected child; maternal pumping queries instead use family and mother. For reference instant `t`, include completed, nondeleted events with `t - 24 hours < occurredAt <= t`. This is an elapsed 86,400-second window, including across daylight-saving changes. Exactly-on-boundary events have aged out. Recompute when the clock advances, records change, sync arrives, or the app returns to foreground. Never mix sibling intake, diapers, measurements, or feeding duration into an individual child's totals.

For a diaper set:

```
peeOnly = count(pee && !poo)
pooOnly = count(poo && !pee)
both = count(pee && poo)
changes = peeOnly + pooOnly + both
wet = peeOnly + both
soiled = pooOnly + both
```

Example used in the mocks: **8 changes = 4 pee only + 1 poo only + 3 both; 7 wet and 4 soiled.** Wet and soiled overlap and must never be added into a change count.

Bottle totals: sum milk and formula components independently; consumed volume is their sum. Exclude pumping, breastfeeding duration, deleted records, and unfinished drafts. Demo last-24-hours total: **440 mL milk + 220 mL formula = 660 mL**. These are fictional records, not feeding recommendations.

### Calendar buckets and missing data

All children's trends and the mother's pumping history use the family's chosen reporting time zone, initially the creator's device zone. Keep this zone shared so caregivers see the same daily buckets; each event retains its original time-zone identifier for audit/display. Travel does not silently re-bucket history. Changing the reporting zone is explicit and explains that calendar charts will change; rolling 24-hour totals do not.

7 days means today plus six preceding local dates; 30 means today plus 29. Mark today as partial. DST calendar days can contain 23 or 25 hours. A backdated event belongs to the day it occurred, not the day it was entered.

Missing records do not establish that no feeding or diaper change happened. Use “No entries” rather than “No feeds,” avoid connecting across missing weight data as though measured, and do not convert unrecorded days into clinical zeroes. If presenting an average, label the denominator explicitly (for example, “per day with bottle entries,” excluding the incomplete current day); show the contributing day count. Prefer daily totals to a potentially misleading headline average.

### Numeric storage

Use canonical decimal quantities in mL and retain the entry unit. Manual entry, free-form care notes, Siri, summaries, and widgets use the convenient bottle convention **1 oz = 30 mL**. Unit switching changes display only; never rewrite or round existing canonical volumes. Explain the convention in Settings preferences. External pipe-delimited exports retain their original exact US-fluid-ounce conversion (29.5735295625 mL) so declared component and total volumes still reconcile. JSONL preserves its numeric mL fields. Weight ounces are a separate mass unit and are unchanged.

Today, Trends, and Settings use one device-local volume display preference. Provide a native mL / oz segmented control with both choices visible and the current unit highlighted: beside Today's summary period, beside the Trends filters, and in family pumping history. Settings exposes the same preference in its Preferences section. Switching updates summaries, history, bottle/pumping charts, selected chart details, and accessible data lists across tabs immediately. Preserve the current tab, chart period, and selection, and remember the preference after relaunch. Settings’ Volume preference uses the same value. The control uses the regular system size at ordinary text sizes with a compact 116-point width, and the large system size with a 132-point width at accessibility sizes. It reserves at least 44 points vertically and exposes full unit names and the selected state to accessibility. Today keeps an 8-point gap between summary controls and the summary card; if the period and units do not fit horizontally, the unit picker moves onto a separate row. Existing unsaved entry drafts keep their own unit controls; changing display units does not rewrite saved quantities.

Weight canonical unit is grams; temperature is °C. Round only for display (typically whole mL, up to two decimals for fl oz, appropriate weight precision, one decimal for temperature). Sum canonical values before formatting. A new 3 oz entry is exactly 90 mL; a 0.25 oz step is 7.5 mL, while an mL-mode step is 10 mL. Older stored amounts retain their precision even when their new ounce display differs.

## 6. Siri and Apple Intelligence

### Evidence and product promise

Apple exposes app actions through App Intents and App Shortcuts [A1, A3]. Its current Siri AI integration additionally describes schema adoption, entities, and contextual discovery [A1, A2]. **The domain catalog and installed iOS 27.2 SDK rechecked on September 24, 2026 do not contain a dedicated newborn-care, diaper, feeding, or pumping schema** [A2]. This is a discovery finding, not a claim that future OS versions can never route these requests. The detailed [iOS 27 Siri audit](SIRI_INTEGRATION_AUDIT.md) records the shipped metadata, applicable APIs, limits, and validation plan.

Use custom, typed App Intents and an `AppShortcutsProvider` as the baseline. Use legitimate matching schemas only if one is actually added or applicable; do not masquerade diaper logs as calendar events, messages, or notes to gain routing. The Assistant domain is a Japan-specific side-button integration, not a generic Siri schema for baby logging [A12].

**Treat unrestricted one-sentence phrasing and app-name-free commands as an explicit validation gate.** App Intent execution, App Shortcut discovery, and arbitrary conversational recognition are separate capabilities. A screenshot of a successful result is not evidence of Siri speech recognition.

The current source exposes 18 actions, including five iOS 27 schema actions, three schema-based entity types, and eight existing App Shortcut phrase registrations. The UI emphasizes Siri, with no link to manual shortcut setup. These registrations remain necessary for custom logging outside Apple's supported schema domains. Compiled metadata and local tests establish implementation; physical Siri AI routing remains a separate release gate.

### iOS 27 content integration

- **Notes:** `.notes.note`, `.notes.folder`, and `.notes.account` represent actual care notes, children as note collections, and the shared family. `.notes.createNote` saves plain text through the validated store. It rejects attachments/pinning, resolves the sole child automatically, and asks among multiple children. Notes remain notes even when they mention feeds or diapers. The first line supplies the note title.
- **Search and opening:** `.system.searchInApp` opens care-history search. `.system.open` opens a record, care note, or feeding report. Opening does not edit data. Search results and deep links resolve against current family access. These schema actions are assistant-only; search/open require local-device authentication.
- **Discovery:** A named, fully protected Core Spotlight index contains the current family's completed, nonconflicting records, including shared pumping. Deleted children/caregivers remove their associated content. Local edits, imports, and observed remote/account/access changes update or remove entries. The delegate handles reindex requests. Each caregiver can enable or disable discovery per device and family; it is enabled by default, and an explicit opt-out survives future launches. Disabling immediately rejects queries and schedules index removal. Suspended/offline devices cannot promise immediate awareness of remote revocation.
- **Context:** Visible care records and feeding summaries carry their real entity IDs while the same discovery preference is enabled. Opting out stops these onscreen annotations. `Transferable` resolves current content on export, `SyncableEntity` uses IDs stable across family devices, and ownership is marked shared. These APIs do not create remote execution or bypass authentication.
- **Fresh answers:** Persistent report IDs identify family, child, and period. Queries and content export recompute totals, with typed milk/formula/unknown/total mL, bottle count, breastfeeding minutes, time zone, and calculation time. Never index a rolling total. The existing feeding-answer action remains the reliable calculation endpoint.
- **Compatibility:** iOS 26 keeps the existing authenticated voice actions and answers. No CloudKit schema or record-envelope migration is required. No separate Apple Watch app or remote-command relay is part of this implementation.

The current API references and physical acceptance matrix are maintained in [SIRI_INTEGRATION_AUDIT.md](SIRI_INTEGRATION_AUDIT.md). Do not claim arbitrary one-sentence logging, app-name-free invocation, or remote-device operation from compilation alone.

### Proposed intent contracts

The child input is **optional in the intent contract**, including in Shortcuts. Resolve it inside the shared command flow using the rules below; do not mark it unconditionally required and let Siri ask for it in a one-child family. After resolution, persisted child-scoped events still require a valid child ID.

| Intent | Inputs and behavior |
| --- | --- |
| Record diaper | Optional child, kind (`pee`, `poo`, `both`), occurrence time (default now). One durable event. |
| Record bottle | Optional child, milk volume and/or formula volume with unit, occurrence time. Explicit source means absent counterpart is zero. |
| Record usual bottle | Optional child and occurrence time; obtain that caregiver's prior composition for the resolved child and request confirmation of the values. |
| Start / switch / pause / finish breastfeeding | Optional child, feeding caregiver, side when needed, optional session identifier. An exact valid session identifies its child; otherwise resolve the child/session and clarify conflicts. |
| Record breastfeeding | Optional child, feeding caregiver, left/right or total duration, occurrence time for a completed manual session. |
| Record pumping | Mother, total or side volumes with unit, occurrence time; no child parameter. Infer the mother when exactly one eligible pumping profile is configured; otherwise clarify. Follow pumping visibility policy. |
| Record weight / temperature | Optional child, quantity, unit, time; temperature method optional. |
| Get recent child activity | Optional child and requested metric/period; spoken answer respects family permissions and authentication. |
| Get pumping history | Mother and metric/period; no child parameter. Use the same mother-resolution rules as Record pumping. Respect maternal privacy and family permissions. |
| Undo my last log | Target the invoking caregiver's most recent eligible creation, read back the exact record, and confirm; do not guess among caregivers. |

Represent a child as a `ChildEntity` conforming to `AppEntity` and bounded choices as `AppEnum`s. Keep the child parameter optional, while retaining explicit-child phrase variants and preconfigured shortcuts. Expose numeric quantities, unit, and time as typed parameters with summaries and localized display names. Do not assume arbitrary String interpolation is supported in an App Shortcut phrase or that a custom intent receives Siri's raw transcript. Compile and test the actual phrase shapes supported by the selected SDK.

### Child resolution for Siri and Shortcuts

Resolve within the caregiver's current family and verify membership/permission before reading or writing. The same resolver serves logging and child-summary intents.

| Situation | Required behavior |
| --- | --- |
| Explicit child name/entity, configured shortcut child, or exact session/record ID | Use that validated child ID. If identifiers disagree, ask for clarification. An invalid, deleted, or ambiguous explicit target never falls back silently to another child. |
| No child supplied; exactly one nondeleted child in the family | Infer that child with **no child-name requirement, selection prompt, or child-only confirmation**. “Record only pee” must work without saying the name. Other genuinely missing fields may still need clarification. |
| No child supplied; multiple children | Ask “Which child?” before saving, unless the request already has an exact child through a configured shortcut or session/record reference. Do not guess from the foreground screen, the most recently used child, age, or feeding defaults. |
| Pause/switch/finish breastfeeding with exactly one matching active session | Use that validated session's child ID without a redundant child question. If more than one session matches, clarify which session/child; never choose merely the most recent. |
| No child profiles | Ask the person to add a child in Settings; do not create an unassigned event or an implicit profile. |
| Family/child list not yet ready during initial share import | Wait or report that setup is incomplete; do not treat a partially imported list as proof there is only one child. |
| Pumping action | Resolve the mother; a child is never requested, even when multiple children exist. |

Count children from the locally available family state, not from a prior invocation's cached default. Revalidate the resolved target and permissions before commit. Adding a second child changes a generic, unconfigured shortcut from automatic inference to clarification; an explicitly child-configured shortcut continues to target that child. After initial synchronization, offline resolution uses the last known family state; it cannot anticipate a child added on another offline device.

Include the resolved child's name in the success response so the target remains clear without an extra interaction. Pumping confirmations name the mother instead. Canceling disambiguation writes nothing. For ambiguous or duplicate names, offer distinguishable profile choices and retain their stable IDs.

### Required utterance outcomes

| User says | Resolved result / clarification |
| --- | --- |
| “Record poo and pee” | One diaper with both flags. |
| “Record only pee” | One diaper with pee only. |
| “Record 3 oz of milk” | Milk `3 oz`, formula zero, now. |
| “Record 130 ml of formula 30 minutes ago” | Formula `130 mL`, milk zero, time = invocation start minus 30 elapsed minutes. |
| “Record 60 ml milk and 30 ml formula” | One feed with both components; total 90 mL. |
| “Record only pee” in a one-child family | Automatically record for the sole child, without asking who. |
| “Record 90 ml of milk for Robin” in a family with Robin and Jamie | Record only for Robin; Jamie's history and totals stay unchanged. |
| “Record only pee” in a family with Robin and Jamie | Ask “Which child?”; save only after a valid selection. |
| A “Record pee for Jamie” configured shortcut | Use Jamie's stored child ID without asking, even with multiple children. |
| “Record 105 ml pumped” in a family with twins and one configured mother | Record one session for that mother; never ask which child. |
| “Record milk” | Ask for amount; do not silently use yesterday's quantity. |
| “Record 3 milk” | Ask for the unit. |
| “Record it for Robin” with ambiguous event | Ask for the event, rather than infer from an unrelated prior action. |
| Past clock time that occurs twice at DST transition | Ask which occurrence if the system has not disambiguated it. |

Desired concise success: “Recorded 130 milliliters of formula for Robin at 9:11 AM.” Include the baby, source, amount/unit, and resolved time. Say “Saved on this iPhone; sharing is pending” if the person explicitly asks about sync, rather than claiming remote delivery.

### Fallbacks and discovery

Recommend “Log a pee and poo diaper in Swaddle” and “Log expressed milk in Swaddle” to give diaper and pumping requests more distinct wording. “Wet and dirty” is a synonym for the combined diaper choice. Preserve “Record pee and poo in Swaddle,” “Record both in Swaddle,” and “Record pumping in Swaddle.” If Siri is unsure, “Record a diaper in Swaddle” prompts for the kind; answer “Both.” Keep these examples and synonyms localized with the App Shortcuts catalog. Verify the compiled phrase-to-intent bindings and localized resources with `scripts/verify_siri_metadata.py`; spoken recognition and flexible matching still require device testing. Offer `SiriTipView` and a link to the app's Shortcuts actions [A3]. A person may create a custom shortcut name such as “Record poo and pee”; conflicts and system recognition still need device testing.

For quantities and relative times, first test direct typed parameter resolution. If the one-sentence flow is unreliable, use guided parameter questions. An optional user-configured Dictate Text shortcut plus a validated parser can be investigated, but it is not an invisible substitute for native Siri AI support and needs its own permission, ambiguity, and localization design. Do not add an LLM service simply to log structured events.

### Authentication, privacy, and execution

Default recommendation: require authentication for reads, edits, deletion, and access to detailed history. Offer an explicit “Allow logging while locked” choice during Siri setup for additive logging only. Apple exposes `IntentAuthenticationPolicy`; actual execution still depends on system settings and device state [A10]. Clearly explain that someone who can invoke Siri may be able to add an entry. Never promise guaranteed lock-screen execution or guaranteed offline Siri.

Choose file protection and shared-store access consistently with that setting. A reboot-before-first-unlock or unavailable protected store must produce a recoverable failure, not a success with an unpersisted event. On iOS 27, care history discovery and onscreen record awareness are enabled by default for the current accessible family. Settings → Siri provides one opt-out that clears the index and disables onscreen context. Honor explicit opt-outs on future launches; keep preferences per device and family. No family, unavailable access, or an unsupported OS means no discovery. Authentication and family permissions still apply.

All entry points use the same validated write service. A UUID created by this app prevents a retry of the same local command from creating another event. Siri does not promise an application-provided stable ID across separately invoked utterances: an independently repeated spoken command may be a legitimate second event. Show suspected duplicate records for review; do not silently deduplicate them by time or text.

### Device validation matrix (required before promising exact phrases)

Test Apple Intelligence available and unavailable, selected minimum/current OS, Siri on/off, app foreground/background/terminated, locked/unlocked/rebooted, online/offline, all supported languages, each unit, and zero/one/multiple-child resolution. Verify no child prompt with one child, explicit and ambiguous names with multiple children, adding a second child, renamed/deleted targets, preconfigured child shortcuts, partial initial imports, and pumping without a child. Test direct requests, app-named phrases, user-created shortcuts, guided questions, cancellation, recognition failures, backdating, double invocation, and persistence failure. Record which layer failed: recognition, routing, parameter resolution, authorization, persistence, or sync.

### Feeding questions in Siri

Provide **How much did my baby eat?** and **When was the last feed?** intents, with the same optional-child resolution rules as logging. Default totals to the preceding 24 elapsed hours; also offer Today and Yesterday in the family's reporting calendar, and an optional mL/oz output unit. Pumping, care notes, incomplete nursing, deleted entries, and siblings are excluded from the child's bottle intake. Report breastfeeding as duration and sessions, never inferred volume.

Return a `TransientAppEntity` with child name, period, canonical milk/formula/total mL, bottle count, nursing minutes/session count, and the query time. Include a spoken `IntentDialog` and a readable SwiftUI snippet. This exposes a result after the action is invoked; transient entities cannot be queried as a persistent content source. It does not independently make the family's history discoverable to Siri AI. Siri may choose how to present the structured answer; device testing must validate both voice and onscreen results.

Keep aggregate calculation in app code. An indexed rolling-24-hour snapshot becomes stale as time passes even without new records. Any future persistent report entity must carry its calculation time and reporting interval, and the app must not describe stale indexed content as a newly calculated answer.

Use language such as “236.6 mL recorded across three bottle feeds” and “No bottle feeds recorded,” avoiding claims that an empty log proves no food was consumed. Provide app-named phrases, a Siri entry point on Today, and examples in the hands-free setup screen. Refresh shortcut parameters when child profiles change.

## 6A. Pasted care notes

The primary interface is a free-form text form, followed by an editable review. It accepts common bottle/diaper shorthand and observations, including `BM`/`EBM`, pee/poo/both, mL/oz, 12/24-hour times, decimal amounts, `2½`, `2 1/2`, and compact fractions such as `21/2`. Compact fractions are explicitly marked for confirmation. The original wording is retained; observations do not become a diagnosis or advice.

1. Choose the child and first calendar date in the notes. With one child the app supplies it; the review still names that child. Display the family time zone.
2. Paste or type up to 50,000 characters/500 lines. Optional ISO date headings (`2026-09-18`) make dates explicit. Keyboard dictation remains available through the system keyboard.
3. Read structured feeding exports deterministically and skip model generation for these reports. Use Apple's on-device Foundation Models framework for line classification on small unstructured reports with unclassified lines when available. Keep numeric/date extraction grounded in the original text. Model output cannot save records or invent quantities. Provide a deterministic parser when the model is unavailable, refuses, or fails. Do not send the notes to a custom server or a cloud model.
4. Offer editable proposed records, showing their original source, child, date/time, units, contents, and review flags. Summarize selected bottle intake, offer a filter for incomplete entries, and keep the review acknowledgment beside Save. Unit changes convert values instead of reinterpreting the same digits. Dates roll forward when a chronological overnight report crosses midnight; show that inference. An unexplained backwards time is flagged, and a nonexistent DST time requires correction.
5. Untimed entries may use a nearby timed entry in the same paragraph as a clearly labeled suggestion. Without a nearby time, require an explicit time. A missing unit may use the report's consistent explicit unit or the user's fallback choice; mark it for review. Do not silently carry one child's context into another.
6. Preserve unclassified observations as selectable care notes with their original wording. Negated, planned, spilled, and other non-consumption statements are retained as notes rather than counted as intake. The reviewer can change type, contents, quantity, unit, time, note, and inclusion.
7. Exclude likely duplicates in the existing log and within the same report by default, scoped to child, composition, and nearby event time, allowing for unit conversion and export rounding; allow an explicit inclusion when they are separate real events. Require acknowledgment of the reviewed child, dates, times, and amounts.
8. Validate the entire selection, then commit atomically. Repeating the same command IDs must not duplicate records. Imports do not change remembered bottle defaults. Offer one Undo for the imported batch and retain revision history.

Structured feeding exports accept `date time | BM / Formula / Mixed BM/formula | total | notes` and the full `date | Bottle feed | type | Total: … | Breast milk: … | Formula: …` form. Skip recognized metadata headers. Honor a valid IANA `Timezone:` header and exact ISO timestamps. Parse component units independently, tolerate only explained decimal rounding, and flag conflicting totals or incomplete splits. Extra numbers, times, diaper references, and negated observations inside a note cannot alter the explicitly recorded feed or create new events. Preserve all original wording.

JSON Lines version 1 uses the same Paste care notes field and review flow. A first non-whitespace `{` selects one-object-per-line parsing; malformed or unsupported lines report their line number and stop the whole batch without natural-language fallback. Support bottle feeds with explicit timestamps/offsets, canonical mL components and total, unknown splits using two null components, optional verbatim notes, matching IANA time zone, and stable source IDs scoped to the selected family/child. Reimports never overwrite an existing ID. Recheck identities before the atomic save, retain original JSON and readable notes, preserve defaults, and support batch Undo. See [the versioned format contract](IMPORT_FORMAT.md).

Also support `type: "pump"` version 1 JSONL in a separate batch for one pumping caregiver. Require a positive `totalML` and explicit timestamp; optional left/right amounts are either both known and consistent with the total or both unknown. When the total is null but both sides are known, add the recorded sides and label the calculation in review. Optional duration is positive or unknown. Preserve Decimal precision, verbatim notes, time zone, and source IDs scoped to the family/caregiver. Auto-detect pump objects and replace the child picker with a pumping-profile picker; allow profile creation and a direct import action from pumping history. Review, duplicate checks, atomic save, and batch Undo apply equally to pumping. Pumped amounts never enter child intake or bottle defaults. Historical sessions retain the same caregiver UUID when that person later accepts an invitation.

Keep this technical format out of ordinary logging: **Format tips & missing units → Advanced: JSON Lines** is collapsed initially and contains examples, validation/duplicate rules, and separate copyable feeding/pumping export instructions.

When a total is known but its split is not recorded, retain the bottle count and total volume as unclassified intake. Display that amount explicitly in review, editing, Today, trends, widgets, and Siri answers; never assign it to milk or formula. Editing a note or date must preserve this volume. Version these records so an older app requests an update rather than showing an incorrect zero. Shared families need all caregivers on a compatible build.

For the nurse example, the proposed records are **three bottles, three diapers, and one care note**. If the reviewer confirms `21/2` as 2½ oz, the bottles total **8 oz** of breast milk. Diapers total three wet and two soiled across three changes. These totals depend on confirming the missing first unit, untimed diapers, and first report date. Preserve “He have a red mark on his cheek on both side think he’s getting baby acne” as the caregiver's wording, without interpreting it.

Reference: Apple's [Foundation Models code-along](https://developer.apple.com/events/resources/code-along-205/) for model availability and guided structured output; [transient entities](https://developer.apple.com/documentation/appintents/transientappentity) and [intent results with value, dialog, and view](https://developer.apple.com/documentation/appintents/intentresult/result(value:dialog:view:)) for Siri answers.

## 7. Widgets

**Medium Home Screen widget is the primary widget.** Each widget is assigned to one child by stable family and child IDs. Show the child's name prominently, “Last 24 hours,” milk and formula consumption, wet and soiled counts, and a compact nonoverlapping breakdown: pee only / poo only / both. The sample medium layout uses 440 mL milk, 220 mL formula, 7 wet, 4 soiled, and `4 / 1 / 3` composition. Show “As of 9:41 AM.”

With one child, choose that child automatically when adding a widget. With multiple children, let the person choose a child for each widget; they can place Robin's and Jamie's widgets next to each other. Adding a sibling or changing the app's selected child never retargets an existing widget. If its child is deleted or its family access is revoked, clear that widget's data and show a setup/access state instead of silently displaying a different child.

- Small: baby, wet/soiled counts, combined bottle volume, with clearly labeled compact source split if space allows. Medium is the complete view; do not shrink text to fit every metric into small.
- Large: the same child's metrics, recent events, and breastfeeding summary. If showing a pumping section, label it explicitly with the mother and “Family pumping”; it references the same maternal sessions, not a volume belonging to this child. Hide that section when its privacy policy excludes the viewer.
- Lock Screen: four circular quick-log widgets for Pee, Poo, Both, and Bottle, as specified below.
- Tapping the volume area or its unit control switches mL ↔ oz in place. Tapping the baby header, an activity row, or the rest of the widget opens the corresponding baby/history. Keep these targets distinct. Do not silently create a feed with remembered amounts from a widget tap. Any later direct logging buttons must use explicit event labels and a visible confirmation/undo route.
- Configure the child; initialize widget units from the person's app preference, then remember changes made on the widget as described below. Provide readable full-color, tinted, dark, StandBy, and redacted states. Respect container margins and system typography [A5].

### Home Screen quick logging

Also offer a **Care & quick log** widget (`SwaddleCareSummary`) in medium and large sizes. It combines the configured child's bottle intake, feed count, and diaper counts with **Family pumping** volume and session count, followed by Pee / Poo / Both / Bottle actions. Pumping includes every pumper in the same family and remains separate from the child's intake. All summaries use the rolling 24 hours ending at the timeline entry's date, exclude future records, and reflect projected edits and deletions. Tap the bottle metric's visible `mL ↔ oz` control to change both intake and pumping units together. Preserve the snapshot's original “As of” time; older snapshots have a compact clock indicator.

The shared cache contains only pump ID, family ID, occurrence time, and total mL. An older cache without pumping data displays a dash and asks the user to open Swaddle; a refreshed cache with no sessions displays zero. The timeline ages cached records out and admits already-cached future records when due, while saves and remote changes request new timelines. WidgetKit controls when refreshes are displayed. The new widget reuses the existing signed actions, exact-child configuration, permissions, and Undo behavior below. It does not replace existing widgets or change the CloudKit schema.

Offer a **Quick log** medium widget with four clearly labeled actions in one horizontal row: **Pee / Poo / Both / Bottle**. Also offer a small individual widget for each action. Each widget has its own child configuration, defaults to the sole child where possible, and shows the child's name. Preserve existing overview widgets and Lock Screen widget identifiers.

Pee, Poo, and Both open Swaddle and immediately record the chosen diaper using the same signed launch and Undo protections as Lock Screen controls. Bottle opens the editor with previous amounts; saving requires the user's confirmation in the editor. Each diaper action has a separate command identity so different buttons on one timeline cannot collide. Home Screen entries are labeled with that source. A recently saved action becomes **Undo Pee / Undo Poo / Undo Both** for 60 seconds; Undo validates the original author, revision, child, and current write access. Tapping outside the four controls opens the child's log without writing.

Use system widget margins and semantic backgrounds, child accent colors in full-color mode, and system accentable symbols in tinted or Liquid Glass rendering. Provide labeled setup/access states instead of allowing an unconfigured or read-only widget to write. Child names respect privacy redaction. Settings → Home & Lock Screen widgets explains installation and behavior. No CloudKit schema or care-record migration is required.

### Lock Screen quick logging

Offer four separately addable `accessoryCircular` widgets, arranged **Pee / Poo / Both / Bottle** in the system's horizontal Lock Screen widget area. Each occupies one circular slot; do not model the row as a custom full-width widget. Use the system accessory background, monochrome symbols, and short labels inside each circle. Pee uses a drop; Poo uses the app's compact dot cluster; Both combines them; Bottle uses the feeding-bottle symbol. Avoid added branding, tiny counts, and app-style colored cards. The [ImageGen concept](artifacts/previews/lock-screen/quick-log-concept.png) illustrates appearance, not a running implementation; native system rendering remains authoritative.

Pee and Poo each create one diaper event at the time of activation. Both creates one event with both flags. Tapping opens Swaddle after the system unlock flow, validates the configured child and caregiver, commits durably, and schedules the existing family synchronization. Today shows the saved confirmation and Undo without another Save step. The widget also shows a checkmark and a clearly labeled Undo action for that exact saved entry when its timeline refreshes; preserve current permissions and conflict safeguards. Do not display success for a failed local save or equate local success with completed iCloud upload. Guard repeated pending activations against duplicate writes. Validate actual feedback and reload behavior on a physical device; widget scheduling must not be treated as an exact-second animation timer.

Bottle opens that child's existing bottle editor using a validated deep link. Prefill the caregiver's previous milk/formula values, allow the normal quick volume adjustments, and require Save. A tap on Bottle must not silently record the previous amount. Use the circular widget’s single `widgetURL` launch target for all four actions [A13, A14]. Diaper URLs carry a device-signed command; an ordinary unsigned deep link must never create or delete a care record.

Each widget stores stable family and child IDs. Preselect the only child at setup; require an explicit selection when there are multiple children. Never retarget a configured widget when Today switches children or a sibling is added. Its accessibility label names the action and child. Keep names and health quantities off the default face; any optional personal content must respect privacy redaction. A missing/deleted child, incomplete setup, or lost write permission shows an appropriate setup/access state without recording elsewhere.

The system requires authentication before interactive Lock Screen widget buttons run; Face ID or the device passcode remains part of this flow. Do not promise writes on a still-locked device [A13]. Users add and arrange the four widgets through Lock Screen customization; the app cannot install the entire row automatically. Validate gallery previews, child configuration, light/dark wallpapers, larger text, VoiceOver, offline saves, retries, Undo, read-only/revoked access, and direct Bottle navigation before shipping.

Implementation: the four `SwaddleQuickLog.*` configurations support `accessoryCircular` and `systemSmall`; `SwaddleHomeQuickLog` supplies the four-action `systemMedium` layout. Each diaper launch URL carries an HMAC-SHA256-signed command containing the exact family, child, caregiver, action, and stable record UUID. The app alone creates the key in its protected App Group; the extension reads it. The app verifies the signature, supported version, timestamp, current caregiver, child, and write permission before using the existing `LogStore` transaction and CKSyncEngine outbox. Timeline entries retain stable command IDs, so repeated delivery and retries after Undo cannot duplicate or restore an entry. A 60-second widget Undo receipt is derived from the original saved revision; the app confirmation offers Undo for 10 seconds. Both reject edits, conflicts, expired receipts, missing children, and lost permissions. System timeline refresh controls visual expiry. Failures appear as a visible app alert. A cache written by an older build first opens the app to refresh; open Swaddle once after updating. The prior authenticated `WidgetDiaperIntent` remains available for cached older widget renderings, but new circles use the entire launch surface because the inner interactive button may be inactive while locked. Settings → Home & Lock Screen widgets explains installation. No CloudKit schema or care-data format change is required.

### Tap to switch mL / oz

**Required on small, medium, and large Home Screen widgets that display volume.** Make the volume summary a button, with a visible compact `mL ↔ oz` affordance and a sufficiently large tap target. A diaper-only widget needs no unit control.

1. One tap switches all volume values in that widget together: milk, formula, combined intake, recent bottles, and pumped volume where shown. A second tap switches back. Diaper counts, times, and breastfeeding durations are unaffected.
2. Example: `440 mL milk + 220 mL formula` becomes approximately `14.67 oz milk + 7.33 oz formula`. Convert from canonical stored mL; toggling back restores exactly 440 and 220. Use the same 1 oz = 30 mL convention as app entry.
3. Remember one widget-volume preference for this person on this device, shared by their Swaddle volume widgets. Refresh other widget instances after a change. The interacted widget updates through its intent-triggered timeline reload; other instances may refresh later under system scheduling.
4. This changes presentation only. It does not edit activity records, change the app's entry defaults, alter another caregiver's units, or synchronize the preference across family members. A caregiver may use oz while another uses mL for the same records.
5. Work offline using the cached canonical totals. Keep the activity snapshot's original “As of” timestamp; changing units does not imply that new activity has synchronized.
6. Expose an accessibility label such as “Switch volumes to ounces” or “Switch volumes to milliliters,” and announce the resulting unit. Provide visible pressed feedback while the widget updates. Honor native authentication/redaction behavior; interactive controls on a locked device may require unlocking [A13].

Implementation proposal: use an App Intent-backed `Button`, not a tap gesture or a URL that launches the app. A `SetWidgetVolumeUnitIntent` receives an explicit target unit, writes it to the App Group preference store, and completes the write before returning. Setting a target unit is idempotent if the same action is retried. The timeline provider reads that preference and formats the same canonical snapshot. WidgetKit reloads the interacted widget after the intent completes; request reloads for other affected widget kinds [A13]. If a preference write fails, retain the prior unit and avoid a false success state.

Use `Link` / `widgetURL` separately for opening the baby's history [A14]. Validate tap targeting on each widget family so a unit switch cannot accidentally navigate or create an event. The existing generated widget screenshot is the initial visual direction; its next revision should expose this unit-switch affordance.

### Freshness and privacy

**Freshness:** write a small derived snapshot atomically into the App Group and request `WidgetCenter` timeline reload after a committed local change or imported remote change. Plan timeline entries for rolling-window expirations using a practical minimum cadence (Apple recommends entries at least about five minutes apart) and refresh after the final entry. Coalesce close expirations; explicitly retain “As of” because widget scheduling is best effort [A4].

The interval represented is the 24 hours ending at the snapshot timestamp, not a false claim of live data. When cloud data is pending or stale, show a compact state without replacing the metrics. Opening the app recomputes from the current store. Never promise exact-second aging or immediate remote widget updates.

Use `privacySensitive`/redaction and the chosen protection policy for child names and quantities [A11]. Empty state says “No entries yet”; it must not contain plausible sample counts. Deleting a child clears its snapshots; revoking family access clears all of that family's snapshots. Deep links validate both family and child IDs and show an explanation when the target is unavailable.

## 8. Trends and routine patterns

Use **Swift Charts** for production, not embedded web charts [A6]. The ImageGen mock charts illustrate chart types and hierarchy; generated bar proportions and event positions are not numerically authoritative. The native implementation must derive every mark from actual records.

Child charts always identify and filter to the selected child. Do not combine siblings' feeding, diapers, weights, or temperatures into one series. Pumping charts belong to the mother within the family and are opened as a separately labeled history.

| View | Chart and interaction |
| --- | --- |
| Bottle intake | Daily stacked `BarMark`: milk plus formula; y-axis starts at zero, unit visible, today's bar marked partial. Tap a day for the date, total, milk/formula split, any amount whose split was not recorded, and feed count. |
| Diapers | Daily stacked bars of pee only / poo only / both. Height equals unique changes. Wet/soiled totals are overlapping summary values, not stacked series. |
| Breastfeeding | Daily recorded active minutes and session count; separate from bottle volume, no dual-axis volume/duration chart. |
| Pumping | Mother's daily expressed volume, counted once across the family. Tap a day for its volume and session count, labeled with the caregiver. Never stack with a child's consumed volume. The separate Family history chart covers the latest 30 sessions and labels its daily totals as including only those sessions. |
| Weight | Dated points and a solid line connecting actual samples; true dates on x-axis and kg on y-axis. Eligible measurements also show dashed WHO 3rd/50th/97th reference curves. Tap selects the nearest actual measurement and shows its date, time, weight, age, and rounded percentile, with the sex-specific reference and corrected-age basis visible. No normative color zones, smoothing of the child's series, or extrapolated child weights. |
| Routine | One row per day for the selected child's bottle, diaper, and breastfeeding events; local time of day across x-axis. Timed sessions use intervals and point events use distinct symbols. Any optional maternal pumping context occupies a separately labeled mother/family lane and never contributes to child totals. Tap a day for bottled volume, feed and diaper counts, and recorded breastfeeding time. Use a focused daily list alternative at large text sizes. |

Callouts remain visible after a tap and highlight the selected day or measurement. Exact details occupy reserved space below daily plots, while weight selections replace the existing summary above the plot. Both provide an explicit 44-point × button labeled **Dismiss chart details** for accessibility. Dismissal clears the value and highlight; VoiceOver supports the escape action. Vertical swipes still scroll the page. Volumes follow the selected mL/oz preference and display up to two decimal places; saved quantities and the existing 1 oz = 30 mL display convention are unchanged. The volume toggle is hidden for weight, which displays kg. Daily selection uses the family's calendar boundaries, including DST, rather than the nearest midnight. Switching the period, child, metric, or pumping profile clears an incompatible selection. Empty days in daily trends say **No entries**, not an implied measured zero. Diaper callouts retain separate pee-only, poo-only, both, and overlapping wet/soiled counts. Accessible list views remain available, including for weight and pumping history.

**Weight-for-age.** Daily LMS coefficients from the official WHO expanded tables are bundled offline and checked against the independent published centile tables; provenance and calculation rules are in [ReferenceData/WHO](ReferenceData/WHO/README.md). The profile defaults to the Boys/Girls reference from its explicitly selected gender. Optional `growthReferenceSex` overrides that default and is retained unchanged for existing profiles. Its picker lives in a collapsed **Advanced growth settings** disclosure. Percentiles require a resolved reference and birth date and use the age on the measurement date, in the family reporting calendar. Missing information shows a setup action without hiding the recorded weight. Comparisons stop at the second calendar birthday. For a known birth before 37 weeks, use WHO corrected age from the estimated 40-week due date. Before that date, retain the measurement and actual-age comparison without extrapolating corrected age. No INTERGROWTH or Fenton calculations are shipped. Name the WHO reference and age basis on each tappable measurement and accessible list row. Round to a whole percentile, labeling extreme tails below 1st/above 99th. The reference is not a target, diagnosis, or feeding recommendation. The accessible measurement list includes each available percentile and age; the About disclosure links to WHO and explains the scope. Optional profile fields use the existing shared revision format, with no schema deployment or care-record rewrite.

For a known preterm birth, additionally show **WHO corrected age** and **WHO actual age** percentiles together for the latest or selected measurement. Corrected age counts from the estimated due date; actual age counts from birth without prematurity adjustment. Corrected WHO values start on the due date, with a clear unavailable state before then. These comparisons use the same sex-specific WHO table. The primary chart curves use corrected age; the actual-age value is a separately labeled comparison. Avoid repeating the corrected-age value above this pair. Include both in chart accessibility values and the measurement list. Stack the columns at accessibility text sizes, preserve dismissal, and respect Reduce Motion.

Use **WHO** as the growth-reference name (OMS in Spanish). Reference choice does not change stored measurements.

For routine charts, separate events at the same time into small sublanes rather than hiding one underneath another. Mark both repeated-hour occurrences on a DST fall-back day in details; split intervals crossing midnight across rows. A 30-day routine view scrolls by day with a stable 24-hour axis. This shows recorded timing, not a predicted schedule or instruction to wait for the next feed.

Charts need labels and symbol/texture differences in addition to color, VoiceOver summaries and selectable data points, a textual daily table alternative, and sensible drag targets [A7]. Omit comparison percentages when a previous range is missing or incomplete. No 3D charts, decorative gauges, or normative achievement rings.

### Milestones — Their unfolding story

Approved concept B is available directly in the **Milestones** bottom tab. A quiet ribbon links the latest family observation and freely browsable age chapters. Today retains its logging layout and adds the same Settings gear used by Trends and Milestones. Each chapter opens in place; its folded corner, 280 ms smooth transition, press response, and selection haptic follow the Cocoon design. Saving uses the existing quiet confirmation and Undo treatment. Reduce Motion removes spatial chapter/selection movement and keeps confirmation fades. Decorative ribbon/large introductory copy are omitted at accessibility text sizes; iPad content has a readable maximum width.

Scrolling gives the ribbon a visible fabric sway and a warm satin highlight near the reading position. Chapter medallions gently turn and settle to full size as they pass through the reading area, rather than only changing at the screen edges; the cards and text remain steady. Motion follows scroll position and stops at rest, with no repeating animation or progress/completion meaning. Reduce Motion keeps the ribbon static and disables the medallion transforms and traveling highlight. Ribbon geometry updates are isolated from the chapter list, and its fine weave is drawn only near the viewport while motion is enabled.

The offline, versioned catalog contains 100 CDC milestones at 2, 4, 6, 9, 12, 15, 18, and 24 months, plus six separately labeled WHO motor-development windows. [Source provenance and review procedure](ReferenceData/Milestones/README.md) retain URLs, retrieval hashes, source version, and domain counts. CDC definitions are verbatim; app editorial chapter titles are separate. No third-party logos or milestone media are bundled. Sources, free CDC availability, and non-endorsement wording are in the app.

Each of the 106 skills has its own original offline vector illustration in the check-in sheet. Six-second scenes start automatically when visible and loop with a gentle hidden reset; the cotton ground remains steady. Pause/Play controls retain the current pose and resume the complete loop. Playback pauses offscreen and when inactive; Reduce Motion shows a meaningful still pose. The artwork uses simple rounded hands, short tucked seated legs, and a narrow standing stance. Illustrations do not change milestone definitions, sources, observations, or sharing. [Illustration inventory and authoring](ReferenceData/MilestoneIllustrations/README.md).

Every scene uses the selected child's illustration appearance. Adult scenes use the current viewer's canonical caregiver profile, independently of the child; the recorded observation's author remains unchanged. The shared vector assets contain neutral/female/male adult hair silhouettes and actor roles. Runtime personalization changes only visibility and pigments, preserving motion, shaded artwork, loop timing, and incidental playmates/strangers. A bounded 12-item local cache avoids creating a separate bundled asset for every combination.

Before two months, show Looking ahead. Between checkpoints, use the younger completed calendar-month checklist and label the next as upcoming. For a birth before 37 weeks, chapters use the estimated 40-week due date until the second birthday, with the corrected-age basis visible. Missing birth date leaves chapters manually browsable and offers profile setup. After the collection's age range, retain the story and link to CDC's older checklists. There are no overdue badges, ranks, completion percentages, or developmental scores.

Choose **Seen it / Not yet / Not sure / Used to do this**. Unanswered remains distinct. A seen skill can include an optional first-noticed date, bounded by birth and the check-in date. All observations may include a note and a concern flag. A new check-in creates an independent record with child, skill ID, source version, frozen skill wording, caregiver, and recording time. Family history supports correction, reversible deletion, and previous-version review. Concurrent corrections retain competing revision heads. New observations never silently replace another caregiver's first-noticed date.

Observations use version 4 of the existing typed revision envelope, existing CloudKit family sharing, and existing edit/view-only permissions. No CloudKit schema deployment or Core Data migration is required. All family members must update before interpreting milestone records. Milestones stay outside intake/diaper totals, pumping totals, widgets, and Siri care-history discovery. Reminders, milestone Siri commands, and clinician export are not included in this version.

WHO windows describe observed 1st–99th percentile age ranges, not deadlines or personalized scores. WHO and CDC observations remain separate. Source guidance directs concerns, lost skills, or missing age-appropriate milestones to the child's clinician and developmental screening without waiting for another checkpoint. Check-ins do not replace a validated screening tool.

### Gentle celebrations

On the first visit to Today on each of the child's first four weekly birthdays (calendar days 7, 14, 21, and 28 in the family's time zone), briefly highlight the age and drift a few cloth-shaped fragments across the screen. Use chronological age for these birthdays. A dismissible message appears above the bottom navigation without moving the care log. Each birthday is acknowledged once per child per device; changing a name or appearance does not replay it. The week-four message links to the next available milestone chapter as **See what's ahead**, preserving the milestone's actual/corrected-age policy and its existing check-in flow. It never claims a two-month skill is due at four weeks. Keep the message until dismissal for VoiceOver or accessibility text sizes; otherwise dismiss after 12 seconds.

When a pumping caregiver personally records a session greater than their largest previous valid, nondeleted session, show **A new personal record** with the session volume and the existing Undo and dismiss controls. Compare canonical milliliters across that caregiver's merged history, independent of display unit. First sessions, ties, smaller sessions, edits, restores, imported batches, another caregiver's entries, and remote sync remain quiet. Siri uses the same rule and adds a short spoken acknowledgment. Publish the celebration only after the care record is successfully saved, and remove it when the session is undone or deleted. Play the flourish once even when navigating between Today and pumping history. No daily target, score, family comparison, or new notification is introduced.

Both flourishes finish in 3.2 seconds, stop offscreen or when inactive, and are decorative/noninteractive. Reduce Motion retains the messages without confetti or the age glow. Celebration receipts and presentation state are device-local, outside the shared care records; no CloudKit schema or record-format change is needed.

## 9. Shared data and technical architecture

### Persistence implementation

The development build uses SwiftUI over a domain service, with **Core Data for local private/shared stores, one `CKShare` for the family graph, and CKSyncEngine after a verified handoff from `NSPersistentCloudKitContainer`**. Existing record IDs, deployed CloudKit fields, care payloads, and accepted family invitations are retained. The legacy writer stays active until server comparisons and export checks pass; the two sync systems never write the same local stores together. See [the migration and recovery contract](CloudSyncMigration.md). All children inherit the family's share permissions. Live cross-account handoff and mixed-version interoperability must be verified on signed devices before release.

Local saves queue durable uploads and attempt a send/fetch soon afterward. Launch and foreground activation request updates; Today and pumping history support pull-to-refresh, with an explicit Sync now action in Settings. The UI separately reports pending uploads, the last upload, and the last successful check of both cloud databases. These are server acknowledgements, not confirmation that another caregiver's phone has received an entry. Offline saves remain usable, and interrupted transfers resume from a protected checkpoint.

The app and widget target iOS 26.0 and are built with Xcode 27.2. Simulator builds save durably on the device with CloudKit disabled. See [README.md](README.md) for capabilities and provisioning, and [QA.md](QA.md) for verified behavior and remaining device checks.

```
SwiftUI screens     App Intents     Widget actions
        \               |               /
         Validated activity command service
                       |
       Repository / durable local Core Data store
                /                    \
     CloudKit private/shared      Derived summaries
       caregiver sync           App Group snapshot
                                      |
                                WidgetKit timeline
```

Keep SwiftUI views out of persistence and conversion logic. Use structured concurrency around commands, persistent history/remote-change processing for sync, and cross-process coordination for extension writes. A Swift actor alone does not serialize writes across the app and its extensions.

### Model

| Entity | Essential fields |
| --- | --- |
| Family | UUID, display name, reporting time zone, owner/share identity; owns child profiles, family-scoped caregiver profiles, and shared records. One active family in v1. |
| ChildProfile | UUID, required family ID, display name, optional birth date and gestational age at birth in completed days. No child-specific share or permission list. |
| CaregiverProfile | Stable profile ID, family ID, display name, family role/permissions, optional linked participant identity; avoid displaying account identifiers. The mother and the person entering an event can be different profiles. |
| ChildActivity | UUID, required family ID and child ID, kind, occurredAt, original time-zone ID, createdAt, updatedAt, author ID, last-editor ID, source, revision, deletion marker, optional note. |
| DiaperDetails | hasPee, hasPoo (at least one true). |
| BottleDetails | milkML, formulaML, original values/units, consumed total derived. |
| BreastfeedingDetails | Feeding caregiver ID, session status, timed segments or manual duration, side/unknown, active time derived; child/family come from its ChildActivity. |
| PumpingSession | UUID, family ID, mother's caregiver/profile ID, timestamps, author/last-editor IDs, source, revision, deletion marker, optional note; no child ID. Details include totalML or leftML/rightML, entry mode, optional duration, and original unit. |
| WeightDetails / TemperatureDetails | Canonical value, original value/unit, optional temperature method. |
| EntryPreferences | Family + child + caregiver key, saved bottle composition/unit, last updated time; private to that caregiver. |
| WidgetConfiguration | Stable family and child IDs for each configured child widget; unaffected by the app's current child selection. |
| WidgetPreferences | Device-local volume display unit (`mL` / `oz`) in the App Group, shared by this person's widget instances; not part of a family's shared log. |
| WidgetSnapshot | Family and child IDs, as-of time, window bounds, canonical mL aggregates and recent-event quantities, freshness/access state. Optional maternal context is separately keyed/labeled by mother. Rebuildable, never source of truth; unit conversion happens at presentation. |

Use explicit payload types with versioned decoding; do not store all activity details in an unvalidated text blob. Migration tests must preserve existing timestamps, flags, quantities, and deletions.

Enforce that every ChildActivity references a child in the same family, every PumpingSession references a mother in its family, and no PumpingSession is stored as a child's intake/activity. Renaming a child must preserve its ID, history, widget configuration, and configured shortcuts. Removing a child affects that child's records only; maternal sessions and sibling records remain intact. Do not implement child deletion by deleting the family's shared zone.

### Deleting caregiver profiles

The family owner can open **Settings → caregiver → Delete caregiver** and confirm deletion of an unlinked profile. The confirmation explains that this removes the profile from active caregivers and new-entry choices, keeps existing care and pumping history, and syncs the change to the family. Canceling makes no change.

Deletion writes a recoverable revision using the existing record format. It does not delete pumping sessions, child activity, original authorship, or historical names. Retained pumping stays available in Trends and its full pumping history with **Deleted profile · History kept** shown; it remains discoverable in historical queries but cannot be selected for a new session. An existing session can be reassigned to an active pumping profile, or the deleted profile can be restored before recording more. No CloudKit schema deployment or data migration is required.

Protect the current caregiver, the family owner, Apple Account linked profiles, unresolved profile conflicts, and profiles with unfinished breastfeeding sessions. Recheck the latest record when committing deletion, including concurrent account links. If an offline deletion arrives alongside an account-link revision from another phone, retain the linked profile as active and surface the conflict for review; a caregiver deletion must not discard that account link. These rules also apply to generic record deletion, conflict resolution, and Undo. Only the owner may restore a profile through **Settings → Review edits & deleted entries**; reject a restore that would duplicate an active profile's Apple Account or invitation association.

Deleting a profile does not revoke an iCloud invitation or family access. Use **Invite or manage caregivers** for CloudKit access changes. An unlinked profile with an invitation reservation can be deleted, with the reservation retained in its deleted revision for recovery; joining and new-entry choices ignore deleted profiles.

### Merging duplicate caregiver profiles

The family owner can open **Settings → caregiver → Merge caregiver profiles**. Choose a second active profile for the same person and explicitly review which profile to keep. Display account/invitation status and pumping-session counts so identical display names remain distinguishable. Prefer a permitted direction that keeps the linked or invited profile. A native confirmation names the kept profile, explains retained history and family synchronization, and reminds the owner to update all family devices first. Unsaved profile edits must be saved before merging.

Keep the destination's UUID, display name, Apple Account identity, and invitation. Preserve pumping capability if either profile has it or has pumping history. Combine pumping and completed breastfeeding projections under that ID while keeping the stored session IDs, times, volumes, notes, original owner references, and authors unchanged. Family history, Today, trends, previous pumping amounts, and Siri discovery use the combined projection. Bottle intake and private bottle preferences are unchanged. The removed duplicate no longer appears in active caregiver or new-session pickers. Merging profiles never deduplicates similar sessions.

Represent the merge as a recoverable tombstone on the duplicate's caregiver revision with an optional `mergedIntoID` UUID. Commit the alias and any destination pumping-capability change together. Review the latest profile heads again at save time; reject a stale confirmation, cross-family profiles, competing edits, unfinished breastfeeding sessions, read-only access, and removing the owner/current profile. A profile with a linked Apple Account must be kept. An invitation-bearing duplicate can only be removed when its reservation identifies the same known account or share participant as the kept profile; otherwise keep the invited profile or manage invitations first. The merge does not modify `CKShare` participants or permissions.

Late offline entries referencing a merged profile join the kept profile when the alias and destination arrive. New entries and imports use the canonical ID, with source-ID deduplication scoped to the combined pumping history. Editing an older session retains its stored original caregiver reference if its effective caregiver is unchanged. An open pumping draft follows an arriving merge without replacing the typed volume. Cycles, missing destinations, and contested aliases fall back to original references so history remains readable; conflicting versions remain recoverable. Concurrent account linking continues to win over caregiver deletion.

**Separate profiles** in **Settings → Review edits & deleted entries** is owner-only and restores the duplicate without an account or invitation. Original records return to their original profiles; entries created under the kept profile stay there. Historical versions remain available. Use record envelope version 3 for aliases so older clients request an update instead of misreading combined history. Existing versions 1 and 2 still decode unchanged; this changes payload content, not the deployed CloudKit record types or fields.

### Sharing and permissions

Share the **family**, including all current and future children, by invitation between **separate Apple Accounts with active iCloud accounts**. An Apple Family Sharing group is not required; a parent can invite a partner, grandparent, or other caregiver. The proposed product uses iCloud identity and needs no separate Swaddle username/password. Both people need the app and access to iCloud for invitation acceptance and synchronization; after initial setup, local logging works offline [A15]. Per-child caregiver access is outside v1: every member's role applies across the family.

#### Invitation and joining flow

1. The person who creates the family is its **owner**. In **Settings → Invite caregiver**, they choose **Can edit** (default) or **View only** for the family; there is no child-selection step.
2. Before opening Apple's sharing sheet, show the scope plainly: the invitation covers every child currently in the family and any child added later, including existing and future shared activity, profiles, measurements, notes, and authorship. Display the current child names and the future-child rule. Private preferences remain private. Pumping follows the separately chosen visibility policy.
3. Use the native iCloud sharing flow to send an invitation through Messages or another system share-sheet destination. Restrict it to invited participants: keep `CKShare.publicPermission = .none`, with no “anyone with the link” access [A16]. No invitation is sent by this specification/design task.
4. The recipient taps the invitation, sees the family and access level, and accepts with their own iCloud account. If needed, guide them to install the app or enable iCloud and then reopen the invitation. Do not require them to create duplicate family or child profiles first.
5. Import the family and its children. With one child, open Today directly; with multiple, let the recipient choose the initial child, then make the child switcher available. Show a loading state during first import, then the existing histories. Pending invitations are distinct from joined caregivers. If an invitation was revoked or is for a different account, explain that state and offer a retry/new-invitation path.
6. Each person chooses a display name for entry attribution. The owner can later review participants, change family-wide permissions, revoke an invitation, or remove access in Settings. A participant can leave the family.

Joining the same share twice opens the same family without duplicate children. If the recipient already belongs to a different family, explain the one-family v1 limit and require an explicit resolution before accepting; do not silently replace or merge families, admit a second active family, or copy another family's history. Sharing setup requires connectivity; a failed invitation does not prevent the owner from continuing local logging.

#### Invite an existing caregiver profile

The owner can open **Settings → caregiver → Invite this caregiver**, enter the recipient’s Apple Account email, and create a private invitation with family-wide editing access. Show this scope before creating it. If profile edits are unsaved, label the action **Save and invite this caregiver**. The subsequent **Send invitation** action uses the system share sheet; preparing a link does not claim a message was sent or that the person joined.

Reserve the existing caregiver ID using CloudKit’s share and participant identifiers, with a hashed account record identifier when available. Do not store the entered email in the shared care record or match people by display name. Wait until the reservation revision has exported before adding the participant and presenting the link. An unknown iCloud account may be resolved by Apple during acceptance; match its accepted participant identity afterward. Reuse the existing profile ID and preserve pumping session IDs, dates, quantities, and original author attribution.

Verify a joining person against a freshly fetched participant for the signed-in account using CloudKit's person-identity comparison. Different user-record representations are not sufficient evidence of an account mismatch. Require accepted private membership, scope verification to the family, account and full share ID, and use the same reserved participant to link an account alias. Offer copyable, identifier-free troubleshooting details when joining fails.

Reject self-invitations, duplicate account/profile bindings, unresolved profile conflicts, and replacing another active invitation. Repeated attempts join an in-flight request and reuse the same reservation. Family/account/profile changes interrupt preparation. A joining user waits for identity resolution before being offered a new profile, and a late import rechecks identity at save time. Use native Family sharing controls to revoke or manage access. Both devices need the profile-invitation update; older builds do not interpret the optional participant reservation.

Show invitation preparation stages: family setup, account lookup, access check, profile synchronization, and link creation. The overall wait must accommodate the profile-export budget. An unchanged, server-verified invitation can be sent again without exporting the same share. Timing out or dismissing stops the screen's wait; retry joins any still-running operation.

Adding a child creates a new profile inside the existing family share. Current members gain access according to their existing family role as that profile synchronizes; no additional invitation is needed. Show clearly that the new child will be visible to the family's caregivers.

#### What each role can do

| Role | Product behavior |
| --- | --- |
| Owner | Add child profiles; record, view, edit, and delete shared activity for all children and shared maternal sessions; manage family invitations/access; stop sharing; explicitly delete the whole family. |
| Can edit | Add child profiles; record through the app or Siri, and view, edit, or delete shared activity across the family's children, including entries made by other caregivers and shared maternal sessions. Cannot manage owner-only controls in the app. Show original author and last editor so corrections remain understandable. |
| View only | View all children's shared history, charts, widgets, and any shared maternal history; choose personal display units. Disable profile and activity mutations, including through Siri, deep links, and future widget logging actions. |

CloudKit's read/write permission covers shared records, not just records authored by that participant [A15]. “Can edit only my own entries” is therefore **not** a security guarantee offered by v1. Likewise, a UI-hidden field is not private from a participant who can read the shared data. Implement private pumping, if chosen, as a separate persistence boundary.

#### Daily use and synchronization

Caregivers see the same family and child profiles, with a separate logical history for each child. If one records a 90 mL bottle for Robin, it appears on the other's Robin timeline with the occurrence time and author when CloudKit synchronizes it; Jamie's totals do not change. The second person can display that same amount in ounces. Each can use Siri and child-configured widgets with their granted family permission. A shared maternal pumping session appears once in the mother's family history.

An entry first saves durably on the recording device. Mark it **Saved on this iPhone / Sharing pending** while upload is outstanding; merge remote records and rebuild summaries as imports arrive. CloudKit synchronization is eventual and its schedule is system-controlled, so neither a local save nor a successful upload proves that the other caregiver has received the record. Show a last successful sync time rather than “Delivered to Alex” [A8].

If both people record different events offline, keep both after sync. If they edit the same event, preserve competing revisions and surface a conflict for review; that is app behavior to implement, not a conflict-resolution guarantee provided by CloudKit. Keep the existing duplicate, deletion, and timer-overlap rules.

Leaving/removal ends access to the entire family for that participant once the change reaches their device; clear all shared child/maternal caches and family widget snapshots on detection. Their previously synchronized entries remain part of the family's history with author attribution. The owner retains the family and all child histories when stopping sharing. Do not promise immediate removal from an offline device or recall of previously exported copies.

#### Storage boundary

Use **one `CKShare` rooted in the self-contained Family graph**, containing its ChildProfiles, ChildActivities, family-scoped CaregiverProfiles, and any shared PumpingSessions. The owner stores the graph in their private CloudKit database, and invitees access it through their shared database; these represent one shared family, not independently maintained histories. Confirm attribution names independently of iCloud identity disclosure. Core Data's CloudKit sharing uses object-graph/zone boundaries and does not support arbitrary cross-share relationships [A8].

Do not create a separate share per child. All children and family-shared pumping stay in the same graph and inherit family permissions. Private entry preferences and any private maternal pumping remain outside that graph, using scalar family/child/caregiver IDs rather than cross-store object relationships. If pumping is private, never leak it into shared summaries, Siri responses, or widget snapshots for other caregivers. Hiding a child in the UI cannot implement child-specific access control inside this family share.

### Reliability requirements

- All normal logging works offline after initial setup. Sync is eventual, not a real-time guarantee. Clearly represent local-only, pending, synced, unavailable, and access-revoked states.
- Create UUIDs before saving; retry an existing queued command with its existing ID. Do not treat timestamp equality as identity.
- Preserve edits as revisions or an application change log. When independent edits conflict, retain both versions and show a resolution item; avoid silently applying a field merge that creates a bottle composition nobody entered. Spike the concrete revision design before implementation.
- A deletion wins over a stale offline edit of that record; retain the edit in recoverable conflict history and require an explicit restore to recreate visibility. An account-linked caregiver revision is the exception: keep that profile active if it conflicts with deletion, preserve both revisions, and require review instead of hiding someone's sign-in profile.
- Report duplicate-looking independently created records; do not merge automatically.
- On revoked family access or leaving the family share, remove all local shared child/maternal data and derived snapshots when revocation is received; explain that an offline device cannot discover revocation instantly. Do not automatically copy shared records into an unshared family.
- Sync errors, quota limits, iCloud sign-out, and account changes never turn a failed sync into an apparent local save failure. Preserve authorized unsynced local edits and explain recovery options; prevent writing into another account's active log by accident.
- Export, deleting a child with its history, and deleting the whole family are distinct explicit actions with visible scope. Deleting a child preserves siblings and maternal pumping; deleting the family affects all of its shared children and shared maternal sessions. No external analytics containing child names, event details, quantities, or caregiver notes; logs must redact personal fields.

## 10. Visual direction and accessibility

**Calm, precise, native.** Warm near-white background, quiet child-specific accents, and distinct labeled diaper states. Use the system font and SF Symbols in implementation; ImageGen's approximations of typography and icons are visual references.

**App identity: Cocoon.** Use the selected swaddled newborn in its mirrored diagonal, three-quarter pose: ivory head at upper left, rounded sage feet at lower right, and an ivory crossing wrap on evergreen. Keep this family-level icon consistent across child profiles. Deliver it as a native Icon Composer document with separate body, head, and wrap groups over a full-bleed background. Enable native glass with restrained refraction, translucency, specular highlights, and shadows; let the system apply the outer mask. Keep the head mostly opaque for recognition. Preserve the same silhouette and visible fold across default, dark, clear, and tinted appearances, and review small-size legibility. The integrated source and native renders are in [the icon gallery](artifacts/app-icon/README.md), following [Apple's app-icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons).

Child profiles have an optional gender setting, entered explicitly during onboarding or in Settings → child. It supplies the default Boys/Girls growth reference; a previously saved reference always takes precedence. Advanced growth settings offers an optional override. The separate optional `colorTheme` field allows Sage, Blue, or Rose; nil follows the gender default, and changing it never changes the growth reference. Boy uses muted blue accents and soft blue surfaces; Girl uses muted rose accents and soft rose surfaces; Not set keeps the original sage palette. Never infer this setting from a name. Apply it to the child's screens, logging controls, and widget, with readable light and dark variants. Open drafts remain colored for their captured child even when a widget selects a sibling. Keep family and maternal pumping screens neutral, and retain consistent milk/formula chart colors across children. The widget cache carries the resolved appearance, without treating colors as growth information. Store the optional setting with the shared child profile; older records without the field remain valid and neutral.

The user's ambition is a 2027 Apple Design Award-caliber experience. Pursue that through exceptionally clear interactions, thoughtful native integrations, accessibility, coherent materials, and dependable everyday use. These screenshots establish a direction; they do not establish award readiness.

Use large navigation titles, standard sheets, segmented controls, native date/number entry, and a bottom tab bar. Keep important save/timer controls reachable near the bottom. Native system materials may appear on navigation, but charts and text sit on stable high-contrast surfaces. Follow the system appearance and Reduce Transparency settings; avoid adding decorative glass to every card.

Use native Liquid Glass for the four quick-log icons, child menu, amount-adjustment buttons, primary Save action, and temporary save confirmation. Group related effects in `GlassEffectContainer`; keep milk/formula and history cards opaque. Quick actions open their editors with source-linked native zoom transitions. Give presses a short spring response, roll displayed quantities between adjustments, and animate the confirmation into place. Exact keyboard entry stays immediate and tappable, and animations never delay a save or add a step. Refresh Today totals immediately after saves, edits, imports, Undo, and changes received from iCloud [A18].

On a cold app session, the Cocoon mark forms from one continuous cloth in the usable Today header over 0.85 seconds; the welcome screen uses the same motion at a larger scale. This is not a blocking launch interstitial. The static system launch screen uses the app's adaptive canvas. Logging, deep links, tab changes, backgrounding, and Reduce Motion settle the opening immediately; it never replays on an ordinary return to the app. Time presets use a brief selected-state transition and accessible selection feedback. Chart details crossfade inside reserved space and retain an explicit dismiss action. Bottle/pumping field reflow remains local, preserves drafts, and is disabled during keyboard editing or Reduce Motion. Only a selected child's bottle or diaper save animates the intake-card fold. See the [October motion review](design/motion-review-2026-10-09/README.md) for native recordings, measured timings, and verification limits.

Reduce Motion removes custom zoom, scale, symbol bounce, and numeric rolling; confirmation uses a brief fade. Capture the sheet's transition choice when opening it so changing accessibility settings during editing never recreates or clears the draft. Reduce Transparency and increased contrast use solid custom-control surfaces. Disabled amount controls have a subdued symbol and solid surface, distinct from enabled glass controls. Keep decorative symbols inside their fixed touch targets as text grows; all labels and quantities continue using Dynamic Type. The primary Save button targets 56 pt at the default text size and expands for larger text.

All frequent controls target at least 44 × 44 pt, body text starts from native 17 pt, and every screen supports Dynamic Type, VoiceOver, increased contrast, dark mode, right-to-left layout, and Reduce Motion. Do not use color as the sole signal. At accessibility sizes, reflow dense metric rows and convert routine charts to an accessible list [A9]. Replace compact segmented choices with readable native menus; stack quantities, feed counts, history timestamps, and left/right timer values before truncating. Keep exact amounts visible and complete. Separate date and time controls vertically at accessibility sizes, and use full-width quick-log rows at the largest settings. Keyboard dismissal must be explicit in bottle, pumping, nursing duration, and care-note entry; dismissing the keyboard must not dismiss an unsaved draft.

The supplied App Store asset page covers marketing rather than application layout. Apply its guidance to later release assets: lead with real core flows, maintain one coherent visual style, use readable captions, and show actual supported behavior [A0]. These design PNGs are **concept mocks**, not screenshots captured from a shipping build and not evidence of working Siri, CloudKit, or WidgetKit. Capture real-device/simulator screens for submission once implemented.

## 11. Acceptance examples

| Area | Required result |
| --- | --- |
| Multiple children | One family can contain Robin and Jamie. Recording a bottle, diaper, breastfeeding session, weight, or temperature for one changes only that child's history and summaries. |
| Child colors | Explicit Boy/Girl/Not set choices select blue/rose/sage respectively. Switching children changes the palette without changing records or an open draft's target. The profile choice persists and reaches that child's widget. |
| Single-child intents | With Robin as the only child, the child input can be omitted in Siri and Shortcuts for every child-scoped intent. Resolve Robin without a name, picker, or child-only confirmation; still name Robin in the success response. |
| Multiple-child intents | With Robin and Jamie, an explicit/configured child succeeds without an extra child question. A new untargeted log asks which child before saving; canceling writes nothing. |
| Changed child list | Adding Jamie makes a previously generic single-child shortcut ask for a child on its next invocation. A shortcut explicitly configured for Robin keeps Robin's ID. A partially imported family must not be mistaken for a one-child family. |
| Invalid or ambiguous target | An unknown/deleted explicit child never falls back to the sole remaining child. Duplicate names require clarification. With no children, request setup and write nothing. |
| Child-specific defaults | Robin's last bottle is 90 mL milk + 30 mL formula; Jamie's is 60 mL milk. Switching children restores the matching caregiver/child values. A new child's draft is blank. |
| Draft and timer identity | Switching the selected child does not retarget an open draft or timer. Separate tandem sessions retain separate child IDs and durations. An exact active session can identify its child for pause/finish. |
| Combined diaper | Saving both creates one event; changes +1, wet +1, soiled +1, both +1. |
| Quick logging | Today offers one-tap Pee/Poo/Both with Undo; a remembered bottle needs only opening the form and saving. Keyboard navigation remains reachable with large text. In compact-height landscape, Done reveals Save. |
| Quick amount adjustments | Independent ±0.25 oz / ±10 mL controls update the amount and save total, repeat on hold, stop at zero, and preserve canonical precision. Cancel leaves saved defaults unchanged; immediate Undo of a new bottle restores its prior defaults. Exact keyboard entry remains available. |
| Siri feeding answer | For a specified child, return milk, formula, total measured intake, bottle count, and separate breastfeeding time for Last 24 hours, Today, or Yesterday. Sibling intake and maternal pumping never enter the result. Speak empty logs as missing records, not proof of no consumption. |
| Nurse report import | The supplied example proposes seven entries: three bottles totaling 8 oz, three diaper changes with three wet and two soiled, and the verbatim observation. Flag the first fraction, missing unit, suggested diaper times, and midnight rollover before saving. |
| Import review | Missing times or invalid quantities block saving selected rows. All rows are editable and optional. Likely duplicates begin excluded. Save the reviewed batch atomically; Undo removes the whole new batch; usual bottle defaults remain unchanged. |
| Previous feed | Save 90 mL milk + 30 mL formula, open a new manual feed: both values are visible and editable. Cancel does not change the saved preference. |
| Voice override | With that preference saved, “3 oz milk” creates only milk; it does not carry over the 30 mL formula. |
| Conversion | Repeated mL/oz switches preserve canonical quantity. Three 1 oz events sum before display rounding. |
| Backdating | At 09:41, “130 ml formula 30 minutes ago” resolves to 09:11, even if clarification finishes at 09:43. |
| Rolling edge | An event exactly 24 hours old is excluded. Deletion, edit, and remote import update totals. |
| DST | Rolling totals use 24 elapsed hours; daily charts use actual local calendar boundaries. |
| Breastfeeding | A left 8m24s + right 4m10s session totals 12m34s active time; pauses excluded; intake volume unchanged. |
| Pumping with multiple children | A mother logs 105 mL once, with no child input or question, even in a family with twins. Maternal pumped output increases by 105 mL once; neither child's consumed total changes. A later 90 mL bottle for Robin affects Robin only. |
| Offline | Entry persists through restart before sync. A later import does not create a second copy. |
| Sharing | Two real iCloud accounts can invite/accept one family, access its separate child histories, see author attribution, edit offline, and recover a conflict. Test revocation and account change. |
| Invitation scope | One invitation gives the member their assigned role for all current children and children added later, with no extra invitations. Reopening it does not create a duplicate family or child. An uninvited account cannot join by receiving a forwarded private-share URL. |
| View-only member | Shared history and widgets work, including local unit switching; activity writes through UI, Siri, or extension entry points are rejected. |
| Attribution and leaving | Edits preserve original author and last editor. A departing member's synchronized entries remain in the family's histories; their shared caches for every child and shared maternal session clear when departure is processed. |
| Deletion scope | Deleting Robin preserves Jamie and maternal pumping. Deleting the whole family is a distinct action; revoking family membership clears every associated child widget when received. |
| Concurrent actions | A local UI save and intent save serialize safely; a retried identical command ID has one event. Separate real feeds are not discarded. |
| Widget expiry | An old event falls out in a later scheduled snapshot without a new log action. Snapshot timestamp accurately conveys freshness. |
| Widget child identity | Robin's and Jamie's widgets display only their assigned child's data. With one child, widget setup defaults to that child. Adding a sibling, switching the app's selected child, or renaming a child does not reassign an existing widget. A deleted target produces an unavailable/setup state. |
| Widget units | Tapping a volume switches every volume in that widget between mL and oz without opening the app or modifying records. Repeated round trips preserve canonical quantities. |
| Widget unit persistence | The selected unit survives a timeline reload/restart and is used by other Swaddle widgets on that device after refresh. Another caregiver's units and app entry defaults are unchanged. |
| Widget units offline | Conversion works from the cached snapshot without cloud access; its “As of” time is unchanged. A protected/locked device follows system authentication rules. |
| Widget tap routing | The unit button converts; a history link opens the correct child at the top of Today with Last 24 hours selected, even from a pushed screen. An existing editor retains its original child and draft until saved or canceled. Neither widget action logs a feed. VoiceOver labels identify the current and target unit. |
| Privacy | Revoked access clears widget data; protected-store failures do not claim success; private pumping never enters shared aggregates if chosen. |
| Accessibility | Large text retains all actions; VoiceOver announces each control's state and each chart's data; tinted widgets remain understandable. |
| Missing data | No entries renders an explicit empty state, not a zero-health judgment or a fabricated trend. |

## 12. Ideas worth exploring

1. **A handoff view:** last bottle, last diaper, active breastfeeding, and caregiver notes in one place. The shared timeline already contains the facts; avoid adding a chat system initially.
2. **One reliable “usual bottle” shortcut:** high value at night, provided the resolved composition is read back and confirmed. Compare its speed with the manual prefilled sheet during testing.
3. **A quiet night experience:** native dark mode, large controls, restrained haptics. Avoid success sounds and gamification.
4. **A visit summary:** date range, recorded intake split, diapers, weight history, notes, and missing-data caveat. Export only when explicitly requested.
5. **Last breast used:** a small factual reminder from the mother's sessions across children, with both/unknown states when appropriate and an unknown state for manually entered unsided sessions.
6. **Live Activity:** a natural follow-up for an active breastfeeding timer; calculate duration from timestamps, not a continually running background task.

Recommended success measures are task based: time/taps to record a diaper or repeated bottle, correct resolution of voice quantities/times, correction frequency, failed local saves, sync-conflict recovery, and accessibility completion. Do not collect infant activity data just to instrument these measures.

## 13. Research sources

Reviewed September 19, 2026. Apple documentation was read through its public Markdown/DocC JSON representation where the HTML required JavaScript. Source-derived capabilities are distinguished above from proposed product behavior and unverified device behavior.

- **A0:** [App Store asset best practices](https://developer.apple.com/app-store/asset-best-practices/).
- **A1:** [Apple Intelligence and Siri AI](https://developer.apple.com/documentation/appintents/apple-intelligence-and-siri-ai).
- **A2:** [App schema domains](https://developer.apple.com/documentation/appintents/app-schema-domains) and [Making actions and content discoverable by Apple Intelligence](https://developer.apple.com/documentation/appintents/making-actions-and-content-discoverable-by-apple-intelligence).
- **A3:** [App Shortcuts](https://developer.apple.com/documentation/appintents/app-shortcuts) and [AppShortcut](https://developer.apple.com/documentation/appintents/appshortcut).
- **A4:** [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date).
- **A5:** [Human Interface Guidelines: Widgets](https://developer.apple.com/design/human-interface-guidelines/widgets).
- **A6:** [Swift Charts](https://developer.apple.com/documentation/charts).
- **A7:** [Human Interface Guidelines: Charts](https://developer.apple.com/design/human-interface-guidelines/charts) and [Design an effective chart](https://developer.apple.com/videos/play/wwdc2022/110340/).
- **A8:** [Sharing Core Data objects between iCloud users](https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users).
- **A9:** [Human Interface Guidelines: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) and [Designing for iOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios).
- **A10:** [AppIntent.authenticationPolicy](https://developer.apple.com/documentation/appintents/appintent/authenticationpolicy) and [IntentAuthenticationPolicy](https://developer.apple.com/documentation/appintents/intentauthenticationpolicy).
- **A11:** [Creating a widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension).
- **A12:** [Assistant schema domain](https://developer.apple.com/documentation/appintents/app-schema-domain-assistant).
- **A13:** [Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities).
- **A14:** [Linking to specific app scenes from your widget or Live Activity](https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity).
- **A15:** [CKShare](https://developer.apple.com/documentation/cloudkit/ckshare), including participant requirements and permission scope.
- **A16:** [CKShare.publicPermission](https://developer.apple.com/documentation/cloudkit/ckshare/publicpermission).
- **A17:** [Human Interface Guidelines: Steppers](https://developer.apple.com/design/human-interface-guidelines/steppers) and [SwiftUI button repeat behavior](https://developer.apple.com/documentation/swiftui/view/buttonrepeatbehavior(_:)).
- **A18:** [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views), [prominent glass buttons](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glassprominent), and [navigation transitions](https://developer.apple.com/documentation/swiftui/view/navigationtransition(_:)). Reviewed September 20, 2026.

### Primary navigation refinement — October 10, 2026

The three bottom tabs are **Today**, **Trends**, and **Milestones**. Each root screen has a clearly labeled-for-accessibility Settings gear at its trailing edge; Settings opens as a dismissible native sheet containing Children, Caregivers & sharing, Preferences, Siri & widgets, and Data & recovery. Existing family deep links open Settings. Preserve each tab’s navigation and selected child when Settings is dismissed.

Trends uses the selected child in its compact navigation header (Family pumping for maternal data). Remove the decorative “The rhythm of care.” heading and the separate ordinary-size child row. Period, metric, and volume controls sit together above the chart; controls reflow for narrow widths, custom-date labels, and large text while retaining 44-point targets. Pumping → All pumping sessions keeps history, editing, and import available for active and deleted profiles.


## English and Spanish

The app, widgets, Siri action descriptions and shortcut phrases, accessibility copy, errors, import guidance, and milestones support English and neutral Spanish. Use the iPhone's preferred/per-app language; Settings includes an App language link to native iPhone settings. Numbers and dates follow the region independently of language. Original names, notes, import field names, identities, source values, and frozen milestone source wording remain unchanged. Spanish CDC titles are matched by stable skill ID to the official Spanish pages, including their different nine-month ordering; WHO motor titles are translated for display. All resources work offline.
