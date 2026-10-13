import AppIntents
import SwiftUI
import WidgetKit

/// Shared presentation rules keep each action's label and destination in agreement.
struct QuickLogControl {
    let action: WidgetQuickAction
    let entry: QuickLogEntry

    var receipt: WidgetQuickLogReceipt? {
        entry.child?.quickLogs?[action.rawValue].flatMap { $0.canUndo(at: entry.date) ? $0 : nil }
    }
    var failure: String? {
        guard let child = entry.child else { return nil }
        return WidgetCache.quickLogFailure(target: "\(child.familyID)/\(child.id)", action: action.rawValue)
    }
    var isReady: Bool {
        entry.isPreview || (entry.child != nil && entry.canRecord && failure == nil &&
                           (action == .bottle || entry.actionURLs[action] != nil))
    }
    var isUndo: Bool { !entry.isPreview && isReady && receipt != nil }
    var title: String { isUndo ? String(localized: "Undo \(action.title)") : action.title }
    var detail: String {
        if entry.isPreview { return action == .bottle ? String(localized: "Review & save") : String(localized: "Log now") }
        if entry.child == nil { return String(localized: "Choose a child") }
        if !isReady { return String(localized: "Open Swaddle") }
        if isUndo { return String(localized: "Just saved") }
        return action == .bottle ? String(localized: "Review & save") : String(localized: "Log now")
    }
    var destination: URL {
        guard entry.child != nil else { return url(host: "family") }
        if failure != nil { return url(host: "today", failed: true) }
        guard entry.canRecord else { return url(host: "today") }
        if action == .bottle { return url(host: "bottle") }
        return entry.actionURLs[action] ?? url(host: "today")
    }
    var statusSymbol: String? {
        if !isReady { return entry.child == nil ? "gearshape" : "exclamationmark.circle" }
        return isUndo ? "arrow.uturn.backward" : nil
    }
    func accessibilityLabel(child: String) -> String {
        if !isReady { return String(localized: "\(action.title). \(detail)") }
        if isUndo { return String(localized: "\(action.title) saved for \(child). Undo this entry") }
        return String(localized: "Record \(action == .both ? String(localized: "pee and poo") : action.title.lowercased()) for \(child)")
    }
    var accessibilityHint: String {
        if !isReady { return String(localized: "Opens Swaddle to check setup and family access.") }
        if isUndo { return String(localized: "Opens Swaddle and removes only the entry just saved.") }
        return action == .bottle ? String(localized: "Opens the previous amounts for review. Tap Save to record the bottle.")
            : String(localized: "Opens Swaddle and saves one diaper change now, with Undo.")
    }
    func url(host: String, failed: Bool = false) -> URL {
        var parts = URLComponents()
        parts.scheme = "littlelog"
        parts.host = host
        if let child = entry.child {
            parts.queryItems = [.init(name: "family", value: child.familyID.uuidString),
                                .init(name: "child", value: child.id.uuidString)]
        }
        if failed { parts.queryItems?.append(.init(name: "widgetError", value: action.rawValue)) }
        return parts.url!
    }
}

struct QuickLogSymbol: View {
    let action: WidgetQuickAction
    var status: String? = nil
    var body: some View {
        Group {
            if let status { Image(systemName: status) }
            else {
                switch action {
                case .pee: Image(systemName: "drop.fill")
                case .poo: Image(systemName: "circle.hexagongrid.fill")
                case .both:
                    HStack(spacing: 2) {
                        Image(systemName: "drop.fill")
                        Image(systemName: "circle.hexagongrid.fill")
                    }
                case .bottle: Image(systemName: "waterbottle.fill")
                }
            }
        }.accessibilityHidden(true)
    }
}

struct HomeQuickLogSingleView: View {
    let action: WidgetQuickAction
    let entry: QuickLogEntry
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.redactionReasons) private var redactionReasons
    private var control: QuickLogControl { .init(action: action, entry: entry) }
    private var palette: BabyPalette { .init(gender: entry.child?.gender) }
    private var childName: String { redactionReasons.contains(.privacy) ? String(localized: "your child") : entry.child?.name ?? String(localized: "Your child") }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(childName).font(.caption.weight(.semibold)).lineLimit(1).privacySensitive()
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.forward").font(.caption2).accessibilityHidden(true)
            }.foregroundStyle(.secondary)
            Spacer(minLength: 2)
            QuickLogSymbol(action: action, status: control.statusSymbol)
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .foregroundStyle(renderingMode == .fullColor ? palette.accent : .primary)
                .widgetAccentable()
            Spacer(minLength: 2)
            Text(control.title).font(.system(.title3, design: .rounded, weight: .bold))
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(control.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(control.accessibilityLabel(child: childName))
        .accessibilityHint(control.accessibilityHint)
        .accessibilityAddTraits(.isButton)
    }
}

struct HomeQuickLogView: View {
    let entry: QuickLogEntry
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.redactionReasons) private var redactionReasons
    private var palette: BabyPalette { .init(gender: entry.child?.gender) }
    private var childName: String { redactionReasons.contains(.privacy) ? String(localized: "Your child") : entry.child?.name ?? String(localized: "Your child") }
    private var fallback: URL { QuickLogControl(action: .bottle, entry: entry).url(host: entry.child == nil ? "family" : "today") }
    private var guidance: String {
        if entry.isPreview { return String(localized: "Diapers save now · Bottle opens editor") }
        if entry.child == nil { return String(localized: "Choose a child in Edit Widget") }
        if !entry.canRecord { return String(localized: "Open Swaddle to check family access") }
        if WidgetQuickAction.allCases.contains(where: { !QuickLogControl(action: $0, entry: entry).isReady }) {
            return String(localized: "Open Swaddle to refresh your actions")
        }
        return String(localized: "Diapers save now · Bottle opens editor")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(childName).font(.headline).lineLimit(1).privacySensitive().layoutPriority(1)
                Spacer(minLength: 8)
                Text("Quick log").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 8) {
                ForEach(WidgetQuickAction.allCases, id: \.self) { action in
                    let control = QuickLogControl(action: action, entry: entry)
                    Link(destination: control.destination) {
                        VStack(spacing: 6) {
                            QuickLogSymbol(action: action, status: control.statusSymbol)
                                .font(.system(.title3, design: .rounded, weight: .semibold)).widgetAccentable()
                            Text(control.title).font(.system(.caption, design: .rounded, weight: .semibold))
                                .lineLimit(1).minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .frame(minHeight: 44)
                        .padding(.vertical, 6)
                        .foregroundStyle(renderingMode == .fullColor ? palette.accent : .primary)
                        .background {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(renderingMode == .fullColor ? palette.surface : Color.primary.opacity(0.12))
                        }
                        .contentShape(.rect(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(control.accessibilityLabel(child: childName))
                    .accessibilityHint(control.accessibilityHint)
                }
            }
            Text(guidance)
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .containerBackground(for: .widget) { Color(uiColor: .secondarySystemGroupedBackground) }
        // The background only opens the log. Only a clearly labeled action may save a diaper.
        .widgetURL(fallback)
    }
}

struct HomeQuickLogWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SwaddleHomeQuickLog", intent: SelectChildIntent.self, provider: QuickLogProvider()) { entry in
            HomeQuickLogView(entry: entry)
        }
        .configurationDisplayName("Quick log")
        .description("Pee, Poo, Both, and Bottle in one row. Diapers open Swaddle and save with Undo; Bottle opens its editor.")
        .supportedFamilies([.systemMedium])
    }
}

#Preview("Home quick log", as: .systemMedium) { HomeQuickLogWidget() } timeline: {
    QuickLogEntry(date: .now, child: CachedChild(id: UUID(), familyID: UUID(), name: "Casey", activities: [], gender: .boy),
                  canRecord: true, isPreview: true)
}
#Preview("Home bottle", as: .systemSmall) { BottleLockScreenWidget() } timeline: {
    QuickLogEntry(date: .now, child: CachedChild(id: UUID(), familyID: UUID(), name: "Casey", activities: [], gender: .boy),
                  canRecord: true, isPreview: true)
}
