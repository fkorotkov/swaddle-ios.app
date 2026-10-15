# iCloud synchronization

Swaddle keeps Core Data as its local store and uses one `CKSyncEngine` for the private database and one for the shared database after a verified handoff from legacy Core Data mirroring. The two sync systems never write the same stores concurrently.

## Storage and sharing

- Local stores remain `Private.sqlite` and `Shared.sqlite`.
- Cloud records retain the deployed `CD_FamilyRoot`, `CD_Revision`, and `CD_PrivatePreference` types and fields.
- A family share includes every child, caregiver profile, care record, and shared pumping session in that family. Private bottle defaults remain outside family share zones.
- The owner accesses the family through the private database; participants access the same shared data through the shared database. Invitations retain private participant access with `CKShare.publicPermission = .none`.
- Care payloads are versioned. Family, record, revision, parent, import, and profile IDs remain stable across synchronization and upgrades.

## Saves, fetches, and status

A local save commits promptly and queues a durable upload. The app requests a send and fetch after a save, at launch and foreground activation, through pull-to-refresh, and through **Sync now** in Settings. Concurrent requests share the running operation. Automatic scheduling and remote notifications also remain enabled.

Failed uploads do not prevent attempting downloads; a failure in one database does not skip fetching the other. Transient failures use retry scheduling. Record or zone permission failures need access recovery and another sync request. Cancellation and interrupted work must preserve pending changes.

Status distinguishes local save, pending uploads, successful upload, and the last successful awaited check of both databases. None confirms that another phone has downloaded an entry. Offline phones cannot immediately detect revoked access.

## Checkpoints and merging

`CareSync-v1.json` is an account-bound journal containing record identities/system fields, acknowledged baselines, durable outbox and inbox, engine state, and cached shares. Writes are atomic and protected until first unlock. Incoming batches are journaled before their Core Data transaction; replay after an interruption must not duplicate records. Checkpoint failures stop the engines rather than advancing beyond durable data.

Care records retain an append-only revision graph. Independent new entries merge, concurrent edits retain their heads, and deletions remain tombstones. Changing a known immutable revision is an error. Mutable family name/time-zone settings use three-way field merging, with the server winning same-field conflicts.

Deleted or revoked zones are not automatically recreated. Visible shared data is removed when access loss is detected, and unsent changes remain in the protected journal for recovery rather than being uploaded into another family. A newly accepted valid invitation can permit the zone again. Account changes suspend the engines; an account mismatch never repurposes an existing checkpoint.

## Compatibility with existing installations

The runtime handoff remains necessary for installations that still use `NSPersistentCloudKitContainer`. Preserve it and its regression tests even though the original rollout plan is retired.

Before activation, the app verifies imports, persistent history, account/share access, local-to-cloud identity mappings, and remote record contents. Unexported physical deletions block handoff; proven local inserts can transfer into the new outbox. It closes the legacy stores before making a consistent `BeforeCKSyncEngine` backup and reopening without mirroring. The local snapshot must remain unchanged.

Only exact, verified legacy orphan revisions can be copied into an existing family share. Their original cloud records remain retained and journaled; ambiguous identity, a changed source, another family's record, or a destination collision stops recovery. Private preferences must never enter a family share zone. A previously unshared family is isolated into a share zone without adding participants or sending invitations.

Failed verification rolls back to legacy mirroring with current local data intact. The local pre-handoff backup remains available for recovery and is removed with family deletion. Downgrading to a build that restarts legacy mirroring is unsafe without reconciling post-handoff changes.

## Code and verification

- [`PersistenceController`](../BabyActivityRecorder/Persistence/PersistenceController.swift): local stores, startup, and handoff ownership.
- [`CloudSyncMigration`](../BabyActivityRecorder/Persistence/CloudSyncMigration.swift): compatibility checks, identity recovery, and backup handoff.
- [`CareCloudSync`](../BabyActivityRecorder/Persistence/CareCloudSync.swift), [`CareSyncJournal`](../BabyActivityRecorder/Persistence/CareSyncJournal.swift), and [`CloudRecordCodec`](../BabyActivityRecorder/Persistence/CloudRecordCodec.swift): engines, durable replica, and deployed record encoding.
- [`CareCloudSyncTests`](../Tests/CareCloudSyncTests.swift) and [`CloudSyncMigrationRecoveryTests`](../Tests/CloudSyncMigrationRecoveryTests.swift): transport, replay, account boundaries, and legacy recovery regressions, run with `swift test`.

Changes to these boundaries also require signed-device checks with two Apple Accounts: accepted invitations, bidirectional updates, concurrent offline changes, interrupted transfers, and permission revocation. Simulator fixtures cannot establish live CloudKit interoperability. **Copy sync diagnostics** provides state and counts without names, invitation links, account identifiers, or care contents.
