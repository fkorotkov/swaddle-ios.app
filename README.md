# Swaddle

App Store listing: **Swaddle: Newborn Log**. A native SwiftUI iPhone app for one family and multiple children. The app records bottles, diapers, breastfeeding, maternal pumping, weight, and temperature, with Swift Charts trends, App Intents, and interactive Home Screen widgets.

The product contract is in [SPEC.md](SPEC.md). The public website is in [website](website/) with [hosting and publishing instructions](docs/website.md). Design experiments and private QA evidence stay in the local checkout. Preview fixtures never populate a person's family log.

The app uses **Cocoon**, an ivory-and-sage swaddled newborn on evergreen, angled from upper left to lower right. Three native glass layers give the head, cocoon, and wrap separate lighting and refraction. The [Icon Composer source](BabyActivityRecorder/Cocoon.icon/) includes the app's layered artwork.

The Cocoon interface carries that identity into warm ivory and deep forest appearances, serif headings, a folded blue intake surface, amber pumping, and a connected care timeline. Bottle and Pumping stay prominent; breastfeeding and less frequent actions are under **More**. Local saves animate the fold and timeline once, while synchronization stays in its fixed status control. Reduce Motion removes positional and numeric motion. Chart values occupy a reserved area beneath the plot, with explicit dismissal and unit conversion.

## Run locally

This project uses Xcode 27's `project.xcproj` format. Development was verified with **Xcode 27.2**, the **iOS 27.2 Simulator SDK**, and an **iPhone 18 Pro** simulator. App and widget deployment targets are iOS 26.0.

1. Open `BabyActivityRecorder.xcodeproj` in Xcode.
2. Select the shared `BabyActivityRecorder` scheme and an iPhone simulator.
3. Run. Onboarding starts empty; create a fictional family to exercise the app.

Simulator builds use durable local Core Data storage and the App Group widget cache. CloudKit is intentionally disabled in Simulator. No network service or third-party dependency is needed for local logging.

The repository includes a small client for **Xcode's native MCP bridge**. Enable Xcode's MCP tools and approve its first workspace access request, then run:

```sh
python3 scripts/xcode_mcp.py BuildProject
python3 scripts/xcode_mcp.py RunProject '{"attachDebugger":true}'
```

The helper selects the shared app scheme and `iPhone 18 Pro`. It opens the workspace on each connection because Xcode's workspace identifiers are session-specific. It also supports `--batch path/to/jobs.json`, with jobs shaped as `{"name":"BuildProject","arguments":{}}`.

## TestFlight

See the local `RELEASE.md` guide for the most recently verified TestFlight build, availability in **Owner testing** and **Family testing**, archive artifacts, and remaining physical-device checks. Source changes described below may be awaiting the next upload; local `QA.md` records their verification and release scope. Update the existing app through TestFlight to retain the Production iCloud setup.

## What is implemented

| Area | Behavior |
| --- | --- |
| Settings | Add and rename children; optional birthdays and gender; child-specific history, summaries, and drafts. Caregiver attribution and mother profiles. |
| Diapers | One-tap Pee / Poo / Both on Today, with immediate Undo. Custom opens a form to choose the time, contents, and note before saving. A mixed diaper counts as one change, one wet, and one soiled. |
| Bottles | Milk and prepared formula components, exact decimal mL storage, oz entry/display, and caregiver/child-specific remembered amounts. Independent ±0.25 oz / ±10 mL adjustments, hold to repeat, or tap for exact typing. Successful new bottles update defaults; edits and failed saves do not. Immediate Undo restores the previous defaults. |
| Breastfeeding | Persistent start/pause/resume/switch/finish sessions, manual duration, and corrections. Timers remain attached to their original child. |
| Pumping | Mother-scoped sessions, optional left/right amounts and duration, separate history and totals. Never counted as a child's consumption. Pumping is family-shared in this build. |
| Measurements | Weight and temperature with units, timestamps, and temperature method. |
| History | Edit, soft-delete, author attribution, change history, and a short undo window for newly created entries. Review competing edits and explicitly restore deleted entries or children. Deletion beats a stale edit. Overlapping nursing sessions are surfaced for review. |
| Dashboard | Today places the summary above both quick-logging rows for easier thumb reach, followed by the care timeline. Rolling 24 hours or calendar Today, 7/30/custom trends, routine patterns, list alternatives, and family reporting time zone. Tap a chart for exact values beneath the plot; close with × or tap the selected day again. |
| Siri | Voice logging, guided bottle questions, spoken feeding totals, and last-feed lookup. iOS 27 adds schema-based care notes, search/open, record indexing with opt-out, and onscreen context. One child needs no name; multiple children disambiguate. |
| Care-note import | Paste or type a handoff, choose its child and starting date, then review editable entries before an atomic save. Supports BM, formula, pee/poo, fractions, units, and overnight notes. Observations stay verbatim care notes. Likely duplicates start excluded; Undo removes the whole new batch. |
| Widgets | Small, medium, and large child-configured widgets. Tap the volume area to switch mL/oz in place across this device's widgets. Other areas open that exact family/child. |
| Sharing | Core Data private/shared stores, private CKShare invitations, native owner/participant sharing controls, invitation acceptance, permission checks, account identity linking, and shared-import gating. Owner-only family deletion. Requires signed device verification. |

There are no feeding targets, clinical interpretation, accounts on a custom server, or analytics collecting infant activity.

Swaddle uses 1 oz = 30 mL for entry, Siri answers, and display without rewriting existing mL values. Bottle and manual breastfeeding quick times are Now, 30 minutes ago, and 45 minutes ago.

For the usual bottle, open **Bottle** and tap **Save**. For a small change, tap minus or plus once before saving. The keyboard stays closed until an amount is tapped. Pumping uses the same controls; bottle, pumping, manual nursing, and pasted-note entry offer explicit keyboard dismissal. In landscape, tap Done after typing to reveal Save. At accessibility text sizes, menus and stacked summaries replace compact layouts. See local `QA.md` for measured controls, native renderings, and live verification.

Choose the child’s gender once in **Settings → child**. The WHO growth reference defaults from it; any previously saved reference is preserved. **Advanced growth settings** contains an optional reference override. **A little color → Color** independently offers Automatic, Sage, Blue, or Rose for the child’s log and widgets. Changing appearance never changes percentiles. Existing profiles and widget caches remain compatible.

## Hands-free logging and questions

Today → **Just ask Siri** and Settings → **Siri** explain voice logging without asking people to build a shortcut. Say “Record pee only in Swaddle,” “Record a bottle in Swaddle,” “Record the usual bottle in Swaddle,” or “How much did my baby eat in Swaddle?” The usual bottle confirms remembered amounts. A new bottle asks breast milk, formula, or both when amounts are missing, then asks only for the missing components. Supplied amounts remain authoritative.

On iOS 27, **Care history in Siri & Search** is enabled by default to expose the current family's completed care records and notes to system search. Genuine care notes adopt Apple's Notes schema; Siri can create a text note without silently logging a feed. Search/open actions navigate to a current record or report, and visible records and feeding summaries provide onscreen context. The named local search index updates with edits and observed sharing/account changes, and clears when disabled. Queries and content export independently recheck current access. This is a per-device, per-family preference. Turning it off also disables onscreen context; explicit opt-outs persist across launches.

Feeding totals use app calculations: Last 24 hours, Today, or Yesterday in the family's time zone. Milk, formula, unknown splits, and nursing duration remain separate. Reports have stable family/child/period IDs and recalculate when queried or exported; rolling totals are never stored in Spotlight. iOS 26 retains the existing voice logging and answers.

Eight App Shortcuts remain as internal phrase registrations for custom baby-care actions. Apple's public schema catalog still has no feeding/diaper domain. The new schema actions are assistant-only and the app no longer directs people into the Shortcuts app. Compiler metadata, automated tests, and native previews are verified; actual iOS 27 Siri AI routing, natural-language variations, and HomePod/Apple Watch execution require device testing. These changes are available in **TestFlight 1.0 (8)**. See the [Siri integration audit](SIRI_INTEGRATION_AUDIT.md) for exact capabilities and acceptance prompts.

## Import a nurse's handoff

Pumping exports can be imported from **Trends → Pumping → All pumping sessions → Import pumping** or by pasting pump JSONL into Care notes. Choose a pumping profile once, review the batch, and save. Total-only sessions retain unknown left/right splits; stable source IDs prevent repeated imports. The accepted format and examples are in [IMPORT_FORMAT.md](IMPORT_FORMAT.md), and under **Format tips & missing units → Advanced: JSON Lines** in the app.

Today → **Paste notes** accepts up to 50,000 characters or 500 lines, with an explicit paste control and a built-in example. Choose the first calendar date for undated notes; explicit dates, ISO timestamps (including UTC offsets and seconds), and a `Timezone:` header take priority. A clock moving from late evening to early morning can advance to the next day. Untimed activities may borrow a nearby time within the same paragraph, visibly marked as a suggestion; an activity with no usable time cannot be saved until corrected.

The sample report proposes three milk bottles (2.5, 3, and 2.5 oz), three diapers (three wet, two soiled), and the original cheek observation. The first `21/2` quantity, its missing unit, and the inferred diaper times all require review. After checking the child, dates, times, and amounts, save the selected entries together. Imported bottles never replace the usual bottle defaults. Original wording is retained, with no medical interpretation.

Pipe-separated feeding exports are read directly without waiting for the language model. For example, `2026-05-10 08:00 | Mixed BM/formula | 64.15 ml | Breast milk 2 oz; formula 5 ml.` creates one bottle with independently converted components. The full `Bottle feed | mixed | Total: … | Breast milk: … | Formula: …` format is also supported. Headers are metadata; observations, repeated quantities, and additional times in notes stay attached to the original feed. Rounded totals are checked against component precision; conflicting or partial amounts require correction. A known total with no split is saved as **Split not recorded**, included in total intake but never assigned to milk or formula. The review summarizes selected intake, filters entries needing details, excludes likely duplicates both in the log and within the batch, and keeps its confirmation control beside Save.

Feeds with unrecorded splits use record envelope version 2. Update every caregiver’s app before importing them: older builds request an update instead of silently treating their intake as zero. Ordinary records remain version 1, existing records decode unchanged, and no CloudKit schema change is required.

For small unstructured reports with unclassified lines, supported devices use Apple's **Foundation Models** framework for guided line classification on device. Amounts and times are extracted from the source text by deterministic code. Unavailable models, unsupported language, or generation failures fall back to the same review workflow; ambiguous details remain editable. The implementation follows Apple's [Foundation Models code-along](https://developer.apple.com/events/resources/code-along-205/). A broad conversational assistant is outside this build's scope.

## Enable iCloud on devices

The app and widget use automatic signing with the Fedor Korotkov development team (`L2G74CB269`). Select another team in both targets' Signing & Capabilities settings if needed. Identifiers currently are:

| Purpose | Identifier |
| --- | --- |
| App | `com.github.fkorotkov.LittleLog` |
| Widget | `com.github.fkorotkov.LittleLog.Widgets` |
| App Group, both targets | `group.com.github.fkorotkov.LittleLog` |
| CloudKit container, app | `iCloud.com.github.fkorotkov.LittleLog` |

Capabilities and entitlements are present in the project. Confirm that the bundle IDs, App Group, and iCloud container exist under the selected team; if changing them, also update `PersistenceController` and the URL type identifier. The app needs iCloud/CloudKit, push notifications, and the remote-notification background mode. `LittleLogCloudKitEnabled` is enabled for signed device builds.

These identifiers establish a new app and storage namespace. Register them under your development team before archiving for TestFlight. Data from builds using the previous identifiers is not automatically migrated into the new App Group or CloudKit container. The `littlelog` URL scheme stays the same.

To install from Xcode, connect and unlock the iPhone, enable [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device) in Settings → Privacy & Security, and complete the restart and confirmation on the phone. Choose the physical iPhone as the run destination and Run the shared `BabyActivityRecorder` scheme. Xcode must include that device in both development provisioning profiles.

Run a development build on two devices signed into different Apple Accounts. Create a family on the owner device; on the second device, open its invitation before creating another family. Settings → Invite or manage caregivers opens Apple's private sharing interface. Select edit or view-only access. Family membership applies to every current and future child and shared pumping session. Personal bottle defaults remain in each user's private store, outside the family relationship graph.

Participants can open Settings → Manage family access to view membership or leave through Apple's sharing controls. Owners can stop sharing while retaining their log; a separate, explicitly confirmed Delete family action deletes the family's Core Data graph. Apple's [sharing controller](https://developer.apple.com/documentation/uikit/uicloudsharingcontroller) determines available membership actions from the user's CloudKit role; [Core Data sharing](https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users) manages the private/shared stores.

To invite someone to a pumping profile created in advance, the owner opens **Settings → caregiver → Invite this caregiver**, enters the recipient’s Apple Account email, and chooses **Create invitation → Send invitation**. This grants editing access to the whole family. The accepting account reuses the original caregiver ID and pumping history. Use this feature with updated builds on both phones; creating a link does not send a message. The optional reservation lives inside the existing versioned caregiver payload, so this feature needs no CloudKit schema deployment. Two-account verification remains a release check.

To remove an unused profile, the owner opens **Settings → caregiver → Delete caregiver** and confirms. Existing pumping and care history stays available, with original names and attribution. The profile can be restored under **Settings → Review edits & deleted entries**. Your own profile and Apple Account linked profiles are protected. This removes a profile from new-entry choices; use Family sharing to manage iCloud invitations or access separately.

To combine duplicate profiles for the same person, the owner opens **Settings → caregiver → Merge caregiver profiles**, chooses the other profile, and selects the profile to keep. Keep the profile already linked to their Apple Account or invitation. Pumping and completed breastfeeding histories are grouped under it; original entry IDs, dates, amounts, notes, and recording authors stay intact. The duplicate disappears from new-entry choices. Sessions are not deduplicated or deleted, and iCloud access is unchanged.

You can undo a merge under **Settings → Review edits & deleted entries → merged profile → Separate profiles**. Original entries return to their original profiles, including edits made after the merge; new entries stay with the kept profile. The restored duplicate is unlinked. Update every family device before merging: merge aliases use record envelope version 3, and older builds require an update to read them. Existing payloads keep their versions; no CloudKit schema deployment is needed. Simulator and replica tests cover merging; live two-account verification remains a release check.

The complete CloudKit schema was initialized, inspected, and deployed to Production under the real team. Cross-account sync remains unverified. Do not treat successful schema deployment, local saves, builds, or previews as evidence of successful cross-account sync. See local `QA.md` for the remaining device checks and product gaps.

## Structure

| Path | Responsibility |
| --- | --- |
| `BabyActivityRecorder/Domain` | Foundation-only typed records, validation, revision projection, metrics, and widget payloads. Also built as the `LittleLogCore` Swift package. |
| `BabyActivityRecorder/Persistence` | Core Data model and stores, observable command/store boundary, private defaults, CloudKit sharing, widget snapshots. |
| `BabyActivityRecorder/Features` | Small feature views and stateful editor drafts; Today, Trends, Family, and logging sheets. |
| `BabyActivityRecorder/Design` | Adaptive semantic colors, shared controls, isolated DEBUG-only preview data. |
| `BabyActivityRecorder/Intents` | Typed App Entities, App Intents, and App Shortcuts. |
| `LittleLogWidgets` | Widget configuration, timeline recalculation, views, and idempotent unit-setting intent. |
| `Tests` / `LittleLogTests` | Domain regression tests / Core Data integration tests hosted by the app in Simulator. |

`LogStore` is `@MainActor @Observable`. Editor drafts capture their child and revision parents when opened. Every save validates and commits before reporting success. Revisions are immutable records with parent IDs; UI projections retain competing heads instead of merging bottle components. Widget display preferences never mutate health records.

## Tests

```sh
swift test --scratch-path /private/tmp/littlelog-swift-build
xcodebuild test -project BabyActivityRecorder.xcodeproj \
  -scheme BabyActivityRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -parallel-testing-enabled NO
```

The verification record, limitations, and interactive QA checklist are in local `QA.md`.

### Navigation

Bottom tabs: **Today · Trends · Milestones**. The Settings gear is available from every root screen. It contains children, caregivers/sharing, Siri/widgets, preferences, and data/recovery. Trends places the child in the header and groups its period, metric, and unit controls directly above the chart. Its pumping view links to the full session history and import.
