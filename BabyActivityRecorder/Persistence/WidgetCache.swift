import Foundation
import CryptoKit
import WidgetKit

enum WidgetCache {
    static let appGroup = "group.com.github.fkorotkov.LittleLog"
    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }
    static var unit: VolumeUnit { VolumeUnit(rawValue: defaults.string(forKey: "widgetVolumeUnit") ?? "ml") ?? .ml }
    static var url: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appending(path: "widget-snapshot.json") }
    private static var signingKeyURL: URL? { url?.deletingLastPathComponent().appending(path: "widget-quick-log.key") }
    static var signingKey: Data? {
        guard let url = signingKeyURL, let key = try? Data(contentsOf: url), key.count == 32 else { return nil }
        return key
    }
    static func setUnit(_ unit: VolumeUnit) {
        defaults.set(unit.rawValue, forKey: "widgetVolumeUnit")
        WidgetCenter.shared.reloadAllTimelines()
    }
    static func read() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
    static func write(snapshot: FamilySnapshot, actorID: UUID? = nil, canRecord: Bool = false) {
        guard let url else { return }
        #if !WIDGET_EXTENSION
        // The main app is the only key writer; the widget reads it when constructing a link.
        if signingKey == nil, let keyURL = signingKeyURL {
            let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            try? key.write(to: keyURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        #endif
        let now = Date.now
        let cached = WidgetSnapshot.capture(snapshot, actorID: actorID, canRecord: canRecord, at: now)
        do {
            try JSONEncoder().encode(cached).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // The primary transaction remains saved; widgets keep the last complete snapshot.
        }
    }

    private static func failureKey(target: String, action: String) -> String { "widgetFailure.\(target).\(action)" }
    static func quickLogFailure(target: String, action: String) -> String? {
        let key = failureKey(target: target, action: action)
        guard let date = defaults.object(forKey: key + ".date") as? Date,
              date > Date.now.addingTimeInterval(-300) else { return nil }
        return defaults.string(forKey: key)
    }
    static func setQuickLogFailure(_ message: String?, target: String, action: String) {
        let key = failureKey(target: target, action: action)
        defaults.set(message, forKey: key)
        defaults.set(message == nil ? nil : Date.now, forKey: key + ".date")
        WidgetCenter.shared.reloadAllTimelines()
    }
}
