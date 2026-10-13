import CloudKit
import Foundation

nonisolated enum CaregiverInvitationStage: CaseIterable {
    case preparingFamily, findingAccount, checkingAccess, syncingProfile, savingInvitation

    var title: String {
        switch self {
        case .preparingFamily: String(localized: "Preparing family sharing…")
        case .findingAccount: String(localized: "Finding their Apple Account…")
        case .checkingAccess: String(localized: "Checking invitation…")
        case .syncingProfile: String(localized: "Syncing caregiver profile…")
        case .savingInvitation: String(localized: "Creating invitation link…")
        }
    }

    var waitingMessage: String {
        switch self {
        case .preparingFamily:
            String(localized: "iCloud is still preparing family sharing. Keep Swaddle open and try again shortly.")
        case .findingAccount:
            String(localized: "iCloud hasn’t finished looking up this Apple Account. Check your connection and try again.")
        case .checkingAccess:
            String(localized: "iCloud hasn’t returned the current invitation. Check your connection and try again.")
        case .syncingProfile:
            String(localized: "The caregiver profile is still syncing to iCloud. Its history is safe. Keep Swaddle open and try again shortly.")
        case .savingInvitation:
            String(localized: "iCloud is still saving the invitation. Try again shortly to get the link.")
        }
    }
}

nonisolated enum CaregiverInvitationReuse {
    static func canReuseAcceptedLink(previous: CaregiverInvitation?, current: CaregiverInvitation,
                                    membership: CloudInvitationSnapshot.Membership, hasURL: Bool) -> Bool {
        // Reopening the same accepted invitation does not create new access.
        // New reservations and pending/changed permissions still need export.
        previous == current && hasURL && membership.status == .accepted
            && membership.isFamilyParticipant
            && membership.permission == .readWrite
    }
}

nonisolated enum CloudSharePreparationError: LocalizedError, Equatable {
    case timedOut
    case invitationNotReady
    case familyChanged

    var errorDescription: String? {
        switch self {
        case .timedOut:
            String(localized: "iCloud is taking longer than expected. You can close this screen and try again shortly.")
        case .invitationNotReady:
            String(localized: "iCloud hasn’t finished creating the invitation link. Please try again shortly.")
        case .familyChanged:
            String(localized: "Your family or iCloud account changed. Reopen Family sharing to continue.")
        }
    }
}

/// Core Data's sharing operations have no cancellation API. A timed-out or
/// dismissed screen stops waiting, but retries must join the same operation.
@MainActor
final class CloudRequest<Value: Sendable> {
    typealias Completion = @Sendable (Result<Value, Error>) -> Void

    private struct Waiter {
        let continuation: CheckedContinuation<Value, Error>
        let timeout: Task<Void, Never>
    }

    private var requestID: UUID?
    private var waiters: [UUID: Waiter] = [:]
    var isRunning: Bool { requestID != nil }

    func value(
        timeout: Duration = .seconds(30),
        start: (@escaping Completion) -> Void
    ) async throws -> Value {
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let timer = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: timeout) }
                    catch { return }
                    self?.removeWaiter(waiterID, error: CloudSharePreparationError.timedOut)
                }
                waiters[waiterID] = Waiter(continuation: continuation, timeout: timer)
                guard requestID == nil else { return }
                let id = UUID()
                requestID = id
                start { [weak self] result in
                    Task { @MainActor [weak self] in
                        self?.complete(result, requestID: id)
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.removeWaiter(waiterID, error: CancellationError())
            }
        }
    }

    private func complete(_ result: Result<Value, Error>, requestID: UUID) {
        guard self.requestID == requestID else { return }
        self.requestID = nil
        let completed = Array(waiters.values)
        waiters.removeAll()
        for waiter in completed {
            waiter.timeout.cancel()
            waiter.continuation.resume(with: result)
        }
    }

    private func removeWaiter(_ id: UUID, error: Error) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.timeout.cancel()
        waiter.continuation.resume(throwing: error)
    }
}

typealias CloudSharePreparation = CloudRequest<CKShare>
