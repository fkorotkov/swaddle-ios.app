import CryptoKit
import Foundation

/// A device-local capability. A plain, externally constructed URL must never add care records.
struct WidgetQuickLogCommand: Codable, Equatable, Sendable {
    var version = 1
    var target: String
    var actorID: UUID
    var action: WidgetQuickAction
    var commandID: UUID
    var undo = false
    var issuedAt: Date
    // Absent in existing Lock Screen links. This does not change the care-record format.
    var source: WidgetQuickLogSource? = nil

    var recordingSource: WidgetQuickLogSource { source ?? .lockScreen }

    static func links(target: String, actorID: UUID, source: WidgetQuickLogSource,
                      receipts: [String: WidgetQuickLogReceipt], signingKey: Data, at date: Date) -> [WidgetQuickAction: URL] {
        var links: [WidgetQuickAction: URL] = [:]
        for action in WidgetQuickAction.allCases where action.diaper != nil {
            let receipt = receipts[action.rawValue].flatMap { $0.canUndo(at: date) ? $0 : nil }
            // Each button needs its own identity: tapping another action before WidgetKit
            // refreshes must never reuse the first action's idempotency key.
            let command = Self(target: target, actorID: actorID, action: action,
                               commandID: receipt?.recordID ?? UUID(), undo: receipt != nil,
                               issuedAt: date, source: source)
            links[action] = try? command.url(signingKey: signingKey)
        }
        return links
    }

    func url(signingKey: Data) throws -> URL {
        let payload = try JSONEncoder().encode(self)
        let signature = Data(HMAC<SHA256>.authenticationCode(for: payload, using: SymmetricKey(data: signingKey)))
        var components = URLComponents()
        components.scheme = "littlelog"
        components.host = "widget-diaper"
        components.queryItems = [
            .init(name: "payload", value: payload.base64EncodedString()),
            .init(name: "signature", value: signature.base64EncodedString()),
        ]
        guard let url = components.url else { throw Self.invalidLink }
        return url
    }

    static func resolve(_ url: URL, signingKey: Data, now: Date = .now) throws -> Self {
        guard signingKey.count == 32, url.absoluteString.count < 4096,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "littlelog", components.host == "widget-diaper",
              components.user == nil, components.password == nil, components.port == nil,
              components.path.isEmpty, components.fragment == nil,
              let items = components.queryItems, items.count == 2,
              Set(items.map(\.name)) == ["payload", "signature"],
              let encoded = items.first(where: { $0.name == "payload" })?.value,
              let payload = Data(base64Encoded: encoded),
              let signed = items.first(where: { $0.name == "signature" })?.value,
              let signature = Data(base64Encoded: signed),
              HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: payload,
                                                     using: SymmetricKey(data: signingKey)) else { throw invalidLink }
        let command = try JSONDecoder().decode(Self.self, from: payload)
        guard command.version == 1, command.action.diaper != nil,
              command.issuedAt <= now.addingTimeInterval(60),
              command.issuedAt > now.addingTimeInterval(-7 * 86400) else { throw invalidLink }
        return command
    }

    static var invalidLink: LogError {
        .message(String(localized: "This widget needs to refresh. Return to your widget and tap it again."))
    }
}
