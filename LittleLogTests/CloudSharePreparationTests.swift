import CloudKit
import Foundation
import Testing
@testable import BabyActivityRecorder

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct CloudSharePreparationTests {
    private func share() -> CKShare {
        CKShare(recordZoneID: CKRecordZone.ID(zoneName: UUID().uuidString))
    }

    @Test func onlyTheUnchangedAcceptedEditingInvitationSkipsProfileExport() {
        let reservation = CaregiverInvitation(shareRecordName: "share", participantID: "member", accountIdentity: "account")
        let accepted = CloudInvitationSnapshot.Membership(status: .accepted, role: .privateUser, permission: .readWrite)
        #expect(CaregiverInvitationReuse.canReuseAcceptedLink(previous: reservation, current: reservation,
                                                             membership: accepted, hasURL: true))
        #expect(!CaregiverInvitationReuse.canReuseAcceptedLink(previous: nil, current: reservation, membership: accepted, hasURL: true))
        #expect(!CaregiverInvitationReuse.canReuseAcceptedLink(previous: reservation, current: reservation, membership: accepted, hasURL: false))
        var different = reservation
        different.participantID = "someone-else"
        #expect(!CaregiverInvitationReuse.canReuseAcceptedLink(previous: reservation, current: different, membership: accepted, hasURL: true))
        different = reservation
        different.accountIdentity = "someone-else"
        #expect(!CaregiverInvitationReuse.canReuseAcceptedLink(previous: reservation, current: different, membership: accepted, hasURL: true))
        for status in [CKShare.ParticipantAcceptanceStatus.pending, .removed, .unknown] {
            var member = accepted; member.status = status
            #expect(!CaregiverInvitationReuse.canReuseAcceptedLink(previous: reservation, current: reservation, membership: member, hasURL: true))
        }
        for permission in [CKShare.ParticipantPermission.readOnly, .none, .unknown] {
            var member = accepted; member.permission = permission
            #expect(!CaregiverInvitationReuse.canReuseAcceptedLink(previous: reservation, current: reservation, membership: member, hasURL: true))
        }
        var publicMember = accepted; publicMember.role = .publicUser
        #expect(!CaregiverInvitationReuse.canReuseAcceptedLink(previous: reservation, current: reservation, membership: publicMember, hasURL: true))
    }

    @Test func acceptsCompletionFromABackgroundQueue() async throws {
        let request = CloudSharePreparation()
        let expected = share()
        let result = try await request.value(timeout: .seconds(2)) { completion in
            DispatchQueue.global().async { completion(.success(expected)) }
        }
        #expect(result.recordID == expected.recordID)
    }

    @Test func propagatesFailureAndAllowsAnotherAttempt() async throws {
        let request = CloudSharePreparation()
        let expectedError = NSError(domain: CKErrorDomain, code: CKError.networkUnavailable.rawValue)
        do {
            _ = try await request.value { $0(.failure(expectedError)) }
            Issue.record("A failed CloudKit operation should report its error.")
        } catch {
            #expect((error as NSError).domain == CKErrorDomain)
            #expect((error as NSError).code == CKError.networkUnavailable.rawValue)
        }
        let expected = share()
        let result = try await request.value { $0(.success(expected)) }
        #expect(result.recordID == expected.recordID)
    }

    @Test func repeatedTimeoutsKeepOnlyOneCloudKitOperation() async {
        let request = CloudSharePreparation()
        var starts = 0
        var completion: CloudSharePreparation.Completion?
        for _ in 0..<3 {
            do {
                _ = try await request.value(timeout: .milliseconds(1)) {
                    starts += 1
                    completion = $0
                }
                Issue.record("A callback that never arrives must time out.")
            } catch {
                #expect(error as? CloudSharePreparationError == .timedOut)
            }
        }
        #expect(starts == 1)
        // A late callback must not resume any of the timed-out continuations.
        completion?(.success(share()))
        completion?(.failure(CloudSharePreparationError.invitationNotReady))
    }

    @Test func ignoresAnOldCompletionWhileRetrying() async throws {
        let request = CloudSharePreparation()
        var oldCompletion: CloudSharePreparation.Completion?
        do {
            _ = try await request.value {
                oldCompletion = $0
                $0(.failure(CloudSharePreparationError.invitationNotReady))
            }
            Issue.record("The first attempt should fail.")
        } catch {
            #expect(error as? CloudSharePreparationError == .invitationNotReady)
        }
        let expected = share()
        let result = try await request.value { completion in
            oldCompletion?(.success(share()))
            oldCompletion?(.failure(CloudSharePreparationError.invitationNotReady))
            completion(.success(expected))
        }
        #expect(result.recordID == expected.recordID)
    }

    @Test func cancellationBeforeStartingDoesNotContactCloudKit() async {
        let request = CloudSharePreparation()
        var starts = 0
        let task = Task { @MainActor in
            try await request.value { _ in starts += 1 }
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("A cancelled screen should stop waiting.")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(starts == 0)
    }

    @Test func cancellingAScreenDoesNotStartADuplicateOnRetry() async {
        let request = CloudSharePreparation()
        let (started, signal) = AsyncStream<Void>.makeStream()
        var starts = 0
        var completion: CloudSharePreparation.Completion?
        let task = Task { @MainActor in
            try await request.value(timeout: .seconds(10)) {
                starts += 1
                completion = $0
                signal.yield(())
                signal.finish()
            }
        }
        for await _ in started { break }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Dismissal should cancel this screen’s wait.")
        } catch {
            #expect(error is CancellationError)
        }
        do {
            _ = try await request.value(timeout: .milliseconds(1)) { _ in starts += 1 }
            Issue.record("The original CloudKit operation is still pending.")
        } catch {
            #expect(error as? CloudSharePreparationError == .timedOut)
        }
        #expect(starts == 1)
        completion?(.success(share()))
    }
}
