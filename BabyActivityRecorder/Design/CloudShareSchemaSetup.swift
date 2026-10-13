#if DEBUG
import CloudKit
import Foundation

/// Explicit developer setup only; requires Development CloudKit signing.
/// Core Data's model initializer does not create CloudKit's system share type.
enum CloudShareSchemaSetup {
    nonisolated static func initialize(containerIdentifier: String) async throws {
        let container = CKContainer(identifier: containerIdentifier)
        guard try await container.accountStatus() == .available else {
            throw setupError("An iCloud account is required on this development device.")
        }

        let database = container.privateCloudDatabase
        let zone = CKRecordZone(zoneName: "SwaddleSchemaBootstrap-\(UUID().uuidString)")
        let savedZone = try await database.save(zone)
        print("SWADDLE_SHARE_SCHEMA_ZONE_CREATED")

        do {
            guard savedZone.capabilities.contains(.zoneWideSharing) else {
                throw setupError("The new development zone does not support zone-wide sharing.")
            }

            // An empty, private zone exercises Apple's actual CKShare serialization.
            // No family records, app-group files, participants, or invitation recipients are used.
            let share = CKShare(recordZoneID: savedZone.zoneID)
            share.publicPermission = .none
            share[CKShare.SystemFieldKey.title] = "Swaddle development schema check"
            guard let savedShare = try await database.save(share) as? CKShare,
                  savedShare.url != nil,
                  savedShare.publicPermission == .none,
                  savedShare.participants.count == 1 else {
                throw setupError("The development share was not saved with private, owner-only settings.")
            }

            let record = try await database.record(for: savedShare.recordID)
            guard let fetchedShare = record as? CKShare,
                  fetchedShare.url != nil,
                  fetchedShare.publicPermission == .none,
                  fetchedShare.participants.count == 1 else {
                throw setupError("The development share could not be verified.")
            }
            print("SWADDLE_SHARE_SCHEMA_READBACK_VERIFIED: \(fetchedShare.recordType)")
        } catch {
            // Only the new test zone is eligible for cleanup; never enumerate existing zones.
            do { _ = try await database.deleteRecordZone(withID: savedZone.zoneID) }
            catch { print("SWADDLE_SHARE_SCHEMA_TEST_ZONE_CLEANUP_FAILED: \(error)") }
            throw error
        }

        _ = try await database.deleteRecordZone(withID: savedZone.zoneID)
        print("SWADDLE_SHARE_SCHEMA_TEST_ZONE_REMOVED")
    }

    nonisolated private static func setupError(_ message: String) -> NSError {
        NSError(domain: "SwaddleSchemaSetup", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
#endif
