# Controlled iCloud syncing

Swaddle keeps Core Data for local persistence and uses one `CKSyncEngine` for the private CloudKit database and one for the shared database after a verified handoff. This is a replacement for Core Data mirroring of these stores, not a second concurrent writer.

## What stays the same

- `Private.sqlite` and `Shared.sqlite`, including local object identities.
- The existing `CD_FamilyRoot`, `CD_Revision`, and `CD_PrivatePreference` CloudKit record types and their deployed fields.
- Existing cloud record IDs and active family shares, including accepted participants. Verified orphan revisions outside the family zone are copied into the existing share; their original cloud records are retained.
- Family, caregiver, child, activity, pumping, revision, parent, and import IDs.
- Versioned care payload bytes, canonical amounts, timestamps inside care payloads, attribution, notes, and tombstone revisions.
- Private bottle defaults stay in the user's private database outside family share zones.

There is no user-facing reimport or replacement invitation. A previously unshared legacy family is first isolated by Core Data into a private family share zone, without adding participants or sending invitations. This prevents a zone-wide share from exposing private preferences.

## Upgrade sequence

1. Existing installations initially keep Core Data mirroring. With no local family, initial imports must finish before the handoff; first-run creation remains gated on discovering an existing family.
2. Read public persistent history. Unexported physical deletions still block the upgrade. Append-only inserts can transfer to the new outbox, so a failed legacy exporter no longer creates an impossible export barrier.
3. Authenticate the account and existing family shares. Capture all local rows and public CloudKit mappings. Missing mappings use provisional identities only for comparison; they are not permission to upload a second copy.
4. Save an inactive checkpoint, close the legacy stores, and make a consistent `BeforeCKSyncEngine` backup. Reopen the same stores in a fresh container without mirroring and verify that the local snapshot did not change.
5. Fully page every accessible custom zone while the old writer is stopped. Recover existing cloud identities using exact revision/family UUIDs, or private-default key/date matches, and verify every field. Queue a missing local insert only with persistent-history proof. Recheck account and invitation access, and the unchanged local snapshot, before activating the checkpoint.
6. Repair a cross-zone legacy revision only when its immutable fields and payload family ID match the local record, its original private zone has no share, its old family reference is orphaned, and its intended family already has a verified share. Copy into that existing zone without deleting or modifying the original. The durable journal remembers retained originals so subsequent fetches cannot create duplicates. Changed originals, ambiguous matches, another family's record, or destination collisions stop recovery.
7. Start CKSyncEngine with durable, account-bound metadata in `CareSync-v1.json`. Send pending records and fetch both databases. No care payload or CloudKit schema change is required.

A failed verification rolls back to legacy mirroring with the current local data intact. Only one writer owns the stores. The Today summary warns when family updates may be missing; **Check iCloud**, pull-to-refresh, foreground activation, and **Sync now** retry. Successful legacy setup/export events do not mark downloads current. **Copy sync diagnostics** reports engine state and counts without names, account identifiers, invitation links, or care contents.

The pre-handoff backup is retained locally for recovery. Deleting the family also deletes that backup. Do not downgrade an upgraded installation to an older app build that restarts Core Data mirroring against the active stores; a rollback needs explicit reconciliation of post-handoff changes.

## Sync behavior

- A local save returns promptly. The durable outbox records uploads and deletions; the app attempts a send and fetch shortly after the save. Relaunch reconstructs any changes saved just before an interruption.
- Foreground activation, launch, Today pull-to-refresh, pumping-history pull-to-refresh, and Family → Storage & calendar → **Sync now** request a sync. Concurrent requests share the running operation.
- CloudKit automatic scheduling and remote notifications remain enabled. Explicit requests can still fail or be throttled; they do not confirm that another phone has downloaded the result.
- Failed uploads do not prevent attempting downloads. A failure in one database or an invitation lookup does not skip fetching the other database. Permanent record/zone failures stay blocked until the next requested sync after checking permissions; transient failures use CKSyncEngine's retry scheduling.
- The UI distinguishes local saves, queued uploads, successful uploads, and the last successful awaited check of both databases. A generic Core Data setup event is not treated as proof of a completed controlled sync.

## Recovery and merging

The journal contains cloud identities/system fields, acknowledged baselines, the outbox, a replayable inbox, engine state, and cached shares. It is written atomically with protection until first unlock. Incoming batches are journaled before their Core Data transaction, including permanent object IDs, so an interruption after the data commit can replay without duplicating private preferences or care records. A storage/checkpoint failure stops the engines rather than advancing beyond uncommitted data. A retry in the same process reloads that durable checkpoint before replaying.

Care records retain Swaddle's append-only revision graph. Independent new entries merge; concurrent edits retain their parent/head information; deletions remain tombstone revisions. An attempt to change an already known immutable revision is an error. Mutable family name/time-zone settings use three-way field merging; the server wins when both devices change the same setting.

Deleted or revoked zones are not automatically recreated. Their visible records are removed, and unsent entries are retained in the protected local journal for recovery instead of being uploaded into a different family. Explicit acceptance of a new valid invitation can allow the zone again. Account changes suspend the engines; an account mismatch never repurposes the existing checkpoint or local data.

## Verification and release gate

The Swift package compiles the actual persistence/sync implementation on macOS and tests the same record codec and replica used by the app. It covers legacy IDs, durable uploads, edits during uploads, replay after a commit/checkpoint interruption, out-of-order arrivals, physical deletion, immutable revisions, private/shared separation, malformed payloads, missing migration mappings, and retry classification.

Before wider distribution, also complete an Xcode app build and app test run, inspect the native refresh UI, and verify a signed device handoff with two Apple Accounts. Check an existing accepted invitation, mixed old/new app versions, bidirectional bottle and pumping updates, concurrent offline changes, process termination, and permission revocation. Local fixture tests alone do not establish live cross-account compatibility with Core Data's mirroring implementation.

The app build, iOS tests, and native refresh/pumping interaction checks passed on September 25–26, 2026; see [QA.md](QA.md). The owner requested publication to the existing private TestFlight groups for the remaining live-device verification. That pilot is not evidence that the two-account checks have passed. Beta notes ask both family phones to update in place, retain their existing family, and compare history and bidirectional changes before treating the handoff as verified.

References: [CKSyncEngine](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5), [Apple's sync overview and manual-sync examples](https://developer.apple.com/videos/play/wwdc2023/10188/), [Core Data's CloudKit record representation](https://developer.apple.com/documentation/coredata/reading-cloudkit-records-for-core-data).
