import Foundation
import Testing
@testable import BabyActivityRecorder

@MainActor
struct WidgetQuickLogTests {
    private func setup() throws -> (LogStore, ChildProfile, String) {
        let store = LogStore(persistence: PersistenceController(inMemory: true),
                             defaults: UserDefaults(suiteName: UUID().uuidString)!, publishesWidgets: false)
        try store.createFamily(childName: "Robin", caregiverName: "Sam", mother: false, unit: .ml)
        let child = try #require(store.selectedChild)
        return (store, child, "\(child.familyID)/\(child.id)")
    }

    @Test func eachControlSavesExactlyOneDiaperAndSurvivesReload() throws {
        let (store, child, target) = try setup()
        for action in [WidgetQuickAction.pee, .poo, .both] {
            let command = UUID()
            try store.recordWidgetDiaper(target: target, action: action, commandID: command)
            try store.recordWidgetDiaper(target: target, action: action, commandID: command)
        }
        let reopened = LogStore(persistence: store.persistence, defaults: store.defaults, publishesWidgets: false)
        #expect(reopened.snapshot.activities.count == 3)
        let summary = ActivitySummary(activities: reopened.snapshot.activities, childID: child.id, end: .now)
        #expect(summary.changes == 3 && summary.wet == 2 && summary.soiled == 2)
        #expect(reopened.snapshot.activities.allSatisfy { $0.source == "Lock Screen" && $0.authorID == store.caregiverID })
    }

    @Test func undoTargetsItsOwnEntryAndLateRetriesCannotResurrectIt() throws {
        let (store, child, target) = try setup()
        let command = UUID()
        try store.recordWidgetDiaper(target: target, action: .both, commandID: command)
        let other = Activity(familyID: child.familyID, childID: child.id, occurredAt: .now,
                             authorID: store.caregiverID, payload: .diaper(.init(pee: true, poo: false)))
        try store.save(.activity(other)) // Replaces the app's transient Undo state.
        let reopened = LogStore(persistence: store.persistence, defaults: store.defaults, publishesWidgets: false)
        try reopened.undoWidgetDiaper(target: target, action: .both, recordID: command)
        try reopened.undoWidgetDiaper(target: target, action: .both, recordID: command)
        try reopened.recordWidgetDiaper(target: target, action: .both, commandID: command)
        #expect(reopened.snapshot.activities == [other])
        #expect(reopened.snapshot.record(command)?.isDeleted == true)
        #expect(reopened.history(for: command).count == 2)
    }

    @Test func undoDoesNotDeleteEditedConflictedExpiredOrOtherPeoplesRecords() throws {
        let (store, _, target) = try setup()
        let editedID = UUID()
        try store.recordWidgetDiaper(target: target, action: .pee, commandID: editedID)
        var edited = try #require(store.snapshot.activities.first)
        edited.note = "Updated by a caregiver"
        try store.save(.activity(edited))
        #expect(throws: LogError.self) { try store.undoWidgetDiaper(target: target, action: .pee, recordID: editedID) }
        let expiredID = UUID()
        try store.recordWidgetDiaper(target: target, action: .poo, commandID: expiredID, now: .now.addingTimeInterval(-61))
        #expect(throws: LogError.self) { try store.undoWidgetDiaper(target: target, action: .poo, recordID: expiredID) }
        let conflictID = UUID()
        try store.recordWidgetDiaper(target: target, action: .both, commandID: conflictID)
        let record = try #require(store.snapshot.record(conflictID))
        try store.save(record.revision.value, parentIDs: [])
        #expect(throws: LogError.self) { try store.undoWidgetDiaper(target: target, action: .both, recordID: conflictID) }
        let person = Caregiver(familyID: edited.familyID, name: "Alex", isMother: false)
        try store.save(.caregiver(person))
        store.defaults.set(person.id.uuidString, forKey: "caregiverID")
        #expect(throws: LogError.self) { try store.undoWidgetDiaper(target: target, action: .pee, recordID: editedID) }
        #expect(store.snapshot.activities.count == 3)
    }

    @Test func childSelectionPermissionsAndBottleNavigationCannotSilentlyLog() throws {
        let (store, child, target) = try setup()
        let sibling = ChildProfile(familyID: child.familyID, name: "Jamie")
        try store.save(.child(sibling))
        store.selectedChildID = sibling.id
        try store.recordWidgetDiaper(target: target, action: .pee, commandID: UUID())
        #expect(store.snapshot.activities.first?.childID == child.id)
        for invalid in ["", "\(UUID())/\(child.id)", "\(child.familyID)/\(UUID())", target + "/extra"] {
            #expect(throws: LogError.self) { try store.recordWidgetDiaper(target: invalid, action: .pee, commandID: UUID()) }
        }
        for (ready, canEdit) in [(false, true), (true, false)] {
            #expect(throws: LogError.self) {
                try WidgetQuickLogRules.child(target: target, in: store.snapshot, ready: ready, canEdit: canEdit, actorID: store.caregiverID)
            }
        }
        #expect(throws: LogError.self) {
            try WidgetQuickLogRules.child(target: target, in: store.snapshot, ready: true, canEdit: true, actorID: UUID())
        }
        #expect(throws: LogError.self) { try store.recordWidgetDiaper(target: target, action: .bottle, commandID: UUID()) }
        let url = try #require(URL(string: "littlelog://bottle?family=\(child.familyID)&child=\(child.id)"))
        #expect(try LogDestination.resolve(url, in: store.snapshot, ready: true) == .bottle(childID: child.id))
        #expect(store.snapshot.activities.count == 1)
        try store.delete(try #require(store.snapshot.record(child.id)))
        #expect(throws: LogError.self) { try store.recordWidgetDiaper(target: target, action: .both, commandID: UUID()) }
        #expect(throws: LogError.self) { try LogDestination.resolve(url, in: store.snapshot, ready: true) }
    }

    @Test func launchLinksSaveAfterReloadShowConfirmationAndUndoExactlyOnce() throws {
        let (store, child, target) = try setup()
        let key = Data(repeating: 43, count: 32)
        for action in [WidgetQuickAction.pee, .poo, .both] {
            let request = WidgetQuickLogCommand(target: target, actorID: store.caregiverID, action: action,
                commandID: UUID(), issuedAt: .now)
            let url = try request.url(signingKey: key)
            let reopened = LogStore(persistence: store.persistence, defaults: store.defaults, publishesWidgets: false)
            #expect(try reopened.openWidgetDiaper(url, signingKey: key) == child.id)
            try reopened.openWidgetDiaper(url, signingKey: key)
            #expect(reopened.snapshot.activities.count == 1)
            #expect(reopened.snapshot.activities.first?.payload == .diaper(action.diaper!))
            #expect(reopened.toast == "\(action.diaper!.title) saved for Robin")
            #expect(reopened.undoID == request.commandID)
            try reopened.undo()
            try reopened.openWidgetDiaper(url, signingKey: key)
            #expect(reopened.snapshot.activities.isEmpty)
            #expect(reopened.undoID == nil)
            #expect(reopened.toast == "This entry was already undone")
        }
    }

    @Test func launchLinksRejectTamperingChangedCaregiverAndDeletedChildBeforeWriting() throws {
        let (store, child, target) = try setup()
        let key = Data(repeating: 43, count: 32)
        let request = WidgetQuickLogCommand(target: target, actorID: store.caregiverID, action: .both,
            commandID: UUID(), issuedAt: .now)
        let url = try request.url(signingKey: key)
        #expect(throws: LogError.self) { try store.openWidgetDiaper(url, signingKey: Data(repeating: 44, count: 32)) }
        var otherActor = request
        otherActor.actorID = UUID()
        #expect(throws: LogError.self) { try store.openWidgetDiaper(otherActor.url(signingKey: key), signingKey: key) }
        try store.delete(try #require(store.snapshot.record(child.id)))
        #expect(throws: LogError.self) { try store.openWidgetDiaper(url, signingKey: key) }
        #expect(store.snapshot.activities.isEmpty)
    }

    @Test func foregroundUndoProtectsAnEditArrivingAfterWidgetSave() throws {
        let (store, _, target) = try setup()
        let key = Data(repeating: 43, count: 32)
        let request = WidgetQuickLogCommand(target: target, actorID: store.caregiverID, action: .poo,
            commandID: UUID(), issuedAt: .now)
        try store.openWidgetDiaper(request.url(signingKey: key), signingKey: key)
        let otherStore = LogStore(persistence: store.persistence, defaults: store.defaults, publishesWidgets: false)
        var activity = try #require(otherStore.snapshot.activities.first)
        activity.note = "Caregiver corrected the note"
        try otherStore.save(.activity(activity))
        #expect(throws: LogError.self) { try store.undo() }
        #expect(store.snapshot.activities.first?.note == activity.note)
        var undo = request
        undo.undo = true
        #expect(throws: LogError.self) { try store.openWidgetDiaper(undo.url(signingKey: key), signingKey: key) }
        #expect(store.snapshot.activities.count == 1)
    }

    @Test func homeScreenActionsFromOneTimelineSaveIndependentlyAndUndoAfterReload() throws {
        let (store, child, target) = try setup()
        let key = Data(repeating: 53, count: 32)
        let links = WidgetQuickLogCommand.links(target: target, actorID: store.caregiverID, source: .homeScreen,
                                                receipts: [:], signingKey: key, at: .now)
        for action in [WidgetQuickAction.pee, .poo, .both] {
            let url = try #require(links[action])
            try store.openWidgetDiaper(url, signingKey: key)
            try store.openWidgetDiaper(url, signingKey: key)
        }
        let reopened = LogStore(persistence: store.persistence, defaults: store.defaults, publishesWidgets: false)
        let summary = ActivitySummary(activities: reopened.snapshot.activities, childID: child.id, end: .now)
        #expect(summary.changes == 3 && summary.wet == 2 && summary.soiled == 2)
        #expect(reopened.snapshot.activities.allSatisfy { $0.source == "Home Screen" && $0.authorID == store.caregiverID })
        let both = try WidgetQuickLogCommand.resolve(try #require(links[.both]), signingKey: key)
        let record = try #require(reopened.snapshot.record(both.commandID))
        let receipt = try #require(WidgetQuickLogRules.receipt(for: record, actorID: store.caregiverID))
        // Undo may come from the other widget surface, but still targets this exact record.
        let undoLinks = WidgetQuickLogCommand.links(target: target, actorID: store.caregiverID, source: .lockScreen,
            receipts: ["both": receipt], signingKey: key, at: .now)
        try reopened.openWidgetDiaper(try #require(undoLinks[.both]), signingKey: key)
        try reopened.openWidgetDiaper(try #require(links[.both]), signingKey: key)
        #expect(reopened.snapshot.activities.count == 2)
        #expect(reopened.snapshot.record(both.commandID)?.isDeleted == true)
    }

    @Test func careWidgetPumpingTotalsFollowSavedEditsAndDeletions() throws {
        let (store, child, _) = try setup()
        let pumper = Caregiver(familyID: child.familyID, name: "Alex", isMother: true)
        try store.save(.caregiver(pumper))
        var pump = PumpSession(familyID: child.familyID, motherID: pumper.id,
            occurredAt: .now.addingTimeInterval(-600), authorID: store.caregiverID,
            totalML: 180, leftML: 90, rightML: 90, unit: .ml)
        try store.save(.pumping(pump))
        func readSummary(_ source: LogStore) throws -> WidgetCareSummary {
            let cache = WidgetSnapshot.capture(source.snapshot, actorID: source.caregiverID,
                canRecord: source.canEdit, at: .now)
            let reopened = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(cache))
            return WidgetCareSummary(child: try #require(reopened.children.first), pumps: reopened.pumps, at: .now)
        }
        #expect(try readSummary(store).pumpedML == 180)
        #expect(try readSummary(store).activity.totalML == 0)
        pump.totalML = 210; pump.leftML = 105; pump.rightML = 105
        try store.save(.pumping(pump))
        let reopened = LogStore(persistence: store.persistence, defaults: store.defaults, publishesWidgets: false)
        #expect(try readSummary(reopened).pumpedML == 210)
        #expect(try readSummary(reopened).pumpingSessions == 1)
        try reopened.delete(try #require(reopened.snapshot.record(pump.id)))
        #expect(try readSummary(reopened).pumpedML == 0)
        #expect(try readSummary(reopened).pumpingSessions == 0)
    }
}
