import Foundation
import Testing
@testable import LittleLogCore

struct WidgetQuickLogLinkTests {
    let key = Data(repeating: 37, count: 32)
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    func command(action: WidgetQuickAction = .both, undo: Bool = false) -> WidgetQuickLogCommand {
        .init(target: "\(UUID())/\(UUID())", actorID: UUID(), action: action,
              commandID: UUID(), undo: undo, issuedAt: now)
    }

    @Test func roundTripsEveryDiaperAndUndoWithItsExactIdentity() throws {
        for action in [WidgetQuickAction.pee, .poo, .both] {
            for undo in [false, true] {
                let request = command(action: action, undo: undo)
                #expect(try WidgetQuickLogCommand.resolve(request.url(signingKey: key), signingKey: key, now: now) == request)
            }
        }
    }

    @Test func rejectsForgedLinksAndAnotherDevicesKey() throws {
        let request = command()
        let url = try request.url(signingKey: key)
        #expect(throws: LogError.self) {
            try WidgetQuickLogCommand.resolve(url, signingKey: Data(repeating: 38, count: 32), now: now)
        }
        var parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        var changed = request
        changed.action = .pee
        parts.queryItems?[0].value = try JSONEncoder().encode(changed).base64EncodedString()
        #expect(throws: LogError.self) { try WidgetQuickLogCommand.resolve(try #require(parts.url), signingKey: key, now: now) }
    }

    @Test func rejectsAmbiguousRoutesVersionsAndAmounts() throws {
        let request = command()
        let url = try request.url(signingKey: key)
        var parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let duplicate = try #require(parts.queryItems?.first)
        parts.queryItems?.append(duplicate)
        #expect(throws: LogError.self) { try WidgetQuickLogCommand.resolve(try #require(parts.url), signingKey: key, now: now) }
        for invalid in [url.absoluteString + "#extra", url.absoluteString.replacingOccurrences(of: "widget-diaper?", with: "today?")] {
            #expect(throws: LogError.self) { try WidgetQuickLogCommand.resolve(try #require(URL(string: invalid)), signingKey: key, now: now) }
        }
        var unsupported = request
        unsupported.version = 2
        #expect(throws: LogError.self) { try WidgetQuickLogCommand.resolve(unsupported.url(signingKey: key), signingKey: key, now: now) }
        #expect(throws: LogError.self) { try WidgetQuickLogCommand.resolve(command(action: .bottle).url(signingKey: key), signingKey: key, now: now) }
    }

    @Test func staleAndFutureCommandsRequireRefresh() throws {
        let url = try command().url(signingKey: key)
        for time in [now.addingTimeInterval(7 * 86400), now.addingTimeInterval(-61)] {
            #expect(throws: LogError.self) { try WidgetQuickLogCommand.resolve(url, signingKey: key, now: time) }
        }
        #expect(try WidgetQuickLogCommand.resolve(url, signingKey: key, now: now.addingTimeInterval(900)).action == .both)
    }

    @Test func oldWidgetSnapshotsStillDecode() throws {
        let original = WidgetSnapshot(asOf: now, children: [], canRecord: true)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(original))
        #expect(decoded.actorID == nil && decoded.canRecord == true)
    }

    @Test func fourActionWidgetUsesIndependentCommandIdentities() throws {
        let target = "\(UUID())/\(UUID())"
        let actor = UUID()
        let links = WidgetQuickLogCommand.links(target: target, actorID: actor, source: .homeScreen,
                                                receipts: [:], signingKey: key, at: now)
        let commands = try links.values.map { try WidgetQuickLogCommand.resolve($0, signingKey: key, now: now) }
        #expect(commands.count == 3)
        #expect(Set(commands.map(\.commandID)).count == 3)
        #expect(Set(commands.map(\.action)) == [.pee, .poo, .both])
        #expect(commands.allSatisfy { $0.target == target && $0.actorID == actor && $0.recordingSource == .homeScreen && !$0.undo })
        #expect(links[.bottle] == nil) // Bottle is navigation, never a write command.
    }

    @Test func eachActionKeepsOnlyItsOwnUnexpiredUndoReceipt() throws {
        let active = WidgetQuickLogReceipt(recordID: UUID(), createdAt: now.addingTimeInterval(-20))
        let expired = WidgetQuickLogReceipt(recordID: UUID(), createdAt: now.addingTimeInterval(-60))
        let links = WidgetQuickLogCommand.links(target: "\(UUID())/\(UUID())", actorID: UUID(), source: .homeScreen,
            receipts: ["pee": active, "poo": expired], signingKey: key, at: now)
        let pee = try WidgetQuickLogCommand.resolve(try #require(links[.pee]), signingKey: key, now: now)
        let poo = try WidgetQuickLogCommand.resolve(try #require(links[.poo]), signingKey: key, now: now)
        let both = try WidgetQuickLogCommand.resolve(try #require(links[.both]), signingKey: key, now: now)
        #expect(pee.undo && pee.commandID == active.recordID)
        #expect(!poo.undo && poo.commandID != expired.recordID)
        #expect(!both.undo && both.commandID != active.recordID)
        let legacy = try WidgetQuickLogCommand.resolve(command().url(signingKey: key), signingKey: key, now: now)
        #expect(legacy.source == nil && legacy.recordingSource == .lockScreen)
    }
}
